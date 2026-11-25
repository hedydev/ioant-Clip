/* Offline vector snapshot with restricted SVG elements and local references. */
  function createSVG(state,attachData) {
  const svgTags = new Set('svg g defs rect circle ellipse line polyline polygon path text tspan textPath title desc marker linearGradient radialGradient stop clipPath mask pattern symbol use'.split(' '));
  const svgAttrs = new Set('id viewBox preserveAspectRatio x y x1 y1 x2 y2 cx cy r rx ry width height d points dx dy rotate textLength lengthAdjust transform gradientUnits gradientTransform spreadMethod offset markerWidth markerHeight refX refY orient markerUnits patternUnits patternContentUnits patternTransform clipPathUnits maskUnits maskContentUnits'.split(' '));
  const paint = 'fill fill-opacity fill-rule stroke stroke-width stroke-opacity stroke-dasharray stroke-dashoffset stroke-linecap stroke-linejoin stroke-miterlimit clip-rule clip-path mask marker-start marker-mid marker-end opacity color font-family font-size font-weight font-style letter-spacing text-anchor dominant-baseline alignment-baseline vector-effect stop-color stop-opacity paint-order'.split(' ');
  const ns = 'http://www.w3.org/2000/svg';
  function snapshotSVG(src, dst) {
    // Recreate a restricted SVG tree instead of copying arbitrary active markup.
    // SVG is loaded as an isolated image; no event handlers, script, HTML or external URLs.
    function clone(node) {
      if (++state.svgNodes > 12000) { state.truncated = true; return null; }
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
    if (!svg) { state.missing++; return; }
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
    return {snapshotSVG};
  }
