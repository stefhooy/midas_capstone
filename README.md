# MIDAS Capstone — Exact Cross-Frequency Aggregation in Mixed-Frequency Time Series

**Student:** Stephan Pentchev | **Supervisor:** Dae-jin Lee (IE University)

**Deadline:** Thesis + Poster → 29 June 2026 | Defense → 7 July 2026

---

## Hard Deadlines

| Date | Event |
| --- | --- |
| Tue 2 June 2026 | Check-in session ✓ — DJL feedback received (see below) |
| Mon 29 June 2026 | Submit thesis (max 30 pages) + A0 poster (by 12:00) |
| Tue 7 July 2026 | Oral defense — 15 min presentation + 15 min Q&A |

---

## Supervisor Feedback — 2 June 2026 Meeting (DJL)

Key additions requested by Dae-jin Lee:

| Topic | What DJL asked | Where it goes |
| --- | --- | --- |
| Kernel U-MIDAS | Non-parametric smoother on lag weights (Breitung); compare to free U-MIDAS and nealmon/nbeta | Phase 6 |
| LSTM | Recurrent neural network as ML benchmark for time series forecasting | Phase 6 |
| XGBoost / tree models | Reference ML benchmark; prepare to defend why not used as primary | Phase 6 |
| LASSO | Penalise U-MIDAS lag coefficients; already planned | Phase 7 |
| PCA | Reduce 12-week WTI lag matrix to principal components as regressors | Phase 7 |
| Multicollinearity | VIF analysis of weekly WTI lags; motivates PCA and LASSO | Phase 7 |
| Energy/oil literature | Add domain-specific references (oil price forecasting, CPI transmission) | Phase 1 + thesis |
| Performance vs interpretability | Explicit trade-off table in results: RMSE vs model complexity | Phase 8 |
| Directional accuracy / precision / recall | Add sign-correct %, precision/recall for large-move episodes | All phases results |
| Segmented regression | Structural break analysis: pre/post 2008, 2014, COVID | Phase 7b |

---

## Repository Structure

```text
midas_capstone/
├── R/
│   ├── 00_setup.R          # Package installation (run once) ✓
│   ├── 01_tutorial.R       # Overview: all models in-sample on USData ✓
│   ├── 02_arimax.R         # Standalone: ARIMAX benchmark ✓
│   ├── 03_adl_midas.R      # Standalone: ADL-MIDAS nealmon + nbeta ✓
│   ├── 04_umidas.R         # Standalone: U-MIDAS unrestricted OLS ✓
│   ├── 05_comparison.R     # Side-by-side in-sample comparison table + plots ✓
│   ├── 06_rolling_window.R # Phase 2c: USData rolling RMSE/MAE + DM test ✓
│   ├── 07_clm_ss.R         # Phase 5: CLM-SS state-space (KFAS) ✓
│   ├── 08_energy_data.R    # Phase 3: energy dataset download + EDA ✓
│   ├── 09_benchmarks.R     # Phase 4: full benchmark suite on energy data ✓
│   ├── 10_ml_benchmarks.R  # Phase 6: ML models (LSTM, XGBoost, kernel U-MIDAS)
│   ├── 11_extended_models.R# Phase 7: LASSO, PCA, segmented regression, metrics
│   └── archive/            # Old broken drafts (kept for reference)
├── data/
│   ├── raw/                # Original downloaded datasets
│   └── processed/          # Cleaned / aligned series + phase4_forecasts.rds
├── output/
│   ├── figures/            # All plots (300 DPI+)
│   └── tables/             # Forecast error tables (.csv)
└── README.md
```

---

## Full Checklist

### Phase 0 — Environment Setup ✓ DONE

- [x] R + midasr working in VSCode (Alt+Enter / Ctrl+Shift+S)
- [x] Packages installed: `midasr`, `forecast`, `quantmod`, `KFAS`, `tseries`, `urca`, `dplyr`, `lmtest`, `sandwich`, `glmnet`, `xts`, `zoo`, `httpgd`
- [x] Project folder structure created + GitHub repo initialized

---

### Phase 1 — Answer Supervisor Q1: Who are MIDAS's competitors?

*Becomes the Literature Review section (3-4 pages).*

#### 1a — Competitor comparison table

- [ ] Finalize and write up competitor table:

| Model | Mixed-freq native? | Aggregation approach | Key limitation |
| --- | --- | --- | --- |
| ARIMAX | No | Pre-average (mean/sum) | Information loss — throws away within-period timing |
| ADL-MIDAS nealmon | Yes | Exponential Almon polynomial | Monotone decay only — misses humped lag structures |
| ADL-MIDAS nbeta | Yes | Normalized Beta polynomial | Best parametric shape; 3 params, local optima risk |
| U-MIDAS | Yes | Free OLS weights | Over-parameterized; needs regularization (LASSO/ridge) |
| Kernel U-MIDAS | Yes | Breitung non-param smoother | Data-driven but no exact aggregation constraint |
| HAR-RV | Partial | Fixed 1/5/22-day avg | Very rigid; only valid for realized variance |
| MF-VAR / Kalman | Yes | State-space Kalman filter | Complex; needs many series for identification |
| Bridge equations | Partial | Pre-aggregation + bridge | Still ad hoc; information loss at aggregation step |
| NowCasting (BDFM) | Yes | Kalman + EM algorithm | Designed for many series; overkill for 1 predictor |
| LSTM | Yes (implicit) | Learned sequence weights | Black box; no interpretability, needs large data |
| XGBoost | No (tabular) | Lagged features as columns | No mixed-frequency native; tree splits not temporal |
| **CLM-SS (this thesis)** | **Yes — exact** | **Free weights, MLE, AR errors** | **Novel; ridge needs CV tuning; needs validation** |

#### 1b — Literature Review paragraphs (one per model)

- [ ] ARIMAX paragraph — cite Sims (1980), Box-Jenkins; pre-averaging problem
- [ ] MIDAS family — Ghysels et al. (2004, 2007); nealmon vs nbeta trade-off
- [ ] U-MIDAS — Foroni, Marcellino & Schumacher (2015); when free weights dominate
- [ ] Kernel/non-parametric MIDAS — Breitung & Marcellino (2013); data-driven smoothing
- [ ] HAR-RV — Corsi (2009); only viable for volatility, not general mixed-freq
- [ ] State-space / MF-VAR — Aruoba et al. (2009), Mariano & Murasawa (2003)
- [ ] Bridge equations — Baffigi et al. (2004); still pre-aggregates, just deferred
- [ ] NowCasting BDFM — Giannone et al. (2008); requires panel of indicators
- [ ] ML methods — Medeiros et al. (2021) LASSO; Fischer & Krauss (2018) LSTM; XGBoost reference
- [ ] CLM-SS (this thesis) — positioning relative to all above

#### 1c — Oil/energy domain literature

- [ ] Hamilton (1983, 2009) — oil price shocks and macroeconomy
- [ ] Kilian (2008) — not all oil price shocks are alike (supply vs demand)
- [ ] Kilian & Lewis (2011) — oil price transmission to CPI
- [ ] Baumeister & Hamilton (2019) — sign restrictions in oil market VARs
- [ ] At least 2 papers on mixed-frequency models in energy forecasting

---

### Phase 2 — Answer Supervisor Q2: Is MIDAS competitive in energy/financial setting? ✓ DONE

#### Step 2a — Built-in data (zero setup) ✓

- [x] Load `USrealgdp` + `USunempr`, transform to stationary series
- [x] Fit nealmon (AIC -390.5), nbeta, U-MIDAS; compare AIC/BIC/RMSE

#### Step 2b — ARIMAX baseline ✓

- [x] `auto.arima()` → ARIMA(1,1,1), AIC -342.5, Ljung-Box p=0.647

#### Step 2c — Rolling window evaluation ✓

- [x] Expanding window 1949–(t-1), test 2000–2011; nealmon RMSE 0.0077 vs ARIMAX 0.0159 (−51%)
- [x] DM = −2.93, p = 0.007; written up as 1-page answer (Midas_vs_ARIMAX.docx)

---

### Phase 3 — Energy Dataset ✓ DONE

- [x] CPIENGSL (monthly) + DCOILWTICO (daily→weekly, m=4) + PNRGINDEXM (context)
- [x] 275 monthly obs, 1199 weekly obs | 2000-02 to 2022-12 | 0 NAs
- [x] Stationarity: all non-stationary in levels, all STATIONARY in log-diff (ADF p<0.05)
- [x] 5 EDA plots: levels, log-diff, ACF/PACF, STL decomp, transmission chain scatter
- [x] Correlations: WTI vs CPI r=0.871 | IMF vs CPI r=0.912 | IMF vs WTI r=0.954

---

### Phase 4 — Full Benchmark Suite (energy data) ✓ DONE

- [x] ARIMAX: monthly WTI mean as xreg — RMSE 0.02986
- [x] ADL-MIDAS nealmon: k=11 — RMSE 0.02104 (−29.5% vs ARIMAX), DM p=0.0003
- [x] ADL-MIDAS nbeta: k=11 — RMSE 0.02057 (−31.1%, **best Phase 4**), DM p=0.0005
- [x] U-MIDAS: k=11 — RMSE 0.02226 (−25.5%), DM p=0.0009
- [x] Lag selection: k=3/7/11 AIC grid → k=11 optimal (3 months of weekly data)
- [x] Rolling window: expanding, train 2000-2014, test 2015-2022 (96 forecasts)

**Key finding:** Lag weight hump peaks at lag 5–6 (≈6 weeks) — crude oil CPI transmission delay. nbeta wins by approximating hump freely; nealmon constrained to monotone decay.

**Pending (DJL feedback):**
- [ ] Add directional accuracy (sign correct %) to Phase 4 results table
- [ ] Add precision/recall for large-move episodes (|Δ| > 2σ threshold)

---

### Phase 5 — CLM-SS Framework (Novel Contribution) ✓ DONE

- [x] Composite link matrix Z = [w_1..w_4]: free MLE weights, no parametric shape
- [x] State-space in KFAS: AR(1) error u_t = phi·u_{t-1} + ε_t (phi=0.266, identified)
- [x] Ridge sensitivity: lambda grid {0, 0.001, 0.01, 0.1}; lambda=0 data-selected
- [x] Identifiability: Hessian positive definite; w_1 and phi significant (*)
- [x] Extended CLM-SS (12 lags, 3 months): RMSE 0.02258 (−24.4% vs ARIMAX)
- [x] Full 6-model comparison + DM tests

**Key findings:**
- CLM-SS (4 lags): RMSE 0.03170 (+6.2%) — fails without 3-month lag history
- CLM-SS (12 lags): RMSE 0.02258 (−24.4%) — ties U-MIDAS performance
- nbeta still best; parametric hump = implicit regularizer outperforming free 12-weight MLE
- CLM-SS weights peak at month −1, weeks 2–3 → independently confirms MIDAS lag hump
- phi: 0.266 → 0.123 when lags extended (richer history absorbs AR dynamics)

**Pending (DJL feedback):**
- [ ] Add directional accuracy for CLM-SS to full comparison table

---

### Phase 6 — ML Benchmark Comparison (NEW — DJL feedback)

*`10_ml_benchmarks.R` — answers DJL's request to compare with ML methods*

#### 6a — Kernel U-MIDAS (non-parametric smoother)

- [ ] Implement Breitung (2013) kernel smoother on U-MIDAS lag weights
- [ ] Compare weight shape to nealmon/nbeta: does kernel recover the hump?
- [ ] Compare OOS RMSE to free U-MIDAS and parametric MIDAS

#### 6b — LSTM (recurrent neural network)

- [ ] Implement in R using `torch` or `keras` package (or Python keras, sourced from R)
- [ ] Input: sequence of 12 weekly WTI log-diffs; output: monthly CPI log-diff
- [ ] Rolling window evaluation (same 2015-2022 test period)
- [ ] Key question: does the LSTM beat parametric MIDAS? At what interpretability cost?

#### 6c — XGBoost (tree-based reference)

- [ ] Input: 12 weekly WTI lags as tabular features + lagged CPI
- [ ] `xgboost` package; 5-fold CV for hyperparameter tuning (depth, eta, nrounds)
- [ ] Rolling window OOS RMSE for fair comparison
- [ ] Purpose: answer DJL's "did you try XGBoost?" question in defense

#### 6d — Performance vs interpretability table

- [ ] Produce final table: Model | RMSE | Directional Acc | Params | Interpretable?
- [ ] Plot: interpretability axis (left) vs forecasting performance (right)

---

### Phase 7 — Extended Feature Selection + Diagnostics (DJL feedback)

*`11_extended_models.R` — combines LASSO, PCA, multicollinearity, structural breaks*

#### 7a — LASSO-MIDAS

- [ ] Apply LASSO penalty to U-MIDAS (12-lag) coefficients via `glmnet`
- [ ] Lambda selected by time-series cross-validation
- [ ] Which weekly lags does LASSO zero out? Does it recover the lag 5-6 hump?
- [ ] Compare OOS RMSE to ridge CLM-SS and free U-MIDAS

#### 7b — PCA on weekly WTI lags

- [ ] Build 12-column lag matrix for WTI; run PCA
- [ ] Check for multicollinearity: VIF of lag columns (adjacent weeks correlated)
- [ ] Use top 3-4 principal components as regressors in ARIMAX
- [ ] Compare: does PCA-ARIMAX beat standard monthly-average ARIMAX?

#### 7c — Segmented regression / structural breaks

- [ ] Use `segmented` R package to detect breakpoints in the WTI→CPI relationship
- [ ] Test periods: 2008 financial crisis, 2014-16 oil collapse, 2020 COVID crash
- [ ] Run subsample rolling windows: pre-COVID vs post-COVID performance
- [ ] Does MIDAS advantage over ARIMAX vary by regime?

#### 7d — Extended metrics across all models

- [ ] Directional accuracy: % of months where sign(forecast) = sign(actual)
- [ ] Precision/recall framing: large move = |Δ CPI| > 1 SD threshold
  - Precision = of predicted large moves, how many were correct?
  - Recall = of actual large moves, how many did we catch?
- [ ] Mincer-Zarnowitz regression: are forecasts unbiased?

---

### Phase 8 — Written Thesis (max 30 pages, due 29 June)

- [ ] Cover page (title, supervisor, program, date, AI use declaration)
- [ ] Abstract (150-250 words)
- [ ] Introduction (2-3 pages) — mixed-frequency problem, contribution statement
- [ ] Literature Review — Phase 1 output (3-4 pages)
  - [ ] MIDAS family + CLM-SS positioning
  - [ ] Oil/energy domain: Hamilton, Kilian, oil→CPI transmission
- [ ] Methodology (4-5 pages)
  - [ ] CLM-SS formulation (math: Z, AR state, MLE)
  - [ ] Benchmarks and competitors
- [ ] Results (4-5 pages)
  - [ ] Phase 4: energy benchmark table (RMSE, directional acc, DM tests)
  - [ ] Phase 5: CLM-SS vs benchmarks, weight interpretation
  - [ ] Phase 6: ML comparison, performance vs interpretability table
  - [ ] Phase 7: LASSO/PCA/segmented regression summary
- [ ] Discussion (2-3 pages)
  - [ ] When does MIDAS beat ARIMAX? When does ML beat MIDAS?
  - [ ] What the lag hump tells us about oil price transmission
  - [ ] Limitations: ridge not cross-validated, LSTM data requirements
- [ ] Conclusions + future work (1-2 pages)
  - [ ] CLM-SS with cross-validated ridge + longer history
  - [ ] Multivariate extension (multiple predictors)
  - [ ] R package idea
- [ ] References (not counted in page limit)
- [ ] Annex A — Individual Contribution Statement (max 1 page, submitted separately)

---

### Phase 9 — Poster (A0 format, due 29 June)

- [ ] Sections: Background → Research Question → Methodology → Results → Conclusion
- [ ] Key figure: 6-model RMSE bar chart (figure 13)
- [ ] Key figure: CLM-SS composite link weights (figure 09)
- [ ] Key figure: lag weight comparison (MIDAS hump vs CLM-SS bar)
- [ ] Performance vs interpretability scatter as visual centrepiece
- [ ] Publication-quality figures only (300 DPI+)
- [ ] Submit as PDF, portrait orientation (841 × 1189 mm)

---

### Phase 10 — Code & Documentation

- [ ] Reproducible seeds `set.seed(42)` in all scripts ✓ (09, 07)
- [ ] All output figures saved to `output/figures/` ✓
- [ ] All result tables saved to `output/tables/` ✓
- [ ] `00_setup.R` updated with all required packages (add `torch`, `xgboost`, `segmented`)
- [ ] (Stretch) Package with `devtools` as minimal R package

---

## Progress Summary

| Phase | Status | Key result |
| --- | --- | --- |
| Phase 0 — Setup | ✓ Done | R + midasr + GitHub repo |
| Phase 2 — USData benchmarks | ✓ Done | nealmon RMSE −51% vs ARIMAX, DM p=0.007 |
| Phase 3 — Energy EDA | ✓ Done | CPIENGSL + WTI weekly, 5 EDA plots |
| Phase 4 — Energy benchmarks | ✓ Done | nbeta RMSE 0.02057 (−31%), all DM p<0.001 |
| Phase 5 — CLM-SS | ✓ Done | CLM-SS(12) RMSE 0.02258 (−24%); confirms lag hump |
| Phase 1 — Literature review | 🔲 Next | Competitor paragraphs + oil domain refs |
| Phase 6 — ML benchmarks | 🔲 Next | LSTM, XGBoost, Kernel U-MIDAS |
| Phase 7 — LASSO/PCA/breaks | 🔲 Next | Feature selection + segmented regression |
| Phase 8 — Thesis writing | 🔲 Due 29 Jun | 30 pages |
| Phase 9 — Poster | 🔲 Due 29 Jun | A0 PDF |
| Phase 10 — Code cleanup | 🔲 Later | |

---

## Key Results (thesis numbers)

| Model | RMSE | vs ARIMAX | Directional Acc | Interpretable? |
| --- | --- | --- | --- | --- |
| ARIMAX | 0.02986 | baseline | TBD | Yes |
| U-MIDAS | 0.02226 | −25.5% | TBD | Partial |
| CLM-SS (12 lags) | 0.02258 | −24.4% | TBD | Yes |
| MIDAS nealmon | 0.02104 | −29.5% | TBD | Yes |
| MIDAS nbeta | 0.02057 | −31.1% | TBD | Yes |
| LSTM | TBD | TBD | TBD | No |
| XGBoost | TBD | TBD | TBD | Partial |

---

## Key References

### MIDAS / Mixed-Frequency

- Ghysels, E., Santa-Clara, P., Valkanov, R. (2004). The MIDAS Touch. *CIRANO Working Paper.*
- Ghysels, E., Sinko, A., Valkanov, R. (2007). MIDAS regressions. *Journal of Financial Econometrics.*
- Foroni, C., Marcellino, M., Schumacher, C. (2015). Unrestricted MIDAS. *J. Royal Stat. Soc. A*, 178(1).
- Breitung, J. & Marcellino, M. (2013). Parameter instability in MIDAS. *J. Econometrics.*
- Ghysels, E. & Marcellino, M. (2018). *Applied Economic Forecasting*. Oxford, Ch. 12.
- midasr package: Kvedaras & Zemlys-Balevičius (CRAN 2025).

### State-Space / Kalman

- Mariano, R. & Murasawa, Y. (2003). A new coincident index. *J. Applied Econometrics.*
- Aruoba, S., Diebold, F., Scotti, C. (2009). Real-time measurement. *J. Business & Econ. Stat.*
- Helske, J. (2017). KFAS: State Space Models in R. *J. Statistical Software*, 78(10).

### ML / Regularisation

- Medeiros, M. et al. (2021). Forecasting inflation with LASSO. *Int. J. Forecasting.*
- Fischer, T. & Krauss, C. (2018). Deep learning with LSTM. *European J. Operational Research.*

### Oil / Energy Domain

- Hamilton, J. (1983). Oil and the macroeconomy. *J. Political Economy.*
- Hamilton, J. (2009). Causes and consequences of oil shocks. *Brookings Papers.*
- Kilian, L. (2008). Not all oil price shocks are alike. *American Economic Review.*
- Kilian, L. & Lewis, L. (2011). Does global oil affect US inflation? *J. Applied Econometrics.*
- Baumeister, C. & Hamilton, J. (2019). Structural interpretation. *J. Econometrics.*

---
