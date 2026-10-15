import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/';
const tree='C:/Users/adyba/pi-zig-native-file-revision-20261015/';
const evidence='C:/Users/adyba/pi-zig-update-evidence-20261003/';
const root=fs.mkdtempSync(path.join(evidence,'file-revision-source4954-fixture-'));
const input=fs.readFileSync(tree+'src/extensions/fixtures/file-revision-source-4954.input.txt','utf8');
let output={sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',runtime:process.version,inputSha256:createHash('sha256').update(input).digest('hex'),ownedFixtureRoot:root,fixturesRetained:true,status:'running'};
try{
  const {getFileRevision}=await import(pathToFileURL(source+'packages/coding-agent/src/utils/paths.ts'));
  globalThis.fileRevision=getFileRevision;
  globalThis.fileRevisionFs=fs;
  globalThis.fileRevisionPath=path;
  globalThis.fileRevisionRoot=root;
  globalThis.fileRevisionToURL=pathToFileURL;
  Function(input)();
  output={...output,...fileRevisionSourceObservations,count:fileRevisionSourceObservations.rows.length,status:'passed'};
  if(output.count!==30+(output.symlink.status==='created-and-followed'?1:0))throw Error('Unexpected genuine Source row inventory');
  for(const row of output.finalFiles){if(getFileRevision(row.path)!==row.revision)throw Error('Retained physical revision changed before output');row.sha256=createHash('sha256').update(fs.readFileSync(row.path)).digest('hex');}
}catch(error){output={...output,...(globalThis.fileRevisionSourceObservations??{}),status:'failed',error:{name:error.name,message:error.message,stack:error.stack}};throw error;}
finally{fs.writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n');}
process.stdout.write(JSON.stringify({sourceHead:output.sourceHead,count:output.count,rawRows:output.rawRows.length,retainedFiles:output.finalFiles.length,symlink:output.symlink,fixturesRetained:true})+'\n');


