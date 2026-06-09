# ============================================================
# 15_future_scenarios_12_months.R - Phase 7gB:
# 12-Month Appendix Scenario Forecasts
#
# Purpose:
#   1. Evaluate the model family on genuinely later data:
#      January 2023 through the latest observed CPI month.
#   2. Produce a richer 12-month appendix scenario set beyond the latest
#      observed CPI using multiple oil-price assumptions.
#
# Important distinction:
#   - Historical pseudo-OOS: 2015-2022, already completed.
#   - External holdout: actual post-2022 CPI values, not used in earlier
#     model selection or historical performance claims.
#   - True future forecast: months beyond observed CPI values. These require
#     WTI assumptions/scenarios because future oil prices are unknown.
#
# Evaluation design:
#   External holdout forecasts are one-step-ahead with an expanding window.
#   The first post-2022 forecast trains on 2000-2022 only. For later months,
#   the window expands using CPI observations that would already have been
#   released before the forecast month.
# ============================================================

library(midasr)
library(forecast)
library(xts)
library(zoo)

setwd("c:/Users/steve/OneDrive - IE University/Term 3/Research Capstone/midas_capstone")

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)

set.seed(42)

original_end <- as.Date("2022-12-31")
future_h <- 12L
future_start_override <- as.yearmon("2026-07")

cat("=== Phase 7gB: 12-Month Appendix Scenario Forecasts ===\n\n")

# ============================================================
# Helpers
# ============================================================

rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
mae <- function(e) mean(abs(e), na.rm = TRUE)

dir_acc <- function(fc, actual) {
  ok <- is.finite(fc) & is.finite(actual)
  if (!any(ok)) return(NA_real_)
  round(mean(sign(fc[ok]) == sign(actual[ok])) * 100, 1)
}

mape <- function(actual, fc) {
  ok <- is.finite(actual) & is.finite(fc) & actual != 0
  if (!any(ok)) return(NA_real_)
  mean(abs((actual[ok] - fc[ok]) / actual[ok])) * 100
}

smape <- function(actual, fc) {
  ok <- is.finite(actual) & is.finite(fc) & (abs(actual) + abs(fc)) > 0
  if (!any(ok)) return(NA_real_)
  mean(2 * abs(fc[ok] - actual[ok]) / (abs(actual[ok]) + abs(fc[ok]))) * 100
}

safe_dm_p <- function(e_model, e_base) {
  ok <- is.finite(e_model) & is.finite(e_base)
  if (sum(ok) < 10L) return(NA_real_)
  out <- tryCatch(
    dm.test(e_model[ok], e_base[ok], alternative = "less", h = 1L, power = 2),
    error = function(e) NULL
  )
  if (is.null(out)) return(NA_real_)
  as.numeric(out$p.value)
}

build_ext_x <- function(X_mat, n_months_back = 2L) {
  n <- nrow(X_mat)
  n_col <- 4L * (n_months_back + 1L)
  X_ext <- matrix(NA_real_, nrow = n, ncol = n_col)
  for (i in seq_len(n)) {
    if (i > n_months_back) {
      lag_rows <- seq(i, i - n_months_back)
      X_ext[i, ] <- as.numeric(t(X_mat[lag_rows, , drop = FALSE]))
    }
  }
  colnames(X_ext) <- c(
    paste0("wti_m0_w", 1:4),
    paste0("wti_m1_w", 1:4),
    paste0("wti_m2_w", 1:4)
  )
  X_ext
}

build_ml_x <- function(X12, y) {
  y_lag1 <- c(NA_real_, y[-length(y)])
  y_lag2 <- c(rep(NA_real_, 2L), y[seq_len(length(y) - 2L)])
  X_ml <- cbind(X12, cpi_lag1 = y_lag1, cpi_lag2 = y_lag2)
  X_ml
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

fit_clmss12 <- function(y, X, lambda = 0.1, init = NULL, maxit = 500L) {
  ok <- is.finite(y) & complete.cases(X)
  y <- y[ok]
  X <- X[ok, , drop = FALSE]
  if (length(y) < 40L) return(NULL)
  if (is.null(init)) {
    init <- c(mean(y), rep(0, ncol(X)), 0, log(sd(y)))
  }
  tryCatch(
    optim(init, clmss_ll_gen, y = y, X = X, lambda = lambda,
          method = "BFGS",
          control = list(maxit = maxit, reltol = 1e-8)),
    error = function(e) NULL
  )
}

predict_clmss12_one <- function(opt, y_tr, X_tr, x_te) {
  if (is.null(opt)) return(NA_real_)
  p <- ncol(X_tr)
  mu <- opt$par[1]
  w <- opt$par[2:(p + 1)]
  phi <- tanh(opt$par[p + 2])
  ok <- is.finite(y_tr) & complete.cases(X_tr)
  y_ok <- y_tr[ok]
  X_ok <- X_tr[ok, , drop = FALSE]
  d_tr <- mu + as.numeric(X_ok %*% w)
  u_T <- tail(y_ok - d_tr, 1L)
  as.numeric(mu + sum(w * x_te) + phi * u_T)
}

render_png <- function(file, width = 10, height = 5, expr) {
  png(file, width = width, height = height, units = "in", res = 300)
  on.exit(dev.off(), add = TRUE)
  force(expr)
}

# ============================================================
# STEP 1 - Load refreshed data
# ============================================================

if (!file.exists("data/processed/recent_midas_design_full.rds")) {
  stop("Missing recent_midas_design_full.rds. Run R/13_update_recent_data.R first.")
}

recent <- readRDS("data/processed/recent_midas_design_full.rds")
wti_wk_recent <- readRDS("data/processed/recent_wti_log_diff_weekly.rds")

y_all <- as.numeric(recent$y_all)
dates <- as.Date(recent$dates)
X4 <- recent$x_mat
X12 <- build_ext_x(X4)
x_monthly <- rowMeans(X4, na.rm = TRUE)
X_ml <- build_ml_x(X12, y_all)
x_all <- as.vector(t(X4))

train_original <- which(dates <= original_end)
post_idx <- which(dates > original_end & complete.cases(X4) & is.finite(y_all))

if (!length(post_idx)) {
  stop("No post-2022 holdout rows found. Run R/13_update_recent_data.R again.")
}

cat("Loaded refreshed design:\n")
cat("  Full monthly log-diff rows:", length(y_all), "\n")
cat("  Original training end:     ", format(max(dates[train_original])), "\n")
cat("  External holdout:          ", format(min(dates[post_idx]), "%Y-%m"),
    "to", format(max(dates[post_idx]), "%Y-%m"),
    "| n =", length(post_idx), "\n\n")

# ============================================================
# STEP 2 - Select tuning choices using only original sample
# ============================================================

cat("Selecting tuning choices using original 2000-2022 sample only...\n")

# Parametric MIDAS lag depth, matching Phase 4 logic.
lag_candidates <- c(3L, 7L, 11L)
lag_tbl <- do.call(rbind, lapply(lag_candidates, function(k) {
  fit <- tryCatch(
    midas_r(y_all[train_original] ~ fmls(x_all[seq_len(max(train_original) * 4L)],
                                         k, 4, nealmon),
            start = list(x_all = c(0, 0, 0))),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  data.frame(k = k, weeks = k + 1L, AIC = AIC(fit), BIC = BIC(fit))
}))

best_k <- if (!is.null(lag_tbl)) lag_tbl$k[which.min(lag_tbl$AIC)] else 7L
cat(sprintf("  MIDAS selected k = %d (%d weekly lags)\n", best_k, best_k + 1L))

# LASSO lambda selection, fixed before external holdout.
has_glmnet <- requireNamespace("glmnet", quietly = TRUE)
best_lambda_lasso <- NA_real_
if (has_glmnet) {
  tune_rows <- which(dates <= as.Date("2012-12-31") & complete.cases(X12))
  val_rows <- which(dates > as.Date("2012-12-31") &
                      dates <= as.Date("2014-12-31") &
                      complete.cases(X12))
  path_fit <- glmnet::glmnet(X12[tune_rows, , drop = FALSE], y_all[tune_rows],
                             alpha = 1, standardize = TRUE)
  val_preds <- predict(path_fit, newx = X12[val_rows, , drop = FALSE])
  val_rmse <- apply(val_preds, 2, function(p) rmse(y_all[val_rows] - p))
  best_lambda_lasso <- path_fit$lambda[which.min(val_rmse)]
  cat(sprintf("  LASSO lambda = %.6f\n", best_lambda_lasso))
} else {
  cat("  glmnet not installed: LASSO-MIDAS will be skipped.\n")
}

# XGBoost tuning, fixed before external holdout.
has_xgboost <- requireNamespace("xgboost", quietly = TRUE)
best_xgb <- NULL
if (has_xgboost) {
  tune_rows <- which(dates <= as.Date("2012-12-31") & complete.cases(X_ml))
  val_rows <- which(dates > as.Date("2012-12-31") &
                      dates <= as.Date("2014-12-31") &
                      complete.cases(X_ml))
  param_grid <- expand.grid(
    max_depth = c(2L, 3L, 4L),
    eta = c(0.03, 0.05, 0.10),
    nrounds = c(50L, 100L, 150L)
  )
  xgb_rows <- lapply(seq_len(nrow(param_grid)), function(j) {
    params <- list(
      objective = "reg:squarederror",
      max_depth = param_grid$max_depth[j],
      eta = param_grid$eta[j],
      subsample = 0.9,
      colsample_bytree = 0.9,
      min_child_weight = 1
    )
    fit <- xgboost::xgb.train(
      params = params,
      data = xgboost::xgb.DMatrix(X_ml[tune_rows, , drop = FALSE],
                                  label = y_all[tune_rows]),
      nrounds = param_grid$nrounds[j],
      verbose = 0
    )
    pred <- predict(fit, xgboost::xgb.DMatrix(X_ml[val_rows, , drop = FALSE]))
    data.frame(param_grid[j, ], Val_RMSE = rmse(y_all[val_rows] - pred))
  })
  xgb_grid <- do.call(rbind, xgb_rows)
  best_xgb <- xgb_grid[which.min(xgb_grid$Val_RMSE), ]
  cat(sprintf("  XGBoost max_depth=%d eta=%.2f nrounds=%d\n",
              best_xgb$max_depth, best_xgb$eta, best_xgb$nrounds))
} else {
  cat("  xgboost not installed: XGBoost will be skipped.\n")
}

# LSTM tuning, fixed before external holdout.
has_torch <- requireNamespace("torch", quietly = TRUE)
best_lstm <- NULL

if (has_torch) {
  suppressPackageStartupMessages(library(torch))
  torch_manual_seed(42)

  lstm_regressor <- nn_module(
    "lstm_regressor",
    initialize = function(input_size = 1, hidden_size = 8) {
      self$lstm <- nn_lstm(input_size = input_size, hidden_size = hidden_size,
                           batch_first = TRUE)
      self$fc <- nn_linear(hidden_size, 1)
    },
    forward = function(x) {
      out <- self$lstm(x)
      last_hidden <- out[[1]][, dim(out[[1]])[2], ]
      self$fc(last_hidden)
    }
  )

  fit_lstm_model <- function(X, y, hidden_size = 8L, epochs = 100L,
                             lr = 0.005, seed = 42L) {
    ok <- is.finite(y) & complete.cases(X)
    X <- X[ok, , drop = FALSE]
    y <- y[ok]
    if (nrow(X) < 40L) return(NULL)

    torch_manual_seed(seed)
    x_center <- colMeans(X, na.rm = TRUE)
    x_scale <- apply(X, 2, sd, na.rm = TRUE)
    x_scale[x_scale == 0 | !is.finite(x_scale)] <- 1
    y_center <- mean(y)
    y_scale <- sd(y)
    if (!is.finite(y_scale) || y_scale == 0) y_scale <- 1

    Xs <- scale(X, center = x_center, scale = x_scale)
    ys <- as.numeric((y - y_center) / y_scale)

    x_tensor <- torch_tensor(array(as.numeric(Xs),
                                  dim = c(nrow(Xs), ncol(Xs), 1)),
                             dtype = torch_float())
    y_tensor <- torch_tensor(matrix(ys, ncol = 1), dtype = torch_float())

    model <- lstm_regressor(input_size = 1, hidden_size = hidden_size)
    optimizer <- optim_adam(model$parameters, lr = lr)
    loss_fn <- nn_mse_loss()

    for (epoch in seq_len(epochs)) {
      optimizer$zero_grad()
      pred <- model(x_tensor)
      loss <- loss_fn(pred, y_tensor)
      loss$backward()
      optimizer$step()
    }

    list(model = model, x_center = x_center, x_scale = x_scale,
         y_center = y_center, y_scale = y_scale,
         hidden_size = hidden_size, epochs = epochs, lr = lr)
  }

  predict_lstm_model <- function(fit, X_new) {
    if (is.null(fit)) return(rep(NA_real_, nrow(as.matrix(X_new))))
    X_new <- as.matrix(X_new)
    Xs <- scale(X_new, center = fit$x_center, scale = fit$x_scale)
    x_tensor <- torch_tensor(array(as.numeric(Xs),
                                  dim = c(nrow(Xs), ncol(Xs), 1)),
                             dtype = torch_float())
    as.numeric(fit$model(x_tensor)) * fit$y_scale + fit$y_center
  }

  tune_rows <- which(dates <= as.Date("2012-12-31") & complete.cases(X12))
  val_rows <- which(dates > as.Date("2012-12-31") &
                      dates <= as.Date("2014-12-31") &
                      complete.cases(X12))
  lstm_grid <- expand.grid(
    hidden_size = c(4L, 8L),
    epochs = c(100L, 150L),
    lr = c(0.005, 0.010)
  )
  lstm_rows <- lapply(seq_len(nrow(lstm_grid)), function(j) {
    fit <- fit_lstm_model(
      X12[tune_rows, , drop = FALSE],
      y_all[tune_rows],
      hidden_size = lstm_grid$hidden_size[j],
      epochs = lstm_grid$epochs[j],
      lr = lstm_grid$lr[j],
      seed = 42L + j
    )
    pred <- predict_lstm_model(fit, X12[val_rows, , drop = FALSE])
    data.frame(lstm_grid[j, ], Val_RMSE = rmse(y_all[val_rows] - pred))
  })
  lstm_tuning_grid <- do.call(rbind, lstm_rows)
  best_lstm <- lstm_tuning_grid[which.min(lstm_tuning_grid$Val_RMSE), ]
  cat(sprintf("  LSTM hidden_size=%d epochs=%d lr=%.3f\n",
              best_lstm$hidden_size, best_lstm$epochs, best_lstm$lr))
} else {
  cat("  torch not installed: LSTM will be skipped.\n")
}

# CLM-SS ridge lambda is kept aligned with Phase 5/7 diagnostics.
clm_lambda <- 0.1
cat(sprintf("  CLM-SS ridge lambda = %.3f\n\n", clm_lambda))

# ============================================================
# STEP 3 - External holdout forecasts, post-2022
# ============================================================

cat("Running post-2022 external holdout forecasts...\n")

n_test <- length(post_idx)
fc <- list(
  ARIMAX = rep(NA_real_, n_test),
  `MIDAS nealmon` = rep(NA_real_, n_test),
  `MIDAS nbeta` = rep(NA_real_, n_test),
  `U-MIDAS` = rep(NA_real_, n_test),
  `LASSO-MIDAS` = rep(NA_real_, n_test),
  XGBoost = rep(NA_real_, n_test),
  LSTM = rep(NA_real_, n_test),
  `CLM-SS (12 lags)` = rep(NA_real_, n_test)
)

clm_init <- NULL
t0 <- proc.time()

for (ii in seq_along(post_idx)) {
  te_i <- post_idx[ii]
  end_i <- te_i - 1L

  y_tr <- y_all[seq_len(end_i)]
  x_tr <- as.vector(t(X4[seq_len(end_i), , drop = FALSE]))
  xm_tr <- x_monthly[seq_len(end_i)]
  x_te4 <- X4[te_i, ]
  xm_te <- x_monthly[te_i]

  # ARIMAX
  fit_ar <- tryCatch(
    auto.arima(y_tr, xreg = matrix(xm_tr, ncol = 1), ic = "aic",
               stepwise = TRUE, approximation = TRUE),
    error = function(e) NULL
  )
  if (!is.null(fit_ar)) {
    fc$ARIMAX[ii] <- tryCatch(
      as.numeric(forecast(fit_ar, h = 1L,
                          xreg = matrix(xm_te, nrow = 1))$mean),
      error = function(e) NA_real_
    )
  }

  # Parametric MIDAS nealmon
  fit_ne <- tryCatch(
    midas_r(y_tr ~ fmls(x_tr, best_k, 4, nealmon),
            start = list(x_tr = c(0, 0, 0))),
    error = function(e) NULL
  )
  if (!is.null(fit_ne)) {
    fc$`MIDAS nealmon`[ii] <- tryCatch(
      as.numeric(forecast(fit_ne, newdata = list(x_tr = x_te4), h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  # Parametric MIDAS nbeta
  fit_nb <- tryCatch(
    midas_r(y_tr ~ fmls(x_tr, best_k, 4, nbeta),
            start = list(x_tr = c(1, 1, 5))),
    error = function(e) NULL
  )
  if (!is.null(fit_nb)) {
    fc$`MIDAS nbeta`[ii] <- tryCatch(
      as.numeric(forecast(fit_nb, newdata = list(x_tr = x_te4), h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  # U-MIDAS
  fit_um <- tryCatch(
    midas_u(y_tr ~ fmls(x_tr, best_k, 4)),
    error = function(e) NULL
  )
  if (!is.null(fit_um)) {
    fc$`U-MIDAS`[ii] <- tryCatch(
      as.numeric(forecast(fit_um, newdata = list(x_tr = x_te4), h = 1L)$mean),
      error = function(e) NA_real_
    )
  }

  # LASSO-MIDAS on 12 weekly lags
  if (has_glmnet && complete.cases(matrix(X12[te_i, ], nrow = 1L))) {
    tr_l <- which(seq_len(end_i) <= end_i & complete.cases(X12[seq_len(end_i), ]))
    fit_l <- tryCatch(
      glmnet::glmnet(X12[tr_l, , drop = FALSE], y_all[tr_l],
                     alpha = 1, lambda = best_lambda_lasso,
                     standardize = TRUE),
      error = function(e) NULL
    )
    if (!is.null(fit_l)) {
      fc$`LASSO-MIDAS`[ii] <- as.numeric(
        predict(fit_l, newx = matrix(X12[te_i, ], nrow = 1L),
                s = best_lambda_lasso)
      )
    }
  }

  # XGBoost on 12 weekly lags + CPI lags
  if (has_xgboost && complete.cases(matrix(X_ml[te_i, ], nrow = 1L))) {
    tr_x <- which(seq_len(end_i) <= end_i & complete.cases(X_ml[seq_len(end_i), ]))
    params <- list(
      objective = "reg:squarederror",
      max_depth = best_xgb$max_depth,
      eta = best_xgb$eta,
      subsample = 0.9,
      colsample_bytree = 0.9,
      min_child_weight = 1
    )
    fit_x <- tryCatch(
      xgboost::xgb.train(
        params = params,
        data = xgboost::xgb.DMatrix(X_ml[tr_x, , drop = FALSE],
                                    label = y_all[tr_x]),
        nrounds = best_xgb$nrounds,
        verbose = 0
      ),
      error = function(e) NULL
    )
    if (!is.null(fit_x)) {
      fc$XGBoost[ii] <- predict(
        fit_x,
        xgboost::xgb.DMatrix(matrix(X_ml[te_i, ], nrow = 1L))
      )
    }
  }

  # LSTM on the 12 weekly WTI lag sequence.
  if (has_torch && complete.cases(matrix(X12[te_i, ], nrow = 1L))) {
    tr_lt <- which(seq_len(end_i) <= end_i & complete.cases(X12[seq_len(end_i), ]))
    fit_lt <- tryCatch(
      fit_lstm_model(
        X12[tr_lt, , drop = FALSE],
        y_all[tr_lt],
        hidden_size = best_lstm$hidden_size,
        epochs = best_lstm$epochs,
        lr = best_lstm$lr,
        seed = 1000L + ii
      ),
      error = function(e) NULL
    )
    if (!is.null(fit_lt)) {
      fc$LSTM[ii] <- predict_lstm_model(
        fit_lt,
        matrix(X12[te_i, ], nrow = 1L)
      )
    }
  }

  # CLM-SS 12-lag ridge
  if (complete.cases(matrix(X12[te_i, ], nrow = 1L))) {
    tr_c <- seq_len(end_i)
    opt_c <- fit_clmss12(y_all[tr_c], X12[tr_c, , drop = FALSE],
                         lambda = clm_lambda, init = clm_init, maxit = 500L)
    if (!is.null(opt_c)) {
      fc$`CLM-SS (12 lags)`[ii] <- predict_clmss12_one(
        opt_c,
        y_all[tr_c],
        X12[tr_c, , drop = FALSE],
        X12[te_i, ]
      )
      clm_init <- opt_c$par
    }
  }

  if (ii %% 6L == 0L || ii == 1L || ii == n_test) {
    cat(sprintf("  [%2d/%d] %s complete\n",
                ii, n_test, format(dates[te_i], "%Y-%m")))
  }
}

elapsed <- round((proc.time() - t0)["elapsed"], 1)
cat("External holdout complete in", elapsed, "seconds.\n\n")

y_test <- y_all[post_idx]
test_dates <- dates[post_idx]

forecast_tbl <- data.frame(
  Date = format(test_dates, "%Y-%m"),
  Actual = round(y_test, 6),
  stringsAsFactors = FALSE
)
for (nm in names(fc)) forecast_tbl[[nm]] <- round(fc[[nm]], 6)

write.csv(forecast_tbl, "output/tables/post2022_external_holdout_forecasts.csv",
          row.names = FALSE)

train_y_original <- y_all[train_original]
mase_denom <- mean(abs(diff(train_y_original)), na.rm = TRUE)
e_arimax <- y_test - fc$ARIMAX

metric_tbl <- do.call(rbind, lapply(names(fc), function(nm) {
  pred <- fc[[nm]]
  ok <- is.finite(pred) & is.finite(y_test)
  err <- y_test[ok] - pred[ok]
  data.frame(
    Model = nm,
    N = sum(ok),
    RMSE = round(rmse(err), 6),
    MAE = round(mae(err), 6),
    MASE = round(mae(err) / mase_denom, 3),
    MAPE_pct = round(mape(y_test[ok], pred[ok]), 1),
    sMAPE_pct = round(smape(y_test[ok], pred[ok]), 1),
    Dir_Acc_pct = dir_acc(pred[ok], y_test[ok]),
    DM_p_vs_ARIMAX = round(safe_dm_p(err, e_arimax[ok]), 4),
    stringsAsFactors = FALSE
  )
}))

arimax_rmse <- metric_tbl$RMSE[metric_tbl$Model == "ARIMAX"]
metric_tbl$vs_ARIMAX_RMSE_pct <- round(
  100 * (metric_tbl$RMSE - arimax_rmse) / arimax_rmse, 1
)
metric_tbl <- metric_tbl[order(metric_tbl$RMSE), ]
metric_tbl$MAPE_warning <- "Use cautiously: actual log changes can be near zero"

write.csv(metric_tbl, "output/tables/post2022_external_holdout_metrics.csv",
          row.names = FALSE)

md <- c(
  "# Post-2022 External Holdout Metrics",
  "",
  sprintf("Forecast period: %s to %s, %d one-step-ahead forecasts.",
          format(min(test_dates), "%Y-%m"), format(max(test_dates), "%Y-%m"),
          length(test_dates)),
  "",
  "Design: the first forecast trains through December 2022. Later forecasts expand the window using only CPI observations already available before the forecast month.",
  "",
  "| Rank | Model | RMSE | MAE | MASE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |",
  "| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
)
for (i in seq_len(nrow(metric_tbl))) {
  md <- c(md, sprintf(
    "| %d | %s | %.5f | %.5f | %.3f | %.1f%% | %.1f%% | %+.1f%% |",
    i, metric_tbl$Model[i], metric_tbl$RMSE[i], metric_tbl$MAE[i],
    metric_tbl$MASE[i], metric_tbl$sMAPE_pct[i],
    metric_tbl$Dir_Acc_pct[i], metric_tbl$vs_ARIMAX_RMSE_pct[i]
  ))
}
writeLines(md, "output/tables/post2022_external_holdout_metrics.md")

saveRDS(
  list(
    forecasts = fc,
    y_actual = y_test,
    test_dates = test_dates,
    metrics = metric_tbl,
    best_k = best_k,
    lasso_lambda = best_lambda_lasso,
    xgb_params = best_xgb,
    lstm_params = best_lstm,
    clm_lambda = clm_lambda
  ),
  "data/processed/post2022_external_forecasts.rds"
)

# ============================================================
# STEP 3b - Updated OOS metrics, 2015 through latest CPI month
# ============================================================

cat("Building updated 2015-latest combined OOS metrics...\n")

combined_sources <- list(
  phase4 = "data/processed/phase4_forecasts.rds",
  clmss = "data/processed/clmss_forecasts.rds",
  xgb = "data/processed/xgb_forecasts.rds",
  lasso = "data/processed/lasso_forecasts.rds",
  lstm = "data/processed/lstm_forecasts.rds"
)

if (all(file.exists(unlist(combined_sources)))) {
  hist_phase4 <- readRDS(combined_sources$phase4)
  hist_clmss <- readRDS(combined_sources$clmss)
  hist_xgb <- readRDS(combined_sources$xgb)
  hist_lasso <- readRDS(combined_sources$lasso)
  hist_lstm <- readRDS(combined_sources$lstm)

  combined_actual <- c(hist_phase4$y_actual, y_test)
  combined_dates <- c(hist_phase4$test_dates, test_dates)
  combined_fc <- list(
    ARIMAX = c(hist_phase4$fc_arimax, fc$ARIMAX),
    `MIDAS nealmon` = c(hist_phase4$fc_nealmon, fc$`MIDAS nealmon`),
    `MIDAS nbeta` = c(hist_phase4$fc_nbeta, fc$`MIDAS nbeta`),
    `U-MIDAS` = c(hist_phase4$fc_umidas, fc$`U-MIDAS`),
    `LASSO-MIDAS` = c(hist_lasso$fc_lasso, fc$`LASSO-MIDAS`),
    XGBoost = c(hist_xgb$fc_xgb, fc$XGBoost),
    LSTM = c(hist_lstm$fc_lstm, fc$LSTM),
    `CLM-SS (12 lags)` = c(hist_clmss$fc_clmss12, fc$`CLM-SS (12 lags)`)
  )

  combined_baseline_err <- combined_actual - combined_fc$ARIMAX
  combined_metric_tbl <- do.call(rbind, lapply(names(combined_fc), function(nm) {
    pred <- combined_fc[[nm]]
    ok <- is.finite(pred) & is.finite(combined_actual)
    err <- combined_actual[ok] - pred[ok]
    data.frame(
      Model = nm,
      N = sum(ok),
      RMSE = round(rmse(err), 6),
      MAE = round(mae(err), 6),
      MASE = round(mae(err) / mase_denom, 3),
      MAPE_pct = round(mape(combined_actual[ok], pred[ok]), 1),
      sMAPE_pct = round(smape(combined_actual[ok], pred[ok]), 1),
      Dir_Acc_pct = dir_acc(pred[ok], combined_actual[ok]),
      DM_p_vs_ARIMAX = round(safe_dm_p(err, combined_baseline_err[ok]), 4),
      stringsAsFactors = FALSE
    )
  }))

  combined_arimax_rmse <- combined_metric_tbl$RMSE[
    combined_metric_tbl$Model == "ARIMAX"
  ]
  combined_metric_tbl$vs_ARIMAX_RMSE_pct <- round(
    100 * (combined_metric_tbl$RMSE - combined_arimax_rmse) /
      combined_arimax_rmse,
    1
  )
  combined_metric_tbl <- combined_metric_tbl[order(combined_metric_tbl$RMSE), ]
  combined_metric_tbl$MAPE_warning <- "Use cautiously: actual log changes can be near zero"

  write.csv(combined_metric_tbl,
            "output/tables/updated_oos_2015_2026_metrics.csv",
            row.names = FALSE)

  combined_md <- c(
    "# Updated OOS Metrics: 2015 Through Latest CPI Month",
    "",
    sprintf("Forecast period: %s to %s, %d one-step-ahead forecasts.",
            format(min(combined_dates), "%Y-%m"),
            format(max(combined_dates), "%Y-%m"),
            length(combined_dates)),
    "",
    "This table combines the original 2015-2022 pseudo-OOS exercise with the post-2022 external holdout. It should be read as an updated robustness summary, not as a replacement for the original model-development validation.",
    "",
    "| Rank | Model | RMSE | MAE | MASE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |",
    "| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
  )
  for (i in seq_len(nrow(combined_metric_tbl))) {
    combined_md <- c(combined_md, sprintf(
      "| %d | %s | %.5f | %.5f | %.3f | %.1f%% | %.1f%% | %+.1f%% |",
      i, combined_metric_tbl$Model[i], combined_metric_tbl$RMSE[i],
      combined_metric_tbl$MAE[i], combined_metric_tbl$MASE[i],
      combined_metric_tbl$sMAPE_pct[i],
      combined_metric_tbl$Dir_Acc_pct[i],
      combined_metric_tbl$vs_ARIMAX_RMSE_pct[i]
    ))
  }
  writeLines(combined_md, "output/tables/updated_oos_2015_2026_metrics.md")

  combined_forecast_tbl <- data.frame(
    Date = format(combined_dates, "%Y-%m"),
    Actual = round(combined_actual, 6),
    stringsAsFactors = FALSE
  )
  for (nm in names(combined_fc)) {
    combined_forecast_tbl[[nm]] <- round(combined_fc[[nm]], 6)
  }
  write.csv(combined_forecast_tbl,
            "output/tables/updated_oos_2015_2026_forecasts.csv",
            row.names = FALSE)

  saveRDS(
    list(
      forecasts = combined_fc,
      y_actual = combined_actual,
      test_dates = combined_dates,
      metrics = combined_metric_tbl
    ),
    "data/processed/updated_oos_2015_2026_forecasts.rds"
  )

  render_png("output/figures/38_updated_oos_2015_2026_rmse.png",
             width = 10, height = 5.5, {
    par(mar = c(5, 8.5, 4, 2))
    ord <- order(combined_metric_tbl$RMSE, decreasing = TRUE)
    tbl <- combined_metric_tbl[ord, ]
    cols <- ifelse(tbl$Model == "ARIMAX", "tomato",
                   ifelse(grepl("MIDAS|CLM", tbl$Model), "steelblue", "grey65"))
    bp <- barplot(tbl$RMSE, names.arg = tbl$Model, horiz = TRUE, las = 1,
                  col = cols, border = "white",
                  main = "Updated OOS RMSE: 2015 Through Latest CPI Month",
                  xlab = "Root Mean Squared Error",
                  xlim = c(0, max(tbl$RMSE, na.rm = TRUE) * 1.22))
    abline(v = combined_arimax_rmse, col = "tomato", lty = 2, lwd = 1.2)
    text(tbl$RMSE + max(tbl$RMSE, na.rm = TRUE) * 0.015, bp,
         labels = sprintf("%.5f", tbl$RMSE), adj = 0, cex = 0.78)
  })
} else {
  combined_metric_tbl <- NULL
  cat("  Some historical forecast RDS files are missing; combined table skipped.\n")
}

# ============================================================
# STEP 4 - External holdout figures
# ============================================================

top_models <- metric_tbl$Model[seq_len(min(5L, nrow(metric_tbl)))]
plot_models <- unique(c("ARIMAX", top_models))

render_png("output/figures/35_post2022_external_holdout_forecasts.png",
           width = 12, height = 5, {
  ylim <- range(c(y_test, unlist(fc[plot_models])), na.rm = TRUE)
  par(mar = c(4.2, 4.8, 4.2, 1))
  plot(test_dates, y_test, type = "l", lwd = 2.2, col = "black",
       ylim = ylim, xlab = "", ylab = "Monthly log-change in CPI Energy",
       main = "Post-2022 External Holdout Forecasts")
  abline(h = 0, col = "grey60", lty = 2, lwd = 0.8)
  cols <- c("tomato", "steelblue", "forestgreen", "purple", "darkorange",
            "grey35", "dodgerblue4")
  names(cols) <- plot_models
  for (nm in plot_models) {
    lines(test_dates, fc[[nm]], col = cols[nm], lwd = 1.5,
          lty = ifelse(nm == "ARIMAX", 2, 1))
  }
  legend("bottomleft", bty = "n", cex = 0.78,
         col = c("black", cols[plot_models]),
         lwd = c(2.2, rep(1.5, length(plot_models))),
         lty = c(1, ifelse(plot_models == "ARIMAX", 2, 1)),
         legend = c("Actual", plot_models))
})

render_png("output/figures/36_post2022_external_holdout_rmse.png",
           width = 10, height = 5.5, {
  par(mar = c(5, 8.5, 4, 2))
  ord <- order(metric_tbl$RMSE, decreasing = TRUE)
  tbl <- metric_tbl[ord, ]
  cols <- ifelse(tbl$Model == "ARIMAX", "tomato",
                 ifelse(grepl("MIDAS|CLM", tbl$Model), "steelblue", "grey65"))
  bp <- barplot(tbl$RMSE, names.arg = tbl$Model, horiz = TRUE, las = 1,
                col = cols, border = "white",
                main = "Post-2022 External Holdout RMSE",
                xlab = "Root Mean Squared Error",
                xlim = c(0, max(tbl$RMSE, na.rm = TRUE) * 1.22))
  abline(v = arimax_rmse, col = "tomato", lty = 2, lwd = 1.2)
  text(tbl$RMSE + max(tbl$RMSE, na.rm = TRUE) * 0.015, bp,
       labels = sprintf("%.5f", tbl$RMSE), adj = 0, cex = 0.78)
})

# ============================================================
# STEP 5 - 12-month appendix scenario forecasts
# ============================================================

cat("Building 12-month appendix scenario forecasts...\n")

latest_cpi_month <- max(dates)
future_start_month <- max(as.yearmon(latest_cpi_month) + 1 / 12,
                          future_start_override)
future_months <- seq(future_start_month, by = 1 / 12, length.out = future_h)
future_dates <- as.Date(future_months)

recent_vals <- tail(as.numeric(wti_wk_recent), 26L)
recent_idx <- seq_along(recent_vals)
recent_trend_fit <- lm(recent_vals ~ recent_idx)
trend_forecast_weeks <- predict(
  recent_trend_fit,
  newdata = data.frame(recent_idx = max(recent_idx) + seq_len(4L * future_h))
)

fit_wti_arima <- auto.arima(na.omit(as.numeric(wti_wk_recent)),
                            seasonal = FALSE, stepwise = TRUE,
                            approximation = TRUE)
arima_forecast_weeks <- as.numeric(forecast(fit_wti_arima, h = 4L * future_h)$mean)

matrix_from_weeks <- function(weekly_values, horizon_h) {
  matrix(weekly_values[seq_len(4L * horizon_h)], ncol = 4L, byrow = TRUE)
}

scenario_mats <- list(
  `Flat oil prices` = matrix(0, nrow = future_h, ncol = 4L),
  `Recent trend` = matrix_from_weeks(trend_forecast_weeks, future_h),
  `ARIMA WTI forecast` = matrix_from_weeks(arima_forecast_weeks, future_h),
  `High-oil shock` = matrix(0.01, nrow = future_h, ncol = 4L),
  `Low-oil shock` = matrix(-0.01, nrow = future_h, ncol = 4L)
)

colnames_template <- colnames(X4)

fit_ar_full <- auto.arima(y_all, xreg = matrix(x_monthly, ncol = 1),
                          ic = "aic", stepwise = TRUE, approximation = TRUE)
fit_ne_full <- tryCatch(
  midas_r(y_all ~ fmls(x_all, best_k, 4, nealmon),
          start = list(x_all = c(0, 0, 0))),
  error = function(e) NULL
)
fit_nb_full <- tryCatch(
  midas_r(y_all ~ fmls(x_all, best_k, 4, nbeta),
          start = list(x_all = c(1, 1, 5))),
  error = function(e) NULL
)
fit_um_full <- tryCatch(
  midas_u(y_all ~ fmls(x_all, best_k, 4)),
  error = function(e) NULL
)
fit_lasso_full <- if (has_glmnet) {
  ok_l <- which(complete.cases(X12))
  glmnet::glmnet(X12[ok_l, , drop = FALSE], y_all[ok_l],
                 alpha = 1, lambda = best_lambda_lasso,
                 standardize = TRUE)
} else NULL
fit_xgb_full <- if (has_xgboost) {
  ok_x <- which(complete.cases(X_ml))
  params <- list(
    objective = "reg:squarederror",
    max_depth = best_xgb$max_depth,
    eta = best_xgb$eta,
    subsample = 0.9,
    colsample_bytree = 0.9,
    min_child_weight = 1
  )
  xgboost::xgb.train(
    params = params,
    data = xgboost::xgb.DMatrix(X_ml[ok_x, , drop = FALSE], label = y_all[ok_x]),
    nrounds = best_xgb$nrounds,
    verbose = 0
  )
} else NULL
fit_lstm_full <- if (has_torch) {
  ok_lt <- which(complete.cases(X12))
  fit_lstm_model(
    X12[ok_lt, , drop = FALSE],
    y_all[ok_lt],
    hidden_size = best_lstm$hidden_size,
    epochs = best_lstm$epochs,
    lr = best_lstm$lr,
    seed = 5252L
  )
} else NULL
fit_clm_full <- fit_clmss12(y_all, X12, lambda = clm_lambda, init = clm_init,
                            maxit = 1500L)

future_rows <- list()
row_id <- 1L

for (sc_name in names(scenario_mats)) {
  fut_X4 <- scenario_mats[[sc_name]]
  colnames(fut_X4) <- colnames_template

  X4_combined <- rbind(X4, fut_X4)
  X12_combined <- build_ext_x(X4_combined)
  fut_rows <- (nrow(X4) + 1L):nrow(X4_combined)
  fut_X12 <- X12_combined[fut_rows, , drop = FALSE]
  fut_x_monthly <- rowMeans(fut_X4, na.rm = TRUE)
  fut_x_vector <- as.vector(t(fut_X4))

  ar_pred <- tryCatch(
    as.numeric(forecast(fit_ar_full, h = future_h,
                        xreg = matrix(fut_x_monthly, ncol = 1))$mean),
    error = function(e) rep(NA_real_, future_h)
  )

  ne_pred <- tryCatch(
    if (is.null(fit_ne_full)) rep(NA_real_, future_h) else
      as.numeric(forecast(fit_ne_full,
                          newdata = list(x_all = fut_x_vector),
                          h = future_h)$mean),
    error = function(e) rep(NA_real_, future_h)
  )

  nb_pred <- tryCatch(
    if (is.null(fit_nb_full)) rep(NA_real_, future_h) else
      as.numeric(forecast(fit_nb_full,
                          newdata = list(x_all = fut_x_vector),
                          h = future_h)$mean),
    error = function(e) rep(NA_real_, future_h)
  )

  um_pred <- tryCatch(
    if (is.null(fit_um_full)) rep(NA_real_, future_h) else
      as.numeric(forecast(fit_um_full,
                          newdata = list(x_all = fut_x_vector),
                          h = future_h)$mean),
    error = function(e) rep(NA_real_, future_h)
  )

  lasso_pred <- if (!is.null(fit_lasso_full)) {
    as.numeric(predict(fit_lasso_full, newx = fut_X12,
                       s = best_lambda_lasso))
  } else {
    rep(NA_real_, future_h)
  }

  xgb_pred <- rep(NA_real_, future_h)
  if (!is.null(fit_xgb_full)) {
    y_aug <- c(y_all, rep(NA_real_, future_h))
    for (h in seq_len(future_h)) {
      row_i <- nrow(X4) + h
      x_row <- c(
        X12_combined[row_i, ],
        cpi_lag1 = y_aug[row_i - 1L],
        cpi_lag2 = y_aug[row_i - 2L]
      )
      xgb_pred[h] <- predict(
        fit_xgb_full,
        xgboost::xgb.DMatrix(matrix(x_row, nrow = 1L))
      )
      y_aug[row_i] <- xgb_pred[h]
    }
  }

  lstm_pred <- if (!is.null(fit_lstm_full)) {
    predict_lstm_model(fit_lstm_full, fut_X12)
  } else {
    rep(NA_real_, future_h)
  }

  clm_pred <- rep(NA_real_, future_h)
  if (!is.null(fit_clm_full)) {
    p <- ncol(X12)
    mu <- fit_clm_full$par[1]
    w <- fit_clm_full$par[2:(p + 1)]
    phi <- tanh(fit_clm_full$par[p + 2])
    ok_c <- is.finite(y_all) & complete.cases(X12)
    d_hist <- mu + as.numeric(X12[ok_c, , drop = FALSE] %*% w)
    u_state <- tail(y_all[ok_c] - d_hist, 1L)
    for (h in seq_len(future_h)) {
      u_state <- phi * u_state
      clm_pred[h] <- mu + sum(w * fut_X12[h, ]) + u_state
    }
  }

  future_rows[[row_id]] <- data.frame(
    Scenario = sc_name,
    Forecast_month = format(future_dates, "%Y-%m"),
    ARIMAX = ar_pred,
    `MIDAS nealmon` = ne_pred,
    `MIDAS nbeta` = nb_pred,
    `U-MIDAS` = um_pred,
    `LASSO-MIDAS` = lasso_pred,
    XGBoost = xgb_pred,
    LSTM = lstm_pred,
    `CLM-SS (12 lags)` = clm_pred,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  row_id <- row_id + 1L
}

future_tbl <- do.call(rbind, future_rows)
num_cols <- setdiff(names(future_tbl), c("Scenario", "Forecast_month"))
future_tbl[num_cols] <- lapply(future_tbl[num_cols], function(z) round(z, 6))

write.csv(future_tbl, "output/tables/future_forecast_12m_scenarios.csv",
          row.names = FALSE)
saveRDS(future_tbl, "data/processed/future_forecast_12m_scenarios.rds")

future_md <- c(
  "# Twelve-Month Appendix Scenario Forecasts",
  "",
  sprintf("Latest observed CPI log-change month: %s.", format(latest_cpi_month, "%Y-%m")),
  sprintf("Forecast months: %s to %s.",
          format(min(future_dates), "%Y-%m"), format(max(future_dates), "%Y-%m")),
  "",
  "These appendix forecasts extend the horizon to 12 months, so they should be read as scenario-conditioned projections rather than validated short-horizon forecast evidence.",
  "",
  "| Scenario | Month | ARIMAX | MIDAS nbeta | U-MIDAS | LASSO-MIDAS | XGBoost | LSTM | CLM-SS 12 |",
  "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
)
for (i in seq_len(nrow(future_tbl))) {
  future_md <- c(future_md, sprintf(
    "| %s | %s | %.5f | %.5f | %.5f | %.5f | %.5f | %.5f | %.5f |",
    future_tbl$Scenario[i], future_tbl$Forecast_month[i],
    future_tbl$ARIMAX[i], future_tbl$`MIDAS nbeta`[i],
    future_tbl$`U-MIDAS`[i], future_tbl$`LASSO-MIDAS`[i],
    future_tbl$XGBoost[i], future_tbl$LSTM[i],
    future_tbl$`CLM-SS (12 lags)`[i]
  ))
}
writeLines(future_md, "output/tables/future_forecast_12m_scenarios.md")

render_png("output/figures/40_future_forecast_12m_fanchart.png",
           width = 11, height = 5.8, {
  model_to_plot <- "MIDAS nbeta"
  sc_order <- c("Low-oil shock", "Flat oil prices", "Recent trend",
                "ARIMA WTI forecast", "High-oil shock")
  plot_tbl <- future_tbl[future_tbl$Scenario %in% sc_order, , drop = FALSE]
  plot_dates <- as.Date(paste0(unique(plot_tbl$Forecast_month), "-01"))
  low_path <- plot_tbl[plot_tbl$Scenario == "Low-oil shock", model_to_plot]
  high_path <- plot_tbl[plot_tbl$Scenario == "High-oil shock", model_to_plot]
  flat_path <- plot_tbl[plot_tbl$Scenario == "Flat oil prices", model_to_plot]
  trend_path <- plot_tbl[plot_tbl$Scenario == "Recent trend", model_to_plot]
  arima_path <- plot_tbl[plot_tbl$Scenario == "ARIMA WTI forecast", model_to_plot]
  y_range <- range(c(low_path, high_path, flat_path, trend_path, arima_path),
                   na.rm = TRUE)

  par(mar = c(4.6, 4.8, 4.2, 1))
  plot(plot_dates, flat_path, type = "n", ylim = y_range,
       xlab = "", ylab = "Forecast monthly log-change in CPI Energy",
       main = "12-Month Appendix Scenario Fan Chart")
  polygon(c(plot_dates, rev(plot_dates)),
          c(low_path, rev(high_path)),
          col = rgb(0.70, 0.78, 0.92, 0.45), border = NA)
  lines(plot_dates, flat_path, lwd = 2, col = "steelblue")
  lines(plot_dates, trend_path, lwd = 2, col = "grey35")
  lines(plot_dates, arima_path, lwd = 2, col = "darkorange")
  lines(plot_dates, high_path, lwd = 1.6, col = "tomato", lty = 2)
  lines(plot_dates, low_path, lwd = 1.6, col = "forestgreen", lty = 2)
  abline(h = 0, col = "grey60", lty = 2)
  legend("topright", bty = "n", lwd = c(10, 2, 2, 2, 1.6, 1.6),
         col = c(rgb(0.70, 0.78, 0.92, 0.45), "steelblue", "grey35",
                 "darkorange", "tomato", "forestgreen"),
         legend = c("Shock range", "Flat oil prices", "Recent trend",
                    "ARIMA WTI forecast", "High-oil shock", "Low-oil shock"))
  mtext("Displayed model: MIDAS nbeta; full table includes all model families.",
        side = 1, line = 3, cex = 0.8)
})

# ============================================================
# STEP 6 - Console summary
# ============================================================

cat("\n=== Post-2022 external holdout metrics ===\n")
print(metric_tbl, row.names = FALSE)

cat("\n=== Twelve-month appendix scenarios saved ===\n")
cat("Latest observed CPI month:", format(latest_cpi_month, "%Y-%m"), "\n")
cat("Future forecast months:   ", format(min(future_dates), "%Y-%m"),
    "to", format(max(future_dates), "%Y-%m"), "\n\n")

cat("Saved tables:\n")
cat("  output/tables/post2022_external_holdout_forecasts.csv\n")
cat("  output/tables/post2022_external_holdout_metrics.csv\n")
cat("  output/tables/post2022_external_holdout_metrics.md\n")
cat("  output/tables/updated_oos_2015_2026_forecasts.csv\n")
cat("  output/tables/updated_oos_2015_2026_metrics.csv\n")
cat("  output/tables/updated_oos_2015_2026_metrics.md\n")
cat("  output/tables/future_forecast_12m_scenarios.csv\n")
cat("  output/tables/future_forecast_12m_scenarios.md\n")
cat("Saved figures:\n")
cat("  output/figures/35_post2022_external_holdout_forecasts.png\n")
cat("  output/figures/36_post2022_external_holdout_rmse.png\n")
cat("  output/figures/38_updated_oos_2015_2026_rmse.png\n")
cat("  output/figures/40_future_forecast_12m_fanchart.png\n")
cat("Saved data:\n")
cat("  data/processed/post2022_external_forecasts.rds\n")
cat("  data/processed/updated_oos_2015_2026_forecasts.rds\n")
cat("  data/processed/future_forecast_12m_scenarios.rds\n\n")

cat("Appendix use:\n")
cat("  This script is for the 12-month scenario appendix and conclusion/future-\n")
cat("  work discussion, not for the main short-horizon forecast evidence.\n")