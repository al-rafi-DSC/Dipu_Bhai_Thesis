# Predicting net heat flux in passive radiative cooling materials

A reproducible Random Forest baseline for the Sample 2 RAFT campaign at INRiM, Turin.
The analysis predicts recorded net heat flux from five atmospheric variables and
examines how validation changes when later measurements are held out.

**Start with [the executed notebook, `main_5.ipynb`](code/main_5.ipynb).** It contains
the complete analysis, output tables, and **20 embedded figures**. You can read the
saved results without executing the code. If GitHub's notebook preview is unavailable,
download the repository and open the notebook in a Jupyter-compatible editor.

## What the notebook does

1. Reads the available instrument exports and inventories their timestamps and units.
2. Checks the recorded voltage-to-flux conversion against the existing merged table.
3. Shows original-timestamp and full-campaign acquisition plots.
4. Computes three-minute bin means and excludes bins missing any model variable.
   It does not interpolate outages or apply an additional moving average.
5. Fits a basic Random Forest with training-only min–max normalization.
6. Evaluates random 80/20 and chronological holdouts against a training-mean baseline.
7. Displays measured-versus-predicted plots, residuals, and permutation importance.

The notebook also includes coverage plots, all six individual variable time series,
a combined panel, daily-cycle plots, and correlation heatmaps. No separate figure
folder is needed or generated.

## Executed results

The default full-campaign analysis retains **24,628 observed three-minute bins**
between 20 April and 1 July 2026. It excludes 12,195 incomplete grid intervals and
interpolates zero values.

| Evaluation | Training bins | Validation bins | RMSE (W/m²) | MAE (W/m²) | R² |
|---|---:|---:|---:|---:|---:|
| Random 80/20 | 19,702 | 4,926 | 12.39 | 7.22 | 0.879 |
| Chronological holdout | 19,222 | 4,926 | 39.64 | 19.14 | −0.149 |

The chronological evaluation excludes a 24-hour interval before validation, removing
480 otherwise eligible bins from training. The weaker chronological score means the
baseline has **not demonstrated reliable prediction for later campaign conditions**.
The random-split score alone should not be described as future-period performance.
The final model fitted on all retained data has no additional independent test score.

## Repository contents

```text
code/main_5.ipynb              Complete executed analysis and inline figures
processed/                    Four input CSVs and their data dictionary
docs/methodology.md            Processing decisions, validation, and limitations
data_manifest.json            Input sizes, row counts, periods, and SHA256 hashes
requirements.txt              Tested Python package versions
scripts/run_notebook.py        Execute using the selected Python environment
scripts/validate_submission.py Check input integrity and saved notebook outputs
```

This branch presents the final baseline. Earlier exploratory notebooks and standalone
figures remain in the development branches. Private supervisor recordings are not
redistributed and are not needed to execute the analysis.

## Reproduce the analysis

Use **Python 3.11**. The package versions below match the environment used for the
saved results. Create a new virtual environment rather than reusing an old project
environment copied from a different machine.

### Windows PowerShell

```powershell
git clone --branch professor-review --single-branch https://github.com/al-rafi-DSC/Dipu_Bhai_Thesis.git
cd Dipu_Bhai_Thesis
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts/validate_submission.py
.\.venv\Scripts\python.exe scripts/run_notebook.py
```

### macOS or Linux

```bash
git clone --branch professor-review --single-branch https://github.com/al-rafi-DSC/Dipu_Bhai_Thesis.git
cd Dipu_Bhai_Thesis
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python scripts/validate_submission.py
.venv/bin/python scripts/run_notebook.py
```

The runner executes every cell and updates `code/main_5.ipynb` only after successful
execution. It selects the same Python interpreter that runs the script, requires no
global kernel installation, and never exports individual figures. To preserve the
committed notebook, supply a different output path:

```bash
python scripts/run_notebook.py --output outputs/main_5_reexecuted.ipynb
```

For interactive editing, open the notebook in your existing Jupyter-compatible editor
and select the new environment. The default `DATA_SCOPE = 'full_campaign'` uses the
April–July merged table. Change it to `'native_exports'` and run all cells to restrict
the model to the independently available April–May instrument exports. That alternative
was also executed successfully during preparation. Metrics above refer to the default
full-campaign mode only.

## Interpretation and source limitations

- The separate instrument files stop on 15 May; the merged table extends into July.
  The earlier full-table matching tolerance and later native timestamps are unavailable.
  Full-campaign results therefore depend on that earlier alignment.
- The conversion `Q_net = voltage_V / 60e-6` is inherited from the dataset. Arithmetic
  checks do not substitute for a calibration certificate. The recorded sign is retained;
  its physical cooling/heating interpretation requires confirmation of sensor polarity.
- Sky temperatures clustered at −50 °C suggest a measurement floor. The notebook flags
  them without claiming a verified hardware limit or replacing them with estimates.
- No hyperparameters were tuned on the holdouts. Permutation importance describes model
  reliance on features, not their causal effect or intrinsic material properties.

See the [methodology and references](docs/methodology.md) and
[input data dictionary](processed/README.md) for details.
