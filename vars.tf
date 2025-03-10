#Define variables for secrets
variable "region" {
  type      = string
  default   = "us-east-1"
}
variable "account_id" {
  type      = string
  sensitive = true
  default   = "787156592790"
}

variable "db_secret_id" {
  type      = string
  sensitive = true
  default   = "arn:aws:secretsmanager:us-east-1:787156592790:secret:prod/sqlserver/target-9GLIFX"
}

variable "pip_path" {
  default = "python/.venv/bin/pip"
}

variable "vpc_name" {
  type= string
  default = "OnpremiseVPC"
}

variable "subnets" {
  type= list
  default = ["OnPremStack/OnpremiseVPC/private-subnetSubnet2", "OnPremStack/OnpremiseVPC/private-subnetSubnet1"]
}
