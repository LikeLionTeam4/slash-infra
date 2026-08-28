# [현재 미적용 모듈] 2026-08-25(PR #70)에 environments/dev/llm-runtime을 terraform
# destroy 해서 이 모듈이 만드는 자원은 지금 존재하지 않는다. 코드를 지우지 않은 것은
# terraform apply 한 번으로 복원 가능하게 두기 위해서다(모델 재다운로드까지
# user_data가 자동화). 되살리려면 slash-api의 SUMMARY_ENGINE=GEMMA 전환이 함께 필요하다.
#
# 제거 경위 — slash-docs#3에서 "핵심 가치는 클라우드에서 LLM을 직접 제공하는 것이
# 아니다"로 제품 방향이 확정되며 요약이 브라우저·PC·서버로 분산됐고, 서버 경로는
# slash-nlu의 CPU 추출 요약이 맡게 됐다. GPU 고정비 제거가 그 전환의 목적이었다.
#
# ---- 아래는 운용하던 당시의 설계 근거 ----
#
# Ollama(LLM 추론 런타임)를 돌리는 단독 EC2 — GPU 노드그룹(Karpenter/EKS) 대신 선택한
# 이유는 docs/aws-architecture.md §5-1 참고: 콜드스타트(0-scale마다 모델 재pull)와
# 비용($100 계정 전체 예산) 문제.
#
# stop/start(터미네이트 아님)로 운용하는 게 전제라, user_data는 최초 부팅 1회만
# 실행되도록 그대로 두고(AMI 자동 업데이트로 인한 교체도 lifecycle에서 막는다) EBS에
# 남은 설치 상태를 재사용한다.

data "aws_ssm_parameter" "dlami" {
  # x86_64 + NVIDIA 드라이버 내장 Deep Learning Base AMI — g4dn(T4)과 호환.
  # 별도 드라이버 설치 스크립트 없이 Ollama만 설치하면 되는 이유.
  name = "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-amazon-linux-2023/latest/ami-id"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ollama" {
  name               = "${var.name_prefix}-ollama-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# SSH 키 없이 세션 매니저(SSM)로 접속하기 위해 (modules/eks 노드와 동일한 이유).
resource "aws_iam_role_policy_attachment" "ollama_ssm" {
  role       = aws_iam_role.ollama.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ollama" {
  name = "${var.name_prefix}-ollama-${var.environment}"
  role = aws_iam_role.ollama.name
}

resource "aws_instance" "ollama" {
  ami                    = data.aws_ssm_parameter.dlami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ollama.name

  # Spot(2026-08-18, 비용 재검토) — On-demand 상시 가동은 월 ~$475인데, 평일
  # 업무시간만 켜두기로 하면서(schedule.tf) Spot까지 더하면 월 ~$60~85로 줄어든다.
  # interruption_behavior=stop이라 AWS가 용량을 회수해도 터미네이트가 아니라 정지 —
  # EBS의 설치 상태(모델 등)는 stop/start 때와 동일하게 보존된다. persistent가
  # 아니면 stop을 지정할 수 없다(AWS 제약).
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "stop"
        spot_instance_type             = "persistent"
      }
    }
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    ollama_model = var.ollama_model
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ollama-${var.environment}"
  })

  lifecycle {
    # SSM 파라미터가 "latest"라 AWS가 AMI를 갱신하면 plan에 새 AMI가 잡힌다 —
    # 그대로 두면 인스턴스가 교체되면서 EBS(=설치된 모델)가 날아가 stop/start로
    # 상태를 보존하려는 설계 의도가 깨진다. AMI 갱신은 명시적으로 재생성할 때만.
    ignore_changes = [ami]
  }
}
