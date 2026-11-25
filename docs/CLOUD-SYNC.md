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
