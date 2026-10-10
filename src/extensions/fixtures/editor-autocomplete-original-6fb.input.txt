const results=[];
const identity=text=>text;
const make=()=>{let renders=0;const e=new Editor({terminal:{columns:80,rows:24},requestRender(){renders++;}},{borderColor:identity,selectList:{selectedPrefix:identity,selectedText:identity,description:identity,scrollInfo:identity,noMatch:identity}});return{e,renders:()=>renders};};
const defer=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{promise,resolve,reject};};
const opts={force:false,explicitTab:true};
const snap=e=>({text:e.getText(),cursor:e.getCursor(),state:e.autocompleteState,prefix:e.autocompletePrefix,list:e.autocompleteList?{items:e.autocompleteList.items,selected:e.autocompleteList.selectedIndex,maximum:e.autocompleteList.maxVisible}:null,token:e.autocompleteStartToken,id:e.autocompleteRequestId,abort:!!e.autocompleteAbort,undo:e.undoStack.length});
const record=(name,value)=>results.push({name,value});
{
  const {e}=make();e.setAutocompleteTriggerCharacters(['!',']','-','\\',' ','/','@','#','!','ab','😀','\ud800']);const values=[];for(const text of['@x','#x','!x',']x','-x','\\x','word@x','(@"a b','界，@x','界@x']){e.setText(text);values.push([text,e.getAutocompleteDebounceMs({force:false,explicitTab:false}),e.getAutocompleteDebounceMs(opts)]);}record('trigger characters actual unicode regex and debounce',{characters:e.autocompleteTriggerCharacters,trigger:e.autocompleteTriggerPattern.source,debounce:e.autocompleteDebouncePattern.source,values});
}
{
  const {e}=make(),items=[{value:'Alpha',label:'other'},{value:'Al',label:'x'},{value:'alphabet',label:'Alpha'}];record('best match value priority and case', ['', 'Al','Alpha','al','z'].map(prefix=>[prefix,e.getBestAutocompleteMatchIndex(items,prefix)]));
}
{
  const {e,renders}=make(),events=[];const provider={getSuggestions(lines,row,col,options){events.push([this===provider,lines===e.state.lines,row,col,options.force,options.signal instanceof AbortSignal,options.signal.aborted]);return{prefix:'a',items:[{value:'abc',label:'A'},{value:'a',label:'Exact'}]};}};e.setAutocompleteProvider(provider);const before=snap(e);e.requestAutocomplete(opts);const synchronous={snapshot:snap(e),calls:events.length};await e.autocompleteRequestTask;record('sync provider is awaited and original list selected',{before,synchronous,events,after:snap(e),renders:renders()});
}
{
  const {e}=make(),events=[],previous=defer();e.setAutocompleteProvider({getSuggestions(){events.push('provider');return{prefix:'',items:[]};}});e.autocompleteRequestTask=previous.promise;const token=e.autocompleteStartToken;const promise=e.startAutocompleteRequest(token,opts);events.push('called');await Promise.resolve();events.push('one tick');previous.resolve();await promise;events.push('finished');record('previous task serializes provider',{events,snapshot:snap(e)});
}
{
  const {e}=make(),events=[],first=defer();let calls=0,signal;const provider={getSuggestions(lines,row,col,options){calls++;events.push(['get',calls,lines===e.state.lines]);if(calls===1){signal=options.signal;signal.addEventListener('abort',function(){events.push(['abort',this===signal,signal.aborted]);});return first.promise;}return{prefix:'new',items:[{value:'new',label:'New'}]};}};e.setAutocompleteProvider(provider);e.requestAutocomplete(opts);await Promise.resolve();e.requestAutocomplete(opts);events.push(['after request',calls,signal.aborted]);first.resolve({prefix:'old',items:[{value:'old',label:'Old'}]});await e.autocompleteRequestTask;record('cancel waits old task and ignores old result',{events,snapshot:snap(e)});
}
{
  const {e,renders}=make(),pending=defer();e.setText('abc');e.setAutocompleteProvider({getSuggestions(){return pending.promise;}});e.requestAutocomplete(opts);await Promise.resolve();e.state.cursorCol=0;pending.resolve({prefix:'abc',items:[{value:'stale',label:'Stale'}]});await e.autocompleteRequestTask;record('changed cursor invalidates result',{snapshot:snap(e),renders:renders()});
}
{
  const {e,renders}=make();e.setAutocompleteProvider({getSuggestions(){return null;}});e.requestAutocomplete(opts);await e.autocompleteRequestTask;record('empty result clears ui and redraws',{snapshot:snap(e),renders:renders()});
}
{
  const {e,renders}=make(),events=[];const provider={shouldTriggerFileCompletion(lines,row,col){events.push(['should',this===provider,lines===e.state.lines,row,col]);return true;},getSuggestions(){return{prefix:'x',items:[{value:'done',label:'Done'}]};},applyCompletion(lines,row,col,item,prefix){events.push(['apply',this===provider,lines===e.state.lines,row,col,item.value,prefix]);return{lines:['COMPLETE'],cursorLine:0,cursorCol:3};}};e.setAutocompleteProvider(provider);e.onChange=function(text){events.push(['change',this===e,text]);};e.requestAutocomplete({force:true,explicitTab:true});await e.autocompleteRequestTask;record('forced single completion applies atomically',{events,snapshot:snap(e),renders:renders()});
}
{
  const {e}=make(),calls=[];e.setAutocompleteProvider({shouldTriggerFileCompletion(){calls.push('denied');return false;},getSuggestions(){calls.push('unexpected');}});const before=snap(e);e.forceFileAutocomplete(true);record('force predicate denial preserves request state',{calls,before,after:snap(e)});
}
{
  const {e}=make(),events=[];const provider={applyCompletion(lines,row,col,item,prefix){events.push([this===provider,lines===e.state.lines,item.value,prefix]);return{lines:['selected'],cursorLine:0,cursorCol:8};}};e.setAutocompleteProvider(provider);e.applyAutocompleteSuggestions({prefix:'/a',items:[{value:'/abc',label:'ABC'},{value:'/a',label:'Exact'}]},'regular');const before=snap(e),list=e.autocompleteList;e.onChange=function(text){events.push([this===e,text]);};list.onSelect(list.items[0]);record('actual SelectList callback applies and cancels',{before,layout:list.layoutOptions,events,after:snap(e)});
}
{
  const {e}=make(),events=[];e.setAutocompleteProvider({applyCompletion(){events.push('old');}});const list=e.createAutocompleteList('old',[{value:'item',label:'Item'}]);const provider={applyCompletion(lines,row,col,item,prefix){events.push([this===provider,prefix,item.value]);return{lines:['new provider'],cursorLine:0,cursorCol:1};}};e.setAutocompleteProvider(provider);list.onSelect({value:'item',label:'Item'});record('retained old list observes current provider and prefix',{events,snapshot:snap(e)});
}
{
  const {e}=make(),raw={raw:true};e.setAutocompleteProvider({getSuggestions(){throw raw;}});const controller=new AbortController();e.autocompleteRequestId=1;let threw=false,promise;try{promise=e.runAutocompleteRequest(1,controller,'',0,0,opts);}catch(error){threw=true;}let same=false;try{await promise;}catch(error){same=error===raw;}record('run wraps synchronous provider throw in raw rejection',{threw,same,snapshot:snap(e)});
}
{
  const {e}=make(),raw={previous:true};e.setAutocompleteProvider({getSuggestions(){throw Error('unexpected');}});e.autocompleteRequestTask=Promise.reject(raw);let same=false;try{await e.startAutocompleteRequest(e.autocompleteStartToken,opts);}catch(error){same=error===raw;}record('previous raw rejection remains serialized',{same,snapshot:snap(e)});
}
{
  const {e}=make(),original=Promise.prototype.then,raw={patched:true};e.setAutocompleteProvider({getSuggestions(){return{prefix:'',items:[]};}});let same=false,ok=false;Promise.prototype.then=function(){throw raw;};try{await e.startAutocompleteRequest(e.autocompleteStartToken,opts);ok=true;}catch(error){same=error===raw;}finally{Promise.prototype.then=original;}record('await ignores patched public promise then',{same,ok,snapshot:snap(e)});
}
{
  const {e}=make(),events=[];e.setText('@path');e.setAutocompleteProvider({getSuggestions(){events.push('get');return{prefix:'@path',items:[{value:'@pathx',label:'Path'}]};}});e.requestAutocomplete({force:false,explicitTab:false});const before={calls:events.length,timer:!!e.autocompleteDebounceTimer};await new Promise(resolve=>setTimeout(resolve,45));await e.autocompleteRequestTask;record('actual debounce timer starts provider',{before,events,timer:!!e.autocompleteDebounceTimer,snapshot:snap(e)});
}
{
  const {e}=make(),events=[];e.setText('@path');e.setAutocompleteProvider({getSuggestions(){events.push('unexpected');}});e.requestAutocomplete({force:false,explicitTab:false});e.cancelAutocomplete();await new Promise(resolve=>setTimeout(resolve,45));record('cancel clears pending debounce without provider',{events,timer:!!e.autocompleteDebounceTimer,snapshot:snap(e)});
}
globalThis.editorAutocompleteResult=results;
