# bundles/

Declarative Automation Bundles (früher Databricks Asset Bundles). Je Bundle gibt es die Targets
`personal` (Entwicklung, `mode: development`), `dev`, `tst` und `prd` (`mode: production`,
`run_as` = Deploy-SP der Stage).

| Bundle | Inhalt | Abhängigkeiten |
| --- | --- | --- |
| [`platform/`](platform/) | Schemas `<env>_platform.{meta,libs,functions,ops}`, Volume `libs.wheels`, Jobs `seed_sources` (simuliert Quell-Team) und `platform_setup` (Federation-Connection, UC Functions, Ops-Views) | Terraform `databricks`-Stack |
| [`ingestion/`](ingestion/) | **aus `metadata/` generiert** (Python for Bundles): Schemas, Silver-Pipelines, Jobs `ingest_<quelle>`, `publish_metadata` | `platform` (Wheel, Foreign Catalog) |
| [`domain_sales/`](domain_sales/) | Gold (SQL auf Serverless Warehouse), Job `gold_sales` mit Table Update Trigger auf Silver | `ingestion` (Silver-Tabellen) |

**Deploy-Reihenfolge:** `platform` → Wheel hochladen → `seed_sources` → `platform_setup` →
`ingestion` → `publish_metadata` → `ingest_*` laufen lassen → `domain_sales`. Der Table Update
Trigger von `gold_sales` verlangt, dass die Silver-Tabellen schon existieren. Siehe `.github/workflows/_stage-bundles.yml`.

```bash
cd bundles/ingestion
databricks bundle validate -t personal     # Host aus Profil/DATABRICKS_HOST
databricks bundle deploy -t personal       # eigene Kopie im dev-Workspace ([dev <user>] …)
```

Workspace-URLs stehen nicht im Repo. Die CLI nimmt `DATABRICKS_HOST` bzw. das Profil.
