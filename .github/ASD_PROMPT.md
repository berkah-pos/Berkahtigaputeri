# Trigger file for "asd"

When the user says "asd", "ASD", or "lanjut misi":

1. Read root `AGENTS.md` and follow its mandatory read order.
2. Treat `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` as the sole authority for configuration inheritance.
3. Use `docs/permanent/DOC_00_ASD_MISSION.md` and `docs/permanent/DOC_08_AUDIT_18_ISSUES.md` only as historical issue inventories. Re-check every item against the current branch and HEAD before acting; unchecked boxes are not proof that an issue remains open.
4. Work in milestone order from `docs/permanent/DOC_00_MASTER_ROADMAP.md`, make scoped changes on a branch, and submit a pull request. Never write implementation changes directly to `main`.
5. Report source inspection, executed tests, staging/production verification, and unresolved risks as separate evidence classes. Do not claim checks that were not run.
