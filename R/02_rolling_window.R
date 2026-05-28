# ============================================================
# 02_rolling_window.R — Phase 2c: Out-of-Sample Evaluation
# Expanding window: train 1949–(t-1), forecast year t
# Test period: 2000–2011 (12 one-step-ahead forecasts)
# Models: ARIMAX vs ADL-MIDAS (nealmon) vs U-MIDAS
# ============================================================

library(midasr)
library(forecast)

# Set working directory to midas_capstone project root
setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")

set.seed(42)

data("USrealgdp")
data("USunempr")

y        <- diff(log(USrealgdp))
x        <- window(diff(USunempr), start = 1949)
x_annual <- window(aggregate(x, FUN = mean), start = 1949, end = 2011)

test_years <- 2000:2011
n_test     <- length(test_years)

fc_arimax  <- numeric(n_test)
fc_nealmon <- numeric(n_test)
fc_umidas  <- numeric(n_test)
act        <- numeric(n_test)

cat("Running expanding-window forecasts (2000-2011)...\n")

for (i in seq_len(n_test)) {

  yr     <- test_years[i]
  act[i] <- as.numeric(window(y, start = yr, end = yr))

  # Training data up to year before the forecast year
  y_tr  <- window(y,        end = yr - 1)
  x_tr  <- window(x,        end = c(yr - 1, 12))
  xa_tr <- as.numeric(window(x_annual, end = yr - 1))

  # Regressors for the forecast year
  x_te  <- as.numeric(window(x, start = c(yr, 1), end = c(yr, 12)))
  xa_te <- as.numeric(window(x_annual, start = yr, end = yr))

  trend_tr <- seq_along(y_tr)
  trend_te <- length(y_tr) + 1L

  # --- ARIMAX -----------------------------------------------
  fit_a <- tryCatch(
    auto.arima(y_tr, xreg = matrix(xa_tr, ncol = 1), ic = "aic",
               stepwise = TRUE, approximation = TRUE),
    error = function(e) NULL
  )
  fc_arimax[i] <- if (!is.null(fit_a)) {
    as.numeric(forecast(fit_a, xreg = matrix(xa_te, nrow = 1), h = 1)$mean)
  } else NA

  # --- ADL-MIDAS nealmon ------------------------------------
  fit_m <- tryCatch(
    midas_r(y_tr ~ trend_tr + fmls(x_tr, 11, 12, nealmon),
            start = list(x_tr = c(0, 0, 0))),
    error = function(e) NULL
  )
  fc_nealmon[i] <- if (!is.null(fit_m)) {
    tryCatch(
      as.numeric(forecast(fit_m,
                          newdata = list(x_tr = x_te, trend_tr = trend_te),
                          h = 1)$mean),
      error = function(e) NA
    )
  } else NA

  # --- U-MIDAS ----------------------------------------------
  fit_u <- tryCatch(
    midas_u(y_tr ~ fmls(x_tr, 11, 12) + trend_tr),
    error = function(e) NULL
  )
  fc_umidas[i] <- if (!is.null(fit_u)) {
    tryCatch(
      as.numeric(forecast(fit_u,
                          newdata = list(x_tr = x_te, trend_tr = trend_te),
                          h = 1)$mean),
      error = function(e) NA
    )
  } else NA

  cat(sprintf("  %d: actual=%+.4f  ARIMAX=%+.4f  nealmon=%+.4f  U-MIDAS=%+.4f\n",
              yr, act[i], fc_arimax[i], fc_nealmon[i], fc_umidas[i]))
}

# ---- Metrics -----------------------------------------------
rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae  <- function(e) mean(abs(e),  na.rm = TRUE)

err_arimax  <- act - fc_arimax
err_nealmon <- act - fc_nealmon
err_umidas  <- act - fc_umidas

results <- data.frame(
  Model = c("ARIMAX", "ADL-MIDAS (nealmon)", "U-MIDAS"),
  RMSE  = c(rmse(err_arimax), rmse(err_nealmon), rmse(err_umidas)),
  MAE   = c(mae(err_arimax),  mae(err_nealmon),  mae(err_umidas))
)

cat("\n=== Out-of-sample forecast accuracy (2000-2011) ===\n")
print(results, digits = 5, row.names = FALSE)

# ---- Diebold-Mariano test ----------------------------------
# H0: equal accuracy  |  H1 (less): nealmon has smaller loss than ARIMAX
dm_result <- dm.test(err_nealmon, err_arimax, alternative = "less", h = 1, power = 2)
cat("\nDiebold-Mariano test (nealmon vs ARIMAX, H1: MIDAS is better):\n")
print(dm_result)
cat("Interpretation:",
    ifelse(dm_result$p.value < 0.10,
           "MIDAS significantly outperforms ARIMAX (p < 0.10)",
           "No significant difference at 10% level"), "\n")

# ---- Plot --------------------------------------------------
par(mar = c(4, 4, 3, 1))
plot(test_years, act,
     type = "b", lwd = 2, pch = 16,
     ylim = range(c(act, fc_arimax, fc_nealmon, fc_umidas), na.rm = TRUE),
     main = "1-Step-Ahead Forecasts vs Actual GDP Growth (2000-2011)",
     xlab = "Year", ylab = "Annual GDP Growth Rate")
lines(test_years, fc_arimax,  col = "steelblue", lty = 2, lwd = 1.5)
lines(test_years, fc_nealmon, col = "firebrick",  lty = 2, lwd = 1.5)
lines(test_years, fc_umidas,  col = "darkgreen",  lty = 2, lwd = 1.5)
abline(h = 0, col = "grey60", lty = 3)
legend("topright",
       legend = c("Actual", "ARIMAX", "ADL-MIDAS (nealmon)", "U-MIDAS"),
       col    = c("black", "steelblue", "firebrick", "darkgreen"),
       lty    = c(1, 2, 2, 2), lwd = c(2, 1.5, 1.5, 1.5),
       pch    = c(16, NA, NA, NA), bty = "n")

# ---- Save --------------------------------------------------
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
write.csv(results, "output/tables/rolling_window_results.csv", row.names = FALSE)
cat("\nSaved: output/tables/rolling_window_results.csv\n")
