# vpc-cni는 클러스터 생성 시 self-managed로 자동 설치돼 지금까지 Terraform이
# 추적하지 않고 있었다(`aws eks list-addons` 결과 0개, 이슈 #45). NetworkPolicy
# 강제를 켜려면(enableNetworkPolicy) 관리형 add-on으로 편입해야 설정값을 코드로
# 남길 수 있다. 버전은 지금 self-managed로 이미 떠 있는 것과 동일한 값을 그대로
# 고정해서, 이 변경이 버전 업그레이드와 섞이지 않게 한다.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = "v1.22.4-eksbuild.3"

  # 이미 떠 있는 self-managed aws-node DaemonSet을 관리형이 덮어쓰고 인수받는다.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # NetworkPolicy를 "강제할 수 있는 능력"만 켠다 — 실제 정책(예: slash-llm을
  # slash-api에서만 접근 가능하게 제한)은 아직 하나도 없어 지금은 아무것도
  # 안 막는다. 정책 작성은 별도 결정 사항(이슈 #45 할 일 2번).
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = var.tags
}
