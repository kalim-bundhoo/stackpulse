#!/bin/bash
set -e

echo "🚀 Creating directory structure..."
mkdir -p modules/{vpc,security,storage,database,compute}
mkdir -p environments/{dev,staging,prod}

echo "📦 Creating VPC Module..."
cat << 'EOF' > modules/vpc/variables.tf
variable "environment" { type = string }
variable "vpc_cidr"     { type = string }
EOF

cat << 'EOF' > modules/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "stackpulse-${var.environment}-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "stackpulse-${var.environment}-igw" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags                    = { Name = "stackpulse-${var.environment}-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 4)
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags                    = { Name = "stackpulse-${var.environment}-public-2" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = "us-east-1a"
  tags              = { Name = "stackpulse-${var.environment}-private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = "us-east-1b"
  tags              = { Name = "stackpulse-${var.environment}-private-2" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "stackpulse-${var.environment}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "stackpulse-${var.environment}-nat-gw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "stackpulse-${var.environment}-public-rt" }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "stackpulse-${var.environment}-private-rt" }
}

resource "aws_route_table_association" "priv_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "priv_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
EOF

cat << 'EOF' > modules/vpc/outputs.tf
output "vpc_id"           { value = aws_vpc.main.id }
output "public_subnet_ids"  { value = [aws_subnet.public_1.id, aws_subnet.public_2.id] }
output "private_subnet_ids" { value = [aws_subnet.private_1.id, aws_subnet.private_2.id] }
EOF


echo "🔒 Creating Security Module..."
cat << 'EOF' > modules/security/variables.tf
variable "vpc_id" { type = string }
EOF

cat << 'EOF' > modules/security/main.tf
resource "aws_security_group" "alb_sg" {
  name        = "stackpulse-alb-sg"
  description = "Allow public HTTP"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "stackpulse-web-sg"
  description = "Allow ALB and SSH"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "stackpulse-db-sg"
  description = "Allow database access from web server"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
EOF

cat << 'EOF' > modules/security/outputs.tf
output "alb_sg_id" { value = aws_security_group.alb_sg.id }
output "web_sg_id" { value = aws_security_group.web_sg.id }
output "db_sg_id"  { value = aws_security_group.db_sg.id }
EOF


echo "🗄️ Creating Storage Module..."
cat << 'EOF' > modules/storage/variables.tf
variable "environment" { type = string }
EOF

cat << 'EOF' > modules/storage/main.tf
resource "aws_s3_bucket" "app_bucket" {
  bucket        = "stackpulse-app-storage-${var.environment}-551504153839"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
EOF

cat << 'EOF' > modules/storage/outputs.tf
output "bucket_name" { value = aws_s3_bucket.app_bucket.id }
EOF


echo "💾 Creating Database Module..."
cat << 'EOF' > modules/database/variables.tf
variable "environment"        { type = string }
variable "instance_class"     { type = string }
variable "multi_az"           { type = bool }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_sg_id"           { type = string }
EOF

cat << 'EOF' > modules/database/main.tf
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
  engine_version            = "15.4"
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
  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "stackpulse-${var.environment}-db-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  tags = { Name = "stackpulse-${var.environment}-postgres" }
}

resource "aws_ssm_parameter" "db_password_param" {
  name        = "/stackpulse/${var.environment}/database_password"
  description = "Database password for ${var.environment}"
  type        = "SecureString"
  value       = random_password.db_password.result
}
EOF

cat << 'EOF' > modules/database/outputs.tf
output "database_endpoint" { value = aws_db_instance.postgres.endpoint }
EOF


echo "💻 Creating Compute Module..."
cat << 'EOF' > modules/compute/variables.tf
variable "environment"       { type = string }
variable "instance_type"     { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "web_sg_id"         { type = string }
variable "key_name"          { type = string }
EOF

cat << 'EOF' > modules/compute/main.tf
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "stackpulse-${var.environment}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_server" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "stackpulse-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.web_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_name

  tags = { Name = "stackpulse-${var.environment}-web-server" }
}

resource "aws_lb" "web_alb" {
  name               = "stackpulse-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.web_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "stackpulse-${var.environment}-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "stackpulse-${var.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "web_attachment" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}
EOF

cat << 'EOF' > modules/compute/outputs.tf
output "alb_dns_name"  { value = aws_lb.web_alb.dns_name }
output "ec2_public_ip" { value = aws_instance.web.public_ip }
EOF


echo "🌍 Creating Prod Environment configuration..."
cat << 'EOF' > environments/prod/providers.tf
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.5" }
  }
  backend "s3" {
    bucket       = "stackpulse-terraform-state-551504153839"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}
EOF

cat << 'EOF' > environments/prod/variables.tf
variable "environment"       { type = string }
variable "vpc_cidr"          { type = string }
variable "db_instance_class" { type = string }
variable "multi_az"          { type = bool }
variable "ec2_instance_type" { type = string }
variable "key_name"          { type = string }
EOF

cat << 'EOF' > environments/prod/terraform.tfvars
environment       = "prod"
vpc_cidr          = "10.0.0.0/16"
db_instance_class = "db.t3.small"
multi_az          = true
ec2_instance_type = "t3.small"
key_name          = "my-dev-key"
EOF

cat << 'EOF' > environments/prod/main.tf
module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "security" {
  source = "../../modules/security"
  vpc_id = module.vpc.vpc_id
}

module "storage" {
  source      = "../../modules/storage"
  environment = var.environment
}

module "database" {
  source             = "../../modules/database"
  environment        = var.environment
  instance_class     = var.db_instance_class
  multi_az           = var.multi_az
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_sg_id           = module.security.db_sg_id
}

module "compute" {
  source            = "../../modules/compute"
  environment       = var.environment
  instance_type     = var.ec2_instance_type
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  web_sg_id         = module.security.web_sg_id
  key_name          = var.key_name
}
EOF

echo "✨ All modular files and production setup generated successfully!"
