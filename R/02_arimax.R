# ============================================================
# 02_arimax.R — ARIMAX Benchmark
# Strategy: pre-aggregate high-freq x to low-freq mean,
#            then fit ARIMA with external regressor
# ============================================================

library(midasr)
library(forecast)

data("USrealgdp")
data("USunempr")

y <- diff(log(USrealgdp))
x <- window(diff(USunempr), start = 1949)

# Pre-aggregate x: mean of 12 monthly values → 1 annual value
x_annual <- aggregate(x, FUN = mean)
x_annual <- window(x_annual, start = 1949, end = 2011)

# Fit: auto.arima selects ARIMA(p,d,q) order by AIC
fit_arimax <- auto.arima(y, xreg = as.numeric(x_annual), ic = "aic",
                         stepwise = FALSE, approximation = FALSE)
summary(fit_arimax)

# Residual diagnostics
checkresiduals(fit_arimax)

# Save for comparison in 06_evaluation.R
saveRDS(fit_arimax, "output/tables/fit_arimax.rds")
cat("ARIMAX fitted and saved.\n")
