BEGIN;

-- =============================================================
-- Staging validations imoprt 
-- may add more future staging table here 
-- =============================================================

-- =============================================================
-- Staging validations 
-- Account Receivables Procedure
-- =============================================================

CREATE OR REPLACE PROCEDURE Staging.ar_import_workflow_validation(
    IN p_session_id INT
)
LANGUAGE plpgsql as $$
DECLARE
    new_session_id INT;
    r RECORD;
    z RECORD; -- This will hold the 4 error columns
BEGIN
    -- 1. Validate Session
    SELECT session_id INTO new_session_id
    FROM Audit.import_sessions a
    WHERE a.session_id = p_session_id
    LIMIT 1;

    IF new_session_id IS NULL THEN
        RAISE EXCEPTION 'Invalid Session ID: %', p_session_id; -- Fixed: use p_session_id, not new_session_id (which is NULL)
    END IF;

    -- 2. Loop through records
    FOR r IN
        SELECT 
            a.*, 
            c.row_number, 
            c.table_name
        FROM Staging.stg_ar_imports a
        LEFT JOIN Staging.import_workflows b ON a.id = b.staging_record_id 
        LEFT JOIN Audit.import_detail_logs c ON a.id = c.created_record_id
        WHERE a.session_id = p_session_id AND b.new_state = 'PENDING' -- Fixed: Handle case where workflow row might not exist yet
    
    LOOP

        -- Call the validation function
        SELECT *
        INTO z
        FROM Compliance.validate_ar_import(
            r.row_number::INT,
            r.customer_code::INT,
            r.amount::DECIMAL,
            r.invoice_date::DATE,
            r.due_date::DATE,
            r.status::VARCHAR
        );

        -- ========================================================
        -- Amount Check 1
        -- ========================================================
        -- FIX: Use z.amount_error instead of z.v_errors_amount
        IF z.amount_error IS NOT NULL THEN
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'INVALID: Check Amount Value!', r.amount, FALSE, 'ERROR'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 1::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'FAIL'
                , 'UNRESOLVED'
                , NULL
            );
        ELSE
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'Valid: Amount!', r.amount, TRUE, 'INFO'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 1::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'PASS'
                , 'RESOLVED'
                , NULL
            );
        END IF;

        -- ========================================================
        -- Invoice Date Check 2
        -- ========================================================
        -- FIX: Use z.Invoice_error instead of z.v_errors_invoice
        IF z.Invoice_error IS NOT NULL THEN
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'INVALID: Check Invoice Value!', r.invoice_date, FALSE, 'ERROR'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 2::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'FAIL'
                , 'UNRESOLVED'
                , NULL
            );
        ELSE
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'VALID: Invoice Date!', r.invoice_date, TRUE, 'INFO'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 2::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'PASS'
                , 'RESOLVED'
                , NULL
            );
        END IF;

        -- ========================================================
        -- Customer Check 3
        -- ========================================================
        -- FIX: Use z.customer_error instead of z.v_errors_customer
        IF z.customer_error IS NOT NULL THEN
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'INVALID: Customer not exists!', r.customer_code, FALSE, 'ERROR'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 3::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'FAIL'
                , 'UNRESOLVED'
                , NULL
            );
        ELSE
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'VALID: Customer!', r.customer_code, TRUE, 'INFO'
            );
            PERFORM Compliance.log_compliance_check(
                r.client_code::INT
                , 3::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'PASS'
                , 'RESOLVED'
                , NULL
            );
        END IF;

        -- ========================================================
        -- Status Check 4
        -- ========================================================
        -- FIX: Use z.status_error instead of z.v_errors_status
        IF z.status_error IS NOT NULL THEN
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'INVALID: Status Check!', r.status, FALSE, 'ERROR'
            );
            -- Log status fail if needed
            PERFORM Compliance.log_compliance_check(
               r.client_code::INT
                , 4::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'FAIL'
                , 'UNRESOLVED'
                , NULL
            );
        ELSE
            PERFORM Audit.import_validation(
                r.session_id, r.row_number, r.table_name, 
                'Valid: Status!', r.status, TRUE, 'INFO'
            );
            -- Log status pass if needed
            PERFORM Compliance.log_compliance_check(
               r.client_code::INT
                , 4::INT
                , r.session_id::INT
                , r.id::INT
                , NULL
                , r.table_name
                , 'PASS'
                , 'RESOLVED'
                , NULL
            );
        END IF;

        -- ========================================================
        -- Update Workflow Status (Only if ALL checks passed)
        -- ========================================================
        -- Logic: If ANY error was found, we should NOT update to 'VALID'.
        -- We only update if ALL four are NULL.
        IF z.amount_error IS NULL 
           AND z.Invoice_error IS NULL 
           AND z.customer_error IS NULL 
           AND z.status_error IS NULL THEN
            
            UPDATE Staging.import_workflows 
            SET 
                new_state = 'VALID',
                previous_state = 'PENDING',
                notes = 'PENDING FOR APPROVAL'
            WHERE Staging.import_workflows.session_id = r.session_id
              AND Staging.import_workflows.staging_record_id = r.id;
        END IF;
    
    END LOOP;    

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Procedure ar_import_workflow_validation failed: %', SQLERRM;
END;
$$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;


-- =============================================================
-- Staging validations END
-- Account Receivables Procedure
-- =============================================================


COMMIT;

SELECT '11 Staging Schema import data validations complete' as Status;