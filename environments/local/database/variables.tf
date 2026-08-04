variable "private_db_subnet_ids" {
  description = "environments/local/network output의 private_db_subnet_ids 값들 (list로 넣는다)"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "environments/local/network output의 db_security_group_id"
  type        = string
}
