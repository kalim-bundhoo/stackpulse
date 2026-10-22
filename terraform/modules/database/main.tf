resource "aws_db_instance" "postgres" {
  identifier                 = "stackpulse-${var.environment}-db"
  engine                     = "postgres"
  engine_version             = "15"
  instance_class             = var.instance_class
  allocated_storage          = 20
  max_allocated_storage      = 100
  db_name                    = "appdb"
  username                   = "dbadmin"
  password                   = random_password.db_password.result
  storage_encrypted          = true
  multi_az                   = var.multi_az
  db_subnet_group_name       = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids     = [var.db_sg_id]
  
  backup_retention_period    = 7
  deletion_protection        = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "stackpulse-${var.environment}-db-final-snapshot"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true # <--- Fixes CKV2_AWS_60

  tags = { Name = "stackpulse-${var.environment}-postgres" }
}

resource "aws_ssm_parameter" "db_password_param" {
  name        = "/stackpulse/${var.environment}/database_password"
  description = "Database password for ${var.environment}"
  type        = "SecureString"
  value       = random_password.db_password.result
}
