data "aws_region" "current" {}

locals {
  public_subnets      = { for idx, az in var.azs : az => var.public_subnet_cidrs[idx] }
  private_app_subnets = { for idx, az in var.azs : az => var.private_app_subnet_cidrs[idx] }
  private_db_subnets  = { for idx, az in var.azs : az => var.private_db_subnet_cidrs[idx] }

  # 비용형(NAT 1개)일 땐 첫 AZ에만 EIP/NAT를 만들고, 나머지 AZ의 private-app 라우트도 그 NAT를 공유한다.
  nat_azs = var.nat_gateway_per_az ? var.azs : [var.azs[0]]
}

# ---- VPC ----

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc-${var.environment}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw-${var.environment}"
  })
}

# ---- Subnets (3-tier: public / private-app / private-db) ----

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${each.key}-${var.environment}"
    Tier = "public"
  })
}

resource "aws_subnet" "private_app" {
  for_each = local.private_app_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${each.key}-${var.environment}"
    Tier = "private-app"
  })
}

resource "aws_subnet" "private_db" {
  for_each = local.private_db_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-${each.key}-${var.environment}"
    Tier = "private-db"
  })
}

# ---- NAT (AZ당 1개, nat_gateway_per_az=false면 첫 AZ에만) ----

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${each.key}-${var.environment}"
  })
}

resource "aws_nat_gateway" "main" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${each.key}-${var.environment}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ---- Route tables: public (공유 1개) ----

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt-${var.environment}"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---- Route tables: private-app (AZ당, NAT로 아웃바운드) ----

resource "aws_route_table" "private_app" {
  for_each = local.private_app_subnets

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-rt-${each.key}-${var.environment}"
  })
}

resource "aws_route" "private_app_nat" {
  for_each = local.private_app_subnets

  route_table_id         = aws_route_table.private_app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_per_az ? aws_nat_gateway.main[each.key].id : aws_nat_gateway.main[local.nat_azs[0]].id
}

resource "aws_route_table_association" "private_app" {
  for_each = aws_subnet.private_app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app[each.key].id
}

# ---- Route tables: private-db (AZ당, 인터넷 기본 경로 없음 — S3 Gateway Endpoint만 연결) ----

resource "aws_route_table" "private_db" {
  for_each = local.private_db_subnets

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-rt-${each.key}-${var.environment}"
  })
}

resource "aws_route_table_association" "private_db" {
  for_each = aws_subnet.private_db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db[each.key].id
}

# ---- S3 Gateway Endpoint — private 서브넷이 NAT 없이 S3에 접근 (private-db는 이것이 유일한 외부 경로) ----

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private_app : rt.id],
    [for rt in aws_route_table.private_db : rt.id],
  )

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-s3-endpoint-${var.environment}"
  })
}

# ---- Security groups: EKS / DB ----

resource "aws_security_group" "eks" {
  name        = "${var.name_prefix}-eks-sg-${var.environment}"
  description = "EKS 노드/파드 baseline SG — 실제 클러스터 생성 시 EKS가 만드는 SG와 별개로 네트워크 계층에서 미리 준비"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-sg-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_self" {
  security_group_id            = aws_security_group.eks.id
  referenced_security_group_id = aws_security_group.eks.id
  ip_protocol                  = "-1"
  description                  = "같은 SG 멤버 간 전체 트래픽 허용 (노드-노드, 컨트롤플레인-노드)"
}

resource "aws_vpc_security_group_egress_rule" "eks_all" {
  security_group_id = aws_security_group.eks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "전체 아웃바운드 허용"
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg-${var.environment}"
  description = "RDS(PostgreSQL) / Valkey — 인바운드는 EKS SG에서만"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-sg-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.eks.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "EKS SG로부터 PostgreSQL"
}

resource "aws_vpc_security_group_ingress_rule" "db_valkey" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.eks.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "EKS SG로부터 Valkey"
}

resource "aws_vpc_security_group_egress_rule" "db_all" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "전체 아웃바운드 허용 (패치 등)"
}
