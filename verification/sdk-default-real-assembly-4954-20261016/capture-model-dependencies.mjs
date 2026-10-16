// External genuine Source observation only. Never used by native runtime.
// Requires the Root-owned clean seal, full freezes, observer and Source slot.
import {readFile,mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
const pinned='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/';
const expected={
  'core/models-store.ts':'9a93afb3ad9123e59cb61606e77d431b38bbeb3063afc0e2974341109f23db02',
  'core/model-config.ts':'9f2cf2de7b8dd503ca4bc68119163c1d9bc8a3bf16caccfb1207e55b6e1cd97e',
};
for(const [path,digest]of Object.entries(expected)){
  const actual=createHash('sha256').update(await readFile(pinned+path)).digest('hex');
  if(actual!==digest)throw Error('Actual Source module byte drift: '+path);
}
const output=process.argv[2];
if(!output)throw Error('Explicit no-overwrite observation output required');
const input=resolve(root,'src/extensions/fixtures/sdk-model-dependencies-4954.input.mjs');
const inputBytes=await readFile(input);
const stores=await import(pathToFileURL(pinned+'core/models-store.ts').href);
const config=await import(pathToFileURL(pinned+'core/model-config.ts').href);
const directory=await mkdtemp(join(tmpdir(),'pi-sdk-model-dependencies-'));
try{
  globalThis.ActualSdkModelDependencies={...stores,...config};
  globalThis.ActualSdkModelFixtureDir=directory;
  await import(pathToFileURL(input).href);
  const rows=globalThis.ActualSdkModelDependencyRows;
  if(!Array.isArray(rows)||rows.length!==53)throw Error('Actual Source53 probe universe incomplete');
  await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',inputSha256:createHash('sha256').update(inputBytes).digest('hex'),modules:expected,cases:rows.length,rows},null,2)+'\n',{flag:'wx'});
}finally{
  delete globalThis.ActualSdkModelDependencies;
  delete globalThis.ActualSdkModelFixtureDir;
  delete globalThis.ActualSdkModelDependencyRows;
  // directory is the exact mkdtemp result owned exclusively by this capture.
  await rm(directory,{recursive:true,force:true});
}
