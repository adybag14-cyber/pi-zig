// Supplementary independent-review cases. Neither earlier input is changed.
const ignore=globalThis.nativeIgnore7;
export const observations=[];
function record(name,fn){try{observations.push({name,result:fn()})}catch(error){observations.push({name,error:{name:error?.name,message:error?.message}})}}
function scan(pattern,paths){const ig=ignore().add(pattern),rule=ig._rules._rules[0];return {rules:ig._rules._rules.length,body:rule?.body,prefix:rule?.regexPrefix,source:rule?.regex.source,paths:paths.map(path=>({path,ignored:ig.ignores(path)}))}}
record('ordinary-three-final-backslashes',()=>scan('foo'+'\\'.repeat(3),['foo\\undefined','foo/undefined','foo"\\undefined']));
record('ordinary-five-final-backslashes',()=>scan('foo'+'\\'.repeat(5),['foo\\\\undefined','foo/undefined','foo"\\\\undefined']));
record('wildcard-three-final-backslashes',()=>scan('*'+'\\'.repeat(3),['a"\\undefined','a"/undefined','a"\\\\undefined','a\u0000\\undefined']));
record('changing-pattern-getter-final-backslash',()=>{let reads=0;const value={get pattern(){return ++reads===1?'checked':'foo\\'},mark:'changed'};return {result:scan(value,['fooundefined','foo','foo/undefined']),reads}});
record('changing-pattern-getter-range-end',()=>{let reads=0;const value={get pattern(){return ++reads===1?'checked':'[a-\\'}};return {result:scan(value,['a','-','\\']),reads}});
record('changing-pattern-getter-bracket-escape-end',()=>{let reads=0;const value={get pattern(){return ++reads===1?'checked':'[a\\'}};return {result:scan(value,['a','[a','\\']),reads}});
record('reflected-group-final-escape',()=>{const Constructor=ignore().add('foo').test('foo').rule.constructor;return new Constructor('group',undefined,'group',false,false,'(\\').regex.source});
record('reflected-class-final-escape',()=>{const Constructor=ignore().add('foo').test('foo').rule.constructor;return new Constructor('class',undefined,'class',false,false,'[\\').regex.source});
record('recursive-parent-null',()=>{const ig=ignore(),original=ig._t,trace=[];ig._t=function(path,cache,unignored){trace.push(path);return path==='a/'?null:original.call(this,path,cache,unignored)};return {result:ig.test('a/b'),trace,cacheKeys:Object.keys(ig._testCache)}});
record('recursive-parent-false',()=>{const ig=ignore(),original=ig._t,trace=[];ig._t=function(path,cache,unignored){trace.push(path);return path==='a/'?false:original.call(this,path,cache,unignored)};return {result:ig.test('a/b'),trace,cacheKeys:Object.keys(ig._testCache)}});
record('recursive-parent-owned-result',()=>{const ig=ignore(),original=ig._t,owned={ignored:true,unignored:false,owner:'retained'};ig._t=function(path,cache,unignored){return path==='a/'?owned:original.call(this,path,cache,unignored)};const result=ig.test('a/b');return {same:result===owned,cachedSame:ig._testCache['a/b']===owned,result}});
record('checkIgnore-parent-null-still-throws',()=>{const ig=ignore();ig._t=()=>null;return ig.checkIgnore('a/b/')});
globalThis.ignore7ScannerEdgeObservations=observations;
export const cases=observations.length;
