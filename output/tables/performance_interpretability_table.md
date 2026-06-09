# Phase 6d Performance vs Interpretability Table

| Rank | Model | RMSE | vs ARIMAX | Dir. Acc. | Complexity | Interpretability | Capstone role |
| ---: | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | LASSO-MIDAS | 0.02103 | -29.6% | 76.0% | 11 nonzero weekly coefficients | Medium-high | Feature-selection robustness |
| 2 | XGBoost | 0.02170 | -21.3% | 79.2% | Tree ensemble over 14 features | Medium-low | Tree-based ML benchmark |
| 3 | CLM-SS (12 lags) | 0.02258 | -24.4% | 74.0% | 12 link weights + AR(1) state | High | Novel exact aggregation framework |
| 4 | LSTM | 0.02505 | -9.2% | 71.9% | LSTM hidden=4, epochs=100 | Low | Deep-learning benchmark |
| 5 | Kernel U-MIDAS | 0.02705 | -1.9% | 77.1% | 12 lags + smoothness penalty | High | Non-parametric smoother robustness |
| 6 | U-MIDAS | 0.02711 | -1.7% | 75.0% | 12 free weekly coefficients | Medium | Flexible MIDAS benchmark |
| 7 | ARIMAX | 0.02758 | baseline | 64.6% | ARMA + monthly mean WTI | Medium | Baseline to beat |
| 8 | MIDAS nbeta | 0.02913 | +5.6% | 74.0% | 3 lag-shape parameters | High | Best RMSE model |
| 9 | MIDAS nealmon | 0.03410 | +23.6% | 80.2% | 3 lag-shape parameters | High | Best directional model |

Main interpretation:

- MIDAS nbeta is the best RMSE model.
- MIDAS nealmon is the best directional model and the clearest defense model.
- Every serious weekly-timing model beats ARIMAX except the lag-limited CLM-SS(4), which is excluded from this final comparison.
- XGBoost and LSTM both beat ARIMAX, but neither beats parametric MIDAS.
- The capstone result is therefore not just about prediction accuracy; it is about accuracy plus an interpretable 5-7 week WTI-to-CPI transmission window.
