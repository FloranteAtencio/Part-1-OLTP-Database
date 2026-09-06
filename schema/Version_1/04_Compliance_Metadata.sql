-- ============================================
-- COMPLIANCE METADATA SCHEMA
-- Purpose: Add compliance & privacy tracking to all tables
-- Level 6: Privacy Principles Implementation
-- ============================================

SELECT 'Compliance Metadata Schema Start!' as Status;

BEGIN;

-- ============================================
-- 1. DATA CLASSIFICATION TYPES
-- ============================================
DROP TYPE IF EXISTS data_classification_enum CASCADE;
CREATE TYPE data_classification_enum AS ENUM (
    'PUBLIC',           -- No sensitivity restrictions
    'INTERNAL',         -- For organization use only
    'CONFIDENTIAL',     -- Restricted to authorized users
    'SENSITIVE'         -- Highly restricted (PII, Financial, etc)
);

-- ============================================
-- 2. DATA RETENTION PERIODS
-- ============================================
DROP TYPE IF EXISTS retention_period_enum CASCADE;
CREATE TYPE retention_period_enum AS ENUM (
    'PERMANENT',        -- Keep indefinitely (e.g., tax records)
    '7_YEARS',          -- 7 years (financial compliance)
    '5_YEARS',          -- 5 years (general business records)
    '3_YEARS',          -- 3 years (operational data)
    '1_YEAR',           -- 1 year (temporary operational)
    '90_DAYS',          -- 90 days (logs, cache)
    '30_DAYS'           -- 30 days (temporary, session data)
);

-- ============================================
-- 3. COMPLIANCE METADATA TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.compliance_metadata CASCADE;
CREATE TABLE Finance.compliance_metadata (
    metadata_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL UNIQUE,
    table_description TEXT,
    data_classification data_classification_enum NOT NULL,
    retention_period retention_period_enum NOT NULL,
    requires_encryption BOOLEAN DEFAULT FALSE,
    requires_audit_log BOOLEAN DEFAULT TRUE,
    pii_present BOOLEAN DEFAULT FALSE,
    financial_data BOOLEAN DEFAULT FALSE,
    data_steward VARCHAR(255),
    compliance_notes TEXT,
    gdpr_applicable BOOLEAN DEFAULT FALSE,
    ph_pdata_applicable BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 4. COLUMN CLASSIFICATION TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.column_classification CASCADE;
CREATE TABLE Finance.column_classification (
    classification_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    column_name VARCHAR(255) NOT NULL,
    data_classification data_classification_enum NOT NULL,
    is_pii BOOLEAN DEFAULT FALSE,
    is_financial BOOLEAN DEFAULT FALSE,
    requires_encryption BOOLEAN DEFAULT FALSE,
    masking_required BOOLEAN DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(table_name, column_name)
);

-- ============================================
-- 5. ENHANCED EVENT LOG (with compliance fields)
-- ============================================
-- NOTE: Enhance existing Finance.event_log table
DROP TABLE IF EXISTS Finance.event_log_enhanced CASCADE;
CREATE TABLE Finance.event_log_enhanced (
    event_id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    table_name VARCHAR(255),
    operation VARCHAR(10),  -- INSERT, UPDATE, DELETE
    record_id BIGINT,
    user_id VARCHAR(255),
    user_role VARCHAR(100),
    old_values JSONB,
    new_values JSONB,
    payload JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING',
    compliance_level data_classification_enum,
    idempotency_key TEXT UNIQUE NOT NULL,
    hash_chain TEXT,  -- For audit chain verification
    ip_address INET,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    archived_at TIMESTAMP,
    CONSTRAINT event_log_status_check CHECK (status IN ('PENDING', 'PROCESSED', 'ARCHIVED', 'FAILED'))
);

-- Create index for faster querying
CREATE INDEX idx_event_log_created_at ON Finance.event_log_enhanced(created_at DESC);
CREATE INDEX idx_event_log_table_name ON Finance.event_log_enhanced(table_name);
CREATE INDEX idx_event_log_user_id ON Finance.event_log_enhanced(user_id);
CREATE INDEX idx_event_log_compliance ON Finance.event_log_enhanced(compliance_level);

-- ============================================
-- 6. AUDIT TRAIL TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.audit_trail CASCADE;
CREATE TABLE Finance.audit_trail (
    audit_id BIGSERIAL PRIMARY KEY,
    transaction_id BIGINT REFERENCES Finance.transactions(transaction_id) ON DELETE NO ACTION,
    event_type VARCHAR(50) NOT NULL,
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actor VARCHAR(255),
    actor_role VARCHAR(100),
    action_details TEXT,
    previous_state JSONB,
    current_state JSONB,
    status VARCHAR(20),
    compliance_status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_trail_transaction ON Finance.audit_trail(transaction_id);
CREATE INDEX idx_audit_trail_created_at ON Finance.audit_trail(created_at DESC);

-- ============================================
-- 7. DATA ACCESS LOG TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.data_access_log CASCADE;
CREATE TABLE Finance.data_access_log (
    access_id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    user_role VARCHAR(100),
    table_name VARCHAR(255) NOT NULL,
    operation VARCHAR(10),  -- SELECT, INSERT, UPDATE, DELETE
    record_id BIGINT,
    access_granted BOOLEAN,
    access_reason TEXT,
    compliance_check_result VARCHAR(50),
    ip_address INET,
    session_id TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_data_access_user ON Finance.data_access_log(user_id);
CREATE INDEX idx_data_access_table ON Finance.data_access_log(table_name);
CREATE INDEX idx_data_access_created ON Finance.data_access_log(created_at DESC);

-- ============================================
-- 8. FIELD-LEVEL ENCRYPTION KEYS TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.encryption_keys CASCADE;
CREATE TABLE Finance.encryption_keys (
    key_id BIGSERIAL PRIMARY KEY,
    key_name VARCHAR(255) NOT NULL UNIQUE,
    table_name VARCHAR(255) NOT NULL,
    column_name VARCHAR(255) NOT NULL,
    encryption_algorithm VARCHAR(50),  -- AES-256, etc
    key_rotation_enabled BOOLEAN DEFAULT TRUE,
    key_rotation_interval_days INT DEFAULT 90,
    last_rotated_at TIMESTAMP,
    next_rotation_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(table_name, column_name)
);

-- ============================================
-- 9. DATA RETENTION POLICY TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.retention_policy CASCADE;
CREATE TABLE Finance.retention_policy (
    policy_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    retention_period retention_period_enum NOT NULL,
    archive_location VARCHAR(500),
    delete_method VARCHAR(50),  -- SOFT_DELETE, HARD_DELETE, ARCHIVE
    last_purge_date DATE,
    next_purge_date DATE,
    purge_enabled BOOLEAN DEFAULT TRUE,
    policy_description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(table_name)
);

-- ============================================
-- 10. CONSENT & PII MANAGEMENT TABLE
-- ============================================
DROP TABLE IF EXISTS Finance.pii_consent CASCADE;
CREATE TABLE Finance.pii_consent (
    consent_id BIGSERIAL PRIMARY KEY,
    client_id INT NOT NULL REFERENCES Finance.clients(client_id) ON DELETE NO ACTION,
    consent_type VARCHAR(100),  -- MARKETING, ANALYTICS, PROCESSING, etc
    consent_given BOOLEAN NOT NULL,
    consent_date TIMESTAMP NOT NULL,
    consent_version VARCHAR(50),  -- Track which version of policy
    withdrawal_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_pii_consent_client ON Finance.pii_consent(client_id);

-- ============================================
-- 11. COMPLIANCE AUDIT CHECKLIST
-- ============================================
DROP TABLE IF EXISTS Finance.compliance_checklist CASCADE;
CREATE TABLE Finance.compliance_checklist (
    checklist_id BIGSERIAL PRIMARY KEY,
    framework VARCHAR(100),  -- GDPR, PH_PDATA, ISO_27001, etc
    requirement_id VARCHAR(50),
    requirement_description TEXT,
    compliance_level VARCHAR(50),
    implementation_status VARCHAR(50),  -- NOT_STARTED, IN_PROGRESS, COMPLETE, REMEDIATION
    evidence_location TEXT,
    responsible_party VARCHAR(255),
    target_completion_date DATE,
    actual_completion_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 12. SECURITY INCIDENT LOG
-- ============================================
DROP TABLE IF EXISTS Finance.security_incident CASCADE;
CREATE TABLE Finance.security_incident (
    incident_id BIGSERIAL PRIMARY KEY,
    incident_type VARCHAR(100),  -- UNAUTHORIZED_ACCESS, DATA_BREACH, etc
    severity VARCHAR(20),  -- CRITICAL, HIGH, MEDIUM, LOW
    description TEXT,
    affected_tables VARCHAR[],
    affected_records_count INT,
    detected_at TIMESTAMP,
    detected_by VARCHAR(255),
    reported_at TIMESTAMP,
    investigation_status VARCHAR(50),
    resolution_status VARCHAR(50),
    resolution_date TIMESTAMP,
    remediation_actions TEXT,
    notification_sent_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 13. BULK OPERATIONS AUDIT
-- ============================================
DROP TABLE IF EXISTS Finance.bulk_operations_audit CASCADE;
CREATE TABLE Finance.bulk_operations_audit (
    bulk_op_id BIGSERIAL PRIMARY KEY,
    operation_type VARCHAR(50),  -- BULK_INSERT, BULK_UPDATE, BULK_DELETE, EXPORT, IMPORT
    table_name VARCHAR(255),
    records_affected INT,
    operation_initiated_by VARCHAR(255),
    operation_status VARCHAR(50),
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    total_time_seconds INT,
    validation_passed BOOLEAN,
    compliance_check_passed BOOLEAN,
    export_format VARCHAR(50),  -- CSV, JSON, XML
    export_encrypted BOOLEAN DEFAULT FALSE,
    export_destination VARCHAR(500),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- POPULATE COMPLIANCE METADATA
-- ============================================

-- Sensitive Tables
INSERT INTO Finance.compliance_metadata 
(table_name, table_description, data_classification, retention_period, requires_encryption, pii_present, financial_data, data_steward, gdpr_applicable, ph_pdata_applicable)
VALUES
('clients', 'Client master data with contact information', 'SENSITIVE', '7_YEARS', TRUE, TRUE, FALSE, 'Finance Manager', TRUE, TRUE),
('transactions', 'Financial transactions core table', 'CONFIDENTIAL', '7_YEARS', FALSE, FALSE, TRUE, 'Finance Manager', FALSE, FALSE),
('customers', 'Customer contact and billing information', 'SENSITIVE', '3_YEARS', TRUE, TRUE, FALSE, 'Sales Manager', TRUE, TRUE),
('vendors', 'Supplier/vendor contact information', 'CONFIDENTIAL', '5_YEARS', FALSE, FALSE, FALSE, 'Procurement Manager', FALSE, FALSE),
('charts', 'Chart of Accounts for clients', 'CONFIDENTIAL', 'PERMANENT', FALSE, FALSE, TRUE, 'Finance Manager', FALSE, FALSE),
('account_receivables', 'AR transactions', 'CONFIDENTIAL', '7_YEARS', FALSE, FALSE, TRUE, 'Finance Manager', FALSE, FALSE),
('account_payables', 'AP transactions', 'CONFIDENTIAL', '7_YEARS', FALSE, FALSE, TRUE, 'Finance Manager', FALSE, FALSE),
('journals', 'Double-entry journal entries', 'CONFIDENTIAL', '7_YEARS', FALSE, FALSE, TRUE, 'Finance Manager', FALSE, FALSE),
('products', 'Product master data', 'INTERNAL', '5_YEARS', FALSE, FALSE, FALSE, 'Inventory Manager', FALSE, FALSE),
('warehouses', 'Warehouse locations', 'INTERNAL', 'PERMANENT', FALSE, FALSE, FALSE, 'Inventory Manager', FALSE, FALSE),
('event_log', 'Transaction event logging', 'SENSITIVE', '7_YEARS', FALSE, FALSE, FALSE, 'Compliance Officer', TRUE, TRUE),
('audit_trail', 'Audit trail for transactions', 'SENSITIVE', '7_YEARS', FALSE, FALSE, FALSE, 'Compliance Officer', TRUE, TRUE);

-- Populate Column Classifications (HIGH PRIORITY COLUMNS)
INSERT INTO Finance.column_classification 
(table_name, column_name, data_classification, is_pii, is_financial, requires_encryption, masking_required, description)
VALUES
-- Clients table
('clients', 'client_id', 'INTERNAL', FALSE, FALSE, FALSE, FALSE, 'Client identifier'),
('clients', 'info', 'SENSITIVE', TRUE, FALSE, TRUE, TRUE, 'Client contact info - contains email, phone, address'),

-- Customers table
('customers', 'customer_id', 'INTERNAL', FALSE, FALSE, FALSE, FALSE, 'Customer identifier'),
('customers', 'customer_name', 'SENSITIVE', TRUE, FALSE, TRUE, TRUE, 'Customer full name - PII'),
('customers', 'email', 'SENSITIVE', TRUE, FALSE, TRUE, TRUE, 'Customer email - PII'),
('customers', 'contact_info', 'SENSITIVE', TRUE, FALSE, TRUE, TRUE, 'Customer phone - PII'),
('customers', 'address', 'SENSITIVE', TRUE, FALSE, TRUE, TRUE, 'Customer address - PII'),

-- Transactions table
('transactions', 'transaction_id', 'INTERNAL', FALSE, TRUE, FALSE, FALSE, 'Transaction identifier'),
('transactions', 'description', 'CONFIDENTIAL', FALSE, TRUE, FALSE, FALSE, 'Transaction description'),
('transactions', 'idempotency_key', 'SENSITIVE', FALSE, FALSE, TRUE, FALSE, 'Prevents duplicate transactions'),

-- Account Receivables
('account_receivables', 'receivable_id', 'INTERNAL', FALSE, TRUE, FALSE, FALSE, 'AR identifier'),
('account_receivables', 'amount', 'CONFIDENTIAL', FALSE, TRUE, FALSE, FALSE, 'AR amount'),

-- Account Payables
('account_payables', 'payable_id', 'INTERNAL', FALSE, TRUE, FALSE, FALSE, 'AP identifier'),
('account_payables', 'amount', 'CONFIDENTIAL', FALSE, TRUE, FALSE, FALSE, 'AP amount');

COMMIT;

SELECT 'Compliance Metadata Schema Complete!' as Status;
