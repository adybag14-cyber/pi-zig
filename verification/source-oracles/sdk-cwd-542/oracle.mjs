// TEST-ONLY: execute unchanged original production resolvePath, never native backend code.
import {readFileSync,writeFileSync,createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {dirname,resolve,sep} from 'node:path';
const root=dirname(fileURLToPath(import.meta.url));
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase();
const manifestFile=resolve(root,'SOURCE-MANIFEST.json'),manifest=JSON.parse(readFileSync(manifestFile,'utf8'));
if(manifest.schema!=='sdk-original-path-source-542-v1'||manifest.source!=='ea448f454af474f3e2fe9733b331e17b0662f5d6')throw Error('Source authority mismatch');
for(const entry of manifest.files){const path=resolve(root,entry.path);if(!path.startsWith(root+sep)||sha(path)!==entry.sha256)throw Error('Original Source/dependency drift: '+entry.path)}
const sdkText=readFileSync(resolve(root,'upstream/sdk.ts.reference.txt'),'utf8');
const factoryExpression='const cwd = resolvePath(options.cwd ?? options.sessionManager?.getCwd() ?? process.cwd());';
if(sha(resolve(root,'upstream/sdk.ts.reference.txt'))!=='61F398403C7510BEC849583B2C46272DF11AC5AA8D2E24B4DED97A108DD55B28'||!sdkText.includes(factoryExpression))throw Error('Original factory resolvePath call differs');
if(sha(resolve(root,'upstream/paths.ts.reference.txt'))!=='64C3EBEF724FA21ED0042E127908B4323A5D2F1B8AAA91EEE550442332FE8502')throw Error('Original TypeScript path helper differs');
const {resolvePath}=await import('./upstream/paths.js');
const inputs=[
 {id:'command-actions/default-actions',input:'/sdk-command-actions/default-actions',capturedWindows:String.raw`C:\sdk-command-actions\default-actions`},
 {id:'normalized-options/metadata-and-copy',input:'/sdk-normalized-options/metadata-and-copy',capturedWindows:String.raw`C:\sdk-normalized-options\metadata-and-copy`},
 {id:'normalized-options/empty-metadata',input:'/sdk-normalized-options/empty-metadata',capturedWindows:String.raw`C:\sdk-normalized-options\empty-metadata`},
];
const records=inputs.map(entry=>({...entry,resolved:resolvePath(entry.input)}));
const nodeHash=createHash('sha256');for await(const part of createReadStream(process.execPath))nodeHash.update(part);
const output={schema:'sdk-source-cwd-oracle-542-v1',source:manifest.source,sdkSha256:sha(resolve(root,'upstream/sdk.ts.reference.txt')),pathsTsSha256:sha(resolve(root,'upstream/paths.ts.reference.txt')),pathsJsSha256:sha(resolve(root,'upstream/paths.js')),childProcessJsSha256:sha(resolve(root,'upstream/child-process.js')),manifestSha256:sha(manifestFile),factoryExpression,node:{version:process.versions.node,platform:process.platform,arch:process.arch,executable:process.execPath,sha256:nodeHash.digest('hex').toUpperCase()},cwd:process.cwd(),records};
const text=JSON.stringify(output,null,2)+'\n';if(process.argv[2])writeFileSync(process.argv[2],text);else process.stdout.write(text);
