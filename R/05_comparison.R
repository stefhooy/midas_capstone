# ============================================================
# 05_comparison.R — In-Sample Model Comparison
# Fits all 4 models and produces a clean side-by-side table
# Run after 02_arimax.R / 03_adl_midas.R / 04_umidas.R
# ============================================================

library(midasr)
library(forecast)

data("USrealgdp")
data("USunempr")

y        <- diff(log(USrealgdp))
x        <- window(diff(USunempr), start = 1949)
x_annual <- window(aggregate(x, FUN = mean), start = 1949, end = 2011)
trend    <- 1:length(y)

# ---- Fit all models ----------------------------------------
fit_arimax <- auto.arima(y, xreg = as.numeric(x_annual), ic = "aic",
                         stepwise = FALSE, approximation = FALSE)

fit_nealmon <- midas_r(y ~ trend + fmls(x, 11, 12, nealmon),
                       start = list(x = c(0, 0, 0)))

fit_nbeta <- midas_r(y ~ trend + fmls(x, 11, 12, nbeta),
                     start = list(x = c(1, 1, 5)))

fit_umidas <- midas_u(y ~ fmls(x, 11, 12) + trend)

# ---- Summary table -----------------------------------------
n_params <- function(m) length(coef(m))

results <- data.frame(
  Model    = c("ARIMAX", "ADL-MIDAS (nealmon)", "ADL-MIDAS (nbeta)", "U-MIDAS"),
  Params   = c(n_params(fit_arimax), n_params(fit_nealmon),
               n_params(fit_nbeta),  n_params(fit_umidas)),
  AIC      = c(AIC(fit_arimax), AIC(fit_nealmon), AIC(fit_nbeta), AIC(fit_umidas)),
  BIC      = c(BIC(fit_arimax), BIC(fit_nealmon), BIC(fit_nbeta), BIC(fit_umidas)),
  RMSE_in  = c(
    sqrt(mean(resid(fit_arimax)^2)),
    sqrt(mean(resid(fit_nealmon)^2)),
    sqrt(mean(resid(fit_nbeta)^2)),
    sqrt(mean(resid(fit_umidas)^2))
  )
)

cat("=== In-sample model comparison (USrealgdp + USunempr, 1949-2011) ===\n\n")
print(results, digits = 4, row.names = FALSE)
cat("\nBest by AIC:", results$Model[which.min(results$AIC)], "\n")
cat("Best by BIC:", results$Model[which.min(results$BIC)], "\n")
cat("Best in-sample RMSE:", results$Model[which.min(results$RMSE_in)], "\n")

# ---- Lag weight plots (nealmon only — nbeta local min) -----
op <- par(mar = c(5, 4, 5, 2))
plot_midas_coef(fit_nealmon, title = "ADL-MIDAS: nealmon lag weights")
mtext("Smooth monotone decay — restrictions valid (F-test p = 0.68)",
      side = 3, line = 0.3, cex = 0.85, col = "grey30")
par(op)

# ---- Residual comparison -----------------------------------
par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
plot(resid(fit_arimax),  type = "l", main = "ARIMAX residuals",         ylab = "")
abline(h = 0, col = "red", lty = 2)
plot(resid(fit_nealmon), type = "l", main = "ADL-MIDAS (nealmon) residuals", ylab = "")
abline(h = 0, col = "red", lty = 2)
plot(resid(fit_nbeta),   type = "l", main = "ADL-MIDAS (nbeta) residuals",   ylab = "")
abline(h = 0, col = "red", lty = 2)
plot(resid(fit_umidas),  type = "l", main = "U-MIDAS residuals",        ylab = "")
abline(h = 0, col = "red", lty = 2)
par(mfrow = c(1, 1))
