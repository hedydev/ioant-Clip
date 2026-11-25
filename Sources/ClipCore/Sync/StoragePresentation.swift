import Foundation

/// Presentation reflects actual enrollment and session state, never a guessed
/// provider or a promise that the entire library is currently synchronized.
public struct StoragePresentation: Equatable, Sendable {
    public enum Provider: Equatable, Sendable { case local, iCloud, googleDrive, unknown }
    public enum Activity: Equatable, Sendable { case idle, checking, syncing, failed }
    public enum State: Equatable, Sendable { case local, checking, syncing, error, conflicts, paused, unavailable, linked, lastSuccess }
    public let provider: Provider
    public let state: State
    public init(enrollment: SyncEnrollment?, activity: Activity, available: Bool, hasConflicts: Bool, hadSuccess: Bool) {
        switch enrollment?.account.provider {
        case nil: provider = .local
        case "icloud": provider = .iCloud
        case "google", "google-drive", "googleDrive": provider = .googleDrive
        default: provider = .unknown
        }
        if activity == .checking { state = .checking }
        else if activity == .syncing { state = .syncing }
        else if activity == .failed { state = .error }
        else if hasConflicts { state = .conflicts }
        else if enrollment == nil { state = .local }
        else if enrollment?.isPaused == true { state = .paused }
        else if !available || provider != .iCloud { state = .unavailable }
        else if hadSuccess { state = .lastSuccess }
        else { state = .linked }
    }
}
