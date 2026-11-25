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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .top)], alignment: .leading) {
                                ForEach(group.indices, id: \.self) { index in
                                    card(group[index])
                                }
                            }
                        }
                    }
                }
                .padding(LayoutMetrics.large)
            }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let preview, let html = preview.previewDocument {
                    ClipSheet(title: "reader.media", size: .large, parentSize: parentSize) {
                        HTMLPreview(html: html)
                    }
                }
            }
        }
    }

    private func card(_ item: NoteMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let html = item.thumbnailDocument {
                HTMLPreview(html: html)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(height: 100)
            }
            title(item).font(.subheadline).lineLimit(2)
            if item.embedded != nil {
                Button { preview = item } label: {
                    Label("reader.media.offline", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } else if let url = item.source {
                Link(destination: url) {
                    Label("reader.media.source", systemImage: "arrow.up.right")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
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
