# Final OOS Forecast Metrics

Test period: January 2015 to December 2022, 96 one-step-ahead/nowcast forecasts.

MASE denominator: mean absolute one-month naive change in the 2000-02 to 2014-12 training period = 0.027748.

MAPE warning: the dependent variable is a monthly log-change, so actual values can be close to zero. Raw MAPE is therefore unstable and should not be the main metric. RMSE, MAE, MASE, sMAPE, and directional accuracy are safer.

| Rank | Model | RMSE | MAE | MASE | MAPE | sMAPE | Dir. Acc. | vs ARIMAX RMSE |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | XGBoost | 0.02170 | 0.01559 | 0.562 | 117.3% | 100.6% | 79.2% | -21.3% |
| 2 | LASSO-MIDAS | 0.02265 | 0.01694 | 0.610 | 125.7% | 104.1% | 76.0% | -17.9% |
| 3 | LSTM | 0.02505 | 0.01821 | 0.656 | 158.9% | 103.5% | 71.9% | -9.2% |
| 4 | PCA-ARIMAX | 0.02663 | 0.01901 | 0.685 | 127.3% | 103.9% | 77.1% | -3.4% |
| 5 | Kernel U-MIDAS | 0.02705 | 0.01836 | 0.662 | 149.2% | 99.9% | 77.1% | -1.9% |
| 6 | U-MIDAS | 0.02711 | 0.01787 | 0.644 | 138.1% | 96.1% | 78.1% | -1.7% |
| 7 | CLM-SS (12 lags) | 0.02750 | 0.01850 | 0.667 | 145.3% | 98.2% | 76.0% | -0.3% |
| 8 | ARIMAX | 0.02758 | 0.02058 | 0.742 | 125.1% | 125.0% | 64.6% | +0.0% |
| 9 | MIDAS nbeta | 0.02913 | 0.01888 | 0.680 | 147.1% | 99.4% | 78.1% | +5.6% |
| 10 | CLM-SS (4 lags) | 0.03187 | 0.02176 | 0.784 | 132.4% | 129.2% | 66.7% | +15.5% |
| 11 | MIDAS nealmon | 0.03410 | 0.01993 | 0.718 | 164.4% | 95.6% | 81.2% | +23.6% |
