// Prepared observer: run only under the admitted owner and pinned TS loader.
// Calls the real exported primary converter; no Source implementation copied.
import {convertMessages} from 'file:///C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/ai/src/api/google-shared.ts';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const sourceFile='C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/ai/src/api/google-shared.ts';
const inputFile=new URL('./primary-tool-callers.mjs',import.meta.url);
if(process.version!=='v24.14.0'||sha(sourceFile)!=='2620d1c4dc428a6c3a15ce156d1f5132c6882ba6bd52c33e4e13ae5737e98647'||sha(inputFile)!=='698517770f92d78a336f372046f1771b2dedabc531d29b44083751b0f1509840')throw Error('Pinned Node, Source or input bytes changed');
globalThis.nativeGoogleToolOutput4dd=convertMessages;
try{
 const {checked,observations}=await import('./primary-tool-callers.mjs');
 if(checked!==true||observations.length!==146)throw Error('All original 146 caller cases required');
 writeFileSync(process.argv[2],JSON.stringify({authority:'Actual official4dd exported Google convertMessages; controlled caller inputs only',sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',sourceTree:'8daed06c8b2ac6787789642952fb3129f00e3d8d',actualNode:{pid:process.pid,version:process.version,execPath:process.execPath},sourceFile:{path:sourceFile,sha256:sha(sourceFile)},callerSha256:sha(inputFile),cases:observations.length,observations,network:false,nativeQualified:false},null,2));
}finally{delete globalThis.nativeGoogleToolOutput4dd;delete globalThis.googleToolOutput4ddObservations}
