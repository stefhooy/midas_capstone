# ============================================================
# 09_benchmarks.R — Phase 4: Full Benchmark Suite (Energy Data)
# y = CPIENGSL monthly log-diff (consumer energy CPI)
# x = DCOILWTICO weekly log-diff (WTI crude oil, m = 4)
#
# Models:  ARIMAX | ADL-MIDAS nealmon | ADL-MIDAS nbeta | U-MIDAS
# Section: In-sample AIC/BIC | Lag selection | Rolling window OOS
# Output:  3 PNG figures + 2 CSV tables
# For Phase 5: CLM-SS DM tests run 09_benchmarks.R and then run 07_clm_ss.R
# ============================================================

library(midasr)
library(forecast)
library(xts)
library(zoo)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables",  recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# ============================================================
# STEP 1 — Load processed data from Phase 3
# ============================================================
cpi_monthly <- readRDS("data/processed/cpi_energy_log_diff_monthly.rds")
wti_wk      <- readRDS("data/processed/wti_log_diff_weekly.rds")

cat("Loaded from Phase 3:\n")
cat("  CPI Energy (monthly log-diff):", nrow(cpi_monthly), "obs |",
    format(start(cpi_monthly), "%Y-%m"), "to",
    format(end(cpi_monthly),   "%Y-%m"), "\n")
cat("  WTI Oil (weekly log-diff):    ", nrow(wti_wk), "obs |",
    format(start(wti_wk), "%Y-%m"), "to",
    format(end(wti_wk),   "%Y-%m"), "\n\n")

# ============================================================
# STEP 2 — Build m = 4 aligned high-frequency vector
# ============================================================
# apply.weekly() gives ~4.35 weeks per month (calendar weeks cross month
# boundaries). Here we take the last 4 weekly obs within each calendar
# month, enforcing exactly m = 4 high-freq obs per low-freq period.
# Months with fewer than 4 weekly obs (rare) are padded from the prior
# month's trailing weekly values.

build_midas_x <- function(wti_series, cpi_index) {
  months    <- as.yearmon(cpi_index)
  wti_dates <- as.Date(index(wti_series))
  wti_vals  <- as.numeric(wti_series)
  n         <- length(months)
  x_mat     <- matrix(NA_real_, nrow = n, ncol = 4L)

  for (i in seq_len(n)) {
    m_start  <- as.Date(months[i])
    m_end    <- as.Date(months[i] + 1/12) - 1L   # last day of month i
    in_month <- which(wti_dates >= m_start & wti_dates <= m_end)

    if (length(in_month) >= 4L) {
      sel <- tail(in_month, 4L)
    } else {
      before <- which(wti_dates < m_start)
      pad    <- tail(before, 4L - length(in_month))
      sel    <- c(pad, in_month)
    }
    x_mat[i, ] <- wti_vals[sel]
  }
  # Row-major flatten: x_all[(t-1)*4+1 : t*4] = week1..week4 of month t
  as.vector(t(x_mat))
}

y_all    <- as.numeric(cpi_monthly)
x_all    <- build_midas_x(wti_wk, index(cpi_monthly))
n_months <- length(y_all)

stopifnot(length(x_all) == 4L * n_months)
cat("MIDAS x aligned: length =", length(x_all),
    "=", n_months, "months x 4 weeks/month\n\n")

# ============================================================
# STEP 3 — Monthly WTI series for ARIMAX
# ============================================================
# Each month's xreg = mean of its 4 weekly WTI log-diff obs
x_monthly <- vapply(seq_len(n_months), function(i)
  mean(x_all[((i - 1L) * 4L + 1L) : (i * 4L)]),
  numeric(1L))

# ============================================================
# STEP 4 — In-sample model comparison (full 2000-2022 sample)
# ============================================================
cat("=== In-sample comparison (2000-2022, k=3) ===\n")

fit_arimax_is <- auto.arima(y_all, xreg = x_monthly, ic = "aic",
                             stepwise = FALSE, approximation = FALSE)

fit_nealmon_is <- midas_r(y_all ~ fmls(x_all, 3, 4, nealmon),
                           start = list(x_all = c(0, 0, 0)))

fit_nbeta_is   <- midas_r(y_all ~ fmls(x_all, 3, 4, nbeta),
                           start = list(x_all = c(1, 1, 5)))

fit_umidas_is  <- midas_u(y_all ~ fmls(x_all, 3, 4))

is_table <- data.frame(
  Model  = c("ARIMAX", "ADL-MIDAS nealmon", "ADL-MIDAS nbeta", "U-MIDAS"),
  Params = c(length(coef(fit_arimax_is)),  length(coef(fit_nealmon_is)),
             length(coef(fit_nbeta_is)),   length(coef(fit_umidas_is))),
  AIC    = round(c(AIC(fit_arimax_is),  AIC(fit_nealmon_is),
                   AIC(fit_nbeta_is),   AIC(fit_umidas_is)),  2),
  BIC    = round(c(BIC(fit_arimax_is),  BIC(fit_nealmon_is),
                   BIC(fit_nbeta_is),   BIC(fit_umidas_is)),  2),
  RMSE   = round(c(sqrt(mean(resid(fit_arimax_is)^2)),
                   sqrt(mean(resid(fit_nealmon_is)^2)),
                   sqrt(mean(resid(fit_nbeta_is)^2)),
                   sqrt(mean(resid(fit_umidas_is)^2))), 5)
)

print(is_table, row.names = FALSE)
cat("\nBest AIC:", is_table$Model[which.min(is_table$AIC)], "\n")
cat("Best BIC:", is_table$Model[which.min(is_table$BIC)], "\n\n")

# ============================================================
# STEP 5 — Lag selection: compare k = 3, 7, 11 for nealmon
# ============================================================
# k = 3  → 4 weekly lags  = 1 month of WTI data
# k = 7  → 8 weekly lags  = 2 months of WTI data
# k = 11 → 12 weekly lags = 3 months of WTI data

cat("=== Lag selection (nealmon, full sample) ===\n")

lag_tbl <- do.call(rbind, lapply(c(3L, 7L, 11L), function(k) {
  fit <- tryCatch(
    midas_r(y_all ~ fmls(x_all, k, 4, nealmon),
            start = list(x_all = c(0, 0, 0))),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  data.frame(k = k, Weeks_covered = k + 1L, AIC = AIC(fit), BIC = BIC(fit))
}))

print(lag_tbl, row.names = FALSE, digits = 5)
best_k <- lag_tbl$k[which.min(lag_tbl$AIC)]
cat("Selected k =", best_k, "(", best_k + 1L, "weekly lags by AIC)\n\n")

# Re-fit in-sample models with the selected best_k
fit_nealmon_is <- midas_r(y_all ~ fmls(x_all, best_k, 4, nealmon),
                           start = list(x_all = c(0, 0, 0)))
fit_nbeta_is   <- midas_r(y_all ~ fmls(x_all, best_k, 4, nbeta),
                           start = list(x_all = c(1, 1, 5)))
fit_umidas_is  <- midas_u(y_all ~ fmls(x_all, best_k, 4))

# ============================================================
# STEP 6 — Rolling window evaluation (expanding, 2015-2022)
# ============================================================
cpi_dates <- as.Date(index(cpi_monthly))
test_idx  <- which(cpi_dates >= as.Date("2015-01-01"))
n_test    <- length(test_idx)

cat("=== Rolling window evaluation ===\n")
cat("Train: 2000-02 to 2014-12 (expanding)\n")
cat("Test:  2015-01 to 2022-12 |", n_test, "one-step-ahead forecasts\n\n")

fc_arimax  <- rep(NA_real_, n_test)
fc_nealmon <- rep(NA_real_, n_test)
fc_nbeta   <- rep(NA_real_, n_test)
fc_umidas  <- rep(NA_real_, n_test)

t0 <- proc.time()

for (i in seq_len(n_test)) {
  te_i  <- test_idx[i]       # forecast month (full-sample index)
  end_i <- te_i - 1L         # last training observation

  # Training vectors
  y_tr  <- y_all[1L : end_i]
  x_tr  <- x_all[1L : (end_i * 4L)]
  xm_tr <- x_monthly[1L : end_i]

  # High-freq WTI for forecast month (exactly 4 weekly obs)
  x_te4 <- x_all[((te_i - 1L) * 4L + 1L) : (te_i * 4L)]
  xm_te <- x_monthly[te_i]

  # ---- ARIMAX ------------------------------------------------
  fit_ar <- tryCatch(
    auto.arima(y_tr, xreg = matrix(xm_tr, ncol = 1), ic = "aic",
               stepwise = TRUE, approximation = TRUE),
    error = function(e) NULL
  )
  if (!is.null(fit_ar)) {
    fc_arimax[i] <- tryCatch(
      as.numeric(forecast(fit_ar, h = 1L,
                          xreg = matrix(xm_te, nrow = 1))$mean),
      error = function(e) NA_real_
    )
  }

  # ---- ADL-MIDAS nealmon -------------------------------------
  fit_ne <- tryCatch(
    midas_r(y_tr ~ fmls(x_tr, best_k, 4, nealmon),
            start = list(x_tr = c(0, 0, 0))),
    error = function(e) NULL
  )
  if (!is.null(fit_ne)) {
    fc_nealmon[i] <- tryCatch(
      as.numeric(forecast(fit_ne,
                          newdata = list(x_tr = x_te4),
                          h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  # ---- ADL-MIDAS nbeta ---------------------------------------
  fit_nb <- tryCatch(
    midas_r(y_tr ~ fmls(x_tr, best_k, 4, nbeta),
            start = list(x_tr = c(1, 1, 5))),
    error = function(e) NULL
  )
  if (!is.null(fit_nb)) {
    fc_nbeta[i] <- tryCatch(
      as.numeric(forecast(fit_nb,
                          newdata = list(x_tr = x_te4),
                          h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  # ---- U-MIDAS -----------------------------------------------
  fit_um <- tryCatch(
    midas_u(y_tr ~ fmls(x_tr, best_k, 4)),
    error = function(e) NULL
  )
  if (!is.null(fit_um)) {
    fc_umidas[i] <- tryCatch(
      as.numeric(forecast(fit_um,
                          newdata = list(x_tr = x_te4),
                          h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  arimax=%+.4f  nealmon=%+.4f\n",
                i, n_test, format(cpi_dates[te_i], "%Y-%m"),
                fc_arimax[i], fc_nealmon[i]))
}

elapsed <- round((proc.time() - t0)["elapsed"], 1)
cat("\nRolling window complete in", elapsed, "seconds.\n\n")

y_actual <- y_all[test_idx]

# ============================================================
# STEP 7 — Forecast accuracy (RMSE, MAE)
# ============================================================
rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae  <- function(e) mean(abs(e),   na.rm = TRUE)

e_arimax  <- y_actual - fc_arimax
e_nealmon <- y_actual - fc_nealmon
e_nbeta   <- y_actual - fc_nbeta
e_umidas  <- y_actual - fc_umidas

oos_results <- data.frame(
  Model        = c("ARIMAX", "ADL-MIDAS nealmon", "ADL-MIDAS nbeta", "U-MIDAS"),
  RMSE         = round(c(rmse(e_arimax), rmse(e_nealmon),
                         rmse(e_nbeta),  rmse(e_umidas)), 6),
  MAE          = round(c(mae(e_arimax),  mae(e_nealmon),
                         mae(e_nbeta),   mae(e_umidas)),  6),
  vs_ARIMAX_pct = round(c(0,
    100 * (rmse(e_nealmon) - rmse(e_arimax)) / rmse(e_arimax),
    100 * (rmse(e_nbeta)   - rmse(e_arimax)) / rmse(e_arimax),
    100 * (rmse(e_umidas)  - rmse(e_arimax)) / rmse(e_arimax)), 1),
  NAs          = c(sum(is.na(fc_arimax)), sum(is.na(fc_nealmon)),
                   sum(is.na(fc_nbeta)),  sum(is.na(fc_umidas)))
)

cat("=== Out-of-sample forecast accuracy (2015-2022) ===\n")
print(oos_results, row.names = FALSE)
cat("\nBest RMSE:", oos_results$Model[which.min(oos_results$RMSE)], "\n")
cat("Best MAE: ", oos_results$Model[which.min(oos_results$MAE)],  "\n\n")

# ============================================================
# STEP 8 — Diebold-Mariano tests (H1: MIDAS < ARIMAX loss)
# ============================================================
cat("=== Diebold-Mariano tests (H0: equal MSE | H1: MIDAS better) ===\n")

dm_safe <- function(e_midas, label) {
  # Keep only paired non-NA observations
  ok  <- !is.na(e_midas) & !is.na(e_arimax)
  res <- tryCatch(
    dm.test(e_midas[ok], e_arimax[ok],
            alternative = "less", h = 1L, power = 2),
    error = function(e) NULL
  )
  if (!is.null(res)) {
    sig <- ifelse(res$p.value < 0.05, "(*)", ifelse(res$p.value < 0.10, "(.)", ""))
    cat(sprintf("  %-22s DM = %6.3f  p = %.4f  %s\n",
                paste0(label, ":"), res$statistic, res$p.value, sig))
  } else {
    cat("  ", label, ": DM test failed\n")
  }
}

dm_safe(e_nealmon, "nealmon vs ARIMAX")
dm_safe(e_nbeta,   "nbeta   vs ARIMAX")
dm_safe(e_umidas,  "U-MIDAS vs ARIMAX")
cat("(*) p < 0.05  (.) p < 0.10\n\n")

# ============================================================
# STEP 9 — Plots
# ============================================================

render <- function(plot_fn, file, w, h) {
  dev.new()
  plot_fn()
  png(file, width = w, height = h, units = "in", res = 300)
  plot_fn()
  invisible(dev.off())
  cat("Saved:", file, "\n")
}

test_dates <- cpi_dates[test_idx]

# ---- 9a: Actual vs model forecasts (2015-2022) -------------
render(function() {
  ylim <- range(c(y_actual, fc_arimax, fc_nealmon, fc_nbeta, fc_umidas),
                na.rm = TRUE)
  par(mar = c(4, 4.5, 4, 1))
  plot(test_dates, y_actual,
       type = "l", lwd = 2.2, col = "black", ylim = ylim,
       main = "One-Step-Ahead Forecasts: US Consumer Energy CPI",
       sub  = "Monthly log-change | Train 2000-2014 (expanding) | Test 2015-2022",
       xlab = "", ylab = "Monthly log-change in CPI Energy")
  lines(test_dates, fc_arimax,  col = "tomato",      lwd = 1.5, lty = 2)
  lines(test_dates, fc_nealmon, col = "steelblue",   lwd = 1.5, lty = 1)
  lines(test_dates, fc_nbeta,   col = "forestgreen", lwd = 1.5, lty = 3)
  lines(test_dates, fc_umidas,  col = "purple",      lwd = 1.5, lty = 4)
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  legend("bottomleft", bty = "n", cex = 0.85,
         lwd = c(2.2, 1.5, 1.5, 1.5, 1.5),
         lty = c(1, 2, 1, 3, 4),
         col = c("black", "tomato", "steelblue", "forestgreen", "purple"),
         legend = c("Actual",
                    paste0("ARIMAX  (RMSE=", round(rmse(e_arimax),  4), ")"),
                    paste0("nealmon (RMSE=", round(rmse(e_nealmon), 4), ")"),
                    paste0("nbeta   (RMSE=", round(rmse(e_nbeta),   4), ")"),
                    paste0("U-MIDAS (RMSE=", round(rmse(e_umidas),  4), ")")))
}, "output/figures/06_energy_forecasts.png", 13, 5)

# ---- 9b: RMSE bar chart ------------------------------------
render(function() {
  cols <- c("tomato", "steelblue", "forestgreen", "purple")
  par(mar = c(4, 8, 4, 2))
  bp <- barplot(oos_results$RMSE,
                names.arg = oos_results$Model,
                horiz     = TRUE, las = 1,
                col       = cols,
                main      = "Out-of-Sample RMSE by Model (2015-2022)",
                xlab      = "Root Mean Squared Error",
                xlim      = c(0, max(oos_results$RMSE) * 1.2))
  # ARIMAX reference line
  abline(v = oos_results$RMSE[1], col = "tomato", lty = 2, lwd = 1.2)
  # Value labels
  text(oos_results$RMSE + max(oos_results$RMSE) * 0.01, bp,
       labels = sprintf("%.5f", oos_results$RMSE),
       adj = 0, cex = 0.8)
}, "output/figures/07_energy_rmse_bars.png", 10, 5)

# ---- 9c: Lag weight plots (nealmon + nbeta, in-sample) -----
render(function() {
  par(mfrow = c(1, 2), mar = c(5, 4, 5, 2))
  tryCatch(
    plot_midas_coef(fit_nealmon_is,
                    title = sprintf("nealmon lag weights (k=%d, m=4)", best_k)),
    error = function(e) plot.new()
  )
  mtext("Exponential Almon: monotone decay expected if week 4 > week 1",
        side = 3, line = 0.3, cex = 0.78, col = "grey30")
  tryCatch(
    plot_midas_coef(fit_nbeta_is,
                    title = sprintf("nbeta lag weights (k=%d, m=4)", best_k)),
    error = function(e) plot.new()
  )
  mtext("Normalized Beta: flexible hump-shaped decay",
        side = 3, line = 0.3, cex = 0.78, col = "grey30")
  par(mfrow = c(1, 1))
}, "output/figures/08_energy_lag_weights.png", 11, 5)

# ============================================================
# STEP 10 — Save result tables
# ============================================================
write.csv(oos_results, "output/tables/energy_rolling_window_results.csv",
          row.names = FALSE)
write.csv(is_table,    "output/tables/energy_insample_comparison.csv",
          row.names = FALSE)

# Save forecast vectors for Phase 5 CLM-SS DM tests
saveRDS(list(
  fc_arimax  = fc_arimax,
  fc_nealmon = fc_nealmon,
  fc_nbeta   = fc_nbeta,
  fc_umidas  = fc_umidas,
  y_actual   = y_actual,
  test_dates = cpi_dates[test_idx]
), "data/processed/phase4_forecasts.rds")

cat("\n=== Phase 4 complete ===\n")
cat("Figures saved:\n")
cat("  output/figures/06_energy_forecasts.png\n")
cat("  output/figures/07_energy_rmse_bars.png\n")
cat("  output/figures/08_energy_lag_weights.png\n")
cat("Tables saved:\n")
cat("  output/tables/energy_rolling_window_results.csv\n")
cat("  output/tables/energy_insample_comparison.csv\n")
