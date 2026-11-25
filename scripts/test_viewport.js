const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const c={TextEncoder}; vm.createContext(c);vm.runInContext(fs.readFileSync('BrowserExtension/viewport.js','utf8'),c);
const result=c.viewportCapture({title:'Fixture',sourceURL:'https://example.test',width:1200},'data:image/png;base64,AA==');
assert.equal(result.mode,'viewport');assert.match(result.html,/width:1232px/);assert.match(result.html,/data:image\/png;base64,AA==/);
assert.throws(()=>c.viewportCapture({sourceURL:'https://example.test'},'https://example.test/image.png'));
console.log('Viewport envelope tests passed');
