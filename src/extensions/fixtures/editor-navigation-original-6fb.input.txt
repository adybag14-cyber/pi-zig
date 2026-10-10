const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const snap=e=>({cursor:e.getCursor(),preferred:e.preferredVisualCol,snapped:e.snappedFromCursorCol,last:e.lastAction,history:e.historyIndex,draft:e.historyDraft});
for(const padding of[0,1,99])for(const x of[-2,0,1,2,3,4,6,10,20])for(const y of[0,1,2,4,6]){
  const e=make();e.state={lines:['ab😀cd','second','','tail'],cursorLine:0,cursorCol:0};e.paddingX=padding;e.render(10);e.historyIndex=2;e.historyDraft={draft:true};e.lastAction='kill';e.preferredVisualCol=7;e.snappedFromCursorCol=3;
  results.push({name:'click '+padding+' '+x+' '+y,value:{result:e.handleMouse({type:'click',button:'left',x,y,width:10,height:10}),snapshot:snap(e)}});
}
{
  const e=make(),values=[];e.render(10);for(const type of['press','drag','release','wheel'])for(const button of['left','right'])values.push({type,button,result:e.handleMouse({type,button,x:1,y:1,width:10,height:10})});results.push({name:'selection gestures remain unhandled',value:values});
}
{
  const e=make(),calls=[];e.paddingX=2;e.autocompleteState='regular';const list={render(){return['one','two'];},handleMouse(event){calls.push([this===list,event]);return{handled:true,focus:false,custom:7};}};e.autocompleteList=list;e.render(20);const start=e.renderedVisibleLineCount+2;
  results.push({name:'autocomplete mouse actual receiver spread and forced focus',value:{result:e.handleMouse({type:'click',button:'right',x:8,y:start+1,width:20,height:12,extra:'retained'}),calls}});
}
{
  const e=make();e.autocompleteState='regular';e.autocompleteList={render(){return['one'];}};e.render(12);results.push({name:'optional autocomplete mouse method remains absent',value:{result:e.handleMouse({type:'click',button:'left',x:1,y:3,width:12,height:10})}});
}
{
  const e=make(),calls=[];e.setText('abc');e.render(10);e.segment=function(text,mode){return{[Symbol.iterator](){let n=0;return{next(){calls.push('next'+n);return n<text.length?{done:false,value:{segment:text[n],index:n++,input:text}}:{done:true};},return(){calls.push('return');return{};}};}};};
  results.push({name:'mouse hit closes actual segment iterator early',value:{result:e.handleMouse({type:'click',button:'left',x:0,y:1,width:10,height:10}),calls,snapshot:snap(e)}});
}
{
  const e=make(),calls=[];e.setText('abc');e.render(10);e.autocompleteState='regular';e.updateAutocomplete=function(){calls.push(this===e);};
  results.push({name:'mouse cursor calls actual update override',value:{result:e.handleMouse({type:'click',button:'left',x:2,y:1,width:10,height:10}),calls,snapshot:snap(e)}});
}
for(const width of[4,6,10,20]){
  const e=make(),steps=[];e.state={lines:['before','[paste #1 1001 chars] tail','short','after longer line'],cursorLine:0,cursorCol:3};e.pastes.set(1,'X'.repeat(1001));e.lastWidth=width;
  const map=e.buildVisualLineMap(width);for(let target=0;target<map.length;target++){const current=e.findCurrentVisualLine(map);e.moveToVisualLine(map,current,target);steps.push({target,snapshot:snap(e)});}results.push({name:'vertical snap and continuation '+width,value:{map,steps}});
}
{
  const e=make(),steps=[];e.state={lines:['abcdef','x','abcdefghi','😀z','last'],cursorLine:0,cursorCol:5};e.lastWidth=6;e.tui.terminal.rows=10;for(const direction of[1,1,-1,-1]){e.pageScroll(direction);steps.push(snap(e));}results.push({name:'page scroll uses actual terminal viewport and sticky columns',value:steps});
}
{
  const e=make(),calls=[];e.autocompleteProvider={};e.requestAutocomplete=function(options){calls.push([this===e,options]);};e.autocompleteState='regular';e.updateAutocomplete();e.autocompleteState='force';e.updateAutocomplete();e.autocompleteState=null;Object.defineProperty(e,'autocompleteProvider',{get(){throw Error('must short circuit');}});e.updateAutocomplete();results.push({name:'actual update guard and request callback',value:calls});
}
globalThis.editorNavigationResult=results;
