-- 03b_review_timing_checks.sql
-- Purpose: check how survey timing (answering before the parcel arrives) distorts the late-side score curve.
-- Needs answered_before_delivery from 02_cleaning.sql (D8). Run each query separately.

-- P1: when were pre-delivery reviews answered, relative to the promised date?
SELECT
  CASE
    WHEN d < 0   THEN '1: before promised date'
    WHEN d = 0   THEN '2: on promised date'
    WHEN d <= 2  THEN '3: 1-2 days after'
    WHEN d <= 5  THEN '4: 3-5 days after'
    WHEN d <= 10 THEN '5: 6-10 days after'
    ELSE '6: 11+ days after'
  END AS review_vs_promise,
  COUNT(*) AS reviews,
  ROUND(AVG(review_score), 2) AS avg_review_score
FROM (
  SELECT review_score,
         DATE_DIFF(DATE(review_answered_ts), DATE(estimated_ts), DAY) AS d
  FROM `olist.order_analysis`
  WHERE is_late AND answered_before_delivery
)
GROUP BY 1 ORDER BY 1;

-- P2: is the D speed bucket based on delivery days or promised days?
SELECT
  speed_bucket,
  MIN(delivery_days) AS min_deliv, MAX(delivery_days) AS max_deliv,
  MIN(promised_days) AS min_prom,  MAX(promised_days) AS max_prom
FROM (
  SELECT delivery_days, promised_days,
    CASE WHEN delivery_days <= 7  THEN '1: up to 7 days'
         WHEN delivery_days <= 14 THEN '2: 8-14 days'
         WHEN delivery_days <= 21 THEN '3: 15-21 days'
         ELSE '4: 22+ days' END AS speed_bucket
  FROM `olist.order_analysis`
)
GROUP BY 1 ORDER BY 1;

-- P3: how many orders carry the timeline-issue flag, and do they sit in the late group?
SELECT has_timeline_issue, is_late, COUNT(*) AS orders,
       ROUND(AVG(review_score), 3) AS avg_review_score
FROM `olist.order_analysis`
GROUP BY 1, 2 ORDER BY 1, 2;

-- P4: does the late-side saturation come from pre-delivery reviews?
SELECT
  CASE WHEN gap_days <= 3  THEN '1: 1-3 late'
       WHEN gap_days <= 7  THEN '2: 4-7 late'
       WHEN gap_days <= 14 THEN '3: 8-14 late'
       ELSE '4: 15+ late' END AS late_bucket,
  answered_before_delivery,
  COUNT(*) AS reviews,
  ROUND(AVG(review_score), 2) AS avg_review_score,
  ROUND(100 * COUNTIF(review_score <= 2) / COUNT(*), 1) AS pct_1_2_star
FROM `olist.order_analysis`
WHERE is_late AND review_score IS NOT NULL
GROUP BY 1, 2 ORDER BY 1, 2;
