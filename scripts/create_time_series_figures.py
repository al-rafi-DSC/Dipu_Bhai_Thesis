"""Create publication-ready time-series figures from the merged dataset."""

from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = PROJECT_ROOT / "processed" / "merged_dataset_104957.csv"
OUTPUT_DIR = PROJECT_ROOT / "processed" / "figures"

SIGNALS = {
    "v": {
        "title": "Wind speed vs Time",
        "ylabel": r"Wind speed [$m\,s^{-1}$]",
        "color": "#9467bd",
        "filename": "v_vs_time",
    },
    "T_sky": {
        "title": "Sky temperature vs Time",
        "ylabel": r"Temperature [$^\circ$C]",
        "color": "#d62728",
        "filename": "T_sky_vs_time",
    },
    "T_pt100_C": {
        "title": "PT100 temperature vs Time",
        "ylabel": r"Temperature [$^\circ$C]",
        "color": "#17becf",
        "filename": "T_pt100_C_vs_time",
    },
    "T_amb": {
        "title": "Ambient temperature vs Time",
        "ylabel": r"Temperature [$^\circ$C]",
        "color": "#1f77b4",
        "filename": "T_amb_vs_time",
    },
    "RH": {
        "title": "Relative humidity vs Time",
        "ylabel": "Relative humidity [%]",
        "color": "#2ca02c",
        "filename": "RH_vs_time",
    },
    "Q_net": {
        "title": "Net heat flux vs Time",
        "ylabel": r"Heat flux [$W\,m^{-2}$]",
        "color": "#111111",
        "filename": "Q_net_vs_time",
    },
}


def load_data() -> pd.DataFrame:
    """Load only the timestamp and signal columns needed for the figures."""
    required_columns = ["timestamp", *SIGNALS]
    data = pd.read_csv(DATA_PATH, usecols=required_columns, low_memory=False)
    data["timestamp"] = pd.to_datetime(data["timestamp"], errors="coerce")
    return data


def create_figure(data: pd.DataFrame, column: str, spec: dict[str, str]) -> int:
    """Drop nulls for one signal and plot the remaining points continuously."""
    plot_data = data[["timestamp", column]].copy()
    plot_data[column] = pd.to_numeric(plot_data[column], errors="coerce")
    plot_data = plot_data.dropna(subset=["timestamp", column]).sort_values("timestamp")

    if plot_data.empty:
        raise ValueError(f"No valid observations found for {column}")

    fig, ax = plt.subplots(figsize=(16, 7))
    ax.plot(
        plot_data["timestamp"],
        plot_data[column],
        color=spec["color"],
        linewidth=1,
    )

    locator = mdates.AutoDateLocator(minticks=5, maxticks=12)
    ax.xaxis.set_major_locator(locator)
    ax.xaxis.set_major_formatter(mdates.ConciseDateFormatter(locator))
    ax.set_title(spec["title"], fontsize=16)
    ax.set_xlabel("Time", fontsize=12)
    ax.set_ylabel(spec["ylabel"], fontsize=12)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    for extension in ("png", "pdf"):
        output_path = OUTPUT_DIR / f"{spec['filename']}.{extension}"
        save_options = {"bbox_inches": "tight"}
        if extension == "png":
            save_options["dpi"] = 300
        fig.savefig(output_path, **save_options)

    plt.close(fig)
    return len(plot_data)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    data = load_data()
    print(f"Loaded {len(data):,} rows from {DATA_PATH.name}")

    for column, spec in SIGNALS.items():
        observations = create_figure(data, column, spec)
        print(f"Created {spec['filename']}.png/.pdf ({observations:,} observations)")


if __name__ == "__main__":
    main()
