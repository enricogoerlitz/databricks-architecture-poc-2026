---
applyTo: "bundles/**/*.yml"
---
- Keine Workspace-URLs oder IDs eintragen (Host kommt aus `DATABRICKS_HOST`/Profil).
- Schema-Namen über `${resources.schemas.<key>.name}` referenzieren (Präfix im Modus development).
- Jobs/Pipelines serverless, mit Tags `project`, `env`; Ingestion-Ressourcen nicht von Hand
  anlegen, sondern über `metadata/` generieren.
- Danach `databricks bundle validate -t personal`.
