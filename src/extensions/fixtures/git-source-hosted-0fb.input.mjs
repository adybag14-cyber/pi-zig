// Prepared original parser/used dependency projection observations. No expected
// results; the Source runner supplies actual imports and an isolated module.
const {parseGitUrl,hosted,nodeUrl}=GitAPI,rows=[];
const inputs=[
 'git:owner/repo','owner/repo',' git: github.com/owner/repo@main ',
 'https://github.com/owner/repo.git','https://github.com/owner/repo@branch/sub',
 'git:git@github.com:owner/repo.git@main','git:github:owner/repo#tag',
 'git:gitlab:group/sub/repo#branch','https://gitlab.com/group/sub/repo.git#branch',
 'https://bitbucket.org/owner/repo.git#tag','https://bitbucket.org/owner/repo/get/tag',
 'git:gist:abcdef','https://gist.github.com/owner/abcdef','https://gist.github.com/abcdef',
 'https://gist.github.com/owner/abcdef/raw','git:sourcehut:~owner/repo',
 'https://git.sr.ht/~owner/repo#main','ssh://git@git.sr.ht/~owner/repo',
 'https://github.com/owner/repo/tree/main','https://github.com/owner/repo/issues/1',
 'https://www.github.com/owner/repo','http://github.com/owner/repo',
 'git+https://github.com/owner/repo','git:git+https://github.com/owner/repo',
 'git:https://example.org/owner/repo@tag','git:example.org/owner/repo@tag',
 'git:localhost/owner/repo','git:barehost/owner/repo','git:git@self.host:owner/repo@tag',
 'https://example.org/owner/repo.git','ssh://user:password@example.org/owner/repo@main',
 'git:github.com/owner/repo@','git:github.com/owner/repo#topic@1',
 'git:github.com/owner/%2e%2e/repo','git:github.com/%2fowner/repo',
 'git:github.com/owner/repo%5cchild','git:github.com/owner/repo%00',
 'git:github.com/owner/%ZZ','git:github.com/owner/%FF','git:github.com/owner/%252e%252e',
 'GIT://github.com/owner/repo','git:HTTPS://example.org/owner/repo','git:','',
];
for(const source of inputs){try{rows.push({name:`parse-${rows.length}`,source,result:parseGitUrl(source)})}catch(error){rows.push({name:`parse-${rows.length}`,source,error:{name:error?.name,message:error?.message}})}}
const project=info=>info&&({domain:info.domain,user:info.user,project:info.project,committish:info.committish});
for(const source of ['github:owner/repo#main','gitlab:group/sub/repo#branch','gist:abcdef','sourcehut:~owner/repo','git@bitbucket.org:owner/repo.git','https://github.com/owner/repo/tree/main'])rows.push({name:`hosted-${source}`,source,result:project(hosted.fromUrl(source))});
{
 const source='https://github.com/cache-probe/repo',first=hosted.fromUrl(source),second=hosted.fromUrl(source);
 rows.push({name:'successful-cache-identity',same:first===second,result:project(second)});
}
{
 const descriptor=Object.getOwnPropertyDescriptor(nodeUrl,'URL'),original=nodeUrl.URL,trace=[];
 try{Object.defineProperty(nodeUrl,'URL',{configurable:true,get(){trace.push('node:url.URL');return original}});for(let i=0;i<2;i++)hosted.fromUrl('https://github.com/');rows.push({name:'undefined-result-is-not-negative-cached',trace});}
 finally{Object.defineProperty(nodeUrl,'URL',descriptor)}
}
{
 const descriptor=Object.getOwnPropertyDescriptor(globalThis,'JSON'),original=JSON,trace=[],source='github:json-cache-probe/repo';
 try{Object.defineProperty(globalThis,'JSON',{configurable:true,get(){trace.push('JSON');return original}});hosted.fromUrl(source);hosted.fromUrl(source);rows.push({name:'JSON-stringify-resolved-on-cache-hit',trace})}
 finally{Object.defineProperty(globalThis,'JSON',descriptor)}
}
{
 const original=globalThis.Boolean,trace=[];
 try{globalThis.Boolean=function(value){trace.push(typeof value);return original(value)};const result=parseGitUrl('git:github.com/boolean-probe/repo@main');rows.push({name:'live-Boolean-filter-and-pinned',result,trace})}
 finally{globalThis.Boolean=original}
}
{
 const source='github:lru-probe/old',first=hosted.fromUrl(source);for(let i=0;i<999;i++)hosted.fromUrl(`github:lru-probe/item${i}`);const retained=hosted.fromUrl(source);hosted.fromUrl('github:lru-probe/final');const promoted=hosted.fromUrl(source);for(let i=0;i<1000;i++)hosted.fromUrl(`github:lru-probe/replacement${i}`);const replaced=hosted.fromUrl(source);
 rows.push({name:'max-1000-LRU-hit-promotes-and-eviction-reparses',retained:first===retained,promoted:first===promoted,replaced:first!==replaced});
}
globalThis.gitSourceHostedRows=rows;globalThis.gitSourceHostedComplete=true;
