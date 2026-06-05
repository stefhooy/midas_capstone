# Phase 6d Performance vs Interpretability Table

| Rank | Model | RMSE | vs ARIMAX | Dir. Acc. | Complexity | Interpretability | Capstone role |
| ---: | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | MIDAS nbeta | 0.02057 | -31.1% | 74.0% | 3 lag-shape parameters | High | Best RMSE model |
| 2 | LASSO-MIDAS | 0.02103 | -29.6% | 76.0% | 11 nonzero weekly coefficients | Medium-high | Feature-selection robustness |
| 3 | MIDAS nealmon | 0.02104 | -29.5% | 80.2% | 3 lag-shape parameters | High | Best directional model |
| 4 | U-MIDAS | 0.02226 | -25.5% | 75.0% | 12 free weekly coefficients | Medium | Flexible MIDAS benchmark |
| 5 | Kernel U-MIDAS | 0.02226 | -25.5% | 75.0% | 12 lags + smoothness penalty | High | Non-parametric smoother robustness |
| 6 | CLM-SS (12 lags) | 0.02258 | -24.4% | 74.0% | 12 link weights + AR(1) state | High | Novel exact aggregation framework |
| 7 | XGBoost | 0.02365 | -20.8% | 72.9% | Tree ensemble over 14 features | Medium-low | Tree-based ML benchmark |
| 8 | LSTM | 0.02588 | -13.3% | 76.0% | LSTM hidden=4, epochs=150 | Low | Deep-learning benchmark |
| 9 | ARIMAX | 0.02986 | baseline | 64.6% | ARMA + monthly mean WTI | Medium | Baseline to beat |

Main interpretation:

- MIDAS nbeta is the best RMSE model.
- MIDAS nealmon is the best directional model and the clearest defense model.
- Every serious weekly-timing model beats ARIMAX except the lag-limited CLM-SS(4), which is excluded from this final comparison.
- XGBoost and LSTM both beat ARIMAX, but neither beats parametric MIDAS.
- The capstone result is therefore not just about prediction accuracy; it is about accuracy plus an interpretable 5-7 week WTI-to-CPI transmission window.
