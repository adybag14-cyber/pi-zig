const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>JSON.parse(JSON.stringify({text:e.getText(),expanded:e.getExpandedText(),state:e.state,pastes:[...e.pastes],counter:e.pasteCounter,undo:e.undoStack.length,last:e.lastAction,historyIndex:e.historyIndex,historyDraft:e.historyDraft,preferred:e.preferredVisualCol,snapped:e.snappedFromCursorCol,scroll:e.scrollOffset}));
const record=(name,run)=>results.push({name,value:run()});
for(const [name,input] of [['clean controls','a\r\nb\rc\t\0\x01\x1b[106;5uZ\x1b[65;5uEND'],['unknown CSI code','a\x1b[42;5u\x1b[0;5uZ'],['empty',''],['ten lines',Array(10).fill('x').join('\n')],['eleven lines',Array(11).fill('x').join('\n')],['1000 units','x'.repeat(1000)],['1001 units','x'.repeat(1001)],['surrogate units','😀'.repeat(501)],['lone surrogates','\ud800\udfff\ud800']]){
  record('paste '+name,()=>{const e=make(),changes=[];e.state={lines:['before','AZ','after'],cursorLine:1,cursorCol:1};e.historyIndex=2;e.historyDraft={};e.lastAction='type-word';e.onChange=function(text){changes.push([this===e,text]);};const list=e.state.lines;e.handlePaste(input);const pasted=snap(e),sameLines=list===e.state.lines;e.undo();return{pasted,sameLines,undo:snap(e),changes};});
}
record('path prefix uses ASCII word before cursor',()=>{
  const steps=[];for(const prefix of ['abc','abc ','界','_','3','-'])for(const path of ['/tmp/file','~/file','./file','ordinary']){const e=make();e.setText(prefix);e.handlePaste(path);steps.push([prefix,path,e.getText()]);}return steps;
});
record('valid ids are constructed from actual keys method',()=>{
  const e=make();e.pastes.set(9,'a');e.pastes.set(2,'b');const valid=e.validPasteIds();e.pastes.delete(9);return{valid:[...valid],independent:valid.has(9),map:[...e.pastes]};
});
record('newline keeps line array and restores whole cursor on undo',()=>{
  const e=make(),changes=[];e.state={lines:['a😀z','last'],cursorLine:0,cursorCol:2};e.historyIndex=1;e.historyDraft={};e.lastAction='kill';e.onChange=function(text){changes.push([this===e,text]);};const list=e.state.lines;e.addNewLine();const split=snap(e),retained=e.state.lines===list;e.undo();return{split,retained,restored:snap(e),changes};
});
record('submit expands trims and clears before ordered callbacks',()=>{
  const e=make(),events=[];e.setText('  [paste #1] \n ');e.pastes.set(1,'PAYLOAD');e.pasteCounter=1;e.historyIndex=3;e.historyDraft={};e.scrollOffset=6;e.preferredVisualCol=7;e.snappedFromCursorCol=8;const old=e.state;
  e.onChange=function(value){events.push(['change',this===e,value,snap(e)]);};e.onSubmit=function(value){events.push(['submit',this===e,value,snap(e)]);};e.submitValue();return{events,replaced:old!==e.state,final:snap(e)};
});
record('submit raw change throw prevents submit after clearing state',()=>{
  const e=make(),raw={raw:true};e.setText('text');let submitted=false,same=false;e.onChange=function(){throw raw;};e.onSubmit=function(){submitted=true;};try{e.submitValue();}catch(error){same=error===raw;}return{same,submitted,final:snap(e)};
});
record('backslash enter honors actual kb receiver and key alternatives',()=>{
  const results=[];for(const disabled of[false,true])for(const text of['a\\','a',''])for(const input of['\r','\x1b[13;2u','x'])for(const bindings of[['enter'],['shift+enter'],['shift+return']]){const e=make(),calls=[];e.setText(text);e.disableSubmit=disabled;const kb={getKeys(action){calls.push([this===kb,action]);return bindings;}};results.push({disabled,text,input,bindings,result:e.shouldSubmitOnBackslashEnter(input,kb),calls});}return results;
});
globalThis.editorPasteResult=results;
