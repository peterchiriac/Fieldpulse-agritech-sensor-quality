-- ============================================================
-- Project FieldPulse
-- 01_create_staging.sql
-- ============================================================

-- Creates the raw staging table used to ingest farm sensor telemetry.
-- This table preserves the original observations before any cleaning
-- or quality assessment is applied.

DROP TABLE IF EXISTS staging_farm_telemetry CASCADE;

CREATE TABLE staging_farm_telemetry (
    ingestion_id BIGSERIAL PRIMARY KEY,
    probe_id INT NOT NULL,
    timestamp_utc TIMESTAMPTZ NOT NULL,
    raw_moisture_pct NUMERIC(5,2),
    raw_temp_c NUMERIC(5,2),
    battery_v NUMERIC(4,2) NOT NULL
);

-- Index supporting probe-level chronological queries.

CREATE INDEX idx_telemetry_probe_time

ON staging_farm_telemetry (probe_id, timestamp_utc DESC);