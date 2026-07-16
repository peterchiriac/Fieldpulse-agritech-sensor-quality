-- ============================================================
-- Project FieldPulse
-- 02_load_data.sql
-- ============================================================

-- Imports the simulated farm sensor telemetry CSV into the raw
-- staging table.

-- ============================================================
-- Project FieldPulse
-- 02_load_data.sql
-- ============================================================

-- Imports the simulated farm sensor telemetry CSV into the raw
-- staging table.

\copy staging_farm_telemetry (probe_id, timestamp_utc, raw_moisture_pct, raw_temp_c, battery_v) FROM 'data/dirty_farm_sensors.csv' WITH (FORMAT CSV, HEADER TRUE);