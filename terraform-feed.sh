#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "======================================================"
echo "      StackPulse Infrastructure Setup Wizard          "
echo "======================================================"
echo ""

# Prompt the user for configuration variables
read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Enter S3 Bucket Name (must be globally unique): " S3_BUCKET_NAME
while [ -z "$S3_BUCKET_NAME" ]; do
  read -p "S3 Bucket Name cannot be empty. Enter S3 Bucket Name: " S3_BUCKET_NAME
done

read -p "Enter EC2 Instance Type (default: t3.micro): " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.micro}

read -p "Enter Database Username (default: dbadmin): " DB_USER
DB_USER=${DB_USER:-dbadmin}

read -s -p "Enter Database Password (min 8 chars): " DB_PASSWORD
echo ""
while [ ${#DB_PASSWORD} -lt 8 ]; do
  read -s -p "Password too short. Enter Database Password (min 8 chars): " DB_PASSWORD
  echo ""
done

read -p "Enter Database Name (default: appdb): " DB_NAME
DB_NAME=${DB_NAME:-appdb}

echo ""
echo "Generating terraform/main.tf with your configuration..."

# Write out the Terraform file using the user-provided variables
cat <<EOF > main.tf
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "$AWS_REGION"
}

# --- VPC & NETWORKING ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "stackpulse-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "stackpulse-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${AWS_REGION}a"

  tags = { Name = "stackpulse-public-subnet" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${AWS_REGION}a"

  tags = { Name = "stackpulse-private-subnet-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${AWS_REGION}b"

  tags = { Name = "stackpulse-private-subnet-2" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "stackpulse-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- SECURITY GROUPS ---
resource "aws_security_group" "web_sg" {
  name        = "stackpulse-web-sg"
  description = "Allow HTTP and SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
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

resource "aws_security_group" "db_sg" {
  name        = "stackpulse-db-sg"
  description = "Allow database access from web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Web SG"
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

# --- S3 STORAGE ---
resource "aws_s3_bucket" "app_bucket" {
  bucket        = "$S3_BUCKET_NAME"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- RDS POSTGRESQL DATABASE ---
resource "aws_db_subnet_group" "db_subnets" {
  name       = "stackpulse-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = { Name = "stackpulse-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier             = "stackpulse-db"
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_name                = "$DB_NAME"
  username               = "$DB_USER"
  password               = "$DB_PASSWORD"
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true

  tags = { Name = "stackpulse-postgres" }
}

# --- EC2 WEB SERVER ---
resource "aws_instance" "web" {
  ami                    = "ami-0453ec754f44f9a4a"
  instance_type          = "$INSTANCE_TYPE"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = { Name = "stackpulse-web-server" }
}

# --- OUTPUTS ---
output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.id
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "database_endpoint" {
  value     = aws_db_instance.postgres.endpoint
  sensitive = true
}
EOF

echo ""
echo "✅ main.tf successfully generated!"
echo ""
read -p "Do you want to run 'terraform init' and 'terraform apply' now? (y/n): " RUN_TF

if [[ "$RUN_TF" =~ ^[Yy]$ ]]; then
  terraform init
  terraform apply
else
  echo "Setup finished! You can run 'terraform init' and 'terraform apply' manually inside /home/kalim/stackpulse/terraform/ when ready."
fi
