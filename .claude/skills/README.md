# Agent Skills

Wiederkehrende Abläufe als [Agent Skills](https://agentskills.io/specification). `.claude/skills/`
wird von Claude Code **und** GitHub Copilot gelesen.

| Skill | Wann |
| --- | --- |
| `add-source-table` | neue Tabelle oder Quelle in die metadata-driven Ingestion aufnehmen |
| `prepare-release` | Release nach tst/prd vorbereiten (Checks, Version, Tag) |
| `teardown-env` | Stage abbauen (Workloads oder komplett) |

Offizielle Databricks-Skills lassen sich ergänzen mit
`databricks aitools install --scope project`.
