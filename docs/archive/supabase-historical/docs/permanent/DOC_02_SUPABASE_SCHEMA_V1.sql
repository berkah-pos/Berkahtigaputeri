-- DOC_02 - SUPABASE SCHEMA CONTRACT INDEX / FINAL POS
--
-- IMPORTANT:
-- This filename is retained because AGENTS.md and historical documents reference it.
-- It is NOT a production seed file and must not re-create the retired three-layer model.
--
-- Canonical architecture authority:
--   docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
-- Canonical data authority:
--   config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
-- Canonical synchronization validator:
--   scripts/sync_excel_to_supabase.py
-- Current security migration:
--   supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql
--
-- FINAL POS CONFIG CONTRACT
-- -------------------------
-- app_config(key PRIMARY KEY, value JSONB, updated_at)
--
-- Canonical key forms:
--   global
--   template:<TEMPLATE_ID>
--   tenant:<tenant_id>
--   tenant:<tenant_id>:service:<service>
--   device:<device_id>
--
-- Canonical inventory:
--   1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 keys
--   keyset MD5 = 1fd3d64219ecc7c333453c20da80e295
--
-- Canonical merge order:
--   GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
--
-- Do not add illustrative production app_config seeds here. Production configuration
-- is workbook-owned and is synchronized/versioned through the canonical importer and
-- atomic RPC. A partial seed is not a valid replacement for the 352-key authority.
--
-- Core relational projections used by Final Pos include:
--   public.tenants
--   public.devices
--   public.licences
--   public.app_config
--   public.config_history
--   public.tenant_services
--
-- Security and resolver contracts are defined in:
--   docs/permanent/DOC_03_RLS_AUTH.sql
--   docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql
--   docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql
--
-- Live verification query (read-only):
select
  count(*) as app_config_count,
  md5(string_agg(key, E'\n' order by key)) as keyset_md5,
  count(*) filter (where key = 'global') as global_count,
  count(*) filter (where key like 'template:%') as template_count,
  count(*) filter (where key like 'tenant:%' and key not like '%:service:%') as tenant_count,
  count(*) filter (where key like 'tenant:%:service:%') as service_count,
  count(*) filter (where key like 'device:%') as device_count
from public.app_config;
