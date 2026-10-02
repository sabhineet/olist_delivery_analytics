# Findings

## The headline
Customers do not simply judge delivery against the promise. They react most strongly **when the parcel has not arrived by the time they are asked**. After arrival, raw speed explains scores about as well as the gap to the promise, or slightly better.

## Overview
- 96,470 delivered orders; 6,534 late (6.77%). Average score 4.29 on time, 2.27 late.
- 53.8% of late orders that were reviewed got 1 star, against 6.6% of on-time orders.
- Lateness is only part of the story: 8,289 on-time orders (8.6%) got 1-2 stars, against 3,983 late orders (4.1%).
- Average score by gap: 4.32 (15+ days early), 4.31, 4.20, 4.03 (on the promised day), 3.29 (1-3 late), 2.10 (4-7 late), 1.67 (8-14 late), 1.72 (15+ late). Early delivery adds about 0.3 stars across the whole early range; late delivery removes about 2.4.

## Survey timing matters
70% of reviews on late orders (4,473 of 6,381) were answered before the parcel arrived. Conditional on the controls, those customers score about 2.2 stars lower and their score is almost flat in lateness (late slope -0.007 per day), so the steep late-side curve in the raw data is partly a timing effect. The bin plot shows the post-delivery curve is much shallower.

## H1: gap vs raw speed
- All reviews: gap fits better (AIC 209,802 vs 211,055; 1,253 points).
- Answered after delivery: speed fits better (AIC 197,793 vs 198,466; 673 points).
- Both add information in both samples (LR p < 0.001). The gap's advantage comes from reviews written before arrival.

## H2: late days cost more than early days gain
| Sample, cap 30 | Early day gains | Late day costs | Ratio |
|---|---|---|---|
| All reviews | 0.024 | 0.122 | 5.1x |
| Answered after delivery | 0.013 | 0.085 | 6.5x |

By cap, the ratio is 5.8 / 5.2 / 5.1 / 3.5 (all reviews, caps 7 / 14 / 30 / 60) and 1.2 / 3.0 / 6.5 / 7.0 (after delivery). The late curve flattens after about 8 days.

## H3: short promises do not hurt more
`late x promise` is +0.0026 on all reviews, +0.0014 with a timing control and -0.0003 (p = 0.81) after delivery. Short-promise orders are answered before delivery less often at 1-3 days late (19.9% vs 25.8% for long promises), which creates the raw pattern. Not supported.

## H4: seller-stage vs carrier-stage
A day of seller-stage delay costs 0.070 stars vs 0.047 for a carrier-stage day (all reviews); after delivery 0.057 vs 0.030 (p = 0.019). Only 22.3% of late orders have any seller-stage delay.

## H5: non-response
Late orders are much less likely to receive a review (odds ratio 0.25, 95% CI 0.21-0.31), but worst-case bounds on the late-minus-on-time gap are -2.05 to -1.94 against an observed -2.02, and IPW leaves the H2 slopes unchanged (0.0240 / 0.1214 vs 0.0238 / 0.1217).

## Where and when
- Highest late rates: AL 21.4%, MA 17.4%, SE 15.2%. SP 4.5% (40,494 orders); RJ 12.1% (12,350 orders).
- RJ has 12.8% of orders but 22.9% of late orders; SP has 27.9%.
- Late rates spiked in Nov-Dec 2017 and Feb-Mar 2018. RJ reached 26.0% (Nov 2017), 34.0% (Feb 2018) and 34.5% (Mar 2018); other states peaked at 23.7% in March 2018.
- Sellers: 615 sellers with 30+ single-seller orders cover 79,176 orders and 5,436 late orders. Lateness is spread broadly rather than concentrated in a few small sellers.

## Practical implications
1. Fix the post-handover leg first: most lateness is accrued after the seller hands over.
2. Warn customers proactively when a parcel will miss the promise; the steepest penalty is in reviews written while the parcel is still in transit.
3. After arrival, a late day costs about the same whatever the promise length (H3), so there is no evidence that a longer promise cushions a late parcel. Early delivery buys very little (H2).
