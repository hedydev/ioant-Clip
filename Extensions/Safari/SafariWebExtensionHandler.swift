import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let response = SafariCaptureBridge.respond(request, inbox: SharedCaptureInbox.directory,
            evidenceDirectory: SharedExtensionEvidence.directory, language: CaptureLanguage.read(from: CaptureLanguage.groupFile))
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
