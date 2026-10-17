> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# AI insight security report

**Status: NOT APPLICABLE TO CURRENT TRACKED IMPLEMENTATION / FEATURE NOT FOUND.**

## Evidence
Repository search found no AI insight source files, AI-specific Supabase functions, OpenAI/LLM client integration, token usage logging or AI configuration. This does not prove no AI feature exists outside this repository.

## Required before introducing an AI feature
- Use a server-side proxy; no provider secret in Flutter or static JavaScript.
- Minimize and redact PII before prompt construction; define data retention and vendor processing policy.
- Treat database text and user content as untrusted data; separate instructions from data and never let model output authorize financial actions.
- Enforce per-tenant quotas, rate limits, hard spend caps, maximum input/output tokens and timeouts.
- Log tenant ID, request ID, model, token usage, latency and outcome without storing sensitive prompt content unnecessarily.
- Add deterministic fallback and make AI unavailable without blocking checkout/accounting.
- Validate output schema and ground numeric summaries in trusted queries; clearly label estimates.

## Tests not run
50 concurrent requests, year-scale summarization, prompt injection, PII leakage, quota enforcement, provider outage and hallucination guards. No feature implementation was found to test.