-- Fulfillment Performance Analysis (Olist public e-commerce data, ~99K orders, 2016-2018)

-- 0. Load
CREATE OR REPLACE TABLE orders  AS SELECT * FROM read_csv_auto('olist_orders_dataset.csv');
CREATE OR REPLACE TABLE items   AS SELECT * FROM read_csv_auto('olist_order_items_dataset.csv');
CREATE OR REPLACE TABLE customers AS SELECT * FROM read_csv_auto('olist_customers_dataset.csv');
CREATE OR REPLACE TABLE sellers AS SELECT * FROM read_csv_auto('olist_sellers_dataset.csv');

-- 1. Data validation: row counts, duplicates, missing timestamps, out-of-order timestamps
CREATE OR REPLACE VIEW validation AS
SELECT
  COUNT(*)                                                     AS total_orders,
  COUNT(*) - COUNT(DISTINCT order_id)                          AS duplicate_order_ids,
  SUM(CASE WHEN order_status='delivered' AND order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS delivered_missing_date,
  SUM(CASE WHEN order_delivered_carrier_date < order_purchase_timestamp THEN 1 ELSE 0 END)           AS carrier_before_purchase,
  SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END)      AS customer_before_carrier
FROM orders;

-- 2. Clean delivered-order base table with stage durations (CTE)
CREATE OR REPLACE TABLE delivered AS
WITH base AS (
  SELECT o.*, c.customer_state,
         date_diff('hour', order_purchase_timestamp, order_approved_at)/24.0            AS approve_days,
         date_diff('hour', order_approved_at, order_delivered_carrier_date)/24.0        AS handling_days,
         date_diff('hour', order_delivered_carrier_date, order_delivered_customer_date)/24.0 AS transit_days,
         date_diff('hour', order_purchase_timestamp, order_delivered_customer_date)/24.0 AS total_days,
         order_delivered_customer_date::DATE > order_estimated_delivery_date::DATE      AS is_late
  FROM orders o JOIN customers c USING (customer_id)
  WHERE order_status='delivered'
    AND order_delivered_customer_date IS NOT NULL
    AND order_delivered_carrier_date IS NOT NULL
    AND order_approved_at IS NOT NULL
)
SELECT * FROM base
WHERE handling_days >= 0 AND transit_days >= 0;   -- drop records that fail validation

-- 3. Network KPIs
CREATE OR REPLACE VIEW kpis AS
SELECT COUNT(*) AS delivered_orders,
       ROUND(100*AVG(CASE WHEN is_late THEN 0 ELSE 1 END),1) AS on_time_pct,
       ROUND(AVG(approve_days),2) AS avg_approve_days,
       ROUND(AVG(handling_days),2) AS avg_handling_days,
       ROUND(AVG(transit_days),2) AS avg_transit_days,
       ROUND(AVG(total_days),2) AS avg_total_days
FROM delivered;

-- 4. Monthly trend
CREATE OR REPLACE VIEW monthly AS
SELECT date_trunc('month', order_purchase_timestamp) AS month,
       COUNT(*) AS orders,
       ROUND(100*AVG(CASE WHEN is_late THEN 1 ELSE 0 END),1) AS late_pct,
       ROUND(AVG(total_days),1) AS avg_total_days
FROM delivered GROUP BY 1 ORDER BY 1;

-- 5. Where lateness concentrates: by customer state (min volume 500)
CREATE OR REPLACE VIEW by_state AS
SELECT customer_state, COUNT(*) AS orders,
       ROUND(100*AVG(CASE WHEN is_late THEN 1 ELSE 0 END),1) AS late_pct,
       ROUND(AVG(transit_days),1) AS avg_transit_days
FROM delivered GROUP BY 1 HAVING COUNT(*)>=500 ORDER BY late_pct DESC;

-- 6. Which stage drives late orders: late vs on-time stage durations
CREATE OR REPLACE VIEW stage_driver AS
SELECT is_late, COUNT(*) AS orders,
       ROUND(AVG(handling_days),2) AS handling_days,
       ROUND(AVG(transit_days),2) AS transit_days
FROM delivered GROUP BY 1;

-- 7. Seller handling: sellers missing the ship-by limit most often (min 100 items)
CREATE OR REPLACE VIEW seller_handling AS
WITH seller_items AS (
  SELECT i.seller_id, i.order_id,
         d.order_delivered_carrier_date > i.shipping_limit_date AS missed_ship_limit
  FROM items i JOIN delivered d USING (order_id)
)
SELECT seller_id, COUNT(*) AS items,
       ROUND(100*AVG(CASE WHEN missed_ship_limit THEN 1 ELSE 0 END),1) AS missed_limit_pct
FROM seller_items GROUP BY 1 HAVING COUNT(*)>=100 ORDER BY missed_limit_pct DESC;
