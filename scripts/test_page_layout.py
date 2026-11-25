import pathlib, subprocess, tempfile, html, re
root=pathlib.Path(__file__).resolve().parents[1]
chrome=pathlib.Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
js=(root/"BrowserExtension/CaptureEngine/injected.js").read_text()
fixture=r"""<!doctype html><meta charset=utf-8><style>
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden}body{background:#10151b;color:#eee;font:16px Arial}
.shell{height:100%;display:flex;flex-direction:column;gap:8px;padding:8px}
.top{height:48px;flex:none}.columns{display:grid;grid-template-columns:220px 1fr 200px;gap:8px;flex:1;min-height:0}
.panel{background:#232a33;border-radius:8px;overflow:auto;padding:12px;min-width:0}
.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
.card{background:#345369;min-height:100px;padding:12px}.row{display:flex;gap:10px;align-items:center}.badge{flex:none;width:70px}.description{flex:1;min-width:0}
.hero{height:90px;background-image:url('data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2210%22%20height%3D%2210%22%3E%3Crect%20width%3D%2210%22%20height%3D%2210%22%20fill%3D%22red%22%2F%3E%3C%2Fsvg%3E');background-size:cover}
</style><div class="shell"><div class="top">Top bar <button>Play</button></div><div class="columns"><aside class="panel">Library</aside><main class="panel"><div class="hero">Hero</div><div class="cards"><article class="card"><div class="row"><span class="badge">Badge</span><span class="description">First card description</span></div></article><article class="card">Second card</article></div><div style="height:950px">Scrollable content</div></main><aside class="panel">Player</aside></div></div><pre id="result" hidden></pre>"""
checks=r"""
(async()=>{try {
 const measure=e=>Math.round(e.getBoundingClientRect().width);
 const expected=[...document.querySelectorAll('.panel,.card,.description')].map(measure);
 const expectedHeight=document.querySelector('main').clientHeight;
 const data=await capture('page');
 const parsed=new DOMParser().parseFromString(data.html,'text/html');
 const snapshot=parsed.querySelector('[data-ioant-layout=page]');
 if(!snapshot || !data.text.includes('Library') || !data.text.includes('Player') || !data.text.includes('Scrollable content') || !snapshot.textContent.includes('Play'))throw new Error('missing page content');
 const frame=document.createElement('iframe');frame.style.cssText='position:fixed;left:0;top:0;width:1200px;height:900px;border:0';
 document.body.append(frame);
 frame.contentDocument.open();frame.contentDocument.write('<!doctype html><style>body{margin:16px}</style>'+data.html);frame.contentDocument.close();
 const d=frame.contentDocument;
 const found=[...d.querySelectorAll('aside,main,article')];
 const actual=found.slice(0,5).map(measure);
 const wanted=[expected[0],expected[1],expected[2],expected[4],expected[5]];
 // original order is panel, panel, card, description, card, panel.
 const ordered=[expected[0],expected[1],expected[2],expected[4],expected[5]];
 if(actual.length!==5 || actual.some((w,i)=>Math.abs(w-ordered[i])>3))throw new Error('layout width '+JSON.stringify({expected,actual,ordered}));
 const main=d.querySelector('main');
 if(Math.abs(main.clientHeight-expectedHeight)>4 || main.scrollHeight<=main.clientHeight)throw new Error('scroll box height '+main.clientHeight+' vs '+expectedHeight);
 if(![...d.querySelectorAll('div')].some(e=>e.style.backgroundImage.includes('data:image/svg+xml')))throw new Error('background lost');
 if(data.truncated)throw new Error('unexpected truncation');
 frame.remove(); document.getElementById('result').textContent='IOANT_PAGE_PASS';
} catch(e) {document.getElementById('result').textContent='IOANT_PAGE_FAIL '+e.message;}})();
"""
with tempfile.TemporaryDirectory(prefix="ioant-page-fixture-") as tmp:
 p=pathlib.Path(tmp); page=p/"fixture.html";page.write_text(fixture+"<script>"+js+"\n"+checks+"</script>")
 cmd=[str(chrome),"--headless","--disable-gpu","--no-first-run","--no-default-browser-check","--disable-background-networking","--disable-component-update","--user-data-dir="+str(p/"profile"),"--window-size=1200,900","--virtual-time-budget=5000","--dump-dom",page.as_uri()]
 result=subprocess.run(cmd,capture_output=True,text=True,timeout=35)
 marker=re.search(r'<pre id="result"[^>]*>(.*?)</pre>',result.stdout,re.S)
 actual=html.unescape(marker.group(1)) if marker else "missing fixture result"
 print("Chrome multi-column layout fixture:",actual[:700])
 if result.returncode or actual!="IOANT_PAGE_PASS": print(result.stderr[-1000:]);raise SystemExit(1)
