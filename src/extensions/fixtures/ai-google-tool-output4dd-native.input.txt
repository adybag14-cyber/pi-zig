// Authored caller controls shared with the genuine Source observer. No golden.
const observations=[];
const originalTrim=Object.getOwnPropertyDescriptor(String.prototype,'trim');
const image={type:'image',mimeType:'image/png',data:'AA=='};
const whitespace=' \t\r\n\v\f\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff';
function check(value,message){if(!value)throw Error(message)}
function model(id,input=['text','image']){return {id,name:'fixture',provider:'google',api:'google-generative-ai',reasoning:false,input,contextWindow:32000,maxTokens:8192,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}}
function context(texts,withImage,isError){return {messages:[{role:'toolResult',toolCallId:'fixture-call',toolName:'fixture-tool',content:[...texts.map(text=>({type:'text',text})),...(withImage?[image]:[])],isError,timestamp:1}]}}
function output(contents,isError){const responses=contents.flatMap(row=>row.parts??[]).filter(part=>part.functionResponse);check(responses.length===1,'one real function response');return responses[0].functionResponse.response[isError?'error':'output']}
function ordinary(name,id,texts,withImage,isError,expected,input=['text','image']){
 const contents=nativeGoogleToolOutput4dd(model(id,input),context(texts,withImage,isError));
 check(output(contents,isError)===expected,name+' original output bytes');
 observations.push({name,id,texts,withImage,isError,input,contents,serialized:JSON.stringify(contents)});
}
const inputs=[['empty',''],['ascii',' \t\r\n\v\f'],['ecma-unicode',whitespace],['bom','\ufeff'],['nel','\u0085'],['zwsp','\u200b'],['mvs','\u180e'],['preserved',' \tanswer\n '],['bom-wrapped','\ufeff answer \ufeff'],['unicode-text','é'],['spaces-nel',' \u0085 '],['spaces-zwsp',' \u200b ']];
for(const id of ['gemini-3.1-pro-preview','gemini-2.5-pro'])for(const withImage of [false,true])for(const isError of [false,true]){
 for(const [name,text] of inputs){const present=originalTrim.value.call(text).length>0;ordinary(name,id,[text],withImage,isError,present?text:withImage?'(see attached image)':'')}
 ordinary('zero-text-blocks',id,[],withImage,isError,withImage?'(see attached image)':'');
 ordinary('joined-preserved',id,[' \t','answer ','\ufeff'],withImage,isError,' \t\nanswer \n\ufeff');
}
// Unsupported images become text in transformMessages before this predicate.
for(const id of ['gemini-3.1-pro-preview','gemini-2.5-pro'])for(const isError of [false,true])ordinary('nonvision-whitespace-image',id,[' \t'],true,isError,' \t\n(tool image omitted: model does not support images)',['text']);
const modes=['getter-forward','getter-throws','call-throws','length-zero','length-fraction','length-large','length-negative','length-nan','length-coerce','length-coerce-throws','length-throws','length-bigint','length-symbol','return-null','missing-method'];
for(const mode of modes)for(const withImage of [false,true]){
 const raw='fixture-tool-output',trace=[];let coercions=0;
 const marker={fixture:'owned-raw-trim-reason',toString(){coercions++;throw Error('raw reason was formatted')}};
 let holder;
 function stage(name,receiver,expected){trace.push(name);check(receiver===expected,name+' receiver')}
 try{
  Object.defineProperty(String.prototype,'trim',{configurable:true,get(){
   stage('trim getter',this,raw);
   if(mode==='getter-throws')throw marker;
   if(mode==='missing-method')return undefined;
   return function(...args){
    stage('trim call',this,raw);check(args.length===0,'trim has no arguments');
    if(mode==='call-throws')throw marker;
    if(mode==='getter-forward')return originalTrim.value.call(this);
    if(mode==='return-null')return null;
    holder={get length(){
     stage('length getter',this,holder);
     if(mode==='length-throws')throw marker;
     if(mode==='length-coerce'||mode==='length-coerce-throws'){
      const length={valueOf(){stage('length valueOf',this,length);if(mode==='length-coerce-throws')throw marker;return .5}};
      return length;
     }
     return mode==='length-zero'?0:mode==='length-fraction'?.5:mode==='length-large'?4294967296:mode==='length-negative'?-1:mode==='length-nan'?NaN:mode==='length-bigint'?1n:Symbol('length');
    }};
    return holder;
   };
  }});
  let contents,thrown;
  try{contents=nativeGoogleToolOutput4dd(model('gemini-3.1-pro-preview'),context([raw],withImage,false))}catch(error){thrown=error}
  const rawThrow=['getter-throws','call-throws','length-throws','length-coerce-throws'].includes(mode);
  const typeThrow=['length-symbol','return-null','missing-method'].includes(mode);
  if(rawThrow)check(thrown===marker,mode+' raw thrown identity');
  else if(typeThrow)check(thrown?.name==='TypeError',mode+' TypeError');
  else{check(thrown===undefined,mode+' unexpected throw');const present=!['length-zero','length-negative','length-nan'].includes(mode);check(output(contents,false)===(present?raw:withImage?'(see attached image)':''),mode+' actual JS relational >0')}
  const expected=['trim getter'];
  if(!['getter-throws','missing-method'].includes(mode))expected.push('trim call');
  if(!['getter-forward','getter-throws','call-throws','return-null','missing-method'].includes(mode))expected.push('length getter');
  if(['length-coerce','length-coerce-throws'].includes(mode))expected.push('length valueOf');
  check(JSON.stringify(trace)===JSON.stringify(expected),mode+' live getter/call/coercion order');
  check(coercions===0,mode+' no formatting of raw reason');
  observations.push({name:mode,withImage,trace,rawSame:rawThrow?thrown===marker:undefined,errorName:typeThrow?thrown.name:undefined,reasonFormatting:coercions,contents,serialized:contents===undefined?undefined:JSON.stringify(contents)});
 }finally{Object.defineProperty(String.prototype,'trim',originalTrim)}
}
check(observations.length===146,'all 146 original caller cases');
globalThis.googleToolOutput4ddObservations=observations;
export const checked=true;
export {observations};
