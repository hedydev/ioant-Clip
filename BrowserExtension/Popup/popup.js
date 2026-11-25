if (typeof document !== 'undefined') {
  const status = document.querySelector('#status');
  const buttons = Array.from(document.querySelectorAll('button'));
  const exportButton = document.querySelector('#export');
  let latestCapture = null;
  function download(data) {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json'}));
    const a = document.createElement('a'); a.href = url;
    a.download = (data.title.replace(/[\\/:*?"<>|]/g,'_').slice(0,70) || 'web-capture') + '.ioantnote.json';
    a.click(); setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
  async function save(mode) {
    buttons.forEach(b => b.disabled = true); status.textContent = 'Capturing…';
    latestCapture = null;
    try {
      const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
      if (!tab?.id) throw new Error('No active tab.');
      let data;
      if (mode === 'viewport') {
        const [meta] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>({title:document.title,sourceURL:location.href,width:window.innerWidth})});
        const [before] = await chrome.tabs.query({active:true,windowId:tab.windowId});
        if (before?.id !== tab.id || before.url !== tab.url) throw new Error('Active page changed. Capture again.');
        const image = await chrome.tabs.captureVisibleTab(tab.windowId,{format:'png'});
        const [after] = await chrome.tabs.query({active:true,windowId:tab.windowId});
        if (after?.id !== tab.id || after.url !== tab.url) throw new Error('Active page changed. Capture again.');
        data = viewportCapture(meta?.result,image);
      } else {
        const [response] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:capture,args:[mode]});
        if (!response?.result) throw new Error(response?.error || 'Unable to capture this page.');
        data = response.result;
      }
      latestCapture = data;
      let resultMessage;
      const copyOnly = document.querySelector('#copy').checked;
      if (copyOnly) {
        try {
          await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([data.html],{type:'text/html'}),'text/plain':new Blob([data.text],{type:'text/plain'})})]);
          resultMessage = 'Styled HTML copied. Paste in ioant-Clip to create a new clip.';
        } catch { resultMessage = 'Clipboard copy unavailable. Export this capture instead.'; }
      } else try {
        const reply = await chrome.runtime.sendNativeMessage('com.ioant.note.capture', {version:1, action:'capture', capture:data});
        if (!reply?.ok || reply.state !== 'queued') throw new Error(reply?.error || 'Unexpected native response.');
        resultMessage = reply.opened ? 'Sent to ioant-Clip. The app will import it.' : 'Queued locally. Open ioant-Clip to import.';
      } catch(error) {
        resultMessage = 'Direct import not confirmed. You can export this capture below. ' + (error.message || String(error));
      }
      status.textContent = resultMessage + (data.truncated ? ' Some content or images could not be captured.' : '');
    } catch(error) { status.textContent = error.message || String(error); }
    finally { buttons.forEach(b => b.disabled = false); exportButton.disabled = !latestCapture; }
  }
  document.querySelector('#viewport').addEventListener('click', () => save('viewport'));
  document.querySelector('#page').addEventListener('click', () => save('page'));
  document.querySelector('#answer').addEventListener('click', () => save('answer'));
  document.querySelector('#selection').addEventListener('click', () => save('selection'));
  exportButton.addEventListener('click', () => { if (latestCapture) { download(latestCapture); status.textContent = 'Exported capture file. Import manually only if needed.'; } });
}
