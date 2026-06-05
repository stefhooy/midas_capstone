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
library(torch)

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
  if (interactive()) {
    dev.new()
    plot_fn()
  }
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
# PHASE 6a - Kernel U-MIDAS
# ============================================================
# Non-parametric MIDAS benchmark inspired by Breitung and Roling
# (2015): estimate 12 unrestricted weekly lag coefficients, but
# penalise roughness in the lag curve.
#
# Objective:
#   min_beta sum_t (y_t - alpha - X_t beta)^2
#            + lambda * ||D2 beta||^2
#
# D2 is the second-difference matrix, so the penalty encourages a
# smooth lag-weight curve without forcing a nealmon or nbeta shape.
# This answers DJL's "kernel/non-parametric MIDAS" request while
# keeping the implementation reproducible in base R.
# ============================================================

cat("\n============================================================\n")
cat("PHASE 6a - Kernel U-MIDAS\n")
cat("============================================================\n\n")

cat("Kernel U-MIDAS here means a smooth non-parametric lag curve:\n")
cat("  U-MIDAS coefficients are free, but a second-difference penalty\n")
cat("  discourages jagged week-to-week weights.\n\n")

kernel_feat_names <- feat_names[1:12]
X_kernel <- X_full[, kernel_feat_names]
D2_kernel <- diff(diag(ncol(X_kernel)), differences = 2)

fit_kernel_umidas <- function(X, y, lambda) {
  ok <- complete.cases(X) & !is.na(y)
  X  <- as.matrix(X[ok, , drop = FALSE])
  y  <- y[ok]

  Z <- cbind(Intercept = 1, X)
  P <- matrix(0, nrow = ncol(Z), ncol = ncol(Z))
  P[-1, -1] <- t(D2_kernel) %*% D2_kernel

  coef_hat <- solve(t(Z) %*% Z + lambda * P, t(Z) %*% y)
  list(coef = as.numeric(coef_hat), lambda = lambda)
}

predict_kernel_umidas <- function(fit, X_new) {
  X_new <- as.matrix(X_new)
  Z_new <- cbind(Intercept = 1, X_new)
  as.numeric(Z_new %*% fit$coef)
}

cat("=== Kernel U-MIDAS lambda selection ===\n")

ok_kernel <- which(complete.cases(X_kernel))
tune_rows_k <- intersect(ok_kernel, which(cpi_dates <= as.Date("2012-12-31")))
val_rows_k  <- intersect(ok_kernel, which(cpi_dates > as.Date("2012-12-31") &
                                            cpi_dates <= as.Date("2014-12-31")))

lambda_grid_k <- c(0, 10^seq(-6, 3, length.out = 25))

lambda_tbl_k <- do.call(rbind, lapply(lambda_grid_k, function(lam) {
  fit_k <- fit_kernel_umidas(X_kernel[tune_rows_k, ], y_all[tune_rows_k],
                             lambda = lam)
  pred_k <- predict_kernel_umidas(fit_k, X_kernel[val_rows_k, ])
  data.frame(
    lambda = lam,
    Val_RMSE = rmse(y_all[val_rows_k] - pred_k),
    Roughness = sum((D2_kernel %*% fit_k$coef[-1])^2),
    stringsAsFactors = FALSE
  )
}))

best_lambda_k <- lambda_tbl_k$lambda[which.min(lambda_tbl_k$Val_RMSE)]

cat(sprintf("Best lambda: %.8f | Val RMSE: %.5f | Roughness: %.5f\n\n",
            best_lambda_k,
            min(lambda_tbl_k$Val_RMSE),
            lambda_tbl_k$Roughness[which.min(lambda_tbl_k$Val_RMSE)]))

write.csv(transform(lambda_tbl_k,
                    Val_RMSE = round(Val_RMSE, 6),
                    Roughness = round(Roughness, 6)),
          "output/tables/kernel_umidas_lambda_grid.csv",
          row.names = FALSE)

fit_kernel_full <- fit_kernel_umidas(X_kernel[ok_kernel, ], y_all[ok_kernel],
                                     lambda = best_lambda_k)
kernel_coefs <- fit_kernel_full$coef[-1]
names(kernel_coefs) <- kernel_feat_names

cat("=== Kernel U-MIDAS full-sample lag weights ===\n")
for (j in seq_along(kernel_coefs)) {
  cat(sprintf("  %-12s  %+.5f\n", kernel_feat_names[j], kernel_coefs[j]))
}
cat("\n")

write.csv(
  data.frame(Feature = kernel_feat_names,
             Lag_Index = seq_along(kernel_feat_names),
             Coefficient = as.numeric(kernel_coefs),
             stringsAsFactors = FALSE),
  "output/tables/kernel_umidas_weights.csv", row.names = FALSE
)

cat("=== Kernel U-MIDAS rolling window (expanding, 2015-2022) ===\n")

test_idx_k  <- which(cpi_dates >= as.Date("2015-01-01"))
n_test_k    <- length(test_idx_k)
fc_kernel   <- rep(NA_real_, n_test_k)

t0_k <- proc.time()

for (i in seq_len(n_test_k)) {
  te_i <- test_idx_k[i]

  tr_rows <- intersect(ok_kernel, seq_len(te_i - 1L))
  if (length(tr_rows) < 36L || any(is.na(X_kernel[te_i, ]))) next

  fit_i <- fit_kernel_umidas(X_kernel[tr_rows, ], y_all[tr_rows],
                             lambda = best_lambda_k)
  fc_kernel[i] <- predict_kernel_umidas(
    fit_i,
    matrix(X_kernel[te_i, ], nrow = 1L,
           dimnames = list(NULL, colnames(X_kernel)))
  )

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  kernel=%+.4f\n",
                i, n_test_k, format(cpi_dates[te_i], "%Y-%m"),
                fc_kernel[i]))
}

elapsed_k <- round((proc.time() - t0_k)["elapsed"], 1)
cat("\nKernel U-MIDAS rolling window complete in", elapsed_k, "seconds.\n\n")

y_actual_k <- y_all[test_idx_k]
e_kernel   <- y_actual_k - fc_kernel

arimax_rmse_k  <- rmse(ph4$y_actual - ph4$fc_arimax)
nealmon_rmse_k <- rmse(ph4$y_actual - ph4$fc_nealmon)
nbeta_rmse_k   <- rmse(ph4$y_actual - ph4$fc_nbeta)
umidas_rmse_k  <- rmse(ph4$y_actual - ph4$fc_umidas)
xgb_rmse_k     <- rmse(e_xgb)
kernel_rmse_k  <- rmse(e_kernel)

kernel_results <- data.frame(
  Model = c("ARIMAX", "Kernel U-MIDAS", "U-MIDAS",
            "MIDAS nealmon", "MIDAS nbeta", "XGBoost"),
  RMSE = round(c(arimax_rmse_k, kernel_rmse_k, umidas_rmse_k,
                 nealmon_rmse_k, nbeta_rmse_k, xgb_rmse_k), 6),
  MAE = round(c(mae(ph4$y_actual - ph4$fc_arimax),
                mae(e_kernel),
                mae(ph4$y_actual - ph4$fc_umidas),
                mae(ph4$y_actual - ph4$fc_nealmon),
                mae(ph4$y_actual - ph4$fc_nbeta),
                mae(e_xgb)), 6),
  Dir_Acc_pct = c(dir_acc(ph4$fc_arimax, ph4$y_actual),
                  dir_acc(fc_kernel, y_actual_k),
                  dir_acc(ph4$fc_umidas, ph4$y_actual),
                  dir_acc(ph4$fc_nealmon, ph4$y_actual),
                  dir_acc(ph4$fc_nbeta, ph4$y_actual),
                  dir_acc(fc_xgb, y_actual)),
  vs_ARIMAX_pct = round(c(0,
                          100 * (kernel_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (umidas_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (nealmon_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (nbeta_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (xgb_rmse_k - arimax_rmse_k) / arimax_rmse_k),
                        1),
  Complexity = c("Monthly average", "12 lags + smoothness penalty",
                 "12 free lags", "3 lag-shape params",
                 "3 lag-shape params", "Tree ensemble"),
  Interpretable = c("Low", "High", "Partial", "High", "High", "Medium"),
  stringsAsFactors = FALSE
)

cat("=== Kernel U-MIDAS vs benchmarks ===\n")
print(kernel_results, row.names = FALSE)

write.csv(kernel_results, "output/tables/kernel_umidas_results.csv",
          row.names = FALSE)

saveRDS(list(
  fc_kernel       = fc_kernel,
  y_actual        = y_actual_k,
  test_dates      = cpi_dates[test_idx_k],
  lambda          = best_lambda_k,
  coefs           = kernel_coefs,
  lambda_grid     = lambda_tbl_k
), "data/processed/kernel_umidas_forecasts.rds")

render(function() {
  cols <- ifelse(grepl("wti_m1", kernel_feat_names), "tomato",
           ifelse(grepl("wti_m2", kernel_feat_names), "darkorange",
                  "steelblue"))
  par(mar = c(6, 4.5, 4, 1))
  plot(seq_along(kernel_coefs), kernel_coefs,
       type = "b", pch = 16, lwd = 2,
       col = "grey30", xaxt = "n",
       main = "Kernel U-MIDAS Lag Weights",
       sub = sprintf("Validation selected lambda = %.6f, so the smoother collapses to U-MIDAS",
                     best_lambda_k),
       xlab = "", ylab = "Coefficient value")
  axis(1, at = seq_along(kernel_feat_names),
       labels = gsub("wti_", "", kernel_feat_names),
       las = 2, cex.axis = 0.8)
  points(seq_along(kernel_coefs), kernel_coefs,
         pch = 19, cex = 1.25, col = cols)
  abline(h = 0, col = "grey45", lty = 2)
  legend("topright", bty = "n", cex = 0.82,
         col = c("steelblue", "tomato", "darkorange"),
         pch = 19,
         legend = c("Current month (m0)", "Prior month (m1)",
                    "2 months ago (m2)"))
}, "output/figures/29_kernel_umidas_weights.png", 10, 5)

render(function() {
  lambda_plot <- lambda_tbl_k[lambda_tbl_k$lambda > 0, ]
  par(mar = c(5, 4.5, 4, 1))
  plot(log10(lambda_plot$lambda), lambda_plot$Val_RMSE,
       type = "b", pch = 16, col = "steelblue", lwd = 2,
       main = "Kernel U-MIDAS Lambda Selection",
       sub = "Validation window: 2013-2014; lower RMSE is better",
       xlab = "log10(lambda)",
       ylab = "Validation RMSE")
  if (best_lambda_k > 0)
    abline(v = log10(best_lambda_k), col = "firebrick", lty = 2, lwd = 1.5)
  legend("topright", bty = "n", cex = 0.82,
         col = c("steelblue", "firebrick"),
         lty = c(1, 2), pch = c(16, NA),
         legend = c("Validation RMSE", "Selected lambda"))
}, "output/figures/30_kernel_lambda_selection.png", 9, 5)

render(function() {
  ylim <- range(c(y_actual_k, fc_kernel, ph4$fc_nbeta, ph4$fc_arimax),
                na.rm = TRUE)
  par(mar = c(4, 4.5, 4, 1))
  plot(cpi_dates[test_idx_k], y_actual_k, type = "l",
       col = "black", lwd = 2.1, ylim = ylim,
       main = "Kernel U-MIDAS Forecasts vs MIDAS and ARIMAX",
       sub = sprintf("Kernel RMSE = %.5f | nbeta RMSE = %.5f | ARIMAX RMSE = %.5f",
                     kernel_rmse_k, nbeta_rmse_k, arimax_rmse_k),
       xlab = "", ylab = "Monthly log-change in CPI Energy")
  lines(cpi_dates[test_idx_k], ph4$fc_arimax,
        col = "tomato", lwd = 1.3, lty = 2)
  lines(cpi_dates[test_idx_k], fc_kernel,
        col = "darkorange", lwd = 1.5, lty = 1)
  lines(cpi_dates[test_idx_k], ph4$fc_nbeta,
        col = "forestgreen", lwd = 1.5, lty = 3)
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  legend("bottomleft", bty = "n", cex = 0.82,
         lwd = c(2.1, 1.3, 1.5, 1.5),
         lty = c(1, 2, 1, 3),
         col = c("black", "tomato", "darkorange", "forestgreen"),
         legend = c("Actual",
                    paste0("ARIMAX (RMSE=", round(arimax_rmse_k, 4), ")"),
                    paste0("Kernel U-MIDAS (RMSE=", round(kernel_rmse_k, 4), ")"),
                    paste0("MIDAS nbeta (RMSE=", round(nbeta_rmse_k, 4), ")")))
}, "output/figures/31_kernel_umidas_forecasts.png", 12, 5)

cat("\n=== Phase 6a complete ===\n")
cat(sprintf("  Kernel U-MIDAS RMSE: %.5f (%+.1f%% vs ARIMAX)\n",
            kernel_rmse_k,
            100 * (kernel_rmse_k - arimax_rmse_k) / arimax_rmse_k))
cat(sprintf("  Selected lambda: %.8f | Dir. Acc.: %.1f%%\n",
            best_lambda_k, dir_acc(fc_kernel, y_actual_k)))
cat("Figures: 29_kernel_umidas_weights.png | 30_kernel_lambda_selection.png | 31_kernel_umidas_forecasts.png\n")
cat("Tables:  kernel_umidas_lambda_grid.csv | kernel_umidas_weights.csv | kernel_umidas_results.csv\n")
cat("Data:    data/processed/kernel_umidas_forecasts.rds\n")

# ============================================================
# PHASE 6b - LSTM benchmark
# ============================================================
# Recurrent neural network benchmark requested by DJL.
# Input sequence: 12 weekly WTI log-diff observations.
# Output: one-month-ahead CPI Energy log-diff.
#
# Important methodological choice:
# The LSTM uses only the same 12 weekly WTI lags as the MIDAS models.
# It does not receive extra macro variables. This makes the comparison
# fair: the question is whether a recurrent neural net can learn the
# lag-transmission pattern better than MIDAS from the same information.
# ============================================================

cat("\n============================================================\n")
cat("PHASE 6b - LSTM\n")
cat("============================================================\n\n")

cat("LSTM benchmark: 12 weekly WTI lags -> monthly CPI Energy change.\n")
cat("Small network, full-batch training, fixed hyperparameters selected\n")
cat("on 2013-2014 validation data to avoid test leakage.\n\n")

torch_manual_seed(42)

lstm_regressor <- nn_module(
  "lstm_regressor",
  initialize = function(hidden_size = 8L) {
    self$lstm <- nn_lstm(input_size = 1L, hidden_size = hidden_size,
                         batch_first = TRUE)
    self$fc <- nn_linear(hidden_size, 1L)
  },
  forward = function(x) {
    lstm_out <- self$lstm(x)[[1]]
    last_out <- lstm_out[, lstm_out$size(2), ]
    self$fc(last_out)
  }
)

fit_lstm_model <- function(X, y, hidden_size = 8L, epochs = 150L,
                           lr = 0.01, seed = 42L, verbose = FALSE) {
  ok <- complete.cases(X) & !is.na(y)
  X <- as.matrix(X[ok, , drop = FALSE])
  y <- y[ok]

  x_center <- colMeans(X)
  x_scale  <- apply(X, 2, sd)
  x_scale[x_scale == 0] <- 1
  Xs <- scale(X, center = x_center, scale = x_scale)

  y_center <- mean(y)
  y_scale  <- sd(y)
  if (is.na(y_scale) || y_scale == 0) y_scale <- 1
  ys <- (y - y_center) / y_scale

  x_tensor <- torch_tensor(array(as.numeric(Xs),
                                 dim = c(nrow(Xs), ncol(Xs), 1L)),
                           dtype = torch_float())
  y_tensor <- torch_tensor(matrix(ys, ncol = 1L), dtype = torch_float())

  torch_manual_seed(seed)
  model <- lstm_regressor(hidden_size = hidden_size)
  optimizer <- optim_adam(model$parameters, lr = lr)

  model$train()
  loss_last <- NA_real_
  for (ep in seq_len(epochs)) {
    optimizer$zero_grad()
    pred <- model(x_tensor)
    loss <- nnf_mse_loss(pred, y_tensor)
    loss$backward()
    optimizer$step()
    loss_last <- as.numeric(loss$item())
    if (verbose && ep %% 50L == 0L)
      cat(sprintf("    epoch %d/%d loss=%.5f\n", ep, epochs, loss_last))
  }

  list(model = model,
       x_center = x_center,
       x_scale = x_scale,
       y_center = y_center,
       y_scale = y_scale,
       hidden_size = hidden_size,
       epochs = epochs,
       lr = lr,
       loss = loss_last)
}

predict_lstm_model <- function(fit, X_new) {
  X_new <- as.matrix(X_new)
  Xs <- scale(X_new, center = fit$x_center, scale = fit$x_scale)
  x_tensor <- torch_tensor(array(as.numeric(Xs),
                                 dim = c(nrow(Xs), ncol(Xs), 1L)),
                           dtype = torch_float())
  fit$model$eval()
  with_no_grad({
    pred_s <- as.numeric(fit$model(x_tensor))
  })
  pred_s * fit$y_scale + fit$y_center
}

X_lstm <- X_kernel
ok_lstm <- which(complete.cases(X_lstm))

tune_rows_lstm <- intersect(ok_lstm, which(cpi_dates <= as.Date("2012-12-31")))
val_rows_lstm  <- intersect(ok_lstm, which(cpi_dates > as.Date("2012-12-31") &
                                             cpi_dates <= as.Date("2014-12-31")))

cat("=== LSTM hyperparameter selection ===\n")

lstm_grid <- expand.grid(
  hidden_size = c(4L, 8L),
  epochs = c(100L, 150L),
  lr = c(0.005, 0.01)
)

lstm_tune_tbl <- do.call(rbind, lapply(seq_len(nrow(lstm_grid)), function(j) {
  cfg <- lstm_grid[j, ]
  fit_j <- fit_lstm_model(X_lstm[tune_rows_lstm, ], y_all[tune_rows_lstm],
                          hidden_size = cfg$hidden_size,
                          epochs = cfg$epochs,
                          lr = cfg$lr,
                          seed = 42L)
  pred_j <- predict_lstm_model(fit_j, X_lstm[val_rows_lstm, ])
  data.frame(
    hidden_size = cfg$hidden_size,
    epochs = cfg$epochs,
    lr = cfg$lr,
    Val_RMSE = rmse(y_all[val_rows_lstm] - pred_j),
    Train_Loss = fit_j$loss,
    stringsAsFactors = FALSE
  )
}))

best_lstm <- lstm_tune_tbl[which.min(lstm_tune_tbl$Val_RMSE), ]

cat(sprintf("Best: hidden=%d | epochs=%d | lr=%.3f | val RMSE=%.5f\n\n",
            best_lstm$hidden_size, best_lstm$epochs, best_lstm$lr,
            best_lstm$Val_RMSE))

write.csv(transform(lstm_tune_tbl,
                    Val_RMSE = round(Val_RMSE, 6),
                    Train_Loss = round(Train_Loss, 6)),
          "output/tables/lstm_tuning_grid.csv", row.names = FALSE)

cat("=== LSTM rolling window (expanding, 2015-2022) ===\n")

test_idx_lstm <- which(cpi_dates >= as.Date("2015-01-01"))
n_test_lstm   <- length(test_idx_lstm)
fc_lstm       <- rep(NA_real_, n_test_lstm)

t0_lstm <- proc.time()

for (i in seq_len(n_test_lstm)) {
  te_i <- test_idx_lstm[i]
  tr_rows <- intersect(ok_lstm, seq_len(te_i - 1L))
  if (length(tr_rows) < 36L || any(is.na(X_lstm[te_i, ]))) next

  fit_i <- fit_lstm_model(
    X_lstm[tr_rows, ], y_all[tr_rows],
    hidden_size = best_lstm$hidden_size,
    epochs = best_lstm$epochs,
    lr = best_lstm$lr,
    seed = 42L + i
  )

  fc_lstm[i] <- predict_lstm_model(
    fit_i,
    matrix(X_lstm[te_i, ], nrow = 1L,
           dimnames = list(NULL, colnames(X_lstm)))
  )

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  lstm=%+.4f\n",
                i, n_test_lstm, format(cpi_dates[te_i], "%Y-%m"),
                fc_lstm[i]))
}

elapsed_lstm <- round((proc.time() - t0_lstm)["elapsed"], 1)
cat("\nLSTM rolling window complete in", elapsed_lstm, "seconds.\n\n")

y_actual_lstm <- y_all[test_idx_lstm]
e_lstm <- y_actual_lstm - fc_lstm
lstm_rmse <- rmse(e_lstm)

lstm_results <- data.frame(
  Model = c("ARIMAX", "MIDAS nbeta", "MIDAS nealmon",
            "U-MIDAS", "Kernel U-MIDAS", "XGBoost", "LSTM"),
  RMSE = round(c(arimax_rmse_k, nbeta_rmse_k, nealmon_rmse_k,
                 umidas_rmse_k, kernel_rmse_k, xgb_rmse_k, lstm_rmse), 6),
  MAE = round(c(mae(ph4$y_actual - ph4$fc_arimax),
                mae(ph4$y_actual - ph4$fc_nbeta),
                mae(ph4$y_actual - ph4$fc_nealmon),
                mae(ph4$y_actual - ph4$fc_umidas),
                mae(e_kernel),
                mae(e_xgb),
                mae(e_lstm)), 6),
  Dir_Acc_pct = c(dir_acc(ph4$fc_arimax, ph4$y_actual),
                  dir_acc(ph4$fc_nbeta, ph4$y_actual),
                  dir_acc(ph4$fc_nealmon, ph4$y_actual),
                  dir_acc(ph4$fc_umidas, ph4$y_actual),
                  dir_acc(fc_kernel, y_actual_k),
                  dir_acc(fc_xgb, y_actual),
                  dir_acc(fc_lstm, y_actual_lstm)),
  vs_ARIMAX_pct = round(c(0,
                          100 * (nbeta_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (nealmon_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (umidas_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (kernel_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (xgb_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (lstm_rmse - arimax_rmse_k) / arimax_rmse_k),
                        1),
  Complexity = c("Monthly average", "3 lag-shape params",
                 "3 lag-shape params", "12 free lags",
                 "12 lags + smoothness penalty", "Tree ensemble",
                 paste0("LSTM hidden=", best_lstm$hidden_size)),
  Interpretable = c("Low", "High", "High", "Partial",
                    "High", "Medium", "Low"),
  stringsAsFactors = FALSE
)

cat("=== LSTM vs benchmark models ===\n")
print(lstm_results, row.names = FALSE)

write.csv(lstm_results, "output/tables/lstm_results.csv",
          row.names = FALSE)

saveRDS(list(
  fc_lstm = fc_lstm,
  y_actual = y_actual_lstm,
  test_dates = cpi_dates[test_idx_lstm],
  best_params = list(hidden_size = best_lstm$hidden_size,
                     epochs = best_lstm$epochs,
                     lr = best_lstm$lr),
  tuning_grid = lstm_tune_tbl
), "data/processed/lstm_forecasts.rds")

render(function() {
  ylim <- range(c(y_actual_lstm, fc_lstm, ph4$fc_nbeta, ph4$fc_arimax),
                na.rm = TRUE)
  par(mar = c(4, 4.5, 4, 1))
  plot(cpi_dates[test_idx_lstm], y_actual_lstm, type = "l",
       col = "black", lwd = 2.1, ylim = ylim,
       main = "LSTM Forecasts vs MIDAS and ARIMAX",
       sub = sprintf("LSTM RMSE = %.5f | nbeta RMSE = %.5f | ARIMAX RMSE = %.5f",
                     lstm_rmse, nbeta_rmse_k, arimax_rmse_k),
       xlab = "", ylab = "Monthly log-change in CPI Energy")
  lines(cpi_dates[test_idx_lstm], ph4$fc_arimax,
        col = "tomato", lwd = 1.3, lty = 2)
  lines(cpi_dates[test_idx_lstm], fc_lstm,
        col = "darkorchid4", lwd = 1.5, lty = 1)
  lines(cpi_dates[test_idx_lstm], ph4$fc_nbeta,
        col = "forestgreen", lwd = 1.5, lty = 3)
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  legend("bottomleft", bty = "n", cex = 0.82,
         lwd = c(2.1, 1.3, 1.5, 1.5),
         lty = c(1, 2, 1, 3),
         col = c("black", "tomato", "darkorchid4", "forestgreen"),
         legend = c("Actual",
                    paste0("ARIMAX (RMSE=", round(arimax_rmse_k, 4), ")"),
                    paste0("LSTM (RMSE=", round(lstm_rmse, 4), ")"),
                    paste0("MIDAS nbeta (RMSE=", round(nbeta_rmse_k, 4), ")")))
}, "output/figures/32_lstm_forecasts.png", 12, 5)

render(function() {
  plot_tbl <- lstm_results[order(lstm_results$RMSE, decreasing = TRUE), ]
  cols <- ifelse(plot_tbl$Model == "LSTM", "darkorchid4",
           ifelse(grepl("MIDAS", plot_tbl$Model), "steelblue",
           ifelse(plot_tbl$Model == "ARIMAX", "tomato", "grey65")))
  par(mar = c(4, 8, 4, 1))
  bp <- barplot(plot_tbl$RMSE, names.arg = plot_tbl$Model,
                horiz = TRUE, las = 1,
                col = cols, border = "white",
                main = "LSTM vs Mixed-Frequency Benchmarks",
                sub = "Lower RMSE is better; all models evaluated on 2015-2022 rolling window",
                xlab = "RMSE")
  text(plot_tbl$RMSE + 0.0006, bp,
       labels = sprintf("%.5f", plot_tbl$RMSE),
       cex = 0.75, adj = 0)
}, "output/figures/33_lstm_rmse_comparison.png", 10, 5)

cat("\n=== Phase 6b complete ===\n")
cat(sprintf("  LSTM RMSE: %.5f (%+.1f%% vs ARIMAX)\n",
            lstm_rmse, 100 * (lstm_rmse - arimax_rmse_k) / arimax_rmse_k))
cat(sprintf("  Best params: hidden=%d | epochs=%d | lr=%.3f | Dir. Acc.: %.1f%%\n",
            best_lstm$hidden_size, best_lstm$epochs, best_lstm$lr,
            dir_acc(fc_lstm, y_actual_lstm)))
cat("Figures: 32_lstm_forecasts.png | 33_lstm_rmse_comparison.png\n")
cat("Tables:  lstm_tuning_grid.csv | lstm_results.csv\n")
cat("Data:    data/processed/lstm_forecasts.rds\n")

# ============================================================
# PHASE 6d - Performance vs interpretability table
# ============================================================

# This table combines Phase 4/5/6/7 results into one defense-facing
# comparison. LASSO-MIDAS and CLM-SS values come from 11_extended_models.R
# and 07_clm_ss.R respectively; all other values are available in this script.
phase6d_tbl <- data.frame(
  Model = c("ARIMAX",
            "MIDAS nbeta",
            "MIDAS nealmon",
            "U-MIDAS",
            "CLM-SS (12 lags)",
            "LASSO-MIDAS",
            "Kernel U-MIDAS",
            "XGBoost",
            "LSTM"),
  Family = c("Monthly benchmark",
             "Parametric MIDAS",
             "Parametric MIDAS",
             "Unrestricted MIDAS",
             "State-space MIDAS-style",
             "Regularised MIDAS",
             "Non-parametric MIDAS",
             "Machine learning",
             "Machine learning"),
  RMSE = round(c(arimax_rmse_k,
                 nbeta_rmse_k,
                 nealmon_rmse_k,
                 umidas_rmse_k,
                 0.022579,
                 0.021030,
                 kernel_rmse_k,
                 xgb_rmse_k,
                 lstm_rmse), 5),
  vs_ARIMAX_pct = round(c(0,
                          100 * (nbeta_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (nealmon_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (umidas_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          -24.4,
                          -29.6,
                          100 * (kernel_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (xgb_rmse_k - arimax_rmse_k) / arimax_rmse_k,
                          100 * (lstm_rmse - arimax_rmse_k) / arimax_rmse_k),
                        1),
  Dir_Acc_pct = c(64.6, 74.0, 80.2, 75.0, 74.0, 76.0,
                  dir_acc(fc_kernel, y_actual_k),
                  dir_acc(fc_xgb, y_actual),
                  dir_acc(fc_lstm, y_actual_lstm)),
  Parameters_or_complexity = c("ARMA + monthly mean WTI",
                               "3 lag-shape parameters",
                               "3 lag-shape parameters",
                               "12 free weekly coefficients",
                               "12 link weights + AR(1) state",
                               "11 nonzero weekly coefficients",
                               "12 lags + smoothness penalty",
                               "Tree ensemble over 14 features",
                               paste0("LSTM hidden=", best_lstm$hidden_size,
                                      ", epochs=", best_lstm$epochs)),
  Weekly_timing_use = c("Aggregates WTI to monthly mean",
                        "Smooth beta lag curve over 12 weekly lags",
                        "Smooth Almon lag curve over 12 weekly lags",
                        "Free coefficient for each weekly lag",
                        "Exact weekly link weights plus AR error",
                        "Sparse weekly lag selection",
                        "Smooth non-parametric weekly lag curve",
                        "Tabular weekly lag features",
                        "Sequential 12-week WTI input"),
  Training_burden = c("Low", "Low", "Low", "Low",
                      "Medium", "Medium", "Low-medium",
                      "Medium", "High"),
  Interpretability = c("Medium",
                       "High",
                       "High",
                       "Medium",
                       "High",
                       "Medium-high",
                       "High",
                       "Medium-low",
                       "Low"),
  Capstone_role = c("Baseline to beat",
                    "Best RMSE model",
                    "Best directional model",
                    "Flexible MIDAS benchmark",
                    "Novel exact aggregation framework",
                    "Feature-selection robustness",
                    "Non-parametric smoother robustness",
                    "Tree-based ML benchmark",
                    "Deep-learning benchmark"),
  Thesis_takeaway = c("Monthly pre-aggregation loses weekly timing.",
                      "Best overall accuracy; strongest main result.",
                      "Best sign accuracy and easiest defense model.",
                      "Weekly timing matters even without shape restrictions.",
                      "Confirms lag hump but does not beat parametric MIDAS.",
                      "Independently selects the prior-month lag window.",
                      "Validation chooses no extra smoothing; U-MIDAS is enough.",
                      "Beats ARIMAX but trails MIDAS; confirms lag hump.",
                      "Beats ARIMAX but complexity is not rewarded."),
  stringsAsFactors = FALSE
)

phase6d_tbl <- phase6d_tbl[order(phase6d_tbl$RMSE), ]
phase6d_tbl$RMSE_rank <- seq_len(nrow(phase6d_tbl))
phase6d_tbl <- phase6d_tbl[, c("RMSE_rank",
                               setdiff(names(phase6d_tbl), "RMSE_rank"))]

write.csv(phase6d_tbl,
          "output/tables/performance_interpretability_table.csv",
          row.names = FALSE)

fmt_vs <- function(x) ifelse(x == 0, "baseline", sprintf("%+.1f%%", x))

md_lines <- c(
  "# Phase 6d Performance vs Interpretability Table",
  "",
  "| Rank | Model | RMSE | vs ARIMAX | Dir. Acc. | Complexity | Interpretability | Capstone role |",
  "| ---: | --- | ---: | ---: | ---: | --- | --- | --- |"
)

for (i in seq_len(nrow(phase6d_tbl))) {
  md_lines <- c(md_lines, sprintf(
    "| %d | %s | %.5f | %s | %.1f%% | %s | %s | %s |",
    phase6d_tbl$RMSE_rank[i],
    phase6d_tbl$Model[i],
    phase6d_tbl$RMSE[i],
    fmt_vs(phase6d_tbl$vs_ARIMAX_pct[i]),
    phase6d_tbl$Dir_Acc_pct[i],
    phase6d_tbl$Parameters_or_complexity[i],
    phase6d_tbl$Interpretability[i],
    phase6d_tbl$Capstone_role[i]
  ))
}

md_lines <- c(
  md_lines,
  "",
  "Main interpretation:",
  "",
  "- MIDAS nbeta is the best RMSE model.",
  "- MIDAS nealmon is the best directional model and the clearest defense model.",
  "- Every serious weekly-timing model beats ARIMAX except the lag-limited CLM-SS(4), which is excluded from this final comparison.",
  "- XGBoost and LSTM both beat ARIMAX, but neither beats parametric MIDAS.",
  "- The capstone result is therefore not just about prediction accuracy; it is about accuracy plus an interpretable 5-7 week WTI-to-CPI transmission window."
)

writeLines(md_lines,
           "output/tables/performance_interpretability_table.md")

summary_lines <- c(
  "Phase 6d - Performance vs Interpretability Takeaways",
  "",
  "Best RMSE: MIDAS nbeta, RMSE 0.02057 (-31.1% vs ARIMAX).",
  "Best directional accuracy: MIDAS nealmon, 80.2%.",
  "Best accuracy/interpretable trade-off: parametric MIDAS, especially nbeta and nealmon.",
  "",
  "Machine-learning conclusion:",
  "XGBoost and LSTM both beat the monthly ARIMAX baseline, so weekly WTI timing contains real signal.",
  "However, neither ML model beats MIDAS. XGBoost reaches RMSE 0.02365 and LSTM reaches RMSE 0.02588, while MIDAS nbeta reaches 0.02057.",
  "This is defense-useful because it shows that modern ML was tested, but the small monthly sample rewards parsimonious lag-shape models.",
  "",
  "MIDAS conclusion:",
  "MIDAS is not only accurate; it explains where the predictive information sits.",
  "Across MIDAS, CLM-SS, LASSO-MIDAS, XGBoost, and Kernel U-MIDAS, the useful signal repeatedly appears in prior-month WTI weeks 2-3, implying a 5-7 week oil-to-consumer-energy-price transmission window.",
  "",
  "Final thesis sentence:",
  "The best model is not the most complex model; it is the model that preserves weekly timing while imposing enough structure to remain stable and interpretable in a small monthly macro-energy sample."
)

writeLines(summary_lines,
           "output/tables/phase6d_interpretability_summary.txt")

cat("\n=== Phase 6d complete ===\n")
cat("Best RMSE model:", phase6d_tbl$Model[1],
    "| RMSE =", sprintf("%.5f", phase6d_tbl$RMSE[1]), "\n")
cat("Tables: performance_interpretability_table.csv | performance_interpretability_table.md\n")
cat("Summary: phase6d_interpretability_summary.txt\n")
