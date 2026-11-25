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
  const skip = new Set('SCRIPT STYLE LINK META NOSCRIPT IFRAME OBJECT EMBED INPUT TEXTAREA SELECT OPTION VIDEO AUDIO TEMPLATE HEAD FORM BUTTON'.split(' '));
  if (wholePage) { skip.delete('FORM'); skip.delete('BUTTON'); skip.delete('INPUT'); skip.delete('TEXTAREA'); skip.delete('SELECT'); }
  const allowed = new Set('A ABBR ARTICLE ASIDE B BLOCKQUOTE BR CAPTION CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE FOOTER H1 H2 H3 H4 H5 H6 HEADER HR I IMG KBD LI MAIN MARK NAV OL P PRE Q S SAMP SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TH THEAD TFOOT TR U UL VAR WBR MATH COL COLGROUP'.split(' '));
  const state={nodes:0,svgNodes:0,imageBytes:0,truncated:false,missing:0};
  const {root,stage}=createSurface(source,wholePage);
  const {attachData,snapshotImage,queueBackground,finish}=createAssets(state);
  const {applyStyles,isVisuallyClipped,appendPseudo}=createLayout({source,wholePage,stage,queueBackground});
  const {snapshotSVG}=createSVG(state,attachData);
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
    if (isVisuallyClipped(node,cs)) return;
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
    if (tag === 'IMG') snapshotImage(node,dst);
    if (tag === 'TD' || tag === 'TH') { dst.colSpan = node.colSpan; dst.rowSpan = node.rowSpan; }
    if (tag === 'OL' && node.start !== 1) dst.start = node.start;
    if (tag === 'A' && /^https?:\/\//i.test(node.href)) dst.setAttribute('data-source-href',node.href);
    if (tag === 'DETAILS') dst.open = wholePage ? node.open : true;
    parent.append(dst);
    if (wholePage && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::before');
    for (const child of node.childNodes) { if (state.nodes >= 18000) { state.truncated = true; break; } visit(child,dst); }
    if (wholePage && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::after');
  }
  visit(source,stage);
  await finish();
  const html = root.outerHTML;
  // innerText of the attached original is not used for selections: it could include text outside the selection.
  // Whole page text comes from the captured, filtered structure, not the
  // original innerText (which may contain clipped accessibility labels).
  function capturedText(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    if (node.hasAttribute('data-ioant-control')) return '';
    const value = Array.from(node.childNodes,capturedText).join('');
    const block = /^(block|flex|grid|table|list-item|flow-root)/.test(node.style.display);
    return block || node.tagName === 'BR' ? '\n'+value+'\n' : value;
  }
  const text = (range ? range.toString() : wholePage ? capturedText(root).replace(/\n{3,}/g,'\n\n').trim() : source.innerText || root.textContent).slice(0,2_000_000);
  if (!text.trim() && !root.querySelector('img[src]')) throw new Error('error_empty');
  const title = mode === 'answer' ? (text.split(/\n/).find(s=>s.trim()) || 'ChatGPT answer').trim().slice(0,100) : document.title || 'Web capture';
  const result = {version:1,title,sourceURL:location.href,mode,html,text,truncated:state.truncated || state.missing>0};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32*1024*1024) throw new Error('error_large');
  return result;
}
