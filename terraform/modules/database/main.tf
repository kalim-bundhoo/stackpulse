resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "db_subnets" {
  name       = "stackpulse-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "stackpulse-${var.environment}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier                = "stackpulse-${var.environment}-db"
  engine                    = "postgres"
  engine_version            = "15"
  instance_class            = var.instance_class
  allocated_storage         = 20
  max_allocated_storage     = 100
  db_name                   = "appdb"
  username                  = "dbadmin"
  password                  = random_password.db_password.result
  storage_encrypted         = true
  multi_az                  = var.multi_az
  db_subnet_group_name      = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids    = [var.db_sg_id]
  backup_retention_period   = 0
  skip_final_snapshot       = true

  tags = { Name = "stackpulse-${var.environment}-postgres" }
}

resource "aws_ssm_parameter" "db_password_param" {
  name        = "/stackpulse/${var.environment}/database_password"
  description = "Database password for ${var.environment}"
  type        = "SecureString"
  value       = random_password.db_password.result
}
