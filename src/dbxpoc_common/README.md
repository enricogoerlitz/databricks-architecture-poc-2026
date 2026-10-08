# dbxpoc-common

Zentrales Python-Paket mit wiederverwendbarer Silver-Logik. Es wird als Wheel gebaut und je
Stage in das UC Volume `/Volumes/<env>_platform/libs/wheels/` hochgeladen. Pipelines und Jobs
binden es über `environment.dependencies` ein, UC Python UDFs über `ENVIRONMENT (dependencies …)`.

| Modul | Inhalt | Läuft wo |
| --- | --- | --- |
| `text` | reine Python-Funktionen (`clean_string`, `normalize_email`, `parse_date_multi`) | überall, auch in UC Python UDFs |
| `transforms` | dieselben Funktionen als PySpark-Column-Ausdrücke + `REGISTRY` | Pipelines/Jobs |
| `scd` | `TableConfig` (Beispiel für Klassen) | Pipelines |

```bash
uv build --wheel src/dbxpoc_common -o dist   # baut dist/dbxpoc_common-<ver>-py3-none-any.whl
uv run pytest tests/                          # Unit-Tests
```

**Versionierung:** SemVer in `pyproject.toml`. Jede Änderung am Code braucht eine neue Version
(serverless cacht Umgebungen je Version). Breaking Changes → neue Major-Version, UDFs mit `_v2`.
