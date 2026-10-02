-- 05_outputs.sql
-- Builds the small output tables used by the Tableau dashboard and the write-up.
-- Source: olist.model_data only (96,470 delivered orders), so every table ties back to the same anchors:
--   96,470 orders | 6,534 late | 646 no review | item revenue 13,220,248.93
-- Run the whole file as one script, then run the RECONCILIATION query at the bottom (every row must say ok = TRUE).
--
-- Re-aggregating in Tableau: do NOT average the avg_score column across rows.
-- Use SUM(score_sum) / SUM(reviews) for a correct weighted average, and SUM(late_orders) / SUM(orders) for late %.
--
-- Export each table to CSV: run  SELECT * FROM `olist.out_xxx`  and use Save results -> CSV (local file).
-- All tables are tiny, far below the console's 10 MB limit.

-- 1. KPI anchors (one row) --------------------------------------------------------------------------
CREATE OR REPLACE TABLE `olist.out_kpi` AS
SELECT
  COUNT(*) AS orders,
  COUNTIF(is_late) AS late_orders,
  ROUND(100 * AVG(CAST(is_late AS INT64)), 2) AS late_pct,
  ROUND(SUM(items_price), 2) AS items_revenue,
  ROUND(SUM(freight_total), 2) AS freight_revenue,
  COUNTIF(review_score IS NULL) AS no_review,
  ROUND(AVG(IF(NOT is_late, review_score, NULL)), 3) AS avg_score_on_time,
  ROUND(AVG(IF(is_late, review_score, NULL)), 3) AS avg_score_late,
  ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
  ROUND(AVG(promised_days), 2) AS avg_promised_days,
  ROUND(AVG(gap_days), 2) AS avg_gap_days
FROM `olist.model_data`;

-- 2. Score by gap bucket, split by when the review was answered ("the cliff") -----------------------
CREATE OR REPLACE TABLE `olist.out_gap_bucket` AS
SELECT
  CASE WHEN gap_days <= -15 THEN '1: 15+ days early'
       WHEN gap_days <= -8  THEN '2: 8-14 days early'
       WHEN gap_days <= -1  THEN '3: 1-7 days early'
       WHEN gap_days = 0    THEN '4: on promised day'
       WHEN gap_days <= 3   THEN '5: 1-3 days late'
       WHEN gap_days <= 7   THEN '6: 4-7 days late'
       WHEN gap_days <= 14  THEN '7: 8-14 days late'
       ELSE '8: 15+ days late' END AS gap_bucket,
  CASE WHEN review_score IS NULL THEN 'no review'
       WHEN answered_before_delivery THEN 'answered before delivery'
       ELSE 'answered after delivery' END AS review_timing,
  COUNT(*) AS orders,
  COUNT(review_score) AS reviews,
  SUM(review_score) AS score_sum,
  COUNTIF(review_score <= 2) AS n_1_2_star,
  COUNTIF(review_score = 5) AS n_5_star,
  ROUND(AVG(review_score), 3) AS avg_score,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(review_score <= 2), COUNT(review_score)), 2) AS pct_1_2_star,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(review_score = 5), COUNT(review_score)), 2) AS pct_5_star
FROM `olist.model_data`
GROUP BY 1, 2;

-- 3. Month x region group (RJ / SP / Other) ----------------------------------------------------------
CREATE OR REPLACE TABLE `olist.out_monthly` AS
SELECT
  purchase_month,
  CASE WHEN customer_state = 'RJ' THEN 'RJ'
       WHEN customer_state = 'SP' THEN 'SP'
       ELSE 'Other' END AS region_group,
  COUNT(*) AS orders,
  COUNTIF(is_late) AS late_orders,
  COUNT(review_score) AS reviews,
  SUM(review_score) AS score_sum,
  ROUND(SUM(items_price), 2) AS items_revenue,
  ROUND(100 * COUNTIF(is_late) / COUNT(*), 2) AS late_pct,
  ROUND(AVG(review_score), 3) AS avg_score
FROM `olist.model_data`
GROUP BY 1, 2;

-- 4. By customer state (27 rows), with full names for the Tableau map ---------------------------------
CREATE OR REPLACE TABLE `olist.out_state` AS
WITH s AS (
  SELECT
    customer_state,
    COUNT(*) AS orders,
    COUNTIF(is_late) AS late_orders,
    COUNT(review_score) AS reviews,
    SUM(review_score) AS score_sum,
    ROUND(AVG(promised_days), 1) AS avg_promised_days,
    ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
    ROUND(AVG(freight_total), 2) AS avg_freight,
    ROUND(AVG(distance_km), 0) AS avg_distance_km,
    ROUND(SUM(items_price), 2) AS items_revenue
  FROM `olist.model_data`
  GROUP BY 1
)
SELECT
  customer_state,
  CASE customer_state
    WHEN 'AC' THEN 'Acre' WHEN 'AL' THEN 'Alagoas' WHEN 'AP' THEN 'Amapá' WHEN 'AM' THEN 'Amazonas'
    WHEN 'BA' THEN 'Bahia' WHEN 'CE' THEN 'Ceará' WHEN 'DF' THEN 'Distrito Federal'
    WHEN 'ES' THEN 'Espírito Santo' WHEN 'GO' THEN 'Goiás' WHEN 'MA' THEN 'Maranhão'
    WHEN 'MT' THEN 'Mato Grosso' WHEN 'MS' THEN 'Mato Grosso do Sul' WHEN 'MG' THEN 'Minas Gerais'
    WHEN 'PA' THEN 'Pará' WHEN 'PB' THEN 'Paraíba' WHEN 'PR' THEN 'Paraná' WHEN 'PE' THEN 'Pernambuco'
    WHEN 'PI' THEN 'Piauí' WHEN 'RJ' THEN 'Rio de Janeiro' WHEN 'RN' THEN 'Rio Grande do Norte'
    WHEN 'RS' THEN 'Rio Grande do Sul' WHEN 'RO' THEN 'Rondônia' WHEN 'RR' THEN 'Roraima'
    WHEN 'SC' THEN 'Santa Catarina' WHEN 'SP' THEN 'São Paulo' WHEN 'SE' THEN 'Sergipe'
    WHEN 'TO' THEN 'Tocantins' END AS state_name,
  orders, late_orders, reviews, score_sum,
  ROUND(100 * late_orders / orders, 2) AS late_pct,
  ROUND(100 * late_orders / SUM(late_orders) OVER (), 2) AS pct_of_all_late,
  ROUND(100 * orders / SUM(orders) OVER (), 2) AS pct_of_orders,
  avg_promised_days, avg_delivery_days,
  ROUND(avg_promised_days - avg_delivery_days, 1) AS avg_buffer_days,
  ROUND(score_sum / reviews, 3) AS avg_score,
  avg_freight, avg_distance_km, items_revenue
FROM s;

-- 5. Segments: late / on time x low score (1-2) / 3-5 stars / no review ------------------------------
CREATE OR REPLACE TABLE `olist.out_segments` AS
SELECT
  segment,
  COUNT(*) AS orders,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders,
  ROUND(SUM(items_price), 2) AS items_revenue,
  ROUND(100 * SUM(items_price) / SUM(SUM(items_price)) OVER (), 2) AS pct_of_revenue
FROM (
  SELECT
    items_price,
    CASE WHEN review_score IS NULL THEN '5: no review'
         WHEN is_late AND review_score <= 2 THEN '1: late + low score (1-2)'
         WHEN is_late THEN '2: late + 3-5 stars'
         WHEN review_score <= 2 THEN '3: on time + low score (1-2)'
         ELSE '4: on time + 3-5 stars' END AS segment
  FROM `olist.model_data`
)
GROUP BY 1;

-- 6. Score distribution, late vs on time -------------------------------------------------------------
CREATE OR REPLACE TABLE `olist.out_score_dist` AS
WITH g AS (
  SELECT IF(is_late, 'late', 'on time') AS delivery_status, review_score, COUNT(*) AS reviews
  FROM `olist.model_data`
  WHERE review_score IS NOT NULL
  GROUP BY 1, 2
)
SELECT
  delivery_status, review_score, reviews,
  ROUND(100 * reviews / SUM(reviews) OVER (PARTITION BY delivery_status), 2) AS pct_within_status
FROM g;

-- 7. Sellers with 30+ single-seller orders (shrunk rate + z-score; never rank on the raw rate) -------
-- late_pct_shrunk pulls small sellers toward the overall single-seller late rate (prior strength = 30 orders).
CREATE OR REPLACE TABLE `olist.out_seller` AS
WITH base AS (
  SELECT AVG(CAST(is_late AS INT64)) AS p0
  FROM `olist.model_data`
  WHERE n_sellers = 1
),
s AS (
  SELECT
    main_seller_id AS seller_id,
    ANY_VALUE(seller_state) AS seller_state,
    COUNT(*) AS orders,
    COUNTIF(is_late) AS late_orders,
    COUNT(review_score) AS reviews,
    SUM(review_score) AS score_sum,
    ROUND(AVG(promised_days), 1) AS avg_promised_days
  FROM `olist.model_data`
  WHERE n_sellers = 1
  GROUP BY 1
  HAVING COUNT(*) >= 30
)
SELECT
  s.*,
  ROUND(100 * late_orders / orders, 2) AS late_pct,
  ROUND(100 * (late_orders + 30 * p0) / (orders + 30), 2) AS late_pct_shrunk,
  ROUND((late_orders - orders * p0) / SQRT(orders * p0 * (1 - p0)), 1) AS z_vs_average,
  ROUND(score_sum / reviews, 3) AS avg_score
FROM s CROSS JOIN base;

-- 8. When late orders were answered before delivery, relative to the promised date -------------------
CREATE OR REPLACE TABLE `olist.out_review_timing` AS
SELECT
  CASE WHEN review_gap_days < 0   THEN '1: before promised date'
       WHEN review_gap_days = 0   THEN '2: on promised date'
       WHEN review_gap_days <= 2  THEN '3: 1-2 days after'
       WHEN review_gap_days <= 5  THEN '4: 3-5 days after'
       WHEN review_gap_days <= 10 THEN '5: 6-10 days after'
       ELSE '6: 11+ days after' END AS answered_vs_promise,
  COUNT(*) AS reviews,
  ROUND(AVG(review_score), 2) AS avg_score
FROM `olist.model_data`
WHERE is_late AND answered_before_delivery AND review_score IS NOT NULL
GROUP BY 1;


-- ============================================================================================
-- RECONCILIATION: every row must show ok = TRUE
-- ============================================================================================
WITH checks AS (
  SELECT 'out_kpi orders' AS chk, 96470.0 AS expected, CAST(orders AS FLOAT64) AS actual FROM `olist.out_kpi`
  UNION ALL SELECT 'out_kpi late_orders', 6534, CAST(late_orders AS FLOAT64) FROM `olist.out_kpi`
  UNION ALL SELECT 'out_kpi no_review', 646, CAST(no_review AS FLOAT64) FROM `olist.out_kpi`
  UNION ALL SELECT 'out_kpi items_revenue', 13220248.93, CAST(items_revenue AS FLOAT64) FROM `olist.out_kpi`
  UNION ALL SELECT 'out_gap_bucket orders', 96470, CAST(SUM(orders) AS FLOAT64) FROM `olist.out_gap_bucket`
  UNION ALL SELECT 'out_gap_bucket late orders', 6534, CAST(SUM(IF(gap_bucket >= '5', orders, 0)) AS FLOAT64) FROM `olist.out_gap_bucket`
  UNION ALL SELECT 'out_gap_bucket reviews', 95824, CAST(SUM(reviews) AS FLOAT64) FROM `olist.out_gap_bucket`
  UNION ALL SELECT 'out_monthly orders', 96470, CAST(SUM(orders) AS FLOAT64) FROM `olist.out_monthly`
  UNION ALL SELECT 'out_monthly late_orders', 6534, CAST(SUM(late_orders) AS FLOAT64) FROM `olist.out_monthly`
  UNION ALL SELECT 'out_monthly items_revenue', 13220248.93, CAST(SUM(items_revenue) AS FLOAT64) FROM `olist.out_monthly`
  UNION ALL SELECT 'out_state rows', 27, CAST(COUNT(*) AS FLOAT64) FROM `olist.out_state`
  UNION ALL SELECT 'out_state orders', 96470, CAST(SUM(orders) AS FLOAT64) FROM `olist.out_state`
  UNION ALL SELECT 'out_state late_orders', 6534, CAST(SUM(late_orders) AS FLOAT64) FROM `olist.out_state`
  UNION ALL SELECT 'out_segments orders', 96470, CAST(SUM(orders) AS FLOAT64) FROM `olist.out_segments`
  UNION ALL SELECT 'out_segments items_revenue', 13220248.93, CAST(SUM(items_revenue) AS FLOAT64) FROM `olist.out_segments`
  UNION ALL SELECT 'out_segments no review', 646, CAST(SUM(IF(STARTS_WITH(segment, '5'), orders, 0)) AS FLOAT64) FROM `olist.out_segments`
  UNION ALL SELECT 'out_segments late + low score', 3983, CAST(SUM(IF(STARTS_WITH(segment, '1'), orders, 0)) AS FLOAT64) FROM `olist.out_segments`
  UNION ALL SELECT 'out_segments on time + low score', 8289, CAST(SUM(IF(STARTS_WITH(segment, '3'), orders, 0)) AS FLOAT64) FROM `olist.out_segments`
  UNION ALL SELECT 'out_score_dist reviews', 95824, CAST(SUM(reviews) AS FLOAT64) FROM `olist.out_score_dist`
  UNION ALL SELECT 'out_score_dist late reviews', 6381, CAST(SUM(IF(delivery_status = 'late', reviews, 0)) AS FLOAT64) FROM `olist.out_score_dist`
  UNION ALL SELECT 'out_seller sellers (30+)', 615, CAST(COUNT(*) AS FLOAT64) FROM `olist.out_seller`
  UNION ALL SELECT 'out_seller orders', 79176, CAST(SUM(orders) AS FLOAT64) FROM `olist.out_seller`
  UNION ALL SELECT 'out_seller late_orders', 5436, CAST(SUM(late_orders) AS FLOAT64) FROM `olist.out_seller`
  UNION ALL SELECT 'out_review_timing reviews', 4473, CAST(SUM(reviews) AS FLOAT64) FROM `olist.out_review_timing`
)
SELECT chk, expected, actual, ROUND(actual - expected, 2) AS diff, ABS(actual - expected) < 0.011 AS ok
FROM checks
ORDER BY ok, chk;