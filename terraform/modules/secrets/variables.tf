variable "environment" { type = string }
variable "app_name" { type = string }
variable "secrets" {
  type      = map(string)
  sensitive = true
  default   = {}
}
