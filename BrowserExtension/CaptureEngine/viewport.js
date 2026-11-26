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
