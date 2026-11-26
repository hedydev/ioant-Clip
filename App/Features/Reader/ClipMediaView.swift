import SwiftUI

struct ClipMediaSection: Identifiable, Sendable {
    struct Item: Identifiable, Sendable {
        let id = UUID()
        let media: NoteMedia
    }

    let id: NoteMedia.Kind
    let items: [Item]

    static func group(_ media: [NoteMedia]) -> [Self] {
        let groups = Dictionary(grouping: media, by: \.kind)
        return NoteMedia.Kind.allCases.compactMap { kind in
            groups[kind].map { Self(id: kind, items: $0.map { Item(media: $0) }) }
        }
    }
}

struct ClipMediaView: View {
    let sections: [ClipMediaSection]
    let parentSize: CGSize
    @State private var preview: NoteMedia?
    @StateObject private var thumbnails = MediaThumbnailStore()

    var body: some View {
        if sections.isEmpty {
            ContentUnavailableView("reader.media.empty", systemImage: "photo.on.rectangle.angled")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LayoutMetrics.large) {
                    ForEach(sections) { section in
                        Text(label(section.id)).font(.headline)
                        if section.items.count == 1, let item = section.items.first {
                            card(item)
                                .frame(maxWidth: 280)
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .top)], alignment: .leading) {
                                ForEach(section.items) { item in card(item) }
                            }
                        }
                    }
                }
                .padding(LayoutMetrics.large)
            }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let preview {
                    ClipSheet(title: "reader.media", size: .large, parentSize: parentSize) {
                        if let html = preview.previewDocument {
                            ReaderHTMLPreview(html: html)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ModalScrollPage {
                                VStack(spacing: LayoutMetrics.medium) {
                                    if let html = preview.thumbnailDocument {
                                        ReaderHTMLPreview(html: html)
                                            .frame(height: 180)
                                    }
                                    title(preview).multilineTextAlignment(.center)
                                    if let url = preview.source {
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
            }
        }
    }

    private func card(_ item: ClipMediaSection.Item) -> some View {
        Button {
            preview = item.media
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MediaThumbnailView(item: item, thumbnails: thumbnails)
                    .frame(height: 100)
                    .accessibilityHidden(true)
                title(item.media).font(.subheadline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(_ item: NoteMedia) -> Text {
        item.title.isEmpty ? Text(label(item.kind)) : Text(verbatim: item.title)
    }

    private func label(_ kind: NoteMedia.Kind) -> LocalizedStringKey {
        switch kind {
        case .image: "reader.media.images"
        case .svg: "reader.media.svg"
        case .video: "reader.media.video"
        case .audio: "reader.media.audio"
        }
    }
}

private struct MediaThumbnailView: View {
    let item: ClipMediaSection.Item
    let thumbnails: MediaThumbnailStore
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: placeholder)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            let loaded = await thumbnails.image(for: item.id, media: item.media)
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { image = nil }
    }

    private var placeholder: String {
        switch item.media.kind {
        case .image, .svg: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}
