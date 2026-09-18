# Input data

These are the four pre-existing input CSVs used by `code/main_5.ipynb`.
They have not been rewritten for publication. Exact byte sizes, row counts, time
coverage, and SHA256 hashes are recorded in `../data_manifest.json`.

| File | Rows | Coverage | Purpose |
|---|---:|---|---|
| `merged_dataset_104957.csv` | 104,957 | 17 April–3 July 2026 | Default full-campaign input and explicit RAFT unit metadata |
| `merged_raft.csv` | 35,132 | 17 April–15 May 2026 | Original-timestamp RAFT export for acquisition and overlap checks |
| `merged_meteo.csv` | 35,327 | 17 April–15 May 2026 | Original-timestamp weather export |
| `merged_ir.csv` | 33,890 | 20 April–15 May 2026 | Original-timestamp sky-temperature export |

The period with complete model inputs is shorter than the full source coverage.
The notebook reports the retained bins after alignment and missing-data exclusion.

## Model columns in the full table

| Column | Meaning | Unit / handling |
|---|---|---|
| `timestamp` | Recorded timestamp after the earlier merge | Timezone not supplied |
| `T_amb` | Ambient temperature | °C |
| `RH` | Relative humidity | Percent, retained on a 0–100 scale |
| `v` | Wind speed | m/s |
| `G` | Solar irradiance | W/m² |
| `T_sky` | Apparent sky temperature | °C; values near −50 °C are flagged |
| `Q_net` | Recorded net heat flux, regression target | W/m²; original sign retained |
| `Q_net_raw` | Logger reading before unit normalization | Interpret using `Q_raw_unit` |
| `Q_raw_unit` | Explicit logger-unit metadata | `V`, `uV`, or `missing` |
| `Q_net_voltage_V` | Logger reading in volts | Consistency checked against the raw reading |

PT100 measurements, dew point, pressure, wind direction, IR diagnostic temperatures,
and emissivity are retained in the source file but are not model predictors.

## Native-column mapping

| Instrument | Native column | Analysis column |
|---|---|---|
| RAFT | `DATE` + `TIME` | `timestamp` |
| RAFT | `HEAT_FLUX_V` | `Q_net`, after exact-timestamp unit lookup and inherited calibration |
| Weather | `TIME` | `timestamp` |
| Weather | `TEMP`, `RH`, `SPEED`, `SOLARRAD` | `T_amb`, `RH`, `v`, `G` |
| Sky | `TIMESTAMP` | `timestamp` |
| Sky, `SIMPLE_TXT` | `TEMPERATURE_C` | `T_sky` |
| Sky, `DETAILED_DAT` | `TPROC` | `T_sky` |

The misleading `HEAT_FLUX_V` header does not imply that every row is in volts. The
notebook uses explicit unit metadata instead of guessing from value magnitude.
Blank, unparseable, or non-finite physical values remain missing. A missing reading
is never converted to a zero.

The files are instrument exports and an existing merged table, not independently
validated raw logger archives. In particular, the original merge tolerance and later
native timestamps are unavailable. See `../docs/methodology.md` for the resulting limits.
