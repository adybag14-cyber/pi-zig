// Original Node24.14 calls, prepared only. No expected values or captured output.
// Capture with Root's bounded Node owner; process/platform changes are restored.
import tty from 'node:tty';
import net from 'node:net';
import os from 'node:os';
const p = tty.WriteStream.prototype;
const rows = [];
const representation = value => {
  if (typeof value === 'function') return {type: 'function', name: value.name};
  if (value === undefined) return {type: 'undefined'};
  if (typeof value === 'number' && !Number.isFinite(value)) return String(value);
  return value;
};
function record(name, body) {
  try { rows.push({name, value: representation(body())}); }
  catch (error) { rows.push({name, error: {name: error.name, code: error.code, message: error.message}}); }
}
// EXACT consumed yoctocolors/jiti optional-chain call, with actual receiver.
record('actual-jiti-colors-call', () => tty?.WriteStream?.prototype?.hasColors?.() ?? false);
record('actual-os-platform', () => process.platform);
record('actual-os-release', () => os.release());
record('ordinary-constructors-and-prototypes', () => ({
  exports: Object.keys(tty),
  readCtorParent: Object.getPrototypeOf(tty.ReadStream) === net.Socket,
  writeCtorParent: Object.getPrototypeOf(tty.WriteStream) === net.Socket,
  readParent: Object.getPrototypeOf(tty.ReadStream.prototype) === net.Socket.prototype,
  writeParent: Object.getPrototypeOf(p) === net.Socket.prototype,
  read: [tty.ReadStream.name, tty.ReadStream.length],
  write: [tty.WriteStream.name, tty.WriteStream.length],
  methods: Object.fromEntries(['hasColors','getColorDepth','getWindowSize','cursorTo','moveCursor','clearLine','clearScreenDown','_refreshSize'].map(key => [key, {name: p[key].name, length: p[key].length, descriptor: Object.getOwnPropertyDescriptor(p,key)}])),
}));
record('lexical-depth-not-receiver-method', () => p.hasColors.call({getColorDepth(){throw Error('wrong receiver dispatch')}}, 16, {FORCE_COLOR:'1'}));
const detachedDepth = p.getColorDepth, detachedHas = p.hasColors;
for (const value of ['', '0','1','2','3','true','false',true,false,0,1,2,3,null,{},undefined]) {
  record(`force:${String(value)}:${typeof value}`, () => ({depth: detachedDepth({FORCE_COLOR:value}), has: detachedHas(16,{FORCE_COLOR:value})}));
}
for (const count of [null,true,'16',()=>16,NaN,Infinity,1,2,2.5,16,256,16777216,9007199254740991,9007199254740992,16n,Symbol('count')]) {
  record(`count:${String(count)}:${typeof count}`, () => detachedHas(count,{FORCE_COLOR:'3'}));
}
record('null-env-throws', () => detachedDepth(null));
record('object-overload', () => detachedHas({FORCE_COLOR:'2'}));
record('function-not-object-overload', () => detachedHas(function env(){}));
record('force-getter-reloaded', () => {
  const trace=[]; let index=0;
  const env = new Proxy({get FORCE_COLOR(){ trace.push('force-body'); return ++index===1 ? 'present' : '2'; }}, {get(target,key,receiver){trace.push(String(key));return Reflect.get(target,key,receiver)}});
  return {depth: detachedDepth(env), trace};
});
const platform = Object.getOwnPropertyDescriptor(process,'platform');
try {
  // Deterministic Source branch controls, separate from actual OS controls.
  Object.defineProperty(process,'platform',{...platform,value:'linux'});
  for (const env of [{},{TMUX:1},{CI:''},{CI:0,CIRCLECI:''},{CI:true,GITHUB_ACTIONS:false},{TF_BUILD:'',AGENT_NAME:''},{TEAMCITY_VERSION:'9.01.2'},{TEAMCITY_VERSION:'9.0.2'},{TEAMCITY_VERSION:'10.0'},{TERM_PROGRAM:'iTerm.app',TERM_PROGRAM_VERSION:'2.9'},{TERM_PROGRAM:'iTerm.app',TERM_PROGRAM_VERSION:'3.0'},{TERM_PROGRAM:'MacTerm'},{TERM_PROGRAM:'Apple_Terminal'},{COLORTERM:'truecolor'},{COLORTERM:'24bit'},{TERM:'xterm-256color'},{TERM:'linux'},{TERM:'rxvt-unicode-24bit'},{TERM:'constructor'},{TERM:'toString'},{TERM:'dumb',TMUX:1},{NO_COLOR:'',TERM:'xterm'},{NO_COLOR:'1',TERM:'xterm'}]) {
    record(`env:${JSON.stringify(env)}`, () => ({depth:representation(detachedDepth(env)),has:detachedHas(16,env)}));
  }
  record('ci-descriptor-presence-order', () => {
    const trace=[];const env=new Proxy({CI:'',APPVEYOR:'',CIRCLECI:''},{get(t,k,r){trace.push(['get',String(k)]);return Reflect.get(t,k,r)},getOwnPropertyDescriptor(t,k){trace.push(['own',String(k)]);return Reflect.getOwnPropertyDescriptor(t,k)},has(t,k){trace.push(['in',String(k)]);return Reflect.has(t,k)}});
    return {depth:detachedDepth(env),trace};
  });
  record('term-inherited-property-reloads', () => {
    const trace=[]; let n=0;
    Object.defineProperty(Object.prototype,'pi_tty_term',{configurable:true,get(){trace.push('inherited');return ++n===1 ? 4 : 8}});
    try { return {depth:detachedDepth({TERM:'pi_tty_term'}),trace}; }
    finally { delete Object.prototype.pi_tty_term; }
  });
  record('term-table-source-property-order', () => {
    const trace=[];
    Object.defineProperty(Object.prototype,'pi_tty_order',{configurable:true,get(){trace.push(Object.keys(this));return 4}});
    try { return {depth:detachedDepth({TERM:'pi_tty_order'}),trace}; }
    finally { delete Object.prototype.pi_tty_order; }
  });
} finally { Object.defineProperty(process,'platform',platform); }
const reason={};
record('exact-env-throw-identity', () => {try{detachedDepth({get FORCE_COLOR(){throw reason}})}catch(e){return e===reason}});
record('isatty-no-object-coercion', () => {let calls=0;return {value:tty.isatty({valueOf(){calls++;return 1}}),calls}});
for(const fd of [-1,1.5,'1',undefined,null,true,2147483648,Symbol('fd'),1n]) {
  record(`ReadStream-invalid:${String(fd)}`, () => tty.ReadStream(fd));
  record(`WriteStream-invalid:${String(fd)}`, () => new tty.WriteStream(fd));
}
record('constructor-coercion-before-invalid-fd', () => {let calls=0;try{tty.WriteStream({valueOf(){calls++;throw reason}})}catch(e){return {same:e===reason,calls}}});
record('window-method-live-get-order', () => {const trace=[];return {value:p.getWindowSize.call({get columns(){trace.push('columns');return 0},get rows(){trace.push('rows');return 12}}),trace}});
record('setRawMode-absent-handle', () => {const receiver={};const result=tty.ReadStream.prototype.setRawMode.call(receiver,1);return {same:result===receiver,isRaw:receiver.isRaw}});
record('refresh-size-real-method-protocol', () => {
  const trace=[];const receiver={get columns(){trace.push('old-cols');return 1},set columns(value){trace.push(['columns',value])},get rows(){trace.push('old-rows');return 2},set rows(value){trace.push(['rows',value])},get _handle(){trace.push('handle');return {getWindowSize(array){trace.push('getWindowSize');array[0]=0;array[1]=3;return 0}}},emit(...args){trace.push(args)}};
  return {value:representation(p._refreshSize.call(receiver)),trace};
});
// A separate fresh process is needed for warning-once and lazy OS-release cache
// controls; see warning-and-cache.mjs. No real fd is opened by this program.
process.stdout.write(JSON.stringify(rows,(key,value)=> typeof value==='function' ? {type:'function',name:value.name} : value)+'\n');
