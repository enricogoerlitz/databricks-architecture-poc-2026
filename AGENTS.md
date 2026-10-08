# AGENTS.md

Anweisungen für AI-Coding-Agents (Claude Code, Copilot, Codex, Cursor, …). Single Source of Truth;
`CLAUDE.md` und `.github/copilot-instructions.md` verweisen nur hierher. Der nächstgelegene
`AGENTS.md` gilt (z. B. [`infra/AGENTS.md`](infra/AGENTS.md)).

## Projekt

Enterprise-PoC für Azure Databricks: Unity Catalog mit Catalogs je Stage, privater Storage,
serverless Compute, metadata-driven Ingestion (Source → Bronze → Silver), Custom Gold,
CI/CD mit GitHub Actions (OIDC) über `dev → tst → prd`. Daten sind bewusst simpel.
Architektur und Begründungen: [`docs/architecture/solution-design.md`](docs/architecture/solution-design.md).
Sprache: Deutsch, Fachbegriffe Englisch.

## Verzeichnisindex

| Ordner | Zweck |
| --- | --- |
| [`infra/`](infra/README.md) | Terraform: Bootstrap, Account, Stacks `azure` → `sources` → `databricks`, Module, Skripte |
| [`bundles/`](bundles/README.md) | Declarative Automation Bundles: `platform`, `ingestion` (aus Metadaten generiert), `domain_sales` |
| [`src/`](src/README.md) | Python-Paket `dbxpoc_common` (zentrale Silver-Funktionen, Wheel) |
| [`metadata/`](metadata/README.md) | Metadaten der Quellen/Tabellen + JSON Schemas + Stage-Werte |
| [`tools/`](tools/README.md) | Metadaten-CLI (`validate`, `render`) |
| [`tests/`](tests/README.md) | pytest (Bibliothek, Generator, Metadaten) |
| [`docs/`](docs/README.md) | Architektur, ADRs (MADR), Specs, Runbooks |
| [`.github/`](.github/README.md) | Workflows, Copilot-Instructions, CODEOWNERS, PR-Template |
| [`.claude/skills/`](.claude/skills/README.md) | Agent Skills (auch von Copilot gelesen) |

## Befehle (lokal geprüft)

```bash
mise install                         # terraform, tflint, gitleaks, uv, databricks CLI (gepinnt)
uv sync                              # Python-Umgebung (.venv)
uv run pre-commit install            # Hooks einmalig aktivieren
make check                           # ruff, terraform fmt/validate, tflint, metadata, pytest
uv run python -m tools.metadata render --env dev   # generierte Jobs/Pipelines ansehen
make tf-plan ENV=dev STACK=azure     # Plan (braucht az login); apply nur nach Freigabe
make bundle-validate ENV=personal BUNDLE=ingestion # braucht Databricks-Login (Profil/Host)
```

## Konventionen

- **Stages:** `dev`, `tst`, `prd`. Catalogs `<env>_{bronze,silver,gold,platform}`; Azure-Namen
  `<typ>-dbxpoc-<env>-weu[-nn]` (siehe Design Kap. 4). Code ist stage-neutral; Stage-Werte nur in
  `metadata/environments/`, Bundle-Targets und Terraform-Variablen-Maps.
- **Keine IDs im Repo** (Tenant, Subscription, Account): nur Platzhalter; echte Werte in GitHub
  Secrets bzw. `.env.local` (gitignored).
- **Neue Quelltabelle** = nur YAML in `metadata/sources/` (Skill `add-source-table`), kein Job-Code.
- **Python:** ruff (Zeilenlänge 120), Typ-Hints, reine Funktionen in `dbxpoc_common.text`,
  Spark-Varianten in `transforms`. Notebooks als `.py` im Databricks-Source-Format.
- **Terraform:** ein State je Stage und Stack; Provider-Versionen gepinnt; keine Secrets im State
  (write-only/ephemeral).
- **Doku:** Wer Struktur ändert, aktualisiert die README des Ordners und diesen Index.

## Git-Workflow

Trunk-based: kurzlebige Branches `feat/…`, `fix/…`, `docs/…` → PR → `main` (deployt dev, dann tst
nach Approval) → Release-Tag `vX.Y.Z` (deployt prd nach Approval). Commits im Stil
Conventional Commits (`feat(ingestion): …`). Kein direkter Commit auf `main`.

## Sicherheits- und Freigaberegeln

- **Nie Secrets** in Code, Doku, Logs oder Chat. Keine Passwörter ausgeben. Nie `.env*`, `*.tfvars`,
  State-Dateien stagen.
- **Vor Commit, Push, `terraform apply/destroy`, `bundle deploy/destroy`, Job-Runs und allem, was
  Kosten erzeugt: den Menschen fragen** (was passiert, Kosten, wie rückgängig).
- **Nie direkt nach `prd`** deployen; prd nur über Tag + GitHub Environment Approval.
- Keine AI-Co-Author-Trailer in Commits; Autor in Dokumenten ist ein Mensch.

## Definition of Done (für Agent-Änderungen)

1. `make check` bzw. `uv run pre-commit run --all-files` grün.
2. Betroffene READMEs/Doku und ggf. dieser Index aktualisiert; Entscheidungen als ADR.
3. Keine Secrets/IDs im Diff (gitleaks grün).
4. Änderung kurz zusammengefasst; Commit/Push erst nach Freigabe.
