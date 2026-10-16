// Authored native caller regression controls, not a Source observation/golden.
const image={type:'image',data:'AA==',mimeType:'image/png'};
const originalTrim=Object.getOwnPropertyDescriptor(String.prototype,'trim');
export const observations=[];
for(const api of ['openai-completions','openai-responses']){
 const model={id:'fixture-model',provider:'openai',api,reasoning:false,input:['text','image']};
 function convert(text,withImage=false){const content=[{type:'text',text},...(withImage?[image]:[])];const context={messages:[{role:'toolResult',toolCallId:'fixture-call',toolName:'fixture-tool',content,isError:false,timestamp:1}]};try{const rows=nativeToolOutput4dd(model,context);observations.push({api,text,withImage,rows});return rows}catch(error){observations.push({api,text,withImage,thrownFixture:error?.fixture});throw error}}
 function output(rows){return api==='openai-completions'?rows.find(row=>row.role==='tool').content:rows.find(row=>row.type==='function_call_output').output}
 const whitespace=' \t\r\n\u00a0\u1680\u2000\u200a\u2028\u2029\u202f\u205f\u3000\ufeff';
 if(output(convert(whitespace))!=='(no tool output)')throw Error(api+' whitespace placeholder');
 const pictured=output(convert(whitespace,true));
 if(api==='openai-completions'?pictured!=='(see attached image)':!Array.isArray(pictured)||pictured.length!==1||pictured[0].type!=='input_image')throw Error(api+' whitespace image output');
 const original=' \t original \ufeff\n';if(output(convert(original))!==original)throw Error(api+' preserve original bytes');
 for(const text of ['\u0085','\u180e','\u200b'])if(output(convert(text))!==text)throw Error(api+' non-ECMA whitespace');
 for(const [length,expected] of [[4294967296,true],[.5,true],[-1,false],[NaN,false],['1',true],['0',false]]){
  const trace=[];
  try{
   Object.defineProperty(String.prototype,'trim',{configurable:true,get(){trace.push('trim getter');return function(){if(this!=='fixture-tool-output')throw Error('trim receiver');trace.push('trim call');return {get length(){trace.push('length getter');return {valueOf(){trace.push('length valueOf');return length}}}}}}});
   const actual=output(convert('fixture-tool-output'));if(actual!==(expected?'fixture-tool-output':'(no tool output)'))throw Error(api+' length relational coercion');
   if(JSON.stringify(trace)!==JSON.stringify(['trim getter','trim call','length getter','length valueOf']))throw Error(api+' live trim order '+JSON.stringify(trace));
   observations.push({api,coercionLength:String(length),trace});
  }finally{Object.defineProperty(String.prototype,'trim',originalTrim)}
 }
 for(const boundary of ['trim getter','trim call','length getter','length valueOf']){
  const raw={fixture:'owned-raw-trim-reason'},trace=[];
  function stage(name){trace.push(name);if(name===boundary)throw raw}
  try{
   Object.defineProperty(String.prototype,'trim',{configurable:true,get(){stage('trim getter');return function(){stage('trim call');return {get length(){stage('length getter');return {valueOf(){stage('length valueOf');return 1}}}}}}});
   let seen;try{convert('fixture-tool-output')}catch(error){seen=error}if(seen!==raw)throw Error(api+' raw reason '+boundary);
   observations.push({api,boundary,trace,rawSame:seen===raw});
  }finally{Object.defineProperty(String.prototype,'trim',originalTrim)}
 }
}
export const checked=true;
