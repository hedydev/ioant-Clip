import Foundation
@main struct PresentationMetricsTest {
    static func check(_ actual: CGSize, _ width: CGFloat, _ height: CGFloat) {
        precondition(actual.width == width && actual.height == height)
    }
    static func main() {
        check(PresentationMetrics.sheetSize(.large, parent: CGSize(width: 1200, height: 800)), 660, 660)
        check(PresentationMetrics.sheetSize(.large, parent: CGSize(width: 760, height: 480)), 660, 448)
        check(PresentationMetrics.sheetSize(.regular, parent: CGSize(width: 450, height: 360)), 386, 328)
        check(PresentationMetrics.initialWindowSize(available: CGSize(width: 1440,height:900),current:CGSize(width:895,height:444)),1200,800)
        check(PresentationMetrics.initialWindowSize(available: CGSize(width: 1024,height:700),current:CGSize(width:895,height:444)),1024,700)
        check(PresentationMetrics.initialWindowSize(available: CGSize(width: 1920,height:1080),current:CGSize(width:1500,height:900)),1500,900)
        print("Presentation metrics: default, small screen, bounded sheets and larger window preservation passed")
    }
}
