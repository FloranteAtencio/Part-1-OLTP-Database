BEGIN;

    CREATE OR REPLACE FUNCTION Audit.WORM()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN

    RAISE EXCEPTION 'Direct Operation of Update and Delete is Prohibited';

    IF TG_OP = 'DELETE' THEN   
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;

    END;
    $$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;

    CREATE TRIGGER Guard_worms
    BEFORE UPDATE OR DELETE ON Audit.record_lineage
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_audit_logs
    BEFORE UPDATE OR DELETE ON Audit.audit_logs
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_audit_log_extended
    BEFORE UPDATE OR DELETE ON Audit.audit_logs_extended
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_import_detail_logs
    BEFORE UPDATE OR DELETE ON Audit.import_detail_logs
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_compliance_logs
    BEFORE UPDATE OR DELETE ON Compliance.compliance_logs
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_compliance_rules
    BEFORE UPDATE OR DELETE ON Compliance.compliance_rules
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_reconciliation_tracking
    BEFORE UPDATE OR DELETE ON Audit.reconciliation_tracking
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_approval_chain
    BEFORE UPDATE OR DELETE ON Audit.approval_chain
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_transaction_lifecycle
    BEFORE UPDATE OR DELETE ON Audit.transaction_lifecycle
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guar_worms_import_validation_log
    BEFORE UPDATE OR DELETE ON Audit.import_validation_log
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE TRIGGER Guard_worms_import_session
    BEFORE DELETE ON Audit.import_sessions
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM();

    CREATE OR REPLACE FUNCTION Audit.WORM_exceptions()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN

        IF current_setting('app.get_permission_to_update', true) IS NULL THEN
        
            RAISE EXCEPTION 'Direct Operation of Update and Delete is Prohibited';
        
        END IF;

    IF TG_OP = 'DELETE' THEN   
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;

    END;
    $$ SECURITY DEFINER SET search_path = Finance, Audit, Compliance, Security, Staging, pg_catalog;

    CREATE TRIGGER Guar_worms_import_validation_log_exceptions
    BEFORE UPDATE ON Audit.import_sessions
    FOR EACH ROW EXECUTE FUNCTION Audit.WORM_exceptions();

COMMIT;

-- ✅ Make audit tables APPEND-ONLY
ALTER TABLE Audit.audit_logs SET (fillfactor = 100);  -- Never update

-- ✅ Add constraint: no UPDATEs or DELETEs
CREATE TRIGGER audit_logs_immutable
BEFORE UPDATE OR DELETE ON Audit.audit_logs
FOR EACH ROW EXECUTE FUNCTION raise_exception('Audit logs cannot be modified');

-- ✅ For extra security: Hash chain (you already have this!)
-- Your code shows:
-- prev_hash, row_hash columns
-- This is good, but verify the hash is SHA-256 and chain validation runs

-- ✅ Implement hash verification:
CREATE OR REPLACE FUNCTION Audit.verify_audit_chain()
RETURNS TABLE(row_id INT, is_valid BOOLEAN, broken_at_row INT) AS $$
BEGIN
    RETURN QUERY
    WITH chain AS (
        SELECT 
            audit_id,
            row_hash,
            LAG(row_hash) OVER (ORDER BY audit_id) as expected_prev_hash,
            prev_hash,
            audit_id = 1 OR prev_hash = LAG(row_hash) OVER (ORDER BY audit_id) as is_valid
        FROM Audit.audit_logs
    )
    SELECT audit_id::INT, is_valid, 
           CASE WHEN NOT is_valid THEN audit_id::INT ELSE NULL END
    FROM chain;
END;
$$ LANGUAGE plpgsql;

-- Run periodically:
-- SELECT * FROM Audit.verify_audit_chain() WHERE NOT is_valid;

SELECT '33 WORM' AS STATUS;
