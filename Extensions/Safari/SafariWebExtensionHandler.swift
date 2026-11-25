import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        var response: [String: Any] = ["ok": false, "error": "Invalid or unsupported capture."]
        do {
            guard let request, request["version"] as? Int == 1 else { throw WebCapture.ImportError.unsupported }
            if request["action"] as? String == "ping" {
                guard SharedCaptureInbox.directory != nil else { throw CocoaError(.fileWriteNoPermission) }
                response = ["ok": true, "state": "reachable", "version": 1]
            } else {
                guard request["action"] as? String == "capture",
                      let capture = request["capture"] as? [String: Any],
                      JSONSerialization.isValidJSONObject(capture) else { throw WebCapture.ImportError.unsupported }
                let data = try JSONSerialization.data(withJSONObject: capture)
                let id = try SharedCaptureInbox.enqueue(data)
                response = ["ok": true, "state": "queued", "id": id.uuidString, "opened": false]
            }
        } catch {
            response = ["ok": false, "error": "Unable to queue capture in ioant-Clip."]
        }
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
