variable "environment" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "ecr_repository_arn" { type = string }
variable "ecs_cluster_arn" { type = string }
variable "ecs_service_arn" { type = string }
variable "app_name" {
  type    = string
  default = "secure-app"
}
