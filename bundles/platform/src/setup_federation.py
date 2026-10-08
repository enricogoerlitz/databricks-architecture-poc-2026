# Databricks notebook source
# MAGIC %md
# MAGIC # Federation: UC Connection + Foreign Catalog
# MAGIC
# MAGIC Die Connection wird **hier** (und nicht in Terraform) angelegt, damit das SQL-Passwort nie im
# MAGIC Terraform-State landet. `secret('kv', …)` löst die Werte aus dem Key-Vault-backed Scope auf.
# MAGIC Rotation: Secret im Key Vault ändern → dieses Notebook erneut ausführen.

# COMMAND ----------

from databricks.sdk import WorkspaceClient

dbutils.widgets.text("env", "dev")
dbutils.widgets.text("database", "sqldb-salesdb")
env = dbutils.widgets.get("env")
database = dbutils.widgets.get("database")
connection = f"conn_{env}_salesdb"
foreign_catalog = f"{env}_src_salesdb"

options = """
  host secret('kv', 'salesdb-host'),
  port '1433',
  user secret('kv', 'salesdb-user'),
  password secret('kv', 'salesdb-password'),
  trustServerCertificate 'false'
"""
w = WorkspaceClient()
exists = any(c.name == connection for c in w.connections.list())
if exists:
    spark.sql(f"ALTER CONNECTION {connection} OPTIONS ({options})")
    print(f"Connection {connection} aktualisiert (Rotation)")
else:
    spark.sql(
        f"CREATE CONNECTION {connection} TYPE sqlserver OPTIONS ({options}) COMMENT 'Azure SQL salesdb ({env}), privat über NCC'"
    )
    print(f"Connection {connection} angelegt")

spark.sql(
    f"CREATE FOREIGN CATALOG IF NOT EXISTS {foreign_catalog} USING CONNECTION {connection} "
    f"OPTIONS (database '{database}')"
)
# Kommentare separat (COMMENT-Klausel ist in CREATE FOREIGN CATALOG nicht an jeder Stelle erlaubt)
spark.sql(f"COMMENT ON CONNECTION {connection} IS 'Azure SQL salesdb ({env}); Secrets aus Scope kv'")
spark.sql(f"COMMENT ON CATALOG {foreign_catalog} IS 'Zero-Copy-Sicht auf die Quelle (Lakehouse Federation)'")

# Engineers der Stage dürfen die Quelle live abfragen (Zero-Copy-Vergleich zu Bronze)
spark.sql(f"GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG {foreign_catalog} TO `sg-dbxpoc-{env}-engineers`")

# COMMAND ----------

# Hinweis: Das Isolieren/Binden des Foreign Catalogs an die Stage-Workspaces passiert NICHT hier –
# der Laufzeit-Token eines Jobs darf UpdateCatalog nicht aufrufen. Das übernimmt der Deploy-Schritt
# (`databricks catalogs update <catalog> --isolation-mode ISOLATED`, siehe _stage-bundles.yml).

# Smoke-Test: Abfrage live gegen die Quelle
display(spark.sql(f"SELECT COUNT(*) AS customers FROM {foreign_catalog}.dbo.customers"))
