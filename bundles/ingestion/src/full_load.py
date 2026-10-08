# Databricks notebook source
# MAGIC %md
# MAGIC # Full Load: Source → Bronze
# MAGIC
# MAGIC Generisches Notebook (Äquivalent zur Fabric/ADF *Copy Data Activity*). Wird vom Job
# MAGIC `ingest_<quelle>` per **for_each** je Tabelle aufgerufen.
# MAGIC
# MAGIC - liest die Quelltabelle über den **Foreign Catalog** (Lakehouse Federation, serverless über NCC)
# MAGIC - schreibt einen **vollständigen Snapshot** nach Bronze (`CREATE OR REPLACE TABLE`)
# MAGIC - vorherige Stände bleiben über Delta Time Travel abrufbar

# COMMAND ----------

dbutils.widgets.text("source_catalog", "")
dbutils.widgets.text("source_object", "")  # schema.tabelle in der Quelle, z. B. dbo.customers
dbutils.widgets.text("target_catalog", "")
dbutils.widgets.text("target_schema", "")
dbutils.widgets.text("target_table", "")

p = {
    k: dbutils.widgets.get(k).strip()
    for k in ("source_catalog", "source_object", "target_catalog", "target_schema", "target_table")
}
missing = [k for k, v in p.items() if not v]
if missing:
    raise ValueError(f"Fehlende Parameter: {missing}")

source = f"`{p['source_catalog']}`.{'.'.join(f'`{x}`' for x in p['source_object'].split('.'))}"
target = f"`{p['target_catalog']}`.`{p['target_schema']}`.`{p['target_table']}`"
print(f"{source}  ->  {target}")

# COMMAND ----------

spark.sql(
    f"""
    CREATE OR REPLACE TABLE {target}
    COMMENT 'Bronze Full Load aus {p["source_catalog"]}.{p["source_object"]}'
    TBLPROPERTIES ('dbxpoc.load_type' = 'full', 'delta.enableChangeDataFeed' = 'true')
    AS SELECT *, current_timestamp() AS _ingested_at FROM {source}
    """
)

rows = spark.table(target).count()
# Hinweis: dbutils.jobs.taskValues.set ist in for_each-Iterationen nicht erlaubt.
print(f"{rows} Zeilen geladen")
