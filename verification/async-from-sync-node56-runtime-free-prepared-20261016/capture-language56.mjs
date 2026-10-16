// Pure genuine language capture. The separately reviewed preload establishes
// the owned fence before this entry or either caller module is imported.
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {consume} from './language-consumer.mjs';
import {observeForAwait} from './for-await-callers.mjs';
const configPath=process.env.PI_LANGUAGE56_CAPTURE_CONFIG;
if(!configPath||process.version!=='v24.14.0')throw Error('Exact owned Language56 config and pinned Node required');
const config=JSON.parse(readFileSync(configPath));
if(config.scope!=='runtime-free-language56-only'||config.expected_cases!==56||config.expected_case_ids.length!==56)throw Error('Separate56 grant/profile required');
const run=realpathSync(config.run),output=resolve(process.argv[3]);
if(realpathSync(process.argv[2])!==realpathSync(config.snapshot)||output!==join(run,'source56-raw.json'))throw Error('Exact owned snapshot/output arguments required');
const ready=JSON.parse(readFileSync(join(run,'start-fence-ready.json'))),permit=JSON.parse(readFileSync(join(run,'start-fence-release.json')));
if(ready.pid!==process.pid||ready.nonce!==config.nonce||ready.sourceImported!==false||permit.node_pid!==process.pid||permit.nonce!==config.nonce||permit.live_identity_verified!==true)throw Error('Owned start-fence evidence required');
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase();
if(sha(process.execPath)!==config.node_sha256||config.node_sha256!=='63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088')throw Error('Pinned actual Node bytes required');
const self=realpathSync(fileURLToPath(import.meta.url));if(!config.module_files.some(row=>realpathSync(row.path)===self&&row.sha256===sha(self)))throw Error('Exact sealed driver required');
const rows=await observeForAwait(consume);
if(rows.length!==56||JSON.stringify(rows.map(row=>row.name))!==JSON.stringify(config.expected_case_ids))throw Error('All56 ordered genuine language observations required');
writeFileSync(output,JSON.stringify({authority:'Actual pinned Node24 language for-await and async-generator yield*; no adapter implementation',scope:config.scope,sourcePacketHead:config.source_head,startFenceNonce:config.nonce,actualNode:{pid:process.pid,execPath:process.execPath,version:process.version,v8:process.versions.v8,sha256:sha(process.execPath)},cases:rows.length,rows,moduleFiles:config.module_files,nativeQualified:false,sdkRuntimeDependency:false},null,2),{flag:'wx'});
