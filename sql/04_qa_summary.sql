-- ============================================================
-- Project FieldPulse
-- 04_qa_summary.sql
-- ============================================================

-- Produces overall and probe-level summaries of the data-quality
-- issues identified in the clean telemetry view.


-- Overall QA summary

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


-- QA summary by probe

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