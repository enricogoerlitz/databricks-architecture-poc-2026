# Gemeinsame Backend-Konfiguration für alle Stacks. Der State-Key kommt per
# -backend-config="key=<env>/<stack>.tfstate" (siehe Makefile).
resource_group_name  = "rg-dbxpoc-shared-weu"
storage_account_name = "stdbxpoctfstateeg26"
container_name       = "tfstate"
use_azuread_auth     = true
