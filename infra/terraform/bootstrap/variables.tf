variable "subscription_id" {
  description = "Azure Subscription für den PoC (nur in terraform.tfvars, nie committen)."
  type        = string
}

variable "prefix" {
  type    = string
  default = "dbxpoc"
}

variable "suffix" {
  description = "Festes 4-Zeichen-Suffix für global eindeutige Namen (Storage, Key Vault, SQL)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{4}$", var.suffix))
    error_message = "suffix: genau 4 Zeichen a-z0-9."
  }
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "location_short" {
  type    = string
  default = "weu"
}

variable "environments" {
  type    = list(string)
  default = ["dev", "tst", "prd"]
}

variable "github_owner" {
  type    = string
  default = "enricogoerlitz"
}

variable "github_repository" {
  type    = string
  default = "databricks-architecture-poc-2026"
}

variable "github_oidc_subject_prefix" {
  description = "Präfix des OIDC-sub-Claims. Ermitteln mit: gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
}

variable "databricks_account_id" {
  description = "Leer lassen bis der Databricks-Account existiert (nach dem ersten Workspace)."
  type        = string
  default     = ""
}

variable "tags" {
  type = map(string)
  default = {
    project     = "dbxpoc"
    owner       = "enrico-goerlitz"
    cost-center = "poc"
    repo        = "databricks-architecture-poc-2026"
  }
}
