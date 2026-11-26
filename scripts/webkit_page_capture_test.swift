import AppKit
import AVFoundation
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
        .sticky{position:sticky;top:120px;z-index:2;height:20px}
        .result-link{display:flex}
        article{margin:0 0 22px} h2{font-size:22px;line-height:30px;margin:0 0 8px;font-weight:400;overflow-wrap:normal}
        p{line-height:24px;margin:0;overflow-wrap:normal}
        .marker::before{content:"◆ ";color:#acf}.marker::after{content:"";display:inline-block;width:8px;height:8px;background:#acf}
        .clip{position:absolute;width:1px;height:1px;clip-path:inset(50%);overflow:hidden}
        </style><div class="head"><a class="sr">Skip to main content</a><a class="sr">Accessibility help</a><span class="brand">Search brand</span><input class="search" type="search" placeholder="Search" value="private field value"><button>Search</button></div>
        <main><nav class="sticky">Filters</nav><article><a class="result-link"><h2>A long result title wrapping correctly over multiple words in the original search results</h2></a><p class="marker">First description with ordinary line wrapping.</p></article><article><h2>Second result title</h2><p>Second description</p></article><a class="clip">Hidden clipped help</a><video controls title="Fixture video" src="data:video/mp4;base64,AA=="></video><a href="https://www.tiktok.com/@fixture/video/123?tracking=example"><video style="width:240px;height:135px" preload="none" title="Fixture short video" src="blob:https://www.tiktok.com/fixture" poster="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII="></video></a><audio title="Fixture audio" src="data:audio/mpeg;base64,AA=="></audio></main>
        """,baseURL:nil)
        try await wait(observer)
        let result = try await view.callAsyncJavaScript(js + "\nreturn await capture('page');",arguments:[:],in:nil,contentWorld:.page)
        guard let data=result as? [String:Any], let html=data["html"] as? String, let text=data["text"] as? String,
              !html.contains("private field value"), !html.contains("Accessibility help"),
              !text.contains("Skip to main content"), !html.contains("Hidden clipped help"),
              html.contains("data-ioant-control"),html.contains("data-ioant-pseudo"),html.contains("data-ioant-layout-version") else {
            throw NSError(domain:"CaptureStructure",code:1)
        }
        guard html.contains("data-ioant-media=\"video\""),
              html.contains("data-ioant-media=\"audio\""),
              html.contains("data-ioant-video-preview"),
              html.contains("data-ioant-media-src=\"https://www.tiktok.com/@fixture/video/123\""),
              html.contains("data-ioant-media-src=\"data:video/mp4;base64,AA==\""),
              !html.contains("<video"), !html.contains("<audio") else {
            throw NSError(domain:"MediaMetadata",code:1)
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
        let videoPreview = try await preview.evaluateJavaScript("""
        (() => {
            const frame = document.querySelectorAll('[data-ioant-video-preview]')[1];
            const bounds = frame.getBoundingClientRect();
            return bounds.width === 240 && bounds.height === 135 &&
                frame.querySelector('img').getAttribute('src')?.startsWith('data:image/png;base64,');
        })()
        """) as? Bool
        guard videoPreview == true else { throw NSError(domain:"VideoPosterGeometry",code:1) }
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
        let expandedObserver = Observer()
        preview.navigationDelegate = expandedObserver
        let expanded = Note.document(for: part).replacingOccurrences(
            of: "</style></head>",
            with: "h2{letter-spacing:12px!important}</style></head>"
        )
        preview.loadHTMLString(expanded,baseURL:nil)
        try await wait(expandedObserver)
        let separated = try await preview.evaluateJavaScript("""
        (() => {
            const heading = document.querySelector('h2');
            const summary = heading.closest('article').querySelector('p');
            const sticky = document.querySelector('nav');
            if (sticky.getBoundingClientRect().bottom > heading.getBoundingClientRect().top) return false;
            const range = document.createRange();
            range.selectNodeContents(heading);
            return range.getClientRects().length > 2 &&
                range.getBoundingClientRect().bottom <= summary.getBoundingClientRect().top;
        })()
        """) as? Bool
        guard separated == true else { throw NSError(domain:"WrappedTitleOverlapsSummary",code:1) }
        let watchObserver = Observer()
        view.navigationDelegate = watchObserver
        window.contentView = view
        view.loadHTMLString("""
        <!doctype html><title>Fixture song - YouTube</title>
        <meta property="og:image" content="https://example.invalid/youtube-logo.png">
        <style>
        body { margin:0 }
        #masthead-container { position:fixed; inset:0 0 auto; height:52px; background:#ddd }
        ytd-watch-flexy { display:flex; gap:16px; margin:68px 16px 0; align-items:flex-start }
        #primary { width:680px }
        #movie_player { width:680px; height:382px; border-radius:12px }
        #secondary { width:320px }
        ytd-playlist-panel-video-renderer { display:block; background:rgb(232,232,216) }
        .overlay { position:fixed; inset:0; background:white }
        </style>
        <div id="masthead-container"><nav>Fixture navigation</nav></div>
        <ytd-watch-flexy>
          <section id="primary">
            <div id="movie_player"><div class="overlay">Transient player overlay</div></div>
            <ytd-watch-metadata><h1>Fixture song</h1><p>Fixture video description</p></ytd-watch-metadata>
            <div class="overlay">Unrelated transient overlay</div>
          </section>
          <aside id="secondary">
            <ytd-playlist-panel-video-renderer selected>
              <span id="video-title">Fixture current playlist row</span>
            </ytd-playlist-panel-video-renderer>
            <p>Fixture related video</p>
          </aside>
        </ytd-watch-flexy>
        """,baseURL:nil)
        try await wait(watchObserver)
        let watchScript = js.replacingOccurrences(
            of: "const pageURL = new URL(location.href);",
            with: "const pageURL = new URL('https://www.youtube.com/watch?v=AgFeZr5ptV8&list=RDfixture');"
        ).replacingOccurrences(of: "queuePoster(poster,image,'src');", with: "")
        let watch = try await view.callAsyncJavaScript(watchScript + "\nreturn await capture('page');",arguments:[:],in:nil,contentWorld:.page) as? [String:Any]
        guard let watchHTML = watch?["html"] as? String, let watchText = watch?["text"] as? String,
              watchText.contains("Fixture song"), watchText.contains("Fixture video description"),
              !watchHTML.contains("Transient player overlay"), !watchHTML.contains("Unrelated transient overlay"),
              watchHTML.contains("data-ioant-media-src"), watchHTML.contains("youtube.com/watch?v=AgFeZr5ptV8"),
              !watchHTML.contains("youtube-logo.png"), watchText.contains("Fixture navigation"),
              watchText.contains("Fixture current playlist row"), watchText.contains("Fixture related video") else {
            throw NSError(domain:"WatchCapture",code:1)
        }
        let watchPreviewObserver = Observer()
        preview.navigationDelegate = watchPreviewObserver
        window.contentView = preview
        preview.loadHTMLString(Note.document(for: NotePart(html:watchHTML,text:watchText)),baseURL:nil)
        try await wait(watchPreviewObserver)
        let watchLayout = try await preview.evaluateJavaScript("""
        (() => {
            const bounds = selector => document.querySelector(selector).getBoundingClientRect();
            const player = bounds('[data-ioant-watch-player]');
            const title = bounds('h1');
            const sidebar = bounds('aside');
            const header = bounds('header');
            return Math.abs(player.width - 680) <= 2 && Math.abs(player.height - 382) <= 2 &&
                title.top >= player.bottom && sidebar.left >= player.right + 12 &&
                Math.abs(sidebar.top - player.top) <= 2 &&
                Math.abs(player.top - header.bottom - 16) <= 2;
        })()
        """) as? Bool
        guard watchLayout == true else { throw NSError(domain:"WatchGeometry",code:1) }
        print("PASS: watch capture retained the original header, player size, title, playlist and related column")
        let homeObserver = Observer()
        view.navigationDelegate = homeObserver
        window.contentView = view
        view.loadHTMLString("""
        <!doctype html><title>YouTube</title><style>
        body{margin:0}#masthead-container{position:fixed;inset:0 0 auto;height:56px;background:#eee}
        #guide-content{position:fixed;left:0;top:56px;width:200px;height:700px;background:#eee}
        ytd-browse{display:block;margin:68px 20px 0 216px}
        ytd-rich-grid-renderer{display:grid;grid-template-columns:repeat(2,260px);gap:16px}
        ytd-rich-item-renderer{display:block;min-height:500px;background:#eee}
        .overlay{position:fixed;inset:0;background:white}
        </style>
        <div id="masthead-container"><nav>Fixture home navigation</nav></div>
        <div id="guide-content">Fixture guide rail</div>
        <ytd-browse page-subtype="home">
          <h1>Fixture home feed</h1>
          <ytd-rich-grid-renderer>
            <ytd-rich-item-renderer><h2>Fixture first video</h2></ytd-rich-item-renderer>
            <ytd-rich-item-renderer><h2>Fixture second video</h2></ytd-rich-item-renderer>
            <ytd-rich-item-renderer><h2>Fixture below-fold video</h2></ytd-rich-item-renderer>
          </ytd-rich-grid-renderer>
          <div class="overlay">Transient home overlay</div>
        </ytd-browse>
        <div class="overlay">App-wide transient overlay</div>
        """,baseURL:nil)
        try await wait(homeObserver)
        let homeScript = js.replacingOccurrences(
            of: "const pageURL = new URL(location.href);",
            with: "const pageURL = new URL('https://www.youtube.com/');"
        )
        let home = try await view.callAsyncJavaScript(homeScript + "\nreturn await capture('page');",arguments:[:],in:nil,contentWorld:.page) as? [String:Any]
        guard let homeHTML = home?["html"] as? String, let homeText = home?["text"] as? String,
              homeText.contains("Fixture home navigation"), homeText.contains("Fixture guide rail"),
              homeText.contains("Fixture below-fold video"),
              !homeHTML.contains("Transient home overlay"), !homeHTML.contains("App-wide transient overlay") else {
            throw NSError(domain:"HomeCapture",code:1)
        }
        let homePreviewObserver = Observer()
        preview.navigationDelegate = homePreviewObserver
        window.contentView = preview
        preview.loadHTMLString(Note.document(for: NotePart(html:homeHTML,text:homeText)),baseURL:nil)
        try await wait(homePreviewObserver)
        let homeLayout = try await preview.evaluateJavaScript("""
        (() => {
            const header = document.querySelector('header').getBoundingClientRect();
            const rail = document.querySelector('aside').getBoundingClientRect();
            const feed = document.querySelector('main').getBoundingClientRect();
            const tiles = Array.from(document.querySelectorAll('h2'), node => node.getBoundingClientRect());
            return tiles.length === 3 && feed.top >= header.bottom && feed.left >= rail.right &&
                Math.abs(tiles[0].top - tiles[1].top) <= 2 && tiles[1].left > tiles[0].left &&
                tiles[2].top > tiles[0].top;
        })()
        """) as? Bool
        guard homeLayout == true else { throw NSError(domain:"HomeGeometry",code:1) }
        print("PASS: YouTube home preserved the navigation, side rail, and loaded feed grid")
        // Make a real local movie so validation covers fetching a whole asset,
        // opening it for metadata inspection, and serializing it for playback.
        window.contentView = view
        let movie = try await fixtureMovie()
        let savedMovie = try await view.callAsyncJavaScript(js + """
        ;const bytes = Uint8Array.from(atob(movie), character => character.charCodeAt(0));
        const url = URL.createObjectURL(new Blob([bytes],{type:'video/mp4'}));
        const video = document.createElement('video');
        video.style.cssText = 'display:block;width:240px;height:135px';
        video.preload = 'none';
        video.src = url;
        document.body.append(video);
        try {
            const result = await capture('page');
            return result.html.includes('data-ioant-media-file="data:video/mp4;base64,');
        } finally {
            video.remove();
            URL.revokeObjectURL(url);
        }
        """,arguments:["movie":movie.base64EncodedString()],in:nil,contentWorld:.page) as? Bool
        guard savedMovie == true else { throw NSError(domain:"PlayableVideoCapture",code:1) }
        print("PASS: whole-page capture embedded a complete MP4 after WebKit read its video metadata")
        print("PASS: WebKit source-to-production-reader layout, hidden labels, inert input, pseudo-elements and result text geometry")
    }

    private static func fixtureMovie() async throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain:"FixtureMovie",code:1) }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        guard let pool = adapter.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,pool,&pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw NSError(domain:"FixtureMovie",code:2) }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(bytes,128,CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        for index in 0..<3 {
            for _ in 0..<100 where !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard input.isReadyForMoreMediaData,
                  adapter.append(pixelBuffer,withPresentationTime: CMTime(value: Int64(index),timescale: 8)) else {
                throw writer.error ?? NSError(domain:"FixtureMovie",code:3)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? NSError(domain:"FixtureMovie",code:4) }
        return try Data(contentsOf: url)
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
