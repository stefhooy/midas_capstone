# ============================================================
# 11_extended_models.R — Phase 7: Extended Metrics + Feature Selection
#
# Phase 7d (this script): Directional accuracy, large-move hit rates,
#           precision/recall, Mincer-Zarnowitz unbiasedness test
#           for all 6 models (Phase 4 + CLM-SS).
#
# Prerequisite: run 09_benchmarks.R and 07_clm_ss.R first so that
#   data/processed/phase4_forecasts.rds and
#   data/processed/clmss_forecasts.rds exist.
# ============================================================

library(forecast)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables",  recursive = TRUE, showWarnings = FALSE)

# ============================================================
# STEP 1 — Load all forecast vectors
# ============================================================
ph4 <- tryCatch(
  readRDS("data/processed/phase4_forecasts.rds"),
  error = function(e) stop("Run 09_benchmarks.R first to generate phase4_forecasts.rds")
)
clm <- tryCatch(
  readRDS("data/processed/clmss_forecasts.rds"),
  error = function(e) stop("Run 07_clm_ss.R first to generate clmss_forecasts.rds")
)

y_actual   <- ph4$y_actual
test_dates <- ph4$test_dates
n_test     <- length(y_actual)

fc_list <- list(
  "ARIMAX"             = ph4$fc_arimax,
  "MIDAS nealmon"      = ph4$fc_nealmon,
  "MIDAS nbeta"        = ph4$fc_nbeta,
  "U-MIDAS"            = ph4$fc_umidas,
  "CLM-SS (4 lags)"    = clm$fc_clmss4,
  "CLM-SS (12 lags)"   = clm$fc_clmss12
)

cat("Loaded", length(fc_list), "model forecast vectors |",
    n_test, "test observations (2015-2022)\n\n")

# ============================================================
# STEP 2 — Helper functions
# ============================================================

# Basic accuracy measures
rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae  <- function(e) mean(abs(e),   na.rm = TRUE)

# Directional accuracy: % of months where sign(forecast) == sign(actual)
dir_acc <- function(fc) {
  ok <- !is.na(fc)
  round(mean(sign(y_actual[ok]) == sign(fc[ok])) * 100, 1)
}

# Large-move threshold: 1 SD of actual test-period CPI changes
sd_y     <- sd(y_actual)
up_idx   <- y_actual >  sd_y    # large positive months (energy price spike)
down_idx <- y_actual < -sd_y    # large negative months (energy price crash)

cat(sprintf("Large-move threshold: +/- %.4f (1 SD of test-period CPI changes)\n",
            sd_y))
cat(sprintf("Large up-moves:   %d months | Large down-moves: %d months\n\n",
            sum(up_idx), sum(down_idx)))

# Hit rate for large up-moves: among spike months, did forecast predict positive?
hit_up <- function(fc) {
  ok  <- !is.na(fc) & up_idx
  if (sum(ok) == 0) return(NA_real_)
  round(mean(fc[ok] > 0) * 100, 1)
}

# Hit rate for large down-moves: among crash months, did forecast predict negative?
hit_down <- function(fc) {
  ok  <- !is.na(fc) & down_idx
  if (sum(ok) == 0) return(NA_real_)
  round(mean(fc[ok] < 0) * 100, 1)
}

# Precision: of months the model flagged as large moves, how many actually were?
# A model "flags" a large move when |forecast| > 0.5 * sd_y
flag_thresh <- 0.5 * sd_y

precision_large <- function(fc) {
  ok       <- !is.na(fc)
  flagged  <- abs(fc[ok]) > flag_thresh
  actual_l <- (up_idx | down_idx)[ok]
  if (sum(flagged) == 0) return(NA_real_)
  round(sum(flagged & actual_l) / sum(flagged) * 100, 1)
}

# Recall: of actual large moves, how many did the model flag?
recall_large <- function(fc) {
  ok       <- !is.na(fc)
  flagged  <- abs(fc[ok]) > flag_thresh
  actual_l <- (up_idx | down_idx)[ok]
  if (sum(actual_l) == 0) return(NA_real_)
  round(sum(flagged & actual_l) / sum(actual_l) * 100, 1)
}

# Mincer-Zarnowitz unbiasedness test
# Regress actual on forecast: y = alpha + beta*f + e
# H0: alpha = 0 AND beta = 1 (unbiased, efficient forecast)
# Manual F-test with 2 restrictions
mz_test <- function(fc) {
  ok    <- !is.na(fc)
  n     <- sum(ok)
  lm_mz <- lm(y_actual[ok] ~ fc[ok])
  alpha <- coef(lm_mz)[1]
  beta  <- coef(lm_mz)[2]
  r2    <- summary(lm_mz)$r.squared

  rss_u <- sum(residuals(lm_mz)^2)
  e_r   <- y_actual[ok] - fc[ok]        # residuals under H0: y = f
  rss_r <- sum(e_r^2)
  f     <- ((rss_r - rss_u) / 2) / (rss_u / (n - 2))
  p     <- pf(f, 2, n - 2, lower.tail = FALSE)

  list(alpha = round(alpha, 5), beta = round(beta, 3),
       R2 = round(r2, 3), F = round(f, 2), p_MZ = round(p, 4))
}

# ============================================================
# STEP 3 — Compute all metrics for all models
# ============================================================
cat("=== Extended metrics (2015-2022 test period) ===\n\n")

rows <- lapply(names(fc_list), function(nm) {
  fc  <- fc_list[[nm]]
  e   <- y_actual - fc
  mz  <- mz_test(fc)

  data.frame(
    Model        = nm,
    RMSE         = round(rmse(e), 5),
    Dir_Acc_pct  = dir_acc(fc),
    Hit_Up_pct   = hit_up(fc),
    Hit_Down_pct = hit_down(fc),
    Precision_pct = precision_large(fc),
    Recall_pct   = recall_large(fc),
    MZ_alpha     = mz$alpha,
    MZ_beta      = mz$beta,
    MZ_R2        = mz$R2,
    MZ_p         = mz$p_MZ,
    stringsAsFactors = FALSE
  )
})

metrics_tbl <- do.call(rbind, rows)

cat("--- Forecast accuracy and directional metrics ---\n")
print(metrics_tbl[, c("Model", "RMSE", "Dir_Acc_pct",
                       "Hit_Up_pct", "Hit_Down_pct")],
      row.names = FALSE, digits = 4)

cat("\n--- Precision, recall and Mincer-Zarnowitz test ---\n")
cat("(Flag threshold = |forecast| > 0.5 SD of actual = ",
    round(flag_thresh, 4), ")\n")
print(metrics_tbl[, c("Model", "Precision_pct", "Recall_pct",
                       "MZ_alpha", "MZ_beta", "MZ_R2", "MZ_p")],
      row.names = FALSE)

cat("\nMincer-Zarnowitz interpretation:\n")
cat("  H0: alpha=0 and beta=1 (unbiased, efficient forecast)\n")
cat("  p_MZ < 0.05 means the forecast is significantly biased or inefficient\n\n")

# ============================================================
# STEP 4 — Summary narrative
# ============================================================
best_dir  <- metrics_tbl$Model[which.max(metrics_tbl$Dir_Acc_pct)]
best_rec  <- metrics_tbl$Model[which.max(metrics_tbl$Recall_pct)]
best_prec <- metrics_tbl$Model[which.max(metrics_tbl$Precision_pct)]

cat("=== Key findings ===\n")
cat(sprintf("  Best directional accuracy: %s (%.1f%%)\n",
            best_dir, max(metrics_tbl$Dir_Acc_pct)))
cat(sprintf("  Best large-move recall:    %s (%.1f%%)\n",
            best_rec, max(metrics_tbl$Recall_pct, na.rm = TRUE)))
cat(sprintf("  Best large-move precision: %s (%.1f%%)\n",
            best_prec, max(metrics_tbl$Precision_pct, na.rm = TRUE)))

unbiased <- metrics_tbl$Model[metrics_tbl$MZ_p >= 0.05]
biased   <- metrics_tbl$Model[metrics_tbl$MZ_p <  0.05]
if (length(unbiased) > 0)
  cat("  Unbiased (MZ p >= 0.05):   ", paste(unbiased, collapse = ", "), "\n")
if (length(biased) > 0)
  cat("  Biased   (MZ p <  0.05):   ", paste(biased, collapse = ", "), "\n")

# ============================================================
# STEP 5 — Plots
# ============================================================
render <- function(plot_fn, file, w, h) {
  dev.new(); plot_fn()
  png(file, width = w, height = h, units = "in", res = 300)
  plot_fn(); invisible(dev.off())
  cat("Saved:", file, "\n")
}

model_cols <- c("tomato", "steelblue", "forestgreen",
                "purple", "darkorchid", "darkorchid4")

# ---- 5a: Directional accuracy bar chart --------------------
render(function() {
  par(mar = c(4, 9, 4, 2))
  bp <- barplot(metrics_tbl$Dir_Acc_pct,
                names.arg = metrics_tbl$Model,
                horiz = TRUE, las = 1,
                col   = model_cols, border = "white",
                xlim  = c(0, 100),
                main  = "Directional Accuracy by Model (2015-2022)",
                xlab  = "% of months with correct sign prediction")
  abline(v = 50, col = "grey50", lty = 2, lwd = 1.2)
  text(metrics_tbl$Dir_Acc_pct + 1, bp,
       labels = paste0(metrics_tbl$Dir_Acc_pct, "%"),
       adj = 0, cex = 0.82)
}, "output/figures/14_directional_accuracy.png", 10, 5)

# ---- 5b: Precision and Recall grouped bar chart ------------
render(function() {
  prec <- metrics_tbl$Precision_pct
  rec  <- metrics_tbl$Recall_pct
  nm   <- metrics_tbl$Model
  n    <- length(nm)

  par(mar = c(5, 9, 4, 5))
  x <- barplot(rbind(prec, rec),
               beside     = TRUE,
               names.arg  = nm,
               horiz      = TRUE,
               las        = 1,
               col        = c("steelblue", "tomato"),
               border     = "white",
               xlim       = c(0, 115),
               main       = "Large-Move Precision and Recall (|actual| > 1 SD)",
               xlab       = "Percentage (%)")
  legend("topright", bty = "n", fill = c("steelblue", "tomato"),
         legend = c("Precision", "Recall"), cex = 0.85)
}, "output/figures/15_precision_recall.png", 11, 6)

# ---- 5c: Mincer-Zarnowitz beta coefficients ----------------
render(function() {
  par(mar = c(5, 9, 4, 2))
  bp <- barplot(metrics_tbl$MZ_beta,
                names.arg = metrics_tbl$Model,
                horiz = TRUE, las = 1,
                col   = ifelse(metrics_tbl$MZ_p < 0.05, "tomato", "steelblue"),
                border = "white",
                xlim  = c(0, max(metrics_tbl$MZ_beta, na.rm = TRUE) * 1.3),
                main  = "Mincer-Zarnowitz Beta Coefficient (ideal = 1.0)",
                xlab  = "Estimated beta  (H0: beta = 1)")
  abline(v = 1, col = "grey40", lty = 2, lwd = 1.5)
  text(metrics_tbl$MZ_beta + 0.02, bp,
       labels = sprintf("%.2f%s", metrics_tbl$MZ_beta,
                         ifelse(metrics_tbl$MZ_p < 0.05, "*", "")),
       adj = 0, cex = 0.82)
  legend("bottomright", bty = "n", cex = 0.8,
         fill = c("steelblue", "tomato"),
         legend = c("MZ unbiased (p >= 0.05)", "MZ biased (p < 0.05)"))
}, "output/figures/16_mz_beta.png", 10, 5)

# ============================================================
# STEP 6 — Save complete metrics table
# ============================================================
write.csv(metrics_tbl, "output/tables/extended_metrics_all_models.csv",
          row.names = FALSE)

cat("\n=== Phase 7d complete ===\n")
cat("Figures saved:\n")
cat("  output/figures/14_directional_accuracy.png\n")
cat("  output/figures/15_precision_recall.png\n")
cat("  output/figures/16_mz_beta.png\n")
cat("Table saved:\n")
cat("  output/tables/extended_metrics_all_models.csv\n")

# ============================================================
# PHASE 7a — LASSO-MIDAS
# ============================================================
# Apply L1 (LASSO) penalty to U-MIDAS 12-lag coefficients.
#
# U-MIDAS sets all 12 weekly WTI lag coefficients free (OLS, no penalty).
# LASSO-MIDAS adds an L1 penalty that shrinks some coefficients to exactly
# zero, producing a sparse lag structure. The key question: do the surviving
# non-zero lags match the hump at prior-month weeks 2-3 already identified
# by MIDAS (parametric), CLM-SS (MLE), and XGBoost (tree-based)?
#
# If yes, four completely independent methods agree on the same lag
# structure — strong evidence that the 5-7 week WTI-to-CPI transmission
# lag is real and not an artefact of any one method.
# ============================================================

library(glmnet)

cat("\n============================================================\n")
cat("PHASE 7a — LASSO-MIDAS\n")
cat("============================================================\n\n")

# ---- Build 12-lag WTI matrix (no AR lags — matches U-MIDAS) ----
lasso_feat_names <- c(paste0("wti_m0_w", 1:4),
                      paste0("wti_m1_w", 1:4),
                      paste0("wti_m2_w", 1:4))

# X_wti12: reuse the same build functions from Phase 7d setup
build_midas_x_lasso <- function(wti_series, cpi_index) {
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

build_ext_x_lasso <- function(X_mat, n_months_back = 2L) {
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

X_wti4_l  <- build_midas_x_lasso(wti_wk, index(cpi_monthly))
X_lasso   <- build_ext_x_lasso(X_wti4_l, n_months_back = 2L)
colnames(X_lasso) <- lasso_feat_names

# ---- Lambda selection: tune on 2000-2012, validate on 2013-2014 ----
cat("=== LASSO lambda selection ===\n")

tune_mask <- cpi_dates <= as.Date("2012-12-31")
val_mask  <- cpi_dates >  as.Date("2012-12-31") & cpi_dates <= as.Date("2014-12-31")

ok_tune <- which(tune_mask & complete.cases(X_lasso))
ok_val  <- which(val_mask  & complete.cases(X_lasso))

X_tune_l <- X_lasso[ok_tune, ]; y_tune_l <- y_all[ok_tune]
X_val_l  <- X_lasso[ok_val,  ]; y_val_l  <- y_all[ok_val]

# Fit LASSO path on training data
path_fit <- glmnet(X_tune_l, y_tune_l, alpha = 1, standardize = TRUE)

# Evaluate on validation set for each lambda
val_preds_l  <- predict(path_fit, newx = X_val_l)
val_rmse_l   <- apply(val_preds_l, 2, function(p)
  sqrt(mean((y_val_l - p)^2, na.rm = TRUE)))

best_lambda_lasso <- path_fit$lambda[which.min(val_rmse_l)]
n_nonzero         <- path_fit$df[which.min(val_rmse_l)]

cat(sprintf("Best lambda: %.6f | Non-zero lags: %d / 12 | Val RMSE: %.5f\n\n",
            best_lambda_lasso, n_nonzero, min(val_rmse_l)))

# ---- In-sample coefficients at best lambda (full 2000-2022 sample) ----
ok_all     <- which(complete.cases(X_lasso))
fit_lasso_is <- glmnet(X_lasso[ok_all, ], y_all[ok_all],
                       alpha = 1, lambda = best_lambda_lasso,
                       standardize = TRUE)

lasso_coefs  <- as.numeric(coef(fit_lasso_is))[-1]   # drop intercept
names(lasso_coefs) <- lasso_feat_names

cat("=== LASSO coefficients at best lambda (full sample) ===\n")
for (j in seq_along(lasso_coefs)) {
  zero_flag <- if (abs(lasso_coefs[j]) < 1e-8) " [zeroed out]" else ""
  cat(sprintf("  %-12s  %+.5f%s\n",
              lasso_feat_names[j], lasso_coefs[j], zero_flag))
}
cat(sprintf("\nSurviving lags: %s\n",
            paste(lasso_feat_names[abs(lasso_coefs) > 1e-8], collapse = ", ")))

# ---- Rolling window OOS evaluation (2015-2022) ----
cat("\n=== LASSO-MIDAS rolling window (expanding, 2015-2022) ===\n")

test_dates_l <- which(cpi_dates >= as.Date("2015-01-01"))
n_test_l     <- length(test_dates_l)
fc_lasso_rw  <- rep(NA_real_, n_test_l)

t0_l <- proc.time()

for (i in seq_len(n_test_l)) {
  te_i  <- test_dates_l[i]
  end_i <- te_i - 1L

  ok_tr <- which(seq_len(end_i) %in% ok_all)
  if (length(ok_tr) < 15L) next
  if (any(is.na(X_lasso[te_i, ]))) next

  X_tr_l <- X_lasso[ok_tr, ]; y_tr_l <- y_all[ok_tr]
  X_te_l <- matrix(X_lasso[te_i, ], nrow = 1L)

  fit_l         <- glmnet(X_tr_l, y_tr_l, alpha = 1,
                           lambda = best_lambda_lasso, standardize = TRUE)
  fc_lasso_rw[i] <- as.numeric(predict(fit_l, newx = X_te_l,
                                        s = best_lambda_lasso))
}

elapsed_l <- round((proc.time() - t0_l)["elapsed"], 1)
cat("LASSO-MIDAS rolling window complete in", elapsed_l, "seconds.\n\n")

# ---- Accuracy metrics ----
y_actual_l  <- y_all[test_dates_l]
e_lasso     <- y_actual_l - fc_lasso_rw

rmse_l   <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae_l    <- function(e) mean(abs(e),   na.rm = TRUE)
dir_acc_l <- function(fc, actual) {
  ok <- !is.na(fc)
  round(mean(sign(actual[ok]) == sign(fc[ok])) * 100, 1)
}

cat("=== LASSO-MIDAS OOS accuracy (2015-2022) ===\n")
cat(sprintf("  RMSE:            %.5f\n", rmse_l(e_lasso)))
cat(sprintf("  MAE:             %.5f\n", mae_l(e_lasso)))
cat(sprintf("  Directional acc: %.1f%%\n", dir_acc_l(fc_lasso_rw, y_actual_l)))
cat(sprintf("  Non-zero lags:   %d / 12\n", n_nonzero))
cat(sprintf("  Lambda:          %.6f\n\n", best_lambda_lasso))

# Compare to Phase 4 benchmarks
if (!is.null(ph4)) {
  arimax_rmse_l <- rmse_l(ph4$y_actual - ph4$fc_arimax)
  nbeta_rmse_l  <- rmse_l(ph4$y_actual - ph4$fc_nbeta)
  umidas_rmse_l <- rmse_l(ph4$y_actual - ph4$fc_umidas)

  cat("=== LASSO-MIDAS vs benchmarks ===\n")
  cat(sprintf("  ARIMAX       RMSE: %.5f  (baseline)\n",    arimax_rmse_l))
  cat(sprintf("  U-MIDAS      RMSE: %.5f  (OLS, no penalty)\n", umidas_rmse_l))
  cat(sprintf("  LASSO-MIDAS  RMSE: %.5f  (%+.1f%% vs ARIMAX)\n",
              rmse_l(e_lasso),
              100 * (rmse_l(e_lasso) - arimax_rmse_l) / arimax_rmse_l))
  cat(sprintf("  nbeta        RMSE: %.5f  (best MIDAS model)\n\n", nbeta_rmse_l))
}

# ---- Plots ----

# 7a-i: LASSO coefficient bar chart
render(function() {
  cols <- ifelse(grepl("wti_m1", lasso_feat_names), "tomato",
           ifelse(grepl("wti_m2", lasso_feat_names), "darkorange", "steelblue"))
  # Mark zeroed coefficients with lighter shade
  cols[abs(lasso_coefs) < 1e-8] <- "grey85"

  par(mar = c(5, 7, 4, 2))
  bp <- barplot(lasso_coefs,
                names.arg = lasso_feat_names,
                horiz = FALSE, las = 2,
                col = cols, border = "white",
                main = "LASSO-MIDAS Coefficients at Best Lambda",
                sub  = sprintf("lambda=%.5f | %d / 12 lags survive | Grey = zeroed out",
                               best_lambda_lasso, n_nonzero),
                ylab = "Coefficient value")
  abline(h = 0, col = "grey40", lty = 2)
  legend("topright", bty = "n", cex = 0.82,
         fill = c("steelblue", "tomato", "darkorange", "grey85"),
         legend = c("Current month (m0)", "Prior month (m1)",
                    "2 months ago (m2)", "Zeroed by LASSO"))
}, "output/figures/19_lasso_coefficients.png", 10, 5)

# 7a-ii: LASSO path (coefficients vs log lambda)
render(function() {
  par(mar = c(5, 4, 4, 2))
  plot(path_fit, xvar = "lambda", label = TRUE,
       main = "LASSO-MIDAS Regularisation Path",
       sub  = "Each line = one weekly WTI lag; vertical dashed = selected lambda")
  abline(v = log(best_lambda_lasso), col = "firebrick", lty = 2, lwd = 1.5)
}, "output/figures/20_lasso_path.png", 10, 5)

# ---- Save ----
saveRDS(list(
  fc_lasso      = fc_lasso_rw,
  y_actual      = y_actual_l,
  test_dates    = cpi_dates[test_dates_l],
  lambda        = best_lambda_lasso,
  coefs         = lasso_coefs,
  n_nonzero     = n_nonzero
), "data/processed/lasso_forecasts.rds")

write.csv(
  data.frame(Feature = lasso_feat_names, Coefficient = lasso_coefs,
             Nonzero = abs(lasso_coefs) > 1e-8),
  "output/tables/lasso_midas_coefficients.csv", row.names = FALSE
)

cat("=== Phase 7a complete ===\n")
cat(sprintf("  LASSO-MIDAS RMSE: %.5f | Dir. Acc.: %.1f%%\n",
            rmse_l(e_lasso), dir_acc_l(fc_lasso_rw, y_actual_l)))
cat(sprintf("  Non-zero lags: %d / 12 | Lambda: %.6f\n",
            n_nonzero, best_lambda_lasso))
cat("Figures: 19_lasso_coefficients.png | 20_lasso_path.png\n")
cat("Tables:  lasso_midas_coefficients.csv\n")
cat("Data:    data/processed/lasso_forecasts.rds\n\n")
cat("Key question: do the surviving lags match the lag 5-6 hump\n")
cat("already identified by MIDAS, CLM-SS, and XGBoost?\n")
