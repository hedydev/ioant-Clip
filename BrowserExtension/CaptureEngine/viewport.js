// Explicit visible-page snapshot, not a substitute for whole-page capture.
function viewportCapture(meta, image) {
  if (!meta || typeof meta.sourceURL !== 'string' || !/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(image || '')) throw new Error('error_snapshot');
  const width = Math.max(1,Math.min(8192,Math.round(Number(meta.width)||1280)));
  const title=(meta.title || 'Visible page') + ' — visible snapshot';
  const html='<div data-ioant-frame="1" data-ioant-snapshot="1" style="box-sizing:border-box;margin:0 auto;max-width:100%;width:'+(width+32)+'px;padding:15px;border:1px solid rgba(128,128,128,.25);border-radius:16px;background:#202020"><img alt="Visible page snapshot" style="display:block;width:100%;height:auto;border-radius:8px" src="'+image+'"></div>';
  const result={version:1,title,sourceURL:meta.sourceURL,mode:'viewport',html,text:title,truncated:false};
  if(new TextEncoder().encode(JSON.stringify(result)).length>32*1024*1024) throw new Error('error_snapshot_large');
  return result;
}

function isYouTubeWatchURL(value) {
  try {
    const url = new URL(value);
    return ['www.youtube.com','youtube.com','m.youtube.com'].includes(url.hostname) &&
      url.pathname === '/watch' && /^[\w-]{11}$/.test(url.searchParams.get('v') || '');
  } catch { return false; }
}

function captureWithViewport(data, meta, image, detailsLabel) {
  if (!meta || data.sourceURL !== meta.sourceURL) throw new Error('error_tab_changed');
  const snapshot = viewportCapture(meta,image);
  const label = detailsLabel.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const html = snapshot.html + '<details style="margin:16px auto;max-width:1200px">' +
    '<summary style="padding:8px;cursor:pointer">'+label+'</summary>'+data.html+'</details>';
  const result = {...data,html};
  if (new TextEncoder().encode(JSON.stringify(result)).length > 32*1024*1024) throw new Error('error_snapshot_large');
  return result;
}
