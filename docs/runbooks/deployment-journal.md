---
datum: 2026-10-08
autor: Enrico Goerlitz
---

# Deployment-Journal — Erstaufbau dev → tst → prd

Protokoll des ersten End-to-End-Aufbaus: was in welcher Reihenfolge passiert ist und welche
Fehler und Gotchas aufgetreten sind. Es dient als Vorlage für den eigenen Lernpfad.

## 0. Lokaler Aufbau (ohne Cloud)

| Schritt | Ergebnis |
| --- | --- |
| Tools: `brew install databricks/tap/databricks gitleaks mise`, `mise install` | Databricks CLI 1.20.0, terraform 1.14.4, tflint 0.64.0, gitleaks 8.30.1, uv 0.12.23 |
| Provider-Schemas lokal geprüft (`terraform providers schema -json`) | azurerm 5.8.0, databricks 1.137.0, azuread 3.10.0, azapi 2.13.0, github 6.13.0 |
| `make check` | ruff, pytest (26), Metadaten, terraform validate, tflint grün |

**Gotchas beim Schreiben**
- **azurerm 5.x:**
  - `azurerm_private_dns_zone_virtual_network_link` nimmt jetzt `private_dns_zone_id` statt
    RG und Zonenname.
  - `azurerm_storage_container` kennt nur noch `storage_account_id`, das geht über ARM. Gut: Das
    funktioniert auch bei privatem Storage aus GitHub-Runnern.
- **Azure SQL Free Offer:** `azurerm_mssql_database` kennt `useFreeLimit` nicht. Lösung:
  `azapi_resource`.
- **Passwörter nicht im State:** `ephemeral "random_password"` plus `administrator_login_password_wo`
  bzw. `value_wo` im Key Vault Secret.
- **OIDC-Subject:** Das neue Repo (angelegt nach 2026-07-15) nutzt
  `repo:<owner>@<id>/<repo>@<id>:environment:<env>`. Abfragen mit
  `gh api repos/<o>/<r>/actions/oidc/customization/sub`.
- **Bundles im Modus development** setzen ein Präfix vor Schema-Namen. Deshalb Schemas immer per
  `${resources.schemas.<key>.name}` referenzieren.
- **Full Load + `AUTO CDC FROM SNAPSHOT`:** Technische Spalten wie `_ingested_at` vor dem Vergleich
  entfernen. Sonst entsteht bei jedem Lauf für jede Zeile eine neue SCD2-Version.
- **tflint-Regel `azurerm_resources_missing_prevent_destroy`** ist deaktiviert, weil der PoC
  bewusst abgebaut wird (D3).

## 1. Bootstrap (lokal, Mensch)

```bash
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # subscription_id, suffix, OIDC-Präfix eintragen
export GITHUB_TOKEN=$(gh auth token)
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

- 77 Ressourcen: tfstate-Storage, 6 RGs, 6 Entra-Apps/SPs mit Federated Credentials, 11 Gruppen,
  RBAC, 3 GitHub Environments (tst/prd mit Reviewer, prd nur Tags `v*`), Secrets und Variablen.
- **Gotcha:** Beim `github`-Provider ist `plaintext_value` deprecated; `value` verwenden.
- Der Bootstrap-State liegt lokal und ist gitignored. Das ist bewusst so (Henne-Ei mit dem
  State-Storage).

## 2. dev – Stack `azure` (lokal mit eigenem Login)

`make tf-plan ENV=dev STACK=azure && make tf-apply ENV=dev STACK=azure`. Das sind 45 Ressourcen und
dauert ca. 10 Minuten (Workspaces). Es lief im ersten Versuch fehlerfrei durch.

- **Gotcha:** `az databricks …` installiert beim ersten Aufruf die CLI-Extension und hängt dabei
  interaktiv. Die Workspace-URL besser per `make ws-host` aus dem Terraform-Output holen. In der CI
  vorher `az config set extension.use_dynamic_install=yes_without_prompt` setzen.

## 3. Account (manuell + lokal)

1. **Manuell:** Login unter `accounts.azuredatabricks.net` als Global Admin.
2. **Erkenntnis:** Der Account existierte bereits, mit Metastores in westeurope und
   germanywestcentral aus 2024/2025 und weiteren Usern (geteilter Lab-Tenant). Der Vorab-Check
   („kein Account“) war falsch, weil frühere Workspaces bereits gelöscht waren.
   - Der Metastore westeurope hat **keinen Root-Storage** (gut). Owner war eine Gruppe aus einem
     früheren Setup.
   - Neue Workspaces wurden **nicht automatisch zugewiesen** (`METASTORE_DOES_NOT_EXIST`).
3. **Vorgehen:**
   - Neue Owner-Gruppe `dbxpoc-metastore-admins`, Mitglieder: Mensch, Infra-SPs und, verschachtelt,
     die bisherige Owner-Gruppe. So verliert niemand Zugriff.
   - Die Metastore-Zuweisung übernimmt der Stack `databricks` explizit.
4. `infra/terraform/account`: `terraform.tfvars` ausfüllen (Account-ID, Client-IDs,
   `previous_metastore_owner`), dann `init -backend-config=../envs/backend.hcl -backend-config=key=account.tfstate`
   und `apply`.

**Gotchas:**
- **Databricks CLI ≥ 1.x** kennt `--host/--account-id` nicht mehr als Flags. Stattdessen
  `DATABRICKS_HOST` und `DATABRICKS_ACCOUNT_ID` als Umgebungsvariablen setzen.
- **Netzwerkabbruch beim State-Upload** („connection reset“) hinterlässt einen Lock. Lösung:
  `az storage blob lease break … --auth-mode login`, danach `terraform apply` erneut.
  `errored.tfstate` erst löschen, wenn `state push` wirklich erfolgreich war.
- **Owner-Wechsel:** Nach dem Wechsel zeigt die Abfrage „aktueller Owner“ auf die neue Gruppe.
  Die bisherige Owner-Gruppe deshalb als Variable festhalten, sonst verschachtelt sich die Gruppe
  in sich selbst.

## 4. dev – Stack `sources`

- **Gotcha:** `ProvisioningDisabled`: Die Subscription darf in West Europe (und UK South)
  **keine Azure-SQL-Server** anlegen. Prüfen kann man das so:
  `az rest … /providers/Microsoft.Sql/locations/<region>/capabilities` → `reason`.
  - **Lösung:** Die SQL liegt in **Germany West Central** (`var.sql_location`). Der Private Endpoint
    bleibt im westeuropäischen VNet; Private Endpoints funktionieren regionsübergreifend.
  - Der fehlgeschlagene Versuch blockiert den Servernamen weiter („already exists in location
    westeurope“), obwohl keine Ressource sichtbar ist. Deshalb heißt der Server jetzt
    `sql-dbxpoc-<env>-gwc-<sfx>`.
- Danach liefen 16 Ressourcen ohne Fehler durch, inklusive SQL Free Offer über `azapi`.

## 5. dev – Stack `databricks`

61 Ressourcen beim ersten Versuch:
- Metastore-Zuweisung für 2 Workspaces
- NCC, Binding und 5 Private-Endpoint-Regeln, automatisch freigegeben durch
  `approve-private-endpoints.sh` (ca. 50 s)
- Storage Credential, 5 External Locations (Landing mit File Events)
- 4 Catalogs mit Bindings (dev-02 liest Bronze/Silver nur, `READ_ONLY`)
- Grants, Secret Scope `kv` in beiden Workspaces, SQL Warehouse, System-Schemas

## 6. dev – Bundles

- **Gotcha `run_as`:** Wer lokal ein Target mit `run_as` = Deploy-SP deployt, auch als Admin,
  braucht `servicePrincipal.user` auf dem SP. Gelöst per `databricks_access_control_rule_set`
  für die Gruppe `dbxpoc-metastore-admins`.
- **Gotcha `root_path`:** Im Modus `production` hat jeder Deployer seinen eigenen Pfad und State.
  Lokal und in der CI entstünden so doppelte Jobs. Lösung: `root_path` fest auf
  `/Workspace/Users/<deploy-sp>/.bundle/…`. `/Workspace/Shared` funktioniert zwar auch, ist aber
  für alle User beschreibbar (CLI-Warnung).
- **Gotcha Seed:** `pymssql` bricht auf serverless mit SIGABRT ab (native Libraries). Lösung:
  `python-tds` (reines Python) mit TLS.
  - Dabei braucht es `pyOpenSSL==24.2.*`, weil `python-tds` `X509.get_extension` nutzt. Das gibt es
    in neueren pyOpenSSL-Versionen nicht mehr.
  - **Gotcha Azure SQL Auto-Pause:** Die Free-Offer-/Serverless-DB pausiert automatisch; der erste
    Login liefert „Database … is not currently available“. Login-Timeout auf 300 s erhöhen.
  - **Gotcha Azure SQL Connection Policy:** Mit `Redirect` (Default) leitet der Gateway nach dem
    Login auf einen Worker-Host (`…worker.database.windows.net:11xxx`) um, der öffentlich aufgelöst
    wird → „Deny Public Network Access is set to Yes“, obwohl der NCC-PE `ESTABLISHED` ist.
    Lösung: `connection_policy = "Proxy"` am SQL-Server (alles über 1433 und den Private Endpoint).
  - **Gotcha Passwort-Drift:** Ein `sources`-Apply brach nach dem Key-Vault-Secret, aber vor dem
    SQL-Server ab (Region gesperrt). Der spätere Lauf setzte am Server ein neues ephemeral Passwort,
    das Secret blieb alt → „Login failed“. Lösung: `sql_password_version` erhöhen; dann werden
    beide im selben Lauf neu gesetzt.
- **Gotcha NCC-Private-Endpoints greifen (noch) nicht:**
  - Alle Regeln sind `ESTABLISHED` und die NCC ist gebunden. Trotzdem löst Serverless die Hosts
    öffentlich auf (`socket.gethostbyname` im Probe-Notebook), und der Storage antwortet mit 403.
  - Laut Doku dauert es „meist 10 Minuten, bis zu 24 Stunden“.
  - **PoC-Fallback:**
    - `storage_public_fallback = true` setzt die Storage-Firewall auf `Allow`. Der Zugriff bleibt
      Entra-only, ohne Shared Keys.
    - `sql_public_access = true` erlaubt nur Azure-Dienste.
  - **Lernpfad:** später auf `false` stellen und den privaten Pfad verifizieren.
- **Gotcha Federation-SQL:**
  - `SHOW CONNECTIONS LIKE` gibt es nicht, stattdessen `WorkspaceClient().connections.list()`.
  - `COMMENT` ist in `CREATE CONNECTION`/`CREATE FOREIGN CATALOG` an der gewählten Stelle ein
    Syntaxfehler, deshalb separat `COMMENT ON …`.
- **Gotcha Laufzeit-Token:**
  - Ein Job-Token (`auth_type=runtime`) darf `UpdateCatalog` (Isolation/Binding) nicht aufrufen.
  - Das Binding passiert deshalb im Deploy-Schritt per CLI:
    `catalogs update --isolation-mode ISOLATED` und
    `workspace-bindings update-bindings`. **Achtung:** `ISOLATED` allein bindet **keinen**
    Workspace, das Binding muss explizit dazu.
- **Gotcha Table Update Trigger:** Die überwachten Tabellen müssen beim Anlegen des Jobs schon
  existieren. Deploy-Reihenfolge deshalb: Ingestion → Läufe → `domain_sales`.
- **Gotcha CI:** `az databricks …` braucht die CLI-Extension. Vorher
  `az config set extension.use_dynamic_install=yes_without_prompt` setzen.
- **Beobachtung:** Im Performance-Modus `STANDARD` startet Serverless 4–6 Minuten verzögert. Das
  ist günstiger, aber Iterationen dauern länger. Zum Entwickeln kann man in
  `metadata/environments/dev.yml` `PERFORMANCE_OPTIMIZED` setzen.

## 7. CI/CD (GitHub Actions)

PR #1 → CI grün (ruff, pytest, terraform validate/tflint, gitleaks) → Squash-Merge auf `main`.
Dadurch starten `infra-deploy` und `bundles-deploy` automatisch für dev.

**Gotchas beim ersten CI-Lauf:**
- **`No value for required variable`:** Das Makefile exportiert `TF_VAR_*` nur innerhalb von
  `make`. Ruft der Workflow `terraform` direkt auf, müssen die Variablen im Workflow-`env` stehen.
- **Owner-Wechsel nicht erlaubt:** „only workspace admins can change the owner of a job“. Die
  Jobs und Pipelines waren lokal von einem Menschen angelegt worden, und der Deploy-SP ist
  bewusst kein Workspace-Admin. Lösung (einmalig): Ownership per
  `databricks permissions set jobs|pipelines <id> --json '{"access_control_list":[{"service_principal_name":"<sp>","permission_level":"IS_OWNER"}]}'`
  übertragen.
  - **Lehre:** Die erste Anlage in einer CI-Stage sollte immer durch die CI erfolgen. Lokal nur
    `-t personal` verwenden.
- **CI-SPs ohne Graph-Rechte:** `az ad sp list` und `data "azuread_*"` funktionieren in der CI
  nicht. Die IDs kommen deshalb vom Bootstrap als Secrets (`AZURE_DATABRICKS_SP_OBJECT_ID`,
  `KV_ADMIN_OBJECT_IDS`, `AZURE_CLIENT_ID_*`).
- **Reihenfolge Infra vor Bundles:** Beide Workflows starten parallel. Bei einer neuen Stage
  (tst/prd) muss die Infra-Freigabe vor der Bundles-Freigabe erteilt werden.
- **Infra-SP kein Workspace-Mitglied:** „cannot read …: User not authorized“. Azure-Contributor
  auf der RG macht einen SP in Workspaces mit Identity Federation **nicht** automatisch zum Admin.
  Lösung: `databricks_mws_permission_assignment` (ADMIN) für den Infra-SP über den
  Account-Provider. Alle Workspace-Ressourcen hängen über die Metastore-Zuweisung daran.
- **Merge ohne Checks möglich:** PR #3 wurde gemerged, bevor die CI lief, weil kein Branch-Schutz
  aktiv war. Jetzt gibt es `github_repository_ruleset` „protect-main“ (Bootstrap): nur Squash-PRs,
  Checks `python`/`terraform`/`secrets` Pflicht, kein Force-Push und kein Löschen.
- **tst-Infra: `LinkedAuthorizationFailed`:** Ein Private Endpoint auf den Workspace-Root-Storage
  (Managed RG) braucht `Microsoft.Storage/storageAccounts/PrivateEndpointConnectionsApproval/action`
  auf diesem Storage. Der Infra-SP hat Rechte nur auf seinen RGs. Lösung: eng geschnittene
  Custom Role `dbxpoc-private-endpoint-approver` auf Subscription-Scope (Bootstrap). Im
  Zielbild mit einer Subscription je Stage ist das automatisch stage-begrenzt.
- **Freigaben automatisieren:** `gh api -X POST repos/<o>/<r>/actions/runs/<id>/pending_deployments -F "environment_ids[]=<id>" -f state=approved`
  (Self-Review ist im Environment erlaubt).
- **Autoritative Grants auf geteilten Objekten:** `databricks_grants` setzt die **komplette**
  Grant-Liste. Der Metastore-Grant des tst-Stacks hat den des dev-Deploy-SP entfernt
  („does not have CREATE CATALOG on Metastore“). Auf dem `system`-Catalog hätte er sogar Grants
  von Kollegen im geteilten Metastore gelöscht. Regel: Für metastore-weite oder fremde Objekte
  `databricks_grant` (nicht-autoritativ, je Principal) verwenden. `databricks_grants` nur für
  Objekte, die dem Stack exklusiv gehören (eigene Catalogs). Die Umstellung erfolgt per
  `removed { lifecycle { destroy = false } }`, damit nichts revoked wird.
- **Gold in neuer Stage leer:** Der Table Update Trigger feuert erst bei der *nächsten*
  Silver-Änderung. Die CI startet `gold_sales` beim Deploy deshalb einmal selbst.
- **Engineers in tst/prd:** brauchen `EXECUTE` (zentrale Funktionen) und `READ_VOLUME`, sonst
  „does not have EXECUTE on Routine“.
