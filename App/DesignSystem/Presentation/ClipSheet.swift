import SwiftUI

/// Common native sheet shell. All feature sheets use this; alerts and
/// confirmation dialogs remain native. A child page can push via NavigationLink.
struct ClipSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    var size: PresentationMetrics.SheetSize = .regular
    let parentSize: CGSize
    var confirmTitle: LocalizedStringKey = "common.done"
    var showsCancel = false
    var onConfirm: () -> Bool = { true }
    @ViewBuilder let content: () -> Content

    var body: some View {
        let navigation = NavigationStack {
            content()
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if showsCancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmTitle) { if onConfirm() { dismiss() } }
                    }
                }
        }
        #if os(macOS)
        let bounds = PresentationMetrics.sheetSize(size, parent: parentSize)
        navigation.frame(width: bounds.width, height: bounds.height)
        #else
        navigation
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

/// Shared page body. Content scrolls independently of native navigation and
/// toolbar actions; no double scroll containers or two-column Form layout.
struct ModalScrollPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.xLarge) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .padding(PresentationMetrics.desktopPadding)
            #else
            .padding(PresentationMetrics.mobilePadding)
            #endif
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

struct ModalSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.medium) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ModalDescription: View {
    let key: LocalizedStringKey
    var body: some View {
        Text(key)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Read the actual presenting window content bounds without changing layout.
struct SheetParentSizeKey: PreferenceKey {
    static var defaultValue = PresentationMetrics.mainDefault
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
