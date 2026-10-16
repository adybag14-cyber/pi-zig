// Observation of the actual original Source classes using Node's native brand.
// Requires Root's clean full-freeze Source slot. No capture was run by authoring.
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
const root=fileURLToPath(new URL('../../',import.meta.url));
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/';
const pins={
  'core/model-runtime.ts':'ba6db976a8947167cb867eded70dfa96475182a3723ce2c7c9a88db5afeab756',
  'core/agent-session-runtime.ts':'b163ce35d2b6e3ba1fc080c0674044a3f1cd9faec93cc2ed015e31b69780bf4a',
  'core/model-config.ts':'9f2cf2de7b8dd503ca4bc68119163c1d9bc8a3bf16caccfb1207e55b6e1cd97e',
  'core/models-store.ts':'9a93afb3ad9123e59cb61606e77d431b38bbeb3063afc0e2974341109f23db02',
};
for(const[path,sha]of Object.entries(pins))if(createHash('sha256').update(await readFile(source+path)).digest('hex')!==sha)throw Error('Actual class module drift: '+path);
const output=process.argv[2];if(!output)throw Error('Explicit no-overwrite output path required');
const model=await import(pathToFileURL(source+'core/model-runtime.ts').href);
const session=await import(pathToFileURL(source+'core/agent-session-runtime.ts').href);
const config=await import(pathToFileURL(source+'core/model-config.ts').href);
const stores=await import(pathToFileURL(source+'core/models-store.ts').href);
const input=resolve(root,'src/extensions/fixtures/sdk-async-brand-4954.input.mjs');const bytes=await readFile(input);
try{
  globalThis.ActualSdkAsyncClasses={...model,...session,...config,...stores};
  globalThis.ActualSdkIsAsyncFunction=types.isAsyncFunction;
  await import(pathToFileURL(input).href);
  const rows=globalThis.ActualSdkAsyncBrandRows;if(!Array.isArray(rows)||rows.length!==15)throw Error('Actual brand15 corpus incomplete');
  await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',brandAuthority:'actual node:util.types.isAsyncFunction',inputSha256:createHash('sha256').update(bytes).digest('hex'),modules:pins,cases:rows.length,rows},null,2)+'\n',{flag:'wx'});
}finally{delete globalThis.ActualSdkAsyncClasses;delete globalThis.ActualSdkIsAsyncFunction;delete globalThis.ActualSdkAsyncBrandRows}
