import fs from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {setTimeout as sleep} from 'node:timers/promises';
import {createHash} from 'node:crypto';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/';
const tree='C:/Users/adyba/pi-zig-native-file-auth-storage-backend-20261015/';
const root=fs.mkdtempSync(path.join(tmpdir(),'pi-file-auth-4954-'));
const previous=process.env.PI_CODING_AGENT_DIR;
process.env.PI_CODING_AGENT_DIR=root;
let output;
try{
  const {FileAuthStorageBackend}=await import(pathToFileURL(source+'packages/coding-agent/src/core/auth-storage.ts'));
  const {default:lockfile}=await import(pathToFileURL(source+'node_modules/proper-lockfile/index.js'));
  globalThis.FileAuthStorageBackend=FileAuthStorageBackend;
  globalThis.fileAuthFs=fs;
  globalThis.fileAuthLockfile=lockfile;
  globalThis.fileAuthJoin=path.join;
  globalThis.fileAuthSleep=sleep;
  globalThis.fileAuthRoot=root;
  const input=fs.readFileSync(tree+'src/extensions/fixtures/sdk-file-auth-storage-4954.input.txt','utf8');
  await Function('return (async()=>{'+input+'\n})()')();
  if(fileAuthObservedRows.length!==32)throw Error('Actual FileAuth32 inventory mismatch');
  output={sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',runtime:process.version,count:32,inputSha256:createHash('sha256').update(input).digest('hex'),rows:fileAuthObservedRows,rawRows:fileAuthObservedRawRows,rawErrors:fileAuthObservedRawErrors,ownedTempRoot:root};
}finally{
  if(previous===undefined)delete process.env.PI_CODING_AGENT_DIR;else process.env.PI_CODING_AGENT_DIR=previous;
  const absolute=path.resolve(root),parent=path.resolve(tmpdir());
  if(path.dirname(absolute)!==parent||!path.basename(absolute).startsWith('pi-file-auth-4954-')||fs.lstatSync(absolute).isSymbolicLink()||fs.realpathSync(absolute)!==absolute)throw Error('Owned temporary cleanup identity mismatch');
  fs.rmSync(absolute,{recursive:true,force:false});
  if(fs.existsSync(absolute))throw Error('Owned temporary cleanup absence mismatch');
}
output.ownedTemporaryRemovedAndAbsenceVerified=true;
fs.writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n');
process.stdout.write(JSON.stringify({sourceHead:output.sourceHead,count:output.count,rawRows:output.rawRows.length,rawErrors:output.rawErrors.length,ownedTemporaryRemovedAndAbsenceVerified:true})+'\n');
