import AppKit
import Foundation
import WebKit

@main struct PageCaptureTest {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let js = try String(contentsOfFile:"BrowserExtension/CaptureEngine/injected.js",encoding:.utf8)
        let view = WKWebView(frame:NSRect(x:0,y:0,width:1200,height:900))
        let window = NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=view
        defer { window.contentView=nil;window.close() }
        let observer=Observer()
        view.navigationDelegate=observer
        view.loadHTMLString("""
        <!doctype html><meta charset="utf-8"><style>
        *{box-sizing:border-box} body{margin:0;background:#202126;color:#eee;font:16px Arial}
        .sr{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap}
        .head{display:flex;align-items:center;gap:16px;padding:20px;height:84px}
        .brand{font-size:28px;font-weight:bold;white-space:nowrap}
        .search{width:600px;height:44px;border:1px solid #777;border-radius:22px;background:#333;color:white;padding:12px}
        main{margin:20px 0 0 140px;width:650px}
        article{margin:0 0 22px} h2{font-size:22px;line-height:30px;margin:0 0 8px;font-weight:400;overflow-wrap:normal}
        p{line-height:24px;margin:0;overflow-wrap:normal}
        .marker::before{content:"◆ ";color:#acf}.marker::after{content:"";display:inline-block;width:8px;height:8px;background:#acf}
        .clip{position:absolute;width:1px;height:1px;clip-path:inset(50%);overflow:hidden}
        </style><div class="head"><a class="sr">Skip to main content</a><a class="sr">Accessibility help</a><span class="brand">Search brand</span><input class="search" type="search" placeholder="Search" value="private field value"><button>Search</button></div>
        <main><article><h2>A long result title wrapping correctly over multiple words in the original search results</h2><p class="marker">First description with ordinary line wrapping.</p></article><article><h2>Second result title</h2><p>Second description</p></article><a class="clip">Hidden clipped help</a></main>
        """,baseURL:nil)
        try await wait(observer)
        let result = try await view.callAsyncJavaScript(js + "\nreturn await capture('page');",arguments:[:],in:nil,contentWorld:.page)
        guard let data=result as? [String:Any], let html=data["html"] as? String, let text=data["text"] as? String,
              !html.contains("private field value"), !html.contains("Accessibility help"),
              !text.contains("Skip to main content"), !html.contains("Hidden clipped help"),
              html.contains("data-ioant-control"),html.contains("data-ioant-pseudo"),html.contains("data-ioant-layout-version") else {
            throw NSError(domain:"CaptureStructure",code:1)
        }
        let original = try await view.evaluateJavaScript("""
        (()=>{const r=e=>({x:e.getBoundingClientRect().x,y:e.getBoundingClientRect().y,w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height});return {head:r(document.querySelector('.head')),input:r(document.querySelector('input')),titles:[...document.querySelectorAll('h2')].map(r),paragraphs:[...document.querySelectorAll('p')].map(r)}})()
        """) as? [String:Any]
        let part=NotePart(html:html,text:text)
        let preview=previewWebView(PreviewCoordinator())
        let previewObserver=Observer()
        preview.navigationDelegate=previewObserver
        window.contentView=preview
        preview.loadHTMLString(Note.document(for:part),baseURL:nil)
        try await wait(previewObserver)
        // The production viewer disables page scripts. Test-only evaluation is
        // isolated and observes geometry, never enables captured code.
        let actual = try await preview.evaluateJavaScript("""
        (()=>{const root=document.querySelector('[data-ioant-layout=page]');const stage=root.firstElementChild;const base=stage.getBoundingClientRect();const r=e=>({x:e.getBoundingClientRect().x-base.x,y:e.getBoundingClientRect().y-base.y,w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height});return {head:r(stage.firstElementChild.firstElementChild),input:r(root.querySelector('[data-ioant-control]')),titles:[...root.querySelectorAll('h2')].map(r),paragraphs:[...root.querySelectorAll('p')].map(r)}})()
        """) as? [String:Any]
        guard let original, let actual else { throw NSError(domain:"GeometryMissing",code:1) }
        func close(_ a:[String:Double],_ b:[String:Double]) -> Bool { ["x","y","w","h"].allSatisfy{abs((a[$0] ?? -10000)-(b[$0] ?? 10000))<=5} }
        for key in ["input"] {
            guard let a=original[key] as? [String:Double],let b=actual[key] as? [String:Double],close(a,b) else { throw NSError(domain:"GeometryMismatch-\(key)",code:1,userInfo:["original":String(describing:original[key]),"actual":String(describing:actual[key])]) }
        }
        for key in ["titles","paragraphs"] {
            guard let a=original[key] as? [[String:Double]],let b=actual[key] as? [[String:Double]],a.count==b.count,zip(a,b).allSatisfy({close($0.0,$0.1)}) else { throw NSError(domain:"GeometryMismatch-\(key)",code:1,userInfo:["original":String(describing:original[key]),"actual":String(describing:actual[key])]) }
        }
        print("PASS: WebKit source-to-production-reader layout, hidden labels, inert input, pseudo-elements and result text geometry")
    }
    @MainActor private static func wait(_ observer:Observer) async throws {
        let deadline=Date().addingTimeInterval(12)
        while !observer.finished && !observer.failed && Date()<deadline { try await Task.sleep(for:.milliseconds(100)) }
        guard observer.finished && !observer.failed else { throw NSError(domain:"Navigation",code:1) }
    }
}
private final class Observer:NSObject,WKNavigationDelegate {
    var finished=false;var failed=false
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {finished=true}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){failed=true}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){failed=true}
}
