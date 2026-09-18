# Methodology and interpretation

## Research objective

Model the recorded net heat flux of the Sample 2 passive radiative cooling material as
a function of ambient temperature, relative humidity, wind speed, solar irradiance,
and sky temperature. This is a supervised regression task. Sample temperature, logger
voltage, timestamps, and other target-derived quantities are not predictors.

## Source hierarchy

The current workflow follows the supervisor's latest recorded instructions: inspect
acquisition before preprocessing; remove missing intervals; align the instruments;
normalize and split; use a basic Random Forest; report validation metrics and a
measured-versus-predicted plot. The supplied audio permits a three-minute time step.
Those instructions take precedence over the earlier presentation's five-minute MLP
example. The recordings are private reference material and are not part of this branch.

The presentation's RMSE of 9.5 W/m² and R² of 0.92 describe a different Sample 1
experiment and neural-network training procedure. They are context, not acceptance
thresholds for this baseline. The MATLAB source mentioned in the audio was not
available, so this is an implementation of the described workflow rather than a
line-by-line translation of that code.

## Inputs and acquisition audit

The four included CSVs are the files read by the notebook. They are preserved byte for
byte and listed in `data_manifest.json`. The individual exports contain original
instrument timestamps but are themselves pre-existing CSV consolidations; the raw
logger files and the original full-campaign merge procedure are not supplied.

The RAFT column labelled `HEAT_FLUX_V` contains both volts and microvolts. The notebook
looks up the full table's explicit unit at each exact RAFT timestamp, checks that the
raw numbers agree, and converts units before applying the inherited 60 µV/(W/m²)
sensitivity. This unit-metadata dependency also applies in native-export mode. It does
not independently certify sensor calibration or polarity.

Detailed IR records use `TPROC`; simple records use `TEMPERATURE_C`. Internal camera
diagnostic temperatures and emissivity are excluded from the model. Duplicate native
timestamps are averaged within each instrument, and the inventory reports their count.

## Alignment and missing data

The default full-campaign path starts from the existing merged table before the older
notebooks' gap interpolation and smoothing. Each variable is averaged independently
in fixed three-minute bins anchored at midnight, left-labelled and left-closed. At
least one finite value of every required variable is necessary to retain a bin.

The native-export alternative builds the same bins directly from each instrument's
own timestamps. A shared-period comparison shows differences from the earlier merge.
Neither method guarantees simultaneous measurements inside a bin: within-bin timing
differences may remain. Timezone metadata are absent, so no timezone conversion or
clock-offset correction is guessed.

Missing intervals are excluded, not filled. There is no additional moving average,
target clipping, or learned imputation. Line plots reintroduce missing grid positions
only as `NaN` so outages remain visible. Daily cycles and correlations describe the
retained observations; excluded periods contribute no invented values.

## Modelling and evaluation

The fixed model is `RandomForestRegressor` with 100 trees, unrestricted depth,
`min_samples_leaf=1`, all five features available per split, bootstrap sampling, and
random seed 42. Two workers limit resource use. A `MinMaxScaler` is fitted inside each
training pipeline. Scaling follows the requested workflow, although the forest does
not require it. The target retains its original physical units and recorded sign.

Two separate evaluation models are fitted:

1. A shuffled, reproducible 80/20 split. Nearby campaign measurements can appear in
   both sets, so this is an interpolation baseline rather than a future-period test.
2. A chronological split with the last 20% of retained bins reserved for validation.
   Training excludes the 24 hours preceding that boundary. This tests later conditions
   but represents only one held-out period, not all seasons or future campaigns.

Each split has a training-mean baseline, RMSE, MAE, R² and prediction bias. Training
scores are reported separately. All held-out observations, including extremes, appear
in parity plots. There is no hyperparameter search, no selection of the more flattering
split, and no independent test score assigned to the final all-data fit.

Chronological permutation importance uses five shuffles per predictor and measures
the change in held-out RMSE. Correlated variables and distribution shift affect this
diagnostic; it must not be interpreted as a causal ranking.

## Limits of the conclusions

The random-split result is stronger than the chronological result. The latter has
negative R², so this baseline does not establish useful later-period generalization.
These outcomes are reported rather than hidden through a changed split or selective
removal of difficult validation observations.

The heat-flux sign, sensitivity, possible IR sensor floor, and original full-campaign
alignment need measurement-level confirmation before physical cooling-performance
claims. Code and source-integrity checks establish reproducibility of this analysis,
not independent metrological validation of the instruments.

## References

- Bertiglia, F.; Forte, D.; Lopardo, G.; Girard, F.; Pattelli, L.; Fasano, M.
  *An Ambient Temperature-tracking Setup for Outdoor Characterization of Passive
  Radiative Cooling (PRC) Materials.* UIT 2026 presentation, 23 June 2026.
  Slides 9 and 11 describe the setup and campaign; slide 13 describes the Sample 1 model.
- Supervisor's approximately six-minute recorded guidance supplied with this project,
  filename dated 18 September 2026. Acquisition: approximately 00:25–01:40;
  alignment and missing intervals: 01:55–02:45; Random Forest: 02:45–03:20;
  validation: 03:20–03:50; simple implementation: 04:00–05:40.
  Timings were obtained from an automated transcript and are approximate.
