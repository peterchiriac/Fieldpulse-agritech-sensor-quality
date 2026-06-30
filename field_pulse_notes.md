# Project FieldPulse — Data Quality Notes

## Stage 1: Raw Data Validation

### Check: Impossible soil moisture values

**Business / domain rule:**
Soil moisture percentage should sit between 0 and 100.

**SQL used to identify invalid values:**

```sql
SELECT 
    probe_id,
    timestamp_utc,
    raw_moisture_pct
FROM staging_farm_telemetry
WHERE raw_moisture_pct < 0
   OR raw_moisture_pct > 100
ORDER BY probe_id, timestamp_utc;
```

### Result

Two invalid soil moisture readings were found on Probe 102:

| probe_id | timestamp_utc | raw_moisture_pct |
|---|---|---:|
| 102 | 2026-06-01 08:20:00 | 999.00 |
| 102 | 2026-06-02 14:40:00 | -45.20 |

### Interpretation

Both readings fall outside the physically possible range for soil moisture percentage.

These values are likely caused by sensor error, electrical disturbance, transmission issue, or another data-quality problem rather than real field conditions.

## Stage 2: Clean View Creation

A reusable SQL view was created to preserve the raw telemetry table while exposing cleaned analysis-ready fields.

**View name:**

`vw_clean_farm_telemetry`

**Purpose:**

The view keeps the original raw sensor readings but adds a cleaned moisture column using the data-quality rule established earlier.

```sql
CREATE VIEW vw_clean_farm_telemetry AS
SELECT 
    probe_id,
    timestamp_utc,
    raw_moisture_pct,
    CASE 
        WHEN raw_moisture_pct < 0 
          OR raw_moisture_pct > 100 
        THEN NULL
        ELSE raw_moisture_pct
    END AS clean_moisture_pct,
    raw_temp_c,
    battery_v
FROM staging_farm_telemetry;
```

### Interpretation

The clean view creates a new field, `clean_moisture_pct`, where impossible moisture readings are converted to `NULL`.

The original values remain available in `raw_moisture_pct`.

This means later analysis can use the cleaned moisture value without losing the original raw sensor reading.

### Principle

The raw table remains untouched. The view acts as a reusable clean layer for validation, analysis, and later reporting.


## Stage 3: Battery Dropout / Missing Values Check

### Check: Low battery and missing environmental readings

**Business / domain rule:**

If a sensor's battery voltage drops below a critical operating threshold, environmental readings may become unreliable or disappear entirely.

For this project, a low-battery threshold of `< 2.8V` was used.

### SQL used to summarise low-battery periods

```sql
SELECT 
    probe_id,
    COUNT(*) AS low_battery_rows,
    COUNT(*) FILTER (WHERE raw_moisture_pct IS NULL) AS missing_moisture_rows,
    COUNT(*) FILTER (WHERE raw_temp_c IS NULL) AS missing_temp_rows,
    MIN(timestamp_utc) AS dropout_start,
    MAX(timestamp_utc) AS dropout_end,
    MIN(battery_v) AS min_battery_v,
    MAX(battery_v) AS max_battery_v
FROM vw_clean_farm_telemetry
WHERE battery_v < 2.8
GROUP BY probe_id
ORDER BY probe_id;
```

### Result

Probe 101 showed a continuous low-battery period:

- `low_battery_rows`: 109
- `missing_moisture_rows`: 109
- `missing_temp_rows`: 109
- `dropout_start`: `2026-06-02 01:00:00`
- `dropout_end`: `2026-06-02 19:00:00`
- `min_battery_v`: `2.42`
- `max_battery_v`: `2.42`

### Interpretation

Every low-battery row also had missing moisture and temperature readings.

This suggests the missing environmental readings were caused by a hardware/power dropout rather than a real soil or weather event.

### Principle

Missing values should not be interpreted automatically as environmental behaviour. Device-health fields such as `battery_v` must be checked before drawing agronomic conclusions.


## Stage 4: Battery Dropout Flag Added to Clean View

### Purpose

After confirming that Probe 101 had a continuous low-battery period where moisture and temperature readings were missing, the clean view was updated to include a `battery_dropout_flag`.

This flag marks rows where missing environmental readings are likely caused by hardware or power failure rather than real soil conditions.

### Logic

A row is flagged as a battery dropout when:

- `battery_v < 2.8`
- `raw_moisture_pct IS NULL`
- `raw_temp_c IS NULL`

### SQL used to update the clean view

```sql
CREATE OR REPLACE VIEW vw_clean_farm_telemetry AS
SELECT 
    probe_id,
    timestamp_utc,
    raw_moisture_pct,
    CASE 
        WHEN raw_moisture_pct < 0 
          OR raw_moisture_pct > 100 
        THEN NULL
        ELSE raw_moisture_pct
    END AS clean_moisture_pct,
    raw_temp_c,
    battery_v,
    CASE
        WHEN battery_v < 2.8
         AND raw_moisture_pct IS NULL
         AND raw_temp_c IS NULL
        THEN TRUE
        ELSE FALSE
    END AS battery_dropout_flag
FROM staging_farm_telemetry;
```

### Validation query

```sql
SELECT 
    probe_id,
    timestamp_utc,
    raw_moisture_pct,
    raw_temp_c,
    battery_v,
    battery_dropout_flag
FROM vw_clean_farm_telemetry
WHERE battery_dropout_flag = TRUE
ORDER BY timestamp_utc
LIMIT 20;
```

### Result

Rows flagged as battery_dropout_flag = TRUE corresponded to Probe 101 during the low-battery dropout window.

These rows showed:

* missing raw_moisture_pct
* missing raw_temp_c
* battery_v = 2.42
* battery_dropout_flag = TRUE

### Interpretation

The missing environmental readings were labelled as hardware-related missingness.

This prevents the missing values from being misread as real agronomic behaviour, such as sudden soil drying, irrigation failure, or temperature collapse.

### Principle                                                                                    

Data-quality flags should preserve the reason why a value is missing or unreliable. In sensor datasets, missing values are not all the same: some are caused by environmental behaviour, while others are caused by device failure.


## Stage 5: Frozen Temperature Sensor Investigation

### Check: Repeated temperature values

A broad check was used to identify temperature readings that appeared unusually often.

```sql
SELECT 
    probe_id,
    raw_temp_c,
    COUNT(*) AS repeated_value_count,
    MIN(timestamp_utc) AS first_seen,
    MAX(timestamp_utc) AS last_seen
FROM vw_clean_farm_telemetry
WHERE raw_temp_c IS NOT NULL
GROUP BY probe_id, raw_temp_c
HAVING COUNT(*) >= 12
ORDER BY repeated_value_count DESC;
```


### Result

The repeated-value check returned one suspicious temperature value:

| probe_id | raw_temp_c | repeated_value_count | first_seen | last_seen |
|---|---:|---:|---|---|
| 103 | 12.50 | 74 | 2026-06-02 06:50:00 | 2026-06-02 21:20:00 |

### Interpretation of broad check

Probe 103 showed an unusually frequent repeated temperature value of `12.50°C`.

However, this broad check only counted how often the value appeared. It did not prove that all occurrences were consecutive.

Because temperature was stored to two decimal places, an earlier `12.50°C` reading may have been a normal rounded value rather than part of the true flatline.

A consecutive timestamp inspection was therefore required.

### Transition inspection

```sql
SELECT 
    probe_id,
    timestamp_utc,
    raw_temp_c
FROM vw_clean_farm_telemetry
WHERE probe_id = 103
  AND timestamp_utc BETWEEN '2026-06-02 08:30:00' 
                        AND '2026-06-02 10:30:00'
ORDER BY timestamp_utc;
```

This showed that Probe 103 was changing normally before `2026-06-02 09:20:00`, then locked at `12.50°C`.

A second inspection around the end of the suspected period showed that the value remained frozen until `2026-06-02 21:20:00`, before changing again at `2026-06-02 21:30:00`.

### Confirmed finding

Probe 103 flatlined at `12.50°C` from:

- `start`: `2026-06-02 09:20:00`
- `end`: `2026-06-02 21:20:00`

### Principle

Repeated values alone are not always enough to prove a frozen sensor. The analyst must check whether the values are repeated consecutively over time and whether normal variation resumes afterwards.


## Stage 6: Frozen Temperature Flag Added to Clean View

### Purpose

After confirming the frozen temperature period on Probe 103, the clean telemetry view was updated to include a `frozen_temp_flag`.

This flag marks rows that belong to a long consecutive run of identical temperature readings.

For this project, a frozen-temperature candidate was defined as:

- the same `raw_temp_c` value repeated consecutively
- for at least 12 readings
- equivalent to 2 hours of 10-minute sensor readings

### Frozen temperature flag validation

After adding `frozen_temp_flag` to the clean telemetry view, the flag was validated with the following summary query:

```sql
SELECT 
    probe_id,
    raw_temp_c,
    COUNT(*) AS flagged_rows,
    MIN(timestamp_utc) AS flag_start,
    MAX(timestamp_utc) AS flag_end
FROM vw_clean_farm_telemetry
WHERE frozen_temp_flag = TRUE
GROUP BY probe_id, raw_temp_c
ORDER BY flagged_rows DESC;
```

### Result

The validation query returned one frozen temperature episode:

| probe_id | raw_temp_c | flagged_rows | flag_start | flag_end |
|---|---:|---:|---|---|
| 103 | 12.50 | 73 | 2026-06-02 09:20:00 | 2026-06-02 21:20:00 |

### Interpretation

Probe 103 reported `12.50°C` for 73 consecutive 10-minute readings, from `2026-06-02 09:20:00` to `2026-06-02 21:20:00`.

This represents a 12-hour flatline and is likely caused by a frozen sensor, cached reading, or device-level reporting issue rather than real soil temperature behaviour.

The earlier repeated-value check found 74 appearances of `12.50°C`, but the consecutive-run method identified the true flatline as 73 consecutive readings. This demonstrates why consecutive-run logic is stronger than simply counting repeated values.

### Principle

Some sensor anomalies cannot be detected from a single row. They only become visible when readings are evaluated in temporal sequence.

This project performs retrospective quality assurance on historical telemetry. Once a long frozen run is identified, every row in that run is flagged. In a live monitoring system, an alert would only trigger after the threshold had been reached.


## Final Data-Quality Summary

### Overall summary

```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE clean_moisture_pct IS NULL AND raw_moisture_pct IS NOT NULL) AS invalid_moisture_rows,
    COUNT(*) FILTER (WHERE battery_dropout_flag = TRUE) AS battery_dropout_rows,
    COUNT(*) FILTER (WHERE frozen_temp_flag = TRUE) AS frozen_temp_rows
FROM vw_clean_farm_telemetry;
```

### Result

| total_rows | invalid_moisture_rows | battery_dropout_rows | frozen_temp_rows |
|---:|---:|---:|---:|
| 1296 | 2 | 109 | 73 |


### Summary by probe

```sql
SELECT
    probe_id,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE clean_moisture_pct IS NULL AND raw_moisture_pct IS NOT NULL) AS invalid_moisture_rows,
    COUNT(*) FILTER (WHERE battery_dropout_flag = TRUE) AS battery_dropout_rows,
    COUNT(*) FILTER (WHERE frozen_temp_flag = TRUE) AS frozen_temp_rows
FROM vw_clean_farm_telemetry
GROUP BY probe_id
ORDER BY probe_id;
```

### Result

| probe_id | total_rows | invalid_moisture_rows | battery_dropout_rows | frozen_temp_rows |
|---:|---:|---:|---:|---:|
| 101 | 432 | 0 | 109 | 0 |
| 102 | 432 | 2 | 0 | 0 |
| 103 | 432 | 0 | 0 | 73 |


### Interpretation

The final clean view successfully identifies three distinct sensor data-quality issues:

- Probe 101 had 109 rows affected by battery dropout.
- Probe 102 had 2 physically impossible soil moisture readings.
- Probe 103 had 73 rows affected by a frozen temperature flatline.

Each probe represents a different class of telemetry problem: missingness caused by device failure, invalid physical values, and sequence-based sensor freezing.

### Principle

A useful data-quality pipeline should not only clean values, but also preserve the reason why data is unreliable.

This project keeps the raw telemetry intact while adding cleaned fields and diagnostic flags that make later analysis safer and more transparent.v
