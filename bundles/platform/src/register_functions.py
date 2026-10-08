# Databricks notebook source
# MAGIC %md
# MAGIC # UC Functions registrieren
# MAGIC
# MAGIC - **Python UDFs** nutzen dieselbe Logik wie die Pipelines – aus dem Wheel `dbxpoc_common`
# MAGIC   im UC Volume (`ENVIRONMENT (dependencies …)`). Dadurch gibt es die Funktion genau einmal.
# MAGIC - **SQL UDF** als Beispiel für einfache Ausdrücke (z. B. Maskierung)
# MAGIC
# MAGIC Weil die Catalogs an alle Workspaces der Stage gebunden sind, sind die Funktionen dort überall
# MAGIC nutzbar: `SELECT dev_platform.functions.clean_string('  a   b ')`.

# COMMAND ----------

dbutils.widgets.text("schema", "dev_platform.functions")
dbutils.widgets.text("wheel", "")
dbutils.widgets.text("lib_version", "0.0.0")
schema = dbutils.widgets.get("schema")
wheel = dbutils.widgets.get("wheel")
version = dbutils.widgets.get("lib_version")

python_udfs = {
    "clean_string": ("s STRING", "STRING", "Trimmt und reduziert Mehrfach-Leerzeichen"),
    "normalize_email": ("s STRING", "STRING", "E-Mail in Kleinbuchstaben, ungültig -> NULL"),
    "parse_date_multi": ("s STRING", "DATE", "Datum aus ISO-, DE-, US- oder Kompaktformat"),
}

for fn, (args, returns, doc) in python_udfs.items():
    spark.sql(f"""
        CREATE OR REPLACE FUNCTION {schema}.{fn}({args})
        RETURNS {returns}
        LANGUAGE PYTHON
        COMMENT '{doc} (dbxpoc_common {version})'
        ENVIRONMENT (dependencies = '["{wheel}"]', environment_version = 'None')
        AS $$
from dbxpoc_common.text import {fn}
return {fn}(s)
        $$
    """)
    print(f"registriert: {schema}.{fn}")

spark.sql(f"""
    CREATE OR REPLACE FUNCTION {schema}.mask_email(email STRING)
    RETURNS STRING
    COMMENT 'Maskiert E-Mail-Adressen (SQL UDF, kann als Column Mask dienen)'
    RETURN regexp_replace(email, '^(.).*(@.*)$', '$1***$2')
""")
print(f"registriert: {schema}.mask_email")

# COMMAND ----------

display(
    spark.sql(f"""
    SELECT {schema}.clean_string('  Anna    Müller ') AS clean,
           {schema}.normalize_email(' ANNA@Example.COM ') AS email,
           {schema}.parse_date_multi('01.02.2026') AS d,
           {schema}.mask_email('anna@example.com') AS masked
""")
)
