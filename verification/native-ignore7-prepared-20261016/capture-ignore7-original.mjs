// Prepared genuine package observer. Execute only after Root's serial grant.
import ignore from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const packageFile='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/index.js';
const packageJson='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/package.json';
const caller=new URL('./original-callers.mjs',import.meta.url);
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
if(process.version!=='v24.14.0'||process.platform!=='win32'||sha(packageFile)!=='643735013bdcf86dfeca4d38fb74d9a4fafa7a640ad2d251077862f18b2556fe'||sha(packageJson)!=='809e28f354aca6ac273e9d455ee2ebd8f2c0e8676d0b62417a5b11ddda4ba8cd'||sha(caller)!=='5d8a62805bd3866fd7742f0f6fa6f3e05411961155f95a7de8d9b60cd19d6363')throw Error('Pinned package, original caller or actual Node identity mismatch');
globalThis.nativeIgnore7=ignore;
try{
 const {observations,matrixSets,matrixPaths,cases}=await import('./original-callers.mjs');
 if(matrixSets!==42||matrixPaths!==54||cases!==2375||observations.length!==cases)throw Error('Every original caller case required');
 writeFileSync(process.argv[2],JSON.stringify({authority:'Actual pinned ignore7.0.8 used by official4dd PackageManager; original caller controls only',sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',version:JSON.parse(readFileSync(packageJson,'utf8')).version,packageFile,packageSha256:sha(packageFile),packageJsonSha256:sha(packageJson),callerSha256:sha(caller),actualNode:{pid:process.pid,execPath:process.execPath,version:process.version,platform:process.platform},matrixSets,matrixPaths,cases,observations,network:false,nativeQualified:false},null,2));
}finally{delete globalThis.nativeIgnore7;delete globalThis.ignore7OriginalObservations}
