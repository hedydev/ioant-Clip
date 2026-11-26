import pathlib, subprocess, tempfile, html, re, os
root=pathlib.Path(__file__).resolve().parents[1]
chrome=pathlib.Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
if not chrome.is_file():
    raise SystemExit("Chrome not installed; capture browser test blocked")
fixture=r"""<!doctype html><meta charset=utf-8><style>
body {background:#fafafa;color:#141414;font:16px Arial}
main {width:760px} table {width:100%;border-collapse:collapse} td {border-bottom:1px solid #ddd;padding:8px}
.track {width:100%;height:8px;background:#eee;border-radius:4px;position:relative;overflow:hidden}
.fill {width:75%;height:8px;background:#12a34a;border-radius:4px}
</style><main id="target"><h1>Fixture title</h1><table><tr><td>Core</td><td>90%</td></tr></table>
<div class="track"><div class="fill"></div></div>
<svg width="500" height="150" viewBox="0 0 500 150" xmlns="http://www.w3.org/2000/svg"><defs><marker id="a" markerWidth="5" markerHeight="5" refX="4" refY="2" orient="auto"><path d="M0 0 L5 2 L0 4 Z" fill="#f80"/></marker></defs><rect x="1" y="1" width="180" height="70" rx="8" fill="#ddd" stroke="blue"/><text x="20" y="40" fill="black">Host</text><line x1="180" y1="35" x2="350" y2="35" stroke="#f80" marker-end="url(#a)"/></svg>
<img id="vector-image" alt="source vector" src="data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2220%22%20height%3D%2210%22%3E%3Crect%20width%3D%2220%22%20height%3D%2210%22%20fill%3D%22red%22%2F%3E%3C%2Fsvg%3E"><pre>const x = 1;</pre></main><pre id="result"></pre>"""
js=(root/"BrowserExtension/CaptureEngine/injected.js").read_text()
checks=r"""
(async()=>{try {
 const range=document.createRange();range.selectNodeContents(document.getElementById('target'));
 const sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);
 const data=await capture('selection'); const parsed=new DOMParser().parseFromString(data.html,'text/html');
 const svg=parsed.querySelector('img[src^="data:image/svg+xml"]');
 const xml=svg && decodeURIComponent(svg.getAttribute('src').split(',').slice(1).join(','));
 const vectorImage=parsed.querySelector('img[alt="source vector"]');
 const frame=parsed.querySelector('[data-ioant-frame="1"]');
 if(!vectorImage?.getAttribute('src')?.startsWith('data:image/svg+xml') || !frame || frame.style.borderRadius!=='16px' || !frame.style.padding || frame.style.backgroundColor!=='rgb(250, 250, 250)') throw new Error('Vector image or source-colored frame missing');
 const fill=[...parsed.querySelectorAll('div')].find(e=>e.style.backgroundColor==='rgb(18, 163, 74)');
 if(!svg || !xml.includes('Host') || !xml.includes('marker-end') || !fill || Math.abs(parseFloat(fill.style.width)-75)>1 || fill.style.height!=='8px' || !parsed.querySelector('table td') || !parsed.querySelector('pre') || !data.text.includes('Fixture title') || data.truncated) throw new Error('svg=' + !!svg + ' marker=' + (xml&&xml.includes('marker-end')) + ' fill=' + (fill&&fill.style.cssText) + ' truncated='+data.truncated);
 document.querySelector('#target').hidden = true;
 const thread = document.createElement('main');
 thread.innerHTML = '<article data-testid="conversation-turn-1" data-turn="assistant"><div class="markdown"><table><tr><td>Mounted turn content</td></tr></table></div><button>Copy toolbar control</button></article><nav><p>Sidebar content</p></nav>';
 document.body.append(thread);
 const script = capture.toString().replace('const conversationURL = new URL(location.href);',
     "const conversationURL = new URL('https://chatgpt.com/g/project/c/fixture');");
 // The injected function is serialized without its caller's lexical scope.
 const injected = Function('return (' + script + ')')();
 const wrapped = await injected('page',{returnOutcome:true});
 if (!wrapped.capture?.text.includes('Mounted turn content') || wrapped.capture?.text.includes('Copy toolbar control') ||
     wrapped.capture?.text.includes('Sidebar content') || !wrapped.capture?.html.includes('data-ioant-conversation')) {
    throw new Error('Conversation with wrappers but no author labels failed');
 }
 thread.innerHTML = '<section><h2>Article heading</h2><table><tr><td>Main document fallback</td></tr></table></section>';
 const fallback = await injected('page',{returnOutcome:true});
 if (!fallback.capture?.text.includes('Main document fallback')) throw new Error('Main document fallback failed');
 thread.replaceChildren();
 const empty = await injected('page',{returnOutcome:true});
 if (empty.error !== 'error_empty') throw new Error('Empty error lost through capture boundary');
 document.getElementById('result').textContent='IOANT_CAPTURE_PASS';
} catch(e) {document.getElementById('result').textContent='IOANT_CAPTURE_FAIL '+e.message;}})();
"""
with tempfile.TemporaryDirectory(prefix="ioant-chrome-fixture-") as tmp:
    p=pathlib.Path(tmp); page=p/"fixture.html"; page.write_text(fixture+"<script>"+js+"\n"+checks+"</script>")
    cmd=[str(chrome),"--headless","--disable-gpu","--no-first-run","--no-default-browser-check","--disable-background-networking","--disable-component-update","--user-data-dir="+str(p/"profile"),"--window-size=1100,900","--virtual-time-budget=5000","--dump-dom",page.as_uri()]
    result=subprocess.run(cmd,capture_output=True,text=True,timeout=35)
    marker=re.search(r'<pre id="result">(.*?)</pre>',result.stdout,re.S)
    actual=html.unescape(marker.group(1)) if marker else "missing fixture result"
    print("Chrome computed-style fixture:",actual[:500])
    if result.returncode or actual!="IOANT_CAPTURE_PASS":
        print(result.stderr[-1000:])
        raise SystemExit(1)
