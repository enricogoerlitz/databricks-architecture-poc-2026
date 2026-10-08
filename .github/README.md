# .github/

| Pfad | Zweck |
| --- | --- |
| `workflows/ci.yml` | PR/main: ruff, pytest, Metadaten, Wheel-Build, terraform fmt/validate, tflint, gitleaks |
| `workflows/infra-deploy.yml` + `_stage-infra.yml` | Terraform je Stage: main → dev → tst (Approval), Tag `v*` → prd (Approval) |
| `workflows/bundles-deploy.yml` + `_stage-bundles.yml` | Bundles je Stage, gleiche Promotion |
| `workflows/teardown.yml` | Manueller Abbau (`workloads` oder `all`) mit Bestätigung |
| `copilot-instructions.md`, `instructions/` | Copilot (verweist auf `AGENTS.md`, pfadspezifische Regeln) |
| `CODEOWNERS`, `pull_request_template.md` | Review-Regeln, PR-Checkliste |

**Identitäten:** Die Workflows melden sich per OIDC an (`azure/login`, ohne Client-Secrets). Je
Stage gibt es `AZURE_CLIENT_ID_INFRA` und `AZURE_CLIENT_ID_DEPLOY` als Environment-Secrets.
Tenant- und Subscription-ID sind Repo-Secrets und damit in den öffentlichen Logs maskiert. Alles
wird vom Terraform-Bootstrap gepflegt.
