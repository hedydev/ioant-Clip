// Chrome owns locale selection and English fallback; no page text replacement.
function message(key) {
  const translated = chrome.i18n.getMessage(key);
  return translated || key;
}
function localizePopup(doc) {
  doc.documentElement.lang = chrome.i18n.getUILanguage();
  for (const el of doc.querySelectorAll('[data-i18n]')) {
    el.textContent = message(el.dataset.i18n);
  }
}
function localizedError(error, fallback = 'error_capture') {
  const detail = error?.message || String(error);
  const known = detail.match(/^(?:Error:\s*)?(error_[a-z_]+)$/)?.[1];
  if (known && chrome.i18n.getMessage(known)) return message(known);
  return [message(fallback), detail].filter(Boolean).join('\n');
}
