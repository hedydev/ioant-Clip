if (typeof document !== 'undefined') {
  localizePopup(document);
  const status = document.querySelector('#status');
  const buttons = Array.from(document.querySelectorAll('button'));
  const exportButton = document.querySelector('#export');
  let latestCapture = null;
  const viewportButton = document.querySelector('#viewport');
  const copyToggle = document.querySelector('#copy');
  function updateCapabilities() {
    const canScreenshot = typeof chrome.tabs.captureVisibleTab === 'function';
    viewportButton.disabled = !canScreenshot;
    viewportButton.title = canScreenshot ? '' : message('error_viewport_unavailable');
    const canCopy = typeof navigator.clipboard?.write === 'function' && typeof ClipboardItem !== 'undefined';
    copyToggle.disabled = !canCopy;
    if (!canCopy) copyToggle.checked = false;
    copyToggle.title = canCopy ? '' : message('status_copy_unavailable');
  }
  updateCapabilities();
  // Opening the popup verifies the native bridge without reading or sending a page.
  let languageReady = Promise.resolve();
  try {
    languageReady = Promise.race([
      Promise.resolve(chrome.runtime.sendNativeMessage('com.ioant.clip.capture', {version:1, action:'ping'})),
      new Promise(resolve => setTimeout(() => resolve(null), 1500))
    ]).then(reply => reply?.ok && reply.language ? applyAppLanguage(reply.language, document) : undefined).catch(() => {}).then(updateCapabilities);
  } catch {}
  function download(data) {
    const url = URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json'}));
    const a = document.createElement('a'); a.href = url;
    a.download = (data.title.replace(/[\\/:*?"<>|]/g,'_').slice(0,70) || 'web-capture') + '.ioantclip.json';
    a.click(); setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
  async function save(mode) {
    buttons.forEach(b => b.disabled = true); await languageReady; status.textContent = message('status_capturing');
    latestCapture = null;
    try {
      const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
      if (!tab?.id) throw new Error('error_no_tab');
      let data;
      if (mode === 'viewport') {
        if (typeof chrome.tabs.captureVisibleTab !== 'function') throw new Error('error_viewport_unavailable');
        const [meta] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>({title:document.title,sourceURL:location.href,width:window.innerWidth})});
        const [before] = await chrome.tabs.query({active:true,windowId:tab.windowId});
        if (before?.id !== tab.id || before.url !== tab.url) throw new Error('error_tab_changed');
        const image = await chrome.tabs.captureVisibleTab(tab.windowId,{format:'png'});
        const [after] = await chrome.tabs.query({active:true,windowId:tab.windowId});
        if (after?.id !== tab.id || after.url !== tab.url) throw new Error('error_tab_changed');
        data = viewportCapture(meta?.result,image);
      } else {
        let response;
        try {
          [response] = await chrome.scripting.executeScript({
            target:{tabId:tab.id},func:capture,args:[mode,{returnOutcome:true}]
          });
        } catch {
          throw new Error('error_capture_tab');
        }
        const result = response?.result;
        if (result?.error) throw new Error(result.error);
        if (!result?.capture) throw new Error('error_capture_result');
        data = result.capture;
      }
      latestCapture = data;
      let resultMessage;
      const copyOnly = document.querySelector('#copy').checked;
      if (copyOnly) {
        try {
          await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([data.html],{type:'text/html'}),'text/plain':new Blob([data.text],{type:'text/plain'})})]);
          resultMessage = message('status_copied');
        } catch { resultMessage = message('status_copy_unavailable'); }
      } else try {
        const reply = await chrome.runtime.sendNativeMessage('com.ioant.clip.capture', {version:1, action:'capture', capture:data});
        if (!reply?.ok || reply.state !== 'queued') throw new Error(reply?.error || 'error_native');
        resultMessage = reply.opened ? message('status_sent') : message('status_queued');
      } catch(error) {
        resultMessage = [message('status_import_unconfirmed'), localizedError(error, 'error_native')].join('\n');
      }
      status.textContent = [resultMessage, data.truncated ? message('status_partial') : ''].filter(Boolean).join('\n');
    } catch(error) { status.textContent = localizedError(error); }
    finally { buttons.forEach(b => b.disabled = false); exportButton.disabled = !latestCapture; updateCapabilities(); }
  }
  document.querySelector('#viewport').addEventListener('click', () => save('viewport'));
  document.querySelector('#page').addEventListener('click', () => save('page'));
  document.querySelector('#answer').addEventListener('click', () => save('answer'));
  document.querySelector('#selection').addEventListener('click', () => save('selection'));
  exportButton.addEventListener('click', () => { if (latestCapture) { download(latestCapture); status.textContent = message('status_exported'); } });
}
