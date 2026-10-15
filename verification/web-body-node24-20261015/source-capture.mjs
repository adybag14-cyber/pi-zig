import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const[output,inputPath,authorityPath,frozenPath]=process.argv.slice(2);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex'),fileHash=path=>hash(readFileSync(path));
const frozenHash=fileHash(frozenPath);
function verify(){if(fileHash(frozenPath)!==frozenHash)throw Error('Frozen registry drift');return JSON.parse(readFileSync(frozenPath,'utf8')).map(manifest=>{if(fileHash(manifest.path)!==manifest.sha256.toLowerCase())throw Error('Manifest drift '+manifest.path);const records=JSON.parse(readFileSync(manifest.path,'utf8'));for(const row of records)if(fileHash(row.path)!==row.sha256.toLowerCase())throw Error('Frozen input drift '+row.path);return{name:manifest.name,count:records.length,drift:0}})}
const before=verify(),bundled=process.binding('natives')['internal/deps/undici/undici'];
if(typeof bundled!=='string'||typeof Response!=='function'||typeof Request!=='function'||typeof ReadableStream!=='function'||typeof gc!=='function')throw Error('Actual Node Web authority unavailable');
writeFileSync(authorityPath,bundled);
let gcCalls=0;globalThis.collectWebBodyGarbage=async()=>{for(let i=0;i<3;i++){await new Promise(resolve=>setImmediate(resolve));gc();gcCalls++}await new Promise(resolve=>setImmediate(resolve))};
const input=readFileSync(inputPath);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(webBodyRows.length<160)throw Error('Actual Request Response BodyMixin inventory too small');
writeFileSync(output,JSON.stringify({authority:'Actual global Request Response BodyMixin from pinned Node v24.14.0 bundled Undici; actual public ReadableStream Blob File FormData AbortSignal dependencies',actualNode:{version:process.version,path:process.execPath,sha256:fileHash(process.execPath),undici:process.versions.undici,execArgv:process.execArgv},bundledUndici:{path:authorityPath,sha256:fileHash(authorityPath),bytes:Buffer.byteLength(bundled)},inputSha256:hash(input),cases:webBodyRows.length,actualGcCalls:gcCalls,before,after:verify(),rows:webBodyRows},null,2));
