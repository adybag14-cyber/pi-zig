const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>JSON.parse(JSON.stringify({text:e.getText(),state:e.state,ring:e.killRing.ring,undo:e.undoStack.length,last:e.lastAction,historyIndex:e.historyIndex,historyDraft:e.historyDraft,preferred:e.preferredVisualCol,snapped:e.snappedFromCursorCol}));
const record=(name,run)=>results.push({name,value:run()});
for(const [name,lines,row,col,ops]of[
  ['backward accumulation',['abc','def','ghi'],1,2,['deleteToStartOfLine','deleteToStartOfLine','deleteToStartOfLine','yank','undo']],
  ['forward accumulation',['abc','def','ghi'],0,1,['deleteToEndOfLine','deleteToEndOfLine','deleteToEndOfLine','yank','undo']],
  ['empty lines merge',['','😀',''],1,0,['deleteToStartOfLine','deleteToEndOfLine','deleteToEndOfLine','yank','undo']],
  ['edges notify',[''],0,0,['deleteToStartOfLine','deleteToEndOfLine','moveToLineEnd','moveToLineStart','yank']],
  ['line moves reset sticky',['e\u0301😀z'],0,3,['moveToLineStart','moveToLineEnd','deleteToStartOfLine','yank']],
])record(name,()=>{const e=make(),changes=[],steps=[];e.state={lines:[...lines],cursorLine:row,cursorCol:col};e.historyIndex=3;e.historyDraft={draft:true};e.preferredVisualCol=9;e.snappedFromCursorCol=7;e.onChange=function(text){changes.push([this===e,text]);};for(const op of ops){e[op]();steps.push(snap(e));}return{steps,changes};});
for(const text of['abc','a\nb','\n','a\n\nb','\ud800😀\t'])record('raw yank '+JSON.stringify(text),()=>{const e=make(),changes=[];e.state={lines:['AZ','last'],cursorLine:0,cursorCol:1};e.killRing.ring.push('older',text);e.onChange=function(value){changes.push([this===e,value]);};const list=e.state.lines;e.yank();const first=snap(e),retained=list===e.state.lines;e.yankPop();const second=snap(e);e.undo();return{first,retained,second,restored:snap(e),changes};});
record('actual splice receiver and source deletion arguments',()=>{const e=make(),calls=[];e.state={lines:['a','b','c'],cursorLine:1,cursorCol:0};const list=e.state.lines,splice=list.splice;Object.defineProperty(list,'splice',{configurable:true,value:function(...args){calls.push([this===list,args,[...this]]);return splice.apply(this,args);}});e.deleteToStartOfLine();e.deleteToEndOfLine();return{calls,retained:list===e.state.lines,snapshot:snap(e)};});
record('yank observes ring replacement during virtual snapshot',()=>{const e=make(),other=make(),push=e.pushUndoSnapshot;e.killRing.ring.push('old');other.killRing.ring.push('new');e.pushUndoSnapshot=function(){push.call(this);this.killRing=other.killRing;};e.yank();return snap(e);});
record('yank pop observes ring replacement during virtual deletion',()=>{const e=make(),other=make();e.killRing.ring.push('old1','old2');other.killRing.ring.push('new1','new2');e.lastAction='yank';e.deleteYankedText=function(){this.killRing=other.killRing;};e.yankPop();return snap(e);});
record('no-op yank pop short circuits before ring getter',()=>{const e=make();e.lastAction=null;Object.defineProperty(e,'killRing',{get(){throw Error('must not read ring');}});e.yankPop();return{last:e.lastAction,undo:e.undoStack.length};});
record('kill raw change throw preserves committed mutation',()=>{const e=make(),raw={raw:true};e.setText('abc');e.onChange=function(){throw raw;};let same=false;try{e.deleteToStartOfLine();}catch(error){same=error===raw;}return{same,snapshot:snap(e)};});
record('public keyboard uses the ordinary source kill ring',()=>{const e=make(),steps=[];e.setText('abc\ndef');for(const key of['\x01','\x0b','\x19','\x05','\x15','\x19']){e.handleInput(key);steps.push(snap(e));}return steps;});
globalThis.editorKillsResult=results;
