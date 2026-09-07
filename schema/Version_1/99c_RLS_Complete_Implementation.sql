-- ============================================
-- ROW LEVEL SECURITY (RLS) - COMPLETE IMPLEMENTATION
-- Version: 3.0 (Production Ready)
-- Purpose: Enforce multi-tenant data isolation at database level
-- ============================================

BEGIN;

-- ============================================
-- STEP 1: CREATE ROLES (User Management)
-- ============================================

-- Admin role (full access, sees everything)
DROP ROLE IF EXISTS admin_user;
CREATE ROLE admin_user WITH LOGIN PASSWORD 'ChangeMeToStrongPassword123!';
GRANT ALL PRIVILEGES ON DATABASE erp_db TO admin_user;

-- Application user (sees only their client's data)
DROP ROLE IF EXISTS app_user;
CREATE ROLE app_user WITH LOGIN PASSWORD 'ChangeMeToStrongPassword456!';

-- Read-only user (reports, dashboards)
DROP ROLE IF EXISTS readonly_user;
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'ChangeMeToStrongPassword789!';

-- Auditor role (sees audit data)
DROP ROLE IF EXISTS auditor_user;
CREATE ROLE auditor_user WITH LOGIN PASSWORD 'ChangeMeToStrongPassword000!';

-- ============================================
-- STEP 2: GRANT SCHEMA PRIVILEGES
-- ============================================

-- Grant usage on schemas
GRANT USAGE ON SCHEMA Finance, Audit, Compliance, Staging, Security TO app_user, readonly_user, auditor_user;

-- Grant table privileges to app_user (needed for RLS to work)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA Finance TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA Audit TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA Compliance TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA Staging TO app_user;

-- Grant only SELECT to readonly_user
GRANT SELECT ON ALL TABLES IN SCHEMA Finance TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA Audit TO readonly_user;

-- Grant audit privileges
GRANT SELECT ON ALL TABLES IN SCHEMA Audit TO auditor_user;

-- Grant function execution
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA Finance TO app_user, readonly_user, auditor_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA Audit TO app_user, auditor_user;

-- ============================================
-- STEP 3: CREATE CONTEXT FUNCTION
-- ============================================

-- Get current client from session variable
DROP FUNCTION IF EXISTS Finance.get_current_client_id() CASCADE;
CREATE OR REPLACE FUNCTION Finance.get_current_client_id()
RETURNS INT AS $$
BEGIN
    IF current_setting('app.current_client_id', true) IS NULL THEN
        RAISE EXCEPTION 'Client context not set. Set using: SET app.current_client_id = <client_id>';
    END IF;
    
    RETURN current_setting('app.current_client_id')::INT;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = Finance, pg_catalog;

-- ============================================
-- STEP 4: ENABLE RLS ON ALL TABLES
-- ============================================

-- Finance Schema
ALTER TABLE Finance.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.charts ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_receivables ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.ar_ext ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.account_payables ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.ap_ext ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.inventory_audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.purchase_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.sale_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE Finance.inventory_transfers ENABLE ROW LEVEL SECURITY;

-- Audit Schema
ALTER TABLE Audit.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.audit_logs_extended ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_detail_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.import_validation_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.transaction_lifecycle ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.approval_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE Audit.record_lineage ENABLE ROW LEVEL SECURITY;

-- Compliance Schema
ALTER TABLE Compliance.compliance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE Compliance.compliance_rules ENABLE ROW LEVEL SECURITY;

-- ============================================
-- STEP 5: ADMIN BYPASS POLICIES
-- ============================================

-- Admin users bypass all RLS (optional - comment out for stricter security)
CREATE POLICY admin_bypass_all ON Finance.clients
    FOR ALL
    TO admin_user
    USING (true);

CREATE POLICY admin_bypass_charts ON Finance.charts
    FOR ALL
    TO admin_user
    USING (true);

CREATE POLICY admin_bypass_transactions ON Finance.transactions
    FOR ALL
    TO admin_user
    USING (true);

-- (Repeat for other critical tables if needed)

-- ============================================
-- STEP 6: FINANCE SCHEMA POLICIES
-- ============================================

-- ============ Clients Table ============
CREATE POLICY clients_select_own ON Finance.clients
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY clients_update_own ON Finance.clients
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Charts Table ============
CREATE POLICY charts_select_by_client ON Finance.charts
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY charts_insert_for_client ON Finance.charts
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY charts_update_own_client ON Finance.charts
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Transactions Table (Core) ============
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

-- ============ Journals Table (Via Transaction) ============
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

-- ============ Customers Table ============
CREATE POLICY customers_select_by_client ON Finance.customers
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY customers_insert_for_client ON Finance.customers
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY customers_update_own_client ON Finance.customers
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Vendors Table ============
CREATE POLICY vendors_select_by_client ON Finance.vendors
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY vendors_insert_for_client ON Finance.vendors
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY vendors_update_own_client ON Finance.vendors
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Products Table ============
CREATE POLICY products_select_by_client ON Finance.products
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY products_insert_for_client ON Finance.products
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY products_update_own_client ON Finance.products
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Warehouses Table ============
CREATE POLICY warehouses_select_by_client ON Finance.warehouses
    FOR SELECT
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY warehouses_insert_for_client ON Finance.warehouses
    FOR INSERT
    WITH CHECK (client_id = Finance.get_current_client_id());

CREATE POLICY warehouses_update_own_client ON Finance.warehouses
    FOR UPDATE
    USING (client_id = Finance.get_current_client_id())
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============ Account Receivables & Extensions ============
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

-- ============ Account Payables & Extensions ============
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

-- ============================================
-- STEP 7: AUDIT SCHEMA POLICIES
-- ============================================

-- Audit logs - restrict by client
CREATE POLICY audit_logs_select_by_client ON Audit.audit_logs_extended
    FOR SELECT
    TO app_user
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY audit_logs_insert_for_client ON Audit.audit_logs_extended
    FOR INSERT
    TO app_user
    WITH CHECK (client_id = Finance.get_current_client_id());

-- Auditor role sees everything
CREATE POLICY audit_logs_select_auditor ON Audit.audit_logs_extended
    FOR SELECT
    TO auditor_user
    USING (true);

-- Import sessions
CREATE POLICY import_session_select_by_client ON Audit.import_sessions
    FOR SELECT
    TO app_user
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY import_session_insert_for_client ON Audit.import_sessions
    FOR INSERT
    TO app_user
    WITH CHECK (client_id = Finance.get_current_client_id());

-- ============================================
-- STEP 8: COMPLIANCE SCHEMA POLICIES
-- ============================================

CREATE POLICY compliance_logs_select_by_client ON Compliance.compliance_logs
    FOR SELECT
    TO app_user
    USING (client_id = Finance.get_current_client_id());

CREATE POLICY compliance_logs_insert_for_client ON Compliance.compliance_logs
    FOR INSERT
    TO app_user
    WITH CHECK (client_id = Finance.get_current_client_id());

COMMIT;

-- ============================================
-- TESTING & VERIFICATION
-- ============================================
-- Run these commands to verify RLS is working

-- 1. Create test clients
INSERT INTO Finance.clients (client_id, info) VALUES (1, '{"name": "Client A"}');
INSERT INTO Finance.clients (client_id, info) VALUES (2, '{"name": "Client B"}');

-- 2. Test as app_user for Client A
SET ROLE app_user;
SET app.current_client_id = '1';
SELECT * FROM Finance.clients;  -- Should only show client_id = 1

-- 3. Try to access Client B data (should return nothing)
SELECT * FROM Finance.clients WHERE client_id = 2;  -- Should return 0 rows

-- 4. Switch to Client B context
SET app.current_client_id = '2';
SELECT * FROM Finance.clients;  -- Should only show client_id = 2

-- 5. Reset to superuser
RESET ROLE;
RESET app.current_client_id;