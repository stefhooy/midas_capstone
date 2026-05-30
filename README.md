# MIDAS Capstone — Exact Cross-Frequency Aggregation in Mixed-Frequency Time Series

**Student:** Stephan Pentchev | **Supervisor:** Dae-jin Lee (IE University)

**Deadline:** Thesis + Poster → 29 June 2026 | Defense → 7 July 2026

---

## Hard Deadlines

| Date               | Event                                                       |
| ------------------ | ----------------------------------------------------------- |
| Tue 2 June 2026    | Check-in session — progress review + confirm final scope    |
| Mon 29 June 2026   | Submit thesis (max 30 pages) + A0 poster (by 12:00)        |
| Tue 7 July 2026    | Oral defense — 15 min presentation + 15 min Q&A            |

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
│   ├── 05_comparison.R     # Side-by-side in-sample comparison table + plots
│   ├── 06_rolling_window.R # Out-of-sample rolling RMSE/MAE + DM test ✓
│   ├── 07_clm_ss.R         # Phase 5: CLM-SS state-space scaffold (KFAS)
│   ├── 08_energy_data.R    # Phase 3: energy dataset download + EDA
│   ├── 09_benchmarks.R     # Phase 4: full benchmark suite on energy data
│   ├── 10_simulation.R     # Phase 6: simulation study
│   ├── 11_lasso_midas.R    # Phase 7: LASSO-MIDAS extension
│   └── archive/            # Old broken drafts (kept for reference)
├── data/
│   ├── raw/                # Original downloaded datasets
│   └── processed/          # Cleaned / aligned series
├── output/
│   ├── figures/            # All plots (300 DPI+)
│   └── tables/             # Forecast error tables (.csv)
└── README.md
```

---

## Full Checklist

### Phase 0 — Environment Setup

- [x] R + midasr working in VSCode (Alt+Enter / Ctrl+Shift+S)
- [x] Packages installed: `midasr`, `forecast`, `quantmod`, `KFAS`, `tseries`, `urca`, `ggplot2`, `dplyr`, `lmtest`, `sandwich`
- [x] Sanity check: `data("USrealgdp"); plot(USrealgdp)` — loads correctly
- [x] Project folder structure created + GitHub repo initialized

---

### Phase 1 — Answer Supervisor Q1: Who are MIDAS's competitors?

*Becomes the Literature Review section.*

- [ ] Write competitor comparison table:

| Model | Mixed-freq native? | Aggregation approach | Key limitation vs CLM-SS |
|-------|--------------------|----------------------|--------------------------|
| ARIMAX | No | Pre-average (mean/sum) | Information loss, ad hoc |
| ADL-MIDAS (`midas_r`) | Yes | Almon/Beta lag shape | Assumes parametric decay |
| U-MIDAS (`midas_u`) | Yes | Unrestricted OLS | Too many params, unstable |
| Non-param MIDAS (`midas_r_np`) | Yes | Breitung's smoother | No exact aggregation |
| HAR-RV (`harstep`) | Partial | Fixed 1/5/22-day avg | Very rigid structure |
| MF-VAR / Kalman | Yes | State-space | Complex, many variables needed |
| Bridge equations | Partial | Pre-aggregation shortcut | Still ad hoc |
| NowCasting (BDFM) | Yes | Kalman + EM | Needs many series, complex |
| **CLM-SS (this thesis)** | **Yes — exact** | **Composite link matrix** | **Novel, needs validation** |

- [ ] Write 1-paragraph summary per competitor for Literature Review
- [ ] Note which are implemented in `midasr` (saves coding effort)
- [ ] Use Connected Papers (start: Ghysels 2004 + Marcellino "Forecasting with Mixed Frequencies")
- [ ] Find 8-12 core references via SciSpace / Google Scholar

---

### Phase 2 — Answer Supervisor Q2: Is MIDAS competitive in energy/financial setting?

*Becomes the empirical application section.*

#### Step 2a — Built-in data (zero setup)

- [x] Load `USrealgdp` + `USunempr`, inspect, transform to stationary series
- [x] Fit `midas_r()` with `nealmon` weights — `AIC: -390.5` (best in-sample)
- [x] Fit `midas_r()` with `nbeta` weights — compare lag shapes with `plot_midas_coef()`
- [x] Fit `midas_u()` (U-MIDAS) — unrestricted OLS

#### Step 2b — ARIMAX baseline

- [x] Aggregate monthly unemployment to annual mean
- [x] Fit `auto.arima(y, xreg = x_annual)` — `AIC: -342.5`
- [x] In-sample comparison: nealmon beats ARIMAX by ~48 AIC points

#### Step 2c — Rolling window evaluation ✓ DONE

- [x] Manual expanding loop: train 1949–(t-1), forecast year t, test 2000-2011
- [x] RMSE: nealmon **0.0077** vs ARIMAX **0.0159** (nealmon −51%) | MAE: 0.0058 vs 0.0142
- [x] Plot: actual vs MIDAS forecast vs ARIMAX forecast (06_rolling_window.R)
- [x] Diebold-Mariano test: DM = −2.93, **p = 0.007** — MIDAS significantly better
- [x] Write 1-page answer: when does MIDAS win, when does ARIMAX win? ← still to do

---

### Phase 3 — Energy Dataset

- [ ] Pick dataset: monthly electricity price + daily WTI oil from FRED
- [ ] Load via `quantmod::getSymbols("DCOILWTICO", src="FRED")`
- [ ] Align frequencies using `mlsd()` or manual indexing
- [ ] EDA: time series plots, ACF/PACF, cross-frequency scatter, seasonal decomposition
- [ ] Document data source, date accessed, units, transformations

---

### Phase 4 — Full Benchmark Suite (on energy data)

- [ ] ARIMAX: aggregate daily → monthly, `auto.arima()` with exogenous
- [ ] ADL-MIDAS nealmon: `midas_r()` with exponential Almon weights
- [ ] ADL-MIDAS nbeta: `midas_r()` with normalized beta weights
- [ ] U-MIDAS: `midas_u()` unrestricted OLS
- [ ] Non-parametric MIDAS: `midas_r_np()` (Breitung smoother)
- [ ] Model selection: `hf_lags_table()` + `lf_lags_table()` for AIC/BIC lag choice
- [ ] Rolling window RMSE/MAE table for all models
- [ ] Diebold-Mariano test: MIDAS vs ARIMAX significance

---

### Phase 5 — CLM-SS Framework (Novel Contribution)

- [ ] Formalize composite link matrix Z (maps high-freq state → low-freq observation)
- [ ] State-space setup in `KFAS` or `dlm`
- [ ] Add ARIMA errors to state equation
- [ ] Implement penalized likelihood (log-lik + ridge/lasso on lag weights)
- [ ] Identifiability check: confirm estimable with data dimensions
- [ ] Estimate on energy dataset, compare forecasts to Phase 4 benchmarks

---

### Phase 6 — Simulation Study

- [ ] Define DGP: synthetic monthly outcome + daily covariate with known decay weights
- [ ] Vary: frequency ratio (4×, 12×), sample size (T=50, 100, 200), noise level
- [ ] Run 100+ replications per scenario — all methods side by side
- [ ] Report: bias, RMSE, confidence interval coverage
- [ ] Visualize: boxplots of RMSE by method and scenario

---

### Phase 7 — Feature Selection (LASSO extension)

- [ ] Regularized MIDAS: penalize unrestricted lag coefficients (U-MIDAS + LASSO)
- [ ] Compare: U-MIDAS vs LASSO-selected vs parametric ADL-MIDAS
- [ ] Identify which daily lags matter most for energy outcome

---

### Phase 8 — Written Thesis (max 30 pages, due 29 June)

- [ ] Cover page (title, supervisor, program, date, AI use declaration)
- [ ] Abstract (150-250 words)
- [ ] Introduction (2-3 pages)
- [ ] Literature Review — Phase 1 output (3-4 pages)
- [ ] Methodology — CLM-SS framework + benchmarks (4-5 pages)
- [ ] Results — simulation tables + energy forecast comparison (4-5 pages)
- [ ] Discussion (2-3 pages)
- [ ] Conclusions + future work / R package idea (1-2 pages)
- [ ] References (not counted in page limit)
- [ ] Annex A — Individual Contribution Statement (max 1 page, submitted separately)

---

### Phase 9 — Poster (A0 format, due 29 June)

- [ ] Sections: Background → Research Aim → Methodology → Results → Conclusion
- [ ] Publication-quality figures only (300 DPI+)
- [ ] Submit as PDF, portrait orientation (841 × 1189 mm)

---

### Phase 10 — Code & Documentation

- [ ] Clean, readable R scripts with reproducible seeds (`set.seed()`)
- [ ] All output figures saved to `output/figures/`
- [ ] All result tables saved to `output/tables/`
- [ ] (Stretch) Package with `devtools` as minimal R package

---

## Immediate Priority — Before 2 June Check-in

1. **[DONE]** Run MIDAS tutorial on USData — `midas_r()`, nealmon, nbeta, ARIMAX in-sample
2. **[NEXT]** Phase 2c rolling window — RMSE/MAE + Diebold-Mariano test on USData
3. **[NEXT]** Phase 1 competitor table — written answer to Q1
4. **Before 2 June** — working script + preliminary results to show DJL

---

## Key References

- Ghysels, E. & Marcellino, M. (2018). *Applied Economic Forecasting using Time Series Methods*. Oxford. **Chapter 12.**
- Ghysels, E., Santa-Clara, P., Valkanov, R. (2004). The MIDAS Touch. *CIRANO Working Paper.*
- Foroni, C., Marcellino, M., Schumacher, C. (2015). Unrestricted mixed data sampling (MIDAS). *J. Royal Stat. Soc. A*, 178(1).
- Marcellino, M. & Schumacher, C. (2010). Factor MIDAS for nowcasting and forecasting. *J. Applied Econometrics.*
- midasr package: Kvedaras & Zemlys-Balevičius (CRAN 2025-04-07)

---