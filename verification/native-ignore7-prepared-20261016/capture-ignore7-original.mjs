// Prepared genuine package observer. Execute only after Root's serial grant.
import ignore from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const packageFile='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/index.js';
const packageJson='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ignore/package.json';
const caller=new URL('./original-callers.mjs',import.meta.url);
const liveCaller=new URL('./live-prototype-callers.mjs',import.meta.url);
const edgeCaller=new URL('./scanner-edge-callers.mjs',import.meta.url);
const posixCaller=new URL('./posix-prototype-callers.mjs',import.meta.url);
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
if(process.version!=='v24.14.0'||process.platform!=='win32'||sha(packageFile)!=='643735013bdcf86dfeca4d38fb74d9a4fafa7a640ad2d251077862f18b2556fe'||sha(packageJson)!=='809e28f354aca6ac273e9d455ee2ebd8f2c0e8676d0b62417a5b11ddda4ba8cd'||sha(caller)!=='5d8a62805bd3866fd7742f0f6fa6f3e05411961155f95a7de8d9b60cd19d6363'||sha(liveCaller)!=='f18ce5b5c25311e054c50b87a487372ba7e0222371a2427545ff0a90a35b1ef6')throw Error('Pinned package, original caller or actual Node identity mismatch');
if(sha(edgeCaller)!=='88daf67e655f7b04852f33c1e4aa2cb5c57b62babe5440ed01dd5fb56c83edc1')throw Error('Original scanner edge caller bytes changed');
if(sha(posixCaller)!=='5ee2e61d622ba80ea6bda3c433c6ab7abbdb2c7c8abb6c1166e933ad520146ab')throw Error('Original POSIX prototype caller bytes changed');
globalThis.nativeIgnore7=ignore;
try{
 const {observations,matrixSets,matrixPaths,cases}=await import('./original-callers.mjs');
 const live=await import('./live-prototype-callers.mjs');
 const edge=await import('./scanner-edge-callers.mjs');
 const posix=await import('./posix-prototype-callers.mjs');
 if(matrixSets!==42||matrixPaths!==54||cases!==2375||observations.length!==cases)throw Error('Every original caller case required');
 if(live.cases!==12||live.observations.length!==12)throw Error('All additive live prototype cases required');
 if(edge.cases!==12||edge.observations.length!==12)throw Error('All independent-review scanner cases required');
 if(posix.cases!==4||posix.observations.length!==4)throw Error('All POSIX prototype cases required');
 writeFileSync(process.argv[2],JSON.stringify({authority:'Actual pinned ignore7.0.8 used by official4dd PackageManager; original caller controls only',sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',version:JSON.parse(readFileSync(packageJson,'utf8')).version,packageFile,packageSha256:sha(packageFile),packageJsonSha256:sha(packageJson),callerSha256:sha(caller),liveCallerSha256:sha(liveCaller),edgeCallerSha256:sha(edgeCaller),posixCallerSha256:sha(posixCaller),actualNode:{pid:process.pid,execPath:process.execPath,version:process.version,platform:process.platform},matrixSets,matrixPaths,cases,observations,liveCases:live.cases,liveObservations:live.observations,edgeCases:edge.cases,edgeObservations:edge.observations,posixCases:posix.cases,posixObservations:posix.observations,totalCases:cases+live.cases+edge.cases+posix.cases,network:false,nativeQualified:false},null,2));
}finally{delete globalThis.nativeIgnore7;delete globalThis.ignore7OriginalObservations;delete globalThis.ignore7LiveObservations;delete globalThis.ignore7ScannerEdgeObservations;delete globalThis.ignore7PosixPrototypeObservations}
