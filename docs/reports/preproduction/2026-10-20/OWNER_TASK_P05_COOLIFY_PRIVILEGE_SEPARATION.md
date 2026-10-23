# Owner Task Prompt — Prompt 05 Live Coolify Privilege Separation

**Task class:** Read-only DevOps/SRE + PostgreSQL security audit  
**Priority:** P1 release blocker  
**Task branch if report changes are needed:** `audit/p05-coolify-runtime-privilege-separation-2026-10-23`  
**Expected report:** `docs/reports/preproduction/2026-10-20/05_COOLIFY_RUNTIME_PRIVILEGE_AUDIT.md`

## Copy/paste task prompt

You are the independent DevOps/SRE and PostgreSQL security specialist for Berkah POS. Verify the **actual deployed Coolify configuration**, not just the repository's Docker Compose example. This task is read-only. Do not change service configuration, rotate credentials, run migrations, create/drop roles or databases, restart/redeploy services, or approve production.

### Authority and scope

Read repository `AGENTS.md` and follow its mandatory permanent-document reading order. Treat the current owner architecture as authoritative: private PostgreSQL 17, one central database plus a distinct database per tenant, restricted central/tenant runtime identities, and a separate private provisioning worker. Do not use Supabase or reinterpret older MariaDB proposals as current authority.

### Required evidence collection

1. Identify the exact Coolify project, running service names, current image tags/digests and source revision. Do not assume this unmerged feature branch is what production currently runs.
2. Inspect **variable names only** for the deployed web service and every ordinary queue/worker service. Confirm none receives `PROVISIONER_*`, `MIGRATOR_*`, PostgreSQL superuser/root credentials, or a bulk secret environment file. Never reveal, copy, log, or paste secret values.
3. Inspect the private provisioning service, if one exists. Confirm it alone receives required `PROVISIONER_*` credentials, uses a dedicated non-superuser broker, and has no public domain, public ingress, or published port. Verify it joins only the required private network(s) to reach PostgreSQL. Confirm the PostgreSQL service itself is not publicly exposed except through an explicitly approved private access path.
4. From the existing application/service context, perform only approved read-only PostgreSQL identity/catalog queries. For central runtime and broker identities, record `current_database()`, `current_user`, `session_user`, and role attributes (`rolsuper`, `rolcreatedb`, `rolcreaterole`, `rolreplication`, `rolbypassrls`). Do not query or output password hashes. Confirm central/web/ordinary-worker identities are not superusers, cannot create databases/roles, do not bypass RLS or replicate, and are not the provisioning broker. Confirm the broker is non-superuser, has only the required `CREATEDB`/`CREATEROLE` capability, and has neither replication nor RLS bypass.
5. Confirm provisioner and migrator credentials are absent from image build args, Dockerfile `ENV`, checked-in files, web/ordinary-worker process environments, logs, and publicly exposed configuration. Report only the presence/absence and variable names, never values.
6. Retain sanitized evidence references: Coolify service/settings screenshots or exports with all values masked, image digest/revision, relevant network/ingress configuration, and read-only role-attribute query results. Do not attach unsanitized configuration dumps.

### Acceptance matrix

Record each item as PASS, FAIL, or NOT VERIFIED with evidence location:
- Running image/source revision is identified.
- Web and ordinary queue/worker services have no `PROVISIONER_*` or `MIGRATOR_*` variables and no broad env-file/secret injection.
- Central runtime role is distinct from broker and has no `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION`, or `BYPASSRLS` attributes.
- Provisioner service is private and has no public ingress/published ports.
- Only the provisioner service holds broker credentials; they are not baked into images or passed to ordinary processes.
- Broker role attributes match the repository's fail-closed contract.
- No evidence collection step modified production state.

### Stop conditions

If the active Coolify project/configuration is unavailable or the owner has not authorized read-only access, STOP. Do not infer deployment state from `docker-compose.yml`, `.env.example`, CI, comments, or this report. Return a precise owner request for the required sanitized service exports/access. Any FAIL is a release blocker until the owner authorizes a separate remediation task.

### Deliverable

Write the report to `docs/reports/preproduction/2026-10-20/05_COOLIFY_RUNTIME_PRIVILEGE_AUDIT.md` on a dedicated audit branch. Include the evidence-to-claim matrix, service/role separation matrix, all PASS/FAIL/NOT VERIFIED cases, risks, and exact follow-up task prompts. Do not change application code or infrastructure in this task.
