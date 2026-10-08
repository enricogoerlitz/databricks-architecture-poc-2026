# metadata/

Source of Truth für die metadata-driven Pipelines. Hier stehen **keine Secrets**, nur Referenzen
auf Connections und Scopes.

| Pfad | Inhalt |
| --- | --- |
| `sources/<quelle>.yml` | Quelle und Tabellen: Ladeart, Keys, Silver-SCD-Typ, Transformationen, Expectations |
| `environments/<env>.yml` | Stage-Werte: Catalogs, Schedules (pausiert/aktiv), Performance-Modus |
| `schema/*.schema.json` | JSON Schemas; werden in pre-commit und CI geprüft |

Daraus entsteht beim `bundle deploy` (Bundle `ingestion`) je Quelle:
- ein Job `ingest_<quelle>`: für SQL Full Load per `for_each` → Silver-Pipeline, für Dateien die
  Pipeline mit File-Arrival-Trigger,
- eine Silver-Pipeline (`AUTO CDC` bzw. `AUTO CDC FROM SNAPSHOT`).

```bash
uv run python -m tools.metadata validate
uv run python -m tools.metadata render --env dev
```

`${env}` in String-Werten wird je Stage ersetzt. Neue Tabelle anlegen: Skill
[`add-source-table`](../.claude/skills/add-source-table/SKILL.md).
