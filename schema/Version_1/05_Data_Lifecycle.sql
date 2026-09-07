-- ============================================
-- DATA LIFECYCLE & RETENTION POLICY SCHEMA
-- Purpose: Manage data retention, archival, and deletion
-- Level 4: Data Lifecycle Implementation
-- ============================================

SELECT 'Data Lifecycle Schema Start!' as Status;

BEGIN;

-- ============================================
-- 1. RETENTION PERIOD TYPES
-- ============================================
DROP TYPE IF EXISTS retention_action_enum CASCADE;
CREATE TYPE retention_action_enum AS ENUM (
    'ACTIVE',          -- Currently in use
    'WARM_STORAGE',    -- Moved to warm storage (slower access)
    'COLD_STORAGE',    -- Archived to cold storage (very slow access)
    'SCHEDULED_DELETE',-- Marked for deletion
    'DELETED'          -- Deleted from system
);

-- ============================================
-- 2. DATA RETENTION POLICY TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.data_retention_policy CASCADE;
CREATE TABLE Finance.data_retention_policy (
    policy_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL UNIQUE,
    table_description TEXT,
    retention_period_days INT NOT NULL,
    retention_category VARCHAR(100),  -- PERMANENT, FINANCIAL, OPERATIONAL, TEMPORARY, LOGS
    archive_after_days INT,            -- When to archive (before delete)
    warm_storage_after_days INT,       -- When to move to slower storage
    delete_enabled BOOLEAN DEFAULT FALSE,
    delete_method VARCHAR(50),         -- SOFT_DELETE (flag), HARD_DELETE (remove), ARCHIVE_ONLY
    soft_delete_column VARCHAR(100),   -- Column name if using soft delete (e.g., 'is_deleted', 'deleted_at')
    archive_table_name VARCHAR(255),   -- Name of archive table
    archive_location VARCHAR(500),     -- Physical location or S3 path
    last_archive_date DATE,
    last_deletion_date DATE,
    next_archive_date DATE,
    next_deletion_date DATE,
    is_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    policy_notes TEXT
);

-- ============================================
-- 3. DATA LIFECYCLE EVENTS TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.data_lifecycle_events CASCADE;
CREATE TABLE Finance.data_lifecycle_events (
    event_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    action retention_action_enum NOT NULL,
    records_affected BIGINT,
    action_triggered_by VARCHAR(255),  -- System, Manual, Scheduled, etc
    trigger_reason VARCHAR(500),
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    total_duration_seconds INT,
    status VARCHAR(50),                -- SUCCESS, FAILED, IN_PROGRESS, PARTIAL
    error_message TEXT,
    archive_location_used VARCHAR(500),
    backup_created BOOLEAN DEFAULT FALSE,
    backup_location VARCHAR(500),
    validation_passed BOOLEAN DEFAULT TRUE,
    rollback_performed BOOLEAN DEFAULT FALSE,
    retention_policy_id BIGINT REFERENCES Finance.data_retention_policy(policy_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lifecycle_table_name ON Finance.data_lifecycle_events(table_name);
CREATE INDEX idx_lifecycle_status ON Finance.data_lifecycle_events(status);
CREATE INDEX idx_lifecycle_action ON Finance.data_lifecycle_events(action);
CREATE INDEX idx_lifecycle_created_at ON Finance.data_lifecycle_events(created_at DESC);

-- ============================================
-- 4. ARCHIVE TABLES METADATA
-- ============================================
DROP TABLE IF EXISTS Finance.archive_metadata CASCADE;
CREATE TABLE Finance.archive_metadata (
    archive_id BIGSERIAL PRIMARY KEY,
    source_table_name VARCHAR(255) NOT NULL,
    archive_table_name VARCHAR(255) NOT NULL,
    archive_date DATE NOT NULL,
    records_archived BIGINT,
    archive_size_mb NUMERIC(12,2),
    archive_location VARCHAR(500),
    archive_format VARCHAR(50),        -- SQL_DUMP, CSV, PARQUET, COMPRESSED
    compression_used VARCHAR(50),      -- GZIP, ZIP, BZIP2, etc
    checksum VARCHAR(255),             -- Hash to verify integrity
    retention_until_date DATE,         -- When to delete archive
    can_be_purged BOOLEAN DEFAULT FALSE,
    is_encrypted BOOLEAN DEFAULT FALSE,
    encryption_key_id VARCHAR(255),
    index_created BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    purged_at TIMESTAMP
);

CREATE INDEX idx_archive_source_table ON Finance.archive_metadata(source_table_name);
CREATE INDEX idx_archive_date ON Finance.archive_metadata(archive_date DESC);

-- ============================================
-- 5. SOFT DELETE TRACKING TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.deleted_records_tracking CASCADE;
CREATE TABLE Finance.deleted_records_tracking (
    tracking_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    record_id BIGINT NOT NULL,
    deleted_by VARCHAR(255),
    delete_reason VARCHAR(500),
    deleted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hard_delete_after DATE,           -- When record can be permanently deleted
    is_recoverable BOOLEAN DEFAULT TRUE,
    recovery_attempted BOOLEAN DEFAULT FALSE,
    recovery_successful BOOLEAN DEFAULT FALSE,
    backup_location VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_deleted_table_name ON Finance.deleted_records_tracking(table_name);
CREATE INDEX idx_deleted_deleted_at ON Finance.deleted_records_tracking(deleted_at DESC);
CREATE INDEX idx_deleted_hard_delete_after ON Finance.deleted_records_tracking(hard_delete_after);

-- ============================================
-- 6. LIFECYCLE SCHEDULE TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.lifecycle_schedule CASCADE;
CREATE TABLE Finance.lifecycle_schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    policy_id BIGINT NOT NULL REFERENCES Finance.data_retention_policy(policy_id),
    schedule_type VARCHAR(50),        -- DAILY, WEEKLY, MONTHLY, QUARTERLY, YEARLY, CUSTOM
    day_of_week INT,                   -- 0=Sunday, 6=Saturday (for WEEKLY)
    day_of_month INT,                  -- 1-31 (for MONTHLY)
    month_of_year INT,                 -- 1-12 (for YEARLY)
    time_of_day TIME,                  -- What time to run (e.g., '02:00:00')
    timezone VARCHAR(50),              -- 'UTC', 'Asia/Manila', etc
    is_active BOOLEAN DEFAULT TRUE,
    last_run_at TIMESTAMP,
    next_run_at TIMESTAMP,
    last_run_status VARCHAR(50),
    notification_email VARCHAR(255),   -- Email for completion notification
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 7. RETENTION EXCEPTION TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.retention_exceptions CASCADE;
CREATE TABLE Finance.retention_exceptions (
    exception_id BIGSERIAL PRIMARY KEY,
    policy_id BIGINT NOT NULL REFERENCES Finance.data_retention_policy(policy_id),
    table_name VARCHAR(255) NOT NULL,
    record_id BIGINT,
    exception_type VARCHAR(100),       -- LEGAL_HOLD, LITIGATION, REGULATORY, AUDIT
    reason TEXT,
    requested_by VARCHAR(255),
    requested_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_by VARCHAR(255),
    approved_date TIMESTAMP,
    hold_until_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_exception_table_name ON Finance.retention_exceptions(table_name);
CREATE INDEX idx_exception_type ON Finance.retention_exceptions(exception_type);

-- ============================================
-- 8. DATA LINEAGE FOR LIFECYCLE
-- ============================================
DROP TABLE IF EXISTS Finance.lifecycle_lineage CASCADE;
CREATE TABLE Finance.lifecycle_lineage (
    lineage_id BIGSERIAL PRIMARY KEY,
    source_table VARCHAR(255) NOT NULL,
    source_schema VARCHAR(255) DEFAULT 'Finance',
    record_id BIGINT,
    lifecycle_stage VARCHAR(50),       -- ACTIVE, WARM, COLD, DELETED, ARCHIVED
    parent_record_table VARCHAR(255),  -- If data comes from another table
    parent_record_id BIGINT,
    created_date TIMESTAMP,
    archived_date TIMESTAMP,
    deleted_date TIMESTAMP,
    is_currently_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lineage_source_table ON Finance.lifecycle_lineage(source_table);
CREATE INDEX idx_lineage_record_id ON Finance.lifecycle_lineage(source_table, record_id);

-- ============================================
-- 9. COMPLIANCE HOLD TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.compliance_hold CASCADE;
CREATE TABLE Finance.compliance_hold (
    hold_id BIGSERIAL PRIMARY KEY,
    hold_name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    hold_type VARCHAR(100),            -- LITIGATION, REGULATORY, AUDIT, INVESTIGATION
    hold_start_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hold_end_date TIMESTAMP,
    requested_by VARCHAR(255),
    authorized_by VARCHAR(255),
    affected_tables VARCHAR[],         -- Array of table names affected
    affected_records_count BIGINT,
    is_active BOOLEAN DEFAULT TRUE,
    compliance_reference VARCHAR(255), -- Reference to legal case, regulation, etc
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 10. PURGE EXECUTION LOG
-- ============================================
DROP TABLE IF EXISTS Finance.purge_execution_log CASCADE;
CREATE TABLE Finance.purge_execution_log (
    purge_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    purge_type VARCHAR(50),            -- ARCHIVE, DELETE, BOTH
    start_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP,
    records_processed BIGINT,
    records_archived BIGINT DEFAULT 0,
    records_deleted BIGINT DEFAULT 0,
    records_failed BIGINT DEFAULT 0,
    purge_status VARCHAR(50),          -- IN_PROGRESS, SUCCESS, FAILED, PARTIAL
    error_details TEXT,
    pre_purge_record_count BIGINT,
    post_purge_record_count BIGINT,
    backup_created BOOLEAN DEFAULT FALSE,
    backup_verification_passed BOOLEAN DEFAULT FALSE,
    total_duration_seconds INT,
    purge_policy_id BIGINT REFERENCES Finance.data_retention_policy(policy_id),
    executed_by VARCHAR(255),
    approval_required BOOLEAN DEFAULT FALSE,
    approved_by VARCHAR(255),
    approved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_purge_table_name ON Finance.purge_execution_log(table_name);
CREATE INDEX idx_purge_status ON Finance.purge_execution_log(purge_status);
CREATE INDEX idx_purge_created_at ON Finance.purge_execution_log(created_at DESC);

-- ============================================
-- POPULATE RETENTION POLICIES
-- ============================================

-- FINANCIAL DATA - 7 years (regulatory requirement)
INSERT INTO Finance.data_retention_policy 
(table_name, table_description, retention_period_days, retention_category, 
 archive_after_days, warm_storage_after_days, delete_enabled, delete_method, 
 soft_delete_column, archive_table_name, policy_notes)
VALUES
('transactions', 'Financial transactions core', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'transactions_archive', 'Must keep 7 years for tax/audit compliance'),
('journals', 'Double-entry journal entries', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'journals_archive', 'Must keep 7 years for financial audits'),
('account_receivables', 'AR transactions', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'account_receivables_archive', 'Keep 7 years per accounting standards'),
('account_payables', 'AP transactions', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'account_payables_archive', 'Keep 7 years per accounting standards'),
('ar_ext', 'AR extension details', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'ar_ext_archive', 'Keep 7 years with AR records'),
('ap_ext', 'AP extension details', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'ap_ext_archive', 'Keep 7 years with AP records'),

-- OPERATIONAL DATA - 3 years
('inventory_audits', 'Inventory audit records', 1095, 'OPERATIONAL', 180, 365, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'inventory_audits_archive', 'Keep 3 years for operational history'),
('inventory_transfers', 'Inventory transfer records', 1095, 'OPERATIONAL', 180, 365, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'inventory_transfers_archive', 'Keep 3 years for history'),
('purchase_returns', 'Purchase returns', 1095, 'OPERATIONAL', 180, 365, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'purchase_returns_archive', 'Keep 3 years'),
('sale_returns', 'Sales returns', 1095, 'OPERATIONAL', 180, 365, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'sale_returns_archive', 'Keep 3 years'),

-- CUSTOMER DATA - 3-5 years (with GDPR delete option)
('customers', 'Customer contact data', 1825, 'OPERATIONAL', 365, 730, TRUE, 'SOFT_DELETE', 
 'is_deleted', 'customers_archive', 'Delete on request (GDPR); 5 years default'),
('vendors', 'Vendor contact data', 1825, 'OPERATIONAL', 365, 730, FALSE, 'ARCHIVE_ONLY', 
 NULL, 'vendors_archive', 'Keep as reference; archive old records'),

-- REFERENCE DATA - PERMANENT
('clients', 'Client master data', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - master data'),
('charts', 'Chart of accounts', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - reference data'),
('products', 'Product master data', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - reference data'),
('warehouses', 'Warehouse locations', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - reference data'),

-- AUDIT/LOGS - 7 years
('event_log', 'Transaction event logs', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'event_log_archive', 'Keep 7 years for audit compliance'),

-- METADATA - PERMANENT
('coa_templates', 'COA template definitions', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - configuration'),
('coa_template_accounts', 'COA template accounts', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - configuration'),
('account_roles', 'Account roles', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - configuration'),
('account_properties', 'Account properties', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - configuration'),
('tax_types', 'Tax type definitions', NULL, 'PERMANENT', NULL, NULL, FALSE, NULL, 
 NULL, NULL, 'Keep permanently - configuration'),
('operations', 'Product operations', 1095, 'OPERATIONAL', 180, 365, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'operations_archive', 'Keep 3 years for reference'),
('ar_product_line', 'AR line items', 2555, 'FINANCIAL', 365, 730, TRUE, 'ARCHIVE_ONLY', 
 NULL, 'ar_product_line_archive', 'Keep 7 years with AR records');

COMMIT;

SELECT 'Data Lifecycle Schema Complete!' as Status;
