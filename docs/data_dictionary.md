# Data dictionary

## Cleaning decisions (`sql/02_cleaning.sql`)

| ID | Decision |
|---|---|
| D1 | All raw columns are STRING. Timestamps are parsed with `SAFE.PARSE_TIMESTAMP`; an empty string becomes NULL. |
| D2 | Analysis set = `order_status = 'delivered'` with a delivered date (96,470 orders). Other statuses stay in `clean_orders` for context only. |
| D3 | "Late" = delivered **date** after estimated **date**. The estimate has no time of day, so dates are compared, not clock times. |
| D4 | One review per order: the most recently answered one. |
| D5 | `order_analysis` has exactly one row per order. Items and payments are aggregated before joining, so revenue is never multiplied. |
| D6 | Impossible timelines are flagged (`has_timeline_issue`), not deleted. |
| D7 | Multi-seller orders: main seller and main category = the most expensive item. `n_sellers` is kept so they can be filtered. |
| D8 | `answered_before_delivery` flags reviews whose answer timestamp is earlier than the delivery timestamp (the survey is sent before arrival for some orders). |

## `model_data.csv` (one row per delivered order, 96,470 rows)

| Column | Meaning |
|---|---|
| `order_id` | Unique order key. |
| `main_seller_id` | Seller of the most expensive item. |
| `n_sellers`, `n_items` | Distinct sellers and item rows in the order. |
| `customer_state`, `seller_state` | Brazilian state codes (main seller for `seller_state`). |
| `purchase_ts`, `purchase_month` | Purchase time and first day of the purchase month. |
| `delivery_days` | Purchase date to delivered date, in days (actual speed). |
| `promised_days` | Purchase date to estimated date, in days (the promise). |
| `gap_days` | Delivered date minus estimated date. Positive = late, negative = early. |
| `is_late` | `gap_days > 0`. |
| `handover_days` | Purchase date to carrier pickup date. |
| `carrier_days` | Carrier pickup date to delivered date. |
| `handover_gap_days` | Carrier pickup date minus the **latest shipping limit date** in the order. Positive = seller handed over late. Confirmed by `03c_check_handover_gap.sql`: 96,469 of 96,470 orders match; one is NULL. |
| `has_timeline_issue` | Carrier or delivery timestamp earlier than purchase, or delivery earlier than carrier pickup. |
| `review_score` | 1-5 stars; NULL for 646 orders without a review. |
| `has_comment` | Review has free text. |
| `answered_before_delivery` | Review answered before the parcel arrived (4,653 reviews; 4,473 on late orders). NULL when there is no review. |
| `review_gap_days` | (earlier of answer time and delivery time) minus estimated date. Equals `gap_days` whenever the review was answered after delivery. |
| `items_price`, `freight_total` | Sum of item prices and freight for the order (BRL). |
| `main_category` | English category of the main item. |
| `distance_km` | Seller-to-customer distance from zip-prefix centroids (NULL for 477 orders). |

## Variables built in the notebook

| Variable | Definition |
|---|---|
| `late_days`, `early_days` | `gap_days` split at 0 and capped at `CAP` (30). |
| `gap_cc` | `gap_days` clipped to [-30, 30]. |
| `deliv_c`, `prom_c` | Delivery / promised days clipped at their 99th percentile. |
| `log_price`, `log_freight`, `log_dist` | `log1p` of price, freight, distance. Missing distance is filled with the state median and flagged by `dist_missing`. |
| `multi_seller` | `n_sellers > 1`. |
| `month` | Purchase month; the three 2016 months are pooled. |
| `cat` | Top 25 categories, the rest as `other`. |
| `gbin` | Eight gap bins from "15+ early" to "15+ late", reference "1-7 early". |

## Output tables (`sql/05_outputs.sql`, used by Tableau)

`out_kpi`, `out_gap_bucket`, `out_monthly`, `out_state`, `out_segments`, `out_score_dist`, `out_seller`, `out_review_timing`. Re-aggregate with `SUM(score_sum) / SUM(reviews)` for scores and `SUM(late_orders) / SUM(orders)` for late %. Never average the pre-computed `avg_score` or `late_pct` columns.
