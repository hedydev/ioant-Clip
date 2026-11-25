const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const base = path.join(__dirname, '../BrowserExtension');
const elements = [{dataset:{i18n:'popup_description'},textContent:''}];
const document = {documentElement:{},querySelectorAll:()=>elements};
const en = JSON.parse(fs.readFileSync(path.join(base,'_locales/en/messages.json')));
const ctx = vm.createContext({
  Object, document,
  chrome:{i18n:{getMessage:key=>en[key]?.message||'',getUILanguage:()=> 'en-US'},runtime:{getURL:p=>p}},
  fetch:async p=>({ok:true,json:async()=>JSON.parse(fs.readFileSync(path.join(base,p)))})
});
vm.runInContext(fs.readFileSync(path.join(base,'Popup/localization.js'),'utf8'),ctx);
(async()=>{
 for (const [code,folder] of Object.entries({'en':'en','zh-Hans':'zh_CN','zh-Hant':'zh_TW','ja':'ja','ko':'ko'})){
   const catalog=JSON.parse(fs.readFileSync(path.join(base,'_locales',folder,'messages.json')));
   await ctx.applyAppLanguage(code,document);
   assert.equal(document.documentElement.lang,code);
   assert.equal(elements[0].textContent,catalog.popup_description.message);
   assert.equal(ctx.localizedError(new Error('error_native')),catalog.error_native.message);
   assert.equal(ctx.localizedError(new Error('Raw English OS diagnostic')),catalog.error_capture.message);
 }
 console.log('Popup explicit app language and localized error fallback passed for five locales');
})().catch(err=>{console.error(err);process.exitCode=1;});
