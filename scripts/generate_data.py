import pandas as pd
import numpy as np

# Set random seed so your numbers match mine exactly
np.random.seed(42)

# 1. GENERATE BASE TIMELINE (3 days at 10-minute intervals)
timestamps = pd.date_range(start="2026-06-01 00:00:00", end="2026-06-03 23:50:00", freq="10min")
n_records = len(timestamps)

data_list = []
for probe_id in [101, 102, 103]:
    # Simulate smooth base agronomic curves with slight micro-fluctuations
    base_moisture = 25.0 + 5.0 * np.sin(np.linspace(0, 4 * np.pi, n_records)) + np.random.normal(0, 0.2, n_records)
    base_temp = 15.0 + 4.0 * np.sin(np.linspace(0, 4 * np.pi, n_records) - np.pi / 2) + np.random.normal(0, 0.05,
                                                                                                         n_records)
    battery = np.linspace(4.1, 3.6, n_records) + np.random.normal(0, 0.01, n_records)

    probe_df = pd.DataFrame({
        'probe_id': probe_id,
        'timestamp_utc': timestamps,
        'raw_moisture_pct': base_moisture,
        'raw_temp_c': base_temp,
        'battery_v': battery
    })
    data_list.append(probe_df)

df = pd.concat(data_list, ignore_index=True)

# 2. INJECT ANOMALY A: Probe 101 - Missing Data Dropout (Battery Death)
# Battery drops to 2.4V, causing hardware to stop transmitting for an 18-hour block
dropout_start = pd.Timestamp("2026-06-02 01:00:00")
dropout_end = pd.Timestamp("2026-06-02 19:00:00")
mask_101 = (df['probe_id'] == 101) & (df['timestamp_utc'] >= dropout_start) & (df['timestamp_utc'] <= dropout_end)
df.loc[mask_101, 'battery_v'] = 2.42
df.loc[mask_101, ['raw_moisture_pct', 'raw_temp_c']] = np.nan

# 3. INJECT ANOMALY B: Probe 102 - Outlier Spikes (Electrical Short Circuits)
# Force impossible numbers directly into the moisture log
spike_idx1 = df[(df['probe_id'] == 102) & (df['timestamp_utc'] == "2026-06-01 08:20:00")].index
spike_idx2 = df[(df['probe_id'] == 102) & (df['timestamp_utc'] == "2026-06-02 14:40:00")].index
df.loc[spike_idx1, 'raw_moisture_pct'] = 999.0
df.loc[spike_idx2, 'raw_moisture_pct'] = -45.2

# 4. INJECT ANOMALY C: Probe 103 - Frozen Sensor (Zero Variance Flatline)
# Temperature completely locks at 12.5000°C for a 12-hour window
freeze_start = pd.Timestamp("2026-06-02 09:20:00")
freeze_end = pd.Timestamp("2026-06-02 21:20:00")
mask_103 = (df['probe_id'] == 103) & (df['timestamp_utc'] >= freeze_start) & (df['timestamp_utc'] <= freeze_end)
df.loc[mask_103, 'raw_temp_c'] = 12.5000

# 5. SAVE OUT RAW FILE
df.to_csv("dirty_farm_sensors.csv", index=False)
print(f"--- Success! Created dirty_farm_sensors.csv with {len(df)} rows. ---")