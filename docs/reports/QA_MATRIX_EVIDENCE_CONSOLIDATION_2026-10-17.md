# QA Matrix and Evidence Consolidation — 2026-10-17

**Reviewed repository:** `berkah-pos/Berkahtigaputeri`  
**Exact main commit reviewed:** `5b0ad4d5808008c33e6cb66176e3433fad5902a0`  
**Canonical matrix:** `config/ci/required-check-matrix.json`  
**Single exact-head evidence index:** `docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json`  
**Disposition:** **BLOCKED** — no release acceptance is claimed.

## 1. Live state and change scope

Live metadata shows PR [#53](https://github.com/berkah-pos/Berkahtigaputeri/pull/53) open/draft at head `091594a18a0e648d557874066127fd5d24c83a42` and PR [#58](https://github.com/berkah-pos/Berkahtigaputeri/pull/58) open/draft at head `31fa8628821ae107931d8ead74442b25af01de46`. Both target `main` but carry stale base SHA `d7ee23cfaada3405416b01d9e127e32b07fb1a38`, not reviewed main `5b0ad4d5808008c33e6cb66176e3433fad5902a0`.

- PR #53 changes: `config/ci/required-check-matrix.json`, `docs/permanent/ACCEPTANCE_MATRIX_CI_EVIDENCE.md`, `docs/reports/CI_EVIDENCE_SNAPSHOT_2026-10-16.md`. Its matrix is a useful source schema with 12 required checks.
- PR #58 changes: `docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md`, `docs/reports/acceptance-matrix-ci-evidence-2026-10-16.json`. Its JSON has 13 historical gates and unique critical/high security-closure and exact-run records.

The new proposal uses the #53 machine-readable matrix as a base, preserves the strongest evidence-quality rules, ports #58's unique verified records, adds the missing independent gates, and defines exactly one canonical matrix plus one current exact-head index. The old PRs and branches were left untouched.

## 2. Fresh workflow/evidence comparison

The inspected commit-bound workflow listings and job records confirm the following scope boundaries:

| Exact tested SHA | Workflow/run | Observed result | Correct interpretation |
|---|---|---|---|
| `6e31574ecc04ecae6a535fe409cf415ec18655cc` (PR #48) | [Workbook 38856048876](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876) | PASS | Workbook-only scope; no artifacts returned by the inspected artifact-list API. |
| `6e31574ecc04ecae6a535fe409cf415ec18655cc` (PR #48) | [Flutter 38856048883](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048883) | PASS | Flutter analysis/tests and local harness only. Artifact `phase5-flutter-check-output` exists but its contents/checksum were not inspected. No API parity claim. |
| `6e31574ecc04ecae6a535fe409cf415ec18655cc` (PR #48) | [Backend 38856048750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048750) | FAIL at preflight | DOC_14 runtime contract guard failed before Composer; downstream backend tenant test job was skipped. |
| `6e31574ecc04ecae6a535fe409cf415ec18655cc` (PR #48) | [POS 38856048817](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048817) | FAIL at preflight | KVM2 contract guard failed; database, Flutter and Android steps were skipped. |
| `ef3a71894db8461a596db5cd51b6bdf764c8f039` (PR #52) | [Flutter 38900260816](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260816) | PASS | Includes local Flutter tests and Android emulator install/launch. Two artifacts were listed but their contents/checksums were not inspected. Does not prove API sync. |
| `ef3a71894db8461a596db5cd51b6bdf764c8f039` (PR #52) | [Backend 38900260758](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260758) and [POS 38900260866](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260866) | FAIL at preflight | Composer/target database and downstream tests were not reached. The corresponding acceptance gates remain NOT RUN / NOT VERIFIED. |
| `e108f5629d688ac2376f77ef1ebdc505501b1d60` (earlier PR #50 head) | [Backend 38886111739](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111739), [POS 38886111728](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111728), [Phase 2 38886111736](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111736) | FAIL | Actual MariaDB 11.4 provisioning/grant tests failed. Some downstream checks were skipped. The separate image-smoke job in run 38886111739 passed only its build/boot scope. |
| `e108f5629d688ac2376f77ef1ebdc505501b1d60` (earlier PR #50 head) | [Workbook 38886111750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111750) | PASS | Later verified in commit-bound run listing; separate from the backend/security failures and not a PG gate. |
| `29127e8ecc9d2c4253939e26a1aa54a59a07cbff` (later PR #50 head) | [Workbook 38914169711](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169711) | PASS | Workbook-only scope at this later SHA. |
| `29127e8ecc9d2c4253939e26a1aa54a59a07cbff` (later PR #50 head) | [Backend 38914169687](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169687), [POS 38914169548](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169548), [Phase 2 38914169628](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38914169628) | FAIL | MariaDB 11.4 provisioning/grant/integration tests failed; some downstream checks were skipped. The production-image subjob in 38914169687 passed only its limited image boot/route/version smoke. |
| `6fe02dd727fbc6ac9c12b65645938967c1a6b7b4` (older PR #48 parent head) | [Flutter 38778107415](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107415), [Workbook 38778107421](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107421) | PASS | Stale parent-head passes, retained as history and ineligible for newer candidate/main. |
| `6fe02dd727fbc6ac9c12b65645938967c1a6b7b4` (older PR #48 parent head) | [Backend 38778107422](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107422), [POS 38778107426](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38778107426) | FAIL | Historical Composer/environment-preparation failures; downstream MariaDB and Flutter tests were skipped. Stale for PR #48 head 6e31574…. |
| `aab154f87342f2a02a1319e1d370ce831dbef522` | [Baseline 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) | PASS | PostgreSQL 17 baseline/install/boot/fresh migration/image smoke passed at this recorded SHA; not exact current main `5b0ad4d5808008c33e6cb66176e3433fad5902a0` and not proof of provisioning grants, API parity, restore/load or deployment. No artifact was returned by the inspected artifact-list API. |
| `091594a18a0e648d557874066127fd5d24c83a42` (PR #53 current head) | [Workbook 38906173717](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38906173717) | PASS | Exact-head workbook-only job; no artifact was returned by inspected artifact listing. The PR base is stale and this does not establish the complete canonical workbook/hash gate on current main. |
| `31fa8628821ae107931d8ead74442b25af01de46` (PR #58 current head) | Exact-head PR-triggered lookup | NOT RUN / NOT VERIFIED | The inspected first-page run lookup returned no run. This is recorded as unverified, not as an exhaustive assertion that no run exists. |

**Important:** workflow run conclusions and subjob conclusions are not interchangeable. PR #50 image smoke passed in a separate job while its MariaDB-backed tenant security tests failed. Both are preserved as independent scope records; the narrow smoke success cannot override the integration failure.

## 3. Why the canonical matrix has 15 gates

The canonical matrix intentionally prevents the prior bundles from conflating:

1. dependency/lockfile/security audit;
2. workbook count and deterministic hash;
3. five-layer config precedence;
4. client unit tests/local SQLite atomicity;
5. backend boot/routes/image smoke;
6. PostgreSQL 17 central/tenant migrations;
7. PostgreSQL 17 provisioning and real grants;
8. tenant/host/worker isolation and authorization negatives;
9. authenticated API parity;
10. Flutter cloud sync/outbox idempotency/replay/conflicts;
11. backup/restore of central, all tenant databases, files/objects and recovery keys;
12. load and resource/capacity evidence;
13. isolated staging acceptance;
14. production release/cutover acceptance;
15. critical/high security closure.

The exact-head index records every historical result with the exact tested SHA, run ID/URL, workflow/job identity where available, engine, environment, scope, result status, and artifact inspection disposition. Missing runner metadata, historical base SHA or artifacts remain explicitly unrecorded/unverified.

## 4. Old-record mapping to the one canonical authority

| Old record | Canonical destination | Disposition |
|---|---|---|
| PR #53 `config/ci/required-check-matrix.json` / AC-01–AC-03 | Canonical matrix AC-01–AC-03 | Retained as the machine-readable starting point; current stack references and status policy corrected. |
| PR #53 AC-04 | AC-05 and AC-06 | Split runtime boot/routes/auth smoke from clean PostgreSQL 17 migrations. |
| PR #53 AC-05 | AC-07 | Retained as real PostgreSQL 17 provisioning/grant proof, with MariaDB rows explicitly non-target. |
| PR #53 AC-06–AC-07 | AC-08 and AC-09, plus AC-15 where security closure applies | Host/authorization negatives, worker isolation and broader API parity are no longer merged into one result. |
| PR #53 AC-08–AC-09 | AC-04 and AC-10 | Client/local SQLite test evidence separated from end-to-end cloud sync/outbox behavior. |
| PR #53 AC-10 | AC-05, AC-13 and AC-14 | Image smoke, staging and production are independent acceptance gates. |
| PR #53 AC-11–AC-12 | AC-11–AC-12 | Restore and load requirements retained; no runbook or configuration counts as an executed pass. |
| PR #58 A01–A03 | AC-01–AC-03 | Same required contracts; duplicate gate definition not copied. |
| PR #58 A04–A07 | AC-05–AC-08 | Boot, PG migrations, grants, host/auth tests and worker isolation separated. |
| PR #58 A08–A10 | AC-04, AC-05, AC-10, AC-13 and AC-14 | Client, API/sync and deployment environments split by scope. |
| PR #58 A11–A12 | AC-11–AC-12 | Restore and load evidence retained as distinct gates. |
| PR #58 A13 critical/high closure | AC-07, AC-08 and AC-15 | Security issue remains blocked until accepted-engine least-privilege/isolation proof and independent review pass. |
| PR #53 `docs/reports/CI_EVIDENCE_SNAPSHOT_2026-10-16.md` | Immutable historical source | Do not rewrite; its exact run/sha records are referenced in the index. |
| PR #58 `docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md` | Immutable historical source | Do not rewrite; unique dated claims are ported to exact-head index rows. |
| PR #58 `docs/reports/acceptance-matrix-ci-evidence-2026-10-16.json` | Immutable historical source → new single index `docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json` | No duplicate new current evidence index is added. Old index remains intact on its original PR branch. |

PR #53 and PR #58 remain open and their branch histories are not changed by this proposal. The old e108f562… and later 29127e8… PR #50 heads, the older 6fe02dd… PR #48 parent and newer 6e31574… PR #48 head remain separate records; no later row overwrites an earlier failure or success.

## 5. Validation commands

Run from the repository root after checking out the proposed PR:

```bash
python -m json.tool config/ci/required-check-matrix.json >/dev/null
python -m json.tool docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json >/dev/null

python - <<'PY'
import json
from pathlib import Path

matrix = json.loads(Path("config/ci/required-check-matrix.json").read_text())
index = json.loads(Path("docs/reports/acceptance-matrix-ci-evidence-2026-10-17.json").read_text())
allowed = {"PASS", "FAIL", "BLOCKED", "NOT RUN / NOT VERIFIED"}

checks = matrix["required_checks"]
assert len(checks) == 15
assert len({row["id"] for row in checks}) == len(checks)
assert all(row["required"] is True and row["status"] in allowed for row in checks)
assert matrix["review_snapshot"]["current_main_sha"] == "5b0ad4d5808008c33e6cb66176e3433fad5902a0"
assert matrix["review_snapshot"]["overall_status"] != "PASS"

records = index["records"]
assert len({row["record_id"] for row in records}) == len(records)
for row in records:
    assert row["result_status"] in allowed
    assert row["pr_head_sha"]
    assert row["workflow_name"]
    assert row["engine"]
    assert row["environment"]
    assert row["scope"]
    # A null run ID is permitted only for an explicit unverified/no-run record.
    if row["run_id"] is None:
        assert row["result_status"] == "NOT RUN / NOT VERIFIED"
assert index["current_refs"]["live_main_sha"] == "5b0ad4d5808008c33e6cb66176e3433fad5902a0"
assert index["overall_status"] != "PASS"
print(f"Validated {len(checks)} required gates and {len(records)} immutable/current evidence records.")
PY

git diff --check
git diff --name-status
```

The authoring-side JSON parse, status-enum and unique-ID assertions passed before the files were submitted through the GitHub contents API. Local `git diff --check` and application tests must still be run on the actual fetched PR checkout; this is documentation/CI-matrix work, not evidence that any product gate passed.

## 6. Explicit non-claims

This change does not modify application code, CI workflow definitions, branch protection, databases, credentials, staging or production. It does not close/delete PR #53/#58 or delete their branches. Overall acceptance remains **BLOCKED**; missing gates must be run on one integrated candidate SHA against the selected PostgreSQL 17 target.
