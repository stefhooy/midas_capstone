# MIDAS Capstone: Exact Cross-Frequency Aggregation in Mixed-Frequency Time Series

**Student:** Stephan Pentchev | **Supervisor:** Dae-jin Lee (IE University)

**Deadline:** Thesis + Poster: 29 June 2026 | Defense: 7 July 2026

---

## Research Context

| Item | Details |
| --- | --- |
| Research question | Does CLM-SS (exact weekly aggregation + AR errors) improve monthly consumer energy price forecasts vs. models that pre-aggregate weekly oil data? |
| **y (outcome)** | Monthly log-change in US Consumer Energy CPI (CPIENGSL, FRED). What US households pay for gasoline, heating oil, electricity. Published monthly. |
| **x (predictor)** | Weekly log-change in WTI crude oil spot price (DCOILWTICO, FRED). Upstream commodity driver. 4 weekly obs per monthly CPI (m=4). |
| Context only | IMF Global Price of Energy Index (PNRGINDEXM, FRED). Used in Phase 3 EDA only. Not in any model. |
| Sample | Feb 2000 to Dec 2022. 275 monthly obs, 1199 weekly obs. |
| Forecasting setup | 1-step-ahead nowcasting. All 4 weekly WTI obs from month t available when forecasting CPI for month t (WTI published weekly, CPI published mid-following-month). |
| Test period | Jan 2015 to Dec 2022. 96 one-step-ahead forecasts per model. |

---

## Hard Deadlines

| Date | Event |
| --- | --- |
| Tue 2 June 2026 | Check-in session (done) — DJL feedback incorporated below |
| Mon 29 June 2026 | Submit thesis (max 30 pages) + A0 poster (by 12:00) |
| Tue 7 July 2026 | Oral defense — 15 min presentation + 15 min Q&A |

---

## Supervisor Feedback — 2 June 2026 (DJL)

| Request | What DJL asked | Status |
| --- | --- | --- |
| Kernel U-MIDAS | Non-parametric smoother on lag weights (Breitung and Roling 2015) | Phase 6a - DONE |
| LSTM | Recurrent neural network as ML benchmark | Phase 6b - DONE |
| XGBoost | Tree-based reference benchmark; defend why not primary model | Phase 6c |
| LASSO-MIDAS | Penalise U-MIDAS lag coefficients via glmnet | Phase 7a |
| PCA on WTI lags | Reduce 12-week lag matrix to PCs; check multicollinearity (VIF) | Phase 7b - DONE |
| Segmented regression | Structural break analysis: 2008, 2014, COVID | Phase 7c - DONE |
| Directional accuracy | Sign-correct %, precision/recall, Mincer-Zarnowitz | Phase 7d — DONE |
| Energy/oil literature | Hamilton, Kilian, Baumeister domain refs | Phase 1 — DONE |
| Forecast horizon validity | How far ahead is oil-CPI prediction valid? Based on oil literature | Phase 7e - DONE |
| Interpretability table | RMSE vs complexity vs interpretability trade-off table | Phase 8 |

---

## Repository Structure

```
midas_capstone/
├── R/
│   ├── 00_setup.R           # Package installation (run once)
│   ├── 01_tutorial.R        # USData in-sample: all models
│   ├── 02_arimax.R          # Standalone: ARIMAX benchmark
│   ├── 03_adl_midas.R       # Standalone: ADL-MIDAS nealmon + nbeta
│   ├── 04_umidas.R          # Standalone: U-MIDAS unrestricted OLS
│   ├── 05_comparison.R      # In-sample comparison table + plots
│   ├── 06_rolling_window.R  # Phase 2c: USData rolling RMSE + DM test
│   ├── 07_clm_ss.R          # Phase 5: CLM-SS (KFAS)
│   ├── 08_energy_data.R     # Phase 3: energy EDA
│   ├── 09_benchmarks.R      # Phase 4: full benchmark suite on energy data
│   ├── 10_ml_benchmarks.R   # Phase 6: XGBoost, LSTM, Kernel U-MIDAS
│   ├── 11_extended_models.R # Phase 7: LASSO, PCA, segmented regression, metrics
│   └── archive/
├── data/
│   ├── raw/
│   └── processed/           # .rds files: phase4_forecasts, clmss_forecasts
├── output/
│   ├── figures/             # All PNG plots (300 DPI)
│   └── tables/              # All CSV result tables
└── README.md
```

---

## Full Checklist

### Phase 0 — Environment Setup (done)

- [x] R + midasr working in VSCode
- [x] All packages installed: midasr, forecast, quantmod, KFAS, tseries, urca, dplyr, lmtest, sandwich, glmnet, xts, zoo, httpgd
- [x] GitHub repo initialized, folder structure created

---

### Phase 1 — Literature Review (done)

*Answers DJL Q1: Who are MIDAS's competitors? Becomes thesis Chapter 2.*

- [x] Competitor comparison table (12 models including CLM-SS)
- [x] ARIMAX paragraph: Box and Jenkins (1970), Sims (1980); pre-averaging problem
- [x] MIDAS family: Ghysels et al. (2004, 2007); nealmon vs nbeta trade-off
- [x] U-MIDAS: Foroni et al. (2015); when free weights dominate
- [x] Kernel MIDAS: Breitung and Roling (2015); non-parametric smoother
- [x] HAR-RV: Corsi (2009); rigid, only valid for realized variance
- [x] State-space / MF-VAR: Aruoba et al. (2009), Mariano and Murasawa (2003)
- [x] Bridge equations: Baffigi et al. (2004); pre-aggregates before estimation
- [x] NowCasting BDFM: Giannone et al. (2008); requires panel of indicators
- [x] ML methods: Fischer and Krauss (2018) LSTM, Chen and Guestrin (2016) XGBoost, Medeiros et al. (2021) LASSO
- [x] CLM-SS positioning relative to all above
- [x] Oil/energy domain: Hamilton (1983, 2009), Kilian (2009), Kilian and Lewis (2011), Baumeister and Hamilton (2019)
- [x] Energy MF literature: Baumeister and Kilian (2015), Nonejad (2022)
- [x] Full APA reference list (24 references, all verified against PDFs in Papers/)

---

### Phase 2 — USData Benchmarks (done)

*Answers DJL Q2: Is MIDAS competitive? Proof of concept on built-in data.*

- [x] USrealgdp + USunempr, m=12 (annual/monthly)
- [x] nealmon AIC -390.5, nbeta AIC -288.5, ARIMAX AIC -342.5
- [x] Rolling window 2000-2011: nealmon RMSE 0.0077 vs ARIMAX 0.0159 (-51%)
- [x] DM test: DM = -2.93, p = 0.007

---

### Phase 3 — Energy Dataset EDA (done)

- [x] CPIENGSL + DCOILWTICO (daily to weekly, m=4) + PNRGINDEXM (context)
- [x] 275 monthly obs, 1199 weekly obs, 0 NAs, sample 2000-02 to 2022-12
- [x] ADF tests: all non-stationary in levels, stationary in log-diff
- [x] 5 EDA plots: levels, log-diff, ACF/PACF, STL decomp, transmission chain scatter
- [x] Correlations: WTI vs CPI r=0.871, IMF vs CPI r=0.912, IMF vs WTI r=0.954

---

### Phase 4 — Full Benchmark Suite on Energy Data (done)

- [x] ARIMAX (monthly WTI mean as xreg): RMSE 0.02986
- [x] MIDAS nealmon (k=11): RMSE 0.02104 (-29.5% vs ARIMAX), DM p=0.0003
- [x] MIDAS nbeta (k=11): RMSE 0.02057 (-31.1%, best), DM p=0.0005
- [x] U-MIDAS (k=11): RMSE 0.02226 (-25.5%), DM p=0.0009
- [x] Lag selection: k=3/7/11 AIC grid, k=11 optimal (3 months of weekly data)
- [x] Rolling window: expanding, train 2000-2014, test 2015-2022 (96 forecasts)
- [x] Phase 4 forecast vectors saved to data/processed/phase4_forecasts.rds

**Key finding:** Lag weight hump peaks at lag 5-6 (approx. 6 weeks) confirming crude oil transmission delay to consumer prices. nbeta wins because it freely approximates the hump; nealmon is constrained to monotone decay.

---

### Phase 5 — CLM-SS Framework: Novel Contribution (done)

*y = mu + w1*x(t,1) + w2*x(t,2) + w3*x(t,3) + w4*x(t,4) + u(t), u(t) = phi*u(t-1) + eps(t)*

- [x] Composite link matrix Z = [w1..w4]: free MLE weights, no parametric shape constraint
- [x] State-space setup in KFAS: AR(1) error, Kalman smoother diagnostics
- [x] Ridge penalty sensitivity: lambda grid {0, 0.001, 0.01, 0.1}, lambda=0 selected
- [x] Identifiability: Hessian positive definite, w1 and phi statistically significant
- [x] CLM-SS (4 lags): RMSE 0.03170 (+6.2% vs ARIMAX) — lag-limited, fails without history
- [x] CLM-SS (12 lags, 3 months): RMSE 0.02258 (-24.4% vs ARIMAX), ties U-MIDAS
- [x] CLM-SS weights peak at month -1 weeks 2-3 — independently confirms MIDAS lag hump at lag 5-6
- [x] phi drops 0.266 to 0.123 when lags extended (richer history absorbs AR dynamics)
- [x] Full 6-model comparison + DM tests saved
- [x] CLM-SS forecast vectors saved to data/processed/clmss_forecasts.rds

---

### Phase 6 — ML Benchmark Comparison (partially done)

*Script: 10_ml_benchmarks.R. Answers DJL requests for ML comparison.*

Note: The original Phase 6 (Simulation Study) has been replaced by this ML benchmark phase per DJL feedback. A simulation study is out of scope for the June 29 deadline.

#### 6a — Kernel U-MIDAS (non-parametric smoother, done)

- [x] Implemented a Breitung and Roling-style penalised least-squares smoother on 12 weekly lag weights using a second-difference roughness penalty
- [x] Lambda selected on 2013-2014 validation window; best lambda = 0, so the smoother collapses to unrestricted U-MIDAS
- [x] Kernel U-MIDAS RMSE 0.02226 (-25.5% vs ARIMAX), identical to U-MIDAS and behind MIDAS nbeta 0.02057 (-31.1%)
- [x] Estimated weights still peak at prior-month weeks 2-3, confirming the lag hump without a parametric nealmon/nbeta shape
- [x] Key thesis argument: non-parametric smoothing does not improve over U-MIDAS here; flexible weekly timing helps, but parametric MIDAS remains more accurate and interpretable

#### 6b — LSTM (recurrent neural network)

- [x] Implemented using torch package in R; torch backend installed successfully
- [x] Input: sequence of 12 weekly WTI log-diffs; output: 1-month-ahead CPI log-diff
- [x] Rolling expanding OOS evaluation on same 2015-2022 test period
- [x] Best validation setup: hidden size 4, 150 epochs, learning rate 0.010
- [x] LSTM RMSE 0.02588 (-13.3% vs ARIMAX), MAE 0.01840, directional accuracy 76.0%
- [x] Key thesis argument: LSTM beats ARIMAX but does not beat MIDAS, XGBoost, U-MIDAS, or Kernel U-MIDAS; in this small mixed-frequency dataset, deep learning adds complexity without improving the main MIDAS result

#### 6c — XGBoost (tree-based tabular reference)

- [x] Input: 12 weekly WTI lag columns + lagged CPI as tabular features
- [x] xgboost package with 5-fold CV for depth, eta, nrounds hyperparameters
- [x] Rolling window OOS RMSE on same 2015-2022 test period
- [x] Purpose: defend against DJL defense question "did you try XGBoost?"

#### 6d — Performance vs interpretability table

- [ ] Final table: Model | RMSE | Dir. Accuracy | Params | Interpretable? | Training time
- [ ] Key point: MIDAS nealmon achieves 80.2% directional accuracy with 4 parameters and full interpretability (lag weights have economic meaning); LSTM achieves 76.0% directional accuracy but higher complexity and lower interpretability

---

### Phase 7 — Extended Feature Selection + Diagnostics (partially done)

*Script: 11_extended_models.R*

#### 7a — LASSO-MIDAS (to do)

- [x] Apply LASSO penalty to U-MIDAS 12-lag coefficients via glmnet
- [x] Lambda selection by time-series cross-validation (not random k-fold)
- [x] Which weekly lags does LASSO zero out? Does LASSO data-adaptively recover the lag 5-6 hump?
- [x] Compare OOS RMSE to ridge CLM-SS, U-MIDAS, and MIDAS nbeta
- [x] Key thesis argument: LASSO discovers the same lag structure as the parametric shapes, confirming the hump is real

#### 7b — PCA on weekly WTI lags (done)

- [x] Build the 12-column WTI lag matrix; compute pairwise correlations and VIF
- [x] VIF result: max pairwise absolute correlation 0.254; median VIF 1.11; max VIF 1.25, so severe multicollinearity is not driving the MIDAS result
- [x] Run PCA and scree plot: 11 PCs needed to explain 95% of variance, meaning weekly WTI shocks are not easily compressed into a few components
- [x] PCA-ARIMAX benchmark with first 4 PCs: RMSE 0.02859 (-4.3% vs ARIMAX), far worse than MIDAS nbeta RMSE 0.02057 (-31.1%)
- [x] Key thesis argument: compression alone is not enough; preserving the weekly timing structure is what gives MIDAS its advantage

#### 7c — Segmented regression: structural breaks (done)

- [x] Base-R segmented break tests used because the segmented package was not installed; no new dependency needed
- [x] Candidate breaks tested: 2008 GFC/oil shock, 2014-16 oil collapse, 2020 COVID crash
- [x] Candidate break result: 2008 event is marginal (p=0.073); 2014 and 2020 are not significant in the simple y ~ WTI slope model
- [x] One-break grid search: best date by AIC is 2005-10, suggesting early-sample slope instability rather than a single clean crisis break
- [x] Sub-period OOS results: pre-COVID winner MIDAS nealmon; 2020 winner XGBoost; 2021-2022 winner U-MIDAS
- [x] Key thesis argument: MIDAS advantage is not purely a COVID artifact; mixed-frequency timing remains valuable across regimes, but the best model varies by regime

#### 7d — Extended metrics: directional accuracy (done)

- [x] Directional accuracy: MIDAS nealmon 80.2%, nbeta 74%, U-MIDAS 75%, ARIMAX 64.6%
- [x] Large-move hit rates: MIDAS nealmon/nbeta/U-MIDAS achieve 100% hit on both spikes and crashes; ARIMAX misses 50% of crashes
- [x] Precision (all models approx. 40%) and recall: nealmon 87.5%, nbeta 83.3%, ARIMAX 37.5%
- [x] Mincer-Zarnowitz: ARIMAX technically unbiased but with R2=0.056 (no predictive power); MIDAS models biased (beta approx. 0.75) but with R2 approx. 0.58
- [x] 3 figures saved: 14_directional_accuracy.png, 15_precision_recall.png, 16_mz_beta.png
- [x] Table saved: extended_metrics_all_models.csv

#### 7e — Forecast horizon validity analysis (new — based on oil literature)

*Answers user question: how long is it valid to predict WTI-to-CPI? What are our assumptions?*

- [x] **Assumption audit**: h=1 is a nowcast because WTI weeks from month t are used to predict CPI Energy for month t after the month closes; h=2 and h=3 are true forecasts using earlier WTI information.
- [x] **Horizon comparison**: h=1 nbeta RMSE 0.02057 (-31.1% vs ARIMAX); h=2 nbeta RMSE 0.02419 (-14.9%); h=3 nbeta RMSE 0.03023 (+2.2%, no MIDAS advantage).
- [x] **Predictability window from literature**: h=1 result is the main validity window; h=2 remains useful; h=3 fades, consistent with the 5-7 week lag evidence and oil transmission literature.
- [x] **Rolling subperiod analysis**: yearly RMSE table saved; COVID/recovery years shown explicitly in figure 22.
- [x] **Summary for thesis discussion**: this is primarily a one-month nowcasting study; the lag hump around prior-month weeks 2-3 is the interpretable transmission mechanism.

---

### Phase 8 — Written Thesis (due 29 June, max 30 pages)

- [ ] Cover page: title, supervisor, IE University, date, AI use declaration
- [ ] Abstract (150-250 words): problem, method, key result (MIDAS beats ARIMAX by 31%, 100% crash recall)
- [ ] Chapter 1 — Introduction (2-3 pages): the mixed-frequency problem, thesis contributions, structure
- [ ] Chapter 2 — Literature Review (3-4 pages): Phase 1 text, already written
- [ ] Chapter 3 — Methodology (4-5 pages):
  - [ ] Data: CPIENGSL, DCOILWTICO, PNRGINDEXM; FRED sources; sample; log-diff transformation
  - [ ] Benchmark models: ARIMAX, nealmon, nbeta, U-MIDAS with equations
  - [ ] CLM-SS formulation: Z matrix, AR(1) state, MLE via BFGS, identifiability
  - [ ] Evaluation: expanding window, RMSE, MAE, DM test, directional accuracy, MZ test
- [ ] Chapter 4 — Results (4-5 pages):
  - [ ] Table 1: In-sample AIC/BIC/RMSE for all models (Phase 4)
  - [ ] Table 2: OOS RMSE, MAE, directional accuracy, DM p-values (Phases 4+5+7d)
  - [ ] Table 3: Large-move precision and recall (Phase 7d)
  - [ ] Table 4: Performance vs interpretability trade-off (Phase 6d)
  - [ ] Figure: CLM-SS composite link weights bar chart
  - [ ] Figure: MIDAS lag weight hump (nealmon vs nbeta)
  - [ ] Figure: OOS forecast comparison line chart
- [ ] Chapter 5 — Discussion (2-3 pages):
  - [ ] When does MIDAS beat ARIMAX, and why (timing information vs. aggregation)
  - [ ] The MZ paradox: ARIMAX passes rationality test because it has no predictive power
  - [ ] Forecast horizon validity: this is a nowcasting study, 1-month-ahead, consistent with Kilian and Lewis (2011)
  - [ ] CLM-SS: free weights recover same hump as parametric MIDAS; AR errors add marginal value
  - [ ] Limitations: ridge CV, LSTM data requirements, energy-only domain
- [ ] Chapter 6 — Conclusions (1-2 pages):
  - [ ] Main findings; CLM-SS as interpretable bridge between ARIMAX and MIDAS
  - [ ] Future work: cross-validated ridge, multivariate extension, R package
- [ ] References (not in page count)
- [ ] Annex A — Individual Contribution Statement (submitted separately)

---

### Phase 9 — Poster (A0 format, due 29 June)

- [ ] Sections: Background, Research Question, Methodology, Results, Conclusion
- [ ] Key figures: figure 13 (6-model RMSE bar), figure 09 (CLM-SS weights), figure 14 (directional accuracy)
- [ ] Performance vs interpretability chart as visual centrepiece
- [ ] All figures at 300 DPI minimum
- [ ] PDF, portrait, 841 x 1189 mm

---

### Phase 10 — Code and Documentation

- [ ] set.seed(42) in all scripts (done in 09 and 07)
- [ ] All output figures in output/figures/ (done)
- [ ] All result tables in output/tables/ (done)
- [ ] Update 00_setup.R with new packages: xgboost, torch or keras, segmented
- [ ] GitHub commit all R scripts + Papers/ folder (22 MB, under 100 MB limit)

---

## Progress Summary

| Phase | Status | Key result |
| --- | --- | --- |
| Phase 0 — Setup | Done | R + midasr + GitHub |
| Phase 1 — Literature review | Done | 24 references, verified from PDFs, APA format |
| Phase 2 — USData benchmarks | Done | nealmon RMSE -51% vs ARIMAX, DM p=0.007 |
| Phase 3 — Energy EDA | Done | CPIENGSL + WTI weekly, 5 EDA plots |
| Phase 4 — Energy benchmarks | Done | nbeta RMSE 0.02057 (-31%), all DM p<0.001 |
| Phase 5 — CLM-SS | Done | CLM-SS(12) RMSE 0.02258 (-24%); confirms lag hump |
| Phase 7d — Directional accuracy | Done | nealmon 80.2% dir. acc.; 100% crash recall vs 50% ARIMAX |
| Phase 6 — ML benchmarks | Partial | Kernel U-MIDAS, XGBoost, and LSTM done; interpretability table remains |
| Phase 7a — LASSO-MIDAS | Done | RMSE 0.02103; largest lags wti_m1_w2 and wti_m1_w3 confirm hump |
| Phase 7b — PCA on WTI lags | Done | PCA-ARIMAX only -4.3% vs ARIMAX; MIDAS nbeta remains -31.1% |
| Phase 7c — Segmented regression | Done | MIDAS wins pre-COVID; XGBoost wins 2020; U-MIDAS wins recovery/spike |
| Phase 7e — Forecast horizon validity | Done | h=1 main window (-31.1%); h=2 useful (-14.9%); h=3 fades (+2.2%) |
| Phase 8 — Thesis writing | To do | Due 29 June 2026, 30 pages |
| Phase 9 — Poster | To do | Due 29 June 2026, A0 PDF |
| Phase 10 — Code cleanup | To do | |

---

## Key Results Table (updated with Phase 7d)

| Model | RMSE | vs ARIMAX | Dir. Acc. | Crash Recall | MZ beta | Interpretable |
| --- | --- | --- | --- | --- | --- | --- |
| ARIMAX | 0.02986 | baseline | 64.6% | 50% | 0.54 | Yes |
| U-MIDAS | 0.02226 | -25.5% | 75.0% | 100% | 0.70* | Partial |
| CLM-SS (12 lags) | 0.02258 | -24.4% | 74.0% | 100% | 0.70* | Yes |
| MIDAS nealmon | 0.02104 | -29.5% | 80.2% | 100% | 0.75* | Yes |
| MIDAS nbeta | 0.02057 | -31.1% | 74.0% | 100% | 0.78* | Yes |
| Kernel U-MIDAS | 0.02226 | -25.5% | 75.0% | 100% | TBD | Yes |
| XGBoost | 0.02365 | -20.8% | 72.9% | TBD | TBD | Partial |
| LSTM | 0.02588 | -13.3% | 76.0% | TBD | TBD | No |

*MZ p < 0.05: statistically biased but with high R2 (approx. 0.58). ARIMAX passes MZ only because R2=0.056 (no real predictive power).

---

## References (verified against Papers/ folder)

### MIDAS / Mixed-Frequency

- Ghysels, E., Santa-Clara, P., and Valkanov, R. (2004). The MIDAS touch: Mixed data sampling regression models. CIRANO Working Paper 2004s-20.
- Ghysels, E., Sinko, A., and Valkanov, R. (2007). MIDAS regressions: Further results and new directions. Econometric Reviews, 26(1), 53-90.
- Foroni, C., Marcellino, M., and Schumacher, C. (2015). Unrestricted mixed data sampling (MIDAS). Journal of the Royal Statistical Society: Series A, 178(1), 57-82.
- Breitung, J., and Roling, C. (2015). Forecasting inflation rates using daily data: A nonparametric MIDAS approach. Journal of Forecasting, 34, 588-603.
- Corsi, F. (2009). A simple approximate long-memory model of realized volatility. Journal of Financial Econometrics, 7(2), 174-196.
- Ghysels, E., and Marcellino, M. (2018). Applied Economic Forecasting Using Time Series Methods. Oxford University Press.

### State-Space / Kalman

- Mariano, R. S., and Murasawa, Y. (2003). A new coincident index of business cycles based on monthly and quarterly series. Journal of Applied Econometrics, 18(4), 427-443.
- Aruoba, S. B., Diebold, F. X., and Scotti, C. (2009). Real-time measurement of business conditions. Journal of Business and Economic Statistics, 27(4), 417-427.
- Helske, J. (2017). KFAS: Exponential family state space models in R. Journal of Statistical Software, 78(10), 1-39.
- Giannone, D., Reichlin, L., and Small, D. (2008). Nowcasting: The real-time informational content of macroeconomic data. Journal of Monetary Economics, 55(4), 665-676.
- Baffigi, A., Golinelli, R., and Parigi, G. (2004). Bridge models to forecast the euro area GDP. International Journal of Forecasting, 20(3), 447-460.

### ML / Regularisation

- Fischer, T., and Krauss, C. (2018). Deep learning with long short-term memory networks for financial market predictions. European Journal of Operational Research, 270(2), 654-669.
- Chen, T., and Guestrin, C. (2016). XGBoost: A scalable tree boosting system. Proceedings of KDD 2016, 785-794.
- Medeiros, M. C., Vasconcelos, G. F. R., Veiga, A., and Zilberman, E. (2021). Forecasting inflation in a data-rich environment: The benefits of machine learning methods. Journal of Business and Economic Statistics, 39(1), 98-119.
- Thompson, R., and Baker, R. J. (1981). Composite link functions in generalized linear models. Applied Statistics, 30(2), 125-131.

### Oil / Energy Domain

- Hamilton, J. D. (1983). Oil and the macroeconomy since World War II. Journal of Political Economy, 91(2), 228-248.
- Hamilton, J. D. (2009). Causes and consequences of the oil shock of 2007-08. Brookings Papers on Economic Activity, 2009(1), 215-261.
- Kilian, L. (2009). Not all oil price shocks are alike: Disentangling demand and supply shocks in the crude oil market. American Economic Review, 99(3), 1053-1069.
- Kilian, L., and Lewis, L. T. (2011). Does the Fed respond to oil price shocks? Economic Journal, 121(555), 1047-1072.
- Baumeister, C., and Hamilton, J. D. (2019). Structural interpretation of vector autoregressions with incomplete identification. American Economic Review, 109(5), 1873-1910.
- Baumeister, C., and Kilian, L. (2015). Forecasting the real price of oil in a changing world: A forecast combination approach. Journal of Business and Economic Statistics, 33(3), 338-351.
- Nonejad, N. (2022). New findings regarding the out-of-sample predictive impact of the price of crude oil on the United States industrial production. Journal of Business Cycle Research, 18, 1-35.
- Box, G. E. P., and Jenkins, G. M. (1970). Time Series Analysis: Forecasting and Control. Holden-Day.
- Sims, C. A. (1980). Macroeconomics and reality. Econometrica, 48(1), 1-48.
- Mariano, R. S., and Murasawa, Y. (2003). A new coincident index of business cycles based on monthly and quarterly series. Journal of Applied Econometrics, 18(4), 427-443.
