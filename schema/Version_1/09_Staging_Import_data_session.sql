BEGIN;

DROP FUNCTION IF EXISTS Staging.ar_import_data(INT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) CASCADE;
CREATE FUNCTION Staging.ar_import_data(
    p_session_id INT,
    p_client_id TEXT,
    p_customer_id TEXT ,
    p_invoice_date TEXT,
    p_due_date TEXT,
    p_amount TEXT,
    p_status TEXT
)
RETURNS INT AS $$
DECLARE
    new_previous_hash TEXT;
    new_ar_staging_id INT;
BEGIN

    SELECT row_hash
    INTO new_previous_hash
    FROM Audit.record_lineage
    ORDER BY lineage_id DESC
    LIMIT 1
    FOR UPDATE;


    INSERT INTO Staging.stg_ar_imports( 
        session_id, 
        client_code,
        customer_code, 
        invoice_date, 
        due_date, 
        amount,
        status, 
        validation_status, 
        validation_errors, 
        imported_at) 
    VALUES ( p_session_id, p_client_id, p_customer_id, p_invoice_date,  p_due_date, p_amount, p_status, 'DRAFT', NULL, NOW())
    RETURNING id INTO new_ar_staging_id;

    INSERT INTO Staging.import_workflows
    (session_id, staging_record_id, staging_table,previous_state, new_state, changed_by)
    VALUES(p_session_id, new_ar_staging_id, 'ar_import_data',NULL, 'DRAFT',current_user);

    -- -- IF current_setting('app.import_session_id', TRUE) IS NOT NULL THEN
    -- INSERT INTO Audit.record_lineage (
    --         table_name, 
    --         record_id, 
    --         client_id, 
    --         source_type, 
    --         source_file, 
    --         import_session_id, 
    --         created_by,
    --         prev_hash, 
    --         row_hash
    --     ) VALUES (
    --         'stg_ar_import', 
    --         new_ar_staging_id, 
    --         p_client_id::INT, 
    --         'SPREADSHEET_IMPORT',
    --         current_setting('app.import_source_file', TRUE),
    --         p_session_id::INT,
    --         current_user,
    --         new_previous_hash,
    --         md5(
    --             COALESCE(new_previous_hash,'')
    --             || p_session_id
    --             || 'stg_ar_import'
    --             || 'SPREADSHEET_IMPORT'
    --             || new_ar_staging_id
    --             || current_user
    --         )
    -- );
    -- -- END IF;

    RETURN new_ar_staging_id;
END; 
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;

DROP FUNCTION IF EXISTS Staging.ar_product_line(int,TEXT,TEXT,TEXT,TEXT) CASCADE;
CREATE Function IF NOT EXISTS Staging.ar_product_line(
    p_session_id INT,
    p_invoice_code TEXT,
    p_product_code TEXT,
    p_quantity TEXT,
    p_discount TEXT
)
RETURNS INT AS $$
DECLARE 
    new_ar_staging_id INT
BEGIN
    INSERT INTO Staging.ar_product_line(
        session_id,
        invoice_code,
        product_code,
        quantity,
        discount,
        validation_status, 
        validation_errors, 
        imported_at
    )
    VALUES (
        p_session_id,
        p_invoice_code,
        p_product_code,
        p_quantity,
        p_discount, 
        'DRAFT', 
        NULL, 
        NOW()
    ) RETURNING id INTO new_ar_staging_id;

    INSERT INTO Staging.import_workflows
    (session_id, staging_record_id, staging_table,previous_state, new_state, changed_by)
    VALUES(p_session_id, new_ar_staging_id, 'ar_product_line',NULL, 'DRAFT',current_user);


    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;

COMMIT;

SELECT '09 Staging Schema import data session complete' as Status;
