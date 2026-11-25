import UIKit
import UniformTypeIdentifiers

/// A deliberate Save tap is required. Sources supply the content; no browser
/// DOM scraping or network fetch is performed by the share extension.
final class ShareViewController: UIViewController {
    private let status = UILabel()
    private let save = UIButton(type: .system)
    private var working = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "ioant-Clip"
        status.font = .preferredFont(forTextStyle: .headline)
        status.numberOfLines = 0
        status.textAlignment = .center
        save.setTitle(String(localized: "common.save"), for: .normal)
        save.addTarget(self, action: #selector(saveCapture), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle(String(localized: "common.cancel"), for: .normal)
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
        Task { @MainActor in
            do {
                let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
                let providers = items.flatMap { $0.attachments ?? [] }
                guard providers.count <= 1 else { throw WebCapture.ImportError.unsupported }
                var text = items.compactMap { $0.attributedContentText?.string }.joined(separator: "\n")
                var url = ""
                var html = ""
                if let provider = providers.first {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                        guard let link = value as? URL, ["http", "https"].contains(link.scheme?.lowercased() ?? "") else {
                            throw WebCapture.ImportError.unsupported
                        }
                        url = link.absoluteString
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = url }
                        else if !text.contains(url) { text += "\n" + url }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        let value = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                        guard let sharedText = value as? String else { throw WebCapture.ImportError.unsupported }
                        text = sharedText
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        let value = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
                        let image: UIImage?
                        if let value = value as? UIImage { image = value }
                        else if let data = value as? Data, data.count <= WebCapture.maxBytes { image = UIImage(data: data) }
                        else if let file = value as? URL, file.isFileURL,
                                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                                size <= WebCapture.maxBytes { image = UIImage(contentsOfFile: file.path) }
                        else { image = nil }
                        guard let image, image.size.width * image.size.height * image.scale * image.scale <= 24_000_000,
                              let data = image.pngData(), data.count <= 22 * 1024 * 1024 else { throw WebCapture.ImportError.tooLarge }
                        html = "<img src=\"data:image/png;base64,\(data.base64EncodedString())\">"
                    } else { throw WebCapture.ImportError.unsupported }
                }
                let title = String(text.split(whereSeparator: \.isNewline).first?.prefix(70) ?? "ioant-Clip")
                let capture: [String: Any] = ["version": 1, "mode": "selection", "title": title, "sourceURL": url, "html": html, "text": text]
                _ = try SharedCaptureInbox.enqueue(JSONSerialization.data(withJSONObject: capture))
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                status.text = error.localizedDescription
                working = false
                save.isEnabled = true
            }
        }
    }
}
