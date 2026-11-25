# Google Drive integration

## Design
Use Google Drive API v3 appDataFolder and only https://www.googleapis.com/auth/drive.appdata. Do not browse or modify normal Drive files. macOS and iOS OAuth clients must belong to the same Google Cloud project for shared application data. Bind the account using Drive about.user.permissionId and a stable explicit project namespace. One active provider per library; do not silently replace an existing iCloud binding. Provider migration requires a separate, explicit history-preserving design.

Each immutable SyncRevision is JSON stored as an application-private file with logical UUID in its name and SHA-256 app property. The adapter pages all matching metadata, checks complete listing, validates size/hash/graph, accepts identical logical duplicates only, and never updates/deletes a remote revision. Uploads are parent-first and allocate a Drive file ID before multipart create. A 409 can be reconciled by that ID and readback. A durable pending create-ID ledger and persistent remote checkpoint/changes cursor are follow-up work; a crash or eventual-consistency race can produce identical duplicate files, not overwrite revisions. Initial adapter performs full reads, not incremental Drive reads. Size/record caps follow existing review limits; resumable large uploads are follow-up.

## Google Cloud configuration required
1. Create/select the ioant-Clip project in https://console.cloud.google.com/ and enable Google Drive API.
2. Configure Google Auth Platform branding, audience and test users, request the appdata scope.
3. Create Desktop app OAuth client for macOS; use system browser, loopback 127.0.0.1, PKCE S256, random state, token refresh stored in Keychain. No server required. For iOS, create a separate iOS OAuth client for com.ioant.clip.ios in the same project and use supported Google Sign-In flow, not desktop loopback.
4. Do not put downloaded OAuth credentials or tokens in source control. Testing-mode refresh tokens may expire; handle reauthorization.
5. Actual OAuth callback, session/Keychain integration, provider selection and real account test remain pending. No user data is sent by this first stage.

References:
https://developers.google.com/workspace/drive/api/guides/appdata
https://developers.google.com/workspace/drive/api/guides/manage-uploads
https://developers.google.com/identity/protocols/oauth2/native-app
https://developers.google.com/identity/sign-in/ios/start-integrating
