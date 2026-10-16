// Original caller inputs only; no copied classifier or authored golden.
export function runRetry698ClassifierCases(classify){
 const rows=[];
 const texts=[
  ['upstream-space','Upstream request failed'],['upstream-none','upstreamrequestfailed'],
  ['upstream-underscore','upstream_request_failed'],['upstream-punctuation','upstream-request.failed'],
  ['upstream-upper','UPSTREAM REQUEST FAILED'],['upstream-two-spaces','upstream  request failed'],
  ['upstream-newline','upstream\nrequest failed'],['upstream-cr','upstream\rrequest failed'],
  ['upstream-nbsp','upstream\u00a0request\u00a0failed'],['upstream-bom','upstream\ufeffrequest\ufefffailed'],
  ['upstream-line-separator','upstream\u2028request failed'],['upstream-paragraph-separator','upstream\u2029request failed'],
  ['upstream-emoji','upstream\u{1f600}request failed'],['upstream-nul','upstream\u0000request failed'],
  ['upstream-leading-embedded','prefixupstream request failed'],['upstream-trailing-embedded','upstream request failedsuffix'],
  ['read-error-exact','upstream_stream_read_error'],['read-error-upper','UPSTREAM_STREAM_READ_ERROR'],
  ['read-error-hyphen','upstream-stream-read-error'],['interrupted-exact','stream was interrupted'],
  ['interrupted-upper','STREAM WAS INTERRUPTED'],['interrupted-double-space','stream  was interrupted'],
  ['interrupted-newline','stream was\ninterrupted'],['http-slash','Upstream HTTP/2 stream failed'],
  ['http-no-slash','http2 stream failed'],['http-upper','HTTP/2 STREAM FAILED'],
  ['http-double-slash','http//2 stream failed'],['http-wrong-version','http/20 stream failed'],
  ['http-double-space','http/2  stream failed'],['quota-wins','upstream request failed: quota exceeded'],
  ['billing-wins','billing: upstream_stream_read_error'],['balance-wins','stream was interrupted: available balance'],
  ['legacy-forward','unknown: Unable to forward upstream stream'],['plain-negative','ordinary unrelated failure'],
  ['empty',''],['wrapped-code','{"type":"upstream_error","message":"Upstream request failed"}'],
 ];
 for(const stopReason of ['error','stop','aborted','length'])for(const [label,errorMessage] of texts){
  rows.push({id:stopReason+'/'+label,stopReason,errorMessage,result:classify({stopReason,errorMessage})});
 }
 for(const [label,errorMessage] of [['undefined',undefined],['null',null],['zero',0],['false',false]])rows.push({id:'falsy/'+label,result:classify({stopReason:'error',errorMessage})});
 rows.push({id:'metadata',name:classify.name,length:classify.length,ownPrototype:Object.hasOwn(classify,'prototype')});
 for(const label of ['stop-getter-throws','error-first-getter-throws','error-second-getter-deny','stop-skips-error-getter']){
  const trace=[],marker={fixture:label};let count=0,result,error;
  const message={get stopReason(){trace.push('stopReason');if(label==='stop-getter-throws')throw marker;return label==='stop-skips-error-getter'?'stop':'error'},get errorMessage(){trace.push('errorMessage:'+ ++count);if(label==='error-first-getter-throws'||label==='stop-skips-error-getter')throw marker;return count===1?'upstream request failed':'billing'}};
  try{result=classify(message)}catch(reason){error=reason===marker?{rawSame:true}:{name:reason.name,message:reason.message}}
  rows.push({id:'getter/'+label,result,error,trace});
 }
 for(const label of ['first-allow-second-negative','first-deny','first-throws','second-throws']){
  const trace=[],marker={fixture:label};let count=0,result,error;
  const value={[Symbol.toPrimitive](hint){trace.push({coercion:++count,hint});if(label==='first-throws'||label==='second-throws'&&count===2)throw marker;return label==='first-deny'?'billing':count===1?'upstream request failed':'ordinary unrelated failure'}};
  try{result=classify({stopReason:'error',errorMessage:value})}catch(reason){error=reason===marker?{rawSame:true}:{name:reason.name,message:reason.message}}
  rows.push({id:'coercion/'+label,result,error,trace});
 }
 const original=Object.getOwnPropertyDescriptor(RegExp.prototype,'test');
 for(const label of ['test-getter-forward','test-getter-throws','test-method-throws']){
  const trace=[],marker={fixture:label};let result,error;
  try{
   Object.defineProperty(RegExp.prototype,'test',{configurable:true,get(){trace.push({event:'test-getter',source:this.source,flags:this.flags});if(label==='test-getter-throws')throw marker;return function(value){trace.push({event:'test-call',source:this.source,receiverRegExp:this instanceof RegExp,value});if(label==='test-method-throws')throw marker;return original.value.call(this,value)}}});
   try{result=classify({stopReason:'error',errorMessage:'upstream request failed'})}catch(reason){error=reason===marker?{rawSame:true}:{name:reason.name,message:reason.message}}
  }finally{Object.defineProperty(RegExp.prototype,'test',original)}
  rows.push({id:'live-regexp/'+label,result,error,trace});
 }
 if(rows.length!==160)throw Error('All160 original retry successor caller cases required');
 return rows;
}
