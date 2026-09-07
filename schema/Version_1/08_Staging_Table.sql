SELECT 'Staging table schema start!' as  Status;

BEGIN;

-- 1. STAGING TABLE
CREATE TABLE IF NOT EXISTS Staging.stg_ar_imports(
    id BIGSERIAL PRIMARY KEY,
    session_id INT,
    -- ID
    invoice_code TEXT,
    customer_code TEXT,
    client_code TEXT,
    
    -- measure
    amount TEXT,
    
    -- meta data
    invoice_date TEXT,
    due_date TEXT,
    status TEXT,
    validation_status VARCHAR(20),
    validation_errors TEXT,
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Staging.stg_ar_lines(
    id BIGSERIAL PRIMARY KEY,
    session_id INT,
    -- ID
    invoice_code TEXT,
    product_code TEXT,
    -- Measure
    quantity TEXT,
    discount TEXT,
    -- meta data
    validation_status VARCHAR(20),
    validation_errors TEXT,
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    
);

-- 2. WORKFLOW TABLE
CREATE TABLE IF NOT EXISTS Staging.import_workflows (
    session_id INT,
    staging_record_id BIGINT,
    staging_table VARCHAR(50),
    previous_state VARCHAR(50),
    new_state VARCHAR(50),
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- 3. APPROVAL TABLE
CREATE TABLE IF NOT EXISTS Staging.import_approvals (
    session_id INT,
    staging_record_id BIGINT,   

    approval_level SMALLINT,
    approval_status VARCHAR(20),

    approved_by VARCHAR(100),
    approved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    comments TEXT
);

COMMIT;

SELECT '08 Staging table schema complete!' as  Status;