#!/usr/bin/env bash
# Baut eine Stage lokal ab: Bundles -> Setup-Job-Objekte -> databricks -> sources -> azure.
# Bootstrap und Account-Stack bleiben bestehen (kosten nichts).
#
# Usage: infra/scripts/teardown-stage.sh <dev|tst|prd>
# Wichtig: Stages NACHEINANDER abbauen – alle Stages teilen sich die Terraform-Arbeitsverzeichnisse
# (der Backend-Key wird per `make tf-init` gesetzt).
set -uo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
[ -f .env.local ] && set -a && . ./.env.local && set +a
ENV=${1:?Stage angeben: dev|tst|prd}
export TF_CLI_ARGS_destroy="-auto-approve -no-color"

echo "===== $ENV: Bundles"
make -s tf-init ENV="$ENV" STACK=azure >/dev/null || exit 1
export DATABRICKS_AUTH_TYPE=azure-cli DATABRICKS_HOST="$(make -s ws-host ENV="$ENV")"
export BUNDLE_VAR_deploy_sp="$(make -s deploy-sp-id ENV="$ENV")"
for b in domain_sales ingestion platform; do
  (cd "bundles/$b" && databricks bundle destroy -t "$ENV" --auto-approve 2>&1 | grep -E "^(Error|Destroy complete)" | tail -2)
done

echo "===== $ENV: Objekte des Setup-Jobs (weder im Bundle- noch im Terraform-State)"
# Gehören dem Deploy-SP. Auch ein Metastore-Admin darf sie nicht direkt löschen, wohl aber den
# Owner ändern -> erst Ownership übernehmen, dann löschen (Catalog vor Connection).
ME=$(databricks current-user me -o json | python3 -c "import json,sys; print(json.load(sys.stdin)['userName'])")
databricks catalogs update "${ENV}_src_salesdb" --json "{\"owner\":\"$ME\"}" >/dev/null 2>&1 &&
  databricks catalogs delete "${ENV}_src_salesdb" --force && echo "deleted ${ENV}_src_salesdb"
databricks connections update "conn_${ENV}_salesdb" --json "{\"owner\":\"$ME\"}" >/dev/null 2>&1 &&
  databricks connections delete "conn_${ENV}_salesdb" && echo "deleted conn_${ENV}_salesdb"

make -s tf-init ENV="$ENV" STACK=databricks >/dev/null || exit 1
# System-Schemas gehören dem (geteilten) Metastore: nicht deaktivieren, nur aus dem State nehmen
for r in $(terraform -chdir=infra/terraform/stacks/databricks state list | grep databricks_system_schema); do
  terraform -chdir=infra/terraform/stacks/databricks state rm "$r" >/dev/null && echo "state rm $r"
done
# Eine NCC lässt sich erst löschen, wenn kein Workspace mehr an ihr hängt -> aus dem State nehmen
# und nach dem azure-Stack (Workspace weg) per Account-CLI löschen.
NCC_ID=$(terraform -chdir=infra/terraform/stacks/databricks output -raw ncc_id 2>/dev/null || true)
terraform -chdir=infra/terraform/stacks/databricks state rm databricks_mws_network_connectivity_config.this >/dev/null 2>&1 &&
  echo "state rm NCC $NCC_ID"

for st in databricks sources azure; do
  echo "===== $ENV: $st"
  make -s tf-destroy ENV="$ENV" STACK=$st 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Error|Destroy complete|│ " | head -15
done

if [ -n "${NCC_ID:-}" ]; then
  echo "===== $ENV: NCC löschen"
  # Der Account sieht gelöschte Workspaces noch einige Minuten als "attached" -> Retry
  for i in $(seq 1 40); do
    DATABRICKS_HOST=https://accounts.azuredatabricks.net DATABRICKS_ACCOUNT_ID="${TF_VAR_databricks_account_id:?in .env.local setzen}" \
      databricks account network-connectivity delete-network-connectivity-configuration "$NCC_ID" >/dev/null 2>&1 &&
      { echo "deleted NCC $NCC_ID"; break; }
    sleep 30
  done
fi
