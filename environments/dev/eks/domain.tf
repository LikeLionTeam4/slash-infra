# api.dev.sbsh.cloud용 ACM 인증서 + DNS 검증.
#
# environments/bootstrap의 state는 로컬로만 관리돼서(§3, state 버킷을 만드는 그 순간엔
# 아직 참조할 backend가 없는 닭-달걀 문제) terraform_remote_state로 못 끌어온다 — ECR URL을
# Helm values에 정적 값으로 넣는 것과 같은 이유로(§6), zone_id를 정적 값으로 직접 쓴다.
locals {
  route53_zone_id = "Z03858108FMADVU36PUA" # bootstrap output route53_zone_id (sbsh.cloud)
}

resource "aws_acm_certificate" "api" {
  domain_name       = "api.dev.sbsh.cloud"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.route53_zone_id
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}
