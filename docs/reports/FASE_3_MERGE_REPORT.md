# FASE 3 — REPOSITORY DIFF AND MERGE DECISION

**Status: GREEN for the exact original base/fork file-diff gate and reviewed branch integration.**  
**Hosted diff run:** [38632527070](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070)  
**Working branch:** chore/consolidate-single-main-repo

## Exact source revisions compared

- Base: berkah-pos/Berkahtigaputeri, commit 98befcd5807585dd0c1b84085fc4a6e73fd90f2b.
- Fork patch: Andisatriawan/Berkahtigaputeri, commit b02a47448eddfc2db6efb1c336b6cda0b4c85556.
- Comparator: scripts/compare_repos_sha256.py, executed in a GitHub-hosted runner after detached checkouts of those exact commits.
- Ignored directory names: .git, __pycache__, build, node_modules.
- Report: [CSV + JSON artifact 11926312229](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070/artifacts/11926312229); the CSV contains one row per path in the union, status, each SHA-256, and byte counts.

| Status | Count |
|---|---:|
| IDENTICAL | 163 |
| MODIFIED | 1 |
| ONLY_IN_MAIN | 0 |
| ONLY_IN_FORK | 0 |
| Union paths | 164 |

## Sole modification and decision

Path: .github/workflows/berkah-pos-trial-ci.yml

- Base: 5,654 bytes; SHA-256 b4741fdcec2aa142eae5ab3c1d702c7d6e5abf01d339eeda3c80a8adffc41f9f.
- Fork: 3,721 bytes; SHA-256 0279c8906a89b87d6c185954e6f4939a6d5bbcf2d0900545d6c9f794b5a89350.

**Decision: retain the base workflow.** It has a verified official Flutter stable archive download, SDK location checks, NDK installation/retry, explicit non-production smoke signing, and uploads the debug APK plus smoke APK/AAB. The fork's shorter workflow does not retain all these checks and uploads only the debug APK. CI and package identity constraints favor preserving the base version.

## Consolidation safety

The comparison was read-only against the original source commits. Ongoing consolidation changes were committed only on the consolidation branch. No fork write or direct main push was performed. The canonical reference repository remains unavailable through the connected GitHub API; its 404 state is a separate Phase 0 limitation.

**Conclusion:** original source-file identity is measured using content SHA-256, not inferred from Git blob IDs. This phase is GREEN for source diff evidence; it does not certify Supabase security or production readiness.
