-- ===================================================
-- This is where you can add and change the table returns for dynamic programming
-- just add if conditions inside the table verification
-- ===================================================
BEGIN;

DROP FUNCTION IF EXISTS Staging.table_verification(INT);
CREATE FUNCTION Staging.table_verification(p_session_id INT)
RETURNS VARCHAR AS $$
DECLARE
    v_table_name VARCHAR;
BEGIN
    
    IF EXISTS (
        SELECT 1 
        FROM Staging.stg_ar_imports a 
        WHERE a.session_id = p_session_id
    ) THEN
        RETURN 'Staging.stg_ar_imports'; -- Fixed typo in string and removed extra dot
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM Staging.stg_ar_lines a 
        WHERE a.session_id = p_session_id
    ) THEN
        RETURN 'Staging.stg_ar_lines'; -- Fixed typo in string and removed extra dot
    END IF;


    RETURN NULL; -- Explicit return if no match found
    
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Table verifications failed : %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;

-- =====================================
-- add more procedure for sanitation for each staging table
-- =====================================

CREATE OR REPLACE PROCEDURE Staging.ar_sanitation(
    IN p_session_id INT
)
LANGUAGE plpgsql as $$
DECLARE
    collect_errors TEXT[] := ARRAY[]::TEXT[];
    r RECORD;
BEGIN

    FOR r IN    
        SELECT *
        FROM Staging.stg_ar_imports a
        WHERE a.session_id = p_session_id
    LOOP

        IF NOT EXISTS ( SELECT 1 FROM Finance.customers z WHERE z.customer_id = r.customer_code::INT ) THEN 
            collect_errors := array_append(collect_errors, 'Customer not found');
        END IF;

        IF NOT EXISTS ( SELECT 1 FROM Finance.clients z WHERE z.client_id = r.client_code::INT )  THEN 
            collect_errors := array_append(collect_errors, 'Client not found');
        
        END IF;
        
        IF r.amount !~ '^\.?\d+(\.\d+)?$' THEN 
            collect_errors := array_append(collect_errors,'Invalid amount format');
        END IF;
        
        IF r.invoice_date !~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$' THEN 
            collect_errors := array_append(collect_errors,'Invalid Date');  
        END IF;
        
        IF r.due_date !~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$' THEN 
            collect_errors := array_append(collect_errors,'Invalid Date');
        END IF;

        IF r.status NOT IN ('Pending', 'Paid', 'Overdue','Returned','Partially Returned','Partially Paid') THEN 
            collect_errors := array_append(collect_errors,'INVALID Status');
        END IF;

        UPDATE Staging.stg_ar_imports s
        SET 
            validation_status = 
                CASE 
                WHEN
                    array_length(collect_errors,1) IS NULL THEN 
                        'VALID' 
                ELSE 
                        'INVALID' 
                END ,
            validation_errors = 
                CASE 
                WHEN
                    array_length(collect_errors,1) IS NULL THEN 
                        NULL  
                    ELSE 
                        array_to_string(collect_errors, '; ')
                END
        WHERE s.session_id = p_session_id
        AND s.validation_status = 'DRAFT'
        AND s.id = r.id;
        
        collect_errors := ARRAY[]::TEXT[];

    END LOOP;

    UPDATE Staging.import_workflows a
    SET
        new_state = 'PENDING',
        previous_state = 'DRAFT',
        notes = 'PENDING FOR VALIDATION'
    FROM Staging.stg_ar_imports b
    WHERE a.staging_record_id = b.id 
    AND a.session_id = b.session_id
    AND b.validation_status = 'VALID'
    AND a.session_id = p_session_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Account Receivables Sanitations Failed: %', SQLERRM;

END;
$$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;


-- =====================================
-- add more procedure for sanitation for each staging table
-- =====================================

CREATE OR REPLACE PROCEDURE Staging.ar_line_sanitation(
    IN p_session_id INT
)
LANGUAGE plpgsql as $$
DECLARE
    collect_errors TEXT[] := ARRAY[]::TEXT[];
    r RECORD;
BEGIN

    FOR r IN    
        SELECT *
        FROM Staging.stg_ar_lines a
        WHERE a.session_id = p_session_id
    LOOP

        IF NOT EXISTS ( SELECT 1 FROM Finance.customers z WHERE z.customer_id = r.customer_code::INT ) THEN 
            collect_errors := array_append(collect_errors, 'Customer not found');
        END IF;

        IF NOT EXISTS ( SELECT 1 FROM Finance.clients z WHERE z.client_id = r.product_code::INT )  THEN 
            collect_errors := array_append(collect_errors, 'Client not found');
        
        END IF;

        IF r.quantity !~ '^\.?\d+(\.\d+)?$' THEN 
            collect_errors := array_append(collect_errors,'Invalid amount format');
        END IF;

        IF r.discount !~ '^\.?\d+(\.\d+)?$' THEN 
            collect_errors := array_append(collect_errors,'Invalid amount format');
        END IF;

        UPDATE Staging.stg_ar_lines s
        SET 
            validation_status = 
                CASE 
                WHEN
                    array_length(collect_errors,1) IS NULL THEN 
                        'VALID' 
                ELSE 
                        'INVALID' 
                END ,
            validation_errors = 
                CASE 
                WHEN
                    array_length(collect_errors,1) IS NULL THEN 
                        NULL  
                    ELSE 
                        array_to_string(collect_errors, '; ')
                END
        WHERE s.session_id = p_session_id
        AND s.validation_status = 'DRAFT'
        AND s.id = r.id;
        
        collect_errors := ARRAY[]::TEXT[];

    END LOOP;

    UPDATE Staging.import_workflows a
    SET
        new_state = 'PENDING',
        previous_state = 'DRAFT',
        notes = 'PENDING FOR VALIDATION'
    FROM Staging.stg_ar_imports b
    WHERE a.staging_record_id = b.id 
    AND a.session_id = b.session_id
    AND b.validation_status = 'VALID'
    AND a.session_id = p_session_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Account Receivables Sanitations Failed: %', SQLERRM;

END;
$$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;


-- =====================================
-- the main staging work flow santation
-- =====================================

CREATE OR REPLACE PROCEDURE Staging.import_workflow_sanitation(
    IN p_session_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    table_related VARCHAR;
    new_session_id INT;
BEGIN

    -- 1. Validate Session ID
    SELECT session_id INTO new_session_id
    FROM Audit.import_sessions
    WHERE session_id = p_session_id
    LIMIT 1;

    IF new_session_id IS NULL THEN
        RAISE EXCEPTION 'Invalid Session ID: %', p_session_id;
    END IF;

    SELECT Staging.table_verification(new_session_id) INTO table_related;
 
    -- 2. Validate Table Name (Whitelist approach)
    IF table_related IS NULL THEN
        RAISE EXCEPTION 'Invalid table name: %. Not Allowed:', table_related;
    END IF;
    
    PERFORM 1 FROM Audit.import_sessions WHERE session_id = p_session_id;
    
    -- 3. Execute Table-Specific Sanitation
    IF table_related = 'Staging.stg_ar_imports' THEN
        CALL Staging.ar_sanitation(new_session_id);

        IF table_related = 'Staging.stg_ar_lines' THEN
        CALL Staging.ar_line_sanitation(new_session_id);

    ELSIF table_related = 'stg_other_table' THEN
        RAISE EXCEPTION 'Sanitation logic for stg_other_table is not yet implemented.';
            
    END IF;

 -- Ensure we only update records for this session
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Staging import sanitation failed for session %: %', p_session_id, SQLERRM;
END;
$$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;


COMMIT;
SELECT '10 Staging Schema data sanitation complete' as Status;