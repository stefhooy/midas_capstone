# ============================================================
# 01_tutorial.R — MIDAS Tutorial: USrealgdp + USunempr
# Frequency ratio m = 12 (12 months per 1 year)
# Shortcut: Ctrl+Shift+S (run whole file), Alt+Enter (run line/block)
# ============================================================

library(midasr)
library(forecast)

# ---- Step 1: Load and inspect data -------------------------

data("USrealgdp")   # annual GDP, 1948-2011
data("USunempr")    # monthly unemployment rate, 1948-2011

class(USrealgdp)
frequency(USrealgdp)   # 1 = annual
start(USrealgdp)
end(USrealgdp)

class(USunempr)
frequency(USunempr)    # 12 = monthly
start(USunempr)
end(USunempr)

par(mfrow = c(2, 1))
plot(USrealgdp, main = "US Real GDP (annual, billions $)", ylab = "")
plot(USunempr,  main = "US Unemployment Rate (monthly, %)", ylab = "")
par(mfrow = c(1, 1))

# ---- Step 2: Transform to stationary series ----------------
# GDP: log-difference = annual growth rate
# Unemployment: first difference = monthly change

y <- diff(log(USrealgdp))
x <- window(diff(USunempr), start = 1949)   # align start year to match y

length(y)              # 63  (1949-2011)
length(x)              # 756 = 63 * 12
length(x) / length(y) # 12 — our frequency ratio m

par(mfrow = c(2, 1))
plot(y, main = "Annual GDP Growth Rate (diff log)", ylab = "")
abline(h = 0, col = "red", lty = 2)
plot(x, main = "Monthly Change in Unemployment Rate (diff)", ylab = "")
abline(h = 0, col = "red", lty = 2)
par(mfrow = c(1, 1))

# ---- Step 3: Fit MIDAS model — nealmon (exp Almon) weights -

# fmls(x, 11, 12) = full MIDAS lags 0..11 at frequency ratio m=12
# nealmon = exponential Almon polynomial (2 free parameters)
# start list provides initial values for the weight function parameters

fit_nealmon <- midas_r(
  y ~ trend + fmls(x, 11, 12, nealmon),
  start = list(x = c(0, 0, 0))
)

summary(fit_nealmon)

# Visualise the estimated lag weights
plot_midas_coef(fit_nealmon)
title("Lag weights — nealmon (exp Almon)")

# ---- Step 4: Try nbeta weights and compare -----------------

# nbeta = normalized beta distribution (3 free parameters)
# More flexible hump-shaped decay

fit_nbeta <- midas_r(
  y ~ trend + fmls(x, 11, 12, nbeta),
  start = list(x = c(1, 1, 5))
)

summary(fit_nbeta)

# Compare lag shapes side by side
par(mfrow = c(1, 2))
plot_midas_coef(fit_nealmon); title("nealmon")
plot_midas_coef(fit_nbeta);   title("nbeta")
par(mfrow = c(1, 1))

# AIC / BIC comparison
AIC(fit_nealmon, fit_nbeta)
BIC(fit_nealmon, fit_nbeta)

# Restriction test: are the nealmon weights jointly adequate?
hAh_test(fit_nealmon)

# ---- Step 5: ARIMAX benchmark ------------------------------
# Pre-aggregate monthly x to annual mean, then fit ARIMA + external regressor

x_annual <- aggregate(x, FUN = mean)          # 63 annual averages
x_annual <- window(x_annual, start = 1949, end = 2011)

fit_arimax <- auto.arima(y, xreg = as.numeric(x_annual))
summary(fit_arimax)

# ---- Step 6: Rolling window forecast evaluation ------------

# Split: train on 1949-1999, evaluate on 2000-2011 (12 years)
split <- split_data(list(y = y, x = x), start = c(2000, 1), end = c(2011, 1),
                    expand = FALSE)

# Rolling 1-step-ahead forecasts for MIDAS (nealmon)
fc_midas <- forecast(fit_nealmon, newdata = split$test, h = 1)

# In-sample fitted values for now (rolling OOS requires re-fitting loop)
# See 06_evaluation.R for the full rolling window implementation

cat("\n--- In-sample fit comparison ---\n")
cat("nealmon — AIC:", AIC(fit_nealmon), " BIC:", BIC(fit_nealmon), "\n")
cat("nbeta   — AIC:", AIC(fit_nbeta),   " BIC:", BIC(fit_nbeta),   "\n")
cat("ARIMAX  — AIC:", AIC(fit_arimax),  " BIC:", BIC(fit_arimax),  "\n")
