-- 04_sellers_regions_customers.sql
-- Exploration queries behind the seller, state and monthly views. Source: olist.order_analysis.
-- A-B: seller late rates and concentration | C-D: states | P5: promise variation within a state | P6: RJ vs SP vs other by month.
-- Run each query separately.

-- A: late rate by seller, single-seller orders only, 30+ orders
SELECT
  main_seller_id AS seller_id,
  COUNT(*) AS orders,
  ROUND(100 * AVG(CAST(is_late AS INT64)), 2) AS late_pct,
  ROUND(AVG(review_score), 3) AS avg_review_score,
  ROUND(AVG(promised_days), 1) AS avg_promised_days
FROM `olist.order_analysis`
WHERE n_sellers = 1
GROUP BY main_seller_id
HAVING COUNT(*) >= 30
ORDER BY late_pct DESC
LIMIT 50;

-- B: coverage of A, and concentration of lateness
WITH per_seller AS (
  SELECT main_seller_id, COUNT(*) AS orders,
         SUM(CAST(is_late AS INT64)) AS late_orders
  FROM `olist.order_analysis`
  WHERE n_sellers = 1
  GROUP BY 1
)
SELECT
  (SELECT COUNTIF(n_sellers = 1) FROM `olist.order_analysis`) AS single_seller_orders,
  (SELECT COUNT(*) FROM `olist.order_analysis`) AS all_orders,
  COUNT(*) AS sellers_total,
  COUNTIF(orders >= 30) AS sellers_30plus,
  SUM(IF(orders >= 30, orders, 0)) AS orders_in_30plus,
  SUM(IF(orders >= 30, late_orders, 0)) AS late_in_30plus,
  SUM(late_orders) AS late_single_seller
FROM per_seller;

-- C: by customer state
SELECT
  customer_state,
  COUNT(*) AS orders,
  ROUND(100 * AVG(CAST(is_late AS INT64)), 2) AS late_pct,
  ROUND(AVG(promised_days), 1) AS avg_promised_days,
  ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
  ROUND(AVG(review_score), 3) AS avg_review_score,
  ROUND(AVG(freight_total), 2) AS avg_freight,
  ROUND(100 * AVG(CAST(seller_state = customer_state AS INT64)), 1) AS pct_same_state
FROM `olist.order_analysis`
GROUP BY customer_state
ORDER BY orders DESC;

-- D: where the late orders sit, by state
SELECT
  customer_state,
  SUM(CAST(is_late AS INT64)) AS late_orders,
  ROUND(100 * SUM(CAST(is_late AS INT64)) / SUM(SUM(CAST(is_late AS INT64))) OVER (), 2) AS pct_of_all_late
FROM `olist.order_analysis`
GROUP BY customer_state
ORDER BY late_orders DESC;


-- P5: how much does the promise vary within a state?
SELECT customer_state, COUNT(*) AS orders,
  ROUND(AVG(promised_days), 1) AS mean_prom,
  ROUND(STDDEV(promised_days), 1) AS sd_prom,
  APPROX_QUANTILES(promised_days, 100)[OFFSET(10)] AS p10_prom,
  APPROX_QUANTILES(promised_days, 100)[OFFSET(90)] AS p90_prom,
  ROUND(STDDEV(delivery_days), 1) AS sd_deliv,
  ROUND(CORR(promised_days, delivery_days), 2) AS corr_prom_deliv
FROM `olist.order_analysis`
GROUP BY 1 ORDER BY orders DESC LIMIT 8;

-- P6: is the Nov 2017 / Feb-Mar 2018 lateness spike concentrated in RJ?
SELECT DATE_TRUNC(DATE(purchase_ts), MONTH) AS purchase_month,
  COUNTIF(customer_state = 'RJ') AS rj_orders,
  ROUND(100 * AVG(IF(customer_state = 'RJ', CAST(is_late AS INT64), NULL)), 1) AS rj_late_pct,
  COUNTIF(customer_state = 'SP') AS sp_orders,
  ROUND(100 * AVG(IF(customer_state = 'SP', CAST(is_late AS INT64), NULL)), 1) AS sp_late_pct,
  COUNTIF(customer_state NOT IN ('RJ', 'SP')) AS other_orders,
  ROUND(100 * AVG(IF(customer_state NOT IN ('RJ', 'SP'), CAST(is_late AS INT64), NULL)), 1) AS other_late_pct
FROM `olist.order_analysis`
WHERE purchase_ts >= '2017-01-01'
GROUP BY 1 ORDER BY 1;
