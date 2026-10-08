# Databricks Architecture PoC 2026

Enterprise-PoC für **Azure Databricks**:
- Unity Catalog mit Catalogs je Stage
- Workspace public, Storage privat
- Serverless Compute
- Metadata-driven Ingestion ohne ADF
- Wiederverwendbare Funktionen (Wheel + UC Functions)
- CI/CD mit GitHub Actions und OIDC über `dev → tst → prd`

- Architektur und Entscheidungen: [docs/architecture/solution-design.md](docs/architecture/solution-design.md)
- Einstieg für Menschen und Agents: [AGENTS.md](AGENTS.md)
- Aufbau-Protokoll mit Gotchas: [docs/runbooks/deployment-journal.md](docs/runbooks/deployment-journal.md)

```bash
mise install && uv sync && make check
```

> PoC: Ressourcen werden nach Gebrauch abgebaut ([teardown](.github/workflows/teardown.yml)).
