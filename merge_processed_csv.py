"""Losslessly merge processed RAFT, meteorological, and IR events."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


PROCESSED_DIR = Path(__file__).resolve().parent / "processed"
OUTPUT_PATH = PROCESSED_DIR / "merged_all_events_lossless.csv"


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


def _to_event_frame(
    frame: pd.DataFrame,
    timestamp: pd.Series,
    source_name: str,
) -> pd.DataFrame:
    """Create one auditable event row for every source row."""

    prefixed = _prefix_columns(frame, source_name)
    event = pd.DataFrame(
        {
            "SOURCE_DATASET": source_name,
            "SOURCE_ROW_NUMBER": range(1, len(frame) + 1),
            "_SORT_TIMESTAMP": timestamp,
        }
    )
    return pd.concat(
        [event.reset_index(drop=True), prefixed.reset_index(drop=True)],
        axis=1,
    )


def merge_processed_data() -> pd.DataFrame:
    """Append every source row and order the complete event table by time."""

    infrared, meteo, raft = _read_sources()
    infrared_time, meteo_time, raft_time = _parse_timestamps(
        infrared,
        meteo,
        raft,
    )

    events = [
        _to_event_frame(raft, raft_time, "RAFT"),
        _to_event_frame(meteo, meteo_time, "METEO"),
        _to_event_frame(infrared, infrared_time, "IR"),
    ]
    merged = pd.concat(
        events,
        ignore_index=True,
        sort=False,
    ).sort_values(
        ["_SORT_TIMESTAMP", "SOURCE_DATASET", "SOURCE_ROW_NUMBER"],
        kind="stable",
    )

    merged.insert(
        0,
        "MERGE_DATE",
        merged["_SORT_TIMESTAMP"].dt.strftime("%d/%m/%y"),
    )
    merged.insert(
        1,
        "MERGE_TIMESTAMP",
        merged["_SORT_TIMESTAMP"].dt.strftime("%d/%m/%y %H:%M:%S.%f").str[:-3],
    )
    merged = merged.drop(columns=["_SORT_TIMESTAMP"])

    return merged.reset_index(drop=True)


def main() -> None:
    merged = merge_processed_data()
    merged.to_csv(OUTPUT_PATH, index=False)

    print(f"Output: {OUTPUT_PATH}")
    print(f"Rows: {len(merged)}")
    print(f"Columns: {len(merged.columns)}")
    print(f"Missing cells preserved: {int(merged.isna().sum().sum())}")
    print("Rows by source:")
    print(merged["SOURCE_DATASET"].value_counts().sort_index().to_string())


if __name__ == "__main__":
    main()
