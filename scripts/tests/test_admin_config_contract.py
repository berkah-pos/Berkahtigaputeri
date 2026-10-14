from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def source(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class AdminCanonicalConfigContractTests(unittest.TestCase):
    def test_atomic_layer_update_preserves_unedited_canonical_fields(self):
        editor = source("btp-admin/editor-core.js")
        self.assertIn("const current=rows[key]?.value;", editor)
        self.assertIn("const next={...current,...payload};", editor)
        self.assertIn("p_new_value:next", editor)
        self.assertNotIn("p_new_value:payload", editor)
        self.assertIn("p_expected_version:loadedVersion", editor)
        self.assertIn("error.code==='40001'", editor)

    def test_tenant_metadata_and_features_use_one_atomic_config_write(self):
        editor = source("btp-admin/editor-core.js")
        page = source("btp-admin/edit.html")
        self.assertIn("async function saveTenant(extra={})", editor)
        self.assertIn("saveLayer('tenant:'+tenant,payload)", editor)
        self.assertNotIn(".from('tenants').update(", editor)
        self.assertIn("const patch=BTP_FEATURES.patch()", page)
        self.assertIn("BTP_EDITOR.saveTenant(patch)", page)
        self.assertIn("BTP_FEATURES.markSaved()", page)
        self.assertNotIn("BTP_FEATURES.save()", page)

    def test_admin_feature_flags_resolve_from_canonical_effective_config(self):
        flags = source("btp-admin/feature-flags.js")
        editor = source("btp-admin/editor-core.js")
        self.assertIn("getEffectiveConfig:()=>merge(", editor)
        self.assertIn("BTP_EDITOR.getEffectiveConfig()", flags)
        self.assertIn("function patch()", flags)
        self.assertIn(":{features:next}", flags)
        self.assertNotIn(".from('tenants')", flags)
        self.assertNotIn('.from("tenants")', flags)
        self.assertNotIn("async function save()", flags)

    def test_effective_config_uses_five_layers_and_one_requested_service(self):
        editor = source("btp-admin/editor-core.js")
        flutter = source("pos-app/lib/core/config/config_service.dart")
        self.assertIn("`template:${templateId}`", editor)
        self.assertIn("`tenant:${tenant}:service:${requestedService}`", editor)
        self.assertIn("`device:${deviceId}`", editor)
        self.assertIn("v!=='pos'&&v!=='akuntansi'", editor)
        self.assertIn("'get_effective_config'", flutter)
        self.assertIn("'p_service': service", flutter)
        self.assertIn("'p6.effective.$tenantId.$deviceId.$service'", flutter)
        self.assertNotIn(".from('app_config')", flutter)
        self.assertNotIn("_fallbackSelectAndMerge", flutter)

    def test_new_tenant_insert_cannot_bypass_the_352_key_contract(self):
        clients = source("btp-admin/clients.html")
        self.assertNotIn("async function addTenant", clients)
        self.assertNotIn(".from('tenants').insert(", clients)
        self.assertNotIn("$('add').onclick", clients)
        self.assertIn("canonical workbook", clients)
        self.assertIn("352-key", clients)

    def test_canonical_sync_remains_atomic_and_inventory_guarded(self):
        sync = source("scripts/sync_excel_to_supabase.py")
        legacy_parser = source("scripts/sync_excel_to_supabase_legacy.py")
        architecture = source("docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md")
        self.assertIn("update_app_config_atomic", sync)
        self.assertIn("--expect-keys", sync)
        self.assertIn("EXPECTED_KEYS = 352", legacy_parser)
        self.assertIn("GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE", architecture)
        self.assertIn("app_config(key PRIMARY KEY, value JSONB, updated_at)", architecture)


if __name__ == "__main__":
    unittest.main()
