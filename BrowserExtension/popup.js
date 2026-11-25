/* Executed in the active tab's isolated world, only after an explicit click. */
function capture(mode) {
  const selection = window.getSelection();
  if (mode === 'selection' && (!selection || selection.isCollapsed || !selection.rangeCount)) throw new Error('Select some page content first.');
  const range = mode === 'selection' ? selection.getRangeAt(0) : null;
  const skip = new Set(['SCRIPT','STYLE','LINK','META','NOSCRIPT','IFRAME','OBJECT','EMBED','INPUT','TEXTAREA','SELECT','OPTION','VIDEO','AUDIO','CANVAS','SVG','TEMPLATE','HEAD']);
  const allowed = new Set('A ABBR ARTICLE ASIDE B BLOCKQUOTE BR CAPTION CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE FOOTER H1 H2 H3 H4 H5 H6 HEADER HR I IMG KBD LI MAIN MARK NAV OL P PRE Q S SAMP SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TH THEAD TFOOT TR U UL VAR WBR'.split(' '));
  const props = 'display color background-color font-family font-size font-weight font-style line-height letter-spacing text-align text-decoration white-space overflow-wrap word-break list-style-type padding-top padding-right padding-bottom padding-left margin-top margin-right margin-bottom margin-left border-top border-right border-bottom border-left border-radius box-shadow opacity flex-direction flex-wrap justify-content align-items gap grid-template-columns vertical-align max-width'.split(' ');
  const limit = 18000; let count = 0, truncated = false, imageBytes = 0;
  const root = document.createElement('div');
  function styles(src, dst, cs) {
    for (const property of props) {
      const value = cs.getPropertyValue(property);
      if (value && !/url\s*\(/i.test(value)) dst.style.setProperty(property, value);
    }
    if (src.tagName === 'IMG') { dst.style.maxWidth = '100%'; dst.style.height = 'auto'; }
  }
  function snapshotImage(src, dst) {
    dst.alt = src.alt || '[Image unavailable offline]';
    try {
      if (!src.complete || !src.naturalWidth || !src.naturalHeight) return;
      const scale = Math.min(1, 1600 / Math.max(src.naturalWidth, src.naturalHeight));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(src.naturalWidth * scale)); canvas.height = Math.max(1, Math.round(src.naturalHeight * scale));
      canvas.getContext('2d').drawImage(src, 0, 0, canvas.width, canvas.height);
      const data = canvas.toDataURL('image/png');
      if (imageBytes + data.length <= 8 * 1024 * 1024) { dst.src = data; imageBytes += data.length; }
      else truncated = true;
    } catch { /* Cross-origin images are not fetched; retain alt text. */ }
  }
  function visit(node, parent) {
    if (count++ >= limit) { truncated = true; return; }
    if (range && !range.intersectsNode(node)) return;
    if (node.nodeType === Node.TEXT_NODE) {
      let value = node.nodeValue || '';
      if (range) value = value.slice(node === range.startContainer ? range.startOffset : 0, node === range.endContainer ? range.endOffset : value.length);
      parent.append(document.createTextNode(value)); return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    if (skip.has(node.tagName) || node.isContentEditable || node.hidden) return;
    const cs = getComputedStyle(node);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') return;
    const dst = document.createElement(allowed.has(node.tagName) ? node.tagName.toLowerCase() : 'div');
    styles(node, dst, cs);
    if (node.tagName === 'IMG') snapshotImage(node, dst);
    if (node.tagName === 'TD' || node.tagName === 'TH') { dst.colSpan = node.colSpan; dst.rowSpan = node.rowSpan; }
    if (node.tagName === 'A') { const url = node.href; if (/^https?:\/\//i.test(url)) dst.setAttribute('data-source-href', url); }
    if (node.tagName === 'DETAILS') dst.open = true;
    parent.append(dst);
    for (const child of node.childNodes) { if (count >= limit) { truncated = true; break; } visit(child, dst); }
  }
  if (!document.body) throw new Error('This page has no capturable body.');
  visit(document.body, root);
  const html = root.innerHTML;
  // Derive plain text from the sanitized snapshot, never from form fields.
  const text = root.textContent.slice(0, 2_000_000);
  if (!html.trim() || (!text.trim() && !root.querySelector('img[src]'))) throw new Error('No capturable content.');
  const result = {version:1,title:document.title || 'Web capture',sourceURL:location.href,mode,html,text,truncated};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32 * 1024 * 1024) throw new Error('Capture too large. Try a smaller selection.');
  return result;
}
if (typeof document !== 'undefined') {
  const status = document.querySelector('#status');
  const buttons = Array.from(document.querySelectorAll('button'));
  async function save(mode) {
    buttons.forEach(b => b.disabled = true); status.textContent = 'Capturing…';
    try {
      const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
      if (!tab?.id) throw new Error('No active tab.');
      const [response] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:capture,args:[mode]});
      if (!response?.result) throw new Error(response?.error || 'Unable to capture this page.');
      const data = response.result;
      const url = URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json'}));
      const a = document.createElement('a'); a.href = url;
      a.download = (data.title.replace(/[\\/:*?"<>|]/g,'_').slice(0,70) || 'web-capture') + '.ioantnote.json';
      a.click(); setTimeout(() => URL.revokeObjectURL(url), 30000);
      let copyStatus = '';
      if (document.querySelector('#copy').checked) {
        try { await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([data.html],{type:'text/html'}),'text/plain':new Blob([data.text],{type:'text/plain'})})]); copyStatus = ' HTML copied.'; }
        catch { copyStatus = ' Clipboard copy unavailable; import the saved file instead.'; }
      }
      status.textContent = 'Saved capture. Import the file in ioant-Note.' + copyStatus + (data.truncated ? ' Some content was truncated.' : '');
    } catch(error) { status.textContent = error.message || String(error); }
    finally { buttons.forEach(b => b.disabled = false); }
  }
  buttons.forEach(b => b.addEventListener('click', () => save(b.id)));
}
