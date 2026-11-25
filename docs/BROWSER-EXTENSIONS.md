# Browser and share extensions

## Platform policy
- macOS: retain existing Chrome extension and key; add Safari Web Extension.
- iOS/iPadOS: Safari Web Extension for page/selection/answer capture; Chrome and other apps through Share Extension (only supplied text, URL, image or supported attachments; never promise DOM access).
- Extension settings list only applicable local capabilities. Distinguish bundled target, Safari system enablement, native host registration, last confirmed bridge communication and actual website authorization. No private Chrome profile scraping or automatic enablement.
- Safari macOS queries SFSafariExtensionManager.stateOfSafariExtension; iOS 26.2+ uses stateOfExtension; older iOS requires manual confirmation or a future shared receipt. Share sheet visibility isn't a global enabled flag. Chrome ping is diagnostic only, no page read, inbox write or app launch.
- Native share and Safari extensions use an App Group durable inbox, never modify notes.json directly. Main app imports using existing CaptureInbox and then existing consent-bound cloud sync. Keep review lanes isolated. No automatic clipboard/background browser collection.

## Registered Apple configuration (signed builds verified)
App Group group.com.ioant.clip; target identifiers com.ioant.clip.macos.safari, com.ioant.clip.ios.safari, com.ioant.clip.ios.share. Existing team and registered identifiers verified in signed builds. Attach group to both main App IDs and the new extension IDs. Preserve CloudKit entitlements on daily main targets; extensions use only required sandbox/group capabilities. Do not apply main app CloudKit Info.plist or entitlements globally to extension targets. Signed builds must verify each embedded extension and group. The daily signed builds now include all applicable extension targets.
 
## Delivery stages
1. Platform-specific settings and Chrome contact diagnostic.
2. Shared inbox writer and main app integration, Share Extension with explicit save, app group verification.
3. Safari adapter/targets sharing existing capture engine, capability detection for screenshot and clipboard APIs.
4. Real Chrome/Safari/share capture acceptance and signed daily app builds.

## Signed daily extension build
After both macOS and iOS signed extension builds passed, the daily Mac launcher targets CloudKitCaptureExtensions. The previous CloudKitDevelopment daily bundle is an explicitly recognized predecessor, with a verified backup and unchanged enrollment required at activation. `scripts/cloudkit/build_signed_development_mac.sh` now builds the extension-enabled artifact; unsigned regression remains separate. Simulator support uses its own extension artifact and verifies embedded entitlements before installation. No legacy user data is moved or deleted.

## Capture diagnostics and shared input
Safari ping records device-local activity without reading the page or creating a clip. A successful queue records only source, activity and timestamp; the share extension records only after explicit save. The settings page distinguishes these historical receipts from Safari's current enablement. Share accepts up to four supplied representations of text/HTTP(S) URLs and one image, de-duplicates repeated values, and rejects unsupported input rather than silently dropping it. The Chrome/Safari popup disables unsupported screenshot and clipboard actions. Synthetic protocol and import tests use a temporary library and never write the daily iCloud library. Actual browser permission and UI interaction remain separate acceptance gates.

## Inbox failure handling
Each capture inbox maintains independent retry and health state. Background errors surface as a non-modal status and retry at 15-second intervals rather than interrupting the user every second. Failed payloads are retained; only successfully saved captures are removed. The macOS signed entitlement must be authorized by its embedded provisioning profile for protected group access; verify both main and extension profiles. An existing development profile without group authorization may run the UI hotfix but is explicitly not considered full capture authorization.

Apple's provisioned `group.` entitlement requires `REGISTER_APP_GROUPS=YES` with automatic signing to refresh older macOS provisioning profiles. The generated extension project now explicitly sets this for its own targets. Verify embedded profile authorization separately from the signed entitlement; never revoke or delete unrelated profiles. See https://developer.apple.com/documentation/xcode/accessing-app-group-containers.

## Page layout v2
Preserve CSS clipping, wrapping, font and layout properties; omit tiny clipped accessibility-only labels, preserve safe inert form control geometry without typed values, and reconstruct literal generated text/decorative pseudo-elements. Do not inject original stylesheets or scripts. New whole-page text uses the filtered capture tree. Existing captures remain unchanged; recapture for the improved representation. Chrome and WebKit geometry regressions validate layout, not merely HTML presence. Live complex websites and remote webfonts can still differ from their original pixels; viewport snapshot remains the pixel-faithful alternative.
