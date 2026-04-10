output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role — set this as AWS_DEPLOY_ROLE_ARN in GitHub secrets"
  value       = aws_iam_role.github_actions.arn
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}
