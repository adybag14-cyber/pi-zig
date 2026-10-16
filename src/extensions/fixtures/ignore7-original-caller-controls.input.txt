// Authored original callers, shared byte-for-byte by genuine ignore7 and native.
// No library implementation and no expected output appears in this file.
const ignore=globalThis.nativeIgnore7;
export const observations=[];
function record(name,fn){try{observations.push({name,result:fn()})}catch(error){observations.push({name,error:{name:error?.name,message:error?.message}})}}
const sets=[
 ['literal',['foo']],
 ['root',['/foo']],
 ['slash',['foo/bar']],
 ['directory',['foo/']],
 ['extension',['*.js']],
 ['question',['a?c']],
 ['ordinary-stars',['a**b']],
 ['leading-globstar',['**/foo']],
 ['repeated-leading-globstar',['**/**/foo/bar']],
 ['middle-globstar',['a/**/b']],
 ['trailing-globstar',['a/**']],
 ['trailing-globstar-directory',['a/**/']],
 ['trailing-segment-star',['a/*']],
 ['escaped-star',['a\\*']],
 ['escaped-question',['a\\?']],
 ['escaped-hash',['\\#secret']],
 ['escaped-exclamation',['\\!secret']],
 ['blank-comment-tab',['','#comment','   ','\t']],
 ['trailing-spaces',['foo   ']],
 ['escaped-trailing-space',['foo\\ ']],
 ['quoted-letters',['\\d\\1']],
 ['bracket-members',['[abc].js']],
 ['bracket-negated',['[!a].js']],
 ['bracket-caret',['[^a].js']],
 ['bracket-leading-close',['[]a].js']],
 ['bracket-posix',['[[:digit:]].js']],
 ['bracket-punct',['[[:punct:]]']],
 ['bracket-unknown',['[[:unknown:]].js']],
 ['bracket-reversed-range',['[c-a].js']],
 ['escaped-bracket',['\\[foo]']],
 ['bracket-slash-range',['[.-0]']],
 ['unterminated-bracket',['foo[abc']],
 ['trailing-backslashes',['foo\\','bar\\\\']],
 ['ancestor-stays-excluded',['foo/','!foo/keep.js']],
 ['child-can-return',['foo/*','!foo/keep.js']],
 ['last-rule-wins',['*.js','!keep.js','keep.js']],
 ['negative-only',['!foo']],
 ['bom',['\ufefffoo']],
 ['tab-and-crlf',['foo\t','x\r\n']],
 ['unicode-and-surrogate',['é?😀*','\ud800*']],
 ['literal-brace-and-hidden',['a{b,c}','.git']],
 ['pinned-wildcard-run',['*a*b*c*d*e*f*z']],
];
const paths=[
 'foo','foo/','foo/bar','foo/bar/','foo/bar/x','foo/keep.js','foo/drop.js',
 'a','a/','a/b','a/b/','a/x/b','a/x/y/b','a/x/','a/b/c.js',
 'foo.js','.js','a.js','b.js','c.js','9.js','].js','keep.js','other/keep.js',
 'a*c','a*','a?','abc','ac','a{b,c}','#secret','!secret','foo ','foo  ',
 'd1','[foo]','foo[abc','bar\\','foo\t','\t','x','.',
 'other/foo','other/foo/','other/foo/bar','a//b','éx😀tail','\ud800tail',
 '.git','.git/config','-', '/', '0', 'aaaaaaaaaaaaaaaaaaaaaaaaaf',
];
for(const [name,patterns] of sets){
 const ig=ignore();const returned=ig.add(patterns);
 record(name+':add-identity',()=>returned===ig);
 for(const path of paths)record(name+':'+JSON.stringify(path),()=>({ignores:ig.ignores(path),test:ig.test(path),checkIgnore:ig.checkIgnore(path)}));
}
record('factory-shape',()=>({name:ignore.name,length:ignore.length,defaultSame:ignore.default===ignore,hasPrototype:Object.hasOwn(ignore,'prototype'),className:ignore().constructor.name}));
record('case-default',()=>['FOO','foo','sub/FoO'].map(path=>ignore().add('foo').ignores(path)));
record('case-sensitive-upper',()=>['FOO','foo','sub/FoO'].map(path=>ignore({ignoreCase:false}).add('foo').ignores(path)));
record('case-sensitive-legacy',()=>['FOO','foo'].map(path=>ignore({ignorecase:false}).add('foo').ignores(path)));
record('case-option-precedence',()=>ignore({ignorecase:false,ignoreCase:true}).add('foo').ignores('FOO'));
record('string-lines',()=>ignore().add('foo\r\nbar\n\n#comment').filter(['foo','bar','baz']));
record('marked-rule',()=>ignore().add({pattern:'foo',mark:'source-rule'}).test('foo'));
record('matcher-add-shares-rules',()=>{const first=ignore().add({pattern:'foo',mark:'shared'});const second=ignore().add(first);return {same:second.test('foo').rule===first.test('foo').rule,result:second.test('foo')}});
record('cache-invalidation',()=>{const ig=ignore().add('*.js');const first=ig.test('keep.js');ig.add('!keep.js');return {first,after:ig.test('keep.js'),ignores:ig.ignores('keep.js')}});
record('cache-identity',()=>{const ig=ignore().add('foo/');return {same:ig.test('foo/')===ig.test('foo/'),ancestorSame:ig.test('foo/bar')===ig.test('foo/'),nullPrototype:Object.getPrototypeOf(ig._testCache)===null}});
record('filter-live-method',()=>{const ig=ignore().add('foo');const filter=ig.createFilter();ig.ignores=path=>path==='bar';return ['foo','bar'].filter(filter)});
record('addPattern-live-method',()=>{const ig=ignore();const trace=[];ig.add=function(value){trace.push([this===ig,value]);return 'replacement'};return {returned:ig.addPattern('foo'),trace}});
record('filter-sparse-array',()=>{const paths=['foo',,'bar'];const ig=ignore().add('foo');return {result:ig.filter(paths),inputLength:paths.length}});
record('array-forEach-live',()=>{const patterns=['foo'];const trace=[];patterns.forEach=function(callback,receiver){trace.push(['forEach',this===patterns,receiver._ignoreCase]);callback.call(receiver,'bar',0,this)};const ig=ignore().add(patterns);return {trace,foo:ig.ignores('foo'),bar:ig.ignores('bar')}});
record('pattern-getters',()=>{const trace=[];const pattern={get pattern(){trace.push('pattern');return 'foo'},get mark(){trace.push('mark');return 'marked'}};const ig=ignore().add(pattern);return {trace,result:ig.test('foo')}});
record('raw-pattern-error',()=>{const raw={fixture:'raw-pattern-error',toString(){throw Error('formatted raw reason')}};let thrown;try{ignore().add({get pattern(){throw raw}})}catch(error){thrown=error}return thrown===raw});
record('constructor-getters',()=>{const trace=[];const options={get ignorecase(){trace.push('ignorecase');return false},get ignoreCase(){trace.push('ignoreCase');return true},get allowRelativePaths(){trace.push('allowRelativePaths');return false}};const ig=ignore(options).add('foo');return {trace,ignored:ig.ignores('FOO')}});
for(const path of ['', '.', '..', './foo','../foo','/foo','C:/foo','C:\\foo','a\\b','\\server\\share','\\\\?\\C:\\foo','a"\\b','a\u0001\\b',null,undefined,0,42,false,{},new String('foo')]){
 record('valid:'+String(path),()=>ignore.isPathValid(path));
 record('strict:'+String(path),()=>ignore().add('foo').ignores(path));
}
for(const path of ['', '.', '..', './foo','../foo','/foo','a//b'])record('allowRelative:'+JSON.stringify(path),()=>ignore({allowRelativePaths:true}).add('foo').test(path));
record('cache-special-keys',()=>{const ig=ignore().add('__proto__');return ['__proto__','constructor','toString'].map(path=>({path,ignored:ig.ignores(path)}))});
export const matrixSets=sets.length;
export const matrixPaths=paths.length;
export const cases=observations.length;
globalThis.ignore7OriginalObservations=observations;
