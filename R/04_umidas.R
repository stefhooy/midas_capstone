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

trend <- 1:length(y)

# --- U-MIDAS: unrestricted OLS, one coefficient per lag -----
fit_umidas <- midas_u(y ~ fmls(x, 11, 12) + trend)
summary(fit_umidas)

# --- Restricted (nealmon) for comparison --------------------
fit_nealmon <- midas_r(
  y ~ trend + fmls(x, 11, 12, nealmon),
  start = list(x = c(0, 0, 0))
)

# --- Are nealmon restrictions valid? Manual F-test ----------
# hAhr_test() has a matrix bug in R 4.x — compute manually instead
# H0: nealmon restrictions hold  (restricted = nealmon, unrestricted = U-MIDAS)
rss_r  <- sum(resid(fit_nealmon)^2)
rss_u  <- sum(resid(fit_umidas)^2)
df_r   <- length(coef(fit_nealmon))   # params in restricted model
df_u   <- length(coef(fit_umidas))    # params in unrestricted model
n      <- length(y)
q      <- df_u - df_r                 # number of restrictions

f_stat <- ((rss_r - rss_u) / q) / (rss_u / (n - df_u))
p_val  <- pf(f_stat, df1 = q, df2 = n - df_u, lower.tail = FALSE)

cat("\n--- Restriction test: nealmon vs U-MIDAS ---\n")
cat(sprintf("F(%d, %d) = %.4f,  p-value = %.4f\n", q, n - df_u, f_stat, p_val))
cat("Interpretation:",
    ifelse(p_val > 0.05,
           "Fail to reject H0 — nealmon restrictions are valid (parsimonious model OK)",
           "Reject H0 — nealmon restrictions are too tight, U-MIDAS fits significantly better"),
    "\n")

# --- AIC / BIC comparison -----------------------------------
cat("\n--- Information criteria ---\n")
cat(sprintf("nealmon:  AIC = %.2f,  BIC = %.2f  (%d params)\n",
            AIC(fit_nealmon), BIC(fit_nealmon), df_r))
cat(sprintf("U-MIDAS:  AIC = %.2f,  BIC = %.2f  (%d params)\n",
            AIC(fit_umidas),  BIC(fit_umidas),  df_u))
cat("Winner by AIC:", ifelse(AIC(fit_nealmon) < AIC(fit_umidas), "nealmon", "U-MIDAS"), "\n")
cat("Winner by BIC:", ifelse(BIC(fit_nealmon) < BIC(fit_umidas), "nealmon", "U-MIDAS"), "\n")
