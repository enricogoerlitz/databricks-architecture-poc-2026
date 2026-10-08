variable "subscription_id" { type = string }
variable "env" { type = string }
variable "prefix" {
  type    = string
  default = "dbxpoc"
}
variable "location_short" {
  type    = string
  default = "weu"
}
variable "tfstate_resource_group" { type = string }
variable "tfstate_storage_account" { type = string }
variable "databricks_account_id" { type = string }
variable "deploy_sp_client_id" {
  description = "Client-ID von sp-<prefix>-<env>-deploy (Output des Bootstraps)."
  type        = string
}
variable "enable_file_events" {
  description = "Managed File Events (Event Grid + Queue) auf der Landing-External-Location."
  type        = bool
  default     = true
}
variable "group_grants_enabled" {
  description = "Grants für Entra-Gruppen (Automatic Identity Management löst sie per Namen auf)."
  type        = bool
  default     = true
}

variable "infra_sp_client_id" {
  description = "Client-ID von sp-<prefix>-<env>-infra (wird Workspace-Admin)."
  type        = string
}
