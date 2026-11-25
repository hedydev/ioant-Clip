/* Self-contained function executed in the active tab's isolated world. */
async function capture(mode) {
  const selection = window.getSelection();
  const range = mode === 'selection' && selection && !selection.isCollapsed && selection.rangeCount ? selection.getRangeAt(0) : null;
  if (mode === 'selection' && !range) throw new Error('Select some page content first.');
  if (!['page','selection','answer'].includes(mode)) throw new Error('Unsupported capture mode.');
  let source = document.body;
  if (range) {
    source = range.commonAncestorContainer;
    if (source.nodeType !== Node.ELEMENT_NODE) source = source.parentElement;
  } else if (mode === 'answer') {
    if (location.hostname !== 'chatgpt.com' && location.hostname !== 'chat.openai.com') throw new Error('Latest answer is available on ChatGPT only.');
    const answers = [...document.querySelectorAll('[data-message-author-role="assistant"]')].filter(e => e.getClientRects().length && e.textContent.trim());
    source = answers[answers.length - 1];
    if (!source) throw new Error('No loaded assistant answer found. Try selecting the content instead.');
  }
  if (!source) throw new Error('No capturable content.');
  const wholePage = mode === 'page';
  const skip = new Set('SCRIPT STYLE LINK META NOSCRIPT IFRAME OBJECT EMBED INPUT TEXTAREA SELECT OPTION VIDEO AUDIO TEMPLATE HEAD FORM BUTTON'.split(' '));
  if (wholePage) { skip.delete('FORM'); skip.delete('BUTTON'); }
  const allowed = new Set('A ABBR ARTICLE ASIDE B BLOCKQUOTE BR CAPTION CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE FOOTER H1 H2 H3 H4 H5 H6 HEADER HR I IMG KBD LI MAIN MARK NAV OL P PRE Q S SAMP SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TH THEAD TFOOT TR U UL VAR WBR MATH'.split(' '));
  const css = 'display box-sizing color background-color background-image font-family font-size font-weight font-style font-variant-numeric line-height letter-spacing text-align text-decoration white-space overflow-wrap word-break list-style-type padding-top padding-right padding-bottom padding-left margin-top margin-right margin-bottom margin-left border-top border-right border-bottom border-left border-radius box-shadow opacity flex flex-direction flex-wrap flex-grow flex-shrink flex-basis justify-content align-items align-self gap row-gap column-gap grid-template-columns grid-template-rows grid-column grid-row vertical-align min-width max-width min-height max-height border-collapse border-spacing table-layout overflow-x overflow-y position top right bottom left transform transform-origin text-indent width height z-index object-fit object-position background-size background-position background-repeat background-origin background-clip box-decoration-break align-content justify-items justify-self grid-auto-flow grid-auto-columns grid-auto-rows order text-overflow direction aspect-ratio float clear overflow-wrap clip-path'.split(' ');
  const svgTags = new Set('svg g defs rect circle ellipse line polyline polygon path text tspan textPath title desc marker linearGradient radialGradient stop clipPath mask pattern symbol use'.split(' '));
  const svgAttrs = new Set('id viewBox preserveAspectRatio x y x1 y1 x2 y2 cx cy r rx ry width height d points dx dy rotate textLength lengthAdjust transform gradientUnits gradientTransform spreadMethod offset markerWidth markerHeight refX refY orient markerUnits patternUnits patternContentUnits patternTransform clipPathUnits maskUnits maskContentUnits'.split(' '));
  const paint = 'fill fill-opacity fill-rule stroke stroke-width stroke-opacity stroke-dasharray stroke-dashoffset stroke-linecap stroke-linejoin stroke-miterlimit clip-rule clip-path mask marker-start marker-mid marker-end opacity color font-family font-size font-weight font-style letter-spacing text-anchor dominant-baseline alignment-baseline vector-effect stop-color stop-opacity paint-order'.split(' ');
  const ns = 'http://www.w3.org/2000/svg';
  const maxImage = 12 * 1024 * 1024;
  const pendingImages = [];
  const deadline = Date.now() + 15000;
  const assetCache = new Map();
  let nodes = 0, svgNodes = 0, imageBytes = 0, truncated = false, missing = 0;
  const root = document.createElement('div');
  root.setAttribute('data-ioant-snapshot','1');
  root.setAttribute('data-ioant-frame','1');
  const sourceCSS = getComputedStyle(source);
  const sourceWidth = Math.ceil(source.getBoundingClientRect().width);
  root.style.cssText = 'box-sizing:border-box;margin:0 auto;max-width:100%;min-width:0;padding:clamp(14px,3vw,24px);border:1px solid rgba(128,128,128,.25);border-radius:16px;';
  root.style.width = (Math.max(1, Math.min(sourceWidth || 768, wholePage ? 8192 : 1800)) + 50) + 'px';
  if (wholePage) {
    root.setAttribute('data-ioant-layout','page');
    root.style.width = (Math.max(1,Math.min(document.documentElement.clientWidth || sourceWidth,8192)) + 50) + 'px';
    root.style.maxWidth = 'none';
    root.style.overflow = 'hidden';
  }
  const stage = wholePage ? document.createElement('div') : root;
  if (wholePage) {
    stage.style.cssText = 'position:relative;transform:translateZ(0);box-sizing:border-box;isolation:isolate;overflow:visible;';
    stage.style.width = Math.max(1,Math.min(document.documentElement.clientWidth || sourceWidth,8192)) + 'px';
    stage.style.minHeight = Math.max(1,document.documentElement.clientHeight) + 'px';
    root.append(stage);
  }
  root.style.color = sourceCSS.color;
  root.style.fontFamily = sourceCSS.fontFamily;
  root.style.fontSize = sourceCSS.fontSize;
  root.style.lineHeight = sourceCSS.lineHeight;
  let background = 'rgb(255, 255, 255)';
  for (let p = source; p; p = p.parentElement) {
    const c = getComputedStyle(p).backgroundColor;
    if (c && c !== 'transparent' && c !== 'rgba(0, 0, 0, 0)') { background = c; break; }
  }
  root.style.backgroundColor = background;
  // Keep the captured surface readable independently of the reader's system theme.
  const channels = background.match(/[\d.]+/g)?.slice(0,3).map(Number);
  root.style.colorScheme = channels?.length === 3 && (channels[0]*.2126 + channels[1]*.7152 + channels[2]*.0722) < 128 ? 'dark' : 'light';
  function safeCSS(value, localSVG = false) {
    if (!value || /(?:expression\s*\(|-moz-binding|javascript:)/i.test(value)) return false;
    if (!/url\s*\(/i.test(value)) return true;
    return localSVG && /^url\(["']?#[\w:.-]+["']?\)$/.test(value.trim());
  }
  function applyStyles(src, dst, cs) {
    for (const prop of css) {
      const value = cs.getPropertyValue(prop);
      if (safeCSS(value)) dst.style.setProperty(prop,value);
    }
    const rect = src.getBoundingClientRect();
    const tag = src.tagName;
    const tablePart = ['TR','TD','TH','THEAD','TBODY','TFOOT','COL','COLGROUP'].includes(tag);
    if (wholePage) {
      // A page is captured at its original CSS viewport, not reflowed into
      // an arbitrary note width. Preserve computed used sizes and scroll boxes.
      if (src === source) {
        dst.style.width = cs.width === 'auto' ? stage.style.width : cs.width;
        dst.style.minHeight = cs.minHeight;
        dst.style.height = cs.height;
        dst.style.position = 'relative';
      }
      if (cs.position === 'fixed') dst.style.position = 'absolute';
      if (cs.position === 'sticky') dst.style.position = 'relative';
      if (cs.display === 'contents') { dst.style.width = 'auto'; dst.style.height = 'auto'; }
    } else {
      // Grid child percentages refer to the grid TRACK, not the grid itself.
      // Flex children also have their own sizing algorithm. Do not apply a
      // measured parent percentage to either kind of item.
      const parent = src.parentElement;
      const parentStyle = parent && getComputedStyle(parent);
      const isGrid = parentStyle && /grid/.test(parentStyle.display);
      const isFlex = parentStyle && /flex/.test(parentStyle.display);
      if (!tablePart && cs.display !== 'inline' && cs.display !== 'contents' && rect.width > 0) {
        const pr = parent?.getBoundingClientRect();
        if (isGrid) {
          dst.style.width = 'auto'; dst.style.minWidth = '0'; dst.style.maxWidth = '100%';
        } else if (isFlex) {
          dst.style.width = cs.width;
          dst.style.minWidth = '0';
          dst.style.maxWidth = '100%';
        } else if (pr && pr.width > 0 && rect.width <= pr.width + 1) {
          dst.style.width = (100 * rect.width / pr.width).toFixed(3) + '%';
          dst.style.boxSizing = 'border-box'; dst.style.maxWidth = '100%'; dst.style.minWidth = '0';
        } else if (src !== source) {
          dst.style.width = Math.ceil(rect.width) + 'px'; dst.style.maxWidth = '100%';
        }
        if (!(src.childNodes.length === 0 || cs.position === 'absolute' || cs.position === 'relative' && /hidden|clip/.test(cs.overflow))) dst.style.height = 'auto';
      }
      if (cs.position === 'fixed' || cs.position === 'sticky') {
        dst.style.position = 'static'; dst.style.inset = 'auto';
      }
      if (src === source) {
        dst.style.width = '100%'; dst.style.minWidth = '0'; dst.style.maxWidth = '100%';
        dst.style.height = 'auto'; dst.style.maxHeight = 'none'; dst.style.overflow = 'visible';
        dst.style.margin = '0'; dst.style.position = 'static'; dst.style.transform = 'none';
      }
      if (tag === 'TABLE') { dst.style.width = '100%'; dst.style.maxWidth = '100%'; }
      if (tag === 'IMG') { dst.style.maxWidth = '100%'; dst.style.height = 'auto'; }
    }
    if (/url\s*\(/i.test(cs.backgroundImage)) {
      const value = cs.backgroundImage;
      pendingImages.push(async () => {
        // Preserve gradient layers and replace only accessible image URL layers.
        const matches = [...value.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/gi)];
        let result = value;
        for (const m of matches) {
          const encoded = await assetData(m[1] ?? m[2] ?? m[3]);
          if (!encoded || imageBytes + encoded.length > maxImage) { missing++; result = result.replace(m[0],'none'); }
          else { imageBytes += encoded.length; result = result.replace(m[0],'url("' + encoded + '")'); }
        }
        dst.style.backgroundImage = result;
      });
    }
  }
  async function assetData(raw) {
    let url;
    try { url = new URL(raw,location.href); } catch { return null; }
    if (!['data:','blob:','http:','https:'].includes(url.protocol)) return null;
    if (assetCache.has(url.href)) return assetCache.get(url.href);
    const task = (async () => {
      if (Date.now() >= deadline) return null;
      const controller = new AbortController();
      const timer = setTimeout(()=>controller.abort(), Math.min(2500,Math.max(1,deadline-Date.now())));
      try {
        // No broad host permissions, no cross-origin credentials, no uploads.
        const response = await fetch(url.href,{signal:controller.signal,credentials:'omit',referrerPolicy:'no-referrer'});
        if (!response.ok) return null;
        const blob = await response.blob();
        if (!blob.size || blob.size > maxImage) return null;
        const mime = blob.type.toLowerCase().split(';')[0];
        if (!['image/png','image/jpeg','image/gif','image/webp','image/avif','image/svg+xml'].includes(mime)) return null;
        if (mime === 'image/svg+xml') {
          const xml = await blob.text();
          if (/<!DOCTYPE|<!ENTITY/i.test(xml)) return null;
          const doc = new DOMParser().parseFromString(xml,'image/svg+xml');
          const svg = doc.documentElement;
          if (svg.localName !== 'svg' || svg.namespaceURI !== ns || doc.querySelector('parsererror')) return null;
          for (const el of svg.querySelectorAll('script,foreignObject,iframe,object,embed,animate,animateMotion,animateTransform,set')) el.remove();
          for (const el of [svg,...svg.querySelectorAll('*')]) {
            for (const attr of [...el.attributes]) {
              const name=attr.localName.toLowerCase();
              if (name.startsWith('on') || name==='base' || (['href','src'].includes(name) && !/^#[\w:.-]+$/.test(attr.value)) || (/url\s*\(/i.test(attr.value) && !safeCSS(attr.value,true))) el.removeAttributeNode(attr);
            }
            if (el.localName==='style' && /@import|url\s*\(/i.test(el.textContent)) el.remove();
          }
          return 'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(new XMLSerializer().serializeToString(svg));
        }
        return await new Promise((resolve,reject)=>{
          const reader=new FileReader(); reader.onload=()=>resolve(reader.result); reader.onerror=reject; reader.readAsDataURL(blob);
        });
      } catch { return null; } finally { clearTimeout(timer); }
    })();
    assetCache.set(url.href,task);
    return task;
  }
  function attachData(dst, data) {
    if (imageBytes + data.length > maxImage) { truncated = true; missing++; return false; }
    imageBytes += data.length; dst.src = data; return true;
  }
  function snapshotImage(src, dst) {
    dst.alt = src.alt || '[Image unavailable offline]';
    dst.style.imageRendering = 'auto';
    const url = src.currentSrc || src.src || '';
    // Preserve original encoded bytes when available locally. In particular,
    // SVG wrapped in an HTML img must not be flattened through canvas.
    async function preserveLocal() {
      const data=await assetData(url);
      if (typeof data !== 'string' || imageBytes + data.length > maxImage) return false;
      return attachData(dst,data);
    }
    function rasterFallback() {
      try {
        if (!src.complete || !src.naturalWidth || !src.naturalHeight) { missing++; return; }
        const r = src.getBoundingClientRect();
        const ratio = Math.min(3,Math.max(2,window.devicePixelRatio || 1));
        const target = Math.max(src.naturalWidth,src.naturalHeight,r.width*ratio,r.height*ratio);
        // For SVG loaded as img, a high-DPI canvas fallback is sharper.
        // For ordinary raster sources never upscale beyond original pixels.
        const vectorHint = /(?:\.svg(?:[?#]|$)|^data:image\/svg\+xml)/i.test(url);
        const scale = Math.min(4096/Math.max(src.naturalWidth,src.naturalHeight),vectorHint ? target/Math.max(src.naturalWidth,src.naturalHeight) : 1);
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(src.naturalWidth * scale));
        canvas.height = Math.max(1, Math.round(src.naturalHeight * scale));
        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(src, 0, 0, canvas.width, canvas.height);
        attachData(dst, canvas.toDataURL('image/png'));
      } catch { missing++; }
    }
    pendingImages.push(async () => { if (!await preserveLocal()) rasterFallback(); });
  }
  function snapshotSVG(src, dst) {
    // Recreate a restricted SVG tree instead of copying arbitrary active markup.
    // SVG is loaded as an isolated image; no event handlers, script, HTML or external URLs.
    function clone(node) {
      if (++svgNodes > 12000) { truncated = true; return null; }
      if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.nodeValue || '');
      if (node.nodeType !== Node.ELEMENT_NODE || !svgTags.has(node.localName)) return null;
      const out = document.createElementNS(ns,node.localName);
      for (const attr of node.attributes) {
        if (svgAttrs.has(attr.name) && !/url\s*\(/i.test(attr.value)) out.setAttribute(attr.name, attr.value);
        if ((attr.name === 'href' || attr.name === 'xlink:href') && /^#[\w:.-]+$/.test(attr.value)) out.setAttribute('href',attr.value);
      }
      const computed = getComputedStyle(node);
      for (const prop of paint) {
        let value = computed.getPropertyValue(prop);
        // Chromium expands same-document marker URLs into absolute URLs.
        // Only convert a reference to this very document back into a local ID.
        const url = value.match(/^url\(["']?(.+?)["']?\)$/);
        if (url && !url[1].startsWith('#')) {
          try {
            const u = new URL(url[1],location.href), current = new URL(location.href);
            if (u.origin === current.origin && u.pathname === current.pathname && u.search === current.search && /^#[\w:.-]+$/.test(u.hash)) value = 'url(' + u.hash + ')';
          } catch {}
        }
        if (safeCSS(value,true)) out.style.setProperty(prop,value);
      }
      for (const child of node.childNodes) { const copy = clone(child); if (copy) out.append(copy); }
      return out;
    }
    const svg = clone(src);
    if (!svg) { missing++; return; }
    const r = src.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return;
    svg.setAttribute('width', String(Math.ceil(r.width)));
    svg.setAttribute('height', String(Math.ceil(r.height)));
    if (!svg.hasAttribute('viewBox')) svg.setAttribute('viewBox','0 0 '+r.width+' '+r.height);
    const xml = new XMLSerializer().serializeToString(svg);
    dst.alt = src.getAttribute('aria-label') || svg.querySelector('title')?.textContent || 'Diagram';
    dst.style.width = Math.ceil(r.width) + 'px';
    dst.style.maxWidth = '100%'; dst.style.height = 'auto';
    attachData(dst,'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(xml));
  }
  function visit(node, parent) {
    if (++nodes > 18000) { truncated = true; return; }
    if (range && !range.intersectsNode(node)) return;
    if (node.nodeType === Node.TEXT_NODE) {
      let value = node.nodeValue || '';
      if (range) value = value.slice(node === range.startContainer ? range.startOffset : 0, node === range.endContainer ? range.endOffset : value.length);
      parent.append(document.createTextNode(value)); return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    const tag = node.tagName.toUpperCase();
    if (skip.has(tag) || node.isContentEditable || node.hidden || !wholePage && node.getAttribute('aria-hidden') === 'true' && tag !== 'SVG') return;
    const cs = getComputedStyle(node);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') return;
    if (tag === 'SVG' || tag === 'CANVAS') {
      const dst = document.createElement('img');
      applyStyles(node,dst,cs);
      if (tag === 'SVG') snapshotSVG(node,dst);
      else { try { attachData(dst,node.toDataURL('image/png')); dst.alt='Canvas graphic'; } catch { missing++; } }
      if (dst.hasAttribute('src')) parent.append(dst);
      return;
    }
    const dst = document.createElement(allowed.has(tag) ? tag.toLowerCase() : 'div');
    applyStyles(node,dst,cs);
    if (tag === 'IMG') snapshotImage(node,dst);
    if (tag === 'TD' || tag === 'TH') { dst.colSpan = node.colSpan; dst.rowSpan = node.rowSpan; }
    if (tag === 'OL' && node.start !== 1) dst.start = node.start;
    if (tag === 'A' && /^https?:\/\//i.test(node.href)) dst.setAttribute('data-source-href',node.href);
    if (tag === 'DETAILS') dst.open = true;
    parent.append(dst);
    for (const child of node.childNodes) { if (nodes >= 18000) { truncated = true; break; } visit(child,dst); }
  }
  visit(source,stage);
  // Four bounded asset workers; fetches are deduplicated and time-limited.
  let cursor=0;
  await Promise.all(Array.from({length:Math.min(4,pendingImages.length)},async()=>{
    while(cursor<pendingImages.length) { const i=cursor++; await pendingImages[i](); }
  }));
  const html = root.outerHTML;
  // innerText of the attached original is not used for selections: it could include text outside the selection.
  const text = (range ? range.toString() : source.innerText || root.textContent).slice(0,2_000_000);
  if (!text.trim() && !root.querySelector('img[src]')) throw new Error('No capturable content.');
  const title = mode === 'answer' ? (text.split(/\n/).find(s=>s.trim()) || 'ChatGPT answer').trim().slice(0,100) : document.title || 'Web capture';
  const result = {version:1,title,sourceURL:location.href,mode,html,text,truncated:truncated || missing>0};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32*1024*1024) throw new Error('Capture too large. Try a smaller selection.');
  return result;
}
