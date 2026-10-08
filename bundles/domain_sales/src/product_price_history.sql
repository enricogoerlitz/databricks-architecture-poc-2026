-- Preis-Historie je Produkt (aus SCD2)
CREATE OR REPLACE VIEW IDENTIFIER(:gold_schema || '.product_price_history')
COMMENT 'Gold: Preis-Historie je Produkt (SCD2 aus Silver)'
AS
SELECT product_code, product_name, category, CAST(price AS DECIMAL(12,2)) AS price,
       __START_AT AS valid_since, __END_AT AS valid_until, __END_AT IS NULL AS is_current
FROM IDENTIFIER(:silver_catalog || '.crm_files.products');
