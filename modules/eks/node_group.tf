# ---- 노드 IAM Role ----
# 노드 자체에는 최소 권한만 준다 (§4 원칙 — 앱이 필요한 AWS 리소스 접근은 IRSA로 별도 부여).

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSH 키 없이 세션 매니저(SSM)로 노드에 접속하기 위해.
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name_prefix}-eks-node-${var.environment}"
  role = aws_iam_role.node.name
}

# ---- Launch Template ----
# network가 만들어둔 eks_security_group_id(self-referencing 규칙 포함)를 명시적으로
# 붙이기 위해 EKS 노드그룹 기본 생성 SG 대신 launch template을 쓴다.

resource "aws_launch_template" "node" {
  name_prefix   = "${var.name_prefix}-eks-node-${var.environment}-"
  instance_type = var.node_instance_type

  vpc_security_group_ids = [var.eks_security_group_id]

  # EKS 관리형 노드그룹은 aws_eks_node_group.node_role_arn으로 인스턴스 프로필을
  # 자체 구성한다 — launch template에 iam_instance_profile을 지정하면 API가 거부한다
  # ("Launch template ... should not specify an instance profile").
  # aws_iam_instance_profile.node 자체는 outputs/karpenter.tf에서 계속 참조하므로 유지.

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-eks-node-${var.environment}"
    })
  }

  tags = var.tags
}

# ---- 범용 노드그룹 (EC2 3대 시작) ----

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-eks-general-${var.environment}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_app_subnet_ids

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  # schedule.tf의 EventBridge Scheduler가 UpdateNodegroupConfig로 desired/min/max를
  # 09~21시 밖에는 0으로 바꿔놓는다 — 그 상태에서 terraform apply가 돌면 이 블록의
  # 선언값(var.node_desired_size 등)으로 되돌리려는 drift가 감지되므로 무시한다.
  # 사이즈를 실제로 바꾸려면 이 lifecycle 블록을 잠깐 지우고 apply해야 한다.
  lifecycle {
    ignore_changes = [scaling_config]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_iam_role_policy_attachment.node_ssm,
  ]
}
