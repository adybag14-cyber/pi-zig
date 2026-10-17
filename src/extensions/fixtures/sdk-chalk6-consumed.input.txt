// Authored caller inputs only. Run with the actual Chalk6 default or the private
// native supplier; outputs must be captured from Source, never hand-authored.
export function runChalkConsumedCases(chalk) {
 const observations=[];
 const record=(id,value)=>observations.push({id,value});
 const make=options=>chalk.constructor(options);
 const samples=[['empty',''],['plain','warning'],['lf','a\nb'],['crlf','a\r\nb'],['bare-cr','a\rb'],['existing-close','a\x1b[39mb'],['double-close','\x1b[39mx\x1b[39m'],['other-sgr','\x1b[22mx\x1b[0m'],['unicode','\ufeff雪\ud800\udc00\udfff\u0000'],['line-edge','\nx\n'],['crlf-edge','\r\nx\r\n']];
 for(const level of [0,1,2,3])for(const [label,text] of samples){const root=make({level});record(`style/${level}/${label}`,root.yellow(text));}
 for(const level of [0,1,2,3]){
  const root=make({level});
  record(`root-call/${level}`,{zero:root(),one:root(undefined),two:root(null,2),many:root('a',null,undefined,3)});
  record(`builder-call/${level}`,{zero:root.yellow(),one:root.yellow(undefined),two:root.yellow(null,2),many:root.yellow('a',null,undefined,3)});
  record(`nested/${level}`,root.yellow.yellow('a\x1b[39mb\r\nc'));
 }
 {
  const root=make({level:1}),before=Object.getOwnPropertyDescriptor(root,'yellow'),first=root.yellow,after=Object.getOwnPropertyDescriptor(root,'yellow');
  const proto=Object.getPrototypeOf(root),builderProto=Object.getPrototypeOf(first),rootLevel=Object.getOwnPropertyDescriptor(proto,'level'),builderLevel=Object.getOwnPropertyDescriptor(builderProto,'level');
  record('descriptors',{type:typeof root,name:root.name,length:root.length,constructor:root.constructor.name,constructorLength:root.constructor.length,rootKeys:Object.keys(root),beforeAbsent:before===undefined,cached:first===root.yellow,styleFlags:{writable:after.writable,enumerable:after.enumerable,configurable:after.configurable},rootLevel:{enumerable:rootLevel.enumerable,configurable:rootLevel.configurable,getName:rootLevel.get.name,setName:rootLevel.set.name},builderLevel:{enumerable:builderLevel.enumerable,configurable:builderLevel.configurable},builderName:first.name,builderLength:first.length,builderPrototypeCallable:typeof builderProto,prototypeName:builderProto.name,prototypeLength:builderProto.length});
 }
 {
  const root=make({level:1}),builder=root.yellow;root.level=0;const disabled=builder('x');builder.level=3;record('live-level',{disabled,enabled:builder('x'),root:root.level,builder:builder.level});
 }
 {
  const trace=[],options={get level(){trace.push('level');return 2;}};const root=make(options);record('factory-option-read-order',{trace,level:root.level});
 }
 {
  const marker={},trace=[];let n=0,raw=false;try{make({get level(){trace.push(++n);if(n===2)throw marker;return 1;}})}catch(error){raw=error===marker}record('factory-option-raw-throw',{trace,raw});
 }
 {
  let n=0;const root=make({get level(){return ++n===4?'unvalidated-final-value':1;}});record('factory-live-final-value',{reads:n,level:root.level});
 }
 for(const [label,value] of [['negative',-1],['too-high',4],['fraction',1.5],['NaN',NaN],['infinity',Infinity],['string','1'],['undefined',undefined],['null',null],['bigint',1n]]){
  const root=make({level:1});let got;try{root.level=value;got={threw:false}}catch(error){got={name:error.name,message:error.message,retained:root.level}}record(`invalid-level/${label}`,got);
 }
 for(const kind of ['root','single','two','many']){
  const root=make({level:0}),trace=[],first={[Symbol.toPrimitive](hint){trace.push('first:'+hint);return 'A'}},second={[Symbol.toPrimitive](hint){trace.push('second:'+hint);return 'B'}};
  const output=kind==='root'?root(first,second):kind==='single'?root.yellow(first):kind==='two'?root.yellow(first,second):root.yellow(first,second,first);record(`coercion/${kind}`,{trace,output});
 }
 for(const kind of ['root','single','two','many']){
  const root=make({level:1}),marker={},trace=[],value={[Symbol.toPrimitive](hint){trace.push(hint);throw marker}};let raw=false;try{if(kind==='root')root(value);else if(kind==='single')root.yellow(value);else if(kind==='two')root.yellow('x',value);else root.yellow('x','y',value)}catch(error){raw=error===marker}record(`coercion-raw-throw/${kind}`,{trace,raw});
 }
 {
  const root=make({level:1}),builder=root.yellow,trace=[];Object.defineProperty(root,'level',{get(){trace.push('public-level');return 0},configurable:true});const paint=builder('x');const visible=builder.level;record('symbol-level-versus-public-getter',{paint,visible,trace});
 }
 {
  const root=make({level:1}),builder=root.yellow,levelSymbol=Reflect.ownKeys(root).find(key=>typeof key==='symbol'&&key.description==='LEVEL'),marker={};let raw=false,coerced=false;
  Object.defineProperty(root,levelSymbol,{get(){throw marker},configurable:true});try{builder({[Symbol.toPrimitive](){coerced=true;return 'x'}})}catch(error){raw=error===marker}record('raw-symbol-level-getter',{raw,coerced});
 }
 {
  const root=make({level:1}),trace=[],restore={includes:String.prototype.includes,indexOf:String.prototype.indexOf,slice:String.prototype.slice};let output;
  try{for(const name of Object.keys(restore))String.prototype[name]=function(...args){trace.push([name,...args]);return Reflect.apply(restore[name],this,args)};output=root.yellow('a\x1b[39mb\r\nc')}
  finally{for(const name of Object.keys(restore))String.prototype[name]=restore[name]}
  record('live-string-method-order',{output,trace});
 }
 for(const method of ['includes','indexOf','slice']){
  const root=make({level:1}),marker={},original=String.prototype[method];let raw=false;try{String.prototype[method]=function(){throw marker};root.yellow('a\x1b[39mb\nc')}catch(error){raw=error===marker}finally{String.prototype[method]=original}record(`live-string-raw/${method}`,raw);
 }
 {
  const root=make({level:0}),trace=[],marker={},bad={[Symbol.toPrimitive](){trace.push('coerce');throw marker}};let raw=false;try{root.yellow(bad)}catch(error){raw=error===marker}record('disabled-still-coerces',{trace,raw});
 }
 {
  const root=make({level:1}),builder=root.yellow;let constructible=true;try{Reflect.construct(builder,[])}catch(error){constructible=error.name!=='TypeError'}record('arrow-receiver-and-constructor',{receiverIgnored:builder.call({level:0},'x')===builder('x'),constructible});
 }
 return observations;
}