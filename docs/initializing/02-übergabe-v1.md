---
datum: 2026-10-08
autor: Enrico Goerlitz
quelle: docs/initializing/01-PROMPT.md
---

# Übergabe v1 — Stand nach dem ersten Aufbautag

## 1. Stand in einem Satz

dev und tst wurden komplett über Terraform und die GitHub-Actions-Pipeline aufgebaut und End-to-End
getestet, danach am Abend wieder **abgebaut**:
- Full Load per Federation → Bronze → SCD2 in Silver (`AUTO CDC FROM SNAPSHOT`) → Gold.
- Auto Loader mit File-Arrival-Trigger.
- Zentrale UC Functions aus dem Wheel.
- OIDC-Deploy mit Approvals.

Bestehen bleiben nur die kostenlosen Grundlagen.

| Bereich | Status |
| --- | --- |
| Bootstrap (tfstate-Storage, RGs, Entra-SPs/OIDC, Entra-Gruppen, GitHub Environments/Secrets/Ruleset, PE-Approver-Rolle) | **bleibt** (lokaler State in `infra/terraform/bootstrap/`) |
| Account-Stack (Databricks-SPs + Account-Admin-Rolle, Gruppen, Metastore-Owner `dbxpoc-metastore-admins`) | **bleibt** (State `account.tfstate`) |
| Stacks `azure`, `sources`, `databricks` + Bundles für dev und tst | **abgebaut** |
| prd | nie deployt |
| Workflows `infra-deploy` und `bundles-deploy` | **deaktiviert** (damit ein Push auf `main` nichts hochfährt) |
| Kosten im Ruhezustand | ≈ 0 € (tfstate-Storage im Cent-Bereich) |

Alle Schritte, Fehler und Gotchas des Tages stehen in
[`docs/runbooks/deployment-journal.md`](../runbooks/deployment-journal.md). **Unbedingt vor dem
nächsten Aufbau lesen.**

## 2. Wieder hochfahren (empfohlen: über die Pipeline)

**Voraussetzungen lokal** (einmalig):

```bash
mise install && uv sync && uv run pre-commit install
az login                       # Lab-Tenant, Subscription des PoC
gh auth status                 # Account enricogoerlitz
```

**Ablauf** (ca. 1–1,5 h für dev + tst, ohne Handarbeit):

```bash
# 1. Workflows wieder aktivieren
gh workflow enable infra-deploy.yml
gh workflow enable bundles-deploy.yml

# 2. dev: erst Infra (ca. 15–20 min), dann Bundles (ca. 30–40 min, Serverless "Standard" startet langsam)
gh workflow run infra-deploy.yml -f env=dev
gh run watch            # warten bis grün
gh workflow run bundles-deploy.yml -f env=dev
gh run watch

# 3. tst: gleich, aber mit Freigabe im GitHub-UI (Actions → Run → "Review deployments")
#    Wichtig: erst die Infra freigeben und abwarten, dann die Bundles.
gh workflow run infra-deploy.yml -f env=tst
gh workflow run bundles-deploy.yml -f env=tst
```

**Danach prüfen:**
- **Workspace-URL:** im Azure-Portal (RG `rg-dbxpoc-<env>-weu`) oder
  `make tf-init ENV=dev STACK=azure && make ws-host`.
- **Catalog Explorer:** `dev_bronze|silver|gold|platform` und `dev_src_salesdb` (Federation).
- **Jobs & Pipelines:** `ingest_salesdb`, `ingest_crm_files`, `gold_sales`, `seed_sources`,
  `platform_setup`, `publish_metadata`.
- **SQL:**
  `SELECT * FROM dev_silver.salesdb.customers ORDER BY customer_id, __START_AT`.
- **SCD2-Demo:** Job `seed_sources` mit Parameter `round=2` starten, dann `ingest_salesdb`.
  `ingest_crm_files` und `gold_sales` starten danach automatisch über ihre Trigger.

**Alternative lokal**, ohne Pipeline und gut zum Debuggen. Der Ablauf steht im Journal
(Abschnitte 2–6). Kurz:

```bash
for s in azure sources databricks; do make tf-plan ENV=dev STACK=$s && make tf-apply ENV=dev STACK=$s; done
```

Danach die Bundles in der Reihenfolge aus `bundles/README.md`.

> **Achtung:** Was lokal in einer CI-Stage (dev/tst/prd) angelegt wird, gehört deinem User. Danach
> kann der Deploy-SP es nicht mehr ändern (Journal: „Owner-Wechsel nicht erlaubt“). Lokal deshalb
> nur `-t personal` deployen und die CI-Stages der Pipeline überlassen.

## 3. Wieder abbauen

```bash
infra/scripts/teardown-stage.sh tst      # Stages NACHEINANDER, nie parallel
infra/scripts/teardown-stage.sh dev
```

Das Skript enthält alle Lehren vom Abbau heute (Journal Abschnitt 8):
- Bundles zuerst.
- Die vom Setup-Job angelegten Objekte (Foreign Catalog und Connection) mit vorheriger
  Ownership-Übernahme entfernen.
- System-Schemas des geteilten Metastores nur aus dem State nehmen, nicht deaktivieren.
- Die NCC erst nach dem Workspace löschen.

Alternativ: Workflow `teardown` (`scope=all`).

## 4. Offene Themen (priorisiert)

| # | Thema | Was zu tun ist | Hinweise |
| --- | --- | --- | --- |
| 1 | **prd-Release** | Nach dem Hochfahren von dev und tst: Tag `v0.1.0` setzen (`git tag -a v0.1.0 -m … && git push origin v0.1.0`). Die Infra-Freigabe vor der Bundles-Freigabe erteilen. | Skill `prepare-release`. Das prd-Environment erlaubt nur Tags `v*`. |
| 2 | **Zweite Promotion** dev → tst | Draft-PR #7 (`lower_clean`, Wheel `0.1.0 → 0.2.0`): Branch aktualisieren („Update branch“, das Ruleset verlangt einen aktuellen Stand), auf „Ready“ setzen, mergen, dann tst freigeben. | Zeigt die Versionierung der zentralen Bibliothek über die Stages. |
| 3 | **Privater Serverless-Pfad (NCC)** | Prüfen, ob die NCC-Private-Endpoints nach der Propagation (laut Doku bis zu 24 h) greifen. Danach `storage_public_fallback = false` (Stacks `azure` und `sources`) und `sql_public_access = false` setzen, neu deployen und testen. | Heute löste Serverless trotz `ESTABLISHED` alles öffentlich auf. Probe-Notebook-Idee im Journal. Das ist die Kernanforderung „ADLS privat“. |
| 4 | **Lernpfad Ingestion** | A2: Lakeflow Connect query-based (inkrementell, Cursor `updated_at`). B: CDC-Gateway (klassisch, braucht eine Cluster Policy und läuft dauerhaft; Change Tracking ist in der Quelle schon aktiv). | Metadaten-Feld `load.type`/`ingestion_mode`. Der Generator unterstützt bisher nur `full_load` und `autoloader`. |
| 5 | **Identitäten: AIM** | Automatic Identity Management ist im (geteilten) Account aus 2024 nicht aktiv. Deshalb gibt es Databricks-Account-Gruppen gleichen Namens. Entscheidung mit den Kollegen: AIM einschalten, dann entfallen die Gruppen im Account-Stack. | Account-weite Einstellung. |
| 6 | **ADRs** | 0001 Region, 0002 Catalog-Topologie und Binding, 0003 Metadaten YAML + Python for Bundles, 0004 Trunk-based + Gates, 0005 Ingestion-Pfade, 0006 Netzwerk inkl. Fallback. | `docs/adr/0000-template.md` |
| 7 | **Monitoring** | Die Ops-Views (`<env>_platform.ops`) existieren. Noch offen: AI/BI-Dashboard „Platform Ops“, Databricks-Budget in der Account Console, Azure-Budget (`budget_contact_emails` setzen). | — |
| 8 | **Teardown-Workflow testen** | Heute lief der Abbau lokal. Der Workflow `teardown` ist angepasst, wurde aber noch nicht ausgeführt. | — |
| 9 | Optional | Lakebase-Modul (Metadaten-UI), OneLake-Federation-Demo, zweiter dev-Workspace als Serverless Workspace. | Solution Design Kap. 11 |

## 5. Bekannte Eigenheiten beim nächsten Aufbau

- **Neuaufbau eines privaten Pfads:** Die NCC-Private-Endpoints entstehen neu, also gilt die
  Propagationszeit wieder. Der Fallback sorgt dafür, dass trotzdem alles läuft.
- **Azure SQL** liegt in **Germany West Central** (West Europe ist für SQL in dieser Subscription
  gesperrt), im Free Offer mit Auto-Pause. Der erste Zugriff dauert 1–3 Minuten.
- **Serverless „Standard“-Modus:** Jeder Job startet 4–6 Minuten verzögert. Zum Iterieren in
  `metadata/environments/dev.yml` `PERFORMANCE_OPTIMIZED` setzen.
- **Gruppen-Mitgliedschaft** wird in Databricks gecacht. Neue Rechte greifen nach einigen Minuten.
- **`main` ist geschützt:** nur per PR mit grünen Checks (`python`, `terraform`, `secrets`).
- **Geteilter Metastore:** Für metastore-weite Objekte immer `databricks_grant` (nicht-autoritativ)
  verwenden, nie `databricks_grants`. Sonst überschreibt man die Grants anderer Stages oder Kollegen.

## 6. Komplett aufräumen (nur wenn der PoC endgültig vorbei ist)

1. Alle Stages abbauen (Abschnitt 3).
2. `cd infra/terraform/account && terraform destroy`. Vorher den Metastore-Owner bewusst zurück auf
   `enrico-goerlitz-uc-admins` setzen.
3. `cd infra/terraform/bootstrap && GITHUB_TOKEN=$(gh auth token) terraform destroy`. Damit
   verschwinden auch die Entra-SPs, die Gruppen und der tfstate-Storage.
