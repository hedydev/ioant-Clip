import Foundation
import AppKit
import SafariServices

@main struct CaptureRuntimeInspection {
    @MainActor static func main() async throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier:"com.ioant.clip.macos").filter { !$0.isTerminated }
        guard apps.count == 1, let url = apps.first?.bundleURL, let app = Bundle(url:url),
              app.object(forInfoDictionaryKey:"ClipCloudKitDevelopment") as? String == "YES" else {
            fatalError("Expected one signed daily Mac client")
        }
        let embedded = try FileManager.default.contentsOfDirectory(at: app.builtInPlugInsURL!, includingPropertiesForKeys:nil).compactMap(Bundle.init(url:))
        guard embedded.contains(where: {$0.bundleIdentifier == "com.ioant.clip.macos.safari"}) else { fatalError("Safari extension not embedded") }
        do {
            let state = try await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier:"com.ioant.clip.macos.safari")
            print("Actual macOS Safari extension enabled:",state.isEnabled)
        } catch {
            print("Actual macOS Safari state unavailable:",(error as NSError).domain,(error as NSError).code)
        }
        print("No user preferences modified; no capture queued")
    }
}
