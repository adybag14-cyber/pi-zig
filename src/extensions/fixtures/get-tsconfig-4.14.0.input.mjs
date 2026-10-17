// The subject is the actual pinned package namespace, or its native port.
// Files are prepared separately and retained at the SAME absolute root for replay.
const subject=globalThis.nativeTsconfigSubject,root=globalThis.nativeTsconfigRoot;
if(!subject||typeof subject.getTsconfig!=='function'||typeof subject.createPathsMatcher!=='function'||typeof root!=='string')throw Error('Actual subject and retained physical root required');
const rows=[];
function observe(name,run){try{rows.push({name,value:run()})}catch(error){rows.push({name,error:{name:error?.name??typeof error,message:error?.message??String(error)}})}}
for(const name of ['getTsconfig','createPathsMatcher'])observe('metadata-'+name,()=>({name:subject[name].name,length:subject[name].length,prototype:Object.hasOwn(subject[name],'prototype')}));
const searches=['simple','simple/source/value.ts','implicit','multi','placeholder','packages/consumer','conditions/consumer','conditions/wildcard','conditions/blocked','nested/consumer','cycle','missing-extends','primitive','empty','partial','escapes','bad-star','bad-target','none'];
const specifiers=['exact','@/x','@/deep/x','abc','@base/x','pkg/x','selected','#/x','partial','unmatched','./relative','../relative','.\\windows-relative','a'];
let firstSymbol;
for(const search of searches)observe('config-'+search,()=>{const value=subject.getTsconfig(root+'/'+search);if(value===null)return null;const symbols=Object.getOwnPropertySymbols(value.config.compilerOptions),markers=symbols.map(symbol=>({description:symbol.description,value:value.config.compilerOptions[symbol],descriptor:Object.getOwnPropertyDescriptor(value.config.compilerOptions,symbol)}));if(symbols.length&&!firstSymbol)firstSymbol=symbols[0];return{path:value.path,config:value.config,markers,sameImplicitSymbol:symbols.length?symbols[0]===firstSymbol:null}});
for(const search of searches)observe('matcher-'+search,()=>{const value=subject.getTsconfig(root+'/'+search);if(!value)return null;const matcher=subject.createPathsMatcher(value);if(!matcher)return null;return{metadata:{name:matcher.name,length:matcher.length,prototype:Object.hasOwn(matcher,'prototype')},matches:specifiers.map(specifier=>({specifier,paths:matcher(specifier)}))}});
observe('fresh-configs-not-cached-mutable',()=>{const a=subject.getTsconfig(root+'/simple');a.config.compilerOptions.baseUrl='changed';const b=subject.getTsconfig(root+'/simple');return{different:a!==b&&a.config!==b.config,baseUrl:b.config.compilerOptions.baseUrl}});
observe('matcher-captures-before-config-mutation',()=>{const result=subject.getTsconfig(root+'/simple'),matcher=subject.createPathsMatcher(result);result.config.compilerOptions.paths.exact=['./changed'];result.config.compilerOptions.baseUrl='changed';return matcher('exact')});
globalThis.nativeTsconfigObservation={root,count:rows.length,rows};
