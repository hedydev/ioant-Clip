import SwiftUI

struct ClipMediaView: View {
    let items: [NoteMedia]
    let parentSize: CGSize
    @State private var preview: NoteMedia?

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("reader.media.empty", systemImage: "photo.on.rectangle.angled")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.large) {
                    ForEach(NoteMedia.Kind.allCases, id: \.self) { kind in
                        let group = items.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Text(label(kind)).font(.headline)
                            if group.count == 1, let item = group.first {
                                card(item)
                                    .frame(maxWidth: 280)
                                    .frame(maxWidth: .infinity)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .top)], alignment: .leading) {
                                    ForEach(group.indices, id: \.self) { index in
                                        card(group[index])
                                    }
                                }
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

    private func card(_ item: NoteMedia) -> some View {
        Button {
            preview = item
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let html = item.thumbnailDocument {
                    ReaderHTMLPreview(html: html, compact: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .frame(height: 100)
                } else {
                    Image(systemName: item.kind == .audio ? "waveform" : item.kind == .video ? "film" : "photo")
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .accessibilityHidden(true)
                }
                title(item).font(.subheadline).lineLimit(2)
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
