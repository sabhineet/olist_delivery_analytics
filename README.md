# Speed or promise? What Olist customers react to when a delivery is late

SQL (BigQuery) + Python (statsmodels) + Tableau analysis of 96,470 delivered orders from the Olist Brazilian e-commerce dataset.

**Question.** Do review scores follow raw delivery time, or the gap between delivery and the promised date? And how does the penalty for a late day compare with the reward for an early day?

- Kaggle notebook: [Speed or Promise?](https://www.kaggle.com/code/abhineetsrivastavaa/speed-or-promise)
- Full write-up: [`docs/findings.md`](docs/findings.md)

## Headline

Customers do not simply judge delivery against the promise. They react most strongly **when the parcel has not arrived by the time they are asked**. After the parcel arrives, raw delivery speed explains scores about as well as the gap to the promise, or slightly better.

| Fact | Value |
|---|---|
| Delivered orders analysed | 96,470 |
| Late orders | 6,534 (6.77%) |
| Average review score, on time vs late | 4.29 vs 2.27 |
| Late orders that get 1 star vs on-time orders | 53.8% vs 6.6% |
| Unhappy customers (1-2 stars) who got their parcel on time | 8,289 vs 3,983 late |
| Item revenue | R$ 13,220,248.93 |

## Findings (H1-H5)

| | Question | Verdict | Key number |
|---|---|---|---|
| H1 | Does the gap beat raw delivery days? | Supported on all reviews, **reversed after delivery** | AIC: gap better by 1,253 (all); speed better by 673 (answered after delivery) |
| H2 | Does a late day cost more than an early day gains? | Supported (direction) | 0.122 vs 0.024 stars per day (5.1x); after delivery 0.085 vs 0.013 (6.5x). Ratio ranges 1.2x-7.0x with the lateness cap |
| H3 | Does the same lateness hurt more when the promise was short? | **Not supported** | late x promise: +0.0026 (all), -0.0003, p = 0.81 (after delivery) |
| H4 | Does seller-stage delay hurt more than carrier-stage delay? | Supported | 0.070 vs 0.047 stars/day (all); 0.057 vs 0.030, p = 0.019 (after delivery) |
| H5 | Does non-response bias the results? | Negligible | Worst-case bounds -2.05 to -1.94 vs observed -2.02 |

All results are associations after controls (state, month, category, price, freight, distance, multi-seller), with seller-clustered standard errors. They are not causal effects. See [`docs/methodology.md`](docs/methodology.md).

## Repository layout

```
.
├── README.md
├── LICENSE
├── requirements.txt
├── sql/                         BigQuery pipeline, run in order
│   ├── 01_data_quality.sql        raw-table checks (keys, nulls, timeline quirks)
│   ├── 02_cleaning.sql            views: clean_orders ... order_analysis
│   ├── 03b_review_timing_checks.sql
│   ├── 03c_check_handover_gap.sql confirms the handover_gap_days definition
│   ├── 04_sellers_regions_customers.sql
│   ├── 05_outputs.sql            out_* tables for Tableau + reconciliation
│   └── 05a_export_model_data.sql builds model_data (notebook input)
├── notebooks/
│   └── olist_speed_or_promise.ipynb   H1-H5 tests; writes results/
├── results/                     notebook outputs (h1_*.csv ... h5_*.csv, h2_gap_bins.png)
├── tableau/
│   ├── data/                      out_*.csv, model_verdicts.csv
│   ├── workbook/                  packaged .twbx
│   └── screenshots/               01_overview.png ... 04_where_and_when.png
├── data/
│   └── README.md                  how to obtain the raw and model data (not committed)
└── docs/
    ├── data_dictionary.md
    ├── methodology.md
    ├── findings.md
    └── kaggle_writeup.md
```

## How to reproduce

1. Download the [Olist dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and load the CSVs into a BigQuery dataset named `olist` as `raw_*` tables (all columns as STRING).
2. Run `sql/01` to `sql/05a` in order. After `05_outputs.sql`, run its reconciliation query: every row must show `ok = TRUE`. Anchors: 96,470 orders, 6,534 late, 646 without review, item revenue 13,220,248.93.
3. Export `olist.model_data` to `model_data.csv`.
4. Install requirements (`pip install -r requirements.txt`) and run `notebooks/olist_speed_or_promise.ipynb` with `model_data.csv` in the same folder (or attached as a Kaggle dataset). It asserts the anchor numbers before modelling.

## Data and licence

Data: Olist Brazilian E-Commerce Public Dataset, CC BY-NC-SA 4.0. see [`data/README.md`](data/README.md). Code in this repository is released under the MIT licence.
