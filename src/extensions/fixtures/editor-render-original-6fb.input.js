const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const fields=e=>({lastWidth:e.lastWidth,scrollOffset:e.scrollOffset,visible:e.renderedVisibleLineCount,autocomplete:e.renderedAutocompleteHeight});
const attempt=run=>{try{return run();}catch(error){return{error:error.name};}};
for(const width of[0,1,2,4,8,20,80])for(const padding of[0,1,99])for(const focused of[false,true]){
  const e=make();e.setText('abc\ne\u0301😀z\nlast');e.paddingX=padding;e.focused=focused;e.state.cursorLine=0;e.state.cursorCol=2;
  results.push({name:'frame '+width+' '+padding+' '+focused,value:{frame:attempt(()=>e.render(width)),fields:fields(e)}});
}
for(const width of[0,1,2,3,4,7,10,12,20,80])for(const hidden of[0,1,12,100000]){
  const e=make();e.borderColor=function(text){return[this===e,text].join(':');};results.push({name:'borders '+width+' '+hidden,value:{top:e.renderTopBorder(width,hidden),bottom:e.renderBottomBorder(width,hidden)}});
}
{
  const e=make(),frames=[];e.state.lines=Array.from({length:20},(_,i)=>'line '+i);e.tui.terminal.rows=10;e.focused=true;
  for(const row of[0,5,19,18,2]){e.state.cursorLine=row;e.state.cursorCol=e.state.lines[row].length;frames.push({row,frame:e.render(15),fields:fields(e)});}results.push({name:'scroll follows cursor and reverses with resize',value:frames});
}
{
  const e=make(),calls=[];e.paddingX=2;e.state={lines:['abcdef'],cursorLine:0,cursorCol:6};e.autocompleteState='regular';const list={render(width){calls.push([this===list,width]);return['one','界','very long autocomplete row'];}};e.autocompleteList=list;
  results.push({name:'autocomplete renders actual list receiver and content width',value:{frame:e.render(10),fields:fields(e),calls}});
}
{
  const e=make(),calls=[];e.layoutText=function(width){calls.push(['layout',this===e,width]);const lines=[{text:'abc',hasCursor:true,cursorPos:1},{text:'tail',hasCursor:false}];const find=lines.findIndex,slice=lines.slice;Object.defineProperty(lines,'findIndex',{value:function(fn){calls.push(['find',this===lines,fn.length]);return find.call(this,fn);}});Object.defineProperty(lines,'slice',{value:function(...args){calls.push(['slice',this===lines,args]);return slice.apply(this,args);}});return lines;};
  e.renderTopBorder=function(...args){calls.push(['top',this===e,args]);return'TOP';};e.renderBottomBorder=function(...args){calls.push(['bottom',this===e,args]);return'BOTTOM';};e.focused=true;
  results.push({name:'virtual render layout border and array methods',value:{frame:e.render(12),fields:fields(e),calls}});
}
{
  const e=make(),raw={raw:true};e.borderColor=function(){throw raw;};let same=false;try{e.render(20);}catch(error){same=error===raw;}results.push({name:'raw border callback throw',value:{same,fields:fields(e)}});
}
{
  const e=make();e.setText('a😀z');e.state.cursorCol=2;e.focused=true;results.push({name:'split surrogate cursor position remains UTF16',value:{frame:e.render(10),fields:fields(e)}});
}
globalThis.editorRenderResult=results;
