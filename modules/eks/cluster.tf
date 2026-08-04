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

  # 버전을 명시하지 않으면 AWS가 그 시점의 최신 지원 버전으로 생성한다 —
  # 특정 버전에 묶여 문서를 계속 갱신하지 않아도 되게.

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-${var.environment}"
  })

  depends_on = [aws_iam_role_policy_attachment.cluster_eks_policy]
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
