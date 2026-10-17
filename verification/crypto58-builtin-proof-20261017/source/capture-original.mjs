// Standalone original58 builtin subject. Only the CI607 owner releases stdin.
import crypto from 'node:crypto';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {registerHooks,syncBuiltinESMExports} from 'node:module';
import http from 'node:http';import https from 'node:https';
import net from 'node:net';import tls from 'node:tls';
import dgram from 'node:dgram';import dns from 'node:dns';
if(process.argv.length!==3||process.argv[2]!=='--owned-original58')throw Error('Exact standalone original58 arguments required');
if(fs.readFileSync(0,'utf8')!=='CRYPTO_SHA256_ORIGINAL58_OWNED_START\n')throw Error('CI607 owned-start fence required');
const allowedNames=new Set(['SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','PSModulePath','TEMP','TMP','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','NO_COLOR','POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK','NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE'].map(name=>name.toUpperCase()));
const environmentNames=Object.keys(process.env).sort();
const unexpectedEnvironmentNames=environmentNames.filter(name=>!allowedNames.has(name.toUpperCase()));
if(unexpectedEnvironmentNames.length)throw Error('Unexpected inherited environment names: '+JSON.stringify(unexpectedEnvironmentNames));
for(const name of ['NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE'])if(process.env[name]!=='')throw Error('CI607 empty Node control variable required');
if(!process.permission||process.permission.has('child')||process.permission.has('worker')||process.permission.has('addons')||process.permission.has('fs.write'))throw Error('Restricted standalone builtin capture permissions required');
const networkAttempts=[],moduleAttempts=[];
function denied(name){return function(){networkAttempts.push(name);throw Error('Original58NetworkForbidden:'+name)}}
for(const [object,names,prefix] of [[http,['request','get','createServer'],'http'],[https,['request','get','createServer'],'https'],[net,['connect','createConnection','createServer'],'net'],[tls,['connect','createServer'],'tls'],[dgram,['createSocket'],'dgram']])for(const name of names)object[name]=denied(prefix+'.'+name);
net.Socket.prototype.connect=denied('net.Socket.connect');
for(const object of [dns,dns.promises])for(const name of Object.keys(object))if(name==='lookup'||name==='lookupService'||name.startsWith('resolve'))object[name]=denied('dns.'+name);
globalThis.fetch=denied('fetch');globalThis.WebSocket=denied('WebSocket');syncBuiltinESMExports();
// All fixed imports above are original Node builtins. The immutable subject
// input has no module imports; any later public resolution is a negative.
registerHooks({resolve(specifier){moduleAttempts.push(specifier);throw Error('Original58UnexpectedModule:'+specifier)}});
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const executableSha256=sha(fs.readFileSync(process.execPath));
if(process.version!=='v24.14.0'||executableSha256!=='63c259c81e5d472b5f11c8d506070130cb04a1ecf84b80377a34ed6ec9048088')throw Error('Exact original Windows Node24.14.0 required');
const inputPath=fileURLToPath(new URL('../../src/extensions/fixtures/node-crypto-sha256-package.input.txt',import.meta.url));
const input=fs.readFileSync(inputPath,'utf8'),inputSha256=sha(input);
const controls=JSON.parse(fs.readFileSync(new URL('source-only-controls.json',import.meta.url)));
if(inputSha256!==controls.input_sha256.toLowerCase()||controls.case_ids.length!==58)throw Error('Immutable original58 input/ordered IDs required');
globalThis.nativeNodeCryptoSubject=crypto;
await(new Function('return(async()=>{'+input+'\n})()'))();
const observed=globalThis.nativeNodeCryptoObservation;
if(observed?.count!==58||observed.rows.length!==58||new Set(observed.rows.map(row=>row.name)).size!==58)throw Error('Original58 subject census differs');
for(let i=0;i<58;i++)if(observed.rows[i].name!==controls.case_ids[i])throw Error('Original58 ordered case ID differs');
if(networkAttempts.length||moduleAttempts.length)throw Error('Unexpected network/module attempt during original subject');
process.stdout.write(JSON.stringify({subject:'actual node:crypto SHA256 PackageManager dependency',runtime:{version:process.version,pid:process.pid,execPath:process.execPath,executableSha256},inputSha256,...observed,capture:{stdinFence:true,builtinOnly:true,deletedRuntimeUsed:false,networkAttempts,moduleAttempts,environmentNames,childAllowed:false,workerAllowed:false,addonAllowed:false,filesystemWritesAllowed:false}})+'\n');
