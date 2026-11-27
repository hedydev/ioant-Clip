import SwiftUI

struct ClipLinksView: View {
    let links: [NoteLink]
    @StateObject private var thumbnails = MediaThumbnailStore()

    var body: some View {
        if links.isEmpty {
            ContentUnavailableView("reader.links.empty", systemImage: "link")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(links) { link in
                        Link(destination: link.url) {
                            HStack(spacing: LayoutMetrics.medium) {
                                if let media = link.media.first {
                                    MediaThumbnailView(media: media, id: link.id, thumbnails: thumbnails)
                                        .frame(width: 56, height: 44)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "link")
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                }

                                VStack(alignment: .leading, spacing: LayoutMetrics.xSmall) {
                                    if !link.title.isEmpty {
                                        Text(verbatim: link.title)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                    }
                                    Text(verbatim: link.url.absoluteString)
                                        .font(link.title.isEmpty ? .body : .caption)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, LayoutMetrics.medium)
                            .contentShape(Rectangle())
                        }
                        Divider()
                    }
                }
                .padding(.horizontal, LayoutMetrics.large)
            }
            .pauseVectorThumbnailsDuringScroll(thumbnails)
        }
    }
}
