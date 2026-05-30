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
# Plot separately so titles are not squeezed — hit Enter between plots
op <- par(mar = c(5, 4, 5, 2))   # extra top margin for title

plot_midas_coef(fit_nealmon, title = "nealmon (exp Almon) lag weights")
mtext("ADL-MIDAS — exponential Almon: smooth monotone decay",
      side = 3, line = 0.3, cex = 0.85, col = "grey30")

plot_midas_coef(fit_nbeta, title = "nbeta (normalized Beta) lag weights")
mtext("ADL-MIDAS — normalized Beta: note poor fit due to starting values",
      side = 3, line = 0.3, cex = 0.85, col = "grey30")

par(op)

# --- Restriction tests (nealmon restrictions adequate?) -----
hAh_test(fit_nealmon)
hAh_test(fit_nbeta)

# --- Model selection table ----------------------------------
# midas_r_ic_table() has a NULL-environment bug in R 4.x — use manual comparison
ic_table <- data.frame(
  Weight   = c("nealmon", "nbeta"),
  Params   = c(length(coef(fit_nealmon)), length(coef(fit_nbeta))),
  AIC      = c(AIC(fit_nealmon), AIC(fit_nbeta)),
  BIC      = c(BIC(fit_nealmon), BIC(fit_nbeta))
)
cat("\n--- ADL-MIDAS model comparison ---\n")
print(ic_table, row.names = FALSE, digits = 5)
cat("Best by AIC:", ic_table$Weight[which.min(ic_table$AIC)], "\n")
cat("Best by BIC:", ic_table$Weight[which.min(ic_table$BIC)], "\n")
cat("\nDone — models fitted and compared.\n")
