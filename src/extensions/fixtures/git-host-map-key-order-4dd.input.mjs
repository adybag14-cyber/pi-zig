// Prepared genuine GitHost/LRU raw-key observations. Each case requires a
// fresh Source process/native context. No expected answer or cache stand-in.
const {hosted,caseId}=GitAPI;
if(!['set_tail','remove_previous','remove_next'].includes(caseId))throw Error('Explicit raw-key case required');
const trace=[],symbols={A:Symbol('slot-A'),B:Symbol('slot-B'),C:Symbol('slot-C')};
const bootstrap=name=>`github:lru-key-order/bootstrap-${name}`;
const source='https://lru-key-order.test/first',key=source+'{}';
const original=Object.getOwnPropertyDescriptor(Map.prototype,'get');
let armed=false,strings=0,allow=true,forceMiss=false,reentered=false;
const index=name=>({[Symbol.toPrimitive](hint){
 trace.push({index:name,hint});
 if(name==='A'&&armed&&hint==='string'&&++strings===4){armed=false;reentered=true;trace.push({operation:'reenter-B'});hosted.fromUrl(bootstrap('B'))}
 return hint==='string'?symbols[name]:0;
}});
const A=index('A'),B=index('B'),C=index('C');
hosted.addHost('lru-key-order',{protocols:['https:'],domain:'lru-key-order.test',extract(){return allow?{user:'user',project:'first',committish:''}:undefined}});
try{
 Object.defineProperty(Map.prototype,'get',{...original,value:function(candidate){
  if(candidate===bootstrap('A')+'{}')return A;
  if(candidate===bootstrap('B')+'{}')return B;
  if(candidate===bootstrap('C')+'{}')return C;
  if(candidate===key&&forceMiss){forceMiss=false;return undefined}
  return Reflect.apply(original.value,this,arguments);
 }});
 hosted.fromUrl(bootstrap('A')); // Actual source get makes the raw A its tail.
 trace.length=0;strings=0;armed=caseId!=='remove_next';
 const first=hosted.fromUrl(source);
 const afterSet=trace.slice();
 if(caseId!=='set_tail'){
  hosted.fromUrl('github:lru-key-order/second');hosted.fromUrl('github:lru-key-order/third');
  if(caseId==='remove_next'){hosted.fromUrl(source);hosted.fromUrl(bootstrap('C'))}
  trace.length=0;allow=false;forceMiss=true;
  const removed=hosted.fromUrl(source);
  globalThis.gitHostKeyOrderRows=[{name:`raw-key-${caseId}`,afterSet,trace:trace.slice(),removedUndefined:removed===undefined,reentered,firstProject:first?.project}];
 }else globalThis.gitHostKeyOrderRows=[{name:'raw-key-set-tail',trace:afterSet,reentered,firstProject:first?.project}];
}finally{Object.defineProperty(Map.prototype,'get',original)}
globalThis.gitSourceHostedRows=gitHostKeyOrderRows;globalThis.gitSourceHostedComplete=true;
