# Kaggle write-up

## Notebook title
Speed or promise? What Olist customers react to when a delivery is late

## Subtitle (one line)
Ordered-logit and piecewise tests on 96,470 orders show the late-delivery penalty is mostly about parcels still in transit when the customer is asked.

## Tags
e-commerce, brazil, statistics, regression, survey-bias, tableau, bigquery, olist

## Description (paste into the Kaggle notebook / project description)

**The question.** When a parcel is late, do customers punish the delay itself, the broken promise, or the fact that the parcel has not arrived yet? Olist gives each order a promised date, so I could separate raw delivery time from the gap to the promise.

**The data.** 96,470 delivered Olist orders (2016-2018). I cleaned and joined the nine raw tables in BigQuery (documented decisions, reconciliation checks to fixed anchors: 96,470 orders, 6,534 late, 646 without review, R$13.22M item revenue), exported one row per order, and tested five hypotheses in this notebook. Four Tableau dashboards present the descriptive side.

**What I found.**
1. *Gap vs speed (H1).* On all reviews the gap to the promise fits better than delivery days (AIC 1,253 points better). On reviews written *after* delivery the order reverses: speed fits better by 673 points. Both still add information.
2. *Asymmetry (H2).* A late day costs about 0.12 stars; an early day gains about 0.02 (5x). After delivery the ratio is 6.5x at a 30-day cap, but it ranges from 1.2x to 7.0x depending on the cap, so the headline number needs its cap attached.
3. *Short promises (H3).* The idea that the same lateness hurts more after a short promise looks true in raw data (+0.0026 per promised day) and disappears after delivery (-0.0003, p = 0.81). Short-promise orders are simply reviewed before arrival less often.
4. *Seller vs carrier (H4).* A day of seller-stage delay costs more than a carrier-stage day (0.057 vs 0.030 after delivery, p = 0.019), but only 22% of late orders have any seller delay.
5. *Non-response (H5).* Late orders are four times less likely to be reviewed (odds ratio 0.25), yet worst-case bounds and inverse-probability weights barely move the result.

**The key lesson.** 70% of reviews on late orders were written before the parcel arrived. Those reviews react to a missed promise, are almost flat in lateness, and drive much of the raw "cliff". Any analysis of late delivery and satisfaction on Olist should split the sample by review timing.

**Method notes.** Ordered logit with natural cubic splines (custom L-BFGS with analytic gradients), OLS with seller-clustered standard errors, likelihood-ratio and Wald tests, Manski bounds, IPW. Observational only; coefficients are associations after controls for state, month, category, price, freight and distance.

**How to run.** Attach `model_data.csv` as a Kaggle dataset, choose "Run All". The notebook finds the file automatically, asserts the anchor numbers, and writes all result tables to `results/`.

## Dataset description (for the `model_data` dataset)
One row per delivered Olist order (96,470 rows, 24 columns) derived from the Olist Brazilian E-Commerce Public Dataset (CC BY-NC-SA 4.0) with delivery gaps, review timing flags and seller-customer distance added. Built by `sql/05a_export_model_data.sql`; column definitions in the GitHub repo (`docs/data_dictionary.md`). License: CC BY-NC-SA 4.0 (inherits from the source).

## Links to add before publishing
GitHub repository: `<link>` | Tableau Public: `<link>`
