-- =====================================================================
-- 02_cleaning.sql
-- Project : Olist delivery analytics
-- Raw tables are NEVER edited. Everything below is a VIEW on top of them.
-- Run the whole CREATE VIEW block first (highlight sections 1-7, Run),
-- then run the validation queries in section 8 one at a time.
--
-- DECISIONS (copy these into docs/data_dictionary.md)
--   D1  Timestamps are text. They are parsed with SAFE.PARSE_TIMESTAMP;
--       an empty string becomes NULL.
--   D2  Analysis set = order_status = 'delivered' AND has a delivered date.
--       Canceled, unavailable, shipped etc. stay in clean_orders for
--       context but are excluded from lateness and review analysis.
--   D3  "Late" = delivered DATE is after the estimated DATE. The estimate
--       has no time of day, so we compare dates, not clock times.
--   D4  One review per order: keep the most recently answered one.
--   D5  order_analysis has exactly ONE row per order. Items and payments
--       are aggregated BEFORE joining, so revenue is never multiplied.
--   D6  Impossible timelines are flagged (has_timeline_issue), not deleted.
--   D7  Multi-seller orders: main seller and main category = the most
--       expensive item. n_sellers is kept so they can be filtered later.
--   D8  answered_before_delivery = the kept review was answered BEFORE the
--       parcel was delivered (answer timestamp < delivered timestamp).
--       NULL when the order has no review. Check V4 at the bottom: it must
--       return 4,653 reviews (4,473 on late orders).
--   D9  handover_gap_days = carrier pickup DATE minus the LATEST shipping
--       limit DATE in the order (positive = seller handed over late).
--       Confirmed by 03c_check_handover_gap.sql (96,469 of 96,470 match).
-- =====================================================================


-- 1. All orders, timestamps parsed ------------------------------------
CREATE OR REPLACE VIEW olist.clean_orders AS
SELECT
  order_id,
  customer_id,
  order_status,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_purchase_timestamp), ''))      AS purchase_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_approved_at), ''))             AS approved_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_delivered_carrier_date), ''))  AS carrier_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_delivered_customer_date), '')) AS delivered_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(order_estimated_delivery_date), '')) AS estimated_ts
FROM olist.raw_orders;


-- 2. Analysis set: delivered orders + delivery metrics ----------------
-- gap_days > 0 means late, < 0 means early.
CREATE OR REPLACE VIEW olist.delivered_orders AS
SELECT
  *,
  DATE_DIFF(DATE(delivered_ts), DATE(purchase_ts),  DAY) AS delivery_days,   -- how long it actually took
  DATE_DIFF(DATE(estimated_ts), DATE(purchase_ts),  DAY) AS promised_days,   -- how long Olist promised
  DATE_DIFF(DATE(delivered_ts), DATE(estimated_ts), DAY) AS gap_days,        -- delivered minus promised
  DATE_DIFF(DATE(delivered_ts), DATE(estimated_ts), DAY) > 0 AS is_late,
  DATE_DIFF(DATE(carrier_ts),   DATE(purchase_ts),  DAY) AS handover_days,   -- purchase to carrier pickup
  DATE_DIFF(DATE(delivered_ts), DATE(carrier_ts),   DAY) AS carrier_days,    -- carrier pickup to customer
  COALESCE(carrier_ts < purchase_ts
           OR delivered_ts < purchase_ts
           OR delivered_ts < carrier_ts, FALSE)          AS has_timeline_issue
FROM olist.clean_orders
WHERE order_status = 'delivered'
  AND delivered_ts IS NOT NULL
  AND estimated_ts IS NOT NULL
  AND purchase_ts  IS NOT NULL;


-- 3. Reviews: one per order, score as INT -----------------------------
CREATE OR REPLACE VIEW olist.clean_reviews AS
SELECT
  order_id,
  review_id,
  review_score,
  has_comment,
  review_created_ts,
  review_answered_ts
FROM (
  SELECT
    r.order_id,
    r.review_id,
    SAFE_CAST(r.review_score AS INT64) AS review_score,
    NULLIF(TRIM(r.review_comment_message), '') IS NOT NULL AS has_comment,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(r.review_creation_date), ''))   AS review_created_ts,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(r.review_answer_timestamp), '')) AS review_answered_ts,
    ROW_NUMBER() OVER (
      PARTITION BY r.order_id
      ORDER BY SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(r.review_answer_timestamp), '')) DESC,
               r.review_id DESC
    ) AS rn
  FROM olist.raw_order_reviews r
)
WHERE rn = 1
  AND review_score BETWEEN 1 AND 5;


-- 4. Items: numeric price/freight + English category ------------------
CREATE OR REPLACE VIEW olist.clean_items AS
SELECT
  i.order_id,
  SAFE_CAST(i.order_item_id AS INT64)                                              AS order_item_id,
  i.product_id,
  i.seller_id,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', NULLIF(TRIM(i.shipping_limit_date), '')) AS shipping_limit_ts,
  SAFE_CAST(i.price AS NUMERIC)                                                    AS price,
  SAFE_CAST(i.freight_value AS NUMERIC)                                            AS freight_value,
  COALESCE(t.product_category_name_english,
           NULLIF(TRIM(p.product_category_name), ''),
           'unknown')                                                              AS category_en,
  SAFE_CAST(p.product_weight_g AS INT64)                                           AS weight_g
FROM olist.raw_order_items i
LEFT JOIN olist.raw_products p
       ON i.product_id = p.product_id
LEFT JOIN olist.raw_category_translation t
       ON p.product_category_name = t.product_category_name;


-- 5. Items collapsed to ONE row per order -----------------------------
CREATE OR REPLACE VIEW olist.order_items_agg AS
SELECT
  order_id,
  COUNT(*)                                                         AS n_items,
  COUNT(DISTINCT seller_id)                                        AS n_sellers,
  SUM(price)                                                       AS items_price,
  SUM(freight_value)                                               AS freight_total,
  MAX(shipping_limit_ts)                                           AS shipping_limit_ts_max,
  ARRAY_AGG(seller_id   ORDER BY price DESC, order_item_id LIMIT 1)[OFFSET(0)] AS main_seller_id,
  ARRAY_AGG(category_en ORDER BY price DESC, order_item_id LIMIT 1)[OFFSET(0)] AS main_category
FROM olist.clean_items
GROUP BY order_id;


-- 6. Payments collapsed to ONE row per order --------------------------
CREATE OR REPLACE VIEW olist.order_payments_agg AS
SELECT
  order_id,
  COUNT(*)                                                         AS n_payment_rows,
  SUM(SAFE_CAST(payment_value AS NUMERIC))                         AS payment_total,
  MAX(SAFE_CAST(payment_installments AS INT64))                    AS max_installments,
  ARRAY_AGG(payment_type ORDER BY SAFE_CAST(payment_value AS NUMERIC) DESC LIMIT 1)[OFFSET(0)] AS main_payment_type
FROM olist.raw_order_payments
GROUP BY order_id;


-- 7. THE analysis table: one row per delivered order ------------------
CREATE OR REPLACE VIEW olist.order_analysis AS
SELECT
  d.order_id,
  d.customer_id,
  c.customer_unique_id,
  c.customer_state,
  d.purchase_ts,
  d.approved_ts,
  d.carrier_ts,
  d.delivered_ts,
  d.estimated_ts,
  d.delivery_days,
  d.promised_days,
  d.gap_days,
  d.is_late,
  d.handover_days,
  d.carrier_days,
  d.has_timeline_issue,
  -- seller stage: days past the seller's shipping limit (> 0 = seller handed over late)
  DATE_DIFF(DATE(d.carrier_ts), DATE(ia.shipping_limit_ts_max), DAY) AS handover_gap_days,
  ia.n_items,
  ia.n_sellers,
  ia.items_price,
  ia.freight_total,
  ia.main_category,
  ia.main_seller_id,
  s.seller_state,
  pa.payment_total,
  pa.main_payment_type,
  pa.max_installments,
  r.review_score,
  r.has_comment,
  r.review_created_ts,
  r.review_answered_ts,
  r.review_answered_ts < d.delivered_ts AS answered_before_delivery   -- D8; NULL if no review
FROM olist.delivered_orders d
LEFT JOIN olist.raw_customers      c  ON d.customer_id    = c.customer_id
LEFT JOIN olist.order_items_agg    ia ON d.order_id       = ia.order_id
LEFT JOIN olist.raw_sellers        s  ON ia.main_seller_id = s.seller_id
LEFT JOIN olist.order_payments_agg pa ON d.order_id       = pa.order_id
LEFT JOIN olist.clean_reviews      r  ON d.order_id       = r.order_id;


-- =====================================================================
-- 8. VALIDATION. Run each query separately and write the numbers down.
-- =====================================================================

-- V1. Anchor totals and no-fan-out checks.
-- EXPECT:
--   clean_orders rows        = raw_orders rows          (99,441)
--   clean_items rows         = raw_order_items rows     (112,650)
--   clean_reviews: rows = distinct orders (~98,673)
--   order_analysis rows      = delivered_orders rows (~96,470)
--   order_analysis distinct orders = its rows
--   the two item-price totals are IDENTICAL
SELECT 'clean_orders rows' AS check_name, CAST(COUNT(*) AS FLOAT64) AS value FROM olist.clean_orders
UNION ALL SELECT 'raw_orders rows',                       COUNT(*) FROM olist.raw_orders
UNION ALL SELECT 'clean_items rows',                      COUNT(*) FROM olist.clean_items
UNION ALL SELECT 'raw_order_items rows',                  COUNT(*) FROM olist.raw_order_items
UNION ALL SELECT 'clean_reviews rows',                    COUNT(*) FROM olist.clean_reviews
UNION ALL SELECT 'clean_reviews distinct orders',         COUNT(DISTINCT order_id) FROM olist.clean_reviews
UNION ALL SELECT 'delivered_orders rows (analysis set)',  COUNT(*) FROM olist.delivered_orders
UNION ALL SELECT 'order_analysis rows',                   COUNT(*) FROM olist.order_analysis
UNION ALL SELECT 'order_analysis distinct orders',        COUNT(DISTINCT order_id) FROM olist.order_analysis
UNION ALL SELECT 'item price, delivered orders, via clean_items',
                 CAST(SUM(i.price) AS FLOAT64)
                 FROM olist.clean_items i JOIN olist.delivered_orders d ON i.order_id = d.order_id
UNION ALL SELECT 'item price, delivered orders, via order_analysis',
                 CAST(SUM(items_price) AS FLOAT64) FROM olist.order_analysis;

-- V2. Null check on the columns the analysis depends on.
-- EXPECT: no review for ~1% of orders; a few missing item/payment rows.
SELECT
  COUNT(*)                                     AS orders,
  COUNTIF(review_score IS NULL)                AS no_review,
  COUNTIF(items_price IS NULL)                 AS no_items,
  COUNTIF(payment_total IS NULL)               AS no_payment,
  COUNTIF(customer_state IS NULL)              AS no_customer_state,
  COUNTIF(seller_state IS NULL)                AS no_seller_state,
  COUNTIF(has_timeline_issue)                  AS timeline_issues,
  COUNTIF(n_sellers > 1)                       AS multi_seller_orders
FROM olist.order_analysis;

-- V3. First look: late vs on-time (anchor for 05_outputs.sql).
-- EXPECT: 6,534 late orders (6.77%), average review 2.27 late vs 4.29 on time, 646 without review in total.
SELECT
  is_late,
  COUNT(*)                                                  AS orders,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_orders,
  ROUND(AVG(review_score), 3)                               AS avg_review_score,
  COUNTIF(review_score IS NULL)                             AS no_review
FROM olist.order_analysis
GROUP BY is_late;

-- V4. answered_before_delivery check (D8).
-- EXPECT: answered_before = 4,653 | late_and_answered_before = 4,473 | no_review = 646
-- If the numbers differ, the deployed definition used dates instead of timestamps.
-- Try:  DATE(r.review_answered_ts) < DATE(d.delivered_ts)  and compare again.
SELECT
  COUNTIF(answered_before_delivery)                AS answered_before,
  COUNTIF(answered_before_delivery AND is_late)    AS late_and_answered_before,
  COUNTIF(review_score IS NULL)                    AS no_review
FROM olist.order_analysis;
