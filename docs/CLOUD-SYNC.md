# Optional cloud synchronization

Status: journal integrated with local mutations and native capture inbox, atomic persistence in existing notes.json, conflict projection and explicit resolution UI, Cloud Sync settings show local-only status. No live provider connected and no user data uploaded. Legacy libraries are initialized locally; downgrading to builds that do not preserve the journal is unsupported.

## Provider selection

Default local-only. One active account/provider at a time. Switching provider requires an explicit merge/import review, never blindly copies an entire library or treats missing records as deletes. Keep local note data available offline. Bind sync state to provider + account + library namespace; no automatic cross-account upload.

- iCloud: CloudKit private database, shared explicit container for both bundle identifiers, CKAsset for large HTML/image payloads. Requires Apple Developer team, signing/provisioning with iCloud entitlement, actual container/schema, same Apple account on review devices. No production entitlement added to existing unsigned development build.
- Google Drive: Drive API v3 appDataFolder (drive.appdata scope), native OAuth on macOS/iOS with appropriate platform client IDs under the same Google Cloud project, native secure auth flow and Keychain token storage. No broad Drive permissions, embedded client secrets, or service account. Cross-platform account/appDataFolder interoperability must be validated with real credentials.

## Data and conflict safety

Do not synchronize notes.json directly. Immutable per-key revisions contain note payload or tag color and parents, and explicit deletion tombstones. Journal merge is atomic, idempotent and independent of clock order. Concurrent divergent edits/delete-versus-edit remain unresolved, retaining both versions until explicitly resolved. Large payload transport, chunking/checksums, per-provider incremental listing/pagination, retry and account handling remain to implement. Revision history grows until a safe retention/compaction policy is proven. This foundation intentionally does not alter existing note data.

## Next steps

1. Local integration implemented; validate migration, offline edits, deletion, capture and conflict resolution. Before provider activation, add account binding, transport/checksums and a history size policy.
2. CloudKit signed development integration, private record storage, test Mac/iPhone with same Apple ID.
3. Google OAuth/Drive adapter, real same-account cross-device validation.
4. Foreground sync on activation and changes, optional background refresh where allowed, manual sync button, status/errors and safe disconnect. Neither background timing nor instant synchronization is guaranteed.

## CloudKit transport prototype
The native adapter uses a private custom zone, immutable record names (revision UUID), CKAsset JSON payload and SHA-256 verification. It verifies the expected account/namespace before each exchange and upload, pages full queries, orders uploads parent-first and rejects nonidentical record collisions. The protocol is exercised against an in-memory provider. The adapter is **not instantiated in the review build**; no real CloudKit operation runs without signed container setup, persisted account binding, explicit consent and app-level coordinator. Configure NoteRevisionV1 schema/query indexes and test with an actual signed app before enabling. The current full-history design retains deleted content and can grow substantially; implement retention/storage policy and user-facing permanent deletion before release. No automatic migration of cloud identities or data. No live provider validation yet.

## Enrollment and transaction stage (R5)
Persist SyncEnrollment with notes.json. A first enrollment requires explicit consent to replace the pre-cloud revision history with a snapshot of current live clips/tag colors; this deliberately does not upload previously deleted content. Current clips remain unchanged, unresolved pre-cloud conflicts block enrollment. Pausing retains the binding and history; another account or provider cannot silently take over. No migration/forget action is exposed yet. SyncCycle uses a single main-actor library owner, validates a complete remote graph, reads the newest local snapshot after network awaits, persists merged data before upload, checks account/pause/cancellation, and bounds history transfer (review ceiling 4000 revisions, 128 MiB per revision, 256 MiB total). Limits block sync without removing data; not a permanent deletion/compaction implementation. CloudKit fetch also checks counts and byte sizes before decoding assets. No network calls or enrollment in the unsigned review build. Signed shared container, explicit consent UI, foreground scheduling, retry/status handling and actual CloudKit acceptance remain next. Before a general release implement retention/permanent deletion with safe multi-device semantics. The first baseline replacement must be plainly explained in the consent UI; do not call it silently.
