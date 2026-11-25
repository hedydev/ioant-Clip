import Foundation

/// Points, not pixels. The native system owns safe areas, animation and chrome.
enum PresentationMetrics {
    static let mainDefault = CGSize(width: 1200, height: 800)
    static let mainMinimum = CGSize(width: 760, height: 480)
    static let sheetMargin: CGFloat = 32
    static let desktopPadding: CGFloat = 28
    static let mobilePadding: CGFloat = 20
    enum SheetSize {
        case regular, large
        var preferred: CGSize {
            switch self {
            case .regular: CGSize(width: 580, height: 580)
            case .large: CGSize(width: 660, height: 660)
            }
        }
    }
    static func sheetSize(_ preset: SheetSize, parent: CGSize) -> CGSize {
        let availableWidth = max(1, parent.width - sheetMargin * 2)
        let availableHeight = max(1, parent.height - sheetMargin)
        return CGSize(width: min(preset.preferred.width, availableWidth),
                      height: min(preset.preferred.height, availableHeight))
    }
    static func initialWindowSize(available: CGSize, current: CGSize) -> CGSize {
        CGSize(width: min(available.width, max(current.width, mainDefault.width)),
               height: min(available.height, max(current.height, mainDefault.height)))
    }
}
