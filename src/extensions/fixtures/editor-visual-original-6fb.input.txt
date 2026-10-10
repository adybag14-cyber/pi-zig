const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const attempt=run=>{try{return run();}catch(error){return{error:error.name,message:error.message};}};
for(const lines of[[],[''],['abcdef'],['one two three four'],['a  b   c '],['中文かな한글'],['e\u0301😀🇺🇳x'],['\ud800a\udfff'],['first','','last'],['abc [paste #1 +12 lines] suffix']])for(const width of[0,1,2,4,8,12,80]){
  const e=make();e.state={lines:[...lines],cursorLine:Math.max(0,lines.length-1),cursorCol:lines.at(-1)?.length??0};e.pastes.set(1,'hidden');e.lastWidth=width;
  const value={layout:attempt(()=>e.layoutText(width)),map:attempt(()=>e.buildVisualLineMap(width)),current:attempt(()=>e.findCurrentVisualLine(e.buildVisualLineMap(width))),first:attempt(()=>e.isOnFirstVisualLine()),last:attempt(()=>e.isOnLastVisualLine())};
  results.push({name:'layout '+JSON.stringify(lines)+' '+width,value});
}
{
  const e=make(),map=[{logicalLine:0,startCol:0,length:3},{logicalLine:0,startCol:3,length:2},{logicalLine:1,startCol:0,length:0},{logicalLine:2,startCol:0,length:4}],positions=[];
  for(const row of[0,1,2,3,'0'])for(const col of[-1,0,2,3,4,5,9])positions.push({row,col,value:e.findVisualLineAt(map,row,col)});
  results.push({name:'visual lookup strict rows and last segment ends',value:{positions,empty:e.findVisualLineAt([],0,0)}});
}
{
  const values=[];for(const preferred of[null,0,2,5,'3'])for(const current of[0,2,4])for(const source of[1,4,8])for(const target of[0,3,6]){const e=make();e.preferredVisualCol=preferred;values.push({preferred,current,source,target,result:e.computeVerticalMoveColumn(current,source,target),after:e.preferredVisualCol});}
  results.push({name:'sticky column decision table',value:values});
}
{
  const e=make(),calls=[];e.state={lines:['abcdef'],cursorLine:0,cursorCol:4};e.segment=function(text,mode){calls.push([this===e,text,mode]);return[{segment:text.slice(0,2),index:0,input:text},{segment:text.slice(2),index:2,input:text}];};
  results.push({name:'actual segment override supplies atomic wrap chunks',value:{layout:e.layoutText(4),calls}});
}
{
  const e=make(),calls=[];e.buildVisualLineMap=function(width){calls.push(['map',this===e,width]);return[{logicalLine:0,startCol:0,length:9}];};e.findVisualLineAt=function(...args){calls.push(['find',this===e,args]);return 0;};e.lastWidth=17;e.state.cursorCol=5;
  results.push({name:'virtual map and lookup receiver',value:{first:e.isOnFirstVisualLine(),last:e.isOnLastVisualLine(),calls}});
}
globalThis.editorVisualResult=results;
