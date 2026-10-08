variable "subscription_id" { type = string }
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "tst", "prd"], var.env)
    error_message = "env: dev | tst | prd"
  }
}
variable "prefix" {
  type    = string
  default = "dbxpoc"
}
variable "suffix" { type = string }
variable "location" {
  type    = string
  default = "westeurope"
}
variable "location_short" {
  type    = string
  default = "weu"
}
variable "vnet_cidrs" {
  description = "/22 je Stage"
  type        = map(string)
  default = {
    dev = "10.10.0.0/22"
    tst = "10.20.0.0/22"
    prd = "10.30.0.0/22"
  }
}
variable "workspace_indexes" {
  description = "Workspaces je Stage (D2: dev x2, tst x1, prd x1)"
  type        = map(list(string))
  default = {
    dev = ["01", "02"]
    tst = ["01"]
    prd = ["01"]
  }
}
variable "kv_admin_object_ids" {
  description = "Entra-Objekt-IDs mit Secret-Vollzugriff im Key Vault: Infra-SP der Stage + Gruppe ws-admins."
  type        = list(string)
}

variable "azure_databricks_sp_object_id" {
  description = "Objekt-ID der Enterprise App 'AzureDatabricks' (App-ID 2ff814a6-…) im Tenant."
  type        = string
}
variable "budget_amount" {
  description = "Monatsbudget in der Abrechnungswährung je Stage-RG"
  type        = number
  default     = 20
}
variable "budget_contact_emails" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "storage_public_fallback" {
  description = "PoC-Fallback: Storage-Firewall auf Allow, solange NCC-Private-Endpoints noch nicht wirken. Danach false."
  type        = bool
  default     = true
}
