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
