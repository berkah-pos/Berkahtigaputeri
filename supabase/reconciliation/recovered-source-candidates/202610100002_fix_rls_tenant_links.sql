-- RLS correction for private.tenant_accounting_links.
-- Intended for the isolated target clone; source Supabase remains read-only.
BEGIN;
ALTER TABLE private.tenant_accounting_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_anon_all ON private.tenant_accounting_links;
CREATE POLICY deny_anon_all ON private.tenant_accounting_links
  FOR ALL TO anon USING (false) WITH CHECK (false);

-- Replace the overly broad legacy authenticated FOR ALL policy.
DROP POLICY IF EXISTS tenant_isolation_all ON private.tenant_accounting_links;
DROP POLICY IF EXISTS tenant_isolation_select ON private.tenant_accounting_links;
CREATE POLICY tenant_isolation_select ON private.tenant_accounting_links
  FOR SELECT TO authenticated
  USING (accounting_tenant_id IN (
    SELECT m.tenant_id
    FROM public.accounting_memberships AS m
    WHERE m.user_id = (SELECT auth.uid()) AND m.is_active = true
  ));

-- Allow the required SET ROLE anon proof to test RLS itself, rather than
-- passing/failing due to schema permission errors. No anon write privilege.
GRANT USAGE ON SCHEMA private TO anon;
GRANT SELECT ON TABLE private.tenant_accounting_links TO anon;
COMMIT;
