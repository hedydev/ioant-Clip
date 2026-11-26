import UIKit
import UniformTypeIdentifiers

/// A deliberate Save tap is required. Safari supplies its page capture
/// through the same share item channel as other source attachments.
final class ShareViewController: UIViewController {
    private let status = UILabel()
    private let save = UIButton(type: .system)
    private var working = false
    private lazy var language = CaptureLanguage.read(from: CaptureLanguage.groupFile)
        ?? CaptureLanguage.resolve(selection: "system", preferred: Locale.preferredLanguages)
    private func localized(_ key: String) -> String {
        CaptureLanguage.localized(key, language: language)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "ioant-Clip"
        status.font = .preferredFont(forTextStyle: .headline)
        status.numberOfLines = 0
        status.textAlignment = .center
        save.setTitle(localized("common.save"), for: .normal)
        save.addTarget(self, action: #selector(saveCapture), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle(localized("common.cancel"), for: .normal)
        cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [status, save, cancel])
        stack.axis = .vertical; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        preferredContentSize = CGSize(width: 320, height: 240)
    }
    @objc private func cancelCapture() {
        guard !working else { return }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    @objc private func saveCapture() {
        guard !working else { return }
        working = true
        save.isEnabled = false
        status.text = localized("share.saving")
        Task { @MainActor in
            do {
                let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
                let providers = items.flatMap { $0.attachments ?? [] }
                guard providers.count <= ShareCaptureComposer.maxProviders else { throw WebCapture.ImportError.unsupported }
                let envelope = try await captureEnvelope(items: items, providers: providers)
                _ = try SharedCaptureInbox.enqueue(envelope)
                try? SharedExtensionEvidence.record(.share, activity: .queued)
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                switch error {
                case WebCapture.ImportError.tooLarge: status.text = localized("error.capture.large")
                case WebCapture.ImportError.unsupported: status.text = localized("error.capture.format")
                case WebCapture.ImportError.empty: status.text = localized("error.capture.empty")
                default: status.text = localized("share.error")
                }
                working = false
                save.isEnabled = true
            }
        }
    }

    private func captureEnvelope(items: [NSExtensionItem], providers: [NSItemProvider]) async throws -> Data {
        let propertyList = UTType.propertyList.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(propertyList) {
            let item = try await provider.loadItem(forTypeIdentifier: propertyList)
            guard let payload = item as? [String: Any],
                  let results = payload[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else { continue }
            return try ShareCaptureComposer.webPageEnvelope(results)
        }

        var composer = ShareCaptureComposer()
        for item in items {
            if let text = item.attributedContentText?.string { try composer.addText(text) }
        }
        for provider in providers {
            // A file URL offered by an image provider is not a web link.
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let value = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
                let image: UIImage?
                if let value = value as? UIImage { image = value }
                else if let data = value as? Data, data.count <= WebCapture.maxBytes { image = UIImage(data: data) }
                else if let file = value as? URL, file.isFileURL,
                        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                        size <= WebCapture.maxBytes { image = UIImage(contentsOfFile: file.path) }
                else { image = nil }
                guard let image, image.size.width * image.size.height * image.scale * image.scale <= 24_000_000,
                      let data = image.pngData() else { throw WebCapture.ImportError.tooLarge }
                try composer.addPNG(data)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                guard let link = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) else {
                    throw WebCapture.ImportError.unsupported
                }
                try composer.addURL(link)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let value = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                guard let text = (value as? String) ?? (value as? NSAttributedString)?.string else { throw WebCapture.ImportError.unsupported }
                try composer.addText(text)
            } else { throw WebCapture.ImportError.unsupported }
        }
        return try composer.envelope()
    }
}
