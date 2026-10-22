---
datum: 2026-10-22
autor: Enrico Goerlitz
quelle: docs/initializing/02-übergabe-v1.md
---

# Lernplan — den Prozess selbst durchgehen

**Arbeitsweise:** Du führst die Schritte selbst aus, ich erkläre das *Warum*, beantworte Fragen
und helfe bei Fehlern. Nach jedem Schritt hakst du ihn ab und sagst mir Bescheid. Ich gebe dir dann
die nächsten 2–3 Punkte.

**Ausgangslage (2026-10-22):** Die **dev-Infrastruktur** ist über die Pipeline neu aufgebaut
(Workflow `infra-deploy`, dev). Noch ohne Bundles und Daten, tst und prd existieren nicht.
Bootstrap und Account-Stack bestehen weiter.

> **Gotcha vorab:** Nach `az login` kann eine *andere* Subscription aktiv sein. Prüfen mit
> `az account show --query name -o tsv`, korrekt ist die PoC-Subscription. Lokal ist sie in
> `.env.local` als `TF_VAR_subscription_id` gepinnt, `az`-Befehle nutzen aber die aktive.
> Umstellen: `az account set --subscription <name>`.

---

## Block A — Orientierung (nur schauen, nichts kostet)

- [ ] **A1 Lokales Setup und Databricks-Login**
  - `mise install && uv sync && uv run pre-commit install && make check`
  - Workspace-URL: `make tf-init ENV=dev STACK=azure && make ws-host`
  - Profil anlegen: `databricks auth login --host <url> --profile dbxpoc-dev`
  - *Lernziel:* Werkzeugkette, pinned Versions, wie die CLI sich gegenüber Entra anmeldet.
- [ ] **A2 Tour durch das, was Terraform gebaut hat**
  - Azure-Portal: RG `rg-dbxpoc-dev-weu`, Managed RG je Workspace, UC-Storage → *Networking*
    (Firewall, Private Endpoints), Key Vault, NAT Gateway.
  - Account Console: *Workspaces* (dev-01, dev-02), *Catalog* (Metastore, Zuweisung),
    *Security → Network connectivity configurations* (NCC + PE-Regeln), *User management*
    (Gruppen, SPs).
  - Workspace dev-01 und dev-02 → *Catalog*: `dev_bronze|silver|gold|platform`. Das Binding prüfst
    du unter *Catalog → ⚙ → Workspaces*: dev-02 hat bronze/silver nur lesend.
  - *Lernziel:* Account → Metastore → Catalog → Binding; Workspace public, Storage privat.
- [ ] **A3 Code lesen, der gleich deployt wird**
  - `metadata/sources/*.yml`, dann `uv run python -m tools.metadata render --env dev | less`.
  - `bundles/*/databricks.yml` (Targets `personal`/`dev`/`tst`/`prd`, `run_as`, `root_path`).
  - `bundles/ingestion/src/silver_pipeline.py` (AUTO CDC FROM SNAPSHOT).
  - *Lernziel:* Wie aus YAML Jobs und Pipelines werden. Was die Targets unterscheidet.

## Block B — Erstes Deployment in dev (selbst ausgelöst)

- [ ] **B1 Bundles per Pipeline nach dev**
  - `gh workflow enable bundles-deploy.yml && gh workflow run bundles-deploy.yml -f env=dev`
  - Lauf im GitHub-UI verfolgen. Die Reihenfolge der Steps erklärt sich aus `bundles/README.md`.
  - *Kosten:* einige Serverless-DBU (Seed, Setup, Ingest, Gold).
  - *Lernziel:* OIDC-Login des Deploy-SP, Build einmal, Deploy, Erstbefüllung.
- [ ] **B2 Daten und SCD2 selbst beobachten**
  - SQL-Editor: Bronze vs. Silver vergleichen (bereinigte E-Mails, Datumsformate, Expectation
    `amount >= 0`).
  - Job `seed_sources` mit `round=2` starten → `ingest_salesdb` starten → Historie in
    `dev_silver.salesdb.customers` (`__START_AT`/`__END_AT`) ansehen. `gold_sales` und
    `ingest_crm_files` starten über ihre Trigger von selbst.
  - Pipeline-Graph, Expectation-Metriken, Lineage im Catalog Explorer.
  - *Lernziel:* Full Load + Snapshot-CDC, Trigger, Lineage.
- [ ] **B3 Eigener Entwicklungs-Loop (personal)**
  - Eine Kleinigkeit in den Metadaten ändern, z. B. eine Expectation.
  - `cd bundles/ingestion && databricks bundle deploy -t personal -p dbxpoc-dev`, dann den eigenen
    Job laufen lassen. Die Schemas heißen dann `dev_<user>_…`.
  - *Lernziel:* Isoliert entwickeln, ohne die geteilte dev-Stage zu verändern.

## Block C — Änderung durch die Stages fördern

- [ ] **C1 PR #7 (`lower_clean`, Wheel 0.2.0)**
  - Branch aktualisieren, „Ready for review“, CI grün, Squash-Merge → dev deployt automatisch.
  - Prüfen: `SELECT dev_platform.functions.lower_clean(' SHIPPED ')`, Status in Silver.
  - *Lernziel:* Versionierte Library über Stages, Ruleset, trunk-based.
- [ ] **C2 tst aufbauen und promoten**
  - `gh workflow run infra-deploy.yml -f env=tst` → Freigabe im UI → danach
    `gh workflow run bundles-deploy.yml -f env=tst` → Freigabe.
  - Rechte prüfen: In tst bist du als Engineer nur lesend.
  - *Kosten:* zweite Stage im Leerlauf ca. 0,15 €/h.
- [ ] **C3 prd-Release + Rollback-Übung**
  - Skill `prepare-release`: Tag `v0.2.0` → Infra- und Bundles-Freigabe für prd.
  - Rollback: `gh workflow run bundles-deploy.yml --ref v0.1.0 -f env=prd` (falls vorhanden) oder
    eine bewusst kleine Änderung zurückrollen.
  - *Lernziel:* Tag-basierte Promotion, „getestet = deployt“, Rollback ohne Git-Eingriff.

## Block D — Offene Architekturthemen (vertiefen)

- [ ] **D1 Privater Serverless-Pfad:** Prüfen, ob NCC-PEs jetzt greifen (Probe-Notebook: DNS
  auflösen auf private IP?). Dann `storage_public_fallback = false` und `sql_public_access = false`
  setzen und verifizieren. *Kernanforderung „ADLS privat“.*
- [ ] **D2 Ingestion-Lernpfad:** A2 Lakeflow Connect query-based (inkrementell), B CDC-Gateway
  (klassisch, Cluster Policy, dauerhaft). Bewertung gegen Full Load.
- [ ] **D3 Governance:** Column Mask mit `dev_platform.functions.mask_email`, Row Filter,
  Rechte-Tests als Analyst (dev-02).
- [ ] **D4 Identitäten:** AIM im geteilten Account klären (mit Kollegen). Danach die Gruppen aus
  Entra statt aus dem Account-Stack.
- [ ] **D5 Monitoring:** Ops-Views abfragen, AI/BI-Dashboard „Platform Ops“, Budget in der
  Account Console.
- [ ] **D6 ADRs** schreiben (0001–0006, siehe Übergabe).

## Block E — Abbau

- [ ] Je Stage, nacheinander: `infra/scripts/teardown-stage.sh <env>`. Danach
  `gh workflow disable infra-deploy.yml bundles-deploy.yml`.

---

**Kosten im Blick:** dev im Leerlauf ca. 0,15 €/h (NAT, Private Endpoints). Läufe kosten
Serverless-DBU. Am Ende des Tages abbauen (Block E) oder bewusst stehen lassen.
