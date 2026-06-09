# Post-2022 External Holdout Metrics

Forecast period: 2023-01 to 2026-04, 38 one-step-ahead forecasts.

Design: the first forecast trains through December 2022. Later forecasts expand the window using only CPI observations already available before the forecast month.

| Rank | Model | RMSE | MAE | MASE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | MIDAS nbeta | 0.01622 | 0.01234 | 0.456 | 127.0% | 57.9% | -16.0% |
| 2 | U-MIDAS | 0.01639 | 0.01286 | 0.476 | 114.8% | 71.1% | -15.1% |
| 3 | LASSO-MIDAS | 0.01703 | 0.01295 | 0.479 | 120.2% | 71.1% | -11.9% |
| 4 | MIDAS nealmon | 0.01762 | 0.01272 | 0.470 | 129.8% | 63.2% | -8.8% |
| 5 | CLM-SS (12 lags) | 0.01825 | 0.01377 | 0.509 | 109.7% | 71.1% | -5.5% |
| 6 | LSTM | 0.01860 | 0.01310 | 0.484 | 118.3% | 63.2% | -3.7% |
| 7 | XGBoost | 0.01929 | 0.01369 | 0.506 | 119.8% | 65.8% | -0.1% |
| 8 | ARIMAX | 0.01932 | 0.01247 | 0.461 | 122.9% | 65.8% | +0.0% |
