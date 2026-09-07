-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- Version: 2.0
-- Purpose: Ensure users only see data for their client/organization
-- ============================================

BEGIN;

-- Enable RLS enforcement on core tables
ALTER TABLE Finance.clients FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.coa_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.coa_template_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.charts FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_properties FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.journals FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.vendors FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.products FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.operations FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.warehouses FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_receivables FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.ar_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_payables FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.ap_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.inventory_audits FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.purchase_returns FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.sale_returns FORCE ROW LEVEL SECURITY;
ALTER TABLE Finance.inventory_transfers FORCE ROW LEVEL SECURITY;

--ALTER TABLE Staging.import_workflows FORCE ROW LEVEL SECURITY;
--ALTER TABLE Staging.stg_ar_imports FORCE ROW LEVEL SECURITY;
--ALTER TABLE Staging.import_approvals FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION Finance.get_current_client_id()
RETURNS INT AS $$
BEGIN
    IF current_setting('app.current_client_id', true) IS NULL THEN
        RAISE EXCEPTION
            'Client context not set';
    END IF;

    RETURN current_setting('app.current_client_id')::INT;

END;
$$ LANGUAGE plpgsql STABLE;

-- CREATE POLICY coa_templates_admin ON Finance.coa_templates
--     FOR ALL 
--     TO client_role
--     USING(TRUE)

CREATE POLICY coa_templates_admin ON Finance.coa_templates
    FOR ALL 
    TO admin_user
    USING(TRUE);

CREATE POLICY coa_templates_accounts_admin ON Finance.coa_template_accounts
    FOR ALL
    TO admin_user
    USING(TRUE);

-- Policy 1: Clients can only SELECT their own record
CREATE POLICY clients_select_own ON Finance.clients
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY clients_delete_own ON Finance.clients
    FOR DELETE
    USING (client_id = Finance.get_current_client_id());

-- Policy 2: Clients can only UPDATE their own record
CREATE POLICY clients_update_own ON Finance.clients
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- optional
CREATE POLICY admin_insert_all ON Finance.clients
    FOR INSERT
    TO admin_user
    WITH CHECK (true); -- Allows admin to insert any row

-- SELECT only charts for current client
CREATE POLICY charts_select_by_client ON Finance.charts
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

-- INSERT only for current client
CREATE POLICY charts_insert_for_client ON Finance.charts
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

-- UPDATE only for current client
CREATE POLICY charts_update_own_client ON Finance.charts
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- Account Roles
CREATE POLICY account_roles_select_by_client ON Finance.account_roles
    FOR SELECT
    USING (
        chart_id IN (
            SELECT chart_id FROM Finance.charts 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY account_roles_insert_for_client ON Finance.account_roles
    FOR INSERT
    WITH CHECK (
        chart_id IN (
            SELECT chart_id FROM Finance.charts 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ========================================================
-- 
--
-- =========================================================

-- Account Properties (same pattern)
CREATE POLICY account_properties_select_by_client ON Finance.account_properties
    FOR SELECT
    USING (
        chart_id IN (
            SELECT chart_id FROM Finance.charts 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY account_properties_insert_for_client ON Finance.account_properties
    FOR INSERT
    WITH CHECK (
        chart_id IN (
            SELECT chart_id FROM Finance.charts 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY transactions_select_by_client ON Finance.transactions
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY transactions_insert_for_client ON Finance.transactions
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY transactions_update_own_client ON Finance.transactions
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- Journals visible only if their transaction belongs to user's client
CREATE POLICY journals_select_by_client ON Finance.journals
    FOR SELECT
    USING (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY journals_insert_for_client ON Finance.journals
    FOR INSERT
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- AR - Receivables
CREATE POLICY ar_select_by_client ON Finance.account_receivables
    FOR SELECT
    USING (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY ar_insert_for_client ON Finance.account_receivables
    FOR INSERT
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- AP - Payables (same pattern)
CREATE POLICY ap_select_by_client ON Finance.account_payables
    FOR SELECT
    USING (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY ap_insert_for_client ON Finance.account_payables
    FOR INSERT
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );    

-- AR Extensions
CREATE POLICY ar_ext_select_by_client ON Finance.ar_ext
    FOR SELECT
    USING (
        receivable_id IN (
            SELECT receivable_id 
            FROM Finance.account_receivables ar
            WHERE ar.transaction_id IN (
                SELECT transaction_id 
                FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

-- AP Extensions
CREATE POLICY ap_ext_select_by_client ON Finance.ap_ext
    FOR SELECT
    USING (
        payable_id IN (
            SELECT payable_id 
            FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id 
                FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

-- Customers
CREATE POLICY customers_select_by_client ON Finance.customers
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY customers_insert_for_client ON Finance.customers
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

-- Vendors
CREATE POLICY vendors_select_by_client ON Finance.vendors
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY vendors_insert_for_client ON Finance.vendors
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());    

CREATE POLICY inventory_audits_select_by_client ON Finance.inventory_audits
    FOR SELECT
    USING (
        transaction_id IN (
            SELECT transaction_id 
            FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ============================================
-- MISSING: INSERT, UPDATE, DELETE for ar_ext
-- ============================================

CREATE POLICY ar_ext_insert_for_client ON Finance.ar_ext
    FOR INSERT
    WITH CHECK (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ar
            WHERE ar.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY ar_ext_update_own_client ON Finance.ar_ext
    FOR UPDATE
    USING (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ar
            WHERE ar.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    )
    WITH CHECK (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ar
            WHERE ar.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY ar_ext_delete_own_client ON Finance.ar_ext
    FOR DELETE
    USING (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ar
            WHERE ar.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

-- ============================================
-- MISSING: INSERT, UPDATE, DELETE for ap_ext
-- ============================================

CREATE POLICY ap_ext_insert_for_client ON Finance.ap_ext
    FOR INSERT
    WITH CHECK (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY ap_ext_update_own_client ON Finance.ap_ext
    FOR UPDATE
    USING (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    )
    WITH CHECK (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY ap_ext_delete_own_client ON Finance.ap_ext
    FOR DELETE
    USING (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

-- ============================================
-- MISSING: UPDATE, DELETE for journals
-- ============================================

CREATE POLICY journals_update_own_client ON Finance.journals
    FOR UPDATE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    )
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY journals_delete_own_client ON Finance.journals
    FOR DELETE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ============================================
-- MISSING: UPDATE, DELETE for account_receivables
-- ============================================

CREATE POLICY ar_update_own_client ON Finance.account_receivables
    FOR UPDATE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    )
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY ar_delete_own_client ON Finance.account_receivables
    FOR DELETE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ============================================
-- MISSING: UPDATE, DELETE for account_payables
-- ============================================

CREATE POLICY ap_update_own_client ON Finance.account_payables
    FOR UPDATE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    )
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY ap_delete_own_client ON Finance.account_payables
    FOR DELETE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ============================================
-- MISSING: UPDATE, DELETE for customers
-- ============================================

CREATE POLICY customers_update_own_client ON Finance.customers
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY customers_delete_own_client ON Finance.customers
    FOR DELETE
    USING (client_id = Finance.get_current_client_id());

-- ============================================
-- MISSING: UPDATE, DELETE for vendors
-- ============================================

CREATE POLICY vendors_update_own_client ON Finance.vendors
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY vendors_delete_own_client ON Finance.vendors
    FOR DELETE
    USING (client_id = Finance.get_current_client_id());

-- ============================================
-- MISSING: UPDATE, DELETE for clients
-- ============================================


-- ============================================
-- MISSING: INSERT, UPDATE, DELETE for inventory_audits
-- ============================================

CREATE POLICY inventory_audits_insert_for_client ON Finance.inventory_audits
    FOR INSERT
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY inventory_audits_update_own_client ON Finance.inventory_audits
    FOR UPDATE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    )
    WITH CHECK (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

CREATE POLICY inventory_audits_delete_own_client ON Finance.inventory_audits
    FOR DELETE
    USING (
        transaction_id IN (
            SELECT transaction_id FROM Finance.transactions 
            WHERE client_id = Finance.get_current_client_id()
        )
    );

-- ==============================================================
-- Products Insert, update and delete policy
-- ==============================================================


CREATE POLICY products_SELECT_policy ON Finance.products
    FOR SELECT
        USING(client_id = Finance.get_current_client_id());

CREATE POLICY products_INSERT_policy ON Finance.products
    FOR INSERT
        WITH CHECK(client_id = Finance.get_current_client_id()
        );
    
CREATE POLICY products_DELETE_policy ON Finance.products
    FOR DELETE 
        USING (client_id = Finance.get_current_client_id());

CREATE POLICY products_UPDATE_policy ON Finance.products
    FOR UPDATE
        USING(client_id = Finance.get_current_client_id())
        WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY operation_select_products ON Finance.operations 
    FOR SELECT
        USING (
            product_id IN (
                SELECT product_id FROM Finance.products 
                WHERE client_id = Finance.get_current_client_id()
            )
        );

CREATE POLICY operation_insert_products ON Finance.operations 
    FOR INSERT
        WITH CHECK(
            product_id IN (
                SELECT product_id FROM Finance.products 
                WHERE client_id = Finance.get_current_client_id()
            )
        );

CREATE POLICY operation_delete_products ON Finance.operations 
    FOR DELETE
        USING(
            product_id IN (
                SELECT product_id FROM Finance.products 
                WHERE client_id = Finance.get_current_client_id()
            )
        );

CREATE POLICY operation_update_products ON Finance.operations
    FOR UPDATE
        USING(
            product_id IN (
                SELECT product_id FROM Finance.products
                WHERE client_id = Finance.get_current_client_id()
            )
        )
        WITH CHECK(
            product_id IN (
                SELECT product_id FROM Finance.products
                WHERE client_id = Finance.get_current_client_id()
            )
        );

CREATE POLICY warehouses_select_policy ON Finance.warehouses
    FOR SELECT
        USING(client_id = Finance.get_current_client_id());

CREATE POLICY warehouses_insert_policy ON Finance.warehouses
    FOR INSERT
        WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY warehouses_delete_policy ON Finance.warehouses
    FOR DELETE
        USING(client_id = Finance.get_current_client_id());

CREATE POLICY warehouses_update_policy ON Finance.warehouses
    FOR UPDATE
        USING(client_id = Finance.get_current_client_id())
        WITH CHECK(client_id = Finance.get_current_client_id());            
-- -- ============================================
-- -- MISSING: Tax table policies
-- -- ============================================

-- CREATE POLICY tax_types_update_own_client ON Finance.tax_types
--     FOR UPDATE
--     USING (client_id = Finance.get_current_client_id())
--     WITH CHECK (client_id = Finance.get_current_client_id());

-- CREATE POLICY tax_types_delete_own_client ON Finance.tax_types
--     FOR DELETE
--     USING (client_id = Finance.get_current_client_id());

-- CREATE POLICY tax_calculations_update_own_client ON Finance.tax_calculations
--     FOR UPDATE
--     USING (client_id = Finance.get_current_client_id())
--     WITH CHECK (client_id = Finance.get_current_client_id());

-- CREATE POLICY tax_calculations_delete_own_client ON Finance.tax_calculations
--     FOR DELETE
--     USING (client_id = Finance.get_current_client_id());

-- CREATE POLICY tax_liabilities_update_own_client ON Finance.tax_liabilities
--     FOR UPDATE
--     USING (client_id = Finance.get_current_client_id())
--     WITH CHECK (client_id = Finance.get_current_client_id());

-- CREATE POLICY tax_liabilities_delete_own_client ON Finance.tax_liabilities
--     FOR DELETE
--     USING (client_id = Finance.get_current_client_id());

-- =========================================================
-- Sales_returns insert, update and delete
-- =========================================================

CREATE POLICY Sales_return_insert_own_client ON Finance.sale_returns
    FOR INSERT
    WITH CHECK (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );


CREATE POLICY Sales_return_update_own_client ON Finance.sale_returns
    FOR UPDATE
        USING (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    )
    WITH CHECK (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY Sales_return_select_own_client ON Finance.sale_returns
    FOR SELECT
    USING (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY Sales_return_delete_own_client ON Finance.sale_returns
    FOR DELETE
    USING (
        receivable_id IN (
            SELECT receivable_id FROM Finance.account_receivables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

-- =========================================================
-- Purchase_returns insert, update and delete
-- =========================================================

CREATE POLICY purchase_return_insert_own_client ON Finance.purchase_returns
    FOR INSERT
    WITH CHECK (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );


CREATE POLICY purchase_return_update_own_client ON Finance.purchase_returns
    FOR UPDATE
    USING (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    )
    WITH CHECK (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY purchase_return_select_own_client ON Finance.purchase_returns
    FOR SELECT
    USING (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY purchase_return_delete_own_client ON Finance.purchase_returns
    FOR DELETE
    USING (
        payable_id IN (
            SELECT payable_id FROM Finance.account_payables ap
            WHERE ap.transaction_id IN (
                SELECT transaction_id FROM Finance.transactions 
                WHERE client_id = Finance.get_current_client_id()
            )
        )
    );


-- =========================================================
-- Purchase_returns insert, update and delete
-- =========================================================

CREATE POLICY inventory_transfer_insert_own_client ON Finance.inventory_transfers
    FOR INSERT
    WITH CHECK (
        product_id IN (
            SELECT product_id FROM Finance.inventory_transfers sr
            WHERE sr.product_id IN  (
                SELECT product_id FROM Finance.products ar
                WHERE ar.client_id = Finance.get_current_client_id()
            )
        )
    );


CREATE POLICY inventory_transfer_update_own_client ON Finance.inventory_transfers
    FOR UPDATE
    USING (
        product_id IN (
            SELECT product_id FROM Finance.inventory_transfers sr
            WHERE sr.product_id IN (
                SELECT product_id FROM Finance.products ar
                WHERE ar.client_id = Finance.get_current_client_id()
            )
        )
    )
    WITH CHECK (
        product_id IN (
            SELECT product_id FROM Finance.inventory_transfers sr
            WHERE sr.product_id IN (
                SELECT product_id FROM Finance.products ar
                WHERE ar.client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY inventory_transfer_select_own_client ON Finance.inventory_transfers    
    FOR SELECT
    USING (
        product_id IN (
            SELECT product_id FROM Finance.inventory_transfers sr
            WHERE sr.product_id IN (
                SELECT product_id FROM Finance.products ar
                WHERE ar.client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY inventory_transfer_delete_own_client ON Finance.inventory_transfers
    FOR DELETE
    USING (
        product_id IN (
            SELECT product_id FROM Finance.inventory_transfers sr
            WHERE sr.product_id IN (
                SELECT product_id FROM Finance.products ar
                WHERE ar.client_id = Finance.get_current_client_id()
            )
        )
    );



-- Enable RLS on audit tables
ALTER TABLE Audit.audit_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.audit_logs_extended FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.transaction_lifecycle FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.approval_chain FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.reconciliation_tracking FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.record_lineage FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_detail_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_validation_log FORCE ROW LEVEL SECURITY;
ALTER TABLE Audit.record_lineage FORCE ROW LEVEL SECURITY;

CREATE POLICY record_lineage_select_own_client ON Audit.record_lineage
    FOR SELECT
    TO auditor_user, admin_user
    USING (TRUE);

CREATE POLICY reconciliation_tracking_insert_own_client ON Audit.record_lineage
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());


CREATE POLICY _select_own_client ON Audit.reconciliation_tracking

    FOR SELECT
    TO auditor_user, admin_user
    USING (TRUE);

CREATE POLICY reconciliation_tracking_insert_own_client ON Audit.reconciliation_tracking
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY approval_chain_select_own_client ON Audit.approval_chain
    FOR SELECT
    TO auditor_user, admin_user
    USING (TRUE);

CREATE POLICY approval_chain_insert_own_client ON Audit.approval_chain
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY transaction_lifecycle_select_own_client ON Audit.transaction_lifecycle
    FOR SELECT
    TO auditor_user, admin_user
    USING (TRUE);

CREATE POLICY transaction_lifecycle_insert_own_client ON Audit.transaction_lifecycle
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY audit_log_select_own_client ON Audit.audit_logs
    FOR SELECT
    TO auditor_user, admin_user
    USING (TRUE);

CREATE POLICY audit_log_insert_own_client ON Audit.audit_logs
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (true);

CREATE POLICY audit_log_extended_select_own_client ON Audit.audit_logs_extended   
    FOR SELECT
    to auditor_user, admin_user
    USING (true);

CREATE POLICY audit_log_extended_insert_own_client ON Audit.audit_logs_extended    
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY import_session_select_own_client ON Audit.import_sessions
    FOR SELECT
    to auditor_user, admin_user
    USING (true);

CREATE POLICY import_session_insert_own_client ON Audit.import_sessions
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY import_details_log_select_own_client ON Audit.import_detail_logs
    FOR SELECT
    to auditor_user, admin_user
    USING (true);

CREATE POLICY import_detail_logs_select_own_client ON Audit.import_detail_logs
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM Audit.import_detail_logs idl
            WHERE idl.session_id IN (
                SELECT session_id FROM Audit.import_sessions iss
                WHERE iss.client_id = Finance.get_current_client_id()
            )
        )
    );

CREATE POLICY import_validation_log_select_own_client ON Audit.import_validation_log
    FOR SELECT
    to auditor_user, admin_user
    USING (true);

CREATE POLICY import_validation_log_insert_own_client ON Audit.import_validation_log
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (
        validation_id IN (
            SELECT validation_id FROM Audit.import_validation_log ivl
            WHERE ivl.session_id IN (
                SELECT session_id FROM Audit.import_sessions iss
                WHERE iss.client_id = Finance.get_current_client_id()
            )
        )
    );

--compliance Enable RLS on audit tables
ALTER TABLE Compliance.compliance_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE Compliance.compliance_rules FORCE ROW LEVEL SECURITY;

CREATE POLICY compliance_logs_select_own_client ON Compliance.compliance_logs
    FOR SELECT
    to auditor_user, admin_user
    USING (true);

CREATE POLICY compliance_logs_insert_own_client ON Compliance.compliance_logs
    FOR INSERT
    TO app_user, admin_user
    WITH CHECK (client_id = Finance.get_current_client_id());

COMMIT;