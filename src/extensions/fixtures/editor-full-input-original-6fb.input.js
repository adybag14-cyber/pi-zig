const results=[];
const identity=text=>text;
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:identity,selectList:{selectedPrefix:identity,selectedText:identity,description:identity,scrollInfo:identity,noMatch:identity}});
const snap=e=>JSON.parse(JSON.stringify({text:e.getText(),cursor:e.getCursor(),last:e.lastAction,undo:e.undoStack.length,history:e.historyIndex,draft:e.historyDraft,pasting:e.isInPaste,paste:e.pasteBuffer,jump:e.jumpMode,state:e.autocompleteState,prefix:e.autocompletePrefix,ring:e.killRing.ring}));
for(const [name,initial,inputs]of[
 ['typing words','',['a','b',' ','c','d','\x1f','\x1f','\x1f']],
 ['unicode delete','a😀e\u0301🇺🇳z',['\x1b[D','\x7f','\x1b[3~','\x01','\x1b[3~','\x1f']],
 ['paste chunks','A',['\x1b[200~a\r\nb','\tX','\x1b[201~Z','\x1f','\x1f']],
 ['empty paste trailing','',['\x1b[200~\x1b[201~tail']],
 ['newlines and submit','a\\',['\r','next','\x1b\r','last','\r']],
 ['copy cancel ignored','abc',['\x03','\x1b','\x00','']],
 ['kitty shifted characters','',['\x1b[97:65;2u','\x1b[128512u','\x1b[32;2u','\x1b[127;2u']],
 ['visual arrows','one two three\nshort\nlast',['\x1b[A','\x1b[A','\x1b[B','\x1b[C','\x1b[D','\x1b[5~','\x1b[6~']],
 ['packet text remains atomic','',['abc def','\x1f']],
]){
 const e=make(),changes=[],submitted=[],steps=[];e.setText(initial);e.onChange=function(text){changes.push([this===e,text]);};e.onSubmit=function(text){submitted.push([this===e,text]);};e.lastWidth=6;for(const input of inputs){e.handleInput(input);steps.push(snap(e));}results.push({name,value:{steps,changes,submitted}});
}
{
 const e=make(),steps=[];e.addToHistory('old\nentry');e.addToHistory('new');for(const input of['\x1b[A','\x1b[A','\x1b[B','\x1b[B','draft','\x01','\x1b[A','X','\x1f']){e.handleInput(input);steps.push(snap(e));}results.push({name:'arrow history and edits',value:steps});
}
{
 const original=getKeybindings(),e=make(),calls=[];const kb={matches(data,action){calls.push([this===kb,data,action]);return (data==='U'&&action==='tui.editor.undo')||(data==='J'&&action==='tui.editor.jumpForward')||(data==='H'&&action==='tui.editor.historyPrevious');},getKeys(){return[];}};setKeybindings(kb);try{e.setText('axxa');e.state.cursorCol=0;e.handleInput('J');e.handleInput('x');const jumped=snap(e);e.handleInput('z');e.handleInput('U');results.push({name:'actual global keybinding manager override and jump',value:{jumped,after:snap(e),receivers:calls.every(call=>call[0]),matchedActions:calls.filter(call=>['U','J'].includes(call[1])).map(call=>call.slice(1))}});}finally{setKeybindings(original);}
}
{
 const e=make();e.setText('text');e.disableSubmit=true;e.handleInput('\r');results.push({name:'disabled submit keeps text',value:snap(e)});
}
for(const prefix of['/','@'])for(const confirm of['\t','\r']){
 const e=make(),events=[];const provider={getSuggestions(){return{prefix,items:[{value:prefix+'done',label:'Done'}]};},applyCompletion(lines,row,col,item){events.push(['apply',this===provider,item.value]);return{lines:[item.value],cursorLine:0,cursorCol:item.value.length};}};e.setAutocompleteProvider(provider);e.onChange=function(text){events.push(['change',this===e,text]);};e.onSubmit=function(text){events.push(['submit',this===e,text]);};e.requestAutocomplete({force:false,explicitTab:true});await e.autocompleteRequestTask;e.handleInput(confirm);results.push({name:'picker completion '+prefix+' '+JSON.stringify(confirm),value:{events,after:snap(e)}});
}
{
 const e=make(),calls=[];e.setAutocompleteProvider({getSuggestions(lines,row,col,options){calls.push([lines===e.state.lines,row,col,options.force]);return{prefix:'',items:[]};}});e.handleInput('a');e.handleInput('\t');await e.autocompleteRequestTask;results.push({name:'tab invokes actual forced provider request',value:{calls,after:snap(e)}});
}
globalThis.editorFullInputResult=results;
