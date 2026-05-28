# ============================================================
# 04_umidas.R — U-MIDAS Benchmark (Unrestricted MIDAS)
# midas_u() = OLS with all 12 monthly lags as separate regressors
# Many parameters — good in large samples, can overfit small ones
# ============================================================

library(midasr)

data("USrealgdp")
data("USunempr")

y <- diff(log(USrealgdp))
x <- window(diff(USunempr), start = 1949)

# midas_u: unrestricted — each of the 12 lags gets its own coefficient
fit_umidas <- midas_u(y ~ fmls(x, 11, 12) + trend)
summary(fit_umidas)

# Compare U-MIDAS vs restricted (nealmon) via restriction test
fit_nealmon <- midas_r(
  y ~ trend + fmls(x, 11, 12, nealmon),
  start = list(x = c(0, 0, 0))
)
hAhr_test(fit_nealmon, fit_umidas)   # H0: nealmon restrictions are valid

# Save
saveRDS(fit_umidas, "output/tables/fit_umidas.rds")
cat("U-MIDAS fitted and saved.\n")
