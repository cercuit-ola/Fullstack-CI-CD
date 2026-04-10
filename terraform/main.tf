terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "secure-app-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "secure-app-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "secure-cicd"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    }
  }
}

# ─────────────────────────────────────────────
# VPC & Networking
# ─────────────────────────────────────────────
module "vpc" {
  source      = "./modules/vpc"
  environment = var.environment
  aws_region  = var.aws_region
  vpc_cidr    = var.vpc_cidr
}

# ─────────────────────────────────────────────
# IAM (OIDC role for GitHub Actions)
# ─────────────────────────────────────────────
module "iam" {
  source             = "./modules/iam"
  environment        = var.environment
  github_org         = var.github_org
  github_repo        = var.github_repo
  ecr_repository_arn = module.ecr.repository_arn
  ecs_cluster_arn    = module.ecs.cluster_arn
  ecs_service_arn    = module.ecs.service_arn
}

# ─────────────────────────────────────────────
# ECR Repository
# ─────────────────────────────────────────────
module "ecr" {
  source      = "./modules/ecr"
  environment = var.environment
  app_name    = var.app_name
}

# ─────────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────────
module "secrets" {
  source      = "./modules/secrets"
  environment = var.environment
  app_name    = var.app_name
  secrets     = var.app_secrets
}

# ─────────────────────────────────────────────
# ECS Cluster + Service + Task Definition
# ─────────────────────────────────────────────
module "ecs" {
  source             = "./modules/ecs"
  environment        = var.environment
  app_name           = var.app_name
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  ecr_image_url      = module.ecr.repository_url
  secrets_arns       = module.secrets.secret_arns
  task_role_arn      = module.iam.ecs_task_role_arn
  execution_role_arn = module.iam.ecs_execution_role_arn
  container_port     = var.container_port
  cpu                = var.task_cpu
  memory             = var.task_memory
  desired_count      = var.desired_count
}
