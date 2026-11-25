// The native app may supply its resolved language. Otherwise use the browser.
// Only extension resources are fetched; no page or user content is translated.
let clipMessages = null;
let clipLanguage = null;
function message(key) {
  return clipMessages?.[key]?.message || chrome.i18n.getMessage(key) || key;
}
function localizePopup(doc) {
  doc.documentElement.lang = clipLanguage || chrome.i18n.getUILanguage();
  for (const el of doc.querySelectorAll('[data-i18n]')) {
    el.textContent = message(el.dataset.i18n);
  }
}
async function applyAppLanguage(language, doc) {
  const locale = {'en':'en','zh-Hans':'zh_CN','zh-Hant':'zh_TW','ja':'ja','ko':'ko'}[language];
  if (!locale || !Object.hasOwn({'en':1,'zh-Hans':1,'zh-Hant':1,'ja':1,'ko':1}, language)) return;
  try {
    const response = await fetch(chrome.runtime.getURL('_locales/' + locale + '/messages.json'));
    if (!response.ok) return;
    const catalog = await response.json();
    if (!catalog?.popup_description?.message) return;
    clipMessages = catalog;
    clipLanguage = language;
    localizePopup(doc);
  } catch {}
}
function localizedError(error, fallback = 'error_capture') {
  const detail = error?.message || String(error);
  const known = detail.match(/^(?:Error:\s*)?(error_[a-z_]+)$/)?.[1];
  if (known && (clipMessages?.[known]?.message || chrome.i18n.getMessage(known))) return message(known);
  return message(fallback);
}
