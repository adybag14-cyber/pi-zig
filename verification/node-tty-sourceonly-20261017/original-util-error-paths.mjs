// Original Node24.14 API inputs only. Prepared/unrun; expected packet absent.
import util from 'node:util';
import tty from 'node:tty';
const rows = [];
const describe = e => ({name:e.name,code:e.code,message:e.message});
function record(name, body) {try { rows.push({name,value:body()}); } catch(e) {rows.push({name,error:describe(e)});}}
for (const error of [-4095,-4094,-4093,-4083,-4071,-4047,-3000,-3014,-4022,-1,-123456,
  -4294971343,-9007199254740991,0,-0,NaN,Infinity,-Infinity,1.5,-1.5,'-4047',16n,Symbol('err')]) {
  record(`error-name:${String(error)}:${typeof error}`, () => util.getSystemErrorName(error));
}
record('error-name-does-not-coerce-object', () => {
  let calls=0; const error={valueOf(){calls++;return -4047}};
  try {util.getSystemErrorName(error);}catch(e){return {calls,error:describe(e)}}
});
for (const value of [undefined,null,true,false,NaN,Infinity,-Infinity,-0,1.23456789,
  0.0000001,1000000000000000000000,16n,-123456789n,Symbol('a'),
  "quote'", 'both\'"', '${`}', '\u007f\u0080\u009f', '\ud800x\udc00',
  'line one\nline two\n'.repeat(6)]) {
  record(`inspect:${typeof value}:${String(value)}`, () => util.inspect(value));
  record(`numeric-separator:${typeof value}:${String(value)}`, () => util.inspect(value,{numericSeparator:true}));
}
record('fd-custom-inspect-exact-receiver-options', () => {
  const trace=[]; const fd={valueOf(){trace.push('valueOf');return -1},[util.inspect.custom](depth,options,inspect){
    trace.push({same:this===fd,depth,keys:Object.keys(options),options:{...options,stylize:typeof options.stylize},inspectSame:inspect===util.inspect}); return 'custom descriptor';
  }};
  try {new tty.WriteStream(fd);}catch(e){return {trace,error:describe(e)}}
});
record('fd-proxy-inspect-bypasses-traps-but-keeps-receiver', () => {
  const trace=[]; let fd;
  const target={valueOf(){return -1},[util.inspect.custom](depth,options,inspect){trace.push({custom:true,same:this===fd,depth,nullOptions:Object.getPrototypeOf(options)===null,nullStylize:Object.getPrototypeOf(options.stylize)===null,inspectSame:inspect===util.inspect});return 'proxy descriptor'}};
  fd=new Proxy(target,{get(t,k,r){trace.push(['get',String(k)]);return Reflect.get(t,k,r)},getPrototypeOf(t){trace.push('getPrototypeOf');return Reflect.getPrototypeOf(t)},ownKeys(t){trace.push('ownKeys');return Reflect.ownKeys(t)}});
  try {new tty.WriteStream(fd);}catch(e){return {trace,error:describe(e)}}
});
record('inspect-revoked-proxy-no-trap',()=>{const revocable=Proxy.revocable({},{});revocable.revoke();return util.inspect(revocable.proxy)});
record('fd-ordinary-descriptor-getter-not-evaluated-by-inspect',()=>{
  const trace=[];const fd={get valueOf(){trace.push('valueOf getter');return ()=>-1},get payload(){trace.push('payload getter');return 42},nested:{one:1},items:[1,2]};
  try{new tty.WriteStream(fd)}catch(e){return {trace,error:describe(e)}}
});
record('fd-custom-inspect-exact-throw',()=>{const reason={};const fd={valueOf(){return -1},[util.inspect.custom](){throw reason}};try{new tty.WriteStream(fd)}catch(e){return e===reason}});
record('fd-custom-toPrimitive-string-hint',()=>{
  const trace=[];const fd={[Symbol.toPrimitive](hint){trace.push(hint);return hint==='number' ? -1 : 'string descriptor'}};
  try{new tty.WriteStream(fd)}catch(e){return {trace,error:describe(e)}}
});
record('public-inspect-property-copy-not-private-module-mutation',()=>{
  const actual=util.inspect; const reason={}; util.inspect=()=>{throw reason};
  try {try{tty.WriteStream.prototype.hasColors(NaN,{FORCE_COLOR:'3'})}catch(e){return {same:e===reason,error:describe(e)}}}
  finally {util.inspect=actual}
});
record('default-options-assign-enumerability-is-live',()=>{
  const before={...util.inspect.defaultOptions};const trace=[];
  const options={get depth(){trace.push('depth');Object.defineProperty(options,'numericSeparator',{configurable:true,enumerable:false,value:true});return 0},numericSeparator:true};
  try {util.inspect.defaultOptions=options;return {trace,depth:util.inspect.defaultOptions.depth,numericSeparator:util.inspect.defaultOptions.numericSeparator}}
  finally {util.inspect.defaultOptions=before}
});
record('default-options-setter-direct-return-identity',()=>{
  const defaults=util.inspect.defaultOptions;
  const setter=Object.getOwnPropertyDescriptor(util.inspect,'defaultOptions').set;
  const before={...defaults};
  try {return {same:setter.call({}, {depth:0})===defaults,sealed:Object.isSealed(defaults),depth:defaults.depth}}
  finally {util.inspect.defaultOptions=before}
});
record('fd-format-inherits-real-default-numeric-separator',()=>{
  const before={...util.inspect.defaultOptions};
  try {
    util.inspect.defaultOptions.numericSeparator=true;
    const values=[util.format('"fd" must be a positive integer: %s',12345),util.format('"fd" must be a positive integer: %s',12345n)];
    try{new tty.WriteStream(12345.5)}catch(e){values.push(describe(e))}
    return values;
  } finally {util.inspect.defaultOptions=before}
});
process.stdout.write(JSON.stringify(rows,(_key,value)=> typeof value==='bigint' ? `${value}n` : value)+'\n');
