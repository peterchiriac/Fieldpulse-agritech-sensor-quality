-- ============================================================
-- Project FieldPulse
-- 03_create_clean_view.sql
-- ============================================================

-- Creates the analytical telemetry view by applying data-quality
-- rules to the raw staging table. The view preserves the original
-- measurements while identifying invalid moisture readings,
-- battery-related missingness, and frozen temperature sensor behaviour.


DROP VIEW IF EXISTS vw_clean_farm_telemetry;

CREATE VIEW vw_clean_farm_telemetry AS
WITH prepared_readings AS (
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
    FROM prepared_readings
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