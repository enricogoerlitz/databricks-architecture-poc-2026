variable "subscription_id" { type = string }
variable "env" { type = string }
variable "prefix" {
  type    = string
  default = "dbxpoc"
}
variable "suffix" { type = string }
variable "location_short" {
  type    = string
  default = "weu"
}
variable "tfstate_resource_group" { type = string }
variable "tfstate_storage_account" { type = string }
variable "sql_password_version" {
  description = <<-EOT
    Erhöhen, um die SQL-Passwörter zu rotieren (write-only, nie im State). Auch nötig, wenn ein
    Apply nach dem Schreiben des Key-Vault-Secrets, aber vor dem SQL-Server abgebrochen ist
    (sonst passen Server- und Key-Vault-Passwort nicht zusammen).
  EOT
  type        = number
  default     = 2
}
variable "sql_location" {
  description = <<-EOT
    Region der Azure SQL. In West Europe ist SQL-Provisioning für die PoC-Subscription gesperrt
    ("ProvisioningDisabled", Kapazitätsbeschränkung) -> Germany West Central. Private Endpoints
    funktionieren regionsübergreifend (PE im westeuropäischen VNet, NCC-PE aus Serverless).
  EOT
  type        = string
  default     = "germanywestcentral"
}

variable "sql_public_access" {
  description = "SQL öffentlich, aber nur für Azure-Dienste (PoC-Kompromiss, siehe Deployment-Journal)."
  type        = bool
  default     = true
}

variable "storage_public_fallback" {
  description = "PoC-Fallback: Storage-Firewall auf Allow, solange NCC-Private-Endpoints noch nicht wirken. Danach false."
  type        = bool
  default     = true
}
