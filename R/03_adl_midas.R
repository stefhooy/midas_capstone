# ============================================================
# 03_adl_midas.R — ADL-MIDAS Benchmark
# midas_r() with nealmon and nbeta weight functions
# ============================================================

library(midasr)

data("USrealgdp")
data("USunempr")

y <- diff(log(USrealgdp))
x <- window(diff(USunempr), start = 1949)

trend <- 1:length(y)

# --- nealmon (exponential Almon polynomial) ------------------
fit_nealmon <- midas_r(
  y ~ trend + fmls(x, 11, 12, nealmon),
  start = list(x = c(0, 0, 0))
)
summary(fit_nealmon)

# --- nbeta (normalized Beta) --------------------------------
fit_nbeta <- midas_r(
  y ~ trend + fmls(x, 11, 12, nbeta),
  start = list(x = c(1, 1, 5))
)
summary(fit_nbeta)

# --- Lag weight comparison ----------------------------------
par(mfrow = c(1, 2))
plot_midas_coef(fit_nealmon)
title("ADL-MIDAS: nealmon weights")
plot_midas_coef(fit_nbeta)
title("ADL-MIDAS: nbeta weights")
par(mfrow = c(1, 1))

# --- Restriction tests (nealmon restrictions adequate?) -----
hAh_test(fit_nealmon)
hAh_test(fit_nbeta)

# --- Model selection table ----------------------------------
ic_table <- midas_r_ic_table(
  y,
  table = list(fmls(x, 11, 12, nealmon)),
  start = list(x = c(0, 0, 0))
)
print(ic_table)

# Save
saveRDS(fit_nealmon, "output/tables/fit_nealmon.rds")
saveRDS(fit_nbeta,   "output/tables/fit_nbeta.rds")
cat("ADL-MIDAS models fitted and saved.\n")
