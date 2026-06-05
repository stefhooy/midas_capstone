# ============================================================
# 12_final_evaluation.R - Final AIC/BIC and forecast metrics
#
# Purpose:
#   1. Refit likelihood-based in-sample models for AIC/BIC.
#   2. Combine saved rolling forecasts and compute RMSE, MAE, MASE,
#      MAPE, sMAPE, and directional accuracy on the same OOS period.
#   3. Document why MAPE is fragile for log-change data near zero.
# ============================================================

library(midasr)
library(forecast)
library(xts)
library(zoo)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)

rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae <- function(e) mean(abs(e), na.rm = TRUE)
dir_acc <- function(fc, actual) {
  ok <- is.finite(fc) & is.finite(actual)
  round(mean(sign(fc[ok]) == sign(actual[ok])) * 100, 1)
}
mape <- function(actual, fc) {
  ok <- is.finite(actual) & is.finite(fc) & actual != 0
  mean(abs((actual[ok] - fc[ok]) / actual[ok])) * 100
}
smape <- function(actual, fc) {
  ok <- is.finite(actual) & is.finite(fc) &
    (abs(actual) + abs(fc)) > 0
  mean(2 * abs(fc[ok] - actual[ok]) /
         (abs(actual[ok]) + abs(fc[ok]))) * 100
}

build_midas_x <- function(wti_series, cpi_index) {
  months <- as.yearmon(cpi_index)
  wti_dates <- as.Date(index(wti_series))
  wti_vals <- as.numeric(wti_series)
  n <- length(months)
  x_mat <- matrix(NA_real_, nrow = n, ncol = 4L)

  for (i in seq_len(n)) {
    m_start <- as.Date(months[i])
    m_end <- as.Date(months[i] + 1 / 12) - 1L
    in_month <- which(wti_dates >= m_start & wti_dates <= m_end)

    if (length(in_month) >= 4L) {
      sel <- tail(in_month, 4L)
    } else {
      before <- which(wti_dates < m_start)
      sel <- c(tail(before, 4L - length(in_month)), in_month)
    }
    x_mat[i, ] <- wti_vals[sel]
  }

  list(matrix = x_mat, vector = as.vector(t(x_mat)))
}

build_ext_x <- function(X_mat, n_months_back = 2L) {
  n <- nrow(X_mat)
  n_col <- 4L * (n_months_back + 1L)
  X_ext <- matrix(NA_real_, nrow = n, ncol = n_col)
  for (i in seq_len(n)) {
    if (i > n_months_back) {
      lag_rows <- seq(i, i - n_months_back)
      X_ext[i, ] <- as.numeric(t(X_mat[lag_rows, ]))
    }
  }
  X_ext
}

clmss_ll_gen <- function(params, y, X, lambda = 0) {
  p <- ncol(X)
  mu <- params[1]
  w <- params[2:(p + 1)]
  phi <- tanh(params[p + 2])
  sigma <- exp(params[p + 3])
  d <- mu + as.numeric(X %*% w)
  e <- y - d
  n <- length(e)
  sig2 <- sigma^2
  sv <- sig2 / (1 - phi^2)
  ll <- dnorm(e[1L], 0, sqrt(sv), log = TRUE)
  ll <- ll + sum(dnorm(e[-1L] - phi * e[-n], 0, sigma, log = TRUE))
  -ll + lambda * sum(w^2)
}

cat("Loading processed data...\n")
cpi_monthly <- readRDS("data/processed/cpi_energy_log_diff_monthly.rds")
wti_wk <- readRDS("data/processed/wti_log_diff_weekly.rds")

y_all <- as.numeric(cpi_monthly)
cpi_dates <- as.Date(index(cpi_monthly))
n_months <- length(y_all)

x_built <- build_midas_x(wti_wk, index(cpi_monthly))
X_wti4 <- x_built$matrix
x_all <- x_built$vector
x_monthly <- rowMeans(X_wti4)

# ============================================================
# 1. In-sample AIC/BIC for likelihood-based/statistical models
# ============================================================

cat("Refitting in-sample likelihood models for AIC/BIC...\n")

fit_arimax <- auto.arima(y_all, xreg = x_monthly, ic = "aic",
                         stepwise = FALSE, approximation = FALSE)
fit_nealmon <- midas_r(y_all ~ fmls(x_all, 11, 4, nealmon),
                       start = list(x_all = c(0, 0, 0)))
fit_nbeta <- midas_r(y_all ~ fmls(x_all, 11, 4, nbeta),
                     start = list(x_all = c(1, 1, 5)))
fit_umidas <- midas_u(y_all ~ fmls(x_all, 11, 4))

X12_all <- build_ext_x(X_wti4, n_months_back = 2L)
valid12 <- which(complete.cases(X12_all))
X12 <- X12_all[valid12, ]
y12 <- y_all[valid12]

fit_clmss12 <- tryCatch({
  init <- c(mean(y12), rep(0, ncol(X12)), 0, log(sd(y12)))
  optim(init, clmss_ll_gen, y = y12, X = X12, lambda = 0,
        method = "BFGS",
        control = list(maxit = 3000, reltol = 1e-12))
}, error = function(e) NULL)

clm_aic <- clm_bic <- clm_loglik <- NA_real_
if (!is.null(fit_clmss12)) {
  clm_loglik <- -fit_clmss12$value
  clm_k <- ncol(X12) + 3L
  clm_aic <- -2 * clm_loglik + 2 * clm_k
  clm_bic <- -2 * clm_loglik + log(length(y12)) * clm_k
}

ic_tbl <- data.frame(
  Model = c("ARIMAX monthly mean",
            "MIDAS nealmon (12 weekly lags)",
            "MIDAS nbeta (12 weekly lags)",
            "U-MIDAS (12 weekly lags)",
            "CLM-SS (12 weekly lags)",
            "LASSO-MIDAS",
            "Kernel U-MIDAS",
            "XGBoost",
            "LSTM",
            "PCA-ARIMAX"),
  Model_class = c("Likelihood/ARIMA",
                  "Likelihood/MIDAS",
                  "Likelihood/MIDAS",
                  "Likelihood/OLS",
                  "Likelihood/state-space",
                  "Penalised regression",
                  "Penalised smoother",
                  "Machine learning",
                  "Machine learning",
                  "Diagnostic compression"),
  Effective_N = c(length(residuals(fit_arimax)),
                  length(residuals(fit_nealmon)),
                  length(residuals(fit_nbeta)),
                  length(residuals(fit_umidas)),
                  length(y12),
                  NA, NA, NA, NA, NA),
  Parameters = c(length(coef(fit_arimax)),
                 length(coef(fit_nealmon)),
                 length(coef(fit_nbeta)),
                 length(coef(fit_umidas)),
                 ncol(X12) + 3L,
                 NA, NA, NA, NA, NA),
  AIC = round(c(AIC(fit_arimax),
                AIC(fit_nealmon),
                AIC(fit_nbeta),
                AIC(fit_umidas),
                clm_aic,
                NA, NA, NA, NA, NA), 2),
  BIC = round(c(BIC(fit_arimax),
                BIC(fit_nealmon),
                BIC(fit_nbeta),
                BIC(fit_umidas),
                clm_bic,
                NA, NA, NA, NA, NA), 2),
  In_sample_RMSE = round(c(rmse(residuals(fit_arimax)),
                           rmse(residuals(fit_nealmon)),
                           rmse(residuals(fit_nbeta)),
                           rmse(residuals(fit_umidas)),
                           NA, NA, NA, NA, NA, NA), 5),
  AIC_BIC_applicable = c("Yes", "Yes", "Yes", "Yes",
                         "Yes, but effective sample differs",
                         "No standard IC after L1 penalty",
                         "No standard IC after smoothing penalty",
                         "No likelihood AIC/BIC",
                         "No likelihood AIC/BIC",
                         "Not central; diagnostic benchmark"),
  stringsAsFactors = FALSE
)

write.csv(ic_tbl, "output/tables/final_insample_aic_bic.csv",
          row.names = FALSE)

# ============================================================
# 2. OOS forecast performance: RMSE, MAE, MASE, MAPE, sMAPE
# ============================================================

cat("Combining saved rolling forecasts...\n")
ph4 <- readRDS("data/processed/phase4_forecasts.rds")
clm <- readRDS("data/processed/clmss_forecasts.rds")
xgb <- readRDS("data/processed/xgb_forecasts.rds")
ker <- readRDS("data/processed/kernel_umidas_forecasts.rds")
las <- readRDS("data/processed/lasso_forecasts.rds")
lst <- readRDS("data/processed/lstm_forecasts.rds")
pca <- readRDS("data/processed/pca_arimax_forecasts.rds")

actual <- ph4$y_actual
test_dates <- as.Date(ph4$test_dates)
train_y <- y_all[cpi_dates < min(test_dates)]
mase_denom <- mean(abs(diff(train_y)), na.rm = TRUE)

fc_list <- list(
  "ARIMAX" = ph4$fc_arimax,
  "MIDAS nealmon" = ph4$fc_nealmon,
  "MIDAS nbeta" = ph4$fc_nbeta,
  "U-MIDAS" = ph4$fc_umidas,
  "CLM-SS (4 lags)" = clm$fc_clmss4,
  "CLM-SS (12 lags)" = clm$fc_clmss12,
  "LASSO-MIDAS" = las$fc_lasso,
  "Kernel U-MIDAS" = ker$fc_kernel,
  "XGBoost" = xgb$fc_xgb,
  "LSTM" = lst$fc_lstm,
  "PCA-ARIMAX" = pca$fc_pca_arimax
)

metric_tbl <- do.call(rbind, lapply(names(fc_list), function(model) {
  fc <- fc_list[[model]]
  ok <- is.finite(actual) & is.finite(fc)
  err <- actual[ok] - fc[ok]
  data.frame(
    Model = model,
    N = sum(ok),
    RMSE = round(rmse(err), 6),
    MAE = round(mae(err), 6),
    MASE = round(mae(err) / mase_denom, 3),
    MAPE_pct = round(mape(actual[ok], fc[ok]), 1),
    sMAPE_pct = round(smape(actual[ok], fc[ok]), 1),
    Dir_Acc_pct = dir_acc(fc[ok], actual[ok]),
    stringsAsFactors = FALSE
  )
}))

arimax_rmse <- metric_tbl$RMSE[metric_tbl$Model == "ARIMAX"]
metric_tbl$vs_ARIMAX_RMSE_pct <- round(
  100 * (metric_tbl$RMSE - arimax_rmse) / arimax_rmse, 1
)
metric_tbl <- metric_tbl[order(metric_tbl$RMSE), ]

metric_tbl$MAPE_warning <- "Use cautiously: actual log changes can be near zero"
write.csv(metric_tbl, "output/tables/final_oos_forecast_metrics.csv",
          row.names = FALSE)

md <- c(
  "# Final OOS Forecast Metrics",
  "",
  "Test period: January 2015 to December 2022, 96 one-step-ahead/nowcast forecasts.",
  "",
  sprintf("MASE denominator: mean absolute one-month naive change in the 2000-02 to 2014-12 training period = %.6f.", mase_denom),
  "",
  "MAPE warning: the dependent variable is a monthly log-change, so actual values can be close to zero. Raw MAPE is therefore unstable and should not be the main metric. RMSE, MAE, MASE, sMAPE, and directional accuracy are safer.",
  "",
  "| Rank | Model | RMSE | MAE | MASE | MAPE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |",
  "| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
)

for (i in seq_len(nrow(metric_tbl))) {
  md <- c(md, sprintf(
    "| %d | %s | %.5f | %.5f | %.3f | %.1f%% | %.1f%% | %.1f%% | %+.1f%% |",
    i, metric_tbl$Model[i], metric_tbl$RMSE[i], metric_tbl$MAE[i],
    metric_tbl$MASE[i], metric_tbl$MAPE_pct[i], metric_tbl$sMAPE_pct[i],
    metric_tbl$Dir_Acc_pct[i], metric_tbl$vs_ARIMAX_RMSE_pct[i]
  ))
}

writeLines(md, "output/tables/final_oos_forecast_metrics.md")

summary_lines <- c(
  "Final Evaluation Addendum - AIC/BIC, MASE, MAPE, and PCA Choice",
  "",
  "Forecast-performance dataset:",
  "- Outcome: monthly log-change in US Consumer Energy CPI (CPIENGSL).",
  "- Predictor: weekly log-change in WTI crude oil spot price (DCOILWTICO), converted to exactly 4 weekly observations per CPI month.",
  "- Sample: 2000-02 to 2022-12.",
  "- Rolling forecast test period: 2015-01 to 2022-12, 96 one-step-ahead forecasts.",
  "- Initial training period: 2000-02 to 2014-12; the window expands one month at a time.",
  "",
  "AIC/BIC:",
  "- AIC/BIC are valid for likelihood-based statistical models, not for XGBoost or LSTM.",
  "- Use AIC/BIC as in-sample fit/parsimony evidence, not as the main forecast-performance result.",
  "- The main forecast claim should still be based on OOS rolling metrics.",
  "",
  "MAPE:",
  "- Raw MAPE is reported because it was requested, but it should not be emphasized.",
  "- The dependent variable is a log-change that often lies near zero, so dividing by the actual value can make MAPE unstable.",
  "- MASE and sMAPE are more defensible scale-free metrics here.",
  "",
  "PCA choice:",
  "- The scree table shows 11 PCs are needed to explain 95.3% of the 12 weekly WTI lag variance.",
  "- For the diagnostic PCA-ARIMAX benchmark, using 4 PCs is appropriate because it tests whether a low-dimensional compression can compete with MIDAS.",
  "- It cannot: PCA-ARIMAX RMSE is 0.02859, only -4.3% vs ARIMAX, far worse than MIDAS nbeta at 0.02057.",
  "- Therefore we should not use 11 PCs as the main PCA benchmark; 11 PCs nearly reconstruct the original 12 lags and defeats the purpose of PCA compression."
)

writeLines(summary_lines, "output/tables/final_evaluation_addendum.txt")

cat("\n=== Final evaluation complete ===\n")
cat("Tables:\n")
cat("  output/tables/final_insample_aic_bic.csv\n")
cat("  output/tables/final_oos_forecast_metrics.csv\n")
cat("  output/tables/final_oos_forecast_metrics.md\n")
cat("  output/tables/final_evaluation_addendum.txt\n")
