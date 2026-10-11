# Google Play release checklist — Berkah POS

**Application:** Berkah POS  
**Publisher/legal name:** PT Berkah Tiga Puteri  
**Package / application ID:** `id.co.berkahtigaputeri.berkahpos`  
**Release status:** **NOT READY TO SUBMIT** until every blocker below is evidenced as complete.

This checklist distinguishes repository configuration from steps that only the organization can complete in Play Console or on company-operated services. Source code cannot certify a company, verify its legal identity, publish a live privacy policy, or guarantee review approval.

## 1. Repository checks

- [x] Android namespace and application ID use `id.co.berkahtigaputeri.berkahpos`.
- [x] Default target API is 36, the current target required for new apps and updates submitted from 31 August 2026.
- [x] Android cleartext traffic is disabled; backup is disabled.
- [x] Manifest currently declares Internet and network-state permissions only.
- [x] Local inventory/sales database and checkout smoke-level formatter test are present.
- [x] Gradle wrapper scripts and JAR are checked in.
- [x] A single purpose-specific Android CI workflow exists at `.github/workflows/berkah-pos-android-ci.yml` with path filters scoped to the standalone Flutter app.
- [ ] The new CI run must finish successfully; queued, pending, cancelled or artifact-free historical runs do not count as passing results.
- [ ] CI run must finish successfully. A queued run is not a passing result.
- [ ] Add/retain tests for product create/edit/delete, checkout stock invariants, duplicate product names, and persistence after app restart.
- [ ] Device acceptance test on the supported Android range, including a small-screen physical device, offline behavior, app restart, and update-over-existing-install.
- [ ] Test app startup and all primary flows with a clean install and upgrade install.

## 2. Organization account and developer verification — Play Console owner action

- [ ] Select an **Organization** developer account (not Personal) for the commercial publisher.
- [ ] Have the organization's D-U-N-S number ready and confirm that the legal name/address match the linked Google Payments profile and Dun & Bradstreet record.
- [ ] Complete the organization and authorized-representative identity checks using the documents requested by Google.
- [ ] Verify the organization's website, contact email, and phone; verify the developer email and developer phone shown on Google Play.
- [ ] Complete any Android developer verification and package-name registration tasks displayed in Play Console for distribution in Indonesia.
- [ ] Do not substitute a personal identity, unrelated D-U-N-S record, or domain not controlled by the organization.

Official references:
- Organization vs personal account: https://support.google.com/googleplay/android-developer/answer/13634885
- Information required for organization accounts: https://support.google.com/googleplay/android-developer/answer/13628312
- Developer identity verification: https://support.google.com/googleplay/android-developer/answer/10841920
- Developer verification and Indonesia rollout: https://support.google.com/googleplay/android-developer/answer/16471116

## 3. Privacy, data safety, and deletion — release blockers

- [ ] Publish a complete privacy policy as an active, publicly accessible HTTPS web page (not a PDF), accessible without login, regional restriction, or edit access.
- [ ] The policy must name PT Berkah Tiga Puteri and provide a working privacy contact, the actual data collected, recipients/processors, purpose, security controls, retention period, and deletion procedure.
- [ ] Confirm the live URL in the app and Play Console matches the company-controlled policy page.
- [ ] Verify the in-app **Hapus akun** link opens a live account/deletion request flow. If this app or its backend allows account creation, provide both the in-app deletion path and an external web resource to request account and associated-data deletion.
- [ ] Make deletion operational: define what happens to the email/entitlement record on the server and local POS records on the device; do not just suspend or lock an account.
- [ ] Complete the Data safety form based on the actual client **and backend/SDK** behavior. At minimum, review the email transmitted in the subscription-status request. Do not declare “no data collected” simply because transaction rows remain on-device.
- [ ] Confirm with the backend operator whether query-string email values are logged, retained, shared with processors, or used for analytics. If so, reflect the real handling in the policy/Data safety form.
- [ ] Verify all third-party SDKs and the final merged manifest, not just this source manifest.
- [ ] Re-test the privacy and deletion links from inside the released app.

Current code constants for review:
- Privacy: `https://berkahtigaputeri.co.id/privacy`
- Account deletion: `https://berkahtigaputeri.co.id/delete-account`
- Access-status endpoint: `https://api.berkahtigaputeri.co.id/check-status`

These URLs were not independently verified as live during this work. Treat them as **unverified** until an unauthenticated browser and actual device can open them and the company confirms ownership/content. Do not state that deletion is operational until the backend path has been exercised end to end.

Official references:
- Privacy policy requirements: https://support.google.com/googleplay/android-developer/answer/17517561
- Account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Review login/access instructions: https://support.google.com/googleplay/android-developer/answer/15748846

## 4. Entitlement, login and review access

- [ ] Replace/confirm the subscription-status endpoint with an organization-controlled production service, HTTPS certificate and documented response schema.
- [ ] Verify server-side entitlement enforcement; a client-side local trial is not secure authorization because app data can be reset or modified.
- [ ] Test expired, suspended, active, network timeout, malformed response, wrong email, and server-unavailable cases.
- [ ] Provide the Play reviewer a reusable review account and all instructions needed to reach every feature that requires access. Ensure credentials remain valid, accessible from the reviewer's location, and do not require a one-time code that the reviewer cannot obtain.
- [ ] If access requires subscription/payment, give Google clear review instructions and a functioning reviewer entitlement or demo path that does not require a real purchase.
- [ ] Confirm that the app is not blocked by trial expiry, device registration, geo checks, or a backend outage during review.

The current local trial is a fallback/demo behavior, not proof of production-grade access control.

## 5. Signing, versioning, and Android artifact

- [ ] Configure the organization's release/upload key outside Git, enable Play App Signing, and verify recovery/ownership procedures for the upload key.
- [ ] Build a signed release AAB from the exact commit selected for production. Do not use the unsigned CI artifact.
- [ ] Increment `versionCode` on every upload. Current source is `1` and `versionName=1.0.0`.
- [ ] Check the final merged manifest, application ID, target API, permissions, native libraries, SDK declarations and AAB output.
- [ ] Store the AAB checksum and source commit SHA in the release record.
- [ ] Confirm Android API 36 compatibility and run Play Console pre-launch report; address crashes, ANRs, accessibility/usability problems and policy warnings before production.

Target API policy: https://support.google.com/googleplay/android-developer/answer/11926878

## 6. Play Console declarations and store listing

- [ ] App title, short/full description, icon, screenshots and feature graphic accurately represent real functionality.
- [ ] Set the right category, contact email, website and privacy policy.
- [ ] Complete app access instructions, ads declaration, target-audience/content rating, data safety, and any financial-features / permissions declarations that actually apply.
- [ ] Ensure screenshots and listing text do not promise cloud sync, accounting/tax automation, integrations, encryption, deletion, or features that are not implemented and tested.
- [ ] Test store listing and app name/package are consistent with PT Berkah Tiga Puteri.
- [ ] Review policy status in Play Console; fix every warning before rollout.
- [ ] Complete internal testing/pre-launch reports; start with a controlled rollout and monitor crashes and policy messages.

## 7. Production go/no-go

Release is **NO-GO** if any of these remain unresolved: organization verification, package registration if requested, non-working privacy/deletion URLs, unknown backend data handling, untested reviewer login, unsigned artifact, failed CI, or an untested signed bundle.
