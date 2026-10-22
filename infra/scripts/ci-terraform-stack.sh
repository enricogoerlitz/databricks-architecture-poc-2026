#!/usr/bin/env bash
# CI: Plan + Apply eines Stacks. Öffentliches Repo -> nur die Plan-Zusammenfassung loggen.
# Usage: ci-terraform-stack.sh <azure|sources|databricks>   (ENV kommt aus der Umgebung)
set -euo pipefail
stack=$1
echo "::group::$stack plan"
make -s tf-init ENV="$ENV" STACK="$stack" >/dev/null
terraform -chdir="infra/terraform/stacks/$stack" plan -input=false -no-color -out=tfplan > "plan-$stack.txt" \
  || { grep -A20 -E "^(│ )?Error" "plan-$stack.txt"; exit 1; }
grep -E "^(Plan:|No changes)" "plan-$stack.txt" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "::endgroup::"
echo "::group::$stack apply"
terraform -chdir="infra/terraform/stacks/$stack" apply -input=false -no-color tfplan
echo "::endgroup::"
