// Executed unchanged against the actual Source Editor and the native export.
const results = [];
const identity = text => text;
const make = options => {
  let requests = 0;
  const tui = { terminal: { columns: 80, rows: 24 }, requestRender() { requests++; } };
  const theme = { borderColor: identity };
  const editor = new Editor(tui, theme, options);
  return { editor, tui, theme, requests: () => requests };
};
const snap = e => ({text:e.getText(), cursor:e.getCursor(), lines:e.getLines(), expanded:e.getExpandedText(), state:e.state, pastes:[...e.pastes], pasteCounter:e.pasteCounter, history:e.history, historyIndex:e.historyIndex, historyDraft:e.historyDraft, lastAction:e.lastAction, preferredVisualCol:e.preferredVisualCol, snappedFromCursorCol:e.snappedFromCursorCol, undo:e.undoStack.length});
const record = (name, run) => results.push({name, value:run()});
record('constructor fields and real auxiliary values', () => {
  const {editor:e,tui,theme}=make();
  return {own:Object.keys(e), descriptor:Object.values(Object.getOwnPropertyDescriptors(e)).every(d=>d.enumerable&&d.writable&&d.configurable), tui:e.tui===tui, theme:e.theme===theme, border:e.borderColor===theme.borderColor, trigger:e.autocompleteTriggerPattern.source, debounce:e.autocompleteDebouncePattern.source, flags:[e.autocompleteTriggerPattern.flags,e.autocompleteDebouncePattern.flags], promise:e.autocompleteRequestTask instanceof Promise, map:e.pastes instanceof Map, undo:e.undoStack.constructor.name, undoFields:Object.keys(e.undoStack), kill:e.killRing.constructor.name, killFields:Object.keys(e.killRing), initial:snap(e)};
});
record('fields control text cursor and cloned lines', () => {
  const {editor:e}=make(); e.state={lines:['a\ud800','b😀c'],cursorLine:1,cursorCol:3};
  const lines=e.getLines();lines[0]='detached';
  e.paddingX=123.25;e.autocompleteMaxVisible=-9;
  return {snapshot:snap(e),padding:e.getPaddingX(),maximum:e.getAutocompleteMaxVisible(),clone:lines!==e.state.lines};
});
record('atomic insert undo deep clones state maps and cursor', () => {
  const {editor:e}=make(); e.state={lines:['first','a😀z','last'],cursorLine:1,cursorCol:3};
  e.pastes.set(7,'payload');e.pasteCounter=7;e.historyIndex=2;e.historyDraft={lines:['draft'],cursorLine:0,cursorCol:1};e.lastAction='type-word';
  const state=e.state,lines=e.state.lines,map=e.pastes;
  e.insertTextAtCursor('\tX\r\nY\rZ');
  const inserted=JSON.parse(JSON.stringify(snap(e))), replaced=e.state.lines!==lines;
  e.pastes.set(7,'changed');e.pasteCounter=99;e.preferredVisualCol=8;e.snappedFromCursorCol=9;e.undo();
  return {inserted,replaced,stateRetained:e.state===state,mapReplaced:e.pastes!==map,restored:snap(e)};
});
record('same text set clears paste registry without extra undo', () => {
  const {editor:e}=make();e.setText('a\tb\r\nc');const changes=[];e.onChange=function(value){changes.push([this===e,value]);};
  const count=e.undoStack.length;e.pastes.set(1,'hidden');e.pasteCounter=3;e.historyIndex=1;e.historyDraft={};e.lastAction='kill';
  e.setText('a    b\nc');const same=snap(e);e.undo();
  return {count,same,restored:snap(e),changes};
});
record('single line internal insertion keeps array identity', () => {
  const {editor:e}=make();e.state={lines:['a😀z'],cursorLine:0,cursorCol:2};const list=e.state.lines;
  e.insertTextAtCursorInternal('\ud800');return{retained:e.state.lines===list,snapshot:snap(e)};
});
record('empty insertion is side effect free', () => {
  const {editor:e}=make();e.historyIndex=5;e.historyDraft={draft:1};e.lastAction='kill';const token=e.autocompleteStartToken;e.insertTextAtCursor('');e.insertTextAtCursorInternal('');
  return {snapshot:snap(e),token:e.autocompleteStartToken===token};
});
record('map expansion follows insertion order and literal replacement', () => {
  const {editor:e}=make();e.pastes.set(1,'[paste #2]');e.pastes.set(2,'$&\nDONE');e.state.lines=['[paste #1 +12 lines] [paste #2 900 chars] [paste #404]'];
  const forward=e.getExpandedText();e.pastes=new Map([[2,'$&'],[1,'[paste #2]']]);
  return{forward,reverse:e.getExpandedText()};
});
record('borrowed getters observe ordinary receivers and iterators', () => {
  let reads=0;const receiver={get state(){reads++;return{lines:['a','b'],cursorLine:reads,cursorCol:reads};}};
  const cursor=Editor.prototype.getCursor.call(receiver),text=Editor.prototype.getText.call(receiver);
  const lines=Editor.prototype.getLines.call({state:{lines:{*[Symbol.iterator](){yield 'custom';yield '\udfff';}}}});
  return{reads,cursor,text,lines};
});
record('paste pair destructuring closes after two entries', () => {
  const calls=[];const pair={ [Symbol.iterator](){let n=0;return {next(){calls.push('next'+n);if(n===2)throw Error('third element must not be read');return{value:n++===0?4:'expanded',done:false};},return(){calls.push('close');return{};}};}};
  return{expanded:Editor.prototype.expandPasteMarkers.call({pastes:[pair]},'[paste #4]'),calls};
});
record('normalization uses actual replace method and receivers', () => {
  const calls=[],fake={replace(pattern,value){calls.push([this===fake,pattern.source,pattern.flags,value]);return calls.length===3?'DONE':this;}};
  return{result:Editor.prototype.normalizeText.call({},fake),calls};
});
record('virtual text hooks preserve order and callback receivers', () => {
  const {editor:e}=make();const calls=[];
  for(const name of ['cancelAutocomplete','exitHistoryBrowsing','normalizeText','getText','pushUndoSnapshot','setTextInternal','setCursorCol']){const original=e[name];e[name]=function(...args){calls.push([name,this===e,args]);return original.apply(this,args);};}
  e.onChange=function(text){calls.push(['onChange',this===e,text]);};e.setText('x\ty\rZ');
  return{calls,text:e.getText()};
});
record('raw onChange throw preserves mutation and identity', () => {
  const {editor:e}=make(),sentinel={raw:true};e.onChange=function(){throw sentinel;};let same=false;try{e.setText('committed');}catch(error){same=error===sentinel;}
  e.onChange=undefined;return{same,snapshot:snap(e)};
});
record('undo assigns into current state and invokes virtual hooks', () => {
  const {editor:e}=make();const calls=[],state=e.state;e.setText('A');e.setText('B');const saved=e.undoStack.stack.at(-1);saved.state.extra='saved';e.state.extra='current';e.snappedFromCursorCol=37;e.preferredVisualCol=17;
  e.onChange=function(text){calls.push([this===e,text]);};e.undo();return{retained:e.state===state,extra:e.state.extra,snapshot:snap(e),calls};
});
record('history trim duplicates and capacity', () => {
  const {editor:e}=make();e.addToHistory('  a  ');e.addToHistory('a');e.addToHistory(' ');for(let i=0;i<103;i++)e.addToHistory(String(i));return{count:e.history.length,first:e.history[0],last:e.history.at(-1)};
});
record('setters use replaced tui and normalize without coercion', () => {
  const {editor:e,requests}=make();let other=0,coercions=0;e.tui={requestRender(){other++;}};e.paddingX=19.5;e.autocompleteMaxVisible=42;e.setPaddingX(2.9);e.setAutocompleteMaxVisible(1);e.setPaddingX({valueOf(){coercions++;return 9;}});e.setAutocompleteMaxVisible('8');
  return{original:requests(),other,coercions,padding:e.paddingX,maximum:e.autocompleteMaxVisible};
});
record('cancellation executes real abort and virtual ui hooks', () => {
  const {editor:e}=make();const calls=[];e.autocompleteAbort={abort(){calls.push(this===e.autocompleteAbort);}};e.autocompleteState='regular';e.autocompleteList={};e.autocompletePrefix='abc';const clear=e.clearAutocompleteUi;e.clearAutocompleteUi=function(){calls.push('clear');return clear.call(this);};e.cancelAutocomplete();
  return{calls,token:e.autocompleteStartToken,state:e.autocompleteState,list:e.autocompleteList,prefix:e.autocompletePrefix,abort:e.autocompleteAbort,showing:e.isShowingAutocomplete()};
});
record('normalization regex literals ignore replaced global constructor', () => {
  const {editor:e}=make(),original=globalThis.RegExp;let calls=0;
  globalThis.RegExp=function(){calls++;throw Error('literal must use its intrinsic constructor');};
  try{e.setText('a\r\nb\tc');return{calls,text:e.getText()};}finally{globalThis.RegExp=original;}
});
globalThis.editorCoreResult=results;
