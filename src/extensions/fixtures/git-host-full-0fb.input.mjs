// Prepared genuine pinned GitHost observations. No expected results.
const {hosted}=GitAPI,rows=[];
const observe=(name,operation)=>{try{rows.push({name,result:operation()})}catch(error){rows.push({name,error:{name:error?.name,message:error?.message}})}};
const descriptor=object=>Object.getOwnPropertyNames(object).map(name=>{const d=Object.getOwnPropertyDescriptor(object,name),value=d.value;return {name,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,kind:typeof value,functionName:typeof value==='function'?value.name:undefined,length:typeof value==='function'?value.length:undefined,ownPrototype:typeof value==='function'?Object.hasOwn(value,'prototype'):undefined}});
observe('full-class-descriptors',()=>({name:hosted.name,length:hosted.length,own:descriptor(hosted),prototype:descriptor(hosted.prototype)}));
const sources=['github:owner/full-repo#topic/a','bitbucket:owner/full-repo#topic/a','gitlab:group/sub/full-repo#topic/a','gist:owner/abcdef#topic/a','sourcehut:~owner/full-repo#topic/a'];
const methods=[['hash',[]],['ssh',[{noGitPlus:true}]],['sshurl',[{noGitPlus:true}]],['browse',['a b.js','Frag / Name',{noGitPlus:true}]],['browseFile',['a b.js','Frag / Name',{noGitPlus:true}]],['docs',[{}]],['bugs',[{}]],['https',[{noGitPlus:true}]],['git',[{}]],['shortcut',[{}]],['path',[{}]],['tarball',[{noCommittish:true}]],['file',['a b.js',{noGitPlus:true}]],['edit',['a b.js',{}]],['getDefaultRepresentation',[]],['toString',[{noGitPlus:true}]]];
for(const source of sources){
 const instance=hosted.fromUrl(source);
 observe(`instance-shape-${source}`,()=>({keys:Object.keys(instance),ownKeys:Reflect.ownKeys(instance).map(String),instanceOf:instance instanceof hosted,prototype:Object.getPrototypeOf(instance)===hosted.prototype,values:{domain:instance.domain,type:instance.type,user:instance.user,auth:instance.auth,project:instance.project,committish:instance.committish,default:instance.default,opts:instance.opts}}));
 for(const [name,args] of methods)observe(`${source}-${name}`,()=>Reflect.apply(instance[name],instance,args));
 for(const name of Object.keys(instance).filter(name=>name.endsWith('template'))){
  const trace=[],values={domain:'host.test',user:'u ser',auth:'user:pass',project:'project',committish:'topic/a',treepath:'tree',blobpath:'blob',editpath:'edit',path:'path / file.js',fragment:'Fragment / Name',type:'custom',hashformat:value=>String(value).toLowerCase().replaceAll(' ','-')};
  const input=new Proxy(values,{get(target,key,receiver){trace.push(String(key));return Reflect.get(target,key,receiver)}});
  observe(`template-getters-${source}-${name}`,()=>({value:instance[name](input),trace}));
 }
}
{
 const original=Object.assign,trace=[];
 try{Object.assign=function(target,host,fields){if(fields?.type){trace.push({hostKeys:Object.keys(host),fields:Object.keys(fields),targetKeys:Object.keys(target),instanceOf:target instanceof hosted});}return Reflect.apply(original,this,arguments)};const instance=hosted.fromUrl('github:constructor-observation/first');rows.push({name:'constructor-real-Object-assign-argument-shape',trace,keys:Object.keys(instance)})}
 finally{Object.assign=original}
}
{
 const original=Object.assign,trace=[];let nested,entered=false;
 try{Object.assign=function(target,host,fields){if(fields?.project==='reentry'&&!entered){entered=true;nested=hosted.fromUrl('github:constructor-observation/reentry');trace.push('nested')}return Reflect.apply(original,this,arguments)};const outer=hosted.fromUrl('github:constructor-observation/reentry'),cached=hosted.fromUrl('github:constructor-observation/reentry');rows.push({name:'constructor-reentry-cache-update',trace,distinct:nested!==outer,cached:cached===outer})}
 finally{Object.assign=original}
}
{
 const trace=[],fake={get sshtemplate(){trace.push('sshtemplate');return ()=>''}};
 observe('private-fill-brand-before-template-getter',()=>{let caught;try{hosted.prototype.ssh.call(fake)}catch(error){caught=error};return {trace,error:{name:caught?.name,message:caught?.message}}});
}
{
 class Child extends hosted{};const instance=new Child('github','owner',null,'subclass','tag','https');observe('subclass-real-brand-ownkeys',()=>({child:instance instanceof Child,base:instance instanceof hosted,keys:Reflect.ownKeys(instance).map(String),url:instance.https()}));
}
for(const manifest of [{repository:'git+https://github.com/manifest/repo.git'},{repository:{url:'https://example.test/owner/repo.git'}},{repository:'https://example.test/owner/repo.git'},null,{},()=>{}])observe(`from-manifest-${rows.length}`,()=>{const result=hosted.fromManifest(manifest);return typeof result==='string'||result==null?result:{domain:result.domain,user:result.user,project:result.project,committish:result.committish,default:result.default}});
{
 const trace=[],instance=hosted.fromUrl('github:options-observation/repo#main'),opts={get path(){trace.push('path');return '/owned'},get noCommittish(){trace.push('noCommittish');return true},get noGitPlus(){trace.push('noGitPlus');return true}};
 observe('fill-spread-getter-order-and-options',()=>({value:instance.https(opts),trace}));
}
{
 const host={protocols:['https:'],domain:'custom.host',sshtemplate:()=> 'custom-ssh',httpstemplate:({user,project})=>`custom:${user}/${project}`,extract:url=>({user:'group',project:url.pathname.slice(1),committish:url.hash.slice(1)})};
 hosted.addHost('custom',host);observe('live-addHost-constructor-and-template',()=>{const result=hosted.fromUrl('https://custom.host/repo#ref');return {type:result.type,user:result.user,project:result.project,https:result.https(),ssh:result.ssh()}});
}
{
 const descriptor=Object.getOwnPropertyDescriptor(Object.prototype,'ref'),trace=[];
 try{Object.defineProperty(Object.prototype,'ref',{configurable:true,get(){const value=`branch-${trace.length+1}`;trace.push(value);return value}});observe('Pi-parser-live-inherited-split-ref-reads',()=>({result:GitAPI.parseGitUrl('https://github.com/ref-observation/repo'),trace}))}
 finally{if(descriptor)Object.defineProperty(Object.prototype,'ref',descriptor);else delete Object.prototype.ref}
}
globalThis.gitHostFullRows=rows;globalThis.gitHostFullComplete=true;
globalThis.gitSourceHostedRows=rows;globalThis.gitSourceHostedComplete=true;
