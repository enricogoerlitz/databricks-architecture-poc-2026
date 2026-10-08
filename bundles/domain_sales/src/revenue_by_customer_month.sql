-- Umsatz je Kunde und Monat (aktueller Kundenstand aus SCD2: __END_AT IS NULL)
CREATE OR REPLACE TABLE IDENTIFIER(:gold_schema || '.revenue_by_customer_month')
COMMENT 'Gold: Umsatz je Kunde und Monat (ohne stornierte/gelöschte Bestellungen)'
AS
SELECT
  c.customer_id,
  c.name                              AS customer_name,
  c.segment,
  date_trunc('MONTH', o.order_date)   AS month,
  COUNT(*)                            AS orders,
  SUM(o.amount)                       AS revenue
FROM IDENTIFIER(:silver_catalog || '.salesdb.orders') o
JOIN IDENTIFIER(:silver_catalog || '.salesdb.customers') c
  ON o.customer_id = c.customer_id AND c.__END_AT IS NULL
WHERE NOT o.is_deleted
  AND lower(o.status) <> 'cancelled'
  AND o.order_date IS NOT NULL
GROUP BY ALL;
