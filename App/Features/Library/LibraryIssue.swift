import Foundation

/// Stable presentation codes; raw OS diagnostics stay separate.
struct LibraryIssue {
    let key: String
    let detail: String?
    init(_ key: String, detail: String? = nil) { self.key = key; self.detail = detail }
    init(_ error: Error) {
        switch error {
        case WebCapture.ImportError.tooLarge: self.init("error.capture.large")
        case WebCapture.ImportError.unsupported: self.init("error.capture.format")
        case WebCapture.ImportError.empty: self.init("error.capture.empty")
        case SyncJournal.JournalError.unresolvedConflict: self.init("error.sync.conflict")
        default: self.init("error.operation", detail: error.localizedDescription)
        }
    }
}
