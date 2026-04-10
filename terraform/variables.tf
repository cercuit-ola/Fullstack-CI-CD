variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "app_name" {
  description = "Application name — used as a prefix for all resources"
  type        = string
  default     = "secure-app"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "github_org" {
  description = "GitHub organisation name (used for OIDC trust policy)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (used for OIDC trust policy)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "ECS task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "ECS task memory in MiB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of ECS task instances"
  type        = number
  default     = 2
}

variable "app_secrets" {
  description = "Map of secret name → initial value to store in Secrets Manager"
  type        = map(string)
  sensitive   = true
  default     = {}
}
