-- =====================================================================
-- 01_data_quality.sql
-- Project : Olist delivery analytics
-- Dataset : olist   (every raw_* column was loaded as STRING)
--
-- HOW TO USE
--   Paste this file into the BigQuery editor. Highlight ONE section at a
--   time and click Run (or "Run selected"). Save every result: these are
--   your anchor numbers.
--   If you see "Table not found", add your project id in front, e.g.
--   `my-project.olist.raw_orders`.
--
-- The "EXPECT" lines come from my memory of this public dataset. They are
-- sanity checks only. Trust your own counts and write them down.
-- =====================================================================


-- ---------------------------------------------------------------------
-- SECTION A. Row count of every raw table
-- EXPECT (matches the CSV files): orders 99,441 | order_items 112,650 |
--   payments 103,886 | reviews 99,224 | customers 99,441 |
--   sellers 3,095 | products 32,951 | category_translation 71
-- ---------------------------------------------------------------------
SELECT 'raw_orders' AS table_name, COUNT(*) AS row_count FROM olist.raw_orders
UNION ALL SELECT 'raw_order_items',        COUNT(*) FROM olist.raw_order_items
UNION ALL SELECT 'raw_order_payments',     COUNT(*) FROM olist.raw_order_payments
UNION ALL SELECT 'raw_order_reviews',      COUNT(*) FROM olist.raw_order_reviews
UNION ALL SELECT 'raw_customers',          COUNT(*) FROM olist.raw_customers
UNION ALL SELECT 'raw_sellers',            COUNT(*) FROM olist.raw_sellers
UNION ALL SELECT 'raw_products',           COUNT(*) FROM olist.raw_products
UNION ALL SELECT 'raw_category_translation', COUNT(*) FROM olist.raw_category_translation;


-- ---------------------------------------------------------------------
-- SECTION B. Keys and duplicates (is each key really unique?)
-- EXPECT:
--   orders distinct order_id            = 99,441  (unique)
--   customers distinct customer_id      = 99,441  (unique)
--   customers distinct customer_unique_id ~ 96,096  (fewer = repeat buyers)
--   items distinct (order_id,item_id)   = 112,650 (unique)
--   items distinct order_id             ~ 98,666  (some orders have no items)
--   payments distinct order_id          ~ 99,440
--   reviews distinct review_id          ~ 98,410  (LESS than 99,224 rows)
--   reviews distinct order_id           ~ 98,673  (some orders have 2+ reviews)
-- ---------------------------------------------------------------------
SELECT 'orders: rows' AS check_name, COUNT(*) AS value FROM olist.raw_orders
UNION ALL SELECT 'orders: distinct order_id',          COUNT(DISTINCT order_id) FROM olist.raw_orders
UNION ALL SELECT 'orders: distinct customer_id',       COUNT(DISTINCT customer_id) FROM olist.raw_orders
UNION ALL SELECT 'customers: distinct customer_id',    COUNT(DISTINCT customer_id) FROM olist.raw_customers
UNION ALL SELECT 'customers: distinct customer_unique_id', COUNT(DISTINCT customer_unique_id) FROM olist.raw_customers
UNION ALL SELECT 'items: rows',                        COUNT(*) FROM olist.raw_order_items
UNION ALL SELECT 'items: distinct order_id',           COUNT(DISTINCT order_id) FROM olist.raw_order_items
UNION ALL SELECT 'items: distinct (order_id, order_item_id)', COUNT(DISTINCT CONCAT(order_id, '|', order_item_id)) FROM olist.raw_order_items
UNION ALL SELECT 'payments: rows',                     COUNT(*) FROM olist.raw_order_payments
UNION ALL SELECT 'payments: distinct order_id',        COUNT(DISTINCT order_id) FROM olist.raw_order_payments
UNION ALL SELECT 'payments: distinct (order_id, payment_sequential)', COUNT(DISTINCT CONCAT(order_id, '|', payment_sequential)) FROM olist.raw_order_payments
UNION ALL SELECT 'reviews: rows',                      COUNT(*) FROM olist.raw_order_reviews
UNION ALL SELECT 'reviews: distinct review_id',        COUNT(DISTINCT review_id) FROM olist.raw_order_reviews
UNION ALL SELECT 'reviews: distinct order_id',         COUNT(DISTINCT order_id) FROM olist.raw_order_reviews
UNION ALL SELECT 'products: distinct product_id',      COUNT(DISTINCT product_id) FROM olist.raw_products
UNION ALL SELECT 'sellers: distinct seller_id',        COUNT(DISTINCT seller_id) FROM olist.raw_sellers
UNION ALL SELECT 'translation: distinct category',     COUNT(DISTINCT product_category_name) FROM olist.raw_category_translation;


-- ---------------------------------------------------------------------
-- SECTION C1. Order status mix, and missing delivered dates by status
-- (empty text counts as missing, so we test NULLIF(TRIM(x), '') IS NULL)
-- EXPECT: delivered ~ 97% (~96,478). Others: shipped, canceled,
--   unavailable, invoiced, processing, created, approved.
--   Missing delivered date overall ~ 2,965, but only a handful (~8) of
--   those are status = 'delivered'. That handful is a DECISION POINT.
-- ---------------------------------------------------------------------
SELECT
  order_status,
  COUNT(*) AS orders,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders,
  COUNTIF(NULLIF(TRIM(order_delivered_customer_date), '') IS NULL) AS no_delivered_date
FROM olist.raw_orders
GROUP BY order_status
ORDER BY orders DESC;


-- ---------------------------------------------------------------------
-- SECTION C2. Missing values in every orders timestamp column
-- EXPECT: approved ~160 | carrier ~1,783 | delivered ~2,965 | estimated 0
-- ---------------------------------------------------------------------
SELECT
  COUNTIF(NULLIF(TRIM(order_purchase_timestamp), '')      IS NULL) AS missing_purchase,
  COUNTIF(NULLIF(TRIM(order_approved_at), '')             IS NULL) AS missing_approved,
  COUNTIF(NULLIF(TRIM(order_delivered_carrier_date), '')  IS NULL) AS missing_carrier,
  COUNTIF(NULLIF(TRIM(order_delivered_customer_date), '') IS NULL) AS missing_delivered,
  COUNTIF(NULLIF(TRIM(order_estimated_delivery_date), '') IS NULL) AS missing_estimated
FROM olist.raw_orders;


-- ---------------------------------------------------------------------
-- SECTION D. Do all timestamp strings parse? What is the date range?
-- EXPECT: every bad_* column = 0.
--   Purchases run from about 2016-09 to 2018-10 (very few in 2016 and
--   in the last months of 2018).
-- ---------------------------------------------------------------------
SELECT
  COUNTIF(NULLIF(TRIM(order_purchase_timestamp), '') IS NOT NULL
          AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', TRIM(order_purchase_timestamp)) IS NULL) AS bad_purchase,
  COUNTIF(NULLIF(TRIM(order_approved_at), '') IS NOT NULL
          AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', TRIM(order_approved_at)) IS NULL) AS bad_approved,
  COUNTIF(NULLIF(TRIM(order_delivered_carrier_date), '') IS NOT NULL
          AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', TRIM(order_delivered_carrier_date)) IS NULL) AS bad_carrier,
  COUNTIF(NULLIF(TRIM(order_delivered_customer_date), '') IS NOT NULL
          AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', TRIM(order_delivered_customer_date)) IS NULL) AS bad_delivered,
  COUNTIF(NULLIF(TRIM(order_estimated_delivery_date), '') IS NOT NULL
          AND SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', TRIM(order_estimated_delivery_date)) IS NULL) AS bad_estimated,
  MIN(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_purchase_timestamp), ''))) AS first_purchase,
  MAX(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_purchase_timestamp), ''))) AS last_purchase
FROM olist.raw_orders;


-- ---------------------------------------------------------------------
-- SECTION E. Grain: how many child rows per order? (this is where
-- fan-out comes from). Run E1 to E5 one by one.
-- ---------------------------------------------------------------------

-- E1. Items per order.  EXPECT: most orders have 1 item; max around 21.
SELECT items_in_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS items_in_order FROM olist.raw_order_items GROUP BY order_id)
GROUP BY items_in_order
ORDER BY items_in_order;

-- E2. Payment rows per order.  EXPECT: most have 1, some have 2+.
SELECT payments_in_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS payments_in_order FROM olist.raw_order_payments GROUP BY order_id)
GROUP BY payments_in_order
ORDER BY payments_in_order;

-- E3. Distinct sellers per order.  EXPECT: nearly all 1; a small number 2+.
SELECT sellers_in_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(DISTINCT seller_id) AS sellers_in_order FROM olist.raw_order_items GROUP BY order_id)
GROUP BY sellers_in_order
ORDER BY sellers_in_order;

-- E4. Review rows per order.  EXPECT: most 1, a few hundred with 2+.
SELECT reviews_in_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS reviews_in_order FROM olist.raw_order_reviews GROUP BY order_id)
GROUP BY reviews_in_order
ORDER BY reviews_in_order;

-- E5. FAN-OUT DEMO. Joining items to payments repeats each item row once
-- per payment row, so item revenue gets inflated.
-- EXPECT: total price ~ 13.59 million; the joined (wrong) total is larger.
SELECT 'items: total price (correct)' AS what,
       ROUND(SUM(SAFE_CAST(price AS NUMERIC)), 2) AS total_price
FROM olist.raw_order_items
UNION ALL
SELECT 'items JOIN payments: total price (WRONG, fan-out)',
       ROUND(SUM(SAFE_CAST(i.price AS NUMERIC)), 2)
FROM olist.raw_order_items i
JOIN olist.raw_order_payments p ON i.order_id = p.order_id;


-- ---------------------------------------------------------------------
-- SECTION F. Orphan keys and orders with missing children
-- EXPECT: the first group (orphans) should be 0.
--   Orders with no items ~ 775 (mostly canceled/unavailable),
--   orders with no payment ~ 1, orders with no review ~ 768.
-- ---------------------------------------------------------------------
SELECT 'orders whose customer_id is not in customers' AS check_name, COUNT(*) AS value
FROM olist.raw_orders o LEFT JOIN olist.raw_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL SELECT 'items whose order_id is not in orders', COUNT(*)
FROM olist.raw_order_items i LEFT JOIN olist.raw_orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'items whose product_id is not in products', COUNT(*)
FROM olist.raw_order_items i LEFT JOIN olist.raw_products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL SELECT 'items whose seller_id is not in sellers', COUNT(*)
FROM olist.raw_order_items i LEFT JOIN olist.raw_sellers s ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL
UNION ALL SELECT 'payments whose order_id is not in orders', COUNT(*)
FROM olist.raw_order_payments p LEFT JOIN olist.raw_orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'reviews whose order_id is not in orders', COUNT(*)
FROM olist.raw_order_reviews r LEFT JOIN olist.raw_orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'orders with NO items', COUNT(*)
FROM olist.raw_orders o LEFT JOIN (SELECT DISTINCT order_id FROM olist.raw_order_items) i ON o.order_id = i.order_id
WHERE i.order_id IS NULL
UNION ALL SELECT 'orders with NO payment', COUNT(*)
FROM olist.raw_orders o LEFT JOIN (SELECT DISTINCT order_id FROM olist.raw_order_payments) p ON o.order_id = p.order_id
WHERE p.order_id IS NULL
UNION ALL SELECT 'orders with NO review', COUNT(*)
FROM olist.raw_orders o LEFT JOIN (SELECT DISTINCT order_id FROM olist.raw_order_reviews) r ON o.order_id = r.order_id
WHERE r.order_id IS NULL;


-- ---------------------------------------------------------------------
-- SECTION G. Date sanity: timelines that should not happen
-- EXPECT: small numbers. "delivered before carrier" is typically ~170.
--   'delivered' status with no delivered date ~ 8.
--   non-delivered status WITH a delivered date is a handful.
-- DECISION: flag these rows in 02_cleaning.sql, do not delete silently.
-- ---------------------------------------------------------------------
WITH o AS (
  SELECT
    order_id,
    order_status,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_purchase_timestamp), ''))      AS purchase_ts,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_approved_at), ''))             AS approved_ts,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_delivered_carrier_date), ''))  AS carrier_ts,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_delivered_customer_date), '')) AS delivered_ts,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_estimated_delivery_date), '')) AS estimated_ts
  FROM olist.raw_orders
)
SELECT 'approved before purchase' AS check_name, COUNTIF(approved_ts < purchase_ts) AS value FROM o
UNION ALL SELECT 'carrier pickup before purchase',      COUNTIF(carrier_ts < purchase_ts) FROM o
UNION ALL SELECT 'carrier pickup before approval',      COUNTIF(carrier_ts < approved_ts) FROM o
UNION ALL SELECT 'delivered before carrier pickup',     COUNTIF(delivered_ts < carrier_ts) FROM o
UNION ALL SELECT 'delivered before purchase',           COUNTIF(delivered_ts < purchase_ts) FROM o
UNION ALL SELECT 'estimated date before purchase',      COUNTIF(estimated_ts < purchase_ts) FROM o
UNION ALL SELECT 'status delivered but no delivered date', COUNTIF(order_status = 'delivered' AND delivered_ts IS NULL) FROM o
UNION ALL SELECT 'status NOT delivered but has delivered date', COUNTIF(order_status <> 'delivered' AND delivered_ts IS NOT NULL) FROM o;


-- ---------------------------------------------------------------------
-- SECTION H. Review quirks. Run H1 to H3 one by one.
-- ---------------------------------------------------------------------

-- H1. Score distribution.  EXPECT: only 1 to 5; 5 stars is the biggest
-- group (~58%), then 4, then 1, then 3, then 2.
SELECT
  review_score,
  COUNT(*) AS reviews,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM olist.raw_order_reviews
GROUP BY review_score
ORDER BY review_score;

-- H2. Invalid scores.  EXPECT: 0.
SELECT COUNTIF(SAFE_CAST(review_score AS INT64) IS NULL
               OR SAFE_CAST(review_score AS INT64) NOT BETWEEN 1 AND 5) AS invalid_scores
FROM olist.raw_order_reviews;

-- H3. SURVEY TIMING QUIRK. The Kaggle page says the satisfaction survey is
-- sent when the customer receives the product OR the estimated delivery date
-- is due. So for late orders the survey can go out BEFORE the parcel
-- arrives. This counts how often the review date is earlier than the
-- delivery date (compared at date level).
-- (Orders with 2+ reviews are counted once per review here, which is fine
-- for a quick check.)
WITH x AS (
  SELECT
    r.order_id,
    DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(r.review_creation_date), '')))          AS review_created_date,
    DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(o.order_delivered_customer_date), ''))) AS delivered_date,
    DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(o.order_estimated_delivery_date), ''))) AS estimated_date
  FROM olist.raw_order_reviews r
  JOIN olist.raw_orders o ON r.order_id = o.order_id
  WHERE o.order_status = 'delivered'
)
SELECT
  COUNTIF(delivered_date IS NOT NULL)                                                  AS delivered_reviews,
  COUNTIF(review_created_date < delivered_date)                                        AS survey_sent_before_delivery,
  COUNTIF(delivered_date > estimated_date)                                             AS late_reviews,
  COUNTIF(delivered_date > estimated_date AND review_created_date < delivered_date)    AS late_and_survey_before_delivery
FROM x;


-- ---------------------------------------------------------------------
-- SECTION I. Category translation coverage
-- EXPECT: ~610 products have no category at all, and 2 categories that
--   exist in products are missing from the translation file
--   (pc_gamer and portateis_cozinha_e_preparadores_de_alimentos).
-- ---------------------------------------------------------------------

-- I1. Categories in products with no English translation
SELECT p.product_category_name, COUNT(*) AS products
FROM olist.raw_products p
LEFT JOIN olist.raw_category_translation t ON p.product_category_name = t.product_category_name
WHERE NULLIF(TRIM(p.product_category_name), '') IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY products DESC;

-- I2. Products with a missing category
SELECT COUNTIF(NULLIF(TRIM(product_category_name), '') IS NULL) AS products_without_category
FROM olist.raw_products;