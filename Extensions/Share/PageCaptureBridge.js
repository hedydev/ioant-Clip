/* Safari Share extension entry point. Safari calls run for the shared tab. */
var ExtensionPreprocessingJS = {
  run(input) {
    const maxBytes = 8 * 1024 * 1024;
    capture('page', { maxImageBytes: 4 * 1024 * 1024, assetTimeoutMs: 3500, saveVideoFiles: false })
      .then(page => {
        const payload = JSON.stringify(page);
        if (new TextEncoder().encode(payload).length > maxBytes) {
          input.completionFunction({ error: 'error_large' });
        } else {
          input.completionFunction({ capture: payload });
        }
      }, error => input.completionFunction({ error: error?.message || 'error_capture' }));
  }
};
