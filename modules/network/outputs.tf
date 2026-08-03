output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "AZ => public 서브넷 ID"
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_app_subnet_ids" {
  description = "AZ => private-app(EKS) 서브넷 ID"
  value       = { for az, s in aws_subnet.private_app : az => s.id }
}

output "private_db_subnet_ids" {
  description = "AZ => private-db(RDS/Valkey) 서브넷 ID"
  value       = { for az, s in aws_subnet.private_db : az => s.id }
}

output "private_db_subnet_group_subnet_ids" {
  description = "aws_db_subnet_group / aws_elasticache_subnet_group에 바로 넘길 수 있는 private-db 서브넷 ID 목록"
  value       = [for s in aws_subnet.private_db : s.id]
}

output "eks_security_group_id" {
  description = "EKS 노드/파드용 baseline 보안그룹 ID"
  value       = aws_security_group.eks.id
}

output "db_security_group_id" {
  description = "RDS/Valkey용 보안그룹 ID (EKS SG에서만 인바운드 허용)"
  value       = aws_security_group.db.id
}

output "nat_gateway_ids" {
  description = "AZ => NAT Gateway ID (nat_gateway_per_az=false면 첫 AZ 1개만)"
  value       = { for az, ngw in aws_nat_gateway.main : az => ngw.id }
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "flow_log_bucket_name" {
  description = "VPC Flow Log가 쌓이는 S3 버킷 이름"
  value       = aws_s3_bucket.flow_logs.id
}
