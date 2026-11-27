import SwiftUI

struct ClipLinksView: View {
    let links: [NoteLink]
    let parentSize: CGSize
    @State private var selectedLink: NoteLink?
    @StateObject private var thumbnails = MediaThumbnailStore()

    var body: some View {
        if links.isEmpty {
            ContentUnavailableView("reader.links.empty", systemImage: "link")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(links) { link in
                        Button { selectedLink = link } label: {
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
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, LayoutMetrics.medium)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal, LayoutMetrics.large)
            }
            .pauseVectorThumbnailsDuringScroll(thumbnails)
            .sheet(item: $selectedLink) { link in
                ClipSheet(title: "reader.links.detail", parentSize: parentSize) {
                    ModalScrollPage {
                        if let media = link.media.first {
                            MediaThumbnailView(media: media, id: link.id, thumbnails: thumbnails)
                                .frame(height: 180)
                                .accessibilityHidden(true)
                        }
                        if !link.title.isEmpty {
                            Text(verbatim: link.title)
                                .font(.headline)
                                .textSelection(.enabled)
                        }
                        Text(verbatim: link.url.absoluteString)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(destination: link.url) {
                            Label("reader.links.open", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}
