// Additional genuine ordinary-object POSIX table controls; earlier inputs intact.
const ignore=globalThis.nativeIgnore7;
export const observations=[];
function record(name,fn){try{observations.push({name,result:fn()})}catch(error){observations.push({name,error:{name:error?.name,message:error?.message}})}}
function inspect(pattern){const ig=ignore().add(pattern),rule=ig._rules._rules[0];return {body:rule.body,prefix:rule.regexPrefix,source:rule.regex.source,paths:['a','q','z',']','[object Object]','function Object() { [native code] }'].map(path=>({path,ignored:ig.ignores(path)}))}}
record('inherited-constructor-class',()=>inspect('[[:constructor:]]'));
record('inherited-prototype-class',()=>inspect('[[:__proto__:]]'));
record('inherited-class-getter',()=>{const trace=[];Object.defineProperty(Object.prototype,'ownedIgnoreClass',{configurable:true,get(){trace.push([Object.hasOwn(this,'alnum'),Object.getPrototypeOf(this)===Object.prototype]);return 'q-z'}});try{return {result:inspect('[[:ownedIgnoreClass:]]'),trace}}finally{delete Object.prototype.ownedIgnoreClass}});
record('inherited-class-getter-raw-error',()=>{let formatted=0;const raw={fixture:'raw-inherited-class',toString(){formatted++;throw Error('formatted raw inherited class')}};Object.defineProperty(Object.prototype,'ownedIgnoreClassError',{configurable:true,get(){throw raw}});try{let caught;try{ignore().add('[[:ownedIgnoreClassError:]]')}catch(error){caught=error}return {same:caught===raw,formatted}}finally{delete Object.prototype.ownedIgnoreClassError}});
globalThis.ignore7PosixPrototypeObservations=observations;
export const cases=observations.length;
