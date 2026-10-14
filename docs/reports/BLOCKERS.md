# Blockers — Consolidation Single Main Repository

**Updated:** 2026-10-15  
**Branch:** `chore/consolidate-single-main-repo`

## BLOCKER B0-1 — Canonical reference repository inaccessible through connected GitHub API
- **Observed:** reads of `AGENTS.md` and `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` in `berkah-ajb-dev/Berkahtigaputeri` returned HTTP 404 through the current connector.
- **Impact:** cannot independently compare the designated canonical reference repo against the base and fork.
- **Needed:** restore connector access / confirm repository path or authorize the canonical copies in the base repo as the review reference.

## RESOLVED B0-2 — Cursor rule directory enumerated
- **Observed:** the first file-fetch/search attempts could not enumerate the directory. A follow-up call through the GitHub Contents API found and fetched `.cursor/rules/berkah-pos.mdc`, and its content was read.
- **Resolution:** mandatory Cursor rule review is now source-verified for the base repository's default branch. No code implementation was changed based on an unread rule.

## BLOCKER B0-3 — Original base-versus-fork SHA-256 diff report outstanding
- **Observed:** a hosted export workflow now creates and verifies the requested single Git bundle and source ZIP. Successful run: [38631992229](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229). Bundle artifact [11925864688](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229/artifacts/11925864688), SHA-256 `23937680b832b681da63ff437e8880b5b27c5b2fb8163ff6413e302aa6fa4677`; ZIP artifact [11926029695](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229/artifacts/11926029695), SHA-256 `afea2531398e0cb151a099e7bf1998b25be9cc231cd5c64c074fbc3807f06c64`. Exported commit: `dbea77b0ceb67f9492be1b36377620975b073c54`.
- **Impact:** bundle and ZIP are available, but they do not replace the requested SHA-256 file-by-file comparison between the exact original base/fork revisions.
- **Needed:** run a read-only hosted comparison of the base source commit `98befcd` and fork patch commit `b02a474`, generating a path/category/SHA-256 CSV; do not infer exact content identity from Git blob IDs alone.
- **Retention:** current export artifacts expire 2026-11-13; download them before then.

## BLOCKER B0-4 — Hosted staging-clone ACL and release approval
- **Observed:** captured state identifies staging (139 applied migrations, 67 audited relations, 169 routines) and staging-clone (12 migrations, 71 relations, 134 routines) as materially different projects. Both have 352 canonical keys and matching captured key/value fingerprints. Disposable CI run 38629812613 passes target baseline/Tenant A-B tests (50 pgTAP assertions), atomic versioning (19 assertions), the 139-body staging replay, and the separate 12-body clone replay with their respective catalog fingerprints. Read-only catalog evidence still shows broad effective clone anon access, including 32 public-schema SECURITY DEFINER routines executable by anon and effective anon SELECT on 55 application relations.
- **Impact:** canonical contract and disposable RPC behavior are tested, but hosted clone privilege safety, complete hostile cross-surface isolation, backup/restore, load/resilience, independent review, and production identity/approval remain unverified. No hosted database has been modified.
- **Needed:** review clone ACLs object-by-object and design only a narrow forward-only ACL migration; run the broader hostile Tenant A/B matrix and recovery/resilience tests in disposable environments; identify the production project and obtain independent approval. Keep remote migration push/repair/reset, grants/revokes, workbook apply and production deployment prohibited until then.

## Safety note
No SQL migration, data sync, production action, fork write, or push to `main` has been performed. Do not resolve these blockers by guessing at environment identity, disabling required RPCs globally, or weakening tenant authorization.


## Additional evidence — repository tree screening

The base and fork each expose 164 tracked blobs with identical path sets under the recursive Git tree endpoint. Git blob IDs identify one changed path, `.github/workflows/berkah-pos-trial-ci.yml`; no only-in-main or only-in-fork paths were detected. This is a screening result using Git object IDs, not the requested SHA-256 content-hash report, and must not be labelled as that final report. The base workflow includes more hosted Android SDK/NDK setup than the shorter fork version, so the canonical base version is retained pending verified CI results.


## Workflow evidence — useful, but not phase-completion evidence for consolidation

Draft PR #39 has green CI jobs at `185bfef085abeba479bc94f2df4b6fe7811363cf`: [workbook validation](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280597), [backend foundation](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280427), [POS app](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280123), and [clean replay](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280094). Its reports preserve the open clone-drift, least-privilege, hostile tenant-A/B, recovery, and production approval blockers. Do not treat this separate draft PR as merged or the consolidated branch as green.


## Resolved source-level risks — Phase 2

- **Resolved:** Admin atomic writes now merge the currently loaded JSONB row with the edited patch, so fields outside the visible form are preserved under the expected-version CAS.
- **Resolved:** feature flags now read from effective canonical configuration and save intentional tenant overrides through the same atomic `app_config` RPC rather than writing `tenants.features` directly.
- **Resolved:** the Admin's direct relational-only tenant insert path is disabled; onboarding points to the validated canonical workbook because the fixed 352-key inventory cannot safely gain an orphan tenant.
- **Verification:** [Canonical Workbook Validation run 38583997667](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38583997667) passed Admin JavaScript syntax checks, 10 Python tests, and the 352-key no-write workbook dry-run on the consolidation branch.
- **Remaining limit:** these source-level fixes do not resolve remote staging migration/schema/privilege drift, do not count as hostile Tenant A/B runtime tests, and do not establish a production-ready Supabase target. Do not apply remote migrations or blanket grants/revokes.


## Phase 5/6 runtime evidence — target tests green, release still blocked

- Phase 5 target-schema evidence: clean replay run 38629812613 passed 50 pgTAP assertions covering baseline security and targeted Tenant A/B effective-config/device isolation. The staging-clone replay passed 37 assertions and its own structural fingerprint. Neither result proves broad hosted API isolation.
- Phase 6 atomic-versioning evidence: the same run passed 19 pgTAP assertions against the real RPC in the disposable reconstructed target, including compare-and-swap, N-to-N+1, server-owned version, identity guards and audit history.
- Current backend guardrail: Supabase Backend Foundation CI run 38630659808 passed after the push filter was expanded for source-recovery/archive/workbook/replay helper changes.
- Still blocked: staging-clone broad anon ACLs, complete cross-surface hostile matrix, backup/restore and load/resilience, explicit production identity/approval, and Git bundle/ZIP.
