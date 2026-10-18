// Authored inputs only. Genuine outputs must come from installed ignore7.0.8.
export const ignore708Matrices=[
 {id:'basic',rules:['*.log','!keep.log'],paths:['error.log','keep.log','a/error.log','a/keep.log','a.log/','x.txt','.log','a/.log']},
 {id:'rooted',rules:['/root.txt'],paths:['root.txt','root.txt/','a/root.txt','a/root.txt/','root.txt.bak','ROOT.TXT','/root.txt','./root.txt']},
 {id:'directory',rules:['build/'],paths:['build','build/','build/x','a/build','a/build/','a/build/x','builder/','a/build.txt']},
 {id:'parent-blocked',rules:['a/','!a/b'],paths:['a','a/','a/b','a/c','x/a/','x/a/b','a/b/','a//b']},
 {id:'parent-reincluded',rules:['a/','!a/','a/*','!a/b'],paths:['a','a/','a/b','a/c','a/b/','a/b/c','a/x/b','x/a/b']},
 {id:'globstar-leading',rules:['**/foo/bar'],paths:['foo/bar','x/foo/bar','x/y/foo/bar','foo/x/bar','foobar','x/foo/bar/','foo/','bar']},
 {id:'globstar-middle',rules:['a/**/b'],paths:['a/b','a/x/b','a/x/y/b','a/','a/b/','x/a/b','a/x/c','a//b']},
 {id:'globstar-tail',rules:['a/**'],paths:['a','a/','a/b','a/b/','a/x/y','x/a/','a//b','a/.hidden']},
 {id:'globstar-directories',rules:['a/**/'],paths:['a','a/','a/b','a/b/','a/x/y/','a/x/y','x/a/b/','a//b/']},
 {id:'literal-escapes',rules:['\\!bang','\\#hash','literal\\*','literal\\?','\\d','\\[box]'],paths:['!bang','#hash','literal*','literalX','literal?','d','5','[box]']},
 {id:'spaces-tabs',rules:['trim   ','quoted\\ ','tab\t','   ','\t'],paths:['trim','trim ','quoted ','quoted','tab\t','tab','\t',' ']},
 {id:'bom-comment-lines',rules:['\ufeffname','#comment','','\r\n','ends\r\n'],paths:['name','\ufeffname','#comment','ends','ends\r\n','NAME','a/name','other']},
 {id:'brackets',rules:['[a-c].txt','[!a-c].bin','[]a]','[.-0]'],paths:['a.txt','C.txt','d.txt','d.bin','b.bin',']','a','/']},
 {id:'posix',rules:['[[:alpha:]].a','[[:digit:]].d','[[:space:]].s','[[:unknown:]].x'],paths:['A.a','雪.a','5.d','x.d','\t.s','\v.s','q.x','/.s']},
 {id:'out-of-order-range',rules:['[c-a]','[z-a].txt','[abc'],paths:['c','a','b','z.txt','a.txt','[abc','x','c/']},
 {id:'questions',rules:['?.txt','file??','a?b'],paths:['x.txt','.txt','ab.txt','file12','file1','a/b','acb','a雪b']},
 {id:'unicode',rules:['雪*','?.unit','😀.txt'],paths:['雪','雪山','x雪','😀.txt','\ud800.unit','😀.unit','a.unit','\udfff']},
 {id:'pinned-wildcards',rules:['*a*b*c*d','x*[0-9]*y*z'],paths:['abcd','aaabbbcccddd','abdc','a/bcd','x1yz','x12yzzz','xayz','other']},
 {id:'nul-private-markers',rules:['a\u0000b','x\ue000','\\*'],paths:['a\u0000b','ab','x\ue000','x','xyz','*','abc','a/b']},
 {id:'casefold',rules:['ReadMe','*.TS'],paths:['README','readme','a/ReadMe','x.ts','x.TS','a/X.ts','x.tsx','other']},
 {id:'literal-not-minimatch',rules:['{a,b}.txt','@(a|b)','[[]'],paths:['a.txt','b.txt','{a,b}.txt','a','@(a|b)','[','(',']']},
 {id:'trailing-backslashes',rules:['odd\\','even\\\\','a\\\\*','bad['],paths:['odd','odd\\','even','even\\','a','abc','a\\x','bad[']},
 {id:'cache-special',rules:['__proto__','constructor','toString'],paths:['__proto__','constructor','toString','hasOwnProperty','x/__proto__','x/constructor','x/toString','__proto__/child']},
];
export function runIgnore708ConsumedCases(ignore){
 const rows=[],record=(id,value)=>rows.push({id,value});
 for(const test of ignore708Matrices){
  const matcher=ignore(),returned=matcher.add(test.rules);
  record(test.id+'/rules',{returnedSelf:returned===matcher,patterns:matcher._rules._rules.map(rule=>({pattern:rule.pattern,body:rule.body,negative:rule.negative,ignoreCase:rule.ignoreCase,regexPrefix:rule.regexPrefix})),basenameCount:matcher._rules._basenameCount});
  for(let i=0;i<test.paths.length;i++){const path=test.paths[i];try{record(test.id+'/path/'+i,{path,ignored:matcher.ignores(path)})}catch(error){record(test.id+'/path/'+i,{path,error:{name:error.name,message:error.message}})}}
  record(test.id+'/lazy',matcher._rules._rules.map(rule=>({regex:rule._regex&&{source:rule._regex.source,flags:rule._regex.flags},basenameMaterialized:Object.hasOwn(rule,'_basenameOnly')})));
 }
 {
  const matcher=ignore(),first=matcher._ignoreCache;matcher.add(['#comment',' ','']);const unchanged=matcher._ignoreCache===first;
  matcher.add(['a/','!a/b']);const changed=matcher._ignoreCache!==first;matcher.ignores('a/b');const inherited=matcher._ignoreCache['a/b']===matcher._ignoreCache['a/'];
  matcher.add(['!a/','a/*','!a/b']);record('cache-invalidation',{unchanged,changed,inherited,child:matcher.ignores('a/b'),nullPrototype:Object.getPrototypeOf(matcher._ignoreCache)===null});
 }
 {
  const source=ignore().add(['*.tmp','!keep.tmp']),target=ignore();target.add(source);record('matcher-copy',{sameRule:target._rules._rules[0]===source._rules._rules[0],count:target._rules._basenameCount,ignored:target.ignores('x.tmp'),kept:target.ignores('keep.tmp')});
 }
 {
  const matcher=ignore().add(['x']),rule=matcher._rules._rules[0],marker={};let reads=0,raw=false;
  Object.defineProperty(rule,'_regex',{configurable:true,get(){if(++reads===2)throw marker;return /x/}});try{matcher.ignores('x')}catch(error){raw=error===marker}record('raw-cached-regex-second-read',{reads,raw});
 }
 {
  const matcher=ignore(),old=matcher._ignoreCache;matcher.add(new Array(3));const holesUnchanged=old===matcher._ignoreCache;matcher.add('one\r\ntwo\n#comment\n');record('string-lines-and-holes',{holesUnchanged,patterns:matcher._rules._rules.map(rule=>rule.pattern),one:matcher.ignores('one'),two:matcher.ignores('two')});
 }
 {
  const matcher=ignore(),trace=[],marker={},cache={};const receiver={get _test(){trace.push('get-test');return function(path,gotCache,flag){trace.push(['call-test',this===receiver,path,gotCache===cache,flag]);return {get ignored(){trace.push('get-ignored');return marker}}}},get _ignoreCache(){trace.push('get-cache');return cache}};
  record('live-ignores-receiver',{raw:matcher.ignores.call(receiver,'a')===marker,trace});
 }
 {
  const matcher=ignore(),trace=[],patterns=['x'],manager={get add(){trace.push('get-add');return function(value){trace.push(['call-add',this===manager,value===patterns]);return true}}};
  const receiver={get _rules(){trace.push('get-rules');return manager},get _initCache(){trace.push('get-init');return function(){trace.push(['call-init',this===receiver])}}};record('live-add-receiver',{same:matcher.add.call(receiver,patterns)===receiver,trace});
 }
 {
  const matcher=ignore(),trace=[];Object.defineProperty(matcher._rules,'_ignoreCase',{get(){trace.push('ignoreCase');return true}});
  const input={get [Symbol.for('node-ignore')](){trace.push('tag');return false},get pattern(){trace.push('pattern');return '*.tmp'},get mark(){trace.push('mark');return 'owned-mark'}};
  matcher.add([input]);record('pattern-evaluation-order',{trace,mark:matcher._rules._rules[0].mark,ignored:matcher.ignores('x.tmp')});
 }
 for(const which of ['tag','pattern','forEach','indexOf','regex-test']){
  const matcher=ignore(),marker={},savedForEach=Array.prototype.forEach,savedIndexOf=String.prototype.indexOf,savedTest=RegExp.prototype.test;let raw=false;
  try{if(which==='tag')matcher.add([{get [Symbol.for('node-ignore')](){throw marker}}]);else if(which==='pattern')matcher.add([{get pattern(){throw marker}}]);else if(which==='forEach'){Array.prototype.forEach=function(){throw marker};matcher.add(['x'])}else if(which==='indexOf'){String.prototype.indexOf=function(){throw marker};matcher.add(['x'])}else{RegExp.prototype.test=function(){throw marker};matcher.add(['x'])}}catch(error){raw=error===marker}finally{Array.prototype.forEach=savedForEach;String.prototype.indexOf=savedIndexOf;RegExp.prototype.test=savedTest}record('raw-'+which,raw);
 }
 {
  const matcher=ignore(),trace=[],original=RegExp.prototype.test;let ignored;
  try{RegExp.prototype.test=function(value){trace.push([this.source,value]);return Reflect.apply(original,this,[value])};matcher.add(['[.-0]','*.x']);ignored=matcher.ignores('a.x')}finally{RegExp.prototype.test=original}record('live-regexp-trace',{trace,ignored});
 }
 {
  const matcher=ignore().add(['a/','!a/b']);record('ordinary-shape',{name:matcher.constructor.name,constructorLength:matcher.constructor.length,ownKeys:Object.keys(matcher),symbolTag:matcher[Symbol.for('node-ignore')],factoryDefault:ignore.default===ignore,addName:matcher.add.name,addLength:matcher.add.length,ignoresName:matcher.ignores.name,ignoresLength:matcher.ignores.length});
 }
 {
  let constructible=true;try{Reflect.construct(ignore,[])}catch(error){constructible=error.name!=='TypeError'}record('default-arrow',{constructible,type:typeof ignore,name:ignore.name,length:ignore.length});
 }
 {
  const matcher=ignore().add(['*.txt']);const paths=['C:\\a.txt','C:/a.txt','a\\b.txt','a\\|b.txt','\\\\?\\C:\\a.txt','..\\a.txt','a//b.txt','a/./b.txt'];record('windows-paths',paths.map(path=>{try{return {path,ignored:matcher.ignores(path)}}catch(error){return {path,error:{name:error.name,message:error.message}}}}));
 }
 return rows;
}
