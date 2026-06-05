# Final OOS Forecast Metrics

Test period: January 2015 to December 2022, 96 one-step-ahead/nowcast forecasts.

MASE denominator: mean absolute one-month naive change in the 2000-02 to 2014-12 training period = 0.027748.

MAPE warning: the dependent variable is a monthly log-change, so actual values can be close to zero. Raw MAPE is therefore unstable and should not be the main metric. RMSE, MAE, MASE, sMAPE, and directional accuracy are safer.

| Rank | Model | RMSE | MAE | MASE | MAPE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | MIDAS nbeta | 0.02057 | 0.01557 | 0.561 | 135.3% | 99.6% | 74.0% | -31.1% |
| 2 | LASSO-MIDAS | 0.02103 | 0.01603 | 0.578 | 129.7% | 100.0% | 76.0% | -29.6% |
| 3 | MIDAS nealmon | 0.02104 | 0.01566 | 0.564 | 134.1% | 94.4% | 80.2% | -29.5% |
| 4 | U-MIDAS | 0.02226 | 0.01677 | 0.604 | 141.4% | 99.9% | 75.0% | -25.5% |
| 5 | Kernel U-MIDAS | 0.02226 | 0.01677 | 0.604 | 141.4% | 99.9% | 75.0% | -25.5% |
| 6 | CLM-SS (12 lags) | 0.02258 | 0.01670 | 0.602 | 138.2% | 99.9% | 74.0% | -24.4% |
| 7 | XGBoost | 0.02365 | 0.01772 | 0.639 | 140.9% | 108.3% | 72.9% | -20.8% |
| 8 | LSTM | 0.02588 | 0.01840 | 0.663 | 164.6% | 102.3% | 76.0% | -13.3% |
| 9 | PCA-ARIMAX | 0.02859 | 0.02099 | 0.757 | 142.9% | 123.4% | 67.7% | -4.3% |
| 10 | ARIMAX | 0.02986 | 0.02198 | 0.792 | 129.7% | 131.5% | 64.6% | +0.0% |
| 11 | CLM-SS (4 lags) | 0.03170 | 0.02208 | 0.796 | 131.5% | 132.4% | 63.5% | +6.2% |
