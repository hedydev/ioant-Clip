/* Layout and source surface. No image fetching or traversal. */
  function safeCSS(value, localSVG = false) {
    if (!value || /(?:expression\s*\(|-moz-binding|javascript:)/i.test(value)) return false;
    if (!/url\s*\(/i.test(value)) return true;
    return localSVG && /^url\(["']?#[\w:.-]+["']?\)$/.test(value.trim());
  }
  function createSurface(source, wholePage) {
  const root = document.createElement('div');
  root.setAttribute('data-ioant-snapshot','1');
  root.setAttribute('data-ioant-frame','1');
  const sourceCSS = getComputedStyle(source);
  const sourceWidth = Math.ceil(source.getBoundingClientRect().width);
  root.style.cssText = 'box-sizing:border-box;margin:0 auto;max-width:100%;min-width:0;padding:clamp(14px,3vw,24px);border:1px solid rgba(128,128,128,.25);border-radius:16px;';
  root.style.width = (Math.max(1, Math.min(sourceWidth || 768, wholePage ? 8192 : 1800)) + 50) + 'px';
  if (wholePage) {
    root.setAttribute('data-ioant-layout','page');
    root.setAttribute('data-ioant-layout-version','2');
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
    return {root,stage};
  }
  function createLayout({source,wholePage,stage,queueBackground}) {
  const css = 'display box-sizing visibility clip contain content-visibility overflow-anchor font-stretch font-feature-settings font-kerning font-variant-ligatures text-transform text-rendering text-size-adjust -webkit-text-size-adjust writing-mode unicode-bidi text-decoration-line text-decoration-style text-decoration-color text-decoration-thickness text-underline-offset text-shadow tab-size list-style-position column-count column-gap column-width column-span break-before break-after break-inside isolation mix-blend-mode filter backdrop-filter -webkit-line-clamp -webkit-box-orient -webkit-box-align -webkit-box-pack -webkit-box-flex cursor pointer-events border-top-left-radius border-top-right-radius border-bottom-left-radius border-bottom-right-radius display box-sizing color background-color background-image font-family font-size font-weight font-style font-variant-numeric line-height letter-spacing text-align text-decoration white-space overflow-wrap word-break list-style-type padding-top padding-right padding-bottom padding-left margin-top margin-right margin-bottom margin-left border-top border-right border-bottom border-left border-radius box-shadow opacity flex flex-direction flex-wrap flex-grow flex-shrink flex-basis justify-content align-items align-self gap row-gap column-gap grid-template-columns grid-template-rows grid-column grid-row vertical-align min-width max-width min-height max-height border-collapse border-spacing table-layout overflow-x overflow-y position top right bottom left transform transform-origin text-indent width height z-index object-fit object-position background-size background-position background-repeat background-origin background-clip box-decoration-break align-content justify-items justify-self grid-auto-flow grid-auto-columns grid-auto-rows order text-overflow direction aspect-ratio float clear overflow-wrap clip-path'.split(' ');
  function nodeCanGrow(src, cs) {
    return src.childNodes.length > 0 && /^(block|inline-block|flow-root|list-item)$/.test(cs.display) &&
      /^(static|relative)$/.test(cs.position) && cs.overflowX === 'visible' &&
      cs.overflowY === 'visible' && cs.maxHeight === 'none' &&
      !/\b(size|strict|inline-size)\b/.test(cs.contain);
  }
  function applyStyles(src, dst, cs) {
    for (const prop of css) {
      const value = cs.getPropertyValue(prop);
      if (safeCSS(value)) dst.style.setProperty(prop,value);
    }
    // CSS clip and clip-path are part of the visual layout. In particular,
    // accessibility-only labels frequently have 1px absolute boxes with clip.
    // Preserve visible text wrapping and inherited computed typography.
    if (wholePage) {
      dst.style.setProperty('overflow-wrap', cs.overflowWrap || 'normal');
      dst.style.setProperty('word-break', cs.wordBreak || 'normal');
      dst.style.setProperty('white-space', cs.whiteSpace || 'normal');
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
      // Preserve the original minimum footprint, but let visible block content
      // grow when an offline fallback font wraps text onto extra lines.
      const height = Number.parseFloat(cs.height);
      if (!tablePart && nodeCanGrow(src, cs) && Number.isFinite(height)) {
        dst.style.minHeight = cs.minHeight.endsWith('px')
          ? Math.max(height, Number.parseFloat(cs.minHeight)) + 'px' : cs.height;
        dst.style.height = 'auto';
      }
      if (cs.position === 'fixed') {
        // Fixed overlays are captured at their actual current viewport position,
        // not repositioned relative to an arbitrary cloned containing block.
        dst.style.position = 'absolute';
      }
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
    queueBackground(cs.backgroundImage,dst);
  }
    function isVisuallyClipped(node, cs) {
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') return true;
      if (cs.opacity === '0' && ['absolute','fixed'].includes(cs.position)) return true;
      const r = node.getBoundingClientRect();
      const clipped = cs.clip && cs.clip !== 'auto' && /^rect\(/i.test(cs.clip);
      const hiddenOverflow = /hidden|clip/.test(cs.overflowX) && /hidden|clip/.test(cs.overflowY);
      return ['absolute','fixed'].includes(cs.position) && r.width <= 2 && r.height <= 2 &&
        (clipped || hiddenOverflow || /^inset\(\s*50%/.test(cs.clipPath || ''));
    }
    function appendPseudo(src, dst, position) {
      if (!wholePage) return;
      const cs = getComputedStyle(src, position);
      const content = cs.content;
      if (!content || content === 'none' || content === 'normal' || cs.display === 'none' || cs.visibility === 'hidden') return;
      // Only literal generated text/empty decorative boxes. Never copy URL,
      // counter(), attr(), or arbitrary stylesheet/HTML.
      if (!/^"(?:[^"\\]|\\.)*"$/.test(content) && !/^'(?:[^'\\]|\\.)*'$/.test(content)) return;
      const pseudo = document.createElement('span');
      pseudo.setAttribute('data-ioant-pseudo', position === '::before' ? 'before' : 'after');
      for (const prop of css) {
        const value = cs.getPropertyValue(prop);
        if (safeCSS(value)) pseudo.style.setProperty(prop,value);
      }
      pseudo.textContent = content.slice(1,-1).replace(/\\(["'\\])/g,'$1');
      queueBackground(cs.backgroundImage,pseudo);
      dst.append(pseudo);
    }
    return {applyStyles,isVisuallyClipped,appendPseudo};
  }
