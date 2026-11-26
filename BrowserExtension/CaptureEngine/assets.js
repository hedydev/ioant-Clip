/* Bounded asset embedding and raster fallback. Shared capture budget. */
  function createAssets(state) {
    const ns='http://www.w3.org/2000/svg';
    const maxImage=12*1024*1024;
    const pendingImages=[];
    const deadline=Date.now()+15000;
    const assetCache=new Map();
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
    if (state.imageBytes + data.length > maxImage) { state.truncated = true; state.missing++; return false; }
    state.imageBytes += data.length; dst.src = data; return true;
  }
  function snapshotImage(src, dst) {
    dst.alt = src.alt || '[Image unavailable offline]';
    dst.style.imageRendering = 'auto';
    const url = src.currentSrc || src.src || '';
    // Preserve original encoded bytes when available locally. In particular,
    // SVG wrapped in an HTML img must not be flattened through canvas.
    async function preserveLocal() {
      const data=await assetData(url);
      if (typeof data !== 'string' || state.imageBytes + data.length > maxImage) return false;
      return attachData(dst,data);
    }
    function rasterFallback() {
      try {
        if (!src.complete || !src.naturalWidth || !src.naturalHeight) { state.missing++; return; }
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
      } catch { state.missing++; }
    }
    pendingImages.push(async () => { if (!await preserveLocal()) rasterFallback(); });
  }
    function queueBackground(value,dst) {
    if (/url\s*\(/i.test(value)) {
      pendingImages.push(async () => {
        // Preserve gradient layers and replace only accessible image URL layers.
        const matches = [...value.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/gi)];
        let result = value;
        for (const m of matches) {
          const encoded = await assetData(m[1] ?? m[2] ?? m[3]);
          if (!encoded || state.imageBytes + encoded.length > maxImage) { state.missing++; result = result.replace(m[0],'none'); }
          else { state.imageBytes += encoded.length; result = result.replace(m[0],'url("' + encoded + '")'); }
        }
        dst.style.backgroundImage = result;
      });
    }
    }
    function queuePoster(url, target, attribute = 'data-ioant-media-poster') {
      pendingImages.push(async () => {
        const data = await assetData(url);
        if (!data || state.imageBytes + data.length > maxImage) return;
        state.imageBytes += data.length;
        target.setAttribute(attribute, data);
      });
    }
    async function finish() {
      let cursor=0;
      await Promise.all(Array.from({length:Math.min(4,pendingImages.length)},async()=>{
        while(cursor<pendingImages.length) { const i=cursor++; await pendingImages[i](); }
      }));
    }
    return {attachData,snapshotImage,queueBackground,queuePoster,finish};
  }
