# Speed or promise? H1-H5 (v2). Cells concatenated from olist_analysis_v2.ipynb. Run it as a notebook, not as a plain script.

import os, warnings
import numpy as np, pandas as pd, patsy
import statsmodels.formula.api as smf
from scipy.optimize import minimize
from scipy.special import expit
from types import SimpleNamespace
from scipy import stats
import matplotlib.pyplot as plt
warnings.filterwarnings('ignore')
pd.set_option('display.width', 160); pd.set_option('display.max_columns', 30)

PROJECT = 'olist-delivery-analytics'   # BigQuery project id
CSV = 'model_data.csv'                 # used if the file exists, otherwise BigQuery
CAP = 30                               # |gap| days are capped at this in regressions (heavy tails)
OUT = 'results/'                       # result tables and figures are written here
os.makedirs(OUT, exist_ok=True)

if os.path.exists(CSV):
    df = pd.read_csv(CSV)
else:
    from google.cloud import bigquery
    df = bigquery.Client(project=PROJECT).query('SELECT * FROM `olist.model_data`').to_dataframe()

def to_bool(s):
    return s.map({True: True, False: False, 'true': True, 'false': False, 'True': True, 'False': False}).fillna(False).astype(bool)

for c in ['is_late', 'has_timeline_issue', 'answered_before_delivery']:
    df[c] = to_bool(df[c])
for c in ['items_price', 'freight_total', 'distance_km', 'review_score', 'review_gap_days', 'delivery_days',
          'promised_days', 'gap_days', 'handover_days', 'carrier_days', 'handover_gap_days', 'n_items', 'n_sellers']:
    df[c] = pd.to_numeric(df[c], errors='coerce').astype(float)
df['purchase_month'] = pd.to_datetime(df['purchase_month'])
print(df.shape)

got = {'orders': len(df), 'late_orders': int(df.is_late.sum()), 'no_review': int(df.review_score.isna().sum()),
       'items_revenue': round(float(df.items_price.sum()), 2)}
want = {'orders': 96470, 'late_orders': 6534, 'no_review': 646, 'items_revenue': 13220248.93}
print(got)
bad = {k: (got[k], want[k]) for k in want if abs(got[k] - want[k]) > 0.011}
assert not bad, f'anchor mismatch: {bad}'
assert df.order_id.is_unique

print('late == gap>0 :', (df.is_late == (df.gap_days > 0)).all())
post = df[df.review_score.notna() & ~df.answered_before_delivery]
print('review_gap_days == gap_days for post-delivery reviews:', round((post.review_gap_days == post.gap_days).mean(), 4))
print('missing distance:', df.distance_km.isna().sum(), '| distance km p50/p90/max:',
      df.distance_km.quantile([.5, .9, 1]).round(0).tolist())
print('promised_days > 60:', int((df.promised_days > 60).sum()), '| delivery_days > 60:', int((df.delivery_days > 60).sum()))
print(df.groupby('is_late').review_score.agg(['count', 'mean']).round(3))

df['gap_cc'] = df.gap_days.clip(-CAP, CAP)
df['late_days'] = df.gap_days.clip(0, CAP)
df['early_days'] = (-df.gap_days).clip(0, CAP)
df['deliv_c'] = df.delivery_days.clip(upper=df.delivery_days.quantile(.99))
df['prom_c'] = df.promised_days.clip(upper=df.promised_days.quantile(.99))
df['log_price'] = np.log1p(df.items_price)
df['log_freight'] = np.log1p(df.freight_total)
df['dist_missing'] = df.distance_km.isna().astype(int)
df['distance_km'] = df.distance_km.fillna(df.groupby('customer_state').distance_km.transform('median')).fillna(df.distance_km.median())
df['log_dist'] = np.log1p(df.distance_km)
df['multi_seller'] = (df.n_sellers > 1).astype(int)
df['month'] = df.purchase_month.dt.strftime('%Y-%m')
df.loc[df.purchase_month < '2017-01-01', 'month'] = '2016'          # pool the 3 tiny 2016 months
top_cat = df.main_category.value_counts().head(25).index
df['cat'] = df.main_category.where(df.main_category.isin(top_cat), 'other').fillna('other')
df['seller'] = df.main_seller_id.fillna('unknown')
df['gbin'] = pd.cut(df.gap_days, [-np.inf, -15, -8, -1, 0, 3, 7, 14, np.inf],
                    labels=['1:15+ early', '2:8-14 early', '3:1-7 early', '4:on day',
                            '5:1-3 late', '6:4-7 late', '7:8-14 late', '8:15+ late']).astype(str)

CTRL = 'C(customer_state) + C(month) + C(cat) + log_price + log_freight + log_dist + dist_missing + multi_seller'

rev = df[df.review_score.notna()].copy()            # modelling sample: reviewed orders
rev_post = rev[~rev.answered_before_delivery]       # reviews answered after delivery
print(len(rev), len(rev_post))

def ols(formula, data, weights=None):
    mod = (smf.ols(formula, data) if weights is None else smf.wls(formula, data, weights=weights))
    if int(mod.nobs) != len(data):
        raise ValueError('rows dropped by patsy (NaN in a used column); clean the frame first')
    return mod.fit(cov_type='cluster', cov_kwds={'groups': pd.factorize(data['seller'])[0]})

def ologit(rhs, data):
    # Ordered logit (scores 1-5) by L-BFGS with analytic gradients. No intercept: the thresholds play that role.
    # statsmodels' OrderedModel gives the same log-likelihood but uses numerical gradients and is far too slow here.
    X = patsy.dmatrix(rhs, data, return_type='dataframe').drop(columns='Intercept')
    Xv = X.values.astype(float); sd = Xv.std(0); Xv = (Xv - Xv.mean(0)) / np.where(sd > 0, sd, 1)
    y = data['review_score'].astype(int).values - 1
    K, k, n = 5, Xv.shape[1], len(y)
    def nll(p):
        c = np.cumsum(np.r_[p[k], np.exp(p[k + 1:])]); eta = Xv @ p[:k]
        cc = np.r_[-np.inf, c, np.inf]
        Fu, Fl = expit(cc[y + 1] - eta), expit(cc[y] - eta)
        pr = np.clip(Fu - Fl, 1e-300, None)
        fu, fl = Fu * (1 - Fu), Fl * (1 - Fl)
        g_b = Xv.T @ (-(fu - fl) / pr)
        up, lo = y < K - 1, y > 0
        g_c = (np.bincount(y[up], weights=(fu / pr)[up], minlength=K - 1)
               - np.bincount(y[lo] - 1, weights=(fl / pr)[lo], minlength=K - 1))
        g_t = np.r_[g_c.sum(), np.exp(p[k + 1:]) * np.array([g_c[j:].sum() for j in range(1, K - 1)])]
        return -np.log(pr).sum(), -np.r_[g_b, g_t]
    cum = np.cumsum(np.bincount(y, minlength=K))[:-1] / n
    c0 = np.log(cum / (1 - cum))
    r = minimize(nll, np.r_[np.zeros(k), c0[0], np.log(np.diff(c0))], jac=True, method='L-BFGS-B',
                 options={'maxiter': 2000, 'maxfun': 5000})
    if not r.success:
        print('WARNING: ordered logit did not converge:', r.message)
    kp = len(r.x)
    return SimpleNamespace(llf=-r.fun, params=r.x, aic=2 * kp + 2 * r.fun, bic=kp * np.log(n) + 2 * r.fun)

def lincom(res, w):
    v = np.zeros(len(res.params)); idx = list(res.params.index)
    for k, c in w.items(): v[idx.index(k)] = c
    est = float(v @ res.params.values); se = float(np.sqrt(v @ res.cov_params().values @ v))
    return est, se, float(2 * stats.norm.sf(abs(est / se)))

def joint_wald(res, names):
    idx = list(res.params.index)
    R = np.zeros((len(names), len(idx)))
    for r, n in enumerate(names): R[r, idx.index(n)] = 1
    w = res.wald_test(R, use_f=False, scalar=True)
    return float(w.statistic), float(w.pvalue)

print(rev[['delivery_days', 'promised_days', 'gap_days']].corr().round(2))
f_speed = 'cr(deliv_c, df=5, constraints="center")'
f_gap = 'cr(gap_cc, df=5, constraints="center")'

def run_h1(sample, label):
    forms = {'M0 controls only': CTRL, 'M1 speed': f'{f_speed} + {CTRL}',
             'M2 gap': f'{f_gap} + {CTRL}', 'M3 speed + gap': f'{f_speed} + {f_gap} + {CTRL}'}
    fit = {k: ologit(v, sample) for k, v in forms.items()}
    ols_fit = {k: ols(f'review_score ~ {v}', sample) for k, v in forms.items()}
    tab = pd.DataFrame({k: {'k_params': len(r.params), 'loglik': r.llf, 'AIC': r.aic, 'BIC': r.bic,
                            'dLL_vs_M0': r.llf - fit['M0 controls only'].llf,
                            'ols_R2': ols_fit[k].rsquared, 'ols_adjR2': ols_fit[k].rsquared_adj}
                        for k, r in fit.items()}).T
    print(f'--- H1 on {label} (n={len(sample)}) ---'); print(tab.round(4))
    tests = []
    for big, small, what in [('M3 speed + gap', 'M1 speed', 'gap adds to speed (LR, M3 vs M1)'),
                             ('M3 speed + gap', 'M2 gap', 'speed adds to gap (LR, M3 vs M2)')]:
        stat = 2 * (fit[big].llf - fit[small].llf); k = len(fit[big].params) - len(fit[small].params)
        tests.append(dict(sample=label, test=what, stat=stat, df=k, p=stats.chi2.sf(stat, k)))
    m_full = ols_fit['M3 speed + gap']
    n_speed = [n for n in m_full.params.index if 'deliv_c' in n]
    n_gap = [n for n in m_full.params.index if 'gap_cc' in n]
    for what, names in [('gap terms (seller-clustered Wald chi2)', n_gap), ('speed terms (seller-clustered Wald chi2)', n_speed)]:
        chi2, p = joint_wald(m_full, names); tests.append(dict(sample=label, test=what, stat=chi2, df=len(names), p=p))
    tests = pd.DataFrame(tests); print(tests.round(4).to_string(index=False))
    tab = tab.reset_index().rename(columns={'index': 'model'}); tab.insert(0, 'sample', label)
    return tab, tests

t_all, w_all = run_h1(rev, 'all reviews')
t_post, w_post = run_h1(rev_post, 'answered after delivery only')
pd.concat([t_all, t_post]).to_csv(OUT + 'h1_models.csv', index=False)
pd.concat([w_all, w_post]).to_csv(OUT + 'h1_tests.csv', index=False)

def piecewise(data, gap_col, label):
    d = data.copy()
    d['e'] = (-d[gap_col]).clip(0, CAP); d['l'] = d[gap_col].clip(0, CAP)
    m = ols(f'review_score ~ e + l + {CTRL}', d)
    p = float(np.squeeze(m.t_test('e + l = 0').pvalue))
    return dict(spec=label, n=int(m.nobs), gain_per_early_day=m.params['e'], se_gain=m.bse['e'],
                cost_per_late_day=-m.params['l'], se_cost=m.bse['l'],
                cost_minus_gain=-(m.params['e'] + m.params['l']), p_symmetric=p)

clean = rev[~rev.has_timeline_issue & (rev.multi_seller == 0)]
h2 = pd.DataFrame([
    piecewise(rev, 'gap_days', '1 all reviews, gap at delivery'),
    piecewise(rev_post, 'gap_days', '2 answered after delivery only'),
    piecewise(rev, 'review_gap_days', '3 all reviews, gap as of review time'),
    piecewise(clean, 'gap_days', '4 all, excl. timeline-issue + multi-seller'),
])
print(h2.round(4).to_string(index=False))
h2.to_csv(OUT + 'h2_specs.csv', index=False)

# CAP sensitivity: do the per-day numbers move when lateness is capped at 7, 14, 30 or 60 days?
def piecewise_cap(data, cap, label):
    d = data.copy(); d['e'] = (-d.gap_days).clip(0, cap); d['l'] = d.gap_days.clip(0, cap)
    m = ols(f'review_score ~ e + l + {CTRL}', d)
    return dict(sample=label, cap_days=cap, gain_per_early_day=m.params['e'], cost_per_late_day=-m.params['l'],
                cost_to_gain_ratio=-m.params['l'] / m.params['e'])

cap_tab = pd.DataFrame([piecewise_cap(s, c, lab) for s, lab in [(rev, 'all reviews'), (rev_post, 'answered after delivery only')]
                        for c in (7, 14, 30, 60)])
print(cap_tab.round(4).to_string(index=False))
cap_tab.to_csv(OUT + 'h2_cap_sensitivity.csv', index=False)

# Does the late slope differ for reviews answered before delivery?
d = rev.copy(); d['e'] = d.early_days; d['l'] = d.late_days; d['pre'] = d.answered_before_delivery.astype(int)
m = ols(f'review_score ~ e + l + pre + l:pre + {CTRL}', d)
keys = ['e', 'l', 'pre', 'l:pre']
pre_tab = pd.DataFrame({'coef': m.params[keys], 'se': m.bse[keys]}).round(4)
print(pre_tab)
print('late slope for reviews answered before delivery (l + l:pre): %.4f (se %.4f)' % lincom(m, {'l': 1, 'l:pre': 1})[:2])
pre_tab.rename_axis('term').reset_index().to_csv(OUT + 'h2_pre_interaction.csv', index=False)

# Bin plot: where is the cliff, and where does it saturate? (reference = 1-7 days early)
REF = '3:1-7 early'
def bin_coefs(data):
    m = ols(f'review_score ~ C(gbin, Treatment("{REF}")) + {CTRL}', data)
    ci = m.conf_int(); rows = {REF: (0, 0, 0)}
    for n in m.params.index:
        if 'gbin' in n:
            rows[n.split('[T.')[1][:-1]] = (m.params[n], ci.loc[n, 0], ci.loc[n, 1])
    return pd.DataFrame(rows, index=['coef', 'lo', 'hi']).T.sort_index()

fig, ax = plt.subplots(figsize=(9, 4.5)); bins_out = []
for data, lab, off in [(rev, 'all reviews', -0.1), (rev_post, 'answered after delivery', 0.1)]:
    b = bin_coefs(data); b['n'] = data.gbin.value_counts().reindex(b.index); x = np.arange(len(b)) + off
    ax.errorbar(x, b.coef, yerr=[b.coef - b.lo, b.hi - b.coef], fmt='o-', capsize=3, label=lab)
    bins_out.append(b.assign(sample=lab).rename_axis('gap_bin').reset_index())
ax.set_xticks(range(len(b))); ax.set_xticklabels(b.index, rotation=30, ha='right')
ax.axhline(0, color='grey', lw=.5); ax.set_ylabel('score vs 1-7 days early (controls in)'); ax.legend()
plt.tight_layout(); plt.savefig(OUT + 'h2_gap_bins.png', dpi=150); plt.show()
pd.concat(bins_out).to_csv(OUT + 'h2_bins.csv', index=False)
print(rev_post.gbin.value_counts().sort_index())

def run_h3(sample, label, control_pre=False):
    d = sample.copy()
    d['e'] = d.early_days; d['l'] = d.late_days; d['pre'] = d.answered_before_delivery.astype(int)
    d['prom_dev'] = d.prom_c - d.groupby('customer_state').prom_c.transform('mean')
    d['prom_t'] = d.groupby('customer_state').prom_c.transform(lambda s: pd.qcut(s.rank(method='first'), 3, labels=False)).astype(int)
    extra = ' + pre + l:pre' if control_pre else ''
    rows = []
    m = ols(f'review_score ~ e + l*prom_dev{extra} + {CTRL}', d)
    rows.append(dict(sample=label, term='late slope per day (at state-mean promise)', est=m.params['l'], se=m.bse['l']))
    rows.append(dict(sample=label, term='late x promise (per +1 promised day)', est=m.params['l:prom_dev'],
                     se=m.bse['l:prom_dev'], p=m.pvalues['l:prom_dev']))
    for dev in (-7, 7):
        est, se, p = lincom(m, {'l': 1, 'l:prom_dev': dev})
        rows.append(dict(sample=label, term=f'late slope at promise {dev:+d} d vs state mean', est=est, se=se))
    m3 = ols(f'review_score ~ e + l*C(prom_t){extra} + {CTRL}', d)
    names = [n for n in m3.params.index if n.startswith('l:C(prom_t)')]
    for t in (0, 1, 2):
        w = {'l': 1}
        if t > 0: w[f'l:C(prom_t)[T.{t}]'] = 1
        est, se, p = lincom(m3, w)
        rows.append(dict(sample=label, term=f'late slope, promise tercile {t} (0 = shortest)', est=est, se=se))
    chi2, p = joint_wald(m3, names)
    rows.append(dict(sample=label, term='slopes equal across terciles (Wald chi2)', est=chi2, p=p))
    out = pd.DataFrame(rows); print(f'--- H3 on {label} (n={len(d)}) ---'); print(out.round(4).to_string(index=False))
    cells = None
    if not control_pre:
        late = d[d.is_late].copy()
        late['late_bin'] = pd.cut(late.gap_days, [0, 3, 7, 14, np.inf], labels=['1-3', '4-7', '8-14', '15+'])
        cells = late.groupby(['late_bin', 'prom_t'], observed=True).agg(
            mean_score=('review_score', 'mean'), n=('review_score', 'size'),
            pct_answered_before_delivery=('answered_before_delivery', 'mean')).reset_index()
        cells['pct_answered_before_delivery'] *= 100
        cells.insert(0, 'sample', label); print(cells.round(2).to_string(index=False))
    return out, cells

h3a, c_a = run_h3(rev, 'all reviews')
h3b, _ = run_h3(rev, 'all reviews, timing control', control_pre=True)
h3c, c_c = run_h3(rev_post, 'answered after delivery only')
pd.concat([h3a, h3b, h3c]).to_csv(OUT + 'h3_slopes.csv', index=False)
pd.concat([c_a, c_c]).to_csv(OUT + 'h3_cells.csv', index=False)

s4 = rev[~rev.has_timeline_issue & rev.is_late].dropna(subset=['handover_gap_days']).copy()
s4['seller_late'] = s4.handover_gap_days.clip(lower=0).clip(upper=CAP)
s4['carrier_resid'] = (s4.gap_days - s4.handover_gap_days.clip(lower=0)).clip(-CAP, CAP)
print('late orders with seller-stage delay > 0: %.1f%%' % (100 * (s4.seller_late > 0).mean()))
print(s4[['seller_late', 'carrier_resid']].describe().round(2))
rows = []
for lab, data in [('all reviews', s4), ('answered after delivery', s4[~s4.answered_before_delivery])]:
    m = ols(f'review_score ~ seller_late + carrier_resid + {CTRL}', data)
    est, se, p = lincom(m, {'seller_late': 1, 'carrier_resid': -1})
    rows.append(dict(sample=lab, n=int(m.nobs), per_seller_day=m.params['seller_late'], se_s=m.bse['seller_late'],
                     per_carrier_day=m.params['carrier_resid'], se_c=m.bse['carrier_resid'], diff=est, p_equal=p))
h4 = pd.DataFrame(rows); print(h4.round(4).to_string(index=False))
h4.to_csv(OUT + 'h4_stage_delay.csv', index=False)

g = df.groupby('is_late').agg(n=('order_id', 'size'), reviewed=('review_score', 'count'), mean=('review_score', 'mean'))
miss = g.n - g.reviewed
lo = (g['mean'] * g.reviewed + 1 * miss) / g.n; hi = (g['mean'] * g.reviewed + 5 * miss) / g.n
h5_bounds = pd.DataFrame({'n': g.n, 'missing': miss, 'observed_mean': g['mean'], 'worst_low': lo, 'worst_high': hi}).round(3)
print(h5_bounds)
print('late minus on-time: observed %.3f | bounds [%.3f, %.3f]' % (g['mean'][True] - g['mean'][False], lo[True] - hi[False], hi[True] - lo[False]))
h5_bounds.rename_axis('is_late').reset_index().to_csv(OUT + 'h5_bounds.csv', index=False)

r = df.copy()
r['has_review'] = r.review_score.notna().astype(int); r['late_i'] = r.is_late.astype(int)
top_states = r.customer_state.value_counts().head(8).index
r['state_g'] = r.customer_state.where(r.customer_state.isin(top_states), 'other')
r['quarter'] = r.purchase_month.dt.to_period('Q').astype(str)
resp = smf.logit('has_review ~ late_i + C(state_g) + C(quarter) + log_price + log_freight + log_dist', r).fit(
    disp=False, cov_type='cluster', cov_kwds={'groups': pd.factorize(r.seller)[0]})
orr = np.exp(resp.params['late_i']); ci = np.exp(resp.conf_int().loc['late_i'])
print('odds ratio of a review, late vs on-time: %.2f (95%% CI %.2f-%.2f)' % (orr, *ci))

p_resp = resp.predict(r)
w = (1 / p_resp).loc[rev.index]
d = rev.copy(); d['e'] = (-d.gap_days).clip(0, CAP); d['l'] = d.gap_days.clip(0, CAP)
h5_rows = [dict(item='odds ratio of a review, late vs on-time', value=orr, ci_low=ci[0], ci_high=ci[1])]
for lab, wt in [('unweighted', None), ('IPW', w)]:
    m = ols(f'review_score ~ e + l + {CTRL}', d, weights=wt)
    print(f'{lab:10s} gain/early day {m.params["e"]:.4f} | cost/late day {-m.params["l"]:.4f}')
    h5_rows.append(dict(item=f'{lab}: gain per early day', value=m.params['e']))
    h5_rows.append(dict(item=f'{lab}: cost per late day', value=-m.params['l']))
pd.DataFrame(h5_rows).to_csv(OUT + 'h5_response_ipw.csv', index=False)

for f in sorted(os.listdir(OUT)): print(OUT + f)
