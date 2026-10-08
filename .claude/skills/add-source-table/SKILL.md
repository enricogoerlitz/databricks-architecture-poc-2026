---
name: add-source-table
description: Neue Quelltabelle oder Quelle in die metadata-driven Ingestion (Source → Bronze → Silver) aufnehmen. Verwenden, wenn jemand eine Tabelle/Datei-Quelle integrieren, SCD-Typ, Keys, Transformationen oder Expectations für eine Tabelle festlegen will.
---

# Neue Quelltabelle aufnehmen

Es wird **nur YAML** geändert, kein Job- oder Pipeline-Code. Jobs und Pipelines entstehen beim
Deploy aus `metadata/`.

1. Datei wählen: bestehende Quelle `metadata/sources/<quelle>.yml` oder neue Datei, deren
   Dateiname `source.name` entspricht.
2. Tabelle unter `tables:` ergänzen. Pflichtfelder: `name` (snake_case), `keys`, bei SQL zusätzlich
   `source_object` (`schema.tabelle`). Ladeart `load.type: full` (Standard) oder `incremental`
   (Lernpfad). Für Silver `scd_type` 1 oder 2, optional `track_history_columns`, `transforms`
   (`clean_string`, `normalize_email`, `parse_date_multi`, `lower_clean`) und `expectations`
   (`drop|warn|fail`).
   Keys nicht transformieren.
3. Neue Transformationsfunktion nötig? In `src/dbxpoc_common` (`text.py` + `transforms.py` +
   `REGISTRY`), Test ergänzen, Version in `pyproject.toml` erhöhen und im JSON Schema in
   `metadata/schema/source.schema.json` unter `fn` aufnehmen.
4. Prüfen:
   ```bash
   uv run python -m tools.metadata validate
   uv run python -m tools.metadata render --env dev | less
   uv run pytest -q
   ```
5. Optional persönlich testen: `cd bundles/ingestion && databricks bundle deploy -t personal`.
   Das geht erst nach Rückfrage, weil es Kosten erzeugt.
6. Branch `feat/<quelle>-<tabelle>`, PR mit Checkliste. Commit und Push erst nach Freigabe.

Keine Secrets in Metadaten: Verbindungen werden nur per Namen referenziert (`connection`).
