> **HISTORICAL AUDIT SNAPSHOT — BASELINE 2026-10-05.** This issue table was recorded against an older revision and is retained for traceability. Its rows are candidates to re-check, not proof that the same issues remain open or fixed on current main. Before execution, follow `AGENTS.md`, use `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` as the configuration authority, and verify each finding against the current source and roadmap phase.

---

# Audit 18 Issues - main@68826ec - Full Report
Source: 16m43s audit, 17 branches, 4 workflows green

| # | Sev | Type | File A | File B | Line | Conflict |
|---|-----|------|--------|--------|------|----------|
|1|HIGH|Doc-Code|main.dart:9-23|DOC_03_RLS_AUTH.sql|No auth flow but RLS denies anon|
|2|HIGH|Doc-Code|DOC_02_SCHEMA_V1.sql|DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql|devices.user_id/platform missing in base|
|3|HIGH|Doc-Doc|DOC_03_VERIFICATION.md:7-11|DOC_03_RLS_AUTH.sql|Anon SELECT expected PASS but should DENY|
|4|HIGH|Doc-Doc|DOC_02_VERIFICATION.md|README/canonical|3 layer model, missing TEMPLATE|
|5|HIGH|Doc-Doc|DOC_04_VERIFICATION.md:24-31|canonical|5 keys counting POS+Akuntansi together|
|6|HIGH|Code-Code|btp-admin/feature-flags.js:4-5|config_service.dart:94-116|Admin tenants.features vs APK app_config|
|7|HIGH|Outdated|DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md:3-10|live branch|Points to fix/final-pos-canonical-sync deleted|
|8|HIGH|Doc-Workflow|DOC_07 fail-closed|final-pos-sync.yml|PR skip secrets check but doc says fail-closed|
|9|MED|Doc-Doc|DOC_05_FEATURE_FLAGS.md|DOC_02_FINAL_POS...|tenants.features canonical vs legacy|
|10|MED|Code-Code|config_service.dart|Admin/RPC|Fallback not lowercase service|
|11|MED|Code-Code|config_service.dart:184-225|DOC_08_RPC|inherited_from_template null vs empty|
|12|MED|Doc-Code|config_service_test.dart:5-12|canonical|Test 4 layers not 5|
|13|MED|Doc-Code|DOC_05_FEATURE_FLAGS.sql|DOC_06_AUDIT_VERSIONING.md|Bypass atomic RPC|
|14|MED|Code-Code|sync_excel_to_supabase_legacy.py:555-584|canonical|Legacy direct upsert|
|15|LOW|Doc-Code|home_screen.dart:269|canonical|String "3 layer"|
|16|LOW|Outdated|DOC_02_SCHEMA_V1.sql|pubspec|app_version a19cb3f|
|17|LOW|Doc-Workflow|build.yml|pubspec.yaml|Flutter not pinned|
|18|LOW|Doc-Workflow|main.dart:9-16|build.yml|Hardwired defaults no dart-define|

Top 3 breakers: 1) Auth vs RLS UAT blocker 2) Fresh DB migration chain 3) Feature flags dual authority
Deleted refs checked: ai-personal-ledger 0, fix/analyze-211 0, chore/* 0, feat/apotek-fefo-v2 0, pages-* 0, but DOC_07 still refs fix/final-pos-canonical-sync
