# tests/

pytest ohne Databricks-Zugriff: `uv run pytest -q`.

| Datei | Prüft |
| --- | --- |
| `test_text.py` | reine Funktionen aus `dbxpoc_common.text` |
| `test_scd.py` | `TableConfig` |
| `test_metadata.py` | Metadaten gültig; Generator erzeugt erwartete Jobs, Pipelines und Trigger je Stage; keine Secrets |
