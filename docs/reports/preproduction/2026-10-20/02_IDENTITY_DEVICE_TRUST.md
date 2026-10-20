# Prompt 02 — Identity, Membership, Authentication & Device Enrollment

**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Repository:** https://github.com/berkah-pos/Berkahtigaputeri  
**Inspected revision:** main / 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Report branch:** audit/preproduction-identity-device-trust-2026-10-20  
**Scope owner:** Identity and Device Trust  
**Overall status:** **BLOCKED — the required identity/device trust chain is not implemented on the inspected main revision.**  
**Change boundary:** This commit adds only this assigned audit report. No application code, schema, migration, dependency, workflow, secret, infrastructure, hosted resource, or live data was changed. No Supabase project was accessed.

## 1. Executive result

The target architecture requires the server to validate the caller, active tenant membership, and enrolled device before allowing tenant-scoped operations. The inspected revision does not yet contain that Laravel Central API trust chain.

The backend has useful scaffolding: a central User model, Sanctum API guard configuration, a personal-access-token table, central tenant and device registry tables, and a minimal health route. Those pieces are **not** an implemented authentication, membership, or enrollment service. The only versioned API route found is the public platform-health endpoint. No Laravel HTTP controller or middleware implementation exists in the tracked app/Http tree on this revision.

Meanwhile, the Flutter app still initializes Supabase when build-time Supabase values are present and uses Supabase Auth for cloud login. This is incompatible with the latest owner decision prohibiting all Supabase product use, including read-only project access. There is no verified replacement login/session API in Laravel, so simply removing the Flutter Supabase path would also leave cloud authentication unavailable.

**Release implication:** identity and device authorization are a P0 release blocker. Do not claim SaaS authentication, tenant-membership authorization, device enrollment/revocation, or safe cloud session restoration until the acceptance tests in this report execute successfully against a reviewed Laravel/PostgreSQL 17 candidate.

## 2. Authority, scope, and evidence semantics

The repository’s current authority says:

- The 2026-10-17 owner ADR selects KVM2/Coolify, PHP 8.4, Laravel 13, Sanctum, private PostgreSQL 17, one central DB plus a separate DB and restricted runtime role per tenant, and prohibits all Supabase product use. See [the current owner ADR](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md).
- [DOC_00 canonical configuration decision](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) requires GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE and says tenant, device, and service authorization must be derived/verified server-side. This audit does not change the resolver or configuration merge rules.
- [DOC_14 tenant architecture](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) requires active membership, a registered active device, tenant-context reset, and no reliance on caller-supplied IDs.
- [The master roadmap](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_00_MASTER_ROADMAP.md) places authentication, admin, and Central API in Phase 4. Selecting architecture is not proof that those components exist.

Evidence labels:
- **SOURCE-VERIFIED:** read directly from the named tracked file at the inspected SHA.
- **CI-OBSERVED:** observed check/run metadata for the exact SHA; this does not mean the relevant application tests ran.
- **NOT RUN / NOT VERIFIED:** no execution evidence was available for the behavior described.
- **INFERRED / PROPOSED:** an engineering risk scenario or acceptance contract that still requires executable proof.

## 3. Actual node and connection trace

### 3.1 Current Flutter cloud path — source-verified but prohibited by the selected architecture

    pos-app/lib/main.dart
      ├─ opens local SQLite and SharedPreferences
      ├─ reads SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY build defines
      └─ when both are present:
           Supabase.initialize(...)
                ↓
           LoginScreen
                ↓ signInWithPassword(email, password)
           Supabase Auth session persisted/restored by SDK
                ↓ currentSession != null
           HomeScreen receives ConfigService
                ↓ reads tenant_id/device_id from AppIdentityStore
           ConfigService.getEffectiveConfig(tenantId, deviceId, service)
                ↓
           Supabase RPC get_effective_config

Evidence:
- [main.dart lines 9–44 and 160–179](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/main.dart#L9-L44) selects and initializes the Supabase client from compile-time variables. [Lines 160–179](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/main.dart#L160-L179) sends a restored currentSession directly to the cloud HomeScreen.
- [login_screen.dart lines 47–73](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/auth/login_screen.dart#L47-L73) calls Supabase signInWithPassword.
- [app_identity_store.dart lines 4–26](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/config/app_identity_store.dart#L4-L26) stores tenant/device identifiers in SharedPreferences; these values are client state, not credentials.
- [home_screen.dart lines 521–540](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/home/home_screen.dart#L521-L540) reads those values and supplies them to configuration retrieval.
- [config_service.dart lines 59–99](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/config/config_service.dart#L59-L99) uses the Supabase client and sends p_tenant, p_device, and p_service to the legacy RPC.

The UI text acknowledges that login alone does not prove membership/device enrollment. That is useful explanatory text, but it is not an implementation of server-side authorization. This report does not call the RPC or connect to Supabase.

### 3.2 Current Laravel API path — incomplete

    HTTP request
       ↓
    routes/api.php
       └─ GET /api/v1/platform-health only
            ↓
          JSON health response

    No tracked app/Http controller or auth middleware implementation
    was found on this revision for mobile login, tokens, memberships,
    device enrollment/revocation, or identity-to-tenant propagation.

Evidence:
- [routes/api.php lines 1–12](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php#L1-L12) contains only the platform-health route.
- [routes/web.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/web.php) contains a root status response; no mobile authentication contract was found there.
- The tracked tree on the inspected SHA has no app/Http source path. The only central Eloquent model found under app/Models/Central/ is User.php.
- [config/auth.php lines 5–20](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/auth.php#L5-L20) configures a Sanctum API guard and an Eloquent User provider. Configuration does not create login, token-issue, token-revoke, membership, or device-enrollment endpoints.

### 3.3 Existing central identity/device storage — schema is present, behavior is not

The initial central migration defines:

- **tenants** with an ID, JSON data, and template_id; no dedicated tenant lifecycle/status column is defined in this initial migration. [Migration lines 13–19](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/central/2026_10_17_000001_create_central_platform_tables.php#L13-L19).
- **users** with unique email, password, nullable tenant_id, is_super_admin, and is_active. There is no separate tenant_memberships table in the tracked migration tree. [Migration lines 26–39](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/central/2026_10_17_000001_create_central_platform_tables.php#L26-L39).
- **personal_access_tokens** with token hash, abilities, optional expires_at, and usage timestamps. [Migration lines 41–46](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/central/2026_10_17_000001_create_central_platform_tables.php#L41-L46).
- **device_registry** with globally primary-keyed device_id, tenant_id, nullable owner_user_id, free-form status defaulting to pending, nullable registered_at, and timestamps. [Migration lines 105–114](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/central/2026_10_17_000001_create_central_platform_tables.php#L105-L114).

[User.php lines 14–36](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/app/Models/Central/User.php#L14-L36) sets the central connection and exposes tenant_id, is_super_admin, and is_active. Its canAccessPanel() check protects Filament panel access using is_active && is_super_admin; that check does not implement mobile API authentication or tenant membership.

No TenantMembership/DeviceRegistry model, identity service, enrollment controller, revocation endpoint, or membership authorization policy was found in the tracked source tree at this SHA. This is a source inventory conclusion, not a database runtime inspection.

## 4. Findings (severity-ordered)

### IDT-001 — P0 Critical: Mobile cloud authentication is still bound to the prohibited Supabase product

**Confidence:** High  
**Affected node/edge:** Flutter bootstrap → authentication provider → cloud session → cloud configuration.  
**Evidence:** main.dart lines 9–44; login_screen.dart lines 47–73; config_service.dart lines 59–99. The current owner ADR explicitly prohibits Supabase use and requires the authenticated Laravel Central API.

**Failure scenario:** A configured build uses the legacy Supabase auth/config path. Removing the SDK without a tested Laravel replacement makes the current cloud login path unavailable. Keeping the path is not compliant with the accepted platform decision.

**Business/security impact:** Cloud identity has no compliant target provider on this revision; the product cannot be certified for SaaS login, tenant membership, device authorization, or Laravel API access. No claim is made that a production compromise occurred.

**Required acceptance:**
1. Flutter cloud authentication is backed only by the reviewed Laravel Central API contract; no Supabase initialization, Auth, RPC, URL, build define, credential, service dependency, or fallback remains active.
2. Integration tests prove valid credentials create the intended server session/token, invalid credentials fail generically, and no request is sent to a Supabase host.
3. Dart analysis, Flutter tests, and Android build execute against the exact candidate SHA.
4. Local-only mode remains explicitly local and cannot be mistaken for an authenticated SaaS session.

**Owner hand-off:** Prompt 03 owns the API request/response and error contract. Prompt 06 owns Flutter runtime replacement and cold-start/navigation wiring. Identity implementation must align with those contracts; this audit makes no implementation changes.

### IDT-002 — P0 Critical: No Laravel mobile authentication/session endpoints are implemented

**Confidence:** High  
**Affected node/edge:** Flutter → Laravel Central API → authenticated principal.  
**Evidence:** routes/api.php has only the health route (lines 5–11); the tracked tree lacks app/Http; config/auth.php configures the Sanctum guard but no route/controller/token issuer was found. tests/Feature/PlatformSmokeTest.php contains only framework/health/root-status smoke tests (lines 9–29).

**Failure scenario:** A mobile client attempting to authenticate against the accepted central server has no implemented endpoint that validates credentials and returns a server-verifiable principal. There is no route-based path to revoke the issued credential or obtain the current principal for subsequent requests.

**Business/security impact:** The mobile app cannot rely on Laravel for session establishment or protected endpoint identity. Sanctum package/configuration presence is not proof of implemented authentication.

**Required acceptance:**
- Add a reviewed, versioned auth contract before implementation: login, current-principal/session validation, logout/revocation, and any refresh/renewal behavior needed by the selected token model.
- Unauthenticated requests to every protected endpoint return 401; valid requests bind to the authenticating server-side user, not caller-supplied identity fields.
- Invalid credentials, inactive user, malformed input, rate limits, expired credentials, and revoked credentials are tested without account enumeration.
- Feature tests run against disposable PostgreSQL 17 and the exact candidate SHA. Health endpoints may stay public, but must not be treated as authenticated proof.

**Owner hand-off:** Prompt 03 defines the API surface and status/error contract. The implementation owner should then implement the approved Laravel authentication controller/middleware and feature tests. Prompt 02 does not add routes or application code.

### IDT-003 — P0 Critical: Authoritative user-to-tenant membership is not represented or enforced

**Confidence:** High for missing implementation; medium-high for release impact because no protected Laravel tenant API currently exists.  
**Affected node/edge:** Authenticated user → active tenant membership → server-derived tenant context.  
**Evidence:** The initial migration defines nullable users.tenant_id but no tenant_memberships table; the tracked app/Models/Central/ contains only User.php; no membership model/policy/service/API route was found. User is_active is checked by canAccessPanel() for Filament access only, not by any existing mobile API because no such API exists.

**Failure scenario:** The intended system must decide which tenant(s) an authenticated user may enter and whether each membership is active. A nullable scalar tenant_id cannot express a separately revocable membership relationship or membership state. If a future handler simply trusts that field or accepts body/header tenant_id, a forged tenant selector could be mistaken for authorization. This exploit has **not** been executed; it is a hostile case the missing acceptance suite must prove denied.

**Business/security impact:** No source-verified mapping currently connects an authenticated user to an active tenant membership. This prevents certification that user A cannot switch tenant context by modifying request data or local preferences.

**Required acceptance:**
1. Define and review the authoritative membership schema/contract: user, tenant, status, role/permissions where applicable, timestamps/audit behavior, and policy for multiple memberships.
2. Resolve membership from authenticated identity on the server for every protected request. Client tenant_id, route slug, Host, X-Forwarded-Host, or SharedPreferences data are selectors at most, never authorization.
3. Test a user with no membership, inactive membership, disabled user, nonexistent/suspended tenant, supported multi-membership cases, and user A changing every tenant selector to tenant B.
4. Verify each denial is fail-closed and emits an appropriate audit event without leaking whether a foreign tenant exists.

**Owner hand-off:** Prompt 04 owns schema/model integrity; Prompt 03 owns route policies and request semantics; identity implementation must wire the authoritative membership check. Prompt 05 separately owns PostgreSQL database grants and A/B database isolation.

### IDT-004 — P0 Critical: Device registry storage exists without enrollment/ownership/revocation trust path

**Confidence:** High  
**Affected node/edge:** Authenticated user + active membership → registered active device → authorized request tenant.  
**Evidence:** device_registry exists in the initial central migration, but app/Models/Central/ contains only User.php, routes/api.php contains only health, and no enrollment/revocation handler or test was found. The table permits nullable owner_user_id, has a default pending status, and has no source-verified lifecycle transition logic.

**Failure scenario:** A valid account attempts to use a device ID registered to another user/tenant, a pending device, a revoked/lost device, or a replaced device. On this revision there is no source-verified API to enroll or revoke a device or consistently check user-device-tenant binding before data access.

**Business/security impact:** A client-provided device ID cannot serve as device proof. Device loss, reassignment, duplication, and cross-tenant spoofing have no implemented, testable server-side lifecycle.

**Required acceptance:**
- Enrollment requires an authenticated eligible user and server-defined proof/challenge or approved admin workflow; it records tenant ownership, user ownership, lifecycle status, registration time, and audit actor.
- Device IDs are globally unique or uniqueness is deliberately scoped and enforced. Re-enrollment cannot silently transfer an existing device to a different tenant/user.
- Pending, disabled, revoked, unknown, or wrong-owner devices are denied on every protected route even if the user token remains valid.
- Revocation takes effect on the next request and on queued/background work; replacement and lost-device flows are tested.
- Negative tests cover unauthenticated enrollment, enrollment by a non-member, another user's device ID, modified tenant ID, duplicate/replay attempts, pending status, revoked status, and tenant-context reset.

**Owner hand-off:** Prompt 03 defines device endpoint contracts; Prompt 04 reviews central schema constraints; identity/device implementation builds the lifecycle service and tests. Prompt 05 owns database-level cross-tenant grant proof, not enrollment UX.

### IDT-005 — P1 High: Token expiry, revocation, disabled-account enforcement, and recovery lifecycle are not proven

**Confidence:** High that lifecycle is unimplemented/unverified on this SHA.  
**Affected node/edge:** Credential issuance → authenticated requests → logout/revocation/account recovery.  
**Evidence:** config/sanctum.php sets global expiration to null (lines 7–13); personal_access_tokens.expires_at is nullable; no Laravel token-issuance/revocation code or route was found. config/auth.php points password reset to password_reset_tokens, but no migration creating that table exists in the tracked migration tree. email_verified_at is stored, but no mobile route/middleware enforcing verification was found. The current User panel check is not a substitute for API account-state enforcement.

**Failure scenario:** Once token issuance is implemented, a token minted without explicit per-token expiration could remain valid indefinitely under the current default. If user/device disablement, password reset, or logout does not invalidate existing credentials and every protected request does not check current status, previously issued credentials may remain accepted. This is a conditional risk; no current Laravel mobile token is known to be issued, and no exploit was executed.

**Business/security impact:** Lost-device response, stolen-token containment, user deactivation, password recovery, verification, and logout semantics cannot be certified. The product has no reliable test evidence that stale credentials stop working promptly.

**Required acceptance:**
1. Document token type, storage, ability/scope, expiry, renewal/rotation and revocation semantics. Configure bounded lifetime or explicit per-token expiries; do not rely on a nullable default.
2. Test access with fresh, expired, revoked, malformed, and wrong-ability tokens. Verify deleting/revoking a token makes the next request fail.
3. Disable a user and revoke a device while a token is already valid; the next protected request must fail closed.
4. Define password reset and email-verification policy. Add persistence/routes only through a reviewed implementation change; test reset-token single use, expiry, rate limits and token/session invalidation as required by the approved policy.
5. Test logout while online, offline/network-failure handling, app restart after logout, token-storage cleanup, and server-side revocation. Do not infer behavior from the existence of a logout button or SDK method.

**Owner hand-off:** Prompt 03 owns the contract/error responses; identity implementation owns token lifecycle and account-state checks; Prompt 06 owns secure client token storage, logout UI, and session restoration tests. No token/config changes were made in this audit.

### IDT-006 — P1 High: Cached effective configuration can survive an identity/authorization change

**Confidence:** High that fallback flow exists; medium for exploitability because the legacy provider is prohibited and no runtime test was executed.  
**Affected node/edge:** Authenticated session → tenant/device tuple → configuration cache fallback.  
**Evidence:** config_service.dart lines 70–99 requires only that some Supabase session exists, then calls the RPC with client-supplied tenant/device/service values. A broad catch falls back to a cached result keyed only by tenant ID, device ID and service (cache-key builder at lines 135–142); the cache key does not include authenticated principal or membership version. The client-stored tuple is held in AppIdentityStore.

**Failure scenario:** If an authorization-denied response, revoked device, or account/membership change causes the RPC to fail while the client still has a session and a cached value for the same tuple, the broad error handler may return that cached configuration. Whether this state is reachable in a real install is **NOT VERIFIED**. The legacy path must not remain in the target system regardless.

**Business/security impact:** Cache fallback can blur transient network outage and server authorization denial. It can also make account switching or device revocation depend on local state rather than a fresh authorization decision.

**Required acceptance:**
- Move remote requests to the authenticated Laravel API; distinguish transport/offline failures from 401/403/404 and revoked/inactive identity errors.
- Only use previously server-issued configuration for the exact authorized tenant/device/service context, and define how identity, membership, and device revocation affect cache eligibility. An authorization denial must never be translated into success solely because a cached value exists.
- Test account A logout followed by account B login, changed tenant/device selectors, inactive/revoked device, revoked membership, server 401/403, timeout/offline, same-tuple cache collision, POS-vs-Akuntansi service separation, and logout cache cleanup.
- Repeat the tests on the exact candidate SHA; local preference/cache behavior alone does not prove server authorization.

**Owner hand-off:** Prompt 01 owns effective-config caching/resolution semantics; Prompt 06 owns Flutter integration and session/cache lifecycle. This finding is recorded because it crosses the identity-to-configuration edge; this audit does not edit the config service or resolver.

## 5. Trust-boundary / connection matrix

| Producer → consumer | Required contract / trust boundary | Current source state | Evidence status |
|---|---|---|---|
| Flutter → authentication provider | Laravel Central API only; password/token validated server-side, no Supabase fallback | Current login uses Supabase Auth; Laravel login API missing | **SOURCE-VERIFIED gap / P0** |
| Token/session → authenticated principal | Token tied to central User; explicit expiry/revocation; disabled user fails closed | Sanctum guard/model/token table configured; no mobile token lifecycle implementation | **Partial scaffold; NOT VERIFIED** |
| Principal → active tenant membership | Server resolves active membership/role; client tenant selector is not proof | Nullable users.tenant_id; no membership table/model/policy found | **MISSING / P0** |
| Principal + membership → device ownership | Active enrollment binds device to both tenant and user | device_registry table only; no model/service/endpoint/test found | **MISSING / P0** |
| Authenticated request → tenant context/domain service | Context derived from verified identity/membership/device, then passed to authorized service/database selection | No protected mobile route/controller/auth middleware path found | **MISSING / NOT VERIFIED** |
| Logout/revocation → subsequent requests | Server-side revoke plus client cleanup; revoked credentials rejected promptly | Existing path uses Supabase SDK; no Laravel lifecycle endpoint; failure/relaunch behavior untested | **NOT VERIFIED** |
| Identity/membership change → local cache eligibility | No cache result bypasses fresh 401/403 or wrong-owner decision | Legacy broad catch returns cache after errors for same tuple | **SOURCE-VERIFIED risk / runtime NOT TESTED** |
| Background work → tenant context | Server-derived context is propagated and cleared after each job | No identity propagation/job integration found in this scope | **MISSING / NOT VERIFIED** |

## 6. Hostile identity cases and required expected outcomes

These are acceptance tests required for implementation, not tests executed in this audit.

| Case | Attack/input | Expected result |
|---|---|---|
| Missing credentials | No token/cookie on protected endpoint | 401; no tenant data or protected metadata |
| Invalid login | Unknown email or wrong password | Generic failure with rate limits; no user enumeration |
| Disabled account | Valid token for user whose central is_active changes to false | Denied on next protected request; credential revoked or rendered unusable per approved contract |
| No membership | Active user submits tenant ID for a tenant with no active membership | 403/404 without leaking foreign-tenant existence |
| Inactive membership | Existing membership is suspended/revoked | Denied despite old token and unchanged preferences |
| Tenant selector spoof | User A changes body, path, header, Host, or X-Forwarded-Host to tenant B | Authorization derived independently; request denied unless a separately verified active membership permits it |
| Device spoof | User A submits device ID owned by user/tenant B | Denied; no configuration/data/entitlement side effect |
| Pending device | Device row exists with status=pending | Denied until explicit, audited activation |
| Revoked/lost device | Valid user token but device is revoked | Denied on next protected request; queues and caches cannot restore access |
| Device reassignment | Duplicate/replayed enrollment tries to move a device | Rejected or governed by an explicit audited replacement protocol; never silently transferred |
| Expired/revoked token | Old token is reused | 401 after expiry/revocation; no stale session restoration |
| Logout failure/restart | App logs out during network failure, then restarts | Local cloud UI/credentials clear safely; server revocation reconciles and stale credentials do not regain access |
| Account switch/cache | Account B signs in with cache created by account A for the same tuple | Authorization denial never falls back to A's cached configuration |
| Tenant-context contamination | Job/request for tenant A is followed by tenant B in same long-lived worker | B is evaluated only under B's verified context; no connection/cache/actor state leaks from A |

## 7. Test and CI evidence on the inspected SHA

### SOURCE-VERIFIED test coverage

- tests/Feature/PlatformSmokeTest.php contains framework health, API health, and root status assertions only. It does not test login, Sanctum tokens, membership, enrollment, revocation, account recovery, or tenant spoofing.
- pos-app/test/auth/login_screen_test.dart has two widget tests verifying form/local-only UI labels. The tests instantiate a test Supabase client; they do not exercise a real authenticated Laravel API, membership resolution, token lifecycle, or device enrollment.
- A tracked-tree inventory shows no Laravel authentication feature-test file or device-enrollment test on this revision.

### CI-OBSERVED

The inspected commit is 371b7fdf0bf672b37ceb1023e647f114221bf797. GitHub returned two completed successful check runs named **Dependabot** for the SHA ([run 39186055413](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39186055413) and [run 39184121515](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39184121515)). The commit combined-status endpoint returned no status entries. These Dependabot checks are **not** evidence that Laravel authentication tests, Flutter analysis/tests, Android builds, or device/tenant security tests ran successfully on this SHA.

### NOT RUN / NOT VERIFIED

- No PHPUnit/Laravel feature test was run by this audit.
- No Flutter test/analyzer/build was run by this audit.
- No actual token/session, disabled-user, membership, enrollment, revocation, hostile-host, or cross-tenant request was executed.
- No PostgreSQL database or production/staging service was queried.
- No Supabase project or product was accessed.
- No staging or production behavior is claimed.

This audit was performed through read-only source/metadata inspection. The report-only path docs/reports/preproduction/2026-10-20/02_IDENTITY_DEVICE_TRUST.md does not match the inspected workflow path filters, so it is not expected to dispatch the known legacy workbook-sync workflow. That conclusion comes from source path inspection, not from claiming an application CI run passed.

## 8. Overall decision and unresolved boundaries

**Status: BLOCKED / NOT VERIFIED for Prompt 02 acceptance.**

The accepted trust chain is absent on the inspected revision. The high-priority gaps are: prohibited Supabase login path, missing Laravel auth endpoints, no authoritative active-membership relationship, no device lifecycle implementation, and unproven token/account-recovery behavior. The configuration cache fallback is a separate high-priority identity-boundary concern and must be tested/fixed by its owning specialists.

No exploit was executed. Findings describe source-confirmed gaps and conditional failure scenarios only. No production compromise, unauthorized live access, or customer-data exposure is alleged.

### Ownership boundaries preserved

- **Prompt 02:** identity/session/membership/device trust chain and authenticated identity propagation.
- **Prompt 03:** API routes, DTOs, response/error semantics, and protected-route matrix.
- **Prompt 04:** central schema/model constraints and relationship integrity.
- **Prompt 05:** PostgreSQL provisioning roles/grants and real cross-tenant database isolation.
- **Prompt 06:** Flutter startup/login/logout/local-only wiring, session restoration, secure token/cache handling, and replacement of the legacy provider.
- **Prompt 01:** effective configuration and cache/resolver semantics.
- **Subscription specialist:** subscription lifecycle and entitlements; this report does not infer or implement subscription rules.

### Exactly one next action

**Prompt 03 owner:** define and review the Laravel Central API contract for login/current-principal/logout-revocation plus device enrollment/revocation and membership-denial semantics. Acceptance is a written contract identifying server-derived user, active membership, and active-device requirements and specifying the request/response/error cases needed for Prompt 02 implementation. Do not use Supabase as a temporary fallback.
