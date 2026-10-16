// Prepared only: this script has not been executed and creates no expected rows
// until Root admits a fully sealed original-source process.
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {DefaultPackageManager} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/core/package-manager.ts';
import {SettingsManager} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/core/settings-manager.ts';
if(process.version!=='v24.14.0')throw Error('Pinned Node24.14.0 required');
const source='C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/core/package-manager.ts';
if(createHash('sha256').update(readFileSync(source)).digest('hex')!=='61bb2f0b434b0f5c48ab6bfacd9dff1d99084320eecf695755cd32bd88099310')throw Error('Pinned package manager source changed');
globalThis.PackageAPI={DefaultPackageManager,SettingsManager,isAsyncFunction:types.isAsyncFunction,cwd:process.cwd(),agentDir:process.cwd()+'/package-manager-unused-agent-dir'};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
const concurrencyInput=readFileSync(process.argv[4]);await import('data:text/javascript,'+encodeURIComponent(concurrencyInput.toString('utf8')));
if(packageLeafComplete!==true||packageLeafRows.length!==34||new Set(packageLeafRows.map(row=>row.name)).size!==34||packageConcurrencyComplete!==true||packageConcurrencyRows.length!==9)throw Error('Incomplete actual package controls');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'0fbdbd3f8ab1876ac260c0f08226a400759323b8',sourceSha256:'61bb2f0b434b0f5c48ab6bfacd9dff1d99084320eecf695755cd32bd88099310',inputSha256:createHash('sha256').update(input).digest('hex'),cases:43,sourceCwd:process.cwd(),rows:packageLeafRows,concurrencyInputSha256:createHash('sha256').update(concurrencyInput).digest('hex'),concurrencyRows:packageConcurrencyRows},null,2)+'\n');
