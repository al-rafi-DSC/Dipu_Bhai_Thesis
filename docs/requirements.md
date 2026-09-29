# Project brief implementation audit

Reference: the supplied 11-page `summary.pdf`, reviewed on 29 September 2026, and
`references/PLOT_TRESCO_CORRELATIONS_ML-2.m`. The presentation is excluded at the
user's request. This audit distinguishes implemented analysis from measurement
facts that cannot be certified using the available files.

| Brief section | Implementation and evidence |
|---|---|
| 1-2: objective and instruments | Notebook sections 1-2: five environmental predictors, recorded heat-flux target, three native instrument exports. |
| 3: acquisition | Timestamp parsing, units, source hashes, periods, median sample intervals, duplicate conflicts, missing values and native gaps. These begin with supplied consolidated exports, not a newly verified extraction of raw logger archives. |
| 4: raw inspection | Original-timestamp plots of all six variables, before smoothing or binning. The longer pre-existing merge is plotted separately. |
| 5: synchronization | Primary model independently bins each native instrument on the same three-minute boundaries, within their common acquisition period. |
| 6: missing intervals | Incomplete bins excluded, no interpolation or filling; excluded bins and counts exported. |
| 7: moving average | MATLAB's fixed 20-observation centered moving mean before binning; endpoints shrink. Smoothing resets at missing/excluded intervals and native gaps over three minutes. Window examples and gap isolation checked in the notebook. |
| 8: processed plots | Six individual time series, combined panel, and a six-variable before/after comparison with unsmoothed bin means. All figures inline. |
| 9: final Excel/CSV | `processed/final_processed_dataset.csv`, in the brief's column order, is exported directly from the model table and read back for comparison. CSV is the brief's permitted Excel-readable format. |
| 10: normalization | Min-max scaler fitted only on each training partition. |
| 11: split | Shuffled 80/20, seed 42. A chronological holdout additionally checks temporal performance and disjoint smoothing support. |
| 12-13: model | Basic untuned Random Forest. No neural network or hyperparameter optimization. |
| 14: validation | Held-out MAE, RMSE, prediction R² and bias, with a training-mean baseline. |
| 15: plot | Measured/predicted scatter with fitted regression line, slope/intercept, fit-line R² and 1:1 line. Adapted from the actual MATLAB plotting helper, with explicit separation of fit-line and prediction R². |
| 16: preliminary scores | Previous scores are superseded by this processed native-export run. No claim that a stronger score proves correct physics. |
| 17: traceability | Input manifest; final CSV; per-bin source counts/support; split assignments; predictions; metrics; output hashes. |
| 18: prohibited shortcuts | No 0-100 target clipping, arbitrary sign reversal, gap interpolation, score-selected smoothing or neural-network tuning. |
| 19: five-slide update | Intentionally excluded from this task. |
| 20: complete chain | Executed notebook connects all applicable stages. MATLAB order (smooth native observations before resampling) is explicitly used instead of treating 20 samples as 60 minutes on a three-minute grid. |

## Remaining measurement limitations

The code cannot establish sensor calibration/polarity, missing timezone/clock-offset
metadata, the true reason for the apparent -50 C sky-temperature floor, or native
source alignment after 15 May. The final analysis therefore uses the available
native-export overlap and labels its target as recorded-sign processed heat flux.
Those are source limitations, not omitted software steps. The centered smoother
uses neighboring future readings; this report evaluates offline reconstruction.
