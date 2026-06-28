# Cross-Frequency Aggregation in Mixed-Frequency Time Series

## Forecasting US Consumer Energy Prices with Weekly Oil Data

**Author:** Stephan Stefanov Pentchev
**Supervisor:** Dae-Jin Lee, IE University
**Program:** Master in Business Analytics & Data Science, Advanced AI Concentration, IE University, 2026

[Thesis (PDF)](docs/Pentchev_2026_Thesis.pdf) | [Poster (PDF)](docs/Pentchev_2026_Poster.pdf)

---

## Overview

Standard time series models pre-aggregate high-frequency data before estimation, discarding the within-period timing information that may carry predictive signal. This thesis investigates whether preserving weekly WTI crude oil prices at their native frequency, rather than collapsing them to monthly means before fitting, improves one-month-ahead forecasts of US Consumer Energy CPI.

The main comparison is between ARIMAX (which uses monthly-averaged WTI as an external regressor) and the MIDAS family of models (Mixed Data Sampling), which directly embed the four weekly oil observations per month into the regression through a parameterised lag polynomial. A novel Composite Link Matrix State-Space (CLM-SS) formulation is developed and evaluated alongside machine-learning benchmarks including XGBoost and LSTM.

---

## Data

All series are sourced from the Federal Reserve Economic Data (FRED) database.

| Series | Description | Frequency | FRED Link |
| --- | --- | --- | --- |
| CPIENGSL | US Consumer Energy CPI (outcome variable) | Monthly | [fred.stlouisfed.org/series/CPIENGSL](https://fred.stlouisfed.org/series/CPIENGSL) |
| WCOILWTICO | WTI Crude Oil Spot Price (predictor) | Weekly | [fred.stlouisfed.org/series/WCOILWTICO](https://fred.stlouisfed.org/series/WCOILWTICO) |
| PNRGINDEXM | IMF Global Energy Price Index (context only, EDA only) | Monthly | [fred.stlouisfed.org/series/PNRGINDEXM](https://fred.stlouisfed.org/series/PNRGINDEXM) |

**Sample:** February 2000 to June 2026. Both series are transformed to monthly log-differences prior to modelling. The historical evaluation window covers January 2015 to December 2022 (96 pseudo out-of-sample one-step-ahead forecasts under an expanding window). A separate post-2022 external holdout (2023-2026) serves as an independent test of the findings.

The mixed-frequency ratio is m = 4 (four weekly WTI observations per monthly CPI observation), and models include up to K = 12 weekly lags (three months of WTI history).

---

## Methodology

### Benchmark: ARIMAX

The ARIMAX model uses the monthly mean of weekly WTI log-changes as a scalar external regressor, fitting an ARIMA structure on the residuals. This is the standard approach in applied forecasting and represents the cost of pre-aggregating high-frequency data before estimation.

### MIDAS Regression

MIDAS regresses the monthly outcome directly on a distributed lag of high-frequency observations, weighted by a low-dimensional parametric function:

$$y_t = \alpha + \beta \sum_{k=1}^{K} w(k;\,\theta)\, x_{t-k}^{(m)} + \varepsilon_t$$

where $x_{t-k}^{(m)}$ denotes the $k$-th weekly WTI log-change, and $w(k;\theta)$ is a normalised weighting function controlled by a small parameter vector $\theta$. Two lag-weight specifications are evaluated:

- **Normalised Beta (nbeta):** $w(k;\theta_1,\theta_2) \propto k^{\theta_1-1}(1-k)^{\theta_2-1}$: a flexible two-parameter Beta PDF shape that can represent humped, monotone, or U-shaped weighting profiles. This flexibility allows the model to discover a hump-shaped peak at the empirically relevant lag without imposing a functional form.
- **Exponential Almon (nealmon):** $w(k;\theta_1,\theta_2) \propto \exp(\theta_1 k + \theta_2 k^2)$: constrained to monotone decay or inverted-U shapes. Interpretable but less flexible than nbeta when the lag structure is asymmetric.

The application-specific formulation, with m = 4 weeks per month and K = 12 weekly lags:

$$y_t^{\text{CPI}} = \alpha + \beta \sum_{k=1}^{12} w(k;\,\hat{\theta})\, x_{t-k}^{\text{WTI}} + \varepsilon_t$$

Additional models in the evaluation suite: Unrestricted MIDAS (U-MIDAS), LASSO-MIDAS (glmnet penalty on U-MIDAS lag coefficients), Kernel U-MIDAS (Breitung and Roling, 2015), PCA-ARIMAX (first 4 principal components of the WTI lag matrix), XGBoost, and LSTM.

### Novel Contributions

Three models developed in this thesis go beyond directly applying existing methods off the shelf.

**CLM-SS (Composite Link Matrix State-Space):** Frames the mixed-frequency problem as exact temporal aggregation within a Kalman filter. The composite link matrix Z directly maps the K weekly regressors into the monthly observation equation, with AR(1) errors estimated via MLE using the KFAS package (Helske, 2017). Free MLE weights on Z, without a parametric shape constraint, allow the model to recover the lag structure entirely from the data, building on the composite link function theory of Thompson and Baker (1981).

**LASSO-MIDAS:** Applies L1 regularisation (Tibshirani, 1996) directly to the 12 free lag coefficients of U-MIDAS using the glmnet package (Friedman, Hastie, and Tibshirani, 2010), with lambda selected by time-series cross-validation. This allows the penalty to data-adaptively zero out irrelevant weekly lags and identify the predictive window without imposing a parametric shape. The resulting non-zero coefficients concentrate at prior-month weeks 2-3, independently confirming the transmission hump.

**Kernel U-MIDAS:** Implements the nonparametric lag smoother of Breitung and Roling (2015) using a second-difference roughness penalty on the 12 free U-MIDAS coefficients, with the smoothing parameter lambda selected on a held-out validation window. In this application, the optimal lambda is zero, meaning the penalty collapses to unrestricted U-MIDAS, but the estimated unsmoothed weights still recover the same lag hump, providing a nonparametric confirmation of the parametric MIDAS result.

---

## Key Results

### Historical Evaluation (2015-2022, 96 forecasts)

| Model | RMSE | vs ARIMAX | Dir. Accuracy | Crash Recall |
| --- | --- | --- | --- | --- |
| MIDAS nbeta | 0.02057 | **-31.1%** | 74.0% | 100% |
| LASSO-MIDAS | 0.02103 | -29.6% | 75.0% | 100% |
| MIDAS nealmon | 0.02104 | -29.5% | **80.2%** | 100% |
| U-MIDAS | 0.02226 | -25.5% | 75.0% | 100% |
| Kernel U-MIDAS | 0.02226 | -25.5% | 75.0% | 100% |
| CLM-SS (12 lags) | 0.02258 | -24.4% | 74.0% | 100% |
| XGBoost | 0.02365 | -20.8% | 72.9% | N/A |
| LSTM | 0.02588 | -13.3% | 76.0% | N/A |
| ARIMAX | 0.02986 | baseline | 64.6% | 50% |

MIDAS nbeta and nealmon improvements over ARIMAX are statistically significant (Diebold-Mariano test, p < 0.001). All MIDAS-family models achieve 100% recall on large downward price moves (crashes), compared with 50% for ARIMAX.

### Post-2022 External Holdout (2023-2026)

| Model | vs ARIMAX |
| --- | --- |
| MIDAS nbeta | **-16.0%** |
| MIDAS nealmon | -10.3% |
| ARIMAX | baseline |

The historical ranking holds on genuinely out-of-sample post-2022 data, though the MIDAS advantage narrows relative to the 2015-2022 period, consistent with a more uncertain post-pandemic price environment.

### Transmission Mechanism

Estimated MIDAS lag weights consistently peak at prior-month weeks 2-3 (approximately 5-7 weeks before the CPI observation date). This hump is independently confirmed by CLM-SS free weights (no parametric shape imposed) and by LASSO-MIDAS (which data-adaptively zeroes out most lags and retains the same prior-month window). The transmission delay is consistent with the oil-to-consumer-price literature (Kilian and Lewis, 2011; Baumeister and Kilian, 2015) and is the primary mechanism through which weekly timing information improves forecasts over monthly pre-aggregation.

---

## How MIDAS Performs Across Different Scenarios

Performance is not uniform across regimes, forecast horizons, or evaluation periods. The table below summarises which model wins and by how much in each scenario.

### By Economic Regime (2015-2022 in-sample period)

| Regime | Winner | vs ARIMAX | Key observation |
| --- | --- | --- | --- |
| 2015-2019 pre-COVID | LASSO-MIDAS | -23.6% | Parametric MIDAS (nbeta, nealmon) also competitive (-19% to -22%). Stable transmission makes all weekly models beneficial. |
| 2020 COVID crash | **XGBoost** | **-49.6%** | Parametric MIDAS fails badly: nbeta +94.9%, nealmon +163.1% vs ARIMAX. Tree-based methods handle the structural shock better; the parametric lag shapes assume a smooth oil-to-CPI linkage that breaks during the pandemic. |
| 2021-2022 recovery/spike | CLM-SS (12 lags) | -22.7% | U-MIDAS (-22.6%) and LASSO-MIDAS (-21.0%) are close behind. The flexible, unparameterised models adapt better during the inflationary spike than rigid nbeta/nealmon. |

The COVID period is the single scenario where the MIDAS advantage reverses. Parametric lag shapes (nbeta, nealmon) impose a smooth bell-curve weighting that cannot accommodate the abrupt, unprecedented demand collapse of 2020. XGBoost, which makes no assumptions about the functional form of the oil-CPI relationship, absorbs the structural shock more effectively.

### By Forecast Horizon

| Horizon | Interpretation | MIDAS nbeta vs ARIMAX | MIDAS nealmon vs ARIMAX |
| --- | --- | --- | --- |
| h = 1 (nowcast) | All 4 weeks of WTI from month t are available | +19.9% (ARIMAX wins) | +25.2% (ARIMAX wins) |
| h = 2 (1-month ahead) | Only prior-month WTI is used | **-31.8%** | -1.0% |
| h = 3 (2-months ahead) | WTI from 2 months ago | +10.7% (ARIMAX wins) | +11.3% (ARIMAX wins) |

The most striking result is at h = 2: MIDAS nbeta achieves a 31.8% RMSE reduction over ARIMAX. This corresponds to the lag structure peak (prior-month weeks 2-3), meaning the model is exploiting exactly the weekly timing window that the transmission mechanism predicts. At h = 1, ARIMAX is competitive because it already has access to within-month information. At h = 3, the oil-to-CPI signal has faded and neither model has a meaningful edge.

### Mincer-Zarnowitz Rationality Test

A counterintuitive result emerges from the MZ regression ($y_t = a + b\hat{y}_t + \varepsilon_t$): ARIMAX is technically the only "unbiased" model (MZ beta near 1, cannot reject $a=0, b=1$). However, this is because ARIMAX has essentially no predictive power (MZ R² = 0.056). MIDAS models appear "biased" (beta approximately 0.75, MZ p < 0.05) but have genuine predictive power (R² approximately 0.58). The MZ test penalises models that are directionally correct but miscalibrated in magnitude, which is a known limitation of the test in volatile, nonlinear series.

### PCA as a Compression Alternative

An alternative to MIDAS is to compress the 12-weekly-lag matrix via PCA before feeding it into ARIMAX. The result is telling: PCA-ARIMAX (4 principal components) achieves only -4.3% vs ARIMAX, far behind MIDAS nbeta at -31.1%. VIF analysis confirms that multicollinearity is not the reason MIDAS works (max VIF = 1.79, all well below the threshold of 5). The gain from MIDAS comes from preserving the within-month timing structure, not from dimensionality reduction.

---

## Conclusions

1. **Frequency matters, not just quantity.** Monthly pre-aggregation of weekly oil prices loses the within-month timing information responsible for most of the predictive signal. MIDAS recovers this by fitting the full weekly lag profile directly.

2. **MIDAS nbeta is the best overall model.** Across the 2015-2022 evaluation period, nbeta reduces RMSE by 31.1% versus ARIMAX (DM p < 0.001) and by 16.0% in the post-2022 external holdout. The flexible Beta shape, which can freely form a hump at the empirically identified prior-month weeks 2-3 transmission window, outperforms the more constrained nealmon in RMSE terms.

3. **MIDAS nealmon is the best directional model.** At 80.2% directional accuracy and 100% recall on large crash events, nealmon is the preferred model when getting the direction right matters more than minimising squared errors. ARIMAX achieves only 64.6% directional accuracy and misses 50% of large negative price moves.

4. **The 5-7 week transmission window is robust.** The lag hump at prior-month weeks 2-3 is recovered independently by nbeta (parametric MLE), CLM-SS (free Kalman filter weights), and LASSO-MIDAS (L1 regularisation that zeroes out irrelevant lags). Three very different estimation approaches converge on the same weekly window, which aligns with the oil-to-consumer-price literature.

5. **COVID is the exception, not the rule.** In 2020, parametric MIDAS models fail catastrophically because their smooth lag shapes cannot handle a structural demand shock of unprecedented magnitude. XGBoost, which makes no parametric assumptions, is the only model that beats ARIMAX during the pandemic. Outside crisis periods, parametric MIDAS is consistently superior.

6. **Machine learning does not replace MIDAS here.** XGBoost and LSTM both beat ARIMAX overall, but neither beats parametric MIDAS on the 2015-2022 period. On a dataset of 275 monthly observations, the compact parameterisation of nbeta/nealmon (2 parameters for the lag shape) provides better regularisation than the complex, data-hungry ML architectures.

7. **CLM-SS validates the approach.** The novel CLM-SS formulation, which uses a free composite link matrix inside a Kalman filter rather than a parametric lag polynomial, independently discovers the same lag structure. This confirms that the MIDAS result is not an artefact of the nbeta/nealmon functional form, but a genuine feature of the oil-to-CPI transmission channel.

---

## Repository Structure

```
midas_capstone/
├── docs/
│   ├── Pentchev_2026_Thesis.pdf          # Full thesis
│   └── Pentchev_2026_Poster.pdf          # A0 conference poster
├── R/
│   ├── 00_setup.R                        # Package installation (run once)
│   ├── 01_tutorial.R                     # USData proof-of-concept
│   ├── 02_arimax.R                       # ARIMAX benchmark
│   ├── 03_adl_midas.R                    # MIDAS nealmon and nbeta
│   ├── 04_umidas.R                       # Unrestricted MIDAS
│   ├── 05_comparison.R                   # In-sample comparison
│   ├── 06_rolling_window.R               # Rolling RMSE and DM test
│   ├── 07_clm_ss.R                       # CLM-SS (KFAS state-space)
│   ├── 08_energy_data.R                  # Energy EDA
│   ├── 09_benchmarks.R                   # Full benchmark suite on energy data
│   ├── 10_ml_benchmarks.R               # XGBoost, LSTM, Kernel U-MIDAS
│   ├── 11_extended_models.R             # LASSO, PCA, diagnostics, metrics
│   ├── 12_final_evaluation.R            # AIC/BIC, MASE, sMAPE
│   ├── 13_update_recent_data.R          # Post-2022 data refresh from FRED
│   ├── 14_future_forecast_3_scenarios.R # 1/3/6-month forward scenarios
│   └── 15_future_scenarios_12_months.R  # 12-month appendix extension
├── data/
│   ├── raw/                              # Downloaded FRED series (.rds / .csv)
│   └── processed/                        # Forecast vectors (.rds)
├── output/
│   ├── figures/                          # All plots (300 DPI PNG)
│   └── tables/                           # All result tables (CSV)
└── Papers/                               # Reference PDFs (24 verified papers)
```

---

## Reproducing the Results

### Requirements

- R >= 4.2
- Internet connection for the initial FRED data download (scripts 08 and 13)
- Approximately 10-15 minutes total runtime for all scripts
- The `torch` package (used in script 10 for LSTM) requires a one-time backend installation; follow the prompt when first running `library(torch)`

### Step-by-Step

#### Step 1: Install dependencies

```r
source("R/00_setup.R")
```

This installs all required packages: `midasr`, `forecast`, `KFAS`, `glmnet`, `xgboost`, `torch`, `quantmod`, `tseries`, `urca`, `dplyr`, `lmtest`, `sandwich`, `xts`, `zoo`, `httpgd`.

#### Step 2: Proof of concept on built-in data (optional)

```r
source("R/01_tutorial.R")   # USData in-sample: MIDAS vs ARIMAX
source("R/02_arimax.R")     # ARIMAX standalone
source("R/03_adl_midas.R")  # MIDAS nealmon and nbeta standalone
source("R/04_umidas.R")     # U-MIDAS standalone
source("R/06_rolling_window.R")  # Rolling window DM test on USData
```

#### Step 3: Energy data EDA

```r
source("R/08_energy_data.R")
```

Downloads CPIENGSL and WCOILWTICO from FRED, runs stationarity tests, and saves EDA figures to `output/figures/`.

#### Step 4: Full benchmark suite (core results)

```r
source("R/09_benchmarks.R")
```

Fits ARIMAX, MIDAS nealmon, MIDAS nbeta, and U-MIDAS on the energy data with an expanding window from 2000-2014 to 2015-2022. Saves 96-forecast evaluation vectors to `data/processed/phase4_forecasts.rds` and all figures/tables to `output/`.

#### Step 5: CLM-SS (novel contribution)

```r
source("R/07_clm_ss.R")
```

Fits the Composite Link Matrix State-Space model with 4 and 12 weekly lags using KFAS. Saves forecast vectors to `data/processed/clmss_forecasts.rds`.

#### Step 6: Machine learning benchmarks

```r
source("R/10_ml_benchmarks.R")
```

Fits XGBoost (5-fold CV hyperparameter tuning), LSTM (hidden size 4, 150 epochs), and Kernel U-MIDAS (second-difference roughness penalty). Requires the torch backend for LSTM.

#### Step 7: Extended diagnostics and metrics

```r
source("R/11_extended_models.R")
```

Fits LASSO-MIDAS, PCA-ARIMAX, computes segmented regime analysis, directional accuracy, precision/recall, and Mincer-Zarnowitz tests for all models. Saves figures 14-16 and all extended metrics to `output/tables/extended_metrics_all_models.csv`.

#### Step 8: Final evaluation

```r
source("R/12_final_evaluation.R")
```

Computes AIC/BIC, MASE, sMAPE, and MAPE for all applicable models. Saves to `output/tables/final_oos_forecast_metrics.csv`.

#### Step 9: Post-2022 external holdout

```r
source("R/13_update_recent_data.R")   # Refresh FRED data through June 2026
source("R/14_future_forecast_3_scenarios.R")   # 1/3/6-month forward scenarios
source("R/15_future_scenarios_12_months.R")    # 12-month appendix extension
```

Downloads updated CPIENGSL and WCOILWTICO from FRED, evaluates all models on the 2023-2026 holdout, and generates scenario fan charts.

### Outputs

All figures are written to `output/figures/` as 300 DPI PNG files. All numeric results are written to `output/tables/` as CSV files. No manual steps are required between scripts; each script reads only from `data/` and writes only to `output/`.

---

## References

### MIDAS and Mixed-Frequency Methods

Ghysels, E., Santa-Clara, P., and Valkanov, R. (2004). The MIDAS touch: Mixed data sampling regression models. CIRANO Working Paper 2004s-20.

Ghysels, E., Sinko, A., and Valkanov, R. (2007). MIDAS regressions: Further results and new directions. *Econometric Reviews*, 26(1), 53-90.

Foroni, C., Marcellino, M., and Schumacher, C. (2015). Unrestricted mixed data sampling (MIDAS). *Journal of the Royal Statistical Society: Series A*, 178(1), 57-82.

Breitung, J., and Roling, C. (2015). Forecasting inflation rates using daily data: A nonparametric MIDAS approach. *Journal of Forecasting*, 34, 588-603.

Corsi, F. (2009). A simple approximate long-memory model of realized volatility. *Journal of Financial Econometrics*, 7(2), 174-196.

Ghysels, E., and Marcellino, M. (2018). *Applied Economic Forecasting Using Time Series Methods*. Oxford University Press.

### State-Space and Nowcasting

Mariano, R. S., and Murasawa, Y. (2003). A new coincident index of business cycles based on monthly and quarterly series. *Journal of Applied Econometrics*, 18(4), 427-443.

Aruoba, S. B., Diebold, F. X., and Scotti, C. (2009). Real-time measurement of business conditions. *Journal of Business and Economic Statistics*, 27(4), 417-427.

Helske, J. (2017). KFAS: Exponential family state space models in R. *Journal of Statistical Software*, 78(10), 1-39.

Giannone, D., Reichlin, L., and Small, D. (2008). Nowcasting: The real-time informational content of macroeconomic data. *Journal of Monetary Economics*, 55(4), 665-676.

Baffigi, A., Golinelli, R., and Parigi, G. (2004). Bridge models to forecast the euro area GDP. *International Journal of Forecasting*, 20(3), 447-460.

Thompson, R., and Baker, R. J. (1981). Composite link functions in generalized linear models. *Applied Statistics*, 30(2), 125-131.

### Machine Learning and Regularisation

Tibshirani, R. (1996). Regression shrinkage and selection via the lasso. *Journal of the Royal Statistical Society: Series B*, 58(1), 267-288.

Friedman, J., Hastie, T., and Tibshirani, R. (2010). Regularization paths for generalized linear models via coordinate descent. *Journal of Statistical Software*, 33(1), 1-22.

Fischer, T., and Krauss, C. (2018). Deep learning with long short-term memory networks for financial market predictions. *European Journal of Operational Research*, 270(2), 654-669.

Chen, T., and Guestrin, C. (2016). XGBoost: A scalable tree boosting system. *Proceedings of KDD 2016*, 785-794.

Medeiros, M. C., Vasconcelos, G. F. R., Veiga, A., and Zilberman, E. (2021). Forecasting inflation in a data-rich environment: The benefits of machine learning methods. *Journal of Business and Economic Statistics*, 39(1), 98-119.

### Oil and Energy Economics

Hamilton, J. D. (1983). Oil and the macroeconomy since World War II. *Journal of Political Economy*, 91(2), 228-248.

Hamilton, J. D. (2009). Causes and consequences of the oil shock of 2007-08. *Brookings Papers on Economic Activity*, 2009(1), 215-261.

Kilian, L. (2009). Not all oil price shocks are alike: Disentangling demand and supply shocks in the crude oil market. *American Economic Review*, 99(3), 1053-1069.

Kilian, L., and Lewis, L. T. (2011). Does the Fed respond to oil price shocks? *Economic Journal*, 121(555), 1047-1072.

Baumeister, C., and Hamilton, J. D. (2019). Structural interpretation of vector autoregressions with incomplete identification. *American Economic Review*, 109(5), 1873-1910.

Baumeister, C., and Kilian, L. (2015). Forecasting the real price of oil in a changing world: A forecast combination approach. *Journal of Business and Economic Statistics*, 33(3), 338-351.

Nonejad, N. (2022). New findings regarding the out-of-sample predictive impact of the price of crude oil on the United States industrial production. *Journal of Business Cycle Research*, 18, 1-35.

### Econometrics and Time Series Foundations

Box, G. E. P., and Jenkins, G. M. (1970). *Time Series Analysis: Forecasting and Control*. Holden-Day.

Sims, C. A. (1980). Macroeconomics and reality. *Econometrica*, 48(1), 1-48.

Diebold, F. X., and Mariano, R. S. (1995). Comparing predictive accuracy. *Journal of Business and Economic Statistics*, 13(3), 253-263.
