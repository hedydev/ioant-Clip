import Foundation
@main struct PresentationMetricsTest {
    static func main() {
        let normal = PresentationMetrics.sheetSize(.large, parent: CGSize(width: 1200, height: 800))
        precondition(normal == CGSize(width: 660, height: 660))
        let small = PresentationMetrics.sheetSize(.large, parent: CGSize(width: 760, height: 480))
        precondition(small.width == 660 && small.height == 448)
        let narrow = PresentationMetrics.sheetSize(.regular, parent: CGSize(width: 450, height: 360))
        precondition(narrow == CGSize(width: 386, height: 328))
        precondition(PresentationMetrics.initialWindowSize(available: CGSize(width: 1440,height:900),current:CGSize(width:895,height:444)) == CGSize(width:1200,height:800))
        precondition(PresentationMetrics.initialWindowSize(available: CGSize(width: 1024,height:700),current:CGSize(width:895,height:444)) == CGSize(width:1024,height:700))
        precondition(PresentationMetrics.initialWindowSize(available: CGSize(width: 1920,height:1080),current:CGSize(width:1500,height:900)) == CGSize(width:1500,height:900))
        print("Presentation metrics: default, small screen, bounded sheets and larger window preservation passed")
    }
}
