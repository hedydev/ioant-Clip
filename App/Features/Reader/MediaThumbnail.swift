import ImageIO
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#endif

@MainActor final class MediaThumbnailStore: ObservableObject {
    private final class Entry {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    private let cache = NSCache<NSUUID, Entry>()
    private let decoder = MediaThumbnailDecoder()
    private let vectorRenderer = MediaVectorThumbnailRenderer()
    private var pendingVector: Task<CGImage?, Never>?

    init() {
        cache.countLimit = 96
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    func image(for id: UUID, media: NoteMedia) async -> CGImage? {
        if let entry = cache.object(forKey: id as NSUUID) { return entry.image }
        guard let source = media.thumbnailSource, !Task.isCancelled else { return nil }
        let image: CGImage?
        if source.prefix(100).lowercased().hasPrefix("data:image/svg+xml") {
            let previous = pendingVector
            let work = Task {
                _ = await previous?.value
                guard !Task.isCancelled, let html = media.thumbnailDocument else { return nil as CGImage? }
                return await vectorRenderer.image(for: html)
            }
            pendingVector = work
            image = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
        } else {
            image = await decoder.image(for: source)
        }
        guard !Task.isCancelled else { return nil }
        let cost = image.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(Entry(image), forKey: id as NSUUID, cost: cost)
        return image
    }
}

actor MediaThumbnailDecoder {
    func image(for source: String) -> CGImage? {
        guard !Task.isCancelled, let delimiter = source.firstIndex(of: ",") else { return nil }
        let header = source[..<delimiter].lowercased()
        guard header.hasPrefix("data:image/"), let bytes = Self.bytes(source[source.index(after: delimiter)...],
                                                                        base64: header.hasSuffix(";base64")),
              let image = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary)
    }

    private static func bytes(_ payload: Substring, base64: Bool) -> Data? {
        if base64, !payload.contains("%") { return Data(base64Encoded: String(payload)) }
        var result = Data()
        var input = payload.utf8.makeIterator()
        while let byte = input.next() {
            if byte == 37 {
                guard let first = input.next(), let second = input.next(),
                      let high = hex(first), let low = hex(second) else { return nil }
                result.append(high * 16 + low)
            } else {
                result.append(byte)
            }
        }
        return base64 ? Data(base64Encoded: result) : result
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}

@MainActor final class MediaVectorThumbnailRenderer {
    private let coordinator = PreviewCoordinator()
    private lazy var view: WKWebView = {
        let view = previewWebView(coordinator)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 192)
        return view
    }()
    private var active: (id: UUID, result: CheckedContinuation<CGImage?, Never>)?
    private var timeout: Task<Void, Never>?

    func image(for html: String) async -> CGImage? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, active == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                active = (id, continuation)
                coordinator.onLoad = { [weak self] success in
                    guard let self, self.active?.id == id else { return }
                    if success {
                        self.snapshot(id)
                    } else {
                        self.finish(id, image: nil)
                    }
                }
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled { self?.finish(id, image: nil) }
                }
                coordinator.render(html, in: view, force: true)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, image: nil) }
        }
    }

    private func snapshot(_ id: UUID) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 320
        view.takeSnapshot(with: config) { [weak self] image, _ in
            #if os(macOS)
            var bounds = CGRect(origin: .zero, size: image?.size ?? .zero)
            self?.finish(id, image: image?.cgImage(forProposedRect: &bounds, context: nil, hints: nil))
            #else
            self?.finish(id, image: image?.cgImage)
            #endif
        }
    }

    private func finish(_ id: UUID, image: CGImage?) {
        guard let active, active.id == id else { return }
        self.active = nil
        coordinator.onLoad = nil
        timeout?.cancel()
        timeout = nil
        if image == nil { view.stopLoading() }
        active.result.resume(returning: image)
    }
}
