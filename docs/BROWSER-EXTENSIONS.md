# Browser and share extensions

## Platform policy
- macOS: retain existing Chrome extension and key; add Safari Web Extension.
- iOS/iPadOS: Safari Web Extension for page/selection/answer capture; Chrome and other apps through Share Extension (only supplied text, URL, image or supported attachments; never promise DOM access).
- Extension settings list only applicable local capabilities. Distinguish bundled target, Safari system enablement, native host registration, last confirmed bridge communication and actual website authorization. No private Chrome profile scraping or automatic enablement.
- Safari macOS queries SFSafariExtensionManager.stateOfSafariExtension; iOS 26.2+ uses stateOfExtension; older iOS requires manual confirmation or a future shared receipt. Share sheet visibility isn't a global enabled flag. Chrome ping is diagnostic only, no page read, inbox write or app launch.
- Native share and Safari extensions use an App Group durable inbox, never modify notes.json directly. Main app imports using existing CaptureInbox and then existing consent-bound cloud sync. Keep review lanes isolated. No automatic clipboard/background browser collection.

## Proposed Apple configuration (not yet registered)
App Group group.com.ioant.clip; target identifiers com.ioant.clip.macos.safari, com.ioant.clip.ios.safari, com.ioant.clip.ios.share. Confirm availability and team before registration. Attach group to both main App IDs and the new extension IDs. Preserve CloudKit entitlements on daily main targets; extensions use only required sandbox/group capabilities. Do not apply main app CloudKit Info.plist or entitlements globally to extension targets. Signed builds must verify each embedded extension and group. Use separate conditional XcodeGen targets until signatures ready; no loss of daily client functionality.
 
## Delivery stages
1. Platform-specific settings and Chrome contact diagnostic.
2. Shared inbox writer and main app integration, Share Extension with explicit save, app group verification.
3. Safari adapter/targets sharing existing capture engine, capability detection for screenshot and clipboard APIs.
4. Real Chrome/Safari/share capture acceptance and signed daily app builds.
