// Prepared only. Root must admit actual npm descendants, owned physical files,
// the frozen Node/npm tool tree and complete before/after Source controls.
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {DefaultPackageManager} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/core/package-manager.ts';
import {SettingsManager} from 'file:///C:/Users/adyba/pi-upstream-source-0fbdbd3-20261016/packages/coding-agent/src/core/settings-manager.ts';
if(process.version!=='v24.14.0')throw Error('Pinned Node24.14.0 required');
const ownedParent=realpathSync(process.argv[5]);if(lstatSync(process.argv[5]).isSymbolicLink())throw Error('Owned physical parent cannot be a link');
const npmCommand=JSON.parse(process.argv[6]);if(!Array.isArray(npmCommand)||!npmCommand.length)throw Error('Actual pinned npm command required');
for(const flag of ['--offline','--ignore-scripts','--no-audit','--no-fund'])if(!npmCommand.includes(flag))throw Error('Bounded real npm mode missing '+flag);
const physicalRoot=mkdtempSync(join(ownedParent,'package-real-'));
globalThis.PackageAPI={DefaultPackageManager,SettingsManager,isAsyncFunction:types.isAsyncFunction,cwd:physicalRoot,agentDir:physicalRoot,physicalRoot,npmCommand};
const first=readFileSync(process.argv[3]),second=readFileSync(process.argv[4]);
await import('data:text/javascript,'+encodeURIComponent(first.toString('utf8')));await import('data:text/javascript,'+encodeURIComponent(second.toString('utf8')));
if(packageEmptyBatchComplete!==true||packageEmptyBatchRows.length!==2||packageGetterComplete!==true||packageGetterRows.length!==4)throw Error('Incomplete physical/getter supplements');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'0fbdbd3f8ab1876ac260c0f08226a400759323b8',physicalRoot,npmCommand,cases:6,inputs:[first,second].map(input=>createHash('sha256').update(input).digest('hex')),emptyBatch:packageEmptyBatchRows,getters:packageGetterRows},null,2)+'\n');
