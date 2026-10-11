// TEST-ONLY actual original config path functions; no native runtime import.
import {readFileSync,writeFileSync,createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {dirname,resolve,sep} from 'node:path';
const root=dirname(fileURLToPath(import.meta.url));
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex').toUpperCase();
const manifestPath=resolve(root,'SOURCE-MANIFEST.json'),manifest=JSON.parse(readFileSync(manifestPath,'utf8'));
if(manifest.schema!=='sdk-original-doc-path-source-562-v1')throw Error('Original Source manifest schema differs');
for(const row of manifest.files){const path=resolve(root,row.path);if(!path.startsWith(root+sep)||hash(path)!==row.sha256)throw Error('Original config/dependency drift: '+row.path)}
if(hash(resolve(root,'upstream/config.js'))!=='B53418CA3BC54B70E18CCB192EB471696F5211C5AA2E80D68FE6FE3851FF23AE')throw Error('Original compiled config differs');
if(hash(resolve(root,'upstream/config.ts.reference.txt'))!=='B3B77644910D3FAC28A06625E90F993A8C1BC6C9458F148C723E64E0C99EB23E')throw Error('Original config TypeScript differs');
if(hash(resolve(root,'upstream/system-prompt.ts.reference.txt'))!=='5E28C82634113D0CCA7FF5DA6FA94E27AAAE80E461CD5664CED9DBCEF6F89089')throw Error('Original prompt caller differs');
const original=await import('./upstream/config.js');
const input='C:/sdk-agent-start-package',saved=process.env.PI_PACKAGE_DIR;
process.env.PI_PACKAGE_DIR=input;
const records=[
 {id:'readme',capturedWindows:String.raw`C:\sdk-agent-start-package\README.md`,resolved:original.getReadmePath()},
 {id:'docs',capturedWindows:String.raw`C:\sdk-agent-start-package\docs`,resolved:original.getDocsPath()},
 {id:'examples',capturedWindows:String.raw`C:\sdk-agent-start-package\examples`,resolved:original.getExamplesPath()},
];
if(saved===undefined)delete process.env.PI_PACKAGE_DIR;else process.env.PI_PACKAGE_DIR=saved;
const nodeHash=createHash('sha256');for await(const part of createReadStream(process.execPath))nodeHash.update(part);
const output={schema:'sdk-source-doc-path-oracle-562-v1',configTsSha256:hash(resolve(root,'upstream/config.ts.reference.txt')),configJsSha256:hash(resolve(root,'upstream/config.js')),callerTsSha256:hash(resolve(root,'upstream/system-prompt.ts.reference.txt')),manifestSha256:hash(manifestPath),input:{name:'PI_PACKAGE_DIR',value:input},node:{version:process.versions.node,platform:process.platform,arch:process.arch,executable:process.execPath,sha256:nodeHash.digest('hex').toUpperCase()},cwd:process.cwd(),records};
const raw=JSON.stringify(output,null,2)+'\n';if(process.argv[2])writeFileSync(process.argv[2],raw);else process.stdout.write(raw);
