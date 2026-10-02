-- 03c_check_handover_gap.sql
-- Purpose: confirm how handover_gap_days was defined in 02_cleaning.sql before trusting H4 (seller vs carrier stage).
-- H4 assumes: handover_gap_days = carrier handover date minus the seller's shipping limit date (positive = seller late).
--
-- How to read the result:
--   one of the eq_* columns should be close to (orders - null_gap)  -> that is the definition, H4 stands as written
--   none of them match                                            -> the definition is something else.
--                                                                     Read the 02_cleaning.sql header and re-specify H4.
-- RESULT (full data): orders 96,470 | null_gap 1 | positive_gap 5,570 | eq_date_max 96,469 | eq_date_min 96,136
--   | eq_ts_max 41,902 | eq_ts_min 41,722
--   -> eq_date_max = orders - null_gap, so handover_gap_days = carrier pickup DATE minus the LATEST shipping limit DATE.
-- Note: positive_gap counts ALL delivered orders with a positive gap. The notebook's 22.3% is a share of LATE reviewed
-- orders (timeline issues excluded), so the two numbers are not directly comparable.

WITH lim AS (
  SELECT order_id,
         MIN(shipping_limit_ts) AS lim_min,
         MAX(shipping_limit_ts) AS lim_max
  FROM `olist.clean_items`
  GROUP BY order_id
)
SELECT
  COUNT(*) AS orders,
  COUNTIF(o.handover_gap_days IS NULL) AS null_gap,
  COUNTIF(o.handover_gap_days > 0) AS positive_gap,
  COUNTIF(o.handover_gap_days = DATE_DIFF(DATE(o.carrier_ts), DATE(l.lim_max), DAY)) AS eq_date_max,
  COUNTIF(o.handover_gap_days = DATE_DIFF(DATE(o.carrier_ts), DATE(l.lim_min), DAY)) AS eq_date_min,
  COUNTIF(o.handover_gap_days = TIMESTAMP_DIFF(o.carrier_ts, l.lim_max, DAY)) AS eq_ts_max,
  COUNTIF(o.handover_gap_days = TIMESTAMP_DIFF(o.carrier_ts, l.lim_min, DAY)) AS eq_ts_min
FROM `olist.order_analysis` o
JOIN lim l USING (order_id);
