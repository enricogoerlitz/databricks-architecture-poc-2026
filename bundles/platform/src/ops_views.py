# Databricks notebook source
# MAGIC %md
# MAGIC # Ops-Views auf System Tables
# MAGIC
# MAGIC Kleine, abfragbare Sichten für Kosten und Job-Läufe der Stage (Filter über Tag `env`).
# MAGIC Voraussetzung: der Deploy-SP darf `system.billing` und `system.lakeflow` lesen (Account-Stack).

# COMMAND ----------

dbutils.widgets.text("schema", "dev_platform.ops")
dbutils.widgets.text("env", "dev")
schema = dbutils.widgets.get("schema")
env = dbutils.widgets.get("env")

spark.sql(f"""
CREATE OR REPLACE VIEW {schema}.cost_by_day_and_product
COMMENT 'Kosten (Listenpreis) je Tag und Produkt für Stage {env}'
AS
SELECT u.usage_date,
       u.billing_origin_product,
       u.custom_tags['env']               AS env,
       SUM(u.usage_quantity)              AS dbus,
       SUM(u.usage_quantity * p.pricing.default) AS list_cost
FROM system.billing.usage u
JOIN system.billing.list_prices p
  ON u.sku_name = p.sku_name
 AND u.usage_start_time >= p.price_start_time
 AND (p.price_end_time IS NULL OR u.usage_start_time < p.price_end_time)
WHERE u.custom_tags['project'] = 'dbxpoc' AND u.custom_tags['env'] = '{env}'
GROUP BY ALL
""")

spark.sql(f"""
CREATE OR REPLACE VIEW {schema}.job_runs
COMMENT 'Job-Läufe der letzten 7 Tage (Workspace dieser Stage)'
AS
SELECT j.name AS job_name, r.run_id, r.period_start_time, r.period_end_time, r.result_state,
       timestampdiff(SECOND, r.period_start_time, r.period_end_time) AS duration_s
FROM system.lakeflow.job_run_timeline r
JOIN system.lakeflow.jobs j USING (workspace_id, job_id)
WHERE r.period_start_time >= current_date() - INTERVAL 7 DAYS
""")
print(f"Views in {schema} angelegt")
