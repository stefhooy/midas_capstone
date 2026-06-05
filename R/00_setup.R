# ============================================================
# 00_setup.R — Install all required packages
# Run this once before anything else
# ============================================================

# Stable CRAN settings for Windows/VSCode setups.
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (.Platform$OS.type == "windows") {
  options(download.file.method = "wininet")
}

packages <- c(

  # --- Core MIDAS -------------------------------------------
  "midasr",       # midas_r(), midas_u(), forecast.midas_r(), plot_midas_coef()

  # --- Time series modelling --------------------------------
  "forecast",     # auto.arima(), Acf(), Pacf(), dm.test(), accuracy()
  "tseries",      # adf.test(), kpss.test()
  "urca",         # ur.df(), unit root tests
  "lmtest",       # coeftest(), hypothesis tests
  "sandwich",     # HAC standard errors

  # --- State-space (CLM-SS, Phase 5) -----------------------
  "KFAS",         # Kalman filter / state-space models
  "dlm",          # Alternative state-space (Dynamic Linear Models)

  # --- Data download & time series objects -----------------
  "quantmod",     # getSymbols(), FRED API
  "xts",          # Extensible time series objects
  "zoo",          # Irregular time series, as.yearmon(), mlsd()

  # --- Data wrangling & reshaping --------------------------
  "dplyr",        # Data manipulation (filter, mutate, summarise)
  "tidyr",        # Data reshaping (pivot_wider, pivot_longer)

  # --- Regularisation / LASSO (Phase 7) --------------------
  "glmnet",       # LASSO and ridge regression

  # --- Parallel computing (Phase 6 simulation) -------------
  "foreach",      # Parallel for-loops
  "doParallel",   # Parallel backend for foreach
  "xgboost",      # XGBoost

  # --- Deep learning benchmarks (Phase 6b) ------------------
  "torch",        # LSTM benchmark in R
  "keras3",       # R interface to Keras 3 (installed for completeness)
  "tensorflow",   # TensorFlow interface (installed for completeness)

  # --- VSCode graphics -------------------------------------
  "httpgd"        # HTTP graphics device for VSCode plots panel
)

cat("Checking installed packages...\n")
to_install <- packages[!packages %in% installed.packages()[, "Package"]]

if (length(to_install) > 0) {
  cat("Installing:", paste(to_install, collapse = ", "), "\n")
  install.packages(to_install, dependencies = TRUE)
} else {
  cat("All packages already installed.\n")
}

# torch is a two-step install: the R package plus the LibTorch backend.
# This backend is required for the Phase 6b LSTM benchmark.
if ("torch" %in% packages) {
  cat("\nChecking torch backend...\n")
  torch_ready <- tryCatch({
    requireNamespace("torch", quietly = TRUE) &&
      isTRUE(torch::torch_is_installed())
  }, error = function(e) FALSE)

  if (!torch_ready) {
    cat("Installing torch backend. This can take several minutes on first setup...\n")
    torch::install_torch()
  } else {
    cat("Torch backend already installed.\n")
  }
}

# Verify all load correctly
cat("\nLoading packages...\n")
failed <- c()
for (pkg in packages) {
  ok <- tryCatch({
    library(pkg, character.only = TRUE, quietly = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) failed <- c(failed, pkg)
}

if (length(failed) > 0) {
  warning("Failed to load: ", paste(failed, collapse = ", "),
          "\nTry: install.packages(c('", paste(failed, collapse = "','"), "'))")
} else {
  message("Setup complete — all ", length(packages), " packages loaded successfully.")
}
