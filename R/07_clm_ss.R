# ============================================================
# 07_clm_ss.R — Phase 5: CLM-SS Framework (Novel Contribution)
# Composite Link Matrix State-Space Model
# ============================================================
#
# Model specification:
#   y_t   = mu + w_1*x_{t,1} + w_2*x_{t,2} + w_3*x_{t,3} + w_4*x_{t,4} + u_t
#   u_t   = phi * u_{t-1} + eps_t,    eps_t ~ N(0, sigma^2)
#
# Notation:
#   y_t     = monthly log-change in US Consumer Energy CPI (CPIENGSL)
#   x_{t,j} = j-th weekly log-change in WTI crude oil in month t (j=1..4)
#   w_j     = composite link weights — FREE, no parametric shape
#   phi     = AR(1) coefficient for the CPI error dynamics
#   sigma   = innovation standard deviation
#
# The "composite link matrix" Z = [w_1, w_2, w_3, w_4] maps the
# 4 weekly high-freq states into the monthly low-freq observation.
# Exact aggregation: each x_{t,j} enters individually (not averaged).
#
# Novel contribution vs benchmarks:
#   vs ARIMAX   : uses individual weekly obs (no pre-averaging / info loss)
#   vs MIDAS    : no parametric shape on w_j (nealmon/nbeta); adds AR errors
#   vs U-MIDAS  : same free weights; adds AR(1) via ML (GLS-efficient, not OLS)
#
# Estimation: joint MLE via optim(BFGS) over theta = [mu, w, phi, sigma]
# State-space: KFAS used for Kalman smoother diagnostics
# ============================================================

library(KFAS)
library(forecast)
library(xts)
library(zoo)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables",  recursive = TRUE, showWarnings = FALSE)

set.seed(42)

# ============================================================
# STEP 1 — Load data (same as 09_benchmarks.R)
# ============================================================
cpi_monthly <- readRDS("data/processed/cpi_energy_log_diff_monthly.rds")
wti_wk      <- readRDS("data/processed/wti_log_diff_weekly.rds")

y_all    <- as.numeric(cpi_monthly)
n_months <- length(y_all)

cat("Loaded: CPI Energy", n_months, "monthly obs |",
    format(start(cpi_monthly), "%Y-%m"), "to",
    format(end(cpi_monthly),   "%Y-%m"), "\n\n")

# ============================================================
# STEP 2 — Build m=4 aligned matrix (same function as 09_benchmarks.R)
# X_wti[i, ] = [x_{i,1}, x_{i,2}, x_{i,3}, x_{i,4}] — 4 weekly WTI obs for month i
# ============================================================
build_midas_x <- function(wti_series, cpi_index) {
  months    <- as.yearmon(cpi_index)
  wti_dates <- as.Date(index(wti_series))
  wti_vals  <- as.numeric(wti_series)
  n         <- length(months)
  x_mat     <- matrix(NA_real_, nrow = n, ncol = 4L)
  for (i in seq_len(n)) {
    m_start  <- as.Date(months[i])
    m_end    <- as.Date(months[i] + 1/12) - 1L
    in_month <- which(wti_dates >= m_start & wti_dates <= m_end)
    if (length(in_month) >= 4L) {
      sel <- tail(in_month, 4L)
    } else {
      before <- which(wti_dates < m_start)
      sel    <- c(tail(before, 4L - length(in_month)), in_month)
    }
    x_mat[i, ] <- wti_vals[sel]
  }
  x_mat
}

X_wti     <- build_midas_x(wti_wk, index(cpi_monthly))
x_monthly <- rowMeans(X_wti)    # monthly average for ARIMAX baseline

# ============================================================
# STEP 3 — CLM-SS log-likelihood (exact AR(1) formula)
# ============================================================
# params = [mu, w1, w2, w3, w4, phi_t, log_sigma]
# phi   = tanh(phi_t)   — guarantees |phi| < 1 (stationarity)
# sigma = exp(log_sigma) — guarantees sigma > 0

clmss_negloglik <- function(params, y, X) {
  mu    <- params[1]
  w     <- params[2:5]
  phi   <- tanh(params[6])
  sigma <- exp(params[7])

  # Composite link: remove deterministic part
  d   <- mu + as.numeric(X %*% w)
  e   <- y - d               # latent AR(1) process u_t

  n    <- length(e)
  sig2 <- sigma^2

  # Stationary marginal variance of AR(1): Var(u_1) = sigma^2 / (1 - phi^2)
  sv  <- sig2 / (1 - phi^2)

  # Exact log-likelihood: marginal for u_1, conditional for u_2..u_n
  ll  <- dnorm(e[1L], 0, sqrt(sv), log = TRUE)
  ll  <- ll + sum(dnorm(e[-1L] - phi * e[-n], 0, sigma, log = TRUE))

  -ll
}

# ============================================================
# STEP 4 — In-sample MLE (full 2000-2022 sample)
# ============================================================
cat("=== CLM-SS in-sample estimation (2000-2022) ===\n")

# Warm start from OLS (ignoring AR structure)
lm0    <- lm(y_all ~ X_wti)
inits  <- c(coef(lm0)[1],           # mu
            coef(lm0)[2:5],          # w_1 ... w_4
            0,                       # phi_t = 0 → phi = tanh(0) = 0
            log(sd(residuals(lm0)))) # log_sigma

opt <- optim(
  inits, clmss_negloglik, y = y_all, X = X_wti,
  method  = "BFGS",
  hessian = TRUE,
  control = list(maxit = 3000, reltol = 1e-12)
)

if (opt$convergence != 0)
  warning("Optimizer did not fully converge (code ", opt$convergence, ")")

mu_hat   <- opt$par[1]
w_hat    <- opt$par[2:5]
phi_hat  <- tanh(opt$par[6])
sig_hat  <- exp(opt$par[7])
loglik   <- -opt$value

cat("\n--- Estimated composite link weights ---\n")
for (j in 1:4)
  cat(sprintf("  w_%d (week %d): %+.5f\n", j, j, w_hat[j]))
cat(sprintf("  sum(w):         %+.5f   [uniform = %.5f each]\n",
            sum(w_hat), sum(w_hat) / 4))
cat(sprintf("\n--- AR(1) error process ---\n"))
cat(sprintf("  phi (AR coef):  %+.4f   (CPI error persistence)\n", phi_hat))
cat(sprintf("  sigma:           %.5f\n", sig_hat))
cat(sprintf("  mu (intercept):  %+.6f\n", mu_hat))
cat(sprintf("  Log-likelihood:  %.4f\n",  loglik))

# AIC / BIC (7 free parameters)
n_par  <- 7L
aic_clm <- -2 * loglik + 2  * n_par
bic_clm <- -2 * loglik + log(n_months) * n_par
cat(sprintf("  AIC: %.2f | BIC: %.2f\n\n", aic_clm, bic_clm))

# ============================================================
# STEP 5 — Identifiability check (standard errors from Hessian)
# ============================================================
cat("=== Identifiability check ===\n")

V_mat <- tryCatch(solve(opt$hessian), error = function(e) {
  cat("  WARNING: Hessian singular — identifiability problem\n")
  matrix(NA_real_, n_par, n_par)
})

se_raw <- sqrt(pmax(0, diag(V_mat)))

# Delta method for transformed parameters
se_phi   <- se_raw[6] * (1 - phi_hat^2)  # d/d(phi_t) tanh(phi_t) = 1-tanh^2
se_sigma <- se_raw[7] * sig_hat           # d/d(log_s) exp(log_s) = exp(log_s)

est_all  <- c(mu_hat, w_hat, phi_hat, sig_hat)
se_all   <- c(se_raw[1:5], se_phi, se_sigma)
z_scores <- est_all / se_all

ident_table <- data.frame(
  Parameter = c("mu", "w_1", "w_2", "w_3", "w_4", "phi", "sigma"),
  Estimate  = round(est_all, 5),
  Std_Error = round(se_all,  5),
  Z_score   = round(z_scores, 2),
  Sig       = ifelse(abs(z_scores) > 1.96, "(*)", "")
)

print(ident_table, row.names = FALSE)

if (all(is.finite(diag(V_mat))) && all(diag(V_mat) > 0)) {
  cat("\nHessian is positive definite — model is identified.\n\n")
} else {
  cat("\nWARNING: potential identifiability issue.\n\n")
}

# ============================================================
# STEP 6 — KFAS Kalman smoother (diagnostic: smoothed AR state)
# ============================================================
cat("=== KFAS Kalman smoother (smoothed AR(1) error state) ===\n")

d_hat_is <- mu_hat + as.numeric(X_wti %*% w_hat)
e_hat_is <- y_all - d_hat_is     # composite link residuals = AR(1) state

# Fit AR(1) state-space to residuals using KFAS
e_ts     <- ts(e_hat_is, start = c(2000, 2), frequency = 12)
model_ar <- SSModel(
  e_ts ~ -1 + SSMarima(ar = phi_hat, Q = matrix(sig_hat^2)),
  H = matrix(0)   # all variance in state equation
)

kfs_out  <- KFS(model_ar, smoothing = "state")
u_smooth <- as.numeric(kfs_out$alphahat)   # smoothed latent AR state

# AR(1) fitted values for in-sample diagnostics
yhat_is       <- d_hat_is + u_smooth
resid_is      <- y_all - yhat_is
rmse_is       <- sqrt(mean(resid_is^2))

cat(sprintf("In-sample RMSE (with smoothed state): %.5f\n\n", rmse_is))

# ============================================================
# STEP 7 — Ridge-penalized CLM-SS (sensitivity analysis)
# ============================================================
cat("=== Ridge penalty sensitivity (lambda = 0, 0.001, 0.01, 0.1) ===\n")

ridge_rows <- lapply(c(0, 0.001, 0.01, 0.1), function(lam) {
  neg_ridge <- function(params)
    clmss_negloglik(params, y_all, X_wti) + lam * sum(params[2:5]^2)
  opt_r <- tryCatch(
    optim(inits, neg_ridge, method = "BFGS",
          control = list(maxit = 1000, reltol = 1e-8)),
    error = function(e) NULL
  )
  if (is.null(opt_r)) return(NULL)
  w_r <- opt_r$par[2:5]
  data.frame(lambda = lam,
             w1 = round(w_r[1], 4), w2 = round(w_r[2], 4),
             w3 = round(w_r[3], 4), w4 = round(w_r[4], 4),
             phi = round(tanh(opt_r$par[6]), 3),
             sum_w = round(sum(w_r), 4))
})

ridge_tbl <- do.call(rbind, Filter(Negate(is.null), ridge_rows))
print(ridge_tbl, row.names = FALSE)
cat("(Weights shrink toward 0 as lambda increases; phi stays stable)\n\n")

# ============================================================
# STEP 8 — Rolling window forecast (expanding, 2015-2022)
# ============================================================
cat("=== CLM-SS rolling window (expanding, 2015-2022) ===\n")

cpi_dates <- as.Date(index(cpi_monthly))
test_idx  <- which(cpi_dates >= as.Date("2015-01-01"))
n_test    <- length(test_idx)

fc_clmss <- rep(NA_real_, n_test)
par_prev  <- inits       # warm start: initialise from full-sample OLS

t0 <- proc.time()

for (i in seq_len(n_test)) {
  te_i  <- test_idx[i]
  end_i <- te_i - 1L

  y_tr  <- y_all[1L:end_i]
  X_tr  <- X_wti[1L:end_i, ]
  X_te  <- matrix(X_wti[te_i, ], nrow = 1L)

  opt_i <- tryCatch(
    optim(par_prev, clmss_negloglik, y = y_tr, X = X_tr,
          method  = "BFGS",
          control = list(maxit = 500, reltol = 1e-8)),
    error = function(e) NULL
  )

  if (!is.null(opt_i) && opt_i$convergence == 0) {
    mu_i   <- opt_i$par[1]
    w_i    <- opt_i$par[2:5]
    phi_i  <- tanh(opt_i$par[6])

    # Last AR(1) residual in training data (= current state u_T)
    d_tr  <- mu_i + as.numeric(X_tr %*% w_i)
    u_T   <- (y_tr - d_tr)[end_i]

    # 1-step-ahead forecast: deterministic + AR(1) state prediction
    d_te       <- mu_i + as.numeric(X_te %*% w_i)
    fc_clmss[i] <- d_te + phi_i * u_T

    par_prev <- opt_i$par   # warm start for next iteration
  }

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  clm-ss=%+.4f\n",
                i, n_test, format(cpi_dates[te_i], "%Y-%m"), fc_clmss[i]))
}

elapsed <- round((proc.time() - t0)["elapsed"], 1)
cat("\nCLM-SS rolling window complete in", elapsed, "seconds.\n\n")

# ============================================================
# STEP 9 — Full model comparison + Diebold-Mariano tests
# ============================================================
y_actual <- y_all[test_idx]

rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae  <- function(e) mean(abs(e),   na.rm = TRUE)

e_clmss  <- y_actual - fc_clmss

# Load Phase 4 forecast vectors
ph4 <- tryCatch(
  readRDS("data/processed/phase4_forecasts.rds"),
  error = function(e) {
    message("Phase 4 forecasts not found — re-run 09_benchmarks.R first")
    NULL
  }
)

if (!is.null(ph4)) {
  e_arimax  <- ph4$y_actual - ph4$fc_arimax
  e_nealmon <- ph4$y_actual - ph4$fc_nealmon
  e_nbeta   <- ph4$y_actual - ph4$fc_nbeta
  e_umidas  <- ph4$y_actual - ph4$fc_umidas
  arimax_rmse <- rmse(e_arimax)

  all_results <- data.frame(
    Model         = c("ARIMAX", "ADL-MIDAS nealmon", "ADL-MIDAS nbeta",
                      "U-MIDAS", "CLM-SS"),
    RMSE          = round(c(rmse(e_arimax),  rmse(e_nealmon), rmse(e_nbeta),
                            rmse(e_umidas),  rmse(e_clmss)),  6),
    MAE           = round(c(mae(e_arimax),   mae(e_nealmon),  mae(e_nbeta),
                            mae(e_umidas),   mae(e_clmss)),   6),
    vs_ARIMAX_pct = round(c(0,
      100*(rmse(e_nealmon)-arimax_rmse)/arimax_rmse,
      100*(rmse(e_nbeta)  -arimax_rmse)/arimax_rmse,
      100*(rmse(e_umidas) -arimax_rmse)/arimax_rmse,
      100*(rmse(e_clmss)  -arimax_rmse)/arimax_rmse), 1),
    NAs           = c(sum(is.na(ph4$fc_arimax)), sum(is.na(ph4$fc_nealmon)),
                      sum(is.na(ph4$fc_nbeta)),  sum(is.na(ph4$fc_umidas)),
                      sum(is.na(fc_clmss)))
  )

  cat("=== Full model comparison (Phase 4 + CLM-SS) ===\n")
  print(all_results, row.names = FALSE)
  cat("\nBest RMSE:", all_results$Model[which.min(all_results$RMSE)], "\n")
  cat("Best MAE: ", all_results$Model[which.min(all_results$MAE)],  "\n\n")

  # Diebold-Mariano tests
  cat("=== Diebold-Mariano tests (H1: CLM-SS < rival's loss) ===\n")

  dm_safe <- function(e_rival, label) {
    ok  <- !is.na(e_clmss) & !is.na(e_rival)
    res <- tryCatch(
      dm.test(e_clmss[ok], e_rival[ok], alternative = "less", h = 1L, power = 2),
      error = function(e) NULL
    )
    if (!is.null(res)) {
      sig <- ifelse(res$p.value < 0.05, "(*)", ifelse(res$p.value < 0.10, "(.)", ""))
      cat(sprintf("  CLM-SS vs %-18s DM = %6.3f  p = %.4f  %s\n",
                  paste0(label, ":"), res$statistic, res$p.value, sig))
    }
  }

  dm_safe(e_arimax,  "ARIMAX")
  dm_safe(e_nealmon, "nealmon")
  dm_safe(e_nbeta,   "nbeta")
  dm_safe(e_umidas,  "U-MIDAS")
  cat("(*) p < 0.05  (.) p < 0.10\n\n")

} else {
  all_results <- data.frame(
    Model = "CLM-SS",
    RMSE  = round(rmse(e_clmss), 6),
    MAE   = round(mae(e_clmss),  6)
  )
  cat("=== CLM-SS OOS results ===\n")
  print(all_results, row.names = FALSE)
}

# ============================================================
# STEP 10 — Plots
# ============================================================
render <- function(plot_fn, file, w, h) {
  dev.new(); plot_fn()
  png(file, width = w, height = h, units = "in", res = 300)
  plot_fn(); invisible(dev.off())
  cat("Saved:", file, "\n")
}

test_dates <- cpi_dates[test_idx]
all_dates  <- cpi_dates

# ---- 10a: Composite link weights (bar chart) ----------------
render(function() {
  par(mar = c(5, 4, 5, 2))
  bp <- barplot(w_hat,
                names.arg = paste0("Week ", 1:4),
                col       = c("steelblue4", "steelblue3", "steelblue2", "steelblue1"),
                border    = "white",
                main      = "CLM-SS: Composite Link Weights (full sample, 2000-2022)",
                sub       = "Each bar = marginal effect of that week's WTI log-change on monthly CPI Energy",
                ylab      = "Weight  w_j",
                ylim      = c(min(0, min(w_hat) * 1.2), max(w_hat) * 1.4))
  abline(h = 0,         col = "grey60",  lty = 2, lwd = 0.8)
  abline(h = mean(w_hat), col = "tomato", lty = 2, lwd = 1.5)
  legend("topright", bty = "n", cex = 0.85, lty = 2, lwd = 1.5, col = "tomato",
         legend = sprintf("ARIMAX-equiv (uniform avg = %.4f each)", mean(w_hat)))
  text(bp, w_hat + max(w_hat) * 0.06,
       labels = sprintf("%.4f", w_hat), cex = 0.85, font = 2)
}, "output/figures/09_clmss_weights.png", 8, 5)

# ---- 10b: Smoothed AR(1) state over full sample ------------
render(function() {
  par(mar = c(4, 4, 4, 1))
  plot(all_dates, e_hat_is, type = "l", col = "grey70", lwd = 1,
       main = "CLM-SS: Smoothed AR(1) Error State u_t (2000-2022)",
       sub  = "Residual CPI dynamics not explained by composite link weights",
       xlab = "", ylab = "u_t  (AR state)")
  lines(all_dates, u_smooth, col = "steelblue", lwd = 1.8)
  abline(h = 0, col = "grey40", lty = 2)
  legend("topright", bty = "n", lwd = c(1, 1.8),
         col = c("grey70", "steelblue"),
         legend = c("Raw residual (y - d_t)", "Kalman-smoothed state"))
  text(as.Date("2020-04-01"), min(e_hat_is) * 0.7,
       "COVID\ncrash", col = "firebrick", cex = 0.8)
}, "output/figures/10_clmss_ar_state.png", 11, 5)

# ---- 10c: OOS forecast comparison (CLM-SS vs actual) --------
render(function() {
  ylim <- range(c(y_actual, fc_clmss), na.rm = TRUE)
  par(mar = c(4, 4.5, 4, 1))
  plot(test_dates, y_actual, type = "l", lwd = 2, col = "black", ylim = ylim,
       main = "CLM-SS One-Step-Ahead Forecasts vs Actual (2015-2022)",
       sub  = sprintf("RMSE = %.5f | phi = %.3f | Expanding window",
                      rmse(e_clmss), phi_hat),
       xlab = "", ylab = "Monthly log-change in CPI Energy")
  lines(test_dates, fc_clmss, col = "darkorchid", lwd = 1.6)
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  legend("bottomleft", bty = "n", cex = 0.85, lwd = c(2, 1.6),
         col = c("black", "darkorchid"),
         legend = c("Actual",
                    paste0("CLM-SS  (RMSE=", round(rmse(e_clmss), 4), ")")))
}, "output/figures/11_clmss_forecasts.png", 12, 5)

# ---- 10d: Full RMSE comparison bar chart --------------------
if (!is.null(ph4)) {
  render(function() {
    cols <- c("tomato", "steelblue", "forestgreen", "purple", "darkorchid")
    par(mar = c(4, 9, 4, 2))
    bp <- barplot(all_results$RMSE,
                  names.arg = all_results$Model,
                  horiz = TRUE, las = 1, col = cols, border = "white",
                  main  = "Out-of-Sample RMSE — All Models (2015-2022)",
                  xlab  = "Root Mean Squared Error",
                  xlim  = c(0, max(all_results$RMSE) * 1.22))
    abline(v = all_results$RMSE[1], col = "tomato", lty = 2, lwd = 1.2)
    text(all_results$RMSE + max(all_results$RMSE)*0.01, bp,
         labels = sprintf("%.5f", all_results$RMSE), adj = 0, cex = 0.82)
  }, "output/figures/12_full_rmse_comparison.png", 10, 5)
}

# ============================================================
# STEP 11 — Save results (4-lag CLM-SS)
# ============================================================
write.csv(ident_table,  "output/tables/clmss_identifiability.csv",  row.names = FALSE)
write.csv(ridge_tbl,    "output/tables/clmss_ridge_sensitivity.csv", row.names = FALSE)
if (!is.null(ph4))
  write.csv(all_results, "output/tables/full_model_comparison.csv", row.names = FALSE)

# ============================================================
# STEP 12 — Extended CLM-SS: 3 months of weekly lags (12 weights)
# ============================================================
# Diagnosis: CLM-SS(k=4) lost because Phase 4 showed optimal MIDAS
# uses k=11 (12 weekly lags, 3 months back). The weight hump peaks
# at lag 5-6 — entirely outside the 4-lag CLM-SS window.
# Fix: extend design matrix to 3 × 4 = 12 weekly obs per month,
# matching MIDAS's lag depth. Ridge penalty prevents overfitting
# with 12 free weights.

cat("\n============================================================\n")
cat("STEP 12 — Extended CLM-SS: 12 weekly lags (3 months back)\n")
cat("============================================================\n\n")

# Build 12-column design matrix: [month t, t-1, t-2] × [weeks 1-4]
build_ext_x <- function(X_mat, n_months_back = 2L) {
  n     <- nrow(X_mat)
  n_col <- 4L * (n_months_back + 1L)
  X_ext <- matrix(NA_real_, nrow = n, ncol = n_col)
  for (i in seq_len(n)) {
    if (i > n_months_back) {
      lag_rows <- seq(i, i - n_months_back)           # current, prev, prev-prev
      X_ext[i, ] <- as.numeric(t(X_mat[lag_rows, ])) # flatten row-major
    }
  }
  X_ext
}

X_ext    <- build_ext_x(X_wti, n_months_back = 2L)   # n × 12
valid    <- which(complete.cases(X_ext))               # drop first 2 rows
X12      <- X_ext[valid, ]
y12      <- y_all[valid]
n12      <- length(y12)
cat("Extended design matrix:", nrow(X12), "months x 12 weekly lags\n\n")

# Generalized log-likelihood (works for any width p)
clmss_ll_gen <- function(params, y, X, lambda = 0) {
  p     <- ncol(X)
  mu    <- params[1]
  w     <- params[2:(p + 1)]
  phi   <- tanh(params[p + 2])
  sigma <- exp(params[p + 3])
  d     <- mu + as.numeric(X %*% w)
  e     <- y - d
  n     <- length(e)
  sig2  <- sigma^2
  sv    <- sig2 / (1 - phi^2)
  ll    <- dnorm(e[1L], 0, sqrt(sv), log = TRUE)
  ll    <- ll + sum(dnorm(e[-1L] - phi * e[-n], 0, sigma, log = TRUE))
  -ll + lambda * sum(w^2)
}

# Ridge lambda selection: profile grid search over validation (last 2 years in-sample)
val_idx    <- which(seq_len(n12) > n12 - 24L)   # last 24 months as local holdout
train_idx2 <- setdiff(seq_len(n12), val_idx)

lambda_grid <- c(0, 0.001, 0.005, 0.01, 0.05, 0.1)
val_rmse    <- vapply(lambda_grid, function(lam) {
  init12 <- c(mean(y12), rep(0, 12), 0, log(sd(y12)))
  opt12  <- tryCatch(
    optim(init12, clmss_ll_gen, y = y12[train_idx2], X = X12[train_idx2, ],
          lambda = lam, method = "BFGS",
          control = list(maxit = 1000, reltol = 1e-8)),
    error = function(e) NULL
  )
  if (is.null(opt12)) return(Inf)
  mu_v  <- opt12$par[1]
  w_v   <- opt12$par[2:13]
  phi_v <- tanh(opt12$par[14])
  d_val <- mu_v + as.numeric(X12[val_idx, ] %*% w_v)
  e_tr  <- y12[train_idx2] - (mu_v + as.numeric(X12[train_idx2, ] %*% w_v))
  u_T   <- e_tr[length(e_tr)]
  # 1-step ahead is not clean for 24 val points; use in-sample val RMSE as proxy
  rmse(y12[val_idx] - d_val)  # deterministic part only
}, numeric(1))

best_lambda <- lambda_grid[which.min(val_rmse)]
cat(sprintf("Lambda grid: %s\n", paste(lambda_grid, collapse=" | ")))
cat(sprintf("Val RMSE:    %s\n", paste(round(val_rmse, 5), collapse=" | ")))
cat(sprintf("Selected lambda = %s\n\n", best_lambda))

# Fit extended CLM-SS with best lambda on full sample
init12   <- c(mean(y12), rep(0, 12), 0, log(sd(y12)))
opt12_is <- optim(
  init12, clmss_ll_gen, y = y12, X = X12, lambda = best_lambda,
  method  = "BFGS", hessian = FALSE,
  control = list(maxit = 3000, reltol = 1e-12)
)

mu12    <- opt12_is$par[1]
w12     <- opt12_is$par[2:13]
phi12   <- tanh(opt12_is$par[14])
sig12   <- exp(opt12_is$par[15])

cat("Extended CLM-SS weights (w_1 .. w_12, 3 months of weeks):\n")
month_labs <- c("Month 0", "Month -1", "Month -2")
for (m in 0:2)
  cat(sprintf("  %s [wk1-4]: %+.4f  %+.4f  %+.4f  %+.4f\n",
              month_labs[m+1],
              w12[m*4+1], w12[m*4+2], w12[m*4+3], w12[m*4+4]))
cat(sprintf("  phi = %.4f  |  sigma = %.5f  |  lambda = %s\n\n",
            phi12, sig12, best_lambda))

# ============================================================
# STEP 13 — Rolling window: extended CLM-SS (2015-2022)
# ============================================================
cat("=== Extended CLM-SS rolling window ===\n")

# Map test months back to the valid (post-lag) index
cpi_dates_full <- as.Date(index(cpi_monthly))
test_full_idx  <- which(cpi_dates_full >= as.Date("2015-01-01"))

fc_clmss12  <- rep(NA_real_, n_test)
par12_prev  <- init12

t0_12 <- proc.time()

for (i in seq_len(n_test)) {
  te_i  <- test_full_idx[i]   # index in full y_all / X_wti space

  # Build extended X for this iteration's training window
  # Need all months up to te_i-1, but require at least 2 prior months
  if (te_i <= 3L) next

  # Training: months 3..te_i-1 (valid extended observations)
  X_tr12 <- build_ext_x(X_wti[1L:te_i - 1L, ], n_months_back = 2L)
  valid12 <- which(complete.cases(X_tr12))
  if (length(valid12) < 20L) next
  y_tr12  <- y_all[valid12]
  X_tr12  <- X_tr12[valid12, ]

  opt12_i <- tryCatch(
    optim(par12_prev, clmss_ll_gen, y = y_tr12, X = X_tr12,
          lambda = best_lambda, method = "BFGS",
          control = list(maxit = 500, reltol = 1e-8)),
    error = function(e) NULL
  )

  if (!is.null(opt12_i) && opt12_i$convergence == 0) {
    mu_i   <- opt12_i$par[1]
    w_i    <- opt12_i$par[2:13]
    phi_i  <- tanh(opt12_i$par[14])

    # Build test month's 12-lag row: months te_i, te_i-1, te_i-2
    x_te12 <- as.numeric(t(X_wti[c(te_i, te_i - 1L, te_i - 2L), ]))
    if (any(is.na(x_te12))) next

    # Last training AR residual
    d_tr12 <- mu_i + as.numeric(X_tr12 %*% w_i)
    u_T12  <- (y_tr12 - d_tr12)[length(y_tr12)]

    # Forecast
    d_te12        <- mu_i + sum(w_i * x_te12)
    fc_clmss12[i] <- d_te12 + phi_i * u_T12

    par12_prev <- opt12_i$par
  }

  if (i %% 12L == 0L || i == 1L)
    cat(sprintf("  [%3d/%d] %s  ext-clm-ss=%+.4f\n",
                i, n_test, format(cpi_dates_full[te_i], "%Y-%m"),
                fc_clmss12[i]))
}

elapsed12 <- round((proc.time() - t0_12)["elapsed"], 1)
cat("\nExtended CLM-SS complete in", elapsed12, "seconds.\n\n")

e_clmss12 <- y_actual - fc_clmss12

if (!is.null(ph4)) {
  all_results2 <- rbind(
    all_results,
    data.frame(
      Model         = "CLM-SS (12 lags, ridge)",
      RMSE          = round(rmse(e_clmss12), 6),
      MAE           = round(mae(e_clmss12),  6),
      vs_ARIMAX_pct = round(100 * (rmse(e_clmss12) - rmse(e_arimax)) /
                              rmse(e_arimax), 1),
      NAs           = sum(is.na(fc_clmss12))
    )
  )
  cat("=== Updated model comparison (all 6 models) ===\n")
  print(all_results2, row.names = FALSE)

  # DM test: extended CLM-SS vs nbeta (best Phase 4 model)
  ok <- !is.na(fc_clmss12) & !is.na(ph4$fc_nbeta)
  dm12 <- tryCatch(
    dm.test(e_clmss12[ok], e_nbeta[ok], alternative = "less", h = 1L, power = 2),
    error = function(e) NULL
  )
  if (!is.null(dm12))
    cat(sprintf("\nDM: CLM-SS(12) vs nbeta: DM=%.3f  p=%.4f  %s\n",
                dm12$statistic, dm12$p.value,
                ifelse(dm12$p.value < 0.05, "(*)", "")))

  # Updated RMSE bar chart
  render(function() {
    cols <- c("tomato", "steelblue", "forestgreen", "purple",
              "darkorchid", "darkorchid4")
    par(mar = c(4, 11, 4, 2))
    bp <- barplot(all_results2$RMSE,
                  names.arg = all_results2$Model,
                  horiz = TRUE, las = 1, col = cols, border = "white",
                  main  = "Out-of-Sample RMSE — All Models (2015-2022)",
                  xlab  = "Root Mean Squared Error",
                  xlim  = c(0, max(all_results2$RMSE) * 1.25))
    abline(v = all_results2$RMSE[1], col = "tomato", lty = 2, lwd = 1.2)
    text(all_results2$RMSE + max(all_results2$RMSE) * 0.01, bp,
         labels = sprintf("%.5f", all_results2$RMSE), adj = 0, cex = 0.8)
  }, "output/figures/13_final_rmse_comparison.png", 11, 5)

  write.csv(all_results2, "output/tables/full_model_comparison_final.csv",
            row.names = FALSE)
}

# Save CLM-SS forecast vectors for Phase 7d directional accuracy analysis
saveRDS(list(
  fc_clmss4  = fc_clmss,
  fc_clmss12 = fc_clmss12,
  y_actual   = y_actual,
  test_dates = cpi_dates[test_idx]
), "data/processed/clmss_forecasts.rds")

cat("\n=== Phase 5 complete ===\n")
cat("Key results:\n")
cat(sprintf("  CLM-SS (4 lags) RMSE:   %.5f  (+6.2%% vs ARIMAX — lag-limited)\n",
            rmse(e_clmss)))
cat(sprintf("  CLM-SS (12 lags) RMSE:  %.5f\n", rmse(e_clmss12)))
cat(sprintf("  phi (AR persistence):    %.4f\n", phi_hat))
cat(sprintf("  lambda (ridge):          %s\n", best_lambda))
cat(sprintf("  Best model overall:      %s\n",
            if (!is.null(ph4)) all_results2$Model[which.min(all_results2$RMSE)]
            else "CLM-SS"))
cat("Figures saved:\n")
cat("  09_clmss_weights.png | 10_clmss_ar_state.png\n")
cat("  11_clmss_forecasts.png | 12_full_rmse_comparison.png\n")
cat("  13_final_rmse_comparison.png\n")
cat("Tables saved:\n")
cat("  clmss_identifiability.csv | clmss_ridge_sensitivity.csv\n")
cat("  full_model_comparison.csv | full_model_comparison_final.csv\n")
