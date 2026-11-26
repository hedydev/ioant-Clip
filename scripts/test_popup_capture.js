const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const base = path.join(__dirname, '../BrowserExtension');
const buttons = Object.fromEntries(['viewport', 'page', 'answer', 'selection', 'export'].map(name => [
  name, { addEventListener(event, handler) { this[event] = handler; } }
]));
const status = {};
const copy = {checked:false};
const elements = {...buttons, status, copy};
const sample = {version:1, html:'<p>Fixture</p>', text:'Fixture', mode:'page'};
let injectedResult;
let browserFailure = false;
let queued;
const context = vm.createContext({
  document: {
    querySelector: selector => elements[selector.slice(1)],
    querySelectorAll: selector => selector === 'button' ? Object.values(buttons) : []
  },
  chrome: {
    tabs: {query: async () => [{id:7}], captureVisibleTab: async () => null},
    scripting: {executeScript: async request => {
      assert.equal(request.target.tabId, 7);
      assert.equal(request.args[0], 'page');
      assert.equal(request.args[1].returnOutcome, true);
      assert.equal(typeof request.func, 'function');
      if (browserFailure) throw Error('Synthetic tab unavailable');
      return [{result:injectedResult}];
    }},
    runtime: {sendNativeMessage: async (_, message) => {
      if (message.action === 'ping') return {ok:true};
      queued = message.capture;
      return {ok:true, state:'queued'};
    }}
  },
  capture() {},
  localizePopup() {},
  message: key => key,
  localizedError: error => error.message,
  navigator: {},
  setTimeout: () => {}
});
vm.runInContext(fs.readFileSync(path.join(base, 'Popup/popup.js'), 'utf8'), context);

async function check() {
  injectedResult = {error:'error_empty'};
  await buttons.page.click();
  assert.equal(status.textContent, 'error_empty');
  assert.equal(buttons.export.disabled, true);

  injectedResult = undefined;
  await buttons.page.click();
  assert.equal(status.textContent, 'error_capture_result');

  browserFailure = true;
  await buttons.page.click();
  assert.equal(status.textContent, 'error_capture_tab');
  assert.equal(queued, undefined);

  browserFailure = false;
  injectedResult = {capture:sample};
  await buttons.page.click();
  assert.equal(status.textContent, 'status_queued');
  assert.equal(buttons.export.disabled, false);
  assert.equal(queued, sample);
  console.log('Popup distinguishes page errors from injection failures and queues successful captures');
}
check().catch(error => { console.error(error); process.exitCode = 1; });
