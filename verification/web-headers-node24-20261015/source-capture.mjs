import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const [output,inputPath,authorityPath,frozenPath]=process.argv.slice(2);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const fileHash=path=>hash(readFileSync(path));
const frozenHash=fileHash(frozenPath);
function verify(){if(fileHash(frozenPath)!==frozenHash)throw Error('Frozen registry drift');return JSON.parse(readFileSync(frozenPath,'utf8')).map(manifest=>{if(fileHash(manifest.path)!==manifest.sha256.toLowerCase())throw Error('Manifest drift '+manifest.path);const records=JSON.parse(readFileSync(manifest.path,'utf8'));for(const row of records)if(fileHash(row.path)!==row.sha256.toLowerCase())throw Error('Frozen input drift '+row.path);return{name:manifest.name,count:records.length,drift:0}})}
const before=verify();
const bundled=process.binding('natives')['internal/deps/undici/undici'];
if(typeof bundled!=='string'||!bundled.includes('Headers'))throw Error('Actual bundled Undici source unavailable');
writeFileSync(authorityPath,bundled);
if(typeof globalThis.gc!=='function')throw Error('Actual Node GC required');
let gcCalls=0;
globalThis.collectHeadersGarbage=async()=>{for(let i=0;i<3;i++){await new Promise(resolve=>setImmediate(resolve));gc();gcCalls++}await new Promise(resolve=>setImmediate(resolve))};
const input=readFileSync(inputPath);
await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(webHeadersRows.length<180)throw Error('Actual Headers contract inventory too small');
writeFileSync(output,JSON.stringify({authority:'Actual global Headers from pinned Node v24.14.0 bundled Undici; npm undici is not substituted',actualNode:{version:process.version,path:process.execPath,sha256:fileHash(process.execPath),undici:process.versions.undici,execArgv:process.execArgv},bundledUndici:{path:authorityPath,sha256:fileHash(authorityPath),bytes:Buffer.byteLength(bundled)},inputSha256:hash(input),cases:webHeadersRows.length,actualGcCalls:gcCalls,before,after:verify(),rows:webHeadersRows},null,2));
