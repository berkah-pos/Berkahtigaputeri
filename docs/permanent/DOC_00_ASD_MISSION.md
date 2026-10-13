# HISTORICAL ISSUE INVENTORY — ASD MISSION (BASELINE 2026-10-05)
> **TRIGGER ROUTING:** When the user says "asd", "ASD", or "lanjut misi", read this file only as a historical issue inventory. First follow root `AGENTS.md` and the mandatory preflight. Revalidate each listed item against the current branch/HEAD before acting.

> **Historical notice:** The base SHA, branch counts, CI summary, checked boxes, and issue descriptions below were recorded on 2026-10-05. They are not a current backlog, current-head certification, or proof that any test passed on today's revision. The canonical configuration authority is `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`; execution follows `AGENTS.md` and `DOC_00_MASTER_ROADMAP.md`.

**Repo:** berkah-ajb-dev/Berkahtigaputeri
**Base HEAD audited:** 68826ec66e220b82f40c022bc27fa9a3f24b0f2b (17 branches, CI 7/7 green)
**Audit result:** 18 issues - 8 HIGH, 6 MED, 4 LOW - repo green but NOT synchronized
**Full audit:** See DOC_08_AUDIT_18_ISSUES.md in same folder

## MISSION: Make repo 100% synchronized (Docs == Code == Workflows == RLS == UAT) + persistence on main

### PHASE 0 - PERSISTENCE (THIS FILE) [DONE after merge]
- [x] Create DOC_00_ASD_MISSION.md on main
- [x] Create DOC_08_AUDIT_18_ISSUES.md
- [x] Create.github/ASD_PROMPT.md as quick trigger

### PHASE 1 - URGENT GENERAL REQUIREMENTS (P0) - UAT BLOCKER
- [x] **P0-1 HIGH-1 Auth vs RLS:** FIXED - DeviceAuthService + ProvisioningScreen + AuthGate in main.dart
  Fix: Add device provisioning/sign-in before ConfigService, bind devices.user_id
  Files: pos-app/lib/main.dart:9-23, DOC_03_RLS_AUTH.sql

- [x] **P0-2 HIGH-2 Migration broken:** FIXED - ADD COLUMN IF NOT EXISTS user_id/platform in ownership migration
  Fix: ADD COLUMN IF NOT EXISTS user_id uuid, platform text in ownership migration

- [ ] **P0-3 HIGH-6 Feature flags dual authority:** btp-admin/feature-flags.js writes tenants.features, APK reads app_config first
  Fix: Admin must use update_app_config_atomic RPC, tenants.features = projection only

### PHASE 2 - HIGH (Doc-Doc / Doc-Workflow)
- [ ] P1-4 DOC_02_VERIFICATION.md still 3-layer, need 5-layer GLOBAL->TEMPLATE->TENANT->SERVICE->DEVICE
- [ ] P1-5 DOC_03_VERIFICATION.md expects anon SELECT allowed but RLS denies
- [ ] P1-6 DOC_04_VERIFICATION.md counts 5 keys with POS+Akuntansi together, missing TEMPLATE
- [ ] P1-7 DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md points to deleted branch fix/final-pos-canonical-sync, not main@68826ec
- [ ] P1-8 DOC_07 overstates fail-closed: PRs skip live Supabase check (final-pos-sync.yml dry-run only)

### PHASE 3 - MEDIUM (Parity bugs)
- [ ] MED-10 config_service.dart fallback not normalize service (POS vs pos) - add normalizeService()
- [ ] MED-11 inherited_from_template null vs empty string parity Flutter vs SQL
- [ ] MED-12 config_service_test.dart tests only 4 layers, missing TEMPLATE
- [ ] MED-13 DOC_05_FEATURE_FLAGS.sql uses INSERT ON CONFLICT instead of atomic RPC
- [ ] MED-14 scripts/sync_excel_to_supabase_legacy.py bypasses versioning

### PHASE 4 - LOW (Reproducibility)
- [ ] LOW-15 home_screen.dart:269 "config 3 layer" -> "5 layer"
- [ ] LOW-16 devices app_version='a19cb3f' legacy seed vs pubspec 1.0.0+2
- [ ] LOW-17 build.yml Flutter channel: stable not pinned
- [ ] LOW-18 main.dart hardcoded SUPABASE defaults, no.env.example / dart-define

### Current execution protocol for the "asd" trigger

1. Read root `AGENTS.md` and all files in its mandatory order, including the canonical decision, roadmap, DOC_12, DOC_13, scoped schema/auth/Admin contracts, and workbook validator.
2. Confirm the repository, current default branch/HEAD, open PRs, and recent Actions runs. Do not treat the 2026-10-05 snapshot below as current.
3. Re-check candidate findings against current source and current roadmap phase. Record only findings reproduced on the revision being changed.
4. Make scoped changes on a feature/fix/documentation branch and submit a PR. Never write implementation changes directly to `main`.
5. Run available validation and report exact evidence. If a tool, credential, local checkout, or live environment is unavailable, mark that check NOT RUN / NOT VERIFIED; do not assert a target such as "7/7 green" without current run evidence.
6. Active workflows must use GitHub-hosted `ubuntu-24.04` runners. Do not use or add a self-hosted workstation runner dependency.
7. Update the issue inventory only when a finding has been verified as fixed on the relevant branch; include its path, line, commit/PR, and test evidence.

### STATE LOG
- 2026-10-05 00:22Z main@68826ec audit 18 issues, 27->17 branches cleaned, CI green
- 2026-10-05 P0 mission doc created - next: P0-1 auth

### Historical done criteria (not current acceptance)
The old checklist is not sufficient for release approval. Use the current acceptance gates in `docs/permanent/DOC_00_MASTER_ROADMAP.md` and the mandatory evidence report in DOC_12. Phase 7 requires fresh current-head certification and executed evidence.
