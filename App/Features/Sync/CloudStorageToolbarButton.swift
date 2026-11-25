import SwiftUI

private extension StoragePresentation.Provider {
    @MainActor func title(language: LanguagePreferences) -> Text {
        switch self {
        case .local: Text(verbatim: language.localized("sync.local"))
        case .iCloud: Text(verbatim: "iCloud")
        case .googleDrive: Text(verbatim: "Google Drive")
        case .unknown: Text(verbatim: language.localized("sync.provider.unknown"))
        }
    }
    var symbol: String {
        switch self {
        case .local: "internaldrive"
        case .iCloud: "icloud"
        case .googleDrive: "externaldrive"
        case .unknown: "questionmark"
        }
    }
}
private extension StoragePresentation.State {
    var title: String {
        switch self {
        case .local: "sync.disconnected"
        case .checking: "sync.checking"
        case .syncing: "sync.running"
        case .error: "sync.status.error"
        case .conflicts: "sync.conflicts"
        case .paused: "sync.paused"
        case .unavailable: "sync.status.unavailable"
        case .linked: "sync.bound"
        case .lastSuccess: "sync.status.lastSuccess"
        }
    }
    var marker: String? {
        switch self {
        case .local: nil
        case .checking, .syncing: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.circle.fill"
        case .conflicts: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        case .unavailable: "minus.circle.fill"
        case .linked: "link.circle.fill"
        case .lastSuccess: "checkmark.circle.fill"
        }
    }
    func color(_ theme: ClipTheme) -> Color {
        switch self {
        case .error: theme.destructive
        case .conflicts: theme.warning
        case .checking, .syncing: theme.action
        case .lastSuccess: theme.success
        default: theme.secondaryText
        }
    }
}
private extension CloudSyncController {
    func presentation(for library: NoteLibrary) -> StoragePresentation {
        let activity: StoragePresentation.Activity
        switch phase {
        case .idle: activity = .idle
        case .checking: activity = .checking
        case .syncing: activity = .syncing
        case .failed: activity = .failed
        }
        return StoragePresentation(enrollment: library.syncEnrollment, activity: activity, available: available,
            hasConflicts: !(library.syncJournal?.conflictKeys.isEmpty ?? true), hadSuccess: lastSuccess != nil)
    }
}
private struct CloudStorageSymbol: View {
    @Environment(\.clipTheme) private var theme
    let status: StoragePresentation
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: status.provider.symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28, height: 24)
            if let marker = status.state.marker {
                Image(systemName: marker)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.state.color(theme))
                    .background(.background, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Native toolbar entry. Provider and status are distinguishable without color.
struct CloudStorageToolbarButton: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @EnvironmentObject private var controller: CloudSyncController
    let action: () -> Void
    var body: some View {
        let status = controller.presentation(for: store.library)
        Button(action: action) {
            CloudStorageSymbol(status: status)
        }
        .accessibilityLabel(status.provider.title(language: language))
        .accessibilityValue(Text(verbatim: language.localized(status.state.title)))
        .accessibilityHint(Text(verbatim: language.localized("sync.title")))
        .accessibilityIdentifier("clip-cloud-storage")
        #if os(macOS)
        .help(status.provider.title(language: language) + Text(verbatim: " · ") + Text(verbatim: language.localized(status.state.title)))
        #endif
    }
}
struct CloudStorageStatusRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var language: LanguagePreferences
    @EnvironmentObject private var controller: CloudSyncController
    var body: some View {
        let status = controller.presentation(for: store.library)
        HStack(spacing: LayoutMetrics.medium) {
            CloudStorageSymbol(status: status)
            VStack(alignment: .leading, spacing: 4) {
                status.provider.title(language: language).font(.headline)
                Text(verbatim: language.localized(status.state.title)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clip-cloud-storage-status")
    }
}
