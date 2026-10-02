# Data

Nothing in this folder is committed (see `.gitignore`).

## Raw data
Olist Brazilian E-Commerce Public Dataset (CC BY-NC-SA 4.0):
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Nine CSVs. Load them into BigQuery dataset `olist` as `raw_orders`, `raw_order_items`, `raw_order_payments`, `raw_order_reviews`, `raw_customers`, `raw_sellers`, `raw_products`, `raw_category_translation`, plus the geolocation file (named in `sql/05a_export_model_data.sql`). Load every column as STRING; the cleaning views parse them.

## model_data.csv
One row per delivered order (96,470 rows, 24 columns), produced by `sql/05a_export_model_data.sql`. This is the only input the notebook needs. Column definitions: `docs/data_dictionary.md`.

Anchor checks the notebook asserts on load: 96,470 orders, 6,534 late, 646 without a review, item revenue 13,220,248.93.
