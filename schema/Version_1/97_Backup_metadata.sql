-- ============================================
-- 01_BACKUP_RECOVERY_FRAMEWORK_V2.SQL
-- Purpose: Robust Backup & Recovery Metadata Schema
-- ============================================

BEGIN;

-- Ensure schema exists
DO $$ BEGIN CREATE SCHEMA IF NOT EXISTS dba_admin; EXCEPTION WHEN duplicate_schema THEN END $$;

-- ============================================
-- 1. BACKUP METADATA TABLES
-- ============================================

DROP TABLE IF EXISTS dba_admin.backup_history CASCADE;
CREATE TABLE dba_admin.backup_history (
backup_id SERIAL PRIMARY KEY,
backup_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
backup_type VARCHAR(20) NOT NULL CHECK (backup_type IN ('FULL', 'INCREMENTAL', 'DIFFERENTIAL', 'WAL_SEGMENT')),
backup_method VARCHAR(20) NOT NULL CHECK (backup_method IN ('PHYSICAL', 'LOGICAL')), -- CRITICAL: Distinguish methods
backup_path VARCHAR(500) NOT NULL,
backup_size_mb BIGINT,
database_name VARCHAR(100) NOT NULL,
pg_version VARCHAR(20), -- Track DB version for compatibility
backup_duration_seconds INT,
status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS', 'SUCCESS', 'FAILED', 'DELETED', 'CORRUPTED')),
error_message TEXT,
checksum VARCHAR(64), -- For verification (e.g., sha256)
restored_at TIMESTAMP,
restore_test_status VARCHAR(20), -- 'PASSED', 'FAILED', 'PENDING'
restore_test_db_name VARCHAR(100), -- Name of the sandbox DB used for testing
notes TEXT,
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_backup_date ON dba_admin.backup_history(backup_date DESC);
CREATE INDEX idx_backup_status ON dba_admin.backup_history(status);
CREATE INDEX idx_backup_method ON dba_admin.backup_history(backup_method);

-- ============================================
-- 2. RECOVERY TARGETS (RPO/RTO)
-- ============================================

DROP TABLE IF EXISTS dba_admin.rpo_rto_targets CASCADE;
CREATE TABLE dba_admin.rpo_rto_targets (
target_id SERIAL PRIMARY KEY,
database_name VARCHAR(100) NOT NULL UNIQUE,
rto_minutes INT NOT NULL,
rpo_minutes INT NOT NULL,
backup_frequency_minutes INT NOT NULL,
retention_days INT NOT NULL,
full_backup_schedule VARCHAR(50), -- e.g., '0 2 * * *' (Cron format)
requires_pitr BOOLEAN DEFAULT TRUE, -- Physical backups usually need PITR
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed data
INSERT INTO dba_admin.rpo_rto_targets (database_name, rto_minutes, rpo_minutes, backup_frequency_minutes, retention_days, requires_pitr)
VALUES
('accounting_db', 60, 15, 60, 30, TRUE),
('marketing_db', 120, 240, 1440, 14, FALSE) -- Logical backup, less critical
ON CONFLICT (database_name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP;

-- ============================================
-- 3. HELPER FUNCTIONS (Metadata Only)
-- ============================================

-- Function to START a backup (called by external script before running pg_dump/basebackup)
DROP FUNCTION IF EXISTS dba_admin.start_backup_log(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
CREATE FUNCTION dba_admin.start_backup_log(
p_database_name VARCHAR,
p_backup_type VARCHAR,
p_backup_method VARCHAR,
p_backup_path VARCHAR,
p_pg_version VARCHAR DEFAULT NULL
)
RETURNS INT AS $$
DECLARE
v_backup_id INT;
BEGIN
INSERT INTO dba_admin.backup_history (
database_name, backup_type, backup_method, backup_path, pg_version, status
) VALUES (
p_database_name, p_backup_type, p_backup_method, p_backup_path, p_pg_version, 'IN_PROGRESS'
)
RETURNING backup_id INTO v_backup_id;

RETURN v_backup_id;


END;
$$ LANGUAGE plpgsql;

-- Function to COMPLETE a backup (called by external script after success)
DROP FUNCTION IF EXISTS dba_admin.finish_backup_log(INT, BIGINT, INT, VARCHAR, VARCHAR);
CREATE FUNCTION dba_admin.finish_backup_log(
p_backup_id INT,
p_size_mb BIGINT,
p_duration_seconds INT,
p_checksum VARCHAR DEFAULT NULL,
p_error_msg VARCHAR DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
UPDATE dba_admin.backup_history
SET status = CASE WHEN p_error_msg IS NULL THEN 'SUCCESS' ELSE 'FAILED' END,
backup_size_mb = p_size_mb,
backup_duration_seconds = p_duration_seconds,
checksum = p_checksum,
error_message = p_error_msg
WHERE backup_id = p_backup_id;

IF p_error_msg IS NOT NULL THEN
    RAISE WARNING 'Backup failed for ID %: %', p_backup_id, p_error_msg;
END IF;

END;
$$ LANGUAGE plpgsql;

-- Function to LOG TEST RESTORE
DROP FUNCTION IF EXISTS dba_admin.log_restore_test(INT, VARCHAR, VARCHAR);
CREATE FUNCTION dba_admin.log_restore_test(
p_backup_id INT,
p_test_db_name VARCHAR,
p_status VARCHAR
)
RETURNS VOID AS $$
BEGIN
UPDATE dba_admin.backup_history
SET restored_at = CURRENT_TIMESTAMP,
restore_test_status = p_status,
restore_test_db_name = p_test_db_name
WHERE backup_id = p_backup_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. READINESS DASHBOARD
-- ============================================

DROP FUNCTION IF EXISTS dba_admin.get_backup_recovery_status();
CREATE FUNCTION dba_admin.get_backup_recovery_status()
RETURNS TABLE(
database_name VARCHAR,
last_backup_date TIMESTAMP,
backup_age_minutes INT,
backup_status VARCHAR,
backup_method VARCHAR,
rto_minutes INT,
rpo_minutes INT,
rpo_compliant BOOLEAN,
last_test_date TIMESTAMP,
test_status VARCHAR,
recovery_ready BOOLEAN
) AS $$
BEGIN
RETURN QUERY
SELECT
t.database_name,
MAX(b.backup_date),
EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(b.backup_date)))::INT / 60,
MAX(b.status),
MAX(b.backup_method),
t.rto_minutes,
t.rpo_minutes,
-- RPO Check: Is backup age <= RPO?
(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(b.backup_date)))::INT / 60) <= t.rpo_minutes,
MAX(b.restored_at),
MAX(b.restore_test_status),
-- Recovery Ready: Status Success AND Tested recently (within 7 days)
CASE
WHEN MAX(b.status) = 'SUCCESS'
AND MAX(b.restore_test_status) = 'PASSED'
AND MAX(b.restored_at) > CURRENT_TIMESTAMP - INTERVAL '7 days'
THEN TRUE
ELSE FALSE
END
FROM dba_admin.rpo_rto_targets t
LEFT JOIN dba_admin.backup_history b ON t.database_name = b.database_name
GROUP BY t.database_name, t.rto_minutes, t.rpo_minutes;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. RETENTION POLICY CONFIG
-- ============================================

DROP TABLE IF EXISTS dba_admin.retention_policy CASCADE;
CREATE TABLE dba_admin.retention_policy(
retention_id SERIAL PRIMARY KEY,
database_name VARCHAR(100) NOT NULL,
retention_days INT NOT NULL DEFAULT 30,
retention_weeks INT, -- For weekly snapshots
retention_months INT, -- For monthly snapshots
keep_daily INT DEFAULT 7, -- Keep last N daily
keep_weekly INT DEFAULT 4, -- Keep last N weekly
keep_monthly INT DEFAULT 12, -- Keep last N monthly
reason TEXT,
updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Example: Grandfather-Father-Son (GFS) strategy
INSERT INTO dba_admin.retention_policy (database_name, keep_daily, keep_weekly, keep_monthly, reason)
VALUES ('accounting_db', 7, 4, 12, 'GFS Strategy for Compliance');

COMMIT;

-- ============================================
-- EXTERNAL SCRIPT EXAMPLE (Bash)
-- ============================================
/*
This SQL schema is designed to be driven by an external script.
Do NOT try to run pg_dump inside PL/pgSQL.

## Example Bash Wrapper:

#!/bin/bash
DB_NAME="accounting_db"
BACKUP_PATH="/var/lib/postgresql/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_PATH}/${DB_NAME}_${TIMESTAMP}.dump"

# 1. Log Start to SQL

BACKUP_ID=$(psql -d postgres -t -c "SELECT dba_admin.start_backup_log('${DB_NAME}', 'FULL', 'LOGICAL', '${BACKUP_FILE}', '15.4');")

# 2. Run Actual Backup

START_TIME=$(date +%s)
pg_dump -Fc -d "$DB_NAME" -f "$BACKUP_FILE"
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
SIZE=$(du -m "$BACKUP_FILE" | cut -f1)

# 3. Log Finish to SQL

*/

SELECT 'Backup & Recovery Framework V2 Ready. Use external scripts to trigger actual backups.' AS status;