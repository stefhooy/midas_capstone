# ============================================================
# 10_ml_benchmarks.R — Phase 6: ML Benchmark Comparison
#
# 6c — XGBoost              (implemented — run now)
# 6a — Kernel U-MIDAS       (to add)
# 6b — LSTM                 (to add)
# 6d — Interpretability table (to add after 6a/6b)
#
# Prerequisite: 09_benchmarks.R must have been run so that
#   data/processed/phase4_forecasts.rds exists.
# ============================================================

library(xgboost)
library(forecast)
library(xts)
library(zoo)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables",  recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# ============================================================
# STEP 1 — Load processed energy data
# ============================================================
cpi_monthly <- readRDS("data/processed/cpi_energy_log_diff_monthly.rds")
wti_wk      <- readRDS("data/processed/wti_log_diff_weekly.rds")

y_all    <- as.numeric(cpi_monthly)
n_months <- length(y_all)
cpi_dates <- as.Date(index(cpi_monthly))

cat("Loaded: CPI Energy", n_months, "monthly obs |",
    format(start(cpi_monthly), "%Y-%m"), "to",
    format(end(cpi_monthly),   "%Y-%m"), "\n\n")

# ============================================================
# STEP 2 — Build feature matrix (14 features)
# ============================================================
# Features:
#   wti_m0_w1..w4  = 4 weekly WTI log-diffs from current month
#   wti_m1_w1..w4  = 4 weekly WTI log-diffs from 1 month prior
#   wti_m2_w1..w4  = 4 weekly WTI log-diffs from 2 months prior
#   cpi_lag1       = previous month CPI log-diff (AR feature)
#   cpi_lag2       = two months prior CPI log-diff
#
# This matches the CLM-SS extended lag structure exactly,
# so XGBoost and CLM-SS see identical information sets.

build_midas_x <- function(wti_series, cpi_index) {
  months    <- as.yearmon(cpi_index)
  wti_dates <- as.Date(index(wti_series))
  wti_vals  <- as.numeric(wti_series)
  n         <- length(months)
  x_mat     <- matrix(NA_real_, nrow = n, ncol = 4L)
  for (i in seq_len(n)) {
    m_start  <- as.Date(months[i])
    m_end    <- as.Date(months[i] + 1/12) - 1L
    in_month <- which(wti_dates >= m_start & wti_dates <= m_end)
    if (length(in_month) >= 4L) {
      sel <- tail(in_month, 4L)
    } else {
      before <- which(wti_dates < m_start)
      sel    <- c(tail(before, 4L - length(in_month)), in_month)
    }
    x_mat[i, ] <- wti_vals[sel]
  }
  x_mat
}

build_ext_x <- function(X_mat, n_months_back = 2L) {
  n     <- nrow(X_mat)
  n_col <- 4L * (n_months_back + 1L)
  X_ext <- matrix(NA_real_, nrow = n, ncol = n_col)
  for (i in seq_len(n)) {
    if (i > n_months_back) {
      lag_rows   <- seq(i, i - n_months_back)
      X_ext[i, ] <- as.numeric(t(X_mat[lag_rows, ]))
    }
  }
  X_ext
}

X_wti4  <- build_midas_x(wti_wk, index(cpi_monthly))
X_wti12 <- build_ext_x(X_wti4, n_months_back = 2L)

y_lag1 <- c(NA_real_, y_all[-n_months])
y_lag2 <- c(rep(NA_real_, 2L), y_all[seq_len(n_months - 2L)])

feat_names <- c(paste0("wti_m0_w", 1:4),
                paste0("wti_m1_w", 1:4),
                paste0("wti_m2_w", 1:4),
                "cpi_lag1", "cpi_lag2")

X_full <- cbind(X_wti12, y_lag1, y_lag2)
colnames(X_full) <- feat_names

valid_rows <- which(complete.cases(X_full))
cat("Feature matrix:", ncol(X_full), "features |",
    length(valid_rows), "complete rows\n\n")

# ============================================================
# STEP 3 — Hyperparameter tuning
# ============================================================
# Tune on: 2000-02 to 2012-12 (training)
# Validate on: 2013-01 to 2014-12 (held-out validation)
# No test data (2015-2022) is touched during tuning.
# Grid: max_depth x eta x nrounds (27 combinations, fast)

cat("=== XGBoost hyperparameter tuning (grid search) ===\n")

tune_rows <- intersect(valid_rows, which(cpi_dates <= as.Date("2012-12-31")))
val_rows  <- intersect(valid_rows, which(cpi_dates > as.Date("2012-12-31") &
                                           cpi_dates <= as.Date("2014-12-31")))

X_tune <- X_full[tune_rows, ]; y_tune <- y_all[tune_rows]
X_val  <- X_full[val_rows,  ]; y_val  <- y_all[val_rows]

dtune <- xgb.DMatrix(data = X_tune, label = y_tune)
dval  <- xgb.DMatrix(data = X_val,  label = y_val)

param_grid <- expand.grid(
  max_depth = c(3L, 4L, 5L),
  eta       = c(0.05, 0.1, 0.2),
  nrounds   = c(100L, 200L, 300L)
)

best_val_rmse <- Inf
best_params   <- NULL

for (j in seq_len(nrow(param_grid))) {
  params_j <- list(
    objective        = "reg:squarederror",
    max_depth        = param_grid$max_depth[j],
    eta              = param_grid$eta[j],
    subsample        = 0.8,
    colsample_bytree = 0.8,
    min_child_weight = 2L,
    verbosity        = 0L
  )
  fit_j  <- xgb.train(params = params_j, data = dtune,
                       nrounds = param_grid$nrounds[j], verbose = 0)
  rmse_j <- sqrt(mean((y_val - predict(fit_j, dval))^2))

  if (rmse_j < best_val_rmse) {
    best_val_rmse <- rmse_j
    best_params   <- list(
      max_depth = param_grid$max_depth[j],
      eta       = param_grid$eta[j],
      nrounds   = param_grid$nrounds[j]
    )
  }
}

cat(sprintf("Best: max_depth=%d | eta=%.2f | nrounds=%d | val RMSE=%.5f\n\n",
            best_params$max_depth, best_params$eta,
            best_params$nrounds, best_val_rmse))

xgb_params <- list(
  objective        = "reg:squarederror",
  max_depth        = best_params$max_depth,
  eta              = best_params$eta,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 2L,
  verbosity        = 0L
)

# ============================================================
# STEP 4 — Rolling window OOS evaluation (2015-2022)
# ============================================================
cat("=== XGBoost rolling window (expanding, 2015-2022) ===\n")

test_idx <- which(cpi_dates >= as.Date("2015-01-01"))
n_test   <- length(test_idx)
fc_xgb   <- rep(NA_real_, n_test)

t0 <- proc.time()

for (i in seq_len(n_test)) {
  te_i  <- test_idx[i]
  end_i <- te_i - 1L

  tr_rows <- intersect(valid_rows, seq_len(end_i))
  if (length(tr_rows) < 20L || any(is.na(X_full[te_i, ]))) next

  dtr <- xgb.DMatrix(data  = X_full[tr_rows, ],
                     label = y_all[tr_rows])
  dte <- xgb.DMatrix(data  = matrix(X_full[te_i, ], nrow = 1L))

  fit_i      <- xgb.train(params = xgb_params, data = dtr,
                           nrounds = best_params$nrounds, verbose = 0)
  fc_xgb[i]  <- predict(fit_i, dte)

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  xgb=%+.4f\n",
                i, n_test, format(cpi_dates[te_i], "%Y-%m"), fc_xgb[i]))
}

elapsed <- round((proc.time() - t0)["elapsed"], 1)
cat("\nXGBoost rolling window complete in", elapsed, "seconds.\n\n")

# ============================================================
# STEP 5 — Accuracy metrics
# ============================================================
y_actual <- y_all[test_idx]
e_xgb    <- y_actual - fc_xgb

rmse     <- function(e)  sqrt(mean(e^2, na.rm = TRUE))
mae      <- function(e)  mean(abs(e),   na.rm = TRUE)
dir_acc  <- function(fc, actual) {
  ok <- !is.na(fc)
  round(mean(sign(actual[ok]) == sign(fc[ok])) * 100, 1)
}

cat("=== XGBoost OOS accuracy (2015-2022) ===\n")
cat(sprintf("  RMSE:            %.5f\n", rmse(e_xgb)))
cat(sprintf("  MAE:             %.5f\n", mae(e_xgb)))
cat(sprintf("  Directional acc: %.1f%%\n", dir_acc(fc_xgb, y_actual)))
cat(sprintf("  NAs:             %d / %d\n\n", sum(is.na(fc_xgb)), n_test))

# Compare to Phase 4 benchmarks
ph4 <- tryCatch(
  readRDS("data/processed/phase4_forecasts.rds"),
  error = function(e) { message("Run 09_benchmarks.R first"); NULL }
)

if (!is.null(ph4)) {
  arimax_rmse <- rmse(ph4$y_actual - ph4$fc_arimax)
  nbeta_rmse  <- rmse(ph4$y_actual - ph4$fc_nbeta)
  xgb_vs_arimax <- round(100 * (rmse(e_xgb) - arimax_rmse) / arimax_rmse, 1)

  cat("=== Comparison to Phase 4 benchmarks ===\n")
  cat(sprintf("  ARIMAX  RMSE: %.5f  (baseline)\n", arimax_rmse))
  cat(sprintf("  XGBoost RMSE: %.5f  (%+.1f%% vs ARIMAX)\n",
              rmse(e_xgb), xgb_vs_arimax))
  cat(sprintf("  nbeta   RMSE: %.5f  (best Phase 4 model)\n\n", nbeta_rmse))
}

# ============================================================
# STEP 6 — Feature importance (fit on full sample)
# ============================================================
cat("=== XGBoost feature importance (full sample 2000-2022) ===\n")

all_valid <- intersect(valid_rows, seq_len(n_months))
d_all     <- xgb.DMatrix(data  = X_full[all_valid, ],
                          label = y_all[all_valid])
fit_full  <- xgb.train(params = xgb_params, data = d_all,
                        nrounds = best_params$nrounds, verbose = 0)
importance <- xgb.importance(feature_names = colnames(X_full), model = fit_full)

cat("Top features by Gain:\n")
print(head(importance[, c("Feature", "Gain", "Cover")], 14),
      row.names = FALSE, digits = 3)

cat("\nKey comparison:\n")
cat("  If wti_m1_w2 / wti_m1_w3 rank highly, XGBoost confirms the MIDAS\n")
cat("  lag hump (peak at prior-month weeks 2-3 = lag 5-6 in MIDAS notation)\n\n")

# ============================================================
# STEP 7 — Plots
# ============================================================
render <- function(plot_fn, file, w, h) {
  dev.new(); plot_fn()
  png(file, width = w, height = h, units = "in", res = 300)
  plot_fn(); invisible(dev.off())
  cat("Saved:", file, "\n")
}

test_dates <- cpi_dates[test_idx]

# ---- Feature importance bar chart --------------------------
render(function() {
  top_n  <- min(14L, nrow(importance))
  top    <- importance[seq_len(top_n), ]
  gains  <- rev(top$Gain)
  labels <- rev(top$Feature)
  # Colour previous-month lags differently to highlight hump comparison
  cols <- ifelse(grepl("wti_m1", labels), "tomato",
           ifelse(grepl("wti_m2", labels), "darkorange",
           ifelse(grepl("wti_m0", labels), "steelblue", "grey60")))
  par(mar = c(4, 8, 4, 2))
  bp <- barplot(gains, names.arg = labels, horiz = TRUE, las = 1,
                col = cols, border = "white",
                main = "XGBoost Feature Importance (Gain), Full Sample 2000-2022",
                xlab = "Gain (contribution to squared error reduction)")
  legend("bottomright", bty = "n", cex = 0.8,
         fill = c("steelblue", "tomato", "darkorange", "grey60"),
         legend = c("Current month (m0)", "Prior month (m1)",
                    "2 months ago (m2)", "CPI lags"))
}, "output/figures/17_xgb_feature_importance.png", 11, 6)

# ---- XGBoost forecast vs actual ----------------------------
render(function() {
  ylim <- range(c(y_actual, fc_xgb), na.rm = TRUE)
  par(mar = c(4, 4.5, 4, 1))
  plot(test_dates, y_actual, type = "l", lwd = 2, col = "black",
       ylim = ylim,
       main = "XGBoost One-Step-Ahead Forecasts vs Actual (2015-2022)",
       sub  = sprintf("RMSE = %.5f | Dir. Acc. = %.1f%% | max_depth=%d, eta=%.2f, nrounds=%d",
                      rmse(e_xgb), dir_acc(fc_xgb, y_actual),
                      best_params$max_depth, best_params$eta, best_params$nrounds),
       xlab = "", ylab = "Monthly log-change in CPI Energy")
  lines(test_dates, fc_xgb, col = "darkorange", lwd = 1.6)
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  legend("bottomleft", bty = "n", cex = 0.85, lwd = c(2, 1.6),
         col = c("black", "darkorange"),
         legend = c("Actual",
                    paste0("XGBoost (RMSE=", round(rmse(e_xgb), 4), ")")))
}, "output/figures/18_xgb_forecasts.png", 12, 5)

# ============================================================
# STEP 8 — Save results
# ============================================================
saveRDS(list(
  fc_xgb      = fc_xgb,
  y_actual    = y_actual,
  test_dates  = test_dates,
  best_params = best_params
), "data/processed/xgb_forecasts.rds")

write.csv(importance, "output/tables/xgb_feature_importance.csv",
          row.names = FALSE)

cat("\n=== Phase 6c complete ===\n")
cat(sprintf("  XGBoost RMSE: %.5f | Dir. Acc.: %.1f%%\n",
            rmse(e_xgb), dir_acc(fc_xgb, y_actual)))
cat(sprintf("  Best params:  max_depth=%d | eta=%.2f | nrounds=%d\n",
            best_params$max_depth, best_params$eta, best_params$nrounds))
cat("Figures: 17_xgb_feature_importance.png | 18_xgb_forecasts.png\n")
cat("Tables:  xgb_feature_importance.csv\n")
cat("Data:    data/processed/xgb_forecasts.rds\n")

# ============================================================
# PHASE 6a — Kernel U-MIDAS   [TO ADD]
# PHASE 6b — LSTM              [TO ADD]
# PHASE 6d — Interpretability  [TO ADD AFTER 6a/6b]
# ============================================================
