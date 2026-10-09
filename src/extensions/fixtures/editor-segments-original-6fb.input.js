const results=[];
const make=()=>new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:text=>text});
const inspect=(e,text,mode)=>{
  const value=e.segment(text,mode),array=Array.isArray(value),rows=[...value],proto=Object.getPrototypeOf(value),iterator=value[Symbol.iterator]();
  const out={array,tag:Object.prototype.toString.call(value),own:Object.keys(value),rows};
  if(!array){out.prototype=Reflect.ownKeys(proto).map(String);out.containingLength=value.containing.length;out.iteratorLength=value[Symbol.iterator].length;out.iteratorTag=Object.prototype.toString.call(iterator);out.iteratorOwn=Object.keys(iterator);out.iteratorPrototype=Reflect.ownKeys(Object.getPrototypeOf(iterator)).map(String);out.nextLength=iterator.next.length;out.positions=[undefined,NaN,-1,0,.9,1,2,3,4,7,100,Infinity,'2'].map(index=>({index:String(index),value:value.containing(index)}));}
  if(rows.length){const first=rows[0];first.segment='mutated';out.fresh=[...value][0]!==first;out.afterMutation=[...value][0];}
  return out;
};
for(const text of['','abc def','e\u0301😀🇺🇳\n','\ud800a\udfff','中文テスト한글','ภาษาไทย ทดสอบ','[paste #1 +12 lines]x [paste #2]'])for(const mode of['grapheme','word']){const e=make();results.push({name:'empty registry '+JSON.stringify(text)+' '+mode,value:inspect(e,text,mode)});e.pastes.set(1,'hidden');e.pastes.set(2,'other');results.push({name:'valid registry '+JSON.stringify(text)+' '+mode,value:inspect(e,text,mode)});}
{
  const e=make();e.pastes.set(9,'invalid');results.push({name:'no valid matching marker keeps Segments',value:inspect(e,'a[paste #1]b','word')});
}
{
  const e=make(),calls=[];e.validPasteIds=function(){calls.push(this===e);return {size:0,has(){throw Error('empty set must bypass has');}};};const input={toString(){calls.push('toString');return'a😀';}};const result=e.segment(input,'grapheme');results.push({name:'valid set evaluated before intrinsic string conversion',value:{calls,rows:[...result]}});
}
{
  const e=make(),raw={raw:true};e.validPasteIds=function(){return{size:1,has(){return true;}};};let same=false;try{e.segment({includes(){throw raw;}},'word');}catch(error){same=error===raw;}results.push({name:'actual includes raw throw',value:{same}});
}
{
  const e=make(),value=e.segment('a😀','grapheme'),iterator=value[Symbol.iterator](),out=[];for(const method of[value.containing,iterator.next]){try{method.call({});}catch(error){out.push(error.name);}}const first=iterator.next(),second=iterator.next(),done1=iterator.next(),done2=iterator.next();results.push({name:'native segment brand exhaustion and record shape',value:{out,first,second,done1,done2,self:iterator[Symbol.iterator]()===iterator}});
}
globalThis.editorSegmentsResult=results;
