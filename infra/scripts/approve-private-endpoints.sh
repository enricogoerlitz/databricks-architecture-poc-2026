#!/usr/bin/env bash
# Gibt ausstehende Private-Endpoint-Verbindungen auf einer Zielressource frei.
# Verwendet für die NCC-Private-Endpoints von Databricks Serverless (die PEs liegen im
# Databricks-Netz, die Freigabe muss auf UNSERER Ressource erfolgen).
#
# Usage: approve-private-endpoints.sh <resource-id> <anzahl-erwarteter-databricks-pes> [timeout-sekunden]
set -euo pipefail

resource_id="$1"
expected="${2:-1}"
timeout="${3:-900}"
deadline=$(( $(date +%s) + timeout ))
# Eigene (VNet-)PEs liegen in unserer Subscription; die von Databricks Serverless nicht.
own_sub=$(cut -d/ -f3 <<<"$resource_id")

echo "Warte auf Private-Endpoint-Verbindungen an ${resource_id##*/} ..."
while :; do
  pending=$(az network private-endpoint-connection list --id "$resource_id" \
    --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv)
  approved=$(az network private-endpoint-connection list --id "$resource_id" \
    --query "length([?properties.privateLinkServiceConnectionState.status=='Approved' && !contains(properties.privateEndpoint.id, '${own_sub}')])" -o tsv)

  for conn in $pending; do
    echo "  approve ${conn##*/}"
    az network private-endpoint-connection approve --id "$conn" \
      --description "Approved by Terraform (Databricks NCC)" -o none
  done

  # Fertig, sobald nichts mehr aussteht und alle erwarteten Databricks-PEs freigegeben sind
  if [[ -z "$pending" && "${approved:-0}" -ge "$expected" ]]; then
    echo "  ok (${approved} approved)"
    break
  fi
  if (( $(date +%s) > deadline )); then
    echo "Timeout: keine (oder nicht alle) PE-Verbindungen freigegeben" >&2
    exit 1
  fi
  sleep 15
done
