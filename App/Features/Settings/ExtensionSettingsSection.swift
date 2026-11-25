import SwiftUI
import SafariServices
#if os(macOS)
import AppKit
#endif

struct ExtensionSettingsSection: View {
    private enum SafariStatus {
        case checking, notEmbedded, unavailable, enabled, disabled, unknown
        var label: String {
            switch self {
            case .checking: "settings.extensions.checking"
            case .notEmbedded: "settings.extensions.notEmbedded"
            case .unavailable: "settings.extensions.manual"
            case .enabled: "settings.extensions.enabled"
            case .disabled: "settings.extensions.disabled"
            case .unknown: "settings.extensions.unknown"
            }
        }
    }
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var language: LanguagePreferences
    @State private var safari: SafariStatus = .checking
    @State private var checking = false
    @State private var safariIdentifier: String?
    #if os(macOS)
    @State private var chrome = ChromeExtensionEvidence(registration: .unknown, lastContact: nil)
    #else
    @State private var shareEmbedded = false
    #endif

    var body: some View {
        ModalSection(title: "settings.extensions") {
            #if os(macOS)
            details("Chrome", icon: "globe", status: chrome.registration.label,
                    description: "settings.extensions.chrome.description")
            if let date = chrome.lastContact {
                LabeledContent {
                    Text(date, format: .dateTime.month().day().hour().minute())
                } label: { Text(verbatim: language.localized("settings.extensions.lastContact")) }
                .font(.caption)
            } else {
                Text(verbatim: language.localized("settings.extensions.noContact")).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
                   let target = URL(string: "chrome://extensions/") {
                    NSWorkspace.shared.open([target], withApplicationAt: chromeURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                }
            } label: { Text(verbatim: language.localized("settings.extensions.openChrome")) }.buttonStyle(.bordered)
            #else
            details("Chrome", icon: "globe", status: shareEmbedded ? "settings.extensions.shareAvailable" : "settings.extensions.notEmbedded",
                    description: "settings.extensions.mobileChrome.description")
            Divider()
            details("settings.extensions.share", icon: "square.and.arrow.up",
                    status: shareEmbedded ? "settings.extensions.shareAvailable" : "settings.extensions.notEmbedded",
                    description: "settings.extensions.share.description")
            #endif
            Divider()
            details("Safari", icon: "safari", status: safari.label,
                    description: "settings.extensions.safari.description")
            #if os(macOS)
            if let safariIdentifier {
                Button {
                    SFSafariApplication.showPreferencesForExtension(withIdentifier: safariIdentifier) { _ in }
                } label: { Text(verbatim: language.localized("settings.extensions.openSafari")) }.buttonStyle(.bordered)
            }
            #endif
            Button {
                Task { await refresh() }
            } label: {
                Label { Text(verbatim: language.localized("settings.extensions.refresh")) } icon: { Image(systemName: "arrow.clockwise") }
            }
            .disabled(checking)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("clip-extensions-refresh")
        }
        .task { await refresh() }
        .onChange(of: phase) { _, next in
            if next == .active { Task { await refresh() } }
        }
    }

    private func details(_ name: String, icon: String, status: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label { Text(verbatim: name == "Chrome" || name == "Safari" ? name : language.localized(name)) } icon: { Image(systemName: icon) }.font(.headline)
                Spacer(minLength: LayoutMetrics.small)
                Text(verbatim: language.localized(status)).font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: language.localized(description)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 4)
    }

    @MainActor private func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let embedded = (Bundle.main.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        } ?? []).compactMap(Bundle.init(url:))
        func extensionPoint(_ bundle: Bundle) -> String? {
            (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        }
        let safariBundle = embedded.first { extensionPoint($0) == "com.apple.Safari.web-extension" }
        safariIdentifier = safariBundle?.bundleIdentifier
        #if os(macOS)
        chrome = ChromeExtensionEvidence.read()
        #else
        shareEmbedded = embedded.contains { extensionPoint($0) == "com.apple.share-services" }
        #endif
        guard let id = safariIdentifier else { safari = .notEmbedded; return }
        safari = .checking
        do {
            #if os(macOS)
            let state = try await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: id)
            safari = state.isEnabled ? .enabled : .disabled
            #else
            if #available(iOS 26.2, *) {
                let state = try await SFSafariExtensionManager.stateOfExtension(withIdentifier: id)
                safari = state.isEnabled ? .enabled : .disabled
            } else { safari = .unavailable }
            #endif
        } catch { safari = .unknown }
    }
}

#if os(macOS)
private struct ChromeExtensionEvidence {
    enum Registration {
        case registered, absent, unknown
        var label: String {
            switch self {
            case .registered: "settings.extensions.registered"
            case .absent: "settings.extensions.notRegistered"
            case .unknown: "settings.extensions.unknown"
            }
        }
    }
    let registration: Registration
    let lastContact: Date?
    static func read() -> Self {
        // Only read this app's own native host manifest/config/receipt.
        // Do not inspect Chrome profiles or claim current extension enablement.
        let support = URL.applicationSupportDirectory
        let root = support.appending(path: "ioant-Clip/NativeMessaging")
        let manifest = support.appending(path: "Google/Chrome/NativeMessagingHosts/com.ioant.clip.capture.json")
        func object(_ url: URL) throws -> [String: Any] {
            guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
        var status: Registration = .unknown
        do {
            let config = try object(root.appending(path: "config.json"))
            let entry = try object(manifest)
            let expectedOrigin = "chrome-extension://jafafphgjkhcbohicihofmafobligkdj/"
            if entry["name"] as? String == "com.ioant.clip.capture",
               entry["allowed_origins"] as? [String] == [expectedOrigin],
               config["allowed_origins"] as? [String] == [expectedOrigin],
               let path = entry["path"] as? String,
               URL(fileURLWithPath: path).standardizedFileURL.path == root.appending(path: "host.py").standardizedFileURL.path,
               FileManager.default.isExecutableFile(atPath: path) {
                status = .registered
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            status = .absent
        } catch {}
        let receipt = try? object(root.appending(path: "last-contact.json"))
        let date: Date?
        if receipt?["version"] as? Int == 1, let timestamp = receipt?["unixSeconds"] as? Double,
           timestamp > 0, timestamp <= Date().timeIntervalSince1970 + 60 {
            date = Date(timeIntervalSince1970: timestamp)
        } else { date = nil }
        return Self(registration: status, lastContact: date)
    }
}
#endif
