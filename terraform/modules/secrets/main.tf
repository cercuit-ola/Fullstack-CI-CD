resource "aws_kms_key" "secrets" {
  description             = "${var.environment}/${var.app_name} secrets encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.environment}/${var.app_name}/secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_secretsmanager_secret" "app" {
  for_each = var.secrets

  name        = "${var.environment}/${var.app_name}/${each.key}"
  description = "Managed by Terraform — ${var.app_name} ${each.key}"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = var.secrets

  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = each.value
}
