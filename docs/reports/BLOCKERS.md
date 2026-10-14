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

## RESOLVED B0-3 — Original SHA-256 diff and repository exports delivered
- **SHA-256 evidence:** [comparison run 38632527070](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070) successfully compared base commit `98befcd5807585dd0c1b84085fc4a6e73fd90f2b` with fork commit `b02a47448eddfc2db6efb1c336b6cda0b4c85556`. It found 164 paths, 163 identical files, one modified workflow, and no main-only/fork-only paths. CSV artifact: [11926312229](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070/artifacts/11926312229).
- **Exports:** the latest verified export is [run 38632526847](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632526847) on commit `d6b23354765d59899e89f55c1899cad8e87a9e79`. Git bundle [artifact 11927660275](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632526847/artifacts/11927660275), size 1,790,283 bytes, SHA-256 `d1690b94822cebdd9982114e8b7df4b6679d0b2bfefef8a8bfd39ea4d3b61ed7`; source ZIP [artifact 11926905796](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632526847/artifacts/11926905796), 331 files excluding `.git`, size 945,092 bytes, SHA-256 `9b00099970ff1d5cc9ec3b1a78669cc32fa51d7d6c63b6890002b53d63872050`. Export manifest: [artifact 11927515307](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632526847/artifacts/11927515307).
- **Retention:** these GitHub Actions artifacts expire 2026-11-13; download and store independent copies before then.
- **Remaining environment limit:** no local developer worktree was created, so literal local `git status` / root `ls -la` outputs were not obtained. The canonical reference repository still returned HTTP 404 through the current connector.
## BLOCKER B0-4 — Hosted staging-clone ACL and release approval
- **Observed:** captured state identifies staging (139 applied migrations, 67 audited relations, 169 routines) and staging-clone (12 migrations, 71 relations, 134 routines) as materially different projects. Both have 352 canonical keys and matching captured key/value fingerprints. Disposable CI run 38629812613 passes target baseline/Tenant A-B tests (50 pgTAP assertions), atomic versioning (19 assertions), the 139-body staging replay, and the separate 12-body clone replay with their respective catalog fingerprints. Read-only catalog evidence still shows broad effective clone anon access, including 32 public-schema SECURITY DEFINER routines executable by anon and effective anon SELECT on 55 application relations.
- **Impact:** canonical contract and disposable RPC behavior are tested, but hosted clone privilege safety, complete hostile cross-surface isolation, backup/restore, load/resilience, independent review, and production identity/approval remain unverified. No hosted database has been modified.
- **Needed:** review clone ACLs object-by-object and design only a narrow forward-only ACL migration; run the broader hostile Tenant A/B matrix and recovery/resilience tests in disposable environments; identify the production project and obtain independent approval. Keep remote migration push/repair/reset, grants/revokes, workbook apply and production deployment prohibited until then.

## Safety note
No SQL migration, data sync, production action, fork write, or push to `main` has been performed. Do not resolve these blockers by guessing at environment identity, disabling required RPCs globally, or weakening tenant authorization.


## Additional evidence — repository tree screening

The initial API tree screening found 164 tracked blobs per snapshot with identical path sets and one different Git blob ID. The subsequent exact-commit SHA-256 comparison in run 38632527070 supersedes that initial screening: 163 files are content-identical, the only modified file is `.github/workflows/berkah-pos-trial-ci.yml`, and there are no only-in-main or only-in-fork files. The per-path SHA-256 report and rationale for retaining the base workflow are recorded in resolved blocker B0-3.


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
