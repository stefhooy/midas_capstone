# MIDAS Capstone — Exact Cross-Frequency Aggregation in Mixed-Frequency Time Series

**Student:** Stephan Pentchev | **Supervisor:** Dae-jin Lee (IE University)

**Deadline:** Thesis + Poster → 29 June 2026 | Defense → 7 July 2026

---

## Project Overview

This project develops **CLM-SS** (Composite Link Matrix State-Space), a principled approach to exact cross-frequency aggregation that replaces the ad hoc pre-aggregation used by ARIMAX and standard MIDAS.

**Core research questions:**

1. Who are MIDAS's natural competitors in the mixed-frequency literature?
2. Is MIDAS competitive in an energy/financial setting?

---

## Repository Structure

```text
midas_capstone/
├── R/
│   ├── 00_setup.R          # Package installation
│   ├── 01_tutorial.R       # MIDAS tutorial: USrealgdp + USunempr (m=12)
│   ├── 02_arimax.R         # Benchmark 1: ARIMAX (pre-aggregate → ARIMA + X)
│   ├── 03_adl_midas.R      # Benchmark 2: ADL-MIDAS (nealmon / nbeta weights)
│   ├── 04_umidas.R         # Benchmark 3: U-MIDAS (unrestricted OLS)
│   ├── 05_clm_ss.R         # Novel: CLM-SS state-space formulation (KFAS)
│   └── 06_evaluation.R     # Rolling window RMSE/MAE + Diebold-Mariano test
├── data/
│   ├── raw/                # Original downloaded datasets
│   └── processed/          # Cleaned / aligned series
├── output/
│   ├── figures/            # All plots (saved as .pdf or .png)
│   └── tables/             # Forecast error tables (saved as .csv)
└── README.md
```

---

## Phases & Checklist

### Phase 0 — Setup

- [x] Install R packages: `midasr`, `forecast`, `quantmod`, `KFAS`, `tseries`, `urca`, `ggplot2`, `dplyr`
- [x] Initialize GitHub repo (`midas_capstone`)
- [x] Set up folder structure

### Phase 1 — Tutorial (USrealgdp + USunempr, m=12)

- [x] Step 1: Load & inspect data — `frequency()`, `start()`, `end()`, raw plots
- [x] Step 2: Stationarity transforms — `diff(log(GDP))`, `diff(unemp)`, plot
- [ ] Step 3: Fit first MIDAS model — `midas_r()` with `nealmon` weights
- [ ] Step 4: Try `nbeta` weights, compare lag shapes with `plot_midas_coef()`
- [ ] Step 5: ARIMAX benchmark on same data
- [ ] Step 6: Rolling window forecast — RMSE / MAE comparison

### Phase 2 — Literature Review (DJL Q1)

- [ ] Map MIDAS competitors: ARIMAX, U-MIDAS, MF-VAR, bridge equations, nowcasting
- [ ] Summarize Ghysels & Marcellino Ch. 12 (pp. 453-502)
- [ ] Build competitor comparison table (method, assumptions, flexibility, software)
- [ ] Read Ghysels et al. (2004, 2007), Foroni et al. (2015), Marcellino & Schumacher (2010)

### Phase 3 — Empirical Application (DJL Q2)

- [ ] Choose energy dataset (WTI oil daily, electricity prices, or power demand)
- [ ] Download and clean data (`quantmod` / FRED API)
- [ ] Run all 4 models on energy data
- [ ] Rolling window evaluation: RMSE, MAE, Diebold-Mariano test
- [ ] Answer: Is MIDAS competitive vs ARIMAX / U-MIDAS in this setting?

### Phase 4 — CLM-SS (Novel Contribution)

- [ ] Formulate composite link matrix (aggregation constraint)
- [ ] State-space representation with `KFAS`
- [ ] Estimate model, compare forecasts to benchmarks
- [ ] Validate exact aggregation property

### Phase 5 — Write-Up

- [ ] Abstract (150-250 words)
- [ ] Introduction (motivation, research gap)
- [ ] Literature Review (Phase 2 output)
- [ ] Methodology (MIDAS, CLM-SS formulation)
- [ ] Results (Phase 3 + 4 tables/figures)
- [ ] Discussion & Conclusions
- [ ] Poster (A0 portrait)

---

## Key References

- Ghysels, E. & Marcellino, M. (2018). *Applied Economic Forecasting using Time Series Methods*. Oxford. **Chapter 12.**
- Ghysels, E., Santa-Clara, P., Valkanov, R. (2004). The MIDAS Touch. *CIRANO Working Paper.*
- Foroni, C., Marcellino, M., Schumacher, C. (2015). Unrestricted mixed data sampling (MIDAS). *J. Royal Stat. Soc. A*, 178(1).
- midasr package: Kvedaras & Zemlys-Balevičius (CRAN 2025-04-07)

---

Check-in: **2 June 2026** | Thesis due: **29 June 2026** | Defense: **7 July 2026**
