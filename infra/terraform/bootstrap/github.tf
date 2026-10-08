# GitHub Environments, Gates und (maskierte) Werte für die Workflows.
# IDs sind keine echten Geheimnisse, werden aber als Secrets abgelegt, damit sie in den öffentlichen
# Workflow-Logs maskiert sind (Repo ist public).

data "github_user" "reviewer" {
  username = var.github_owner
}

resource "github_repository_environment" "env" {
  for_each    = toset(var.environments)
  repository  = var.github_repository
  environment = each.key

  # tst/prd brauchen eine Freigabe. Self-Review ist erlaubt (Solo-PoC).
  dynamic "reviewers" {
    for_each = contains(["tst", "prd"], each.key) ? [1] : []
    content {
      users = [data.github_user.reviewer.id]
    }
  }
  prevent_self_review = false

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# dev/tst: nur von main; prd: nur von Release-Tags v*
resource "github_repository_environment_deployment_policy" "branch_main" {
  for_each       = toset([for e in var.environments : e if e != "prd"])
  repository     = var.github_repository
  environment    = github_repository_environment.env[each.key].environment
  branch_pattern = "main"
}

resource "github_repository_environment_deployment_policy" "tag_release" {
  for_each    = toset([for e in var.environments : e if e == "prd"])
  repository  = var.github_repository
  environment = github_repository_environment.env[each.key].environment
  tag_pattern = "v*"
}

resource "github_actions_environment_secret" "client_id" {
  for_each    = local.sps
  repository  = var.github_repository
  environment = github_repository_environment.env[each.value.env].environment
  secret_name = "AZURE_CLIENT_ID_${upper(each.value.role)}"
  value       = azuread_application.sp[each.key].client_id
}

resource "github_actions_secret" "repo" {
  for_each = {
    AZURE_TENANT_ID       = data.azuread_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    # CI-SPs haben keine Graph-Rechte -> Objekt-IDs vorab auflösen und mitgeben
    AZURE_DATABRICKS_SP_OBJECT_ID = data.azuread_service_principal.azure_databricks.object_id
  }
  repository  = var.github_repository
  secret_name = each.key
  value       = each.value
}

# Nicht-sensible Konfiguration als Variablen
resource "github_actions_variable" "repo" {
  for_each = {
    PREFIX         = var.prefix
    SUFFIX         = var.suffix
    LOCATION       = var.location
    LOCATION_SHORT = var.location_short
    TF_STATE_RG    = azurerm_resource_group.shared.name
    TF_STATE_SA    = azurerm_storage_account.tfstate.name
  }
  repository    = var.github_repository
  variable_name = each.key
  value         = each.value
}

# Databricks-Account-ID gibt es erst nach dem ersten Workspace + Login (manueller Schritt M4/M5).
resource "github_actions_secret" "databricks_account_id" {
  count       = var.databricks_account_id == "" ? 0 : 1
  repository  = var.github_repository
  secret_name = "DATABRICKS_ACCOUNT_ID"
  value       = var.databricks_account_id
}

# Key-Vault-Admins je Stage: Infra-SP (schreibt Secrets im Layer sources) + Gruppe ws-admins
resource "github_actions_environment_secret" "kv_admins" {
  for_each    = toset(var.environments)
  repository  = var.github_repository
  environment = github_repository_environment.env[each.key].environment
  secret_name = "KV_ADMIN_OBJECT_IDS"
  value = jsonencode([
    azuread_service_principal.sp["${each.key}-infra"].object_id,
    azuread_group.env["${each.key}-ws-admins"].object_id,
  ])
}
