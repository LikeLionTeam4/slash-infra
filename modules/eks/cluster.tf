# ---- 클러스터 IAM Role ----

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---- EKS 클러스터 ----

resource "aws_eks_cluster" "main" {
  name     = "${var.name_prefix}-eks-${var.environment}"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_app_subnet_ids
    security_group_ids      = [var.eks_security_group_id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # CONFIG_MAP(구버전) 단독으로는 aws-auth ConfigMap을 kubectl로 직접 고칠 수 있는
  # 사람만 팀원 권한을 추가할 수 있어 닭과 달걀 문제가 생긴다(이슈 #63). API_AND_CONFIG_MAP은
  # 기존 CONFIG_MAP 동작을 그대로 유지한 채 aws_eks_access_entry로 코드 관리를 추가하는
  # 것뿐이라 되돌릴 수 없는 방향이어도 기존 접근을 끊지 않는다. AWS 정책상 API 단독 모드로는
  # 못 건너뛰고 이 모드를 거쳐야 한다.
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # 기존 클러스터의 실제 값(true)을 그대로 명시해야 한다 — 비워두면 Terraform이
    # "제거"로 해석해 클러스터 재생성을 유발한다(이 속성은 AWS provider에서 ForceNew).
    bootstrap_cluster_creator_admin_permissions = true
  }

  # audit/authenticator만 우선 활성화(이슈 #44) — "누가 클러스터 API에 접근했는지"
  # 감사 목적. api/controllerManager/scheduler는 지금 필요성이 낮아 비용상 보류.
  # aws_cloudwatch_log_group.eks_cluster를 먼저 만들어야 EKS가 무기한 보존으로
  # 로그 그룹을 자동 생성하는 걸 막을 수 있다(logging.tf 참고).
  enabled_cluster_log_types = ["audit", "authenticator"]

  # 버전을 명시하지 않으면 AWS가 그 시점의 최신 지원 버전으로 생성한다 —
  # 특정 버전에 묶여 문서를 계속 갱신하지 않아도 되게.

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-${var.environment}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

# ---- IRSA용 OIDC Provider ----
# 파드가 자기 ServiceAccount 신원으로 IAM Role을 빌려쓰려면(IRSA), 이 클러스터의
# OIDC 발급자를 IAM이 신뢰하도록 등록해야 한다. GitHub Actions용 OIDC provider(§9-1)와는
# 완전히 별개의 리소스.

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = var.tags
}
