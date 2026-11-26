/* Source entry; build_capture_bundle.py embeds the isolated-world helpers. */
async function capture(mode, options = {}) {
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
  const conversationURL = new URL(location.href);
  const chatConversation = wholePage && ['chatgpt.com','chat.openai.com'].includes(conversationURL.hostname) &&
    /\/(?:c|share)\/[^/]+(?:\/|$)/.test(conversationURL.pathname);
  const fixedLayout = wholePage && !chatConversation;
  const skip = new Set('SCRIPT STYLE LINK META NOSCRIPT OBJECT EMBED INPUT TEXTAREA SELECT OPTION TEMPLATE HEAD FORM BUTTON'.split(' '));
  if (fixedLayout) { skip.delete('FORM'); skip.delete('BUTTON'); skip.delete('INPUT'); skip.delete('TEXTAREA'); skip.delete('SELECT'); }
  const allowed = new Set('A ABBR ARTICLE ASIDE B BLOCKQUOTE BR CAPTION CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE FOOTER H1 H2 H3 H4 H5 H6 HEADER HR I IMG KBD LI MAIN MARK NAV OL P PRE Q S SAMP SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TH THEAD TFOOT TR U UL VAR WBR MATH COL COLGROUP'.split(' '));
  const state={nodes:0,svgNodes:0,imageBytes:0,truncated:false,missing:0};
  const {root,stage}=createSurface(source,fixedLayout);
  const {attachData,snapshotImage,queueBackground,queuePoster,queueVideo,finish}=createAssets(state,options);
  const {applyStyles,isVisuallyClipped,appendPseudo}=createLayout({
    source,wholePage:fixedLayout,stage,queueBackground,conversation:chatConversation
  });
  const {snapshotSVG}=createSVG(state,attachData);
  function recordMedia(node, tag, parent, pageLink) {
    let kind = tag.toLowerCase();
    let url = node.currentSrc || node.getAttribute('src') || node.querySelector('source[src]')?.getAttribute('src');
    if (tag === 'IFRAME') {
      let host;
      try { host = new URL(url, document.baseURI).hostname; } catch { return; }
      if (/(^|\.)(youtube(?:-nocookie)?\.com|vimeo\.com|bilibili\.com|dailymotion\.com|player\.twitch\.tv|clips\.twitch\.tv|streamable\.com|loom\.com|wistia\.net|tiktok\.com)$/i.test(host)) kind = 'video';
      else if (/(^|\.)(soundcloud\.com|spotify\.com|mixcloud\.com)$/i.test(host)) kind = 'audio';
      else return;
      url = kind === 'video' ? new URL(url,document.baseURI).href : location.href;
    }
    const marker = document.createElement('span');
    marker.hidden = true;
    marker.setAttribute('data-ioant-media', kind);
    marker.title = (node.getAttribute('aria-label') || node.title || '').slice(0, 500);
    if (url || pageLink) {
      try {
        const source = new URL(url || pageLink, document.baseURI);
        const web = ['https:', 'http:'].includes(source.protocol) && source.href.length <= 8192;
        const local = source.href.startsWith('data:' + kind + '/') && source.href.length <= 512 * 1024 &&
          state.imageBytes + source.href.length <= 12 * 1024 * 1024;
        if (local) state.imageBytes += source.href.length;
        const savedSource = local ? source.href : pageLink || (web ? source.href : '');
        if (savedSource) marker.setAttribute('data-ioant-media-src', savedSource);
        if (tag === 'VIDEO' && options.saveVideoFiles !== false && !node.mediaKeys && (web || source.protocol === 'blob:')) {
          queueVideo(source.href,node,marker);
        }
      } catch { /* Use the captured page as the source. */ }
    }
    if (tag === 'VIDEO' && node.poster) queuePoster(node.poster, marker);
    parent.append(marker);
  }
  function visit(node, parent, pageLayout = null) {
    if (++state.nodes > 18000) { state.truncated = true; return; }
    if (range && !range.intersectsNode(node)) return;
    if (node.nodeType === Node.TEXT_NODE) {
      let value = node.nodeValue || '';
      if (range) value = value.slice(node === range.startContainer ? range.startOffset : 0, node === range.endContainer ? range.endOffset : value.length);
      parent.append(document.createTextNode(value)); return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    const tag = node.tagName.toUpperCase();
    if (node.isContentEditable || node.hidden || !fixedLayout && node.getAttribute('aria-hidden') === 'true' && tag !== 'SVG') return;
    if (chatConversation && (tag === 'BUTTON' || node.getAttribute('role') === 'button')) {
      if (!isVisuallyClipped(node,getComputedStyle(node))) {
        // Image attachments can be buttons. Keep the media inside them, not the control icons.
        for (const child of node.querySelectorAll('img,video,audio,canvas')) {
          if (!child.closest('[hidden],[aria-hidden="true"]')) visit(child,parent,pageLayout);
        }
      }
      return;
    }
    if (skip.has(tag)) return;
    const cs = getComputedStyle(node);
    // Audio without native controls has no layout box. It can still be
    // playable through the page's custom controls and belong in the index.
    const hasAudioSource = tag === 'AUDIO' &&
      (node.currentSrc || node.getAttribute('src') || node.querySelector('source[src]'));
    if (!hasAudioSource && isVisuallyClipped(node,cs)) return;
    if (node === pageLayout?.player) {
      appendWatchPlayer(node, parent, cs, pageLayout);
      return;
    }
    if (pageLayout && node !== pageLayout.region && cs.position === 'fixed') return;
    if (tag === 'VIDEO' && wholePage) {
      appendVideoPreview(node,parent,cs);
      return;
    }
    if (['VIDEO', 'AUDIO', 'IFRAME'].includes(tag)) {
      recordMedia(node, tag, parent);
      return;
    }
    // Keep empty, inert geometry for visible controls rather than removing a
    // flex/grid item. Do not copy current field values (passwords, tokens,
    // personal inputs), form actions, names, or interactive behavior.
    if (fixedLayout && ['INPUT','TEXTAREA','SELECT'].includes(tag)) {
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
    if (node === pageLayout?.region) {
      dst.style.position = 'relative';
      dst.style.inset = 'auto';
      dst.style.margin = '0';
      dst.style.transform = 'none';
      dst.style.boxSizing = 'border-box';
      dst.style.width = '100%';
      dst.style.maxWidth = 'none';
    }
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
    if (fixedLayout && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::before');
    for (const child of node.childNodes) { if (state.nodes >= 18000) { state.truncated = true; break; } visit(child,dst,pageLayout); }
    if (fixedLayout && !['IMG','BR','HR','WBR','COL'].includes(tag)) appendPseudo(node,dst,'::after');
  }
  function appendVideoPreview(node, parent, style) {
    const frame = document.createElement('div');
    applyStyles(node,frame,style);
    if (style.display === 'inline') frame.style.display = 'inline-block';
    frame.style.height = style.height;
    frame.style.overflow = 'hidden';
    frame.setAttribute('data-ioant-video-preview','');

    const card = node.closest('a[href], [data-e2e="explore-item"], [data-e2e="recommend-list-item-container"]');
    const link = card?.matches('a[href]') ? card : card?.querySelector('a[href*="/video/"]');
    const pageLink = link && /^https:\/\/(?:www\.|m\.)?tiktok\.com\/@[^/]+\/video\/\d+(?:[/?#]|$)/i.test(link.href)
      ? link.href.split(/[?#]/)[0] : null;
    recordMedia(node,'VIDEO',frame,pageLink);

    const image = document.createElement('img');
    image.alt = '';
    image.style.cssText = 'display:block;width:100%;height:100%;';
    image.style.objectFit = style.objectFit === 'fill' ? 'cover' : style.objectFit;
    image.style.objectPosition = style.objectPosition;
    frame.append(image);
    parent.append(frame);

    if (captureVideoFrame(node,image)) return;
    const cover = node.poster || card?.querySelector('img')?.currentSrc || card?.querySelector('img')?.src;
    if (cover) queuePoster(cover,image,'src');
  }

  function appendWatchPlayer(node, parent, style, watch) {
    const player = document.createElement('div');
    applyStyles(node,player,style);
    player.setAttribute('data-ioant-watch-player','');
    player.style.height = style.height;
    player.style.background = '#000';
    player.style.overflow = 'hidden';

    const marker = document.createElement('span');
    marker.hidden = true;
    marker.title = watch.title.slice(0,500);
    marker.setAttribute('data-ioant-media','video');
    marker.setAttribute('data-ioant-media-src',watch.url);
    const image = document.createElement('img');
    image.alt = '';
    image.style.cssText = 'display:block;width:100%;height:100%;object-fit:contain;';
    player.append(image,marker);
    parent.append(player);

    const video = node.querySelector('video');
    if (captureVideoFrame(video,image)) return;
    const poster = 'https://i.ytimg.com/vi/' + watch.videoID + '/hqdefault.jpg';
    queuePoster(poster,image,'src');
  }

  function captureVideoFrame(video, image) {
    if (video?.readyState >= 2 && video.videoWidth && video.videoHeight) {
      try {
        const canvas = document.createElement('canvas');
        const scale = Math.min(1,1280 / video.videoWidth,720 / video.videoHeight);
        canvas.width = Math.max(1,Math.round(video.videoWidth * scale));
        canvas.height = Math.max(1,Math.round(video.videoHeight * scale));
        canvas.getContext('2d').drawImage(video,0,0,canvas.width,canvas.height);
        return attachData(image,canvas.toDataURL('image/jpeg',0.85));
      } catch { /* The browser can restrict access to the active frame. */ }
    }
    return false;
  }

  function visibleRegion(selector, scope = document) {
    return Array.from(scope.querySelectorAll(selector)).find(node => {
      const bounds = node.getBoundingClientRect();
      return bounds.width > 0 && bounds.height > 0 && !isVisuallyClipped(node,getComputedStyle(node));
    });
  }

  function appendYouTubeLayout(content, options = {}) {
    function appendRegion(region, name, topGap) {
      const bounds = region.getBoundingClientRect();
      const wrapper = document.createElement(name);
      wrapper.style.display = 'block';
      wrapper.style.boxSizing = 'border-box';
      wrapper.style.width = bounds.width + 'px';
      const left = Math.max(0,bounds.left + window.scrollX) + 'px';
      if (name === 'aside') {
        wrapper.style.position = 'absolute';
        wrapper.style.left = left;
        wrapper.style.top = topGap + 'px';
      } else {
        wrapper.style.marginLeft = left;
        wrapper.style.marginTop = topGap + 'px';
      }
      visit(region,wrapper,{...options,region});
      stage.append(wrapper);
    }

    const header = visibleRegion('#masthead-container, ytd-masthead, ytm-mobile-topbar-renderer');
    const separateHeader = header && !content.contains(header) ? header : null;
    if (separateHeader) appendRegion(separateHeader,'header',0);
    const headerHeight = separateHeader?.getBoundingClientRect().height || 0;
    const contentTop = content.getBoundingClientRect().top + window.scrollY;
    appendRegion(content,'main',Math.max(0,contentTop - headerHeight));
    if (options.guide) appendRegion(options.guide,'aside',headerHeight);
    return true;
  }

  function captureYouTubePage() {
    const pageURL = new URL(location.href);
    if (!wholePage || !['www.youtube.com','youtube.com','m.youtube.com'].includes(pageURL.hostname)) return false;
    if (pageURL.pathname === '/') {
      const feed = visibleRegion('ytd-browse[page-subtype="home"], ytm-browse, ytd-rich-grid-renderer');
      if (!feed || !(feed.innerText?.trim() || feed.querySelector('img[src]'))) throw new Error('error_empty');
      const guide = visibleRegion('#guide-content, ytd-mini-guide-renderer');
      // Include the guide only when it occupies its own space beside the feed.
      const sideRail = guide && !feed.contains(guide) &&
        guide.getBoundingClientRect().right <= feed.getBoundingClientRect().left + 1 ? guide : null;
      return appendYouTubeLayout(feed,{guide:sideRail});
    }

    const videoID = pageURL.searchParams.get('v');
    if (pageURL.pathname !== '/watch' || !/^[\w-]{11}$/.test(videoID || '')) return false;
    const watchContent = visibleRegion('ytd-watch-flexy, ytm-watch');
    const player = watchContent && visibleRegion('#movie_player, .html5-video-player',watchContent);
    if (player) return appendYouTubeLayout(watchContent,{player,title:document.title,url:pageURL.href,videoID});

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
  function captureConversation() {
    const roles = '[data-message-author-role="user"], [data-message-author-role="assistant"]';
    const turns = [...document.querySelectorAll(roles)].filter(node =>
      !node.parentElement?.closest(roles) && !node.closest('[hidden],[inert],[aria-hidden="true"]') &&
      !isVisuallyClipped(node,getComputedStyle(node)));
    root.setAttribute('data-ioant-conversation','');
    root.style.width = '100%';
    root.style.maxWidth = '900px';
    for (const turn of turns) {
      const message = document.createElement('article');
      message.setAttribute('data-ioant-turn',turn.getAttribute('data-message-author-role'));
      message.style.cssText = 'padding-block:12px;border-bottom:1px solid rgba(128,128,128,.25);';
      visit(turn,message);
      // Images receive their embedded source when the asset queue finishes.
      if (message.textContent.trim() || message.querySelector('img, [data-ioant-media]')) {
        stage.append(message);
      }
      if (state.nodes >= 18000) { state.truncated = true; break; }
    }
  }

  if (chatConversation) captureConversation();
  else if (!captureYouTubePage()) visit(source,stage);
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
    const block = /^(block|flex|grid|table|list-item|flow-root)/.test(node.style.display) ||
      chatConversation && /^(ARTICLE|BLOCKQUOTE|DIV|H[1-6]|LI|P|PRE|SECTION|TABLE|TH|TD|TR)$/.test(node.tagName);
    return block || node.tagName === 'BR' ? '\n'+value+'\n' : value;
  }
  const text = (range ? range.toString() : wholePage ? capturedText(root).replace(/\n{3,}/g,'\n\n').trim() : source.innerText || root.textContent).slice(0,2_000_000);
  if (!text.trim() && !root.querySelector('img[src], [data-ioant-media]')) throw new Error('error_empty');
  const title = mode === 'answer' ? (text.split(/\n/).find(s=>s.trim()) || 'ChatGPT answer').trim().slice(0,100) : document.title || 'Web capture';
  const result = {version:1,title,sourceURL:location.href,mode,html,text,truncated:state.truncated || state.missing>0};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32*1024*1024) throw new Error('error_large');
  return result;
}
