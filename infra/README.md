# infra/

Terraform und Hilfsskripte für die Plattform. Regeln für Agents: [AGENTS.md](AGENTS.md).

| Pfad | Zweck | Wer führt aus |
| --- | --- | --- |
| `terraform/bootstrap/` | tfstate-Storage, RGs je Stage, Entra-Apps/SPs + Federated Credentials, Entra-Gruppen, GitHub Environments/Secrets | Mensch lokal (Global Admin), State lokal |
| `terraform/account/` | Databricks-Account: Infra-SPs als Account Admin, Deploy-SPs, Metastore-Admin-Gruppe, System-Schemas, System-Table-Grants | Mensch lokal (Account Admin), einmalig nach dem ersten Workspace |
| `terraform/stacks/azure/` | VNet, NAT, DNS, UC-Storage (privat), Key Vault, Access Connector, Workspaces (VNet-Injection, Storage Firewall), Budget | CI (`sp-…-<env>-infra`) |
| `terraform/stacks/sources/` | Simuliertes Fremdsystem: Azure SQL (Free Offer), Source Storage, PEs; schreibt SQL-Secrets in den Key Vault | CI |
| `terraform/stacks/databricks/` | NCC + Private-Endpoint-Regeln, Storage Credential, External Locations, Catalogs + Bindings, Grants, Secret Scope `kv`, SQL Warehouse | CI |
| `terraform/modules/` | `workspace`, `private_endpoint` | — |
| `terraform/envs/backend.hcl` | gemeinsamer Backend-Teil; Key je Stage/Stack per `-backend-config` | — |
| `scripts/` | `approve-private-endpoints.sh` (NCC-PE-Freigabe), `teardown-stage.sh <env>` (lokaler Abbau einer Stage, Stages nacheinander) | Terraform `local-exec` / Mensch |

**Reihenfolge je Stage:** `azure` → `sources` → `databricks`. Abhängigkeiten laufen über
`terraform_remote_state`. Stage-Werte sind Variablen-Maps in den Stacks. Gesetzt wird nur
`TF_VAR_env`, siehe `Makefile`.

```bash
make tf-plan ENV=dev STACK=azure && make tf-apply ENV=dev STACK=azure
```
