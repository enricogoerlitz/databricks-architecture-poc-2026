# Account-Ebene (einmalig, lokal, durch einen Account Admin):
#   - Infra-SPs im Account registrieren und zu Account Admins machen (PoC-Kompromiss, s. Design)
#   - Deploy-SPs im Account registrieren
#   - Databricks-Gruppe "<prefix>-metastore-admins" (du + Infra-SPs + bisherige Owner-Gruppe)
#     als Metastore-Owner -> niemand verliert Zugriff
#   - Gruppe "<prefix>-deploy-sps" (alle Deploy-SPs) für Grants auf System Tables
# Der Metastore selbst entsteht automatisch mit dem ersten Workspace und wird bewusst NICHT
# von Terraform verwaltet (kein Risiko, ihn per destroy zu löschen).

data "databricks_metastores" "all" {}

locals {
  metastore_ids = [for name, id in data.databricks_metastores.all.ids : id]
}

data "databricks_metastore" "region" {
  # Genau ein Metastore je Region; per Name nicht vorhersagbar -> über die Liste filtern
  for_each     = toset(local.metastore_ids)
  metastore_id = each.key
}

locals {
  metastore = one([for m in data.databricks_metastore.region : m.metastore_info[0] if m.metastore_info[0].region == var.region])
}

resource "databricks_service_principal" "infra" {
  for_each       = var.infra_sp_client_ids
  application_id = each.value
  display_name   = "sp-${var.prefix}-${each.key}-infra"
}

resource "databricks_service_principal_role" "infra_account_admin" {
  for_each             = databricks_service_principal.infra
  service_principal_id = each.value.id
  role                 = "account_admin"
}

resource "databricks_service_principal" "deploy" {
  for_each       = var.deploy_sp_client_ids
  application_id = each.value
  display_name   = "sp-${var.prefix}-${each.key}-deploy"
}

resource "databricks_group" "metastore_admins" {
  display_name = "${var.prefix}-metastore-admins"
}

data "databricks_user" "admin" {
  user_name = var.admin_user_name
}

resource "databricks_group_member" "admin" {
  group_id  = databricks_group.metastore_admins.id
  member_id = data.databricks_user.admin.id
}

# Bisherige Owner-Gruppe (z. B. aus einem früheren Setup) bleibt über Verschachtelung Admin.
data "databricks_group" "previous_owner" {
  count        = var.previous_metastore_owner == "" ? 0 : 1
  display_name = var.previous_metastore_owner
}

resource "databricks_group_member" "previous_owner" {
  count     = length(data.databricks_group.previous_owner)
  group_id  = databricks_group.metastore_admins.id
  member_id = data.databricks_group.previous_owner[0].id
}

resource "databricks_group" "deploy_sps" {
  display_name = "${var.prefix}-deploy-sps"
}

resource "databricks_group_member" "deploy_sps" {
  for_each  = databricks_service_principal.deploy
  group_id  = databricks_group.deploy_sps.id
  member_id = each.value.id
}

resource "databricks_group_member" "infra" {
  for_each  = databricks_service_principal.infra
  group_id  = databricks_group.metastore_admins.id
  member_id = each.value.id
}

# Metastore-Owner auf die Gruppe setzen (CLI statt Ressource, siehe Kommentar oben)
resource "terraform_data" "metastore_owner" {
  triggers_replace = [local.metastore.metastore_id, databricks_group.metastore_admins.display_name]
  provisioner "local-exec" {
    command = <<-EOT
      databricks account metastores update ${local.metastore.metastore_id} \
        --json '{"metastore_info": {"owner": "${databricks_group.metastore_admins.display_name}"}}' -o json >/dev/null
    EOT
    environment = {
      DATABRICKS_HOST       = "https://accounts.azuredatabricks.net"
      DATABRICKS_ACCOUNT_ID = var.databricks_account_id
      DATABRICKS_AUTH_TYPE  = "azure-cli"
    }
  }
  depends_on = [databricks_group_member.admin, databricks_group_member.infra, databricks_group_member.previous_owner]
}

# ---------------------------------------------------------------------------
# Rollen-Gruppen je Stage. Automatic Identity Management ist in diesem (2024 angelegten,
# geteilten) Account nicht aktiv; account-weit einschalten nur nach Abstimmung. Deshalb hier
# Databricks-Account-Gruppen mit denselben Namen wie die Entra-Gruppen aus dem Bootstrap.
# Im Zielbild: AIM an, Gruppen kommen aus Entra und diese Ressourcen entfallen.
# ---------------------------------------------------------------------------
locals {
  role_groups = toset(flatten([
    for env in keys(var.infra_sp_client_ids) : [for kind in ["ws-admins", "engineers", "analysts"] : "sg-${var.prefix}-${env}-${kind}"]
  ]))
}

resource "databricks_group" "role" {
  for_each     = local.role_groups
  display_name = each.key
}

resource "databricks_group_member" "role_admin" {
  for_each  = databricks_group.role
  group_id  = each.value.id
  member_id = data.databricks_user.admin.id
}
