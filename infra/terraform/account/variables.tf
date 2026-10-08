variable "databricks_account_id" { type = string }
variable "region" {
  type    = string
  default = "westeurope"
}
variable "prefix" {
  type    = string
  default = "dbxpoc"
}
variable "admin_user_name" {
  description = "Dein UPN; wird Mitglied der Metastore-Admin-Gruppe."
  type        = string
}
variable "infra_sp_client_ids" {
  description = "Map env => Client-ID von sp-<prefix>-<env>-infra (Bootstrap-Output)."
  type        = map(string)
}
variable "deploy_sp_client_ids" {
  description = "Map env => Client-ID von sp-<prefix>-<env>-deploy (Bootstrap-Output)."
  type        = map(string)
}
variable "previous_metastore_owner" {
  description = "Bisherige Owner-Gruppe des Metastores (bleibt als verschachteltes Mitglied Admin). Leer, wenn keine."
  type        = string
  default     = ""
}
