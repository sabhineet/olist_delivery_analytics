# Methodology

## Sample
Reviewed delivered orders (n = 95,824). Reviews answered **after** delivery (n = 91,171) form the cleaner comparison sample, because customers who answer before the parcel arrives (n = 4,653) are reacting to a missed promise, not to measured lateness.

## Controls
Customer state, purchase month, product category (top 25 + other), log item price, log freight, log distance, a missing-distance flag and a multi-seller flag. Standard errors are clustered by main seller.

## Models
- **H1 (gap vs speed).** Ordered logit of the 1-5 score on a natural cubic spline (5 df) of delivery days (M1), of the gap (M2) or both (M3), each with the controls. Compared by AIC, plus likelihood-ratio tests of M3 vs M1 and M3 vs M2 and seller-clustered Wald tests from the matching OLS. The ordered logit is fitted by L-BFGS with analytic gradients (the statsmodels `OrderedModel` gives the same log-likelihood but is too slow here).
- **H2 (asymmetry).** OLS with a kink at gap = 0: `score ~ early_days + late_days + controls`, days capped at 30. Four specifications (gap at delivery, post-delivery only, gap as of review time, excluding timeline-issue and multi-seller orders) and a cap sensitivity at 7, 14, 30 and 60 days. A bin plot (reference "1-7 days early") shows where the cliff sits and where it flattens.
- **H3 (promise length).** Promise is centred within customer state; `late x promise` is tested continuously and by tercile, on all reviews, with a timing control (`pre`, `late x pre`) and on post-delivery reviews only. The share of reviews answered before delivery is tabulated for every lateness x promise cell.
- **H4 (stage).** On late orders only, lateness is split into seller-stage days (handover after the latest shipping limit) and the carrier-stage remainder; equality of the two per-day costs is tested.
- **H5 (non-response).** Manski worst-case bounds on the late-minus-on-time gap for the 646 missing reviews; a logit response model; the H2 model re-run with inverse-probability weights.

## Limitations
- Observational: coefficients are associations, not causal effects.
- Lateness above about 8 days is rare after delivery (8-14 days late: 57 reviews, 15+: 19), so late-side estimates there are noisy.
- The H2 ratio depends on the cap (post-delivery: 1.2x at 7 days to 7.0x at 60 days), so quote it with the cap.
- Review text and the exact survey send time are not modelled; the pre-/post-delivery split is a proxy for what the customer knew when answering.
- The final months of the data may be affected by right-censoring because undelivered orders are excluded.
