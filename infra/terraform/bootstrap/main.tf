# Bootstrap: einmalig LOKAL durch einen Menschen (Global Admin + Subscription Owner) ausgeführt.
# Legt alles an, was die CI-Identitäten erst möglich macht:
#   - tfstate-Storage (geteilt)
#   - Resource Groups je Stage (Plattform + Quellen)
#   - Entra-Apps/SPs je Stage (infra, deploy) mit Federated Credentials auf GitHub Environments
#   - Entra-Gruppen für das Berechtigungskonzept
#   - GitHub Environments, Reviewer und Variablen
# State: lokal (terraform.tfstate, gitignored). Begründung: Henne-Ei mit dem tfstate-Storage.

data "azuread_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Enterprise App "AzureDatabricks" (First-Party, feste App-ID) – liest Key Vaults für Secret Scopes
data "azuread_service_principal" "azure_databricks" {
  client_id = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
}

locals {
  tags = merge(var.tags, { managed-by = "terraform-bootstrap" })

  # SP-Matrix: je Stage eine Infra- und eine Deploy-Identität.
  sps = merge([
    for env in var.environments : {
      for role in ["infra", "deploy"] :
      "${env}-${role}" => { env = env, role = role }
    }
  ]...)

  # Gruppen: global + je Stage
  global_groups = {
    account-admins   = "Databricks Account Admins (${var.prefix})"
    metastore-admins = "Unity Catalog Metastore Admins (${var.prefix})"
  }
  env_groups = merge([
    for env in var.environments : {
      for g in ["ws-admins", "engineers", "analysts"] :
      "${env}-${g}" => { env = env, kind = g }
    }
  ]...)
}

# ---------------------------------------------------------------------------
# tfstate
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.prefix}-shared-${var.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "st${var.prefix}tfstate${var.suffix}"
  resource_group_name      = azurerm_resource_group.shared.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  # Nur Entra-Auth, keine Shared Keys. Public Endpoint bleibt offen, weil GitHub-hosted Runner
  # sonst den State nicht erreichen (bewusster PoC-Kompromiss, siehe solution-design Kap. 10).
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }
  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# Der ausführende Mensch braucht Datenrechte, um den State später selbst zu lesen.
resource "azurerm_role_assignment" "tfstate_me" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Resource Groups je Stage
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "platform" {
  for_each = toset(var.environments)
  name     = "rg-${var.prefix}-${each.key}-${var.location_short}"
  location = var.location
  tags     = merge(local.tags, { env = each.key })
}

resource "azurerm_resource_group" "sources" {
  for_each = toset(var.environments)
  name     = "rg-${var.prefix}-${each.key}-src-${var.location_short}"
  location = var.location
  tags     = merge(local.tags, { env = each.key })
}

# ---------------------------------------------------------------------------
# Entra: Apps + SPs + Federated Credentials (GitHub OIDC, keine Secrets)
# ---------------------------------------------------------------------------
resource "azuread_application" "sp" {
  for_each     = local.sps
  display_name = "sp-${var.prefix}-${each.key}"
  owners       = [data.azuread_client_config.current.object_id]
  notes        = "GitHub Actions identity (${each.value.role}) for stage ${each.value.env}. Managed by infra/terraform/bootstrap."
}

resource "azuread_service_principal" "sp" {
  for_each  = local.sps
  client_id = azuread_application.sp[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github_env" {
  for_each       = local.sps
  application_id = azuread_application.sp[each.key].id
  display_name   = "github-env-${each.value.env}"
  description    = "GitHub Actions, Environment ${each.value.env}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # Neues GitHub-Format (Repos ab 2026-07-15): repo:<owner>@<id>/<repo>@<id>:environment:<env>
  subject = "${var.github_oidc_subject_prefix}:environment:${each.value.env}"
}

# Infra-SP: Contributor + RBAC-Admin auf den eigenen Stage-RGs (nicht auf der Subscription).
resource "azurerm_role_assignment" "infra_contributor" {
  for_each = {
    for pair in setproduct(var.environments, ["platform", "sources"]) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], rg = pair[1] }
  }
  scope                = each.value.rg == "platform" ? azurerm_resource_group.platform[each.value.env].id : azurerm_resource_group.sources[each.value.env].id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.sp["${each.value.env}-infra"].object_id
}

resource "azurerm_role_assignment" "infra_rbac_admin" {
  for_each = {
    for pair in setproduct(var.environments, ["platform", "sources"]) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], rg = pair[1] }
  }
  scope                = each.value.rg == "platform" ? azurerm_resource_group.platform[each.value.env].id : azurerm_resource_group.sources[each.value.env].id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.sp["${each.value.env}-infra"].object_id
}

# Infra-SP: State lesen/schreiben
resource "azurerm_role_assignment" "infra_tfstate" {
  for_each             = toset(var.environments)
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.sp["${each.key}-infra"].object_id
}

# Deploy-SP: nur Reader auf der Plattform-RG (Workspace-URL nachschlagen); alles Weitere in Databricks.
resource "azurerm_role_assignment" "deploy_reader" {
  for_each             = toset(var.environments)
  scope                = azurerm_resource_group.platform[each.key].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.sp["${each.key}-deploy"].object_id
}

# ---------------------------------------------------------------------------
# Entra-Gruppen (Sync nach Databricks über Automatic Identity Management)
# ---------------------------------------------------------------------------
resource "azuread_group" "global" {
  for_each         = local.global_groups
  display_name     = "sg-${var.prefix}-${each.key}"
  description      = each.value
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members          = [data.azuread_client_config.current.object_id]
}

resource "azuread_group" "env" {
  for_each         = local.env_groups
  display_name     = "sg-${var.prefix}-${each.key}"
  description      = "Databricks ${each.value.kind} for stage ${each.value.env} (${var.prefix})"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  # Der ausführende Mensch ist im PoC überall Mitglied; in tst/prd nur lesend durch die Grants.
  members = [data.azuread_client_config.current.object_id]
}

# Private Endpoints auf den Workspace-Root-Storage (Managed RG, entsteht erst mit dem Workspace)
# brauchen die Approval-Aktion auf diesem Storage. Eng geschnittene Custom Role auf Subscription-
# Scope. PoC-Kompromiss: eine Subscription für alle Stages; im Zielbild (Subscription je Stage)
# ist der Scope automatisch auf die eigene Stage begrenzt.
resource "azurerm_role_definition" "pe_approver" {
  name        = "${var.prefix}-private-endpoint-approver"
  scope       = data.azurerm_subscription.current.id
  description = "Darf Private-Endpoint-Verbindungen auf Storage Accounts freigeben (Workspace-Root-Storage in Managed RGs)."
  permissions {
    actions = ["Microsoft.Storage/storageAccounts/PrivateEndpointConnectionsApproval/action"]
  }
  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "infra_pe_approver" {
  for_each           = toset(var.environments)
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.pe_approver.role_definition_resource_id
  principal_id       = azuread_service_principal.sp["${each.key}-infra"].object_id
}
