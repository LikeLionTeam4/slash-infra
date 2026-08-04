# local/dev/prod 전체가 공유하는 루트 도메인. 서브도메인(local.sbsh.cloud, dev.sbsh.cloud)과
# apex(prod, sbsh.cloud)는 이 존 하나에서 각 환경의 frontend/network 모듈이 레코드만 추가한다.
resource "aws_route53_zone" "root" {
  name = "sbsh.cloud"
  tags = merge(local.tags, { Service = "dns" })
}
