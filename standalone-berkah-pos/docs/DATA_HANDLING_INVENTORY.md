# Berkah POS — data handling inventory

This inventory reflects the current Flutter client source only. It is not a substitute for inspecting the production backend, merged Android manifest, dependency SDKs, server logs, and Play Console Data safety form.

| Data / event | Current behavior found in source | Storage / recipient | Release declaration task |
|---|---|---|---|
| Email address | User enters an email at login; it is normalized and sent as an HTTPS query parameter to the access-status endpoint | Sent off-device to the configured company API; also used in a SharedPreferences key for local trial start date | Declare/describe the actual email processing. Ask backend operator about access logs, retention, sharing, and processors. Avoid email in query strings where possible because URL logs can capture it. |
| Local trial start timestamp | Stored under an email-derived preference key | Local SharedPreferences | Document local persistence and behavior when app data is cleared/uninstalled. |
| Product name, price, inventory count | Create/edit/delete in the app | Local SQLite database `berkah_pos.db` | Current client does not sync these rows in source inspected; confirm no SDK/back-end collection. |
| Sales header and line items | Saved transaction totals, timestamps, product snapshots, quantity, unit price and subtotal | Local SQLite database | Treat as business/transaction data. Confirm whether the business considers these data sensitive and how backup/export/deletion works. |
| Device/network metadata | The client makes a network request to the status API and declares Internet/network-state permissions | API/network infrastructure may see IP address, request metadata and server logs depending on hosting | Ask backend/hosting operators and inspect their logs/retention and SDKs before answering Data safety. |
| Payment credentials | No card/wallet payment-entry flow was found in the current client source | Not present in this app source reviewed | Re-check full project/backend and Play declarations if payment functionality is added. |

## Security / retention observations

- Android manifest disables cleartext traffic and app backup. The network URL is HTTPS in the current source.
- The local SQLite database currently has no in-app “delete all local business data” action; uninstallation or clearing app storage is not equivalent to deleting any server-side account record.
- The settings screen has a web link for privacy and account deletion, but URL liveness and end-to-end deletion behavior were not verified. Do not describe these flows as operational until tested.
- The login screen is email-based access-status checking, not a complete account creation or credential authentication flow by itself. Confirm exactly what the remote service does with the email before deciding whether the app enables account creation and what deletion controls apply.
- The local trial is enforced in client preferences and is not tamper-resistant. It must not be represented as secure subscription enforcement.

## Evidence required before Play submission

1. A live privacy policy matching the actual client, API and third-party SDK behavior.
2. Backend owner's written answers on whether emails are logged/retained/shared, data retention, deletion completion, and processor/vendor list.
3. Device screenshots or test results for successful deletion request and the response/confirmation path.
4. Export of the final merged manifest and SDK inventory.
5. Completed Data safety questionnaire reviewed against this evidence.
