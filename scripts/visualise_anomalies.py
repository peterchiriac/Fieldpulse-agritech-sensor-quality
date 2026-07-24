from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


# Build paths relative to the project root
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = PROJECT_ROOT / "data" / "dirty_farm_sensors.csv"
OUTPUT_DIR = PROJECT_ROOT / "outputs"
OUTPUT_PATH = OUTPUT_DIR / "sensor_anomalies.png"


# Load the telemetry data
df = pd.read_csv(
    DATA_PATH,
    parse_dates=["timestamp_utc"]
)

# Separate the three probes
probe_101 = df[df["probe_id"] == 101]
probe_102 = df[df["probe_id"] == 102]
probe_103 = df[df["probe_id"] == 103]


# Create one figure with three time-series panels
fig, axes = plt.subplots(
    nrows=3,
    ncols=1,
    figsize=(14, 11),
    sharex=True
)

# Probe 101: battery dropout
axes[0].plot(
    probe_101["timestamp_utc"],
    probe_101["battery_v"],
    linewidth=1.5
)

axes[0].axhline(
    y=2.8,
    linestyle="--",
    linewidth=1,
    label="Critical battery threshold (2.8 V)"
)

axes[0].set_title("Probe 101 — Battery Dropout")
axes[0].set_ylabel("Battery voltage")
axes[0].legend()
axes[0].grid(alpha=0.3)


# Probe 102: impossible moisture readings
axes[1].plot(
    probe_102["timestamp_utc"],
    probe_102["raw_moisture_pct"],
    linewidth=1.2
)

axes[1].axhline(
    y=100,
    linestyle="--",
    linewidth=1,
    label="Valid upper limit"
)

axes[1].axhline(
    y=0,
    linestyle="--",
    linewidth=1,
    label="Valid lower limit"
)

axes[1].set_title("Probe 102 — Invalid Soil Moisture Spikes")
axes[1].set_ylabel("Moisture (%)")
axes[1].legend()
axes[1].grid(alpha=0.3)


# Probe 103: frozen temperature sensor
axes[2].plot(
    probe_103["timestamp_utc"],
    probe_103["raw_temp_c"],
    linewidth=1.5
)

axes[2].set_title("Probe 103 — Frozen Temperature Flatline")
axes[2].set_ylabel("Temperature (°C)")
axes[2].set_xlabel("Timestamp (UTC)")
axes[2].grid(alpha=0.3)


# Final formatting and export
fig.suptitle(
    "FieldPulse Sensor Data-Quality Anomalies",
    fontsize=16
)

fig.autofmt_xdate()
fig.tight_layout(rect=[0, 0, 1, 0.97])

OUTPUT_DIR.mkdir(exist_ok=True)

fig.savefig(
    OUTPUT_PATH,
    dpi=300,
    bbox_inches="tight"
)

plt.show()

print(f"Visualisation saved to: {OUTPUT_PATH}")