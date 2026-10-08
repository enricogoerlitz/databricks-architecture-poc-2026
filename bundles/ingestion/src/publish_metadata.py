# Databricks notebook source
# MAGIC %md
# MAGIC # Metadaten veröffentlichen
# MAGIC
# MAGIC Spiegelt die deployten Metadaten (Source of Truth: `metadata/` im Repo) als Delta-Tabellen
# MAGIC nach `<env>_platform.meta`. Damit sind sie per SQL abfragbar, z. B. für Monitoring.

# COMMAND ----------

import json
from datetime import datetime, UTC

dbutils.widgets.text("target_schema", "")
dbutils.widgets.text("metadata_json", "[]")
dbutils.widgets.text("git_sha", "unknown")

target_schema = dbutils.widgets.get("target_schema")
sources = json.loads(dbutils.widgets.get("metadata_json"))
git_sha = dbutils.widgets.get("git_sha")
now = datetime.now(UTC)

source_rows = [
    {
        "source": m["source"]["name"],
        "type": m["source"]["type"],
        "ingestion_mode": m["source"]["ingestion_mode"],
        "config_json": json.dumps(m["source"]),
        "git_sha": git_sha,
        "deployed_at": now,
    }
    for m in sources
]
table_rows = [
    {
        "source": m["source"]["name"],
        "table": t["name"],
        "load_type": t.get("load", {}).get("type", "full" if m["source"]["type"] == "sqlserver" else "files"),
        "keys": t["keys"],
        "scd_type": int(t.get("silver", {}).get("scd_type", 1)),
        "config_json": json.dumps(t),
        "git_sha": git_sha,
        "deployed_at": now,
    }
    for m in sources
    for t in m["tables"]
]

# COMMAND ----------

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {target_schema}")
spark.createDataFrame(source_rows).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{target_schema}.sources"
)
spark.createDataFrame(table_rows).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{target_schema}.tables"
)
print(f"{len(source_rows)} Quellen, {len(table_rows)} Tabellen nach {target_schema} geschrieben (git {git_sha})")
