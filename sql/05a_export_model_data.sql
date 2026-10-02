-- 05a_export_model_data.sql
-- Builds the view olist.model_data: one row per delivered order (96,470), the columns the notebook needs,
-- plus seller-to-customer distance (km) from zip-prefix centroids.
--
-- Needs olist.order_analysis from 02_cleaning.sql (including answered_before_delivery, D8).
-- CONFIG: the three FROM lines marked CONFIG use the table names of the geolocation, customers and sellers files as loaded
-- in this project. If yours differ, list them with:
--   SELECT table_name, table_type FROM `olist.INFORMATION_SCHEMA.TABLES`;
-- All raw columns are STRING (as loaded).
-- Zip prefixes are joined as text, so both sides must come from the raw tables
-- (do not pad or cast one side only). The validation query at the bottom reports the match rate.

CREATE OR REPLACE VIEW `olist.model_data` AS
WITH
geo AS (
  -- one centroid per zip prefix; drop points outside Brazil's bounding box (known bad rows)
  SELECT geolocation_zip_code_prefix AS zip,
         AVG(SAFE_CAST(geolocation_lat AS FLOAT64)) AS lat,
         AVG(SAFE_CAST(geolocation_lng AS FLOAT64)) AS lng
  FROM `olist.olist_geolocation_dataset`            -- CONFIG
  WHERE SAFE_CAST(geolocation_lat AS FLOAT64) BETWEEN -33.75 AND 5.27
    AND SAFE_CAST(geolocation_lng AS FLOAT64) BETWEEN -73.99 AND -34.79
  GROUP BY 1
),
cust AS (
  SELECT customer_id, customer_zip_code_prefix AS zip
  FROM `olist.olist_customers_dataset`              -- CONFIG
),
sell AS (
  SELECT seller_id, seller_zip_code_prefix AS zip
  FROM `olist.olist_sellers_dataset`                -- CONFIG
)
SELECT
  o.order_id,
  o.main_seller_id, o.n_sellers, o.n_items,
  o.customer_state, o.seller_state,
  o.purchase_ts,
  DATE_TRUNC(DATE(o.purchase_ts), MONTH) AS purchase_month,
  o.delivery_days, o.promised_days, o.gap_days, o.is_late,
  o.handover_days, o.carrier_days, o.handover_gap_days, o.has_timeline_issue,
  o.review_score, o.has_comment, o.answered_before_delivery,
  -- lateness as of the moment the customer answered: min(answer, delivery) minus promised date
  DATE_DIFF(DATE(LEAST(o.review_answered_ts, o.delivered_ts)), DATE(o.estimated_ts), DAY) AS review_gap_days,
  o.items_price, o.freight_total, o.main_category,
  ROUND(ST_DISTANCE(ST_GEOGPOINT(gc.lng, gc.lat), ST_GEOGPOINT(gs.lng, gs.lat)) / 1000, 1) AS distance_km
FROM `olist.order_analysis` o
LEFT JOIN cust c  ON o.customer_id   = c.customer_id
LEFT JOIN sell s  ON o.main_seller_id = s.seller_id
LEFT JOIN geo  gc ON c.zip = gc.zip
LEFT JOIN geo  gs ON s.zip = gs.zip;


-- ---------------------------------------------------------------------------
-- VALIDATION (run after the view is created). Expected:
--   rows_ = orders = 96470   (no join fan-out)      no_review = 646
--   no_distance small (well under 1%)               max_km below ~4,500
--   gap_mismatch = 0   (review_gap_days = gap_days when answered after delivery)
--   review_gap_gt_gap = 0   (answering earlier can only lower the gap)
-- ---------------------------------------------------------------------------
-- SELECT
--   COUNT(*) AS rows_,
--   COUNT(DISTINCT order_id) AS orders,
--   COUNTIF(review_score IS NULL) AS no_review,
--   COUNTIF(distance_km IS NULL) AS no_distance,
--   ROUND(APPROX_QUANTILES(distance_km, 100)[OFFSET(50)], 0) AS p50_km,
--   ROUND(MAX(distance_km), 0) AS max_km,
--   COUNTIF(review_score IS NOT NULL AND NOT answered_before_delivery AND review_gap_days != gap_days) AS gap_mismatch,
--   COUNTIF(answered_before_delivery AND review_gap_days > gap_days) AS review_gap_gt_gap
-- FROM `olist.model_data`;