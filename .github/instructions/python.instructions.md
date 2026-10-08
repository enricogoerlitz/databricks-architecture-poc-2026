---
applyTo: "**/*.py"
---
- ruff (Zeilenlänge 120), Typ-Hints, Docstrings auf Deutsch.
- Wiederverwendbare Logik gehört nach `src/dbxpoc_common`: reine Python-Funktion in `text.py` und
  Spark-Variante in `transforms.py` (in `REGISTRY` eintragen), dazu ein Test in `tests/`.
- Notebooks (`bundles/**/src/*.py`) im Databricks-Source-Format; Parameter über `dbutils.widgets`.
- Secrets nur über `dbutils.secrets.get("kv", …)`, nie ausgeben.
- Lakeflow-Pipelines: `from pyspark import pipelines as dp`, `AUTO CDC` statt `APPLY CHANGES`.
