# Methodology and interpretation

## Objective and reference hierarchy

Predict processed recorded net heat flux from ambient temperature, relative humidity,
solar irradiance, wind speed and sky temperature. The project brief (`summary.pdf`)
specifies a basic Random Forest, a common three-minute grid, removal of incomplete
intervals, original/processed plots, a final Excel-readable dataset and held-out
validation. The supplied MATLAB file specifies the previously missing moving-average
window. Its older neural-network workflow is not the current model requirement.

## Acquisition and scope

The four input files remain byte-for-byte unchanged, verified by `data_manifest.json`.
The primary model uses the available April-May instrument exports and their own
timestamps, restricted to full three-minute intervals inside their shared acquisition
period. The April-July merge is used for acquisition comparison and exact-timestamp
RAFT unit lookup, not to supply model alignment. This narrows the modelling period
because the brief makes auditable synchronization the priority.

The RAFT `HEAT_FLUX_V` field contains both volts and microvolts. Exact-timestamp
metadata from the existing merged table identify units, and matching raw readings
are asserted. Voltages are divided by the inherited sensitivity 60e-6 V/(W/m²).
Recorded polarity is retained; the sign reversal in the 2025 MATLAB experiment is
not evidence for reversing the 2026 dataset. The files are consolidated exports,
not independently verified original logger archives.

IR uses `TPROC` for detailed records and `TEMPERATURE_C` for simple records.
Stable sorting followed by first-record duplicate removal mirrors MATLAB's
`unique(...,'stable')`. Duplicate conflicts are reported, not silently averaged.
Temperatures remain Celsius and RH remains percent. These units are labelled in
the data dictionary and are consistent with subsequent training-only normalization.
Sample temperature is not a predictor or an additional completeness requirement.

## Synchronization and smoothing

1. Parse and inspect original instrument timestamps before modifying signals.
2. Audit raw finite values in midnight-anchored, left-labelled, left-closed three-minute
   bins. A row is eligible only when all six required variables have readings.
   Partial bins at the common acquisition boundaries are excluded.
3. Apply a 20-sample centered moving mean separately to each native series within
   eligible, uninterrupted segments. An even window includes ten preceding readings,
   the current reading and nine following readings. Endpoints shrink. This matches
   MATLAB's sample-window convention; it does not mean 20 minutes or 20 resampled bins.
4. Reset the smoother at non-finite readings, excluded common intervals, or native
   gaps greater than three minutes. This conservative, explicitly declared rule
   adapts the older script to the brief's missing-data requirement. No smoothing
   support crosses an excluded interval. Shortened windows and actual durations
   are reported, not hidden.
5. Average the smoothed native readings into the same three-minute bins. Remove
   incomplete bins and retain the original eligibility mask. Never interpolate.

The grid specifies which interval a row represents. Centered smoothing uses nearby
intervals too, so per-variable source-support bounds are exported in `bin_audit.csv`.
Within-bin instrument timing differences and undocumented clock offsets can remain.
No timezone or clock correction is guessed. Missing positions are restored as NaN
only for plotting so lines do not bridge outages.

MATLAB moving-mean semantics are documented by
[MathWorks](https://www.mathworks.com/help/matlab/ref/movmean.html).

## Explicit differences from the MATLAB reference

| Reference code | Current implementation and reason |
|---|---|
| 2025 Excel input and custom `sumtime` | Actual 2026 timestamps from the supplied CSVs. The helper's calendar/offset logic is not transplanted. |
| `movsetting = 20` before resampling | Preserved on native samples, with gap resets to satisfy the brief. |
| Five-minute linear interpolation | Three-minute bin means; no interpolation, per the newer brief. |
| `Q_orig = -Data1_p(:,2)` | Retain recorded sign pending polarity evidence for these sensors. |
| Kelvin temperatures, RH fraction | Celsius and percent, clearly labelled; scaling fitted on training data. |
| `x1 = T_s_full` | Ambient temperature, as requested by the brief. |
| Global normalization and NN tuning | Training-only scaling and untuned Random Forest. |
| Final predictions on training data | Report scores from held-out observations only. |
| `linearRegressionPlot` scatter and fitted line | Same comparison components plus a 1:1 line and direct prediction metrics. |
| Undefined simulation variables | Excluded: incomplete simulation code is unrelated to the requested baseline. |

## Evaluation

The model uses 100 trees, unrestricted depth, one sample per leaf, all five features
available per split, bootstrap sampling and seed 42. No hyperparameters or smoothing
settings are chosen from validation results. A min-max scaler lives inside each
training pipeline. The target remains in physical units.

The requested shuffled 80/20 split is a within-campaign reconstruction benchmark.
Rows are disjoint, but centered smoothing and serial dependence mean nearby rows
share raw support. Its score must not be described as independent future performance.

The chronological evaluation reserves the final 20% and removes the 24 hours before
the boundary from training. Actual source-support ranges are checked for complete
train/validation separation. It evaluates a later processed period, not a causal
real-time forecast: centered validation inputs themselves use future neighbors.
Only one later period is tested. A final all-data fit has no independent test score.

Both splits include MAE, RMSE, direct prediction R², prediction bias and a training-mean
baseline. Training scores diagnose overfitting. The comparison figure adds a fitted
line following MATLAB's helper. Its fit-line R² describes association between
measurements and predictions and is distinct from direct prediction R².
Permutation importance describes model reliance, not physical causality.

## Exports and reproducibility

`processed/final_processed_dataset.csv` is exactly the physical-unit table used to
build X and y, read back and numerically verified. All rows lie on the common grid;
excluded intervals make some successive timestamps farther than three minutes apart.
`results/` contains bin eligibility/counts/source support, native gaps, train/validation
membership, held-out predictions, metrics, source hashes, parameters and output hashes.
The validator independently recomputes held-out metrics and checks support separation.
The notebook tests window centering/endpoints, missing readings and gap isolation.

## Limits

Calibration and polarity, instrument clock synchronization and the apparent -50 °C
IR floor require measurement-level confirmation. No target clipping or floor
replacement is applied. Raw export consolidation itself is inherited. The later
May-July campaign cannot be independently synchronized without later native files.
The results are evidence about this processed dataset, not certified physical
cooling performance or real-time deployment accuracy.

## References

- Supplied `summary.pdf`, 11 pages, reviewed 29 September 2026; presentation excluded.
- Supplied `PLOT_TRESCO_CORRELATIONS_ML-2.m`, retained unchanged under `references/`.
- Bertiglia et al., *An Ambient Temperature-tracking Setup for Outdoor Characterization
  of Passive Radiative Cooling (PRC) Materials*, UIT 2026 presentation, 23 June 2026.
- Supervisor's approximately six-minute recording supplied with this project,
  filename dated 18 September 2026. The recording is not redistributed.
