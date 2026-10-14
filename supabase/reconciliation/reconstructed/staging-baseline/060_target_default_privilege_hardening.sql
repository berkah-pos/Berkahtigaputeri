-- RECONSTRUCTED TARGET HARDENING OVERLAY — NOT HISTORICAL MIGRATION SOURCE.
-- Intended only for the disposable clean-replay baseline. Do not run against a hosted project.
-- Existing caller contracts must be independently reviewed before any forward-only remote rollout.

BEGIN;

-- Row security does not govern TRUNCATE or REFERENCES. Remove ambient direct grants from
-- anonymous/PUBLIC callers on every application relation in this isolated reconstruction.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public, private, accounting_private, inventory_private
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public, private, accounting_private, inventory_private
  FROM PUBLIC, anon;

-- These are trigger utility functions, not supported anonymous RPC endpoints.
REVOKE EXECUTE ON FUNCTION public.log_config_change() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon;

-- Enable RLS on the staging table whose source snapshot had it disabled. Keep direct grants
-- absent for anon/authenticated until an explicit application caller contract is reviewed.
ALTER TABLE private.tenant_accounting_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_accounting_links_deny_anon_reconstructed
  ON private.tenant_accounting_links FOR ALL TO anon
  USING (false) WITH CHECK (false);
CREATE POLICY tenant_accounting_links_read_member_reconstructed
  ON private.tenant_accounting_links FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounting_memberships m
      WHERE m.tenant_id = tenant_accounting_links.accounting_tenant_id
        AND m.user_id = (SELECT auth.uid())
        AND m.is_active = true
    )
  );

-- Future objects must be least-privilege by default. This intentionally differs from some
-- broad legacy default ACLs observed on staging; runtime callers must receive explicit grants.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- Schema-specific default ACL entries override/add to global defaults, so clear them too.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA accounting_private
  REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA accounting_private
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA accounting_private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_private
  REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_private
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory_private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
