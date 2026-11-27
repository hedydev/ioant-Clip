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
    @State private var preview: ClipMediaSection.Item?
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
            .pauseVectorThumbnailsDuringScroll(thumbnails)
            .sheet(item: $preview) { item in
                ClipSheet(title: "reader.media", size: .large, parentSize: parentSize) {
                    ClipMediaDetail(media: item.media)
                }
            }
        }
    }

    private func card(_ item: ClipMediaSection.Item) -> some View {
        Button {
            preview = item
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MediaThumbnailView(media: item.media, id: item.id, thumbnails: thumbnails)
                    .frame(height: 100)
                    .overlay(alignment: .bottomTrailing) {
                        if item.media.embedded != nil && (item.media.kind == .video || item.media.kind == .audio) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .padding(4)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
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

struct MediaThumbnailView: View {
    let media: NoteMedia
    let id: UUID
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
        .task(id: id) {
            let loaded = await thumbnails.image(for: id, media: media)
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { image = nil }
    }

    private var placeholder: String {
        switch media.kind {
        case .image, .svg: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}
