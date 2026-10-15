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
