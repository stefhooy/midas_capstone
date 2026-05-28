# ============================================================
# 00_setup.R — Install all required packages
# Run this once before anything else
# ============================================================

packages <- c(
  "midasr",     # MIDAS regression (midas_r, midas_u, forecast.midas_r)
  "forecast",   # ARIMA, auto.arima, accuracy()
  "quantmod",   # FRED data download, getSymbols()
  "KFAS",       # Kalman filter / state-space (for CLM-SS)
  "tseries",    # adf.test(), kpss.test()
  "urca",       # ur.df(), unit root tests
  "ggplot2",    # Plotting
  "dplyr",      # Data manipulation
  "tidyr",      # Data reshaping
  "zoo",        # Irregular time series / mlsd()
  "lmtest",     # coeftest(), Diebold-Mariano
  "sandwich"    # HAC standard errors
)

to_install <- packages[!packages %in% installed.packages()[, "Package"]]
if (length(to_install) > 0) {
  install.packages(to_install, dependencies = TRUE)
} else {
  message("All packages already installed.")
}

# Verify
invisible(lapply(packages, library, character.only = TRUE))
message("Setup complete — all packages loaded successfully.")
