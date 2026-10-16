// Genuine original Source observation. Root supplies strict full freezes and
// an owned Source slot; this file is never a native runtime implementation.
import {readFile,writeFile,mkdir,readdir,stat} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/';
const pins={
  'src/config.ts':'b3b77644910d3fac28a06625e90f993a8c1bc6c9458f148c723e64e0c99eb23e',
  'src/utils/shell.ts':'c93b05fef8d75072adeff45cdec2abfa2e03eb2910d9755c1edb45ce237e614a',
  'src/core/timings.ts':'55e4d7f31bdf3727baa4e89f361a6abee9ae4a76f64a30369ea157cb37bbc2b2',
  'src/utils/pi-user-agent.ts':'cd2329beb4b18fd99f5180d603fd1371c8f50441d4688f7d75918a051e565c26',
};
for(const [path,digest]of Object.entries(pins))if(createHash('sha256').update(await readFile(source+path)).digest('hex')!==digest)throw Error('Pinned original Source drift: '+path);
if(process.env.PI_TIMING!=='1'||resolve(process.env.PI_PACKAGE_DIR??'')!==resolve(source))throw Error('Explicit actual package root and enabled import-time timing controls required');
const output=process.argv[2];if(!output)throw Error('No-overwrite observation output required');
const directory=resolve(output+'.physical-files');await mkdir(directory);
async function inventory(){return await Promise.all(['',...(await readdir(directory,{recursive:true})).sort()].map(async path=>{const absolute=join(directory,path);const info=await stat(absolute,{bigint:true});return {path,kind:info.isDirectory()?'directory':'file',size:String(info.size),ino:String(info.ino),mode:String(info.mode),mtimeNs:String(info.mtimeNs),ctimeNs:String(info.ctimeNs),birthtimeNs:String(info.birthtimeNs),sha256:info.isFile()?createHash('sha256').update(await readFile(absolute)).digest('hex'):undefined}}))}
await writeFile(output+'.physical-before.json',JSON.stringify({directory,inventory:await inventory()},null,2)+'\n',{flag:'wx'});
const input=resolve(root,'src/extensions/fixtures/sdk-runtime-helpers-4954.input.mjs');const inputBytes=await readFile(input);
try{
  const config=await import(pathToFileURL(source+'src/config.ts').href);
  const shell=await import(pathToFileURL(source+'src/utils/shell.ts').href);
  const timing=await import(pathToFileURL(source+'src/core/timings.ts').href);
  const sessions=await import(pathToFileURL(source+'src/core/session-manager.ts').href);
  const userAgent=await import(pathToFileURL(source+'src/utils/pi-user-agent.ts').href);
  globalThis.ActualSdkRuntimeHelpers={configuration:{...config,getDefaultSessionDir:sessions.getDefaultSessionDir,getPiUserAgent:userAgent.getPiUserAgent},shell,timing};
  globalThis.ActualSdkRuntimeHelperDir=directory;
  await import(pathToFileURL(input).href);
  const rows=globalThis.ActualSdkRuntimeHelperRows;if(!Array.isArray(rows)||rows.length!==44)throw Error('Actual Source44 probe universe incomplete');
  const packageBytes=await readFile(source+'package.json');const pkg=JSON.parse(packageBytes);
  const typeboxBytes=await readFile('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/package.json');
  const typeboxSha=createHash('sha256').update(typeboxBytes).digest('hex');if(typeboxSha!=='c59ddfd977ce941f1e8ee8b0a0b14396c332fa27cc5fa6fa165227ffd5a3992f'||JSON.parse(typeboxBytes).version!=='1.3.27')throw Error('Pinned actual TypeBox metadata drift');
  await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',packageMetadataAuthority:source+'package.json',packageSha256:createHash('sha256').update(packageBytes).digest('hex'),packageName:pkg.name,packageVersion:pkg.version,packageRootOverride:source,typeboxVersion:'1.3.27',typeboxPackageSha256:typeboxSha,inputSha256:createHash('sha256').update(inputBytes).digest('hex'),modules:pins,cases:rows.length,rows},null,2)+'\n',{flag:'wx'});
}finally{
  delete globalThis.ActualSdkRuntimeHelpers;delete globalThis.ActualSdkRuntimeHelperDir;delete globalThis.ActualSdkRuntimeHelperRows;
  await writeFile(output+'.physical-after.json',JSON.stringify({directory,inventory:await inventory()},null,2)+'\n',{flag:'wx'});
}
