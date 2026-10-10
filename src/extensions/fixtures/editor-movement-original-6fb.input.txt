const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>({cursor:e.getCursor(),preferred:e.preferredVisualCol,snapped:e.snappedFromCursorCol,last:e.lastAction});
for(const text of['abc def  ghi','one.two@example.com','中文かな한글','ภาษาไทย ทดสอบ','e\u0301😀🇺🇳 !? x','[paste #1 +12 lines] tail','\ud800x\udfff','first\nsecond\n'])for(const backward of[false,true]){
  const e=make(),steps=[];e.setText(text);e.pastes.set(1,'hidden');if(!backward){e.state.cursorLine=0;e.state.cursorCol=0;}for(let i=0;i<12;i++){e[backward?'moveWordBackwards':'moveWordForwards']();steps.push(snap(e));}results.push({name:'word '+backward+' '+JSON.stringify(text),value:steps});
}
for(const width of[4,8,20]){
  const e=make(),steps=[];e.state={lines:['a😀e\u0301z','short','longer line here',''],cursorLine:0,cursorCol:0};e.lastWidth=width;for(const [row,col]of[[0,1],[0,1],[0,1],[0,-1],[1,0],[1,0],[-1,0],[1,1],[0,1],[0,1],[0,1],[0,1],[0,-1]]){e.moveCursor(row,col);steps.push(snap(e));}results.push({name:'grapheme and visual cursor '+width,value:steps});
}
{
  const e=make(),values=[];e.state={lines:['axxa','line x','abc'],cursorLine:0,cursorCol:1};for(const [char,direction]of[['x','forward'],['a','forward'],['x','forward'],['a','backward'],['x','backward'],['q','forward'],['','forward']]){e.jumpToChar(char,direction);values.push(snap(e));}results.push({name:'jump multi-line excludes current position',value:values});
}
{
  const e=make(),calls=[];e.setText('hello.world');e.state.cursorCol=0;e.segment=function(text,mode){calls.push([this===e,text,mode]);return[{segment:text,index:0,input:text,isWordLike:true}];};e.moveWordForwards();const forward=snap(e);e.state.cursorCol=11;e.moveWordBackwards();results.push({name:'custom word segment keeps ASCII punctuation boundaries',value:{calls,forward,backward:snap(e)}});
}
{
  const e=make(),calls=[];e.setText('abc def');e.state.cursorCol=0;e.segment=function(text){return{[Symbol.iterator](){let i=0;return{next(){calls.push('next'+i);return i++===0?{done:false,value:{segment:'abc',index:0,input:text,isWordLike:true}}:{done:true};},return(){calls.push('unexpected close');return{};}};}};};e.moveWordForwards();results.push({name:'word forward manually leaves iterator unclosed',value:{calls,snapshot:snap(e)}});
}
{
  const e=make(),calls=[];e.setText('abc');e.autocompleteState='regular';e.updateAutocomplete=function(){calls.push(this===e);};e.moveCursor(0,-1);results.push({name:'cursor movement updates actual open picker',value:{calls,snapshot:snap(e)}});
}
globalThis.editorMovementResult=results;
