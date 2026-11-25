import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        var response: [String: Any] = ["ok": false, "error": "error_native"]
        do {
            guard let request, request["version"] as? Int == 1 else { throw WebCapture.ImportError.unsupported }
            if request["action"] as? String == "ping" {
                guard SharedCaptureInbox.directory != nil else { throw CocoaError(.fileWriteNoPermission) }
                response = ["ok": true, "state": "reachable", "version": 1]
                if let language = CaptureLanguage.read(from: CaptureLanguage.groupFile) { response["language"] = language }
            } else {
                guard request["action"] as? String == "capture",
                      let capture = request["capture"] as? [String: Any],
                      JSONSerialization.isValidJSONObject(capture) else { throw WebCapture.ImportError.unsupported }
                let data = try JSONSerialization.data(withJSONObject: capture)
                let id = try SharedCaptureInbox.enqueue(data)
                response = ["ok": true, "state": "queued", "id": id.uuidString, "opened": false]
            }
        } catch {
            let code: String
            switch error {
            case WebCapture.ImportError.tooLarge: code = "error_large"
            case WebCapture.ImportError.empty: code = "error_empty"
            default: code = "error_native"
            }
            response = ["ok": false, "error": code]
        }
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
