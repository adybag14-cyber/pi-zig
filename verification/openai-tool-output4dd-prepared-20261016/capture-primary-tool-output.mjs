// Prepared genuine Source observer. Execute only through a separately admitted
// owner and the pinned real TS loader; no Source implementation is copied here.
import {convertMessages} from 'file:///C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/ai/src/api/openai-completions.ts';
import {convertResponsesMessages} from 'file:///C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/ai/src/api/openai-responses-shared.ts';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
globalThis.nativeToolOutput4dd=(model,context)=>model.api==='openai-completions'?convertMessages(model,context,{}):convertResponsesMessages(model,context,new Set(['openai']),{});
try{
 const {checked,observations}=await import('./primary-tool-callers.mjs');
 if(checked!==true||observations.length!==52||process.version!=='v24.14.0')throw Error('Pinned Node or caller controls changed');
 const files=['openai-completions.ts','openai-responses-shared.ts'].map(name=>{const path='C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/ai/src/api/'+name;return {path,sha256:createHash('sha256').update(readFileSync(path)).digest('hex')}});
 writeFileSync(process.argv[2],JSON.stringify({authority:'Actual official4dd exported OpenAI/Responses converters; controlled caller inputs only',sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',actualNode:{pid:process.pid,version:process.version,execPath:process.execPath},files,observations,network:false,nativeQualified:false},null,2));
}finally{delete globalThis.nativeToolOutput4dd}
