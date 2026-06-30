-- ============================================================
-- Project FieldPulse
-- Agritech Sensor Data Quality Pipeline
-- ============================================================

-- This script creates the raw staging table, imports farm sensor
-- telemetry data, and builds a reusable clean view with data-quality
-- flags for invalid moisture readings, battery dropout, and frozen
-- temperature sensor behaviour.


-- ============================================================
-- 1. Raw staging table
-- ============================================================

DROP TABLE IF EXISTS staging_farm_telemetry CASCADE;

CREATE TABLE staging_farm_telemetry (
    probe_id INT NOT NULL,
    timestamp_utc TIMESTAMP NOT NULL,
    raw_moisture_pct NUMERIC(5,2),
    raw_temp_c NUMERIC(5,2),
    battery_v NUMERIC(4,2) NOT NULL
);


-- ============================================================
-- 2. Index for probe/time queries
-- ============================================================

CREATE INDEX idx_telemetry_probe_time 
ON staging_farm_telemetry (probe_id, timestamp_utc DESC);


-- ============================================================
-- 3. Import raw CSV data
-- ============================================================

-- NOTE:
-- This uses psql's \copy command, so this script should be run
-- from psql rather than directly through a generic SQL client.

\copy staging_farm_telemetry(probe_id, timestamp_utc, raw_moisture_pct, raw_temp_c, battery_v) FROM '/Users/peter/Desktop/pete_writes_code/field_pulse/dirty_farm_sensors.csv' DELIMITER ',' CSV HEADER;


-- ============================================================
-- 4. Create clean telemetry view
-- ============================================================

DROP VIEW IF EXISTS vw_clean_farm_telemetry;

CREATE VIEW vw_clean_farm_telemetry AS
WITH base AS (
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

    FROM staging_farm_telemetry
),

temp_sequence AS (
    SELECT
        *,
        CASE
            WHEN raw_temp_c IS NOT NULL
             AND raw_temp_c = LAG(raw_temp_c) OVER (
                PARTITION BY probe_id
                ORDER BY timestamp_utc
             )
            THEN 0
            ELSE 1
        END AS new_temp_run_flag
    FROM base
),

temp_run_groups AS (
    SELECT
        *,
        SUM(new_temp_run_flag) OVER (
            PARTITION BY probe_id
            ORDER BY timestamp_utc
        ) AS temp_run_id
    FROM temp_sequence
),

temp_run_summary AS (
    SELECT
        probe_id,
        temp_run_id,
        COUNT(*) AS temp_run_length
    FROM temp_run_groups
    WHERE raw_temp_c IS NOT NULL
    GROUP BY probe_id, temp_run_id
)

SELECT
    trg.probe_id,
    trg.timestamp_utc,
    trg.raw_moisture_pct,
    trg.clean_moisture_pct,
    trg.raw_temp_c,
    trg.battery_v,
    trg.battery_dropout_flag,

    CASE
        WHEN trs.temp_run_length >= 12
        THEN TRUE
        ELSE FALSE
    END AS frozen_temp_flag

FROM temp_run_groups trg
LEFT JOIN temp_run_summary trs
    ON trg.probe_id = trs.probe_id
   AND trg.temp_run_id = trs.temp_run_id;


-- ============================================================
-- 5. Final QA summary: overall
-- ============================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE clean_moisture_pct IS NULL 
          AND raw_moisture_pct IS NOT NULL
    ) AS invalid_moisture_rows,
    COUNT(*) FILTER (
        WHERE battery_dropout_flag = TRUE
    ) AS battery_dropout_rows,
    COUNT(*) FILTER (
        WHERE frozen_temp_flag = TRUE
    ) AS frozen_temp_rows
FROM vw_clean_farm_telemetry;


-- ============================================================
-- 6. Final QA summary: by probe
-- ============================================================

SELECT
    probe_id,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE clean_moisture_pct IS NULL 
          AND raw_moisture_pct IS NOT NULL
    ) AS invalid_moisture_rows,
    COUNT(*) FILTER (
        WHERE battery_dropout_flag = TRUE
    ) AS battery_dropout_rows,
    COUNT(*) FILTER (
        WHERE frozen_temp_flag = TRUE
    ) AS frozen_temp_rows
FROM vw_clean_farm_telemetry
GROUP BY probe_id
ORDER BY probe_id;