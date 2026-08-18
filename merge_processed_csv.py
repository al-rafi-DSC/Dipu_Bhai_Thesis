"""Merge processed RAFT, meteorological, and IR data by timestamp."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


PROCESSED_DIR = Path(__file__).resolve().parent / "processed"
OUTPUT_PATH = PROCESSED_DIR / "merged_all_by_time.csv"
TOLERANCE = pd.Timedelta("90s")


def _read_sources() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Read source CSVs without discarding columns or missing values."""

    infrared = pd.read_csv(
        PROCESSED_DIR / "merged_ir.csv",
        dtype=object,
        low_memory=False,
    )
    meteo = pd.read_csv(
        PROCESSED_DIR / "merged_meteo.csv",
        dtype=object,
        low_memory=False,
    )
    raft = pd.read_csv(
        PROCESSED_DIR / "merged_raft.csv",
        dtype=object,
        low_memory=False,
    )
    return infrared, meteo, raft


def _parse_timestamps(
    infrared: pd.DataFrame,
    meteo: pd.DataFrame,
    raft: pd.DataFrame,
) -> tuple[pd.Series, pd.Series, pd.Series]:
    """Convert the three source date formats to comparable timestamps."""

    infrared_time = pd.to_datetime(
        infrared["TIMESTAMP"],
        format="%Y-%m-%d %H:%M:%S.%f",
        errors="coerce",
    )
    meteo_time = pd.to_datetime(
        meteo["TIME"],
        format="%a %d %B %Y %H:%M:%S",
        errors="coerce",
    )
    raft_time = pd.to_datetime(
        raft["DATE"].str.strip() + " " + raft["TIME"].str.strip(),
        format="%d/%m/%Y %H:%M:%S",
        errors="coerce",
    )

    invalid = {
        "IR": int(infrared_time.isna().sum()),
        "METEO": int(meteo_time.isna().sum()),
        "RAFT": int(raft_time.isna().sum()),
    }
    invalid = {name: count for name, count in invalid.items() if count}
    if invalid:
        raise ValueError(f"Unparseable source timestamps: {invalid}")

    return infrared_time, meteo_time, raft_time


def _prefix_columns(frame: pd.DataFrame, prefix: str) -> pd.DataFrame:
    """Preserve every original column while preventing name collisions."""

    return frame.rename(
        columns={column: f"{prefix}_{column}" for column in frame.columns}
    )


def merge_processed_data() -> pd.DataFrame:
    """Merge METEO and IR onto the RAFT timeline using nearest timestamps."""

    infrared, meteo, raft = _read_sources()
    infrared_time, meteo_time, raft_time = _parse_timestamps(
        infrared,
        meteo,
        raft,
    )

    infrared = _prefix_columns(infrared, "IR")
    meteo = _prefix_columns(meteo, "METEO")
    raft = _prefix_columns(raft, "RAFT")

    infrared.insert(0, "MERGE_TIMESTAMP", infrared_time)
    meteo.insert(0, "MERGE_TIMESTAMP", meteo_time)
    raft.insert(0, "MERGE_TIMESTAMP", raft_time)

    merged = pd.merge_asof(
        raft.sort_values("MERGE_TIMESTAMP"),
        meteo.sort_values("MERGE_TIMESTAMP"),
        on="MERGE_TIMESTAMP",
        direction="nearest",
        tolerance=TOLERANCE,
    )
    merged = pd.merge_asof(
        merged.sort_values("MERGE_TIMESTAMP"),
        infrared.sort_values("MERGE_TIMESTAMP"),
        on="MERGE_TIMESTAMP",
        direction="nearest",
        tolerance=TOLERANCE,
    )

    merged.insert(
        0,
        "MERGE_DATE",
        merged["MERGE_TIMESTAMP"].dt.strftime("%d/%m/%y"),
    )
    merged["MERGE_TIMESTAMP"] = merged["MERGE_TIMESTAMP"].dt.strftime(
        "%d/%m/%y %H:%M:%S"
    )

    return merged.reset_index(drop=True)


def main() -> None:
    merged = merge_processed_data()
    merged.to_csv(OUTPUT_PATH, index=False)

    print(f"Output: {OUTPUT_PATH}")
    print(f"Rows: {len(merged)}")
    print(f"Columns: {len(merged.columns)}")
    print(f"Missing cells preserved: {int(merged.isna().sum().sum())}")


if __name__ == "__main__":
    main()
