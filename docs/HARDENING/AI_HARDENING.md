> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated hardening/audit artifact was written against an earlier source or Supabase-era runtime. Preserve its original findings as history only. Do not follow its Supabase/database commands or interpret its statuses as current platform certification. Current platform authority: [owner ADR](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target/acceptance: [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md); current snapshot: [architecture conflict register](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md); full cross-document map: [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

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