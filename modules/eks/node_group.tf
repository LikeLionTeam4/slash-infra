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

  iam_instance_profile {
    arn = aws_iam_instance_profile.node.arn
  }

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

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_iam_role_policy_attachment.node_ssm,
  ]
}
