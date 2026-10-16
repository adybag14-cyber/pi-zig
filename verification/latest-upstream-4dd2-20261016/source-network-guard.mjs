// Capture control only. Unexpected network use is a terminal negative, even
// when Source catches the thrown reason. No response/provider is substituted.
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dgram from 'node:dgram';
import dns from 'node:dns';
import {syncBuiltinESMExports} from 'node:module';
import {join,resolve,sep} from 'node:path';
const root=fs.realpathSync(process.env.PI_LATEST_CAPTURE_RECORD_DIR??'');
const parent=resolve('C:/Users/adyba/pi-zig-update-evidence-20261003/latest4dd-source-captures');
if(!root.startsWith(parent+sep))throw Error('Owned capture record directory is required');
if(!process.permission||!process.permission.has('fs.write',root)||process.permission.has('child')||process.permission.has('worker')||process.permission.has('addons'))throw Error('Expected restricted Node capture permissions');
const attempts=[];
const allowedNames=new Set(['SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','TEMP','TMP','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR','NO_COLOR','POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK','PSModulePath','PI_SOURCE_ORACLE_CONTROL_MANIFEST','PI_LATEST_CAPTURE_KIND','PI_LATEST_CAPTURE_RECORD_DIR'].map(name=>name.toUpperCase()));
const environmentNames=Object.keys(process.env);
if(environmentNames.some(name=>!allowedNames.has(name.toUpperCase())))throw Error('Unexpected inherited child environment name');
for(const name of ['HOME','USERPROFILE','TEMP','TMP','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR'])if(!resolve(process.env[name]??'').startsWith(resolve(root,'..')+sep))throw Error('Owned fixture environment paths are required');
function denied(name){return function(){attempts.push(name);throw Error('OwnedSourceNetworkForbidden:'+name);};}
for(const [object,names,prefix] of [[http,['request','get','createServer'],'http'],[https,['request','get','createServer'],'https'],[net,['connect','createConnection','createServer'],'net'],[tls,['connect','createServer'],'tls'],[dgram,['createSocket'],'dgram']])for(const name of names)object[name]=denied(prefix+'.'+name);
net.Socket.prototype.connect=denied('net.Socket.connect');
for(const name of Object.keys(dns))if(name==='lookup'||name==='lookupService'||name.startsWith('resolve'))dns[name]=denied('dns.'+name);
for(const name of Object.keys(dns.promises))if(name==='lookup'||name==='lookupService'||name.startsWith('resolve'))dns.promises[name]=denied('dns.promises.'+name);
globalThis.fetch=denied('fetch');
globalThis.WebSocket=denied('WebSocket');
syncBuiltinESMExports();
process.once('beforeExit',()=>{
 fs.writeFileSync(join(root,`network-${process.pid}.json`),JSON.stringify({pid:process.pid,attempts,networkRequests:0,permissionModel:true,childProcessAllowed:false,workerAllowed:false,addonAllowed:false},null,2));
 fs.writeFileSync(join(root,`environment-${process.pid}.json`),JSON.stringify({pid:process.pid,names:environmentNames.sort(),allowlistMatched:true,ownedProfileTempAgent:true,credentialValuesRecorded:false},null,2));
 if(attempts.length)process.exitCode=1;
});
