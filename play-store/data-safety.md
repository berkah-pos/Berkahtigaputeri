# Google Play Data Safety — Berkah Tiga Puteri POS

**Status: DRAFT. Re-verify against the exact AAB, deployed Laravel API, permissions and SDK inventory before submitting a release.**

## Build scope

The Flutter app includes local-first product, inventory, checkout and report modules. Feature code existing in the repository does not prove every flow is reachable or that cloud synchronization is active. A release declaration must reflect the precise app build and deployed API reviewed at submission time.

## Data processed

Depending on the activated build/runtime, the app may process:
- account identifier and authentication token needed to sign in;
- tenant and device identifiers for server-side authorization;
- effective configuration and service availability;
- product, stock, sale, sale-item and accounting data created by a tenant;
- durable outbox and synchronization status when a cloud sync endpoint is implemented and activated;
- app/device diagnostics needed to troubleshoot service availability.

Local POS transactions are stored in the device's SQLite database. Cloud transmission must occur only through the authenticated Laravel Central API and the server-authorized tenant context. Repository source alone does not establish that cloud sales sync is live.

## Backend and access controls

The target backend is Laravel Central API, Laravel Auth/Sanctum and MariaDB with a separate database per tenant. The mobile app must not contain database passwords, the Laravel application key, Redis secrets, payment secrets or privileged backend credentials. A client-supplied tenant/device ID is not authorization.

Transport must use HTTPS/TLS for remote data. Tenant boundaries, token revocation, server authorization and tenant A/B isolation must be verified on the deployed service before production claims are made.

## Sharing / sale

The project policy is not to sell user/business data or share it for third-party advertising. Any service provider processing needed to operate the platform must be described accurately in the final release disclosures and contractual privacy policy.

## Release gate

Before Play Console submission, compare this draft with the signed AAB, Android permissions, actual SDK/dependency inventory, deployed API endpoints, current privacy URL, deletion/correction contact process, retention policy and real data flows. Update the declaration before releasing any build that changes transaction sync, billing, payment, analytics, crash reporting, ads or third-party SDKs.
