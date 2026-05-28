# ============================================================
# 06_evaluation.R — Rolling Window Forecast Evaluation
# Compares ARIMAX, ADL-MIDAS (nealmon), U-MIDAS
# Metrics: RMSE, MAE + Diebold-Mariano test
# ============================================================

library(midasr)
library(forecast)

data("USrealgdp")
data("USunempr")

y <- diff(log(USrealgdp))
x <- window(diff(USunempr), start = 1949)
x_annual <- window(aggregate(x, FUN = mean), start = 1949, end = 2011)

# ---- Settings ----------------------------------------------
train_end   <- 1999    # last year in expanding training window
eval_start  <- 2000    # first year we forecast
eval_end    <- 2011    # last year in test set
n_eval      <- eval_end - eval_start + 1   # 12 forecasts

# ---- Storage -----------------------------------------------
fc_arimax   <- numeric(n_eval)
fc_nealmon  <- numeric(n_eval)
fc_umidas   <- numeric(n_eval)
actuals     <- numeric(n_eval)

# ---- Rolling window loop -----------------------------------
for (i in seq_len(n_eval)) {
  yr <- eval_start + i - 1

  # Training windows
  y_tr  <- window(y,        end = yr - 1)
  x_tr  <- window(x,        end = c(yr - 1, 12))
  xa_tr <- window(x_annual, end = yr - 1)

  # Test regressors (the year being forecast)
  xa_te <- window(x_annual, start = yr, end = yr)
  x_te  <- window(x,        start = c(yr, 1), end = c(yr, 12))

  actuals[i] <- window(y, start = yr, end = yr)

  # ARIMAX
  fit_a <- tryCatch(
    auto.arima(y_tr, xreg = as.numeric(xa_tr), ic = "aic"),
    error = function(e) NULL
  )
  fc_arimax[i] <- if (!is.null(fit_a))
    forecast(fit_a, xreg = as.numeric(xa_te), h = 1)$mean[1]
  else NA

  # ADL-MIDAS nealmon
  fit_m <- tryCatch(
    midas_r(y_tr ~ trend + fmls(x_tr, 11, 12, nealmon),
            start = list(x_tr = c(0, 0, 0))),
    error = function(e) NULL
  )
  fc_nealmon[i] <- if (!is.null(fit_m))
    forecast(fit_m, newdata = list(x_tr = x_te), h = 1)$mean[1]
  else NA

  # U-MIDAS
  fit_u <- tryCatch(
    midas_u(y_tr ~ fmls(x_tr, 11, 12) + trend),
    error = function(e) NULL
  )
  fc_umidas[i] <- if (!is.null(fit_u))
    forecast(fit_u, newdata = list(x_tr = x_te), h = 1)$mean[1]
  else NA
}

# ---- Compute RMSE / MAE ------------------------------------
rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae  <- function(e) mean(abs(e), na.rm = TRUE)

err_arimax  <- actuals - fc_arimax
err_nealmon <- actuals - fc_nealmon
err_umidas  <- actuals - fc_umidas

results <- data.frame(
  Model = c("ARIMAX", "ADL-MIDAS (nealmon)", "U-MIDAS"),
  RMSE  = c(rmse(err_arimax), rmse(err_nealmon), rmse(err_umidas)),
  MAE   = c(mae(err_arimax),  mae(err_nealmon),  mae(err_umidas))
)
print(results)

# ---- Diebold-Mariano test (MIDAS vs ARIMAX) ----------------
dm_test <- dm.test(err_nealmon, err_arimax, alternative = "less", h = 1)
cat("\nDiebold-Mariano test (nealmon vs ARIMAX):\n")
print(dm_test)

# ---- Save results ------------------------------------------
write.csv(results, "output/tables/forecast_comparison.csv", row.names = FALSE)

# ---- Plot forecast errors ----------------------------------
years <- eval_start:eval_end
plot(years, actuals, type = "l", lwd = 2,
     main = "Rolling 1-Step-Ahead Forecasts (2000-2011)",
     ylab = "GDP Growth Rate", xlab = "Year")
lines(years, fc_arimax,  col = "blue",   lty = 2)
lines(years, fc_nealmon, col = "red",    lty = 2)
lines(years, fc_umidas,  col = "green3", lty = 2)
legend("topright",
       c("Actual", "ARIMAX", "ADL-MIDAS", "U-MIDAS"),
       col = c("black", "blue", "red", "green3"),
       lty = c(1, 2, 2, 2), lwd = c(2, 1, 1, 1))
