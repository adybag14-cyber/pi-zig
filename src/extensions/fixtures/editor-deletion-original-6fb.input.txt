const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>JSON.parse(JSON.stringify({text:e.getText(),expanded:e.getExpandedText(),cursor:e.getCursor(),pastes:[...e.pastes],counter:e.pasteCounter,last:e.lastAction,ring:e.killRing.ring,undo:e.undoStack.length,history:e.historyIndex,draft:e.historyDraft}));
for(const text of['','abc def','a😀e\u0301🇺🇳z','\ud800x\udfff','one\ntwo\nthree','中文かな한글'])for(const backward of[true,false]){
  const e=make(),steps=[],changes=[];e.setText(text);if(!backward){e.state.cursorLine=0;e.state.cursorCol=0;}e.onChange=function(value){changes.push([this===e,value]);};for(let i=0;i<8;i++){e[backward?'handleBackspace':'handleForwardDelete']();steps.push(snap(e));}e.undo();results.push({name:'grapheme delete '+backward+' '+JSON.stringify(text),value:{steps,changes,restored:snap(e)}});
}
for(const backward of[true,false]){
  const e=make(),steps=[];e.setText('one.two word\nnext line');if(!backward){e.state.cursorLine=0;e.state.cursorCol=0;}for(let i=0;i<7;i++){e[backward?'deleteWordBackwards':'deleteWordForward']();steps.push(snap(e));}e.yank();results.push({name:'word kills accumulate '+backward,value:{steps,yanked:snap(e)}});
}
for(const marker of['[paste #1]','[paste #1 +12 lines]','[paste #1 1001 chars]']){
  const e=make();e.state={lines:[marker+' [paste #3 +20 lines]','[paste #2] [paste #4 1234 chars]'],cursorLine:0,cursorCol:marker.length};e.pastes=new Map([[4,'four'],[2,'two'],[1,'one'],[3,'three']]);e.pasteCounter=4;e.handleBackspace();const deleted=snap(e);e.undo();results.push({name:'backspace renumbers ascending registry '+marker,value:{deleted,restored:snap(e)}});
}
{
  const e=make();e.setText('[paste #2 +20 lines]tail');e.pastes.set(2,'payload');e.pasteCounter=2;e.state.cursorCol=0;e.handleForwardDelete();results.push({name:'forward marker deletion keeps registry',value:snap(e)});
}
{
  const e=make(),steps=[],changes=[];e.onChange=function(value){changes.push([this===e,value]);};for(const text of['a','b',' ','c','d',' ',' ','e','😀','界']){e.insertCharacter(text);steps.push(snap(e));}for(let i=0;i<7;i++){e.undo();steps.push(snap(e));}results.push({name:'fish word whitespace undo coalescing',value:{steps,changes}});
}
{
  const e=make();e.insertCharacter('A',true);e.insertCharacter('B',true);results.push({name:'skip undo coalescing leaves caller responsibility',value:snap(e)});
}
{
  const e=make(),calls=[];e.tryTriggerAutocomplete=function(...args){calls.push(['trigger',this===e,args]);};e.updateAutocomplete=function(){calls.push(['update',this===e]);};for(const text of['/','a',' ','x','@','y','界'])e.insertCharacter(text);e.autocompleteState='regular';e.insertCharacter('z');e.handleBackspace();e.handleForwardDelete();results.push({name:'actual insertion and deletion autocomplete callbacks',value:{calls,snapshot:snap(e)}});
}
{
  const e=make(),calls=[];e.setText('abcdef');e.moveWordBackwards=function(){calls.push(this===e);this.state.cursorCol=2;};e.deleteWordBackwards();results.push({name:'word deletion invokes actual movement override',value:{calls,snapshot:snap(e)}});
}
globalThis.editorDeletionResult=results;
