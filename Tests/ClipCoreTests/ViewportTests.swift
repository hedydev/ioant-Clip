import XCTest
@testable import ClipCore
final class ViewportTests: XCTestCase {
    func testViewportImport() throws {
        let data=Data(#"{"version":1,"title":"Visible page","sourceURL":"https://example.test","mode":"viewport","html":"<img src='data:image/png;base64,AA=='>","text":"Visible page"}"#.utf8)
        let capture=try WebCapture.decode(data)
        XCTAssertEqual(capture.part.captureMode,"viewport")
        XCTAssertTrue(capture.part.renderedHTML.contains("data:image/png"))
    }
}
