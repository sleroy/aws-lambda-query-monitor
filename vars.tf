#Define variables for secrets

variable "db_secret_id" {
  type      = string
  sensitive = true
  default = "arn:aws:secretsmanager:us-east-1:787156592790:secret:prod/sqlserver/target-9GLIFX"
}
