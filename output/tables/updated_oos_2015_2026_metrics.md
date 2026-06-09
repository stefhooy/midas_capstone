# Updated OOS Metrics: 2015 Through Latest CPI Month

Forecast period: 2015-01 to 2026-04, 134 one-step-ahead forecasts.

This table combines the original 2015-2022 pseudo-OOS exercise with the post-2022 external holdout. It should be read as an updated robustness summary, not as a replacement for the original model-development validation.

| Rank | Model | RMSE | MAE | MASE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | XGBoost | 0.02105 | 0.01505 | 0.557 | 106.0% | 75.4% | -17.5% |
| 2 | LASSO-MIDAS | 0.02121 | 0.01581 | 0.585 | 108.7% | 74.6% | -16.9% |
| 3 | LSTM | 0.02340 | 0.01676 | 0.620 | 107.7% | 69.4% | -8.3% |
| 4 | U-MIDAS | 0.02455 | 0.01645 | 0.609 | 101.4% | 76.1% | -3.8% |
| 5 | CLM-SS (12 lags) | 0.02522 | 0.01716 | 0.635 | 101.5% | 74.6% | -1.1% |
| 6 | ARIMAX | 0.02551 | 0.01828 | 0.676 | 124.4% | 64.9% | +0.0% |
| 7 | MIDAS nbeta | 0.02612 | 0.01702 | 0.630 | 107.2% | 72.4% | +2.4% |
| 8 | MIDAS nealmon | 0.03035 | 0.01789 | 0.662 | 105.3% | 76.1% | +19.0% |
