environment   = "dev"
aws_region    = "us-east-1"
app_name      = "secure-app"
vpc_cidr      = "10.1.0.0/16"

github_org    = "your-org"
github_repo   = "your-repo"

container_port = 8080
task_cpu       = 512
task_memory    = 1024
desired_count  = 1

app_secrets = {}
