import Foundation

/// Same request path used by the actual Safari handler; an explicit inbox URL
/// permits end-to-end synthetic tests without using any enrolled library.
public enum SafariCaptureBridge {
    public static func respond(_ request: [String: Any]?, inbox: URL?, evidenceDirectory: URL?, language: String?) -> [String: Any] {
        do {
            guard let request, request["version"] as? Int == 1, let action = request["action"] as? String else {
                throw WebCapture.ImportError.unsupported
            }
            guard let inbox, let evidenceDirectory else { throw CocoaError(.fileWriteNoPermission) }
            if action == "ping" {
                guard Set(request.keys) == ["version", "action"] else { throw WebCapture.ImportError.unsupported }
                try SharedExtensionEvidence.record(.safari, activity: .ping, directory: evidenceDirectory)
                var response: [String: Any] = ["ok": true, "state": "reachable", "version": 1]
                if let language, CaptureLanguage.codes.contains(language) { response["language"] = language }
                return response
            }
            guard action == "capture", let capture = request["capture"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(capture) else { throw WebCapture.ImportError.unsupported }
            let data = try JSONSerialization.data(withJSONObject: capture)
            let id = try SharedCaptureInbox.enqueue(data, directory: inbox)
            // A diagnostic failure must never cause retry of a queued capture.
            try? SharedExtensionEvidence.record(.safari, activity: .queued, directory: evidenceDirectory)
            return ["ok": true, "state": "queued", "id": id.uuidString, "opened": false]
        } catch {
            let code: String
            switch error {
            case WebCapture.ImportError.tooLarge: code = "error_large"
            case WebCapture.ImportError.empty: code = "error_empty"
            default: code = "error_native"
            }
            return ["ok": false, "error": code]
        }
    }
}
