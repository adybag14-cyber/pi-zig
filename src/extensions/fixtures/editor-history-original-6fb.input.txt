// Replay the exact same input against the original Source and native Editor.
const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>JSON.parse(JSON.stringify({state:e.state,text:e.getText(),history:e.history,index:e.historyIndex,draft:e.historyDraft,last:e.lastAction,preferred:e.preferredVisualCol,snapped:e.snappedFromCursorCol,scroll:e.scrollOffset,undo:e.undoStack.length}));
const record=(name,run)=>results.push({name,value:run()});
record('history restores the complete draft cursor and independent arrays',()=>{
  const e=make(),changes=[];e.state={lines:['draft😀','second'],cursorLine:1,cursorCol:2,custom:{value:7}};e.addToHistory('old\nsecond-old');e.addToHistory('new\nsecond-new');e.onChange=function(text){changes.push([this===e,text]);};const draft=e.state,steps=[];
  for(const direction of[-1,-1,-1,1,1,1]){e.navigateHistory(direction);steps.push(snap(e));}
  return{steps,changes,replaced:e.state!==draft,custom:e.state.custom};
});
record('undo browsing keeps current state object and restores draft snapshot',()=>{
  const e=make();e.state={lines:['draft'],cursorLine:0,cursorCol:2};e.addToHistory('stored');const state=e.state;e.navigateHistory(-1);e.preferredVisualCol=9;e.snappedFromCursorCol=4;e.scrollOffset=3;e.undo();return{retained:e.state===state,snapshot:snap(e)};
});
record('navigation invalid bounds resets only lastAction',()=>{
  const e=make();e.lastAction='kill';e.historyIndex=-1;e.historyDraft={held:true};e.preferredVisualCol=2;e.snappedFromCursorCol=3;e.scrollOffset=4;e.navigateHistory(-1);const empty=snap(e);e.addToHistory('one');e.lastAction='yank';e.navigateHistory(1);return{empty,bound:snap(e)};
});
record('missing draft returns empty through virtual setTextInternal',()=>{
  const e=make(),calls=[];e.history=['one'];e.historyIndex=0;e.historyDraft=null;const set=e.setTextInternal;e.setTextInternal=function(...args){calls.push([this===e,args]);return set.apply(this,args);};e.navigateHistory(1);return{calls,snapshot:snap(e)};
});
record('edited recalled history exits browsing through text insertion',()=>{
  const e=make();e.setText('draft');e.addToHistory('stored');e.navigateHistory(-1);e.insertTextAtCursor('X');const edited=snap(e);e.undo();return{edited,undo:snap(e)};
});
record('history draft clone honors the actual structuredClone callback',()=>{
  const previous=globalThis.structuredClone,original=previous??globalThis.nativeDefaultClone,e=make(),calls=[];e.history=['one'];let cloneCount=0;
  globalThis.structuredClone=function(value){calls.push({state:value===e.state,keys:Object.keys(value)});cloneCount++;return original(value);};
  try{e.navigateHistory(-1);return{calls,cloneCount,snapshot:snap(e)};}finally{globalThis.structuredClone=previous;}
});
record('global clone lookup precedes draft state getter',()=>{
  const e=make(),calls=[],state=e.state,descriptor=Object.getOwnPropertyDescriptor(globalThis,'structuredClone'),original=globalThis.structuredClone??globalThis.nativeDefaultClone;
  Object.defineProperty(e,'state',{configurable:true,get(){calls.push('state');return state;},set(value){Object.assign(state,value);}});
  Object.defineProperty(globalThis,'structuredClone',{configurable:true,get(){calls.push('clone');return original;}});
  e.history=['stored'];try{e.navigateHistory(-1);return{calls,text:e.getText()};}finally{if(descriptor)Object.defineProperty(globalThis,'structuredClone',descriptor);else delete globalThis.structuredClone;}
});
globalThis.editorHistoryResult=results;
