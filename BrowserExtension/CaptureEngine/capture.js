/* Source entry; build_capture_bundle.py embeds the isolated-world helpers. */
async function capture(mode) {
  /* @capture-modules */
  const selection = window.getSelection();
  const range = mode === 'selection' && selection && !selection.isCollapsed && selection.rangeCount ? selection.getRangeAt(0) : null;
  if (mode === 'selection' && !range) throw new Error('error_selection');
  if (!['page','selection','answer'].includes(mode)) throw new Error('error_mode');
  let source = document.body;
  if (range) {
    source = range.commonAncestorContainer;
    if (source.nodeType !== Node.ELEMENT_NODE) source = source.parentElement;
  } else if (mode === 'answer') {
    if (location.hostname !== 'chatgpt.com' && location.hostname !== 'chat.openai.com') throw new Error('error_answer_site');
    const answers = [...document.querySelectorAll('[data-message-author-role="assistant"]')].filter(e => e.getClientRects().length && e.textContent.trim());
    source = answers[answers.length - 1];
    if (!source) throw new Error('error_answer_missing');
  }
  if (!source) throw new Error('error_empty');
  const wholePage = mode === 'page';
  const skip = new Set('SCRIPT STYLE LINK META NOSCRIPT OBJECT EMBED INPUT TEXTAREA SELECT OPTION TEMPLATE HEAD FORM BUTTON'.split(' '));
  if (wholePage) { skip.delete('FORM'); skip.delete('BUTTON'); skip.delete('INPUT'); skip.delete('TEXTAREA'); skip.delete('SELECT'); }
  const allowed = new Set('A ABBR ARTICLE ASIDE B BLOCKQUOTE BR CAPTION CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE FOOTER H1 H2 H3 H4 H5 H6 HEADER HR I IMG KBD LI MAIN MARK NAV OL P PRE Q S SAMP SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TH THEAD TFOOT TR U UL VAR WBR MATH COL COLGROUP'.split(' '));
  const state={nodes:0,svgNodes:0,imageBytes:0,truncated:false,missing:0};
  const {root,stage}=createSurface(source,wholePage);
  const {attachData,snapshotImage,queueBackground,queuePoster,finish}=createAssets(state);
  const {applyStyles,isVisuallyClipped,appendPseudo}=createLayout({source,wholePage,stage,queueBackground});
  const {snapshotSVG}=createSVG(state,attachData);
  function recordMedia(node, tag, parent) {
    let kind = tag.toLowerCase();
    let url = node.currentSrc || node.getAttribute('src') || node.querySelector('source[src]')?.getAttribute('src');
    if (tag === 'IFRAME') {
      let host;
      try { host = new URL(url, document.baseURI).hostname; } catch { return; }
      if (/(^|\.)(youtube(?:-nocookie)?\.com|vimeo\.com|bilibili\.com|dailymotion\.com)$/i.test(host)) kind = 'video';
      else if (/(^|\.)(soundcloud\.com|spotify\.com|mixcloud\.com)$/i.test(host)) kind = 'audio';
      else return;
      url = location.href;
    }
    const marker = document.createElement('span');
    marker.hidden = true;
    marker.setAttribute('data-ioant-media', kind);
    marker.title = (node.getAttribute('aria-label') || node.title || '').slice(0, 500);
    if (url) {
      try {
        const source = new URL(url, document.baseURI);
        const web = ['https:', 'http:'].includes(source.protocol) && source.href.length <= 8192;
        const local = source.href.startsWith('data:' + kind + '/') && source.href.length <= 512 * 1024 &&
          state.imageBytes + source.href.length <= 12 * 1024 * 1024;
        if (web || local) {
          if (local) state.imageBytes += source.href.length;
          marker.setAttribute('data-ioant-media-src', source.href);
        }
      } catch { /* Use the captured page as the source. */ }
    }
    if (tag === 'VIDEO' && node.poster) queuePoster(node.poster, marker);
    parent.append(marker);
  }
  function visit(node, parent) {
    if (++state.nodes > 18000) { state.truncated = true; return; }
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
    // Audio without native controls has no layout box. It can still be
    // playable through the page's custom controls and belong in the index.
    const hasAudioSource = tag === 'AUDIO' &&
      (node.currentSrc || node.getAttribute('src') || node.querySelector('source[src]'));
    if (!hasAudioSource && isVisuallyClipped(node,cs)) return;
    if (['VIDEO', 'AUDIO', 'IFRAME'].includes(tag)) {
      recordMedia(node, tag, parent);
      return;
    }
    // Keep empty, inert geometry for visible controls rather than removing a
    // flex/grid item. Do not copy current field values (passwords, tokens,
    // personal inputs), form actions, names, or interactive behavior.
    if (wholePage && ['INPUT','TEXTAREA','SELECT'].includes(tag)) {
      if (tag === 'INPUT' && node.type === 'hidden') return;
      const dst = document.createElement('span');
      dst.setAttribute('data-ioant-control', tag.toLowerCase());
      applyStyles(node,dst,cs);
      if (cs.display === 'inline') dst.style.display = 'inline-block';
      const rect=node.getBoundingClientRect();
      dst.style.boxSizing='border-box';
      dst.style.width=Math.max(0,rect.width)+'px';
      dst.style.height=Math.max(0,rect.height)+'px';
      dst.style.overflow='hidden';
      dst.style.verticalAlign=cs.verticalAlign;
      // Placeholder is public page UI, never the typed value.
      if (tag !== 'SELECT' && node.type !== 'password') dst.textContent=node.placeholder || '';
      parent.append(dst);
      return;
    }
    if (tag === 'SVG' || tag === 'CANVAS') {
      const dst = document.createElement('img');
      applyStyles(node,dst,cs);
      if (tag === 'SVG') snapshotSVG(node,dst);
      else { try { attachData(dst,node.toDataURL('image/png')); dst.alt='Canvas graphic'; } catch { state.missing++; } }
      if (dst.hasAttribute('src')) parent.append(dst);
      return;
    }
    const dst = document.createElement(allowed.has(tag) ? tag.toLowerCase() : 'div');
    applyStyles(node,dst,cs);
    if (tag === 'IMG') {
      snapshotImage(node,dst);
      const original = node.currentSrc || node.src;
      if (/^https?:\/\//i.test(original) && original.length <= 8192) {
        dst.setAttribute('data-ioant-image-origin', original);
      }
    }
    if (tag === 'TD' || tag === 'TH') { dst.colSpan = node.colSpan; dst.rowSpan = node.rowSpan; }
    if (tag === 'OL' && node.start !== 1) dst.start = node.start;
    if (tag === 'A' && /^https?:\/\//i.test(node.href)) dst.setAttribute('data-source-href',node.href);
    if (tag === 'DETAILS') dst.open = wholePage ? node.open : true;
    parent.append(dst);
    if (wholePage && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::before');
    for (const child of node.childNodes) { if (state.nodes >= 18000) { state.truncated = true; break; } visit(child,dst); }
    if (wholePage && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::after');
  }
  function captureWatchPage() {
    const pageURL = new URL(location.href);
    const videoID = pageURL.searchParams.get('v');
    if (!wholePage || !['www.youtube.com','youtube.com','m.youtube.com'].includes(pageURL.hostname) ||
        pageURL.pathname !== '/watch' || !/^[\w-]{11}$/.test(videoID || '')) return false;

    // Watch pages use custom player layers and transient overlays. Keep the
    // watch content readable in a static document without cloning those layers.
    const meta = key => document.querySelector('meta[property="' + key + '"]')?.content?.trim();
    const visibleText = selector => {
      const element = document.querySelector(selector);
      return element?.getClientRects().length && element.innerText?.trim() || '';
    };
    const heading = visibleText('ytd-watch-metadata h1, #title h1') ||
      meta('og:title') || document.title.replace(/\s*-\s*YouTube\s*$/i,'').trim();
    if (!heading || heading === 'YouTube') throw new Error('error_empty');
    root.style.width = '100%';
    root.style.maxWidth = '1200px';
    root.style.color = root.style.colorScheme === 'dark' ? '#f1f1f1' : '#181818';
    stage.style.width = '100%';
    stage.style.minHeight = '0';

    const content = document.createElement('article');
    content.style.cssText = 'display:block;max-width:100%;overflow-wrap:anywhere;color:inherit;';
    const title = document.createElement('h1');
    title.style.cssText = 'display:block;margin:16px 0 8px;line-height:1.25;';
    title.textContent = heading.slice(0,500);
    const marker = document.createElement('span');
    marker.hidden = true;
    marker.title = title.textContent;
    marker.setAttribute('data-ioant-media','video');
    marker.setAttribute('data-ioant-media-src',pageURL.href);
    // The document's og:image can be the YouTube logo, especially after
    // client-side playlist navigation. Resolve the cover from the active URL.
    const poster = 'https://i.ytimg.com/vi/' + videoID + '/hqdefault.jpg';
    const image = document.createElement('img');
    image.alt = '';
    image.style.cssText = 'display:block;width:100%;max-width:760px;max-height:55vh;object-fit:contain;border-radius:12px;';
    image.setAttribute('data-ioant-image-origin',poster);
    content.append(title,image,marker);
    queuePoster(poster,image,'src');
    for (const text of [
      visibleText('#owner ytd-channel-name, ytm-slim-owner-renderer'),
      visibleText('ytd-watch-metadata #description-inline-expander, #description-inline-expander') || meta('og:description')
    ]) {
      if (!text) continue;
      const paragraph = document.createElement('p');
      paragraph.style.cssText = 'display:block;white-space:pre-wrap;margin:8px 0;';
      paragraph.textContent = text.slice(0,8000);
      content.append(paragraph);
    }
    const playlist = document.querySelector('ytd-playlist-panel-renderer, ytm-playlist-panel-renderer');
    const rows = Array.from(playlist?.querySelectorAll('ytd-playlist-panel-video-renderer, ytm-playlist-panel-video-renderer') || [])
      .slice(0,80)
      .map(row => ({
        title: row.querySelector('#video-title, .ytm-playlist-panel-video-renderer-title')?.textContent?.trim(),
        current: row.hasAttribute('selected') || row.getAttribute('aria-current') === 'true'
      }))
      .filter(row => row.title);
    if (rows.length) {
      const columns = document.createElement('div');
      columns.style.cssText = 'display:flex;flex-wrap:wrap;align-items:flex-start;gap:24px;';
      content.style.cssText += 'flex:2 1 520px;min-width:0;';
      const aside = document.createElement('aside');
      aside.style.cssText = 'display:block;flex:1 1 280px;min-width:0;overflow-wrap:anywhere;';
      const name = document.createElement('h2');
      name.textContent = playlist.querySelector('#header-description h3, #playlist-title, .title')?.textContent?.trim() || '';
      if (name.textContent) aside.append(name);
      const list = document.createElement('ol');
      list.style.cssText = 'display:block;margin:16px 0;padding-inline-start:2em;';
      for (const row of rows) {
        const item = document.createElement('li');
        item.style.cssText = 'display:list-item;margin-block:8px;';
        item.textContent = row.title.slice(0,500);
        if (row.current) item.style.fontWeight = 'bold';
        list.append(item);
      }
      aside.append(list);
      columns.append(content,aside);
      stage.append(columns);
    } else {
      stage.append(content);
    }
    return true;
  }
  if (!captureWatchPage()) visit(source,stage);
  await finish();
  const html = root.outerHTML;
  // innerText of the attached original is not used for selections: it could include text outside the selection.
  // Whole page text comes from the captured, filtered structure, not the
  // original innerText (which may contain clipped accessibility labels).
  function capturedText(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    if (node.hasAttribute('data-ioant-control') || node.hasAttribute('data-ioant-media')) return '';
    const value = Array.from(node.childNodes,capturedText).join('');
    const block = /^(block|flex|grid|table|list-item|flow-root)/.test(node.style.display);
    return block || node.tagName === 'BR' ? '\n'+value+'\n' : value;
  }
  const text = (range ? range.toString() : wholePage ? capturedText(root).replace(/\n{3,}/g,'\n\n').trim() : source.innerText || root.textContent).slice(0,2_000_000);
  if (!text.trim() && !root.querySelector('img[src], [data-ioant-media]')) throw new Error('error_empty');
  const title = mode === 'answer' ? (text.split(/\n/).find(s=>s.trim()) || 'ChatGPT answer').trim().slice(0,100) : document.title || 'Web capture';
  const result = {version:1,title,sourceURL:location.href,mode,html,text,truncated:state.truncated || state.missing>0};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32*1024*1024) throw new Error('error_large');
  return result;
}
