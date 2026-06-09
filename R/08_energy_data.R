# ============================================================
# 08_energy_data.R — Phase 3: Energy Dataset Download + EDA
# Source: FRED (Federal Reserve Economic Data) via quantmod
#
# y = US Consumer Price Index: Energy (monthly, SA)
#     FRED: CPIENGSL | Units: Index 1982-84=100
#     → What US consumers pay for energy (gas, electricity, fuel)
#
# x = WTI Crude Oil Spot Price (weekly)
#     FRED: WCOILWTICO | Units: USD/barrel
#     → High-frequency upstream driver, m = 4 (weekly/monthly)
#
# ctx = IMF Global Price of Energy Index (monthly)
#       FRED: PNRGINDEXM | Units: Index 2016=100
#       → Upstream global commodity prices; EDA context only
#
# Transmission chain:
#   Global energy prices (PNRGINDEXM)
#     → WTI crude oil weekly (WCOILWTICO)       [high-freq driver]
#       → Consumer energy costs (CPIENGSL)       [monthly outcome]
#
# Sample: 2000-01 to 2022-12 | MIDAS ratio m = 4
# ============================================================

library(quantmod)
library(xts)
library(zoo)
library(tseries)
library(forecast)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("data/raw",       recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)

sample_start <- "2000-01-01"
sample_end   <- "2022-12-31"

# ============================================================
# STEP 1 — Download from FRED
# ============================================================
cat("Downloading from FRED...\n")
getSymbols("CPIENGSL",   src = "FRED", from = sample_start, to = sample_end)
getSymbols("WCOILWTICO", src = "FRED", from = sample_start, to = sample_end)
getSymbols("PNRGINDEXM", src = "FRED", from = sample_start, to = sample_end)
cat("Download complete.\n\n")

# ---- Consumer Energy CPI (monthly) -------------------------
cpi_raw <- CPIENGSL
colnames(cpi_raw) <- "cpi_energy"
cpi_raw <- window(cpi_raw, start = sample_start, end = sample_end)
cat("CPI Energy (CPIENGSL):", nrow(cpi_raw), "monthly obs |",
    format(start(cpi_raw), "%Y-%m"), "to", format(end(cpi_raw), "%Y-%m"), "\n")
cat("NAs:", sum(is.na(cpi_raw)), "\n")

# ---- WTI Oil (weekly) --------------------------------------
wti_weekly <- WCOILWTICO
colnames(wti_weekly) <- "wti_usd_bbl"
wti_weekly <- na.locf(wti_weekly, na.rm = FALSE)
wti_weekly <- na.omit(wti_weekly)
wti_weekly <- window(wti_weekly, start = sample_start, end = sample_end)
cat("\nWTI Oil (WCOILWTICO):", nrow(wti_weekly), "weekly obs\n")

# ---- IMF Global Energy Index (monthly, context only) -------
imf_raw <- PNRGINDEXM
colnames(imf_raw) <- "imf_energy_idx"
imf_raw <- window(imf_raw, start = sample_start, end = sample_end)
cat("\nIMF Energy Index (PNRGINDEXM):", nrow(imf_raw), "monthly obs\n")

# ---- Alignment check ---------------------------------------
cat("\nAlignment check:\n")
cat("  CPI Energy:  ", nrow(cpi_raw),    "monthly obs\n")
cat("  WTI weekly:  ", nrow(wti_weekly), "weekly obs\n")
cat("  Ratio:       ", round(nrow(wti_weekly) / nrow(cpi_raw), 2),
    "(target ≈ 4)\n\n")

# ============================================================
# STEP 2 — Transform to stationary series
# ============================================================
cpi_monthly <- diff(log(cpi_raw))
cpi_monthly <- na.omit(cpi_monthly)
colnames(cpi_monthly) <- "d_log_cpi_energy"

wti_wk <- diff(log(wti_weekly))
wti_wk <- na.omit(wti_wk)
colnames(wti_wk) <- "d_log_wti"

imf_monthly <- diff(log(imf_raw))
imf_monthly <- na.omit(imf_monthly)
colnames(imf_monthly) <- "d_log_imf_energy"

# ============================================================
# STEP 3 — ADF Stationarity Tests
# ============================================================
cat("=== ADF stationarity tests (H0: unit root) ===\n")
tests <- list(
  "CPI Energy (levels)"    = adf.test(na.omit(as.numeric(cpi_raw))),
  "CPI Energy (log-diff)"  = adf.test(as.numeric(cpi_monthly)),
  "WTI weekly (levels)"    = adf.test(na.omit(as.numeric(wti_weekly))),
  "WTI weekly (log-diff)"  = adf.test(as.numeric(wti_wk)),
  "IMF Index (levels)"     = adf.test(na.omit(as.numeric(imf_raw))),
  "IMF Index (log-diff)"   = adf.test(as.numeric(imf_monthly))
)
for (nm in names(tests)) {
  p <- tests[[nm]]$p.value
  cat(sprintf("  %-30s p = %.3f  %s\n", nm, p,
              ifelse(p < 0.05, "STATIONARY", "non-stationary")))
}

# ============================================================
# STEP 4 — Build merged monthly data frame for correlations
# ============================================================
cpi_df <- data.frame(ym = as.yearmon(index(cpi_raw)), cpi = as.numeric(cpi_raw))
wti_monthly_avg <- apply.monthly(wti_weekly, function(x) mean(x))
wti_df <- data.frame(
  ym  = as.yearmon(index(wti_monthly_avg)),
  wti = as.numeric(wti_monthly_avg)
)
imf_df <- data.frame(ym = as.yearmon(index(imf_raw)), imf = as.numeric(imf_raw))

merged_df <- Reduce(function(a, b) merge(a, b, by = "ym"),
                    list(cpi_df, wti_df, imf_df))
merged_df <- na.omit(merged_df)

cat("\nCorrelations (monthly levels):\n")
cat(sprintf("  WTI oil   vs CPI Energy:     r = %.3f\n",
            cor(merged_df$wti, merged_df$cpi)))
cat(sprintf("  IMF Index vs CPI Energy:     r = %.3f\n",
            cor(merged_df$imf, merged_df$cpi)))
cat(sprintf("  IMF Index vs WTI oil:        r = %.3f\n",
            cor(merged_df$imf, merged_df$wti)))

# ============================================================
# STEP 5 — EDA Plots (5 separate windows + saved as PNG 300 DPI)
# All using base R plot() with explicit Date vectors —
# avoids plot.xts() layout() conflict with par(mfrow) and png()
# ============================================================

# Pre-extract Date + numeric vectors for all series
d_cpi_lv  <- as.Date(index(cpi_raw));     v_cpi_lv  <- as.numeric(cpi_raw)
d_wti_lv  <- as.Date(index(wti_weekly));  v_wti_lv  <- as.numeric(wti_weekly)
d_imf_lv  <- as.Date(index(imf_raw));     v_imf_lv  <- as.numeric(imf_raw)
d_cpi_df  <- as.Date(index(cpi_monthly)); v_cpi_df  <- as.numeric(cpi_monthly)
d_wti_df  <- as.Date(index(wti_wk));      v_wti_df  <- as.numeric(wti_wk)

# Helper: render a plot to screen then save to PNG
render <- function(plot_fn, file, w, h) {
  dev.new()        # new screen window
  plot_fn()
  png(file, width = w, height = h, units = "in", res = 300)
  plot_fn()
  invisible(dev.off())
  cat("Saved:", file, "\n")
}

# Scatter helper
scatter_panel <- function(x, y, col, main, xlab, ylab) {
  plot(x, y, pch = 16, col = adjustcolor(col, 0.5), cex = 0.8,
       main = main, xlab = xlab, ylab = ylab)
  abline(lm(y ~ x), col = "black", lwd = 2)
  legend("topleft", bty = "n", cex = 0.9,
         legend = sprintf("r = %.2f", cor(x, y)))
}

# --- 5a: Raw levels -----------------------------------------
render(function() {
  par(mfrow = c(3, 1), mar = c(3, 4, 3, 1))
  plot(d_cpi_lv, v_cpi_lv, type = "l", col = "steelblue", lwd = 1.5,
       main = "US Consumer Energy CPI (monthly, SA) — CPIENGSL",
       xlab = "", ylab = "Index (1982-84=100)")
  plot(d_wti_lv, v_wti_lv, type = "l", col = "firebrick", lwd = 1,
       main = "WTI Crude Oil Price (weekly) — WCOILWTICO",
       xlab = "", ylab = "USD/barrel")
  plot(d_imf_lv, v_imf_lv, type = "l", col = "darkorange", lwd = 1.5,
       main = "IMF Global Energy Price Index (monthly) — PNRGINDEXM",
       xlab = "", ylab = "Index (2016=100)")
  par(mfrow = c(1, 1))
}, "output/figures/01_energy_levels.png", 11, 8)

# --- 5b: Log-differenced series -----------------------------
render(function() {
  par(mfrow = c(2, 1), mar = c(3, 4, 3, 1))
  plot(d_cpi_df, v_cpi_df, type = "l", col = "steelblue", lwd = 1.5,
       main = "Monthly Log-Change: Consumer Energy CPI",
       xlab = "", ylab = "log-diff")
  abline(h = 0, col = "grey50", lty = 2)
  plot(d_wti_df, v_wti_df, type = "l", col = "firebrick", lwd = 1,
       main = "Weekly Log-Change: WTI Crude Oil",
       xlab = "", ylab = "log-diff")
  abline(h = 0, col = "grey50", lty = 2)
  par(mfrow = c(1, 1))
}, "output/figures/02_energy_log_diff.png", 11, 6)

# --- 5c: ACF / PACF -----------------------------------------
render(function() {
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  Acf(v_cpi_df,  main = "ACF — CPI Energy (log-diff)",  lag.max = 24)
  Pacf(v_cpi_df, main = "PACF — CPI Energy (log-diff)", lag.max = 24)
  Acf(v_wti_df,  main = "ACF — WTI Weekly (log-diff)",  lag.max = 52)
  Pacf(v_wti_df, main = "PACF — WTI Weekly (log-diff)", lag.max = 52)
  par(mfrow = c(1, 1))
}, "output/figures/03_energy_acf_pacf.png", 11, 7)

# --- 5d: STL decomposition ----------------------------------
cpi_ts     <- ts(v_cpi_lv, start = c(2000, 1), frequency = 12)
cpi_decomp <- stl(cpi_ts, s.window = "periodic")
render(function() {
  plot(cpi_decomp,
       main = "STL Decomposition: US Consumer Energy CPI (monthly)")
}, "output/figures/04_cpi_stl_decomp.png", 10, 8)

# --- 5e: Transmission chain scatter -------------------------
render(function() {
  par(mfrow = c(1, 3), mar = c(5, 4, 4, 1))
  scatter_panel(merged_df$imf, merged_df$cpi, "darkorange",
                "Global Energy Index\nvs Consumer Energy CPI",
                "IMF Energy Index (2016=100)", "CPI Energy (1982-84=100)")
  scatter_panel(merged_df$wti, merged_df$cpi, "firebrick",
                "WTI Crude Oil\nvs Consumer Energy CPI",
                "WTI oil (USD/barrel)", "CPI Energy (1982-84=100)")
  scatter_panel(merged_df$imf, merged_df$wti, "steelblue",
                "Global Energy Index\nvs WTI Crude Oil",
                "IMF Energy Index (2016=100)", "WTI oil (USD/barrel)")
  par(mfrow = c(1, 1))
}, "output/figures/05_transmission_chain_scatter.png", 12, 5)

# ============================================================
# STEP 6 — Summary statistics
# ============================================================
cat("\n=== Summary statistics ===\n")
cat("\nCPI Energy (index levels):\n")
print(summary(as.numeric(cpi_raw)))
cat("\nWTI oil (USD/barrel, weekly):\n")
print(summary(as.numeric(wti_weekly)))
cat("\nIMF Global Energy Index:\n")
print(summary(as.numeric(imf_raw)))

# ============================================================
# STEP 7 — Save processed data
# ============================================================
saveRDS(cpi_monthly, "data/processed/cpi_energy_log_diff_monthly.rds")
saveRDS(wti_wk,      "data/processed/wti_log_diff_weekly.rds")
saveRDS(cpi_raw,     "data/processed/cpi_energy_levels_monthly.rds")
saveRDS(wti_weekly,  "data/processed/wti_levels_weekly.rds")
saveRDS(imf_raw,     "data/processed/imf_energy_levels_monthly.rds")

saveRDS(cpi_raw,     "data/raw/fred_CPIENGSL_historical.rds")
saveRDS(wti_weekly,  "data/raw/fred_WCOILWTICO_historical.rds")
saveRDS(wti_weekly,  "data/raw/fred_WTI_weekly_historical.rds")
saveRDS(imf_raw,     "data/raw/fred_PNRGINDEXM_historical.rds")

cat("\n=== Data documentation ===\n")
cat("Source:      FRED — Federal Reserve Bank of St. Louis\n")
cat("CPIENGSL:    Consumer Price Index, Energy (SA, monthly)\n")
cat("             https://fred.stlouisfed.org/series/CPIENGSL\n")
cat("WCOILWTICO:  WTI Crude Oil Spot Price (weekly)\n")
cat("             https://fred.stlouisfed.org/series/WCOILWTICO\n")
cat("PNRGINDEXM:  IMF Global Price of Energy Index (monthly)\n")
cat("             https://fred.stlouisfed.org/series/PNRGINDEXM\n")
cat("Downloaded: ", format(Sys.Date(), "%d %B %Y"), "\n")
cat("Sample:      2000-01 to 2022-12\n")
cat("Transform:   Log-difference for stationarity\n")
cat("MIDAS setup: y = CPIENGSL (monthly) | x = WCOILWTICO (weekly) | m = 4\n")
cat("Raw caches:  data/raw/fred_*_historical.rds\n")
