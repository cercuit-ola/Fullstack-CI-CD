environment   = "prod"
aws_region    = "us-east-1"
app_name      = "secure-app"
vpc_cidr      = "10.0.0.0/16"

# Replace with your GitHub org and repo
github_org    = "your-org"
github_repo   = "your-repo"

container_port = 8080
task_cpu       = 1024
task_memory    = 2048
desired_count  = 2

# Secrets are injected via Secrets Manager — do NOT commit real values here.
# Use: terraform apply -var='app_secrets={"db_password":"..."}'
# or set TF_VAR_app_secrets in CI.
app_secrets = {}
