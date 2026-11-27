import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ClipMediaDetail: View {
    let media: NoteMedia
    @State private var file: MediaPreviewFile?
    @State private var player: AVPlayer?
    @State private var prepared = false
    @State private var exporting = false
    @State private var exportFailed = false
    @State private var playbackFailed = false
    @State private var html: String?

    private var audiovisual: Bool { media.kind == .video || media.kind == .audio }

    var body: some View {
        VStack(spacing: LayoutMetrics.small) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let file {
                Divider()
                HStack {
                    Button { exporting = true } label: {
                        Label(LocalizedStringKey(file.isLink ? "reader.media.saveLink" : "reader.media.download"),
                              systemImage: "arrow.down.to.line")
                    }
                    ShareLink(item: file.isLink ? file.source ?? file.url : file.url) {
                        Label("reader.media.share", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, LayoutMetrics.medium)
                .padding(.bottom, LayoutMetrics.small)
            }
        }
        .task {
            guard !prepared else { return }
            let audiovisual = audiovisual
            let (file, html) = await Task.detached(priority: .userInitiated) { [media] in
                (try? MediaPreviewFile(media: media),
                 audiovisual ? media.thumbnailDocument : media.previewDocument ?? media.thumbnailDocument)
            }.value
            guard !Task.isCancelled else { return }
            self.file = file
            self.html = html
            if audiovisual, let file, !file.isLink {
                let player = AVPlayer(url: file.url)
                self.player = player
                player.play()
            }
            prepared = true
        }
        .onDisappear { player?.pause() }
        .fileExporter(isPresented: $exporting, document: file.map { MediaExportDocument(data: $0.data) },
                      contentType: file?.type ?? .data, defaultFilename: file?.name) { result in
            if case .failure = result { exportFailed = true }
        }
        .alert("reader.media.exportFailed", isPresented: $exportFailed) {
            Button("common.ok", role: .cancel) {}
        }
    }

    @ViewBuilder private var content: some View {
        if let player, let item = player.currentItem, !playbackFailed {
            Group {
                if media.kind == .audio {
                    AudioMediaPreview(player: player, title: media.title)
                } else {
                    VideoPlayer(player: player)
                }
            }
            .onReceive(item.publisher(for: \.status).receive(on: RunLoop.main)) {
                if $0 == .failed { playbackFailed = true }
            }
        } else if !prepared {
            ReaderLoadingView()
        } else if !audiovisual, media.embedded != nil, let html {
            ReaderHTMLPreview(html: html)
        } else {
            ModalScrollPage {
                VStack(spacing: LayoutMetrics.medium) {
                    if let html {
                        ReaderHTMLPreview(html: html).frame(height: 180)
                    }
                    if !media.title.isEmpty {
                        Text(verbatim: media.title).multilineTextAlignment(.center)
                    }
                    if playbackFailed || media.source == nil {
                        Text("reader.preview.error").foregroundStyle(.secondary)
                    }
                    if let url = media.source {
                        Link(destination: url) {
                            Label("reader.media.source", systemImage: "arrow.up.right")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct AudioMediaPreview: View {
    let player: AVPlayer
    let title: String
    @State private var playing = false

    var body: some View {
        VStack(spacing: LayoutMetrics.medium) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(verbatim: title).lineLimit(2)
            Button {
                if playing {
                    player.pause()
                } else {
                    if let duration = player.currentItem?.duration.seconds, duration.isFinite,
                       player.currentTime().seconds >= duration {
                        player.seek(to: .zero)
                    }
                    player.play()
                }
            } label: {
                Label(LocalizedStringKey(playing ? "reader.media.pause" : "reader.media.play"),
                      systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(LayoutMetrics.large)
        .onReceive(player.publisher(for: \.timeControlStatus).receive(on: RunLoop.main)) {
            playing = $0 != .paused
        }
    }
}

private final class MediaPreviewFile: Sendable {
    let data: Data
    let type: UTType
    let name: String
    let url: URL
    let source: URL?
    let isLink: Bool

    init?(media: NoteMedia) throws {
        let reserved = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let title = media.title.components(separatedBy: reserved).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var name = String(String.UnicodeScalarView(title.unicodeScalars.prefix(45)))
        if name.isEmpty { name = "Clip-" + media.kind.rawValue }
        self.name = name
        source = media.source

        if let encoded = media.embedded, let content = MediaData(url: encoded) {
            data = content.bytes
            type = UTType(mimeType: content.mimeType) ?? .data
            isLink = false
        } else if let source = media.source {
            data = try PropertyListSerialization.data(fromPropertyList: ["URL": source.absoluteString], format: .xml, options: 0)
            type = UTType(filenameExtension: "webloc") ?? .xml
            isLink = true
        } else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let filenameExtension = isLink ? "webloc" : type.preferredFilenameExtension ?? "bin"
        let url = directory.appending(path: name).appendingPathExtension(filenameExtension)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.url = url
    }

    deinit { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

private struct MediaExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
