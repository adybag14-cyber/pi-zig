// Genuine Source/native oracle child. This is a test input, never a product host.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const [mode, root, caseId, nonce, ...extra] = process.argv.slice(2);
if (!root || !caseId || !nonce || !path.basename(root).startsWith('sdk-exec-owned-')) throw Error('Owned fixture identity required');
const identity = {pid:process.pid,parentPid:process.ppid,executable:process.execPath,argv:process.argv,observedUtc:new Date().toISOString(),mode,caseId,nonce};
fs.writeFileSync(path.join(root, `${caseId}-${process.pid}.identity.json`), JSON.stringify(identity));
switch (mode) {
  case 'argv': process.stdout.write(JSON.stringify(extra)); break;
  case 'channels': process.stdout.write('out\0\x1b[31m\n'); process.stderr.write('err\n'); break;
  case 'nonzero': process.stdout.write('before-exit'); process.stderr.write('diagnostic'); process.exitCode=17; break;
  case 'bytes': process.stdout.write(Buffer.from([0xe2,0x28,0xa1,0,0x1b])); break;
  case 'split': process.stdout.write(Buffer.from([0xe2])); setTimeout(()=>process.stdout.write(Buffer.from([0x82,0xac])),100); break;
  case 'large': process.stdout.write('x'.repeat(1024*1024+17)); process.stderr.write('tail'); break;
  case 'cwd': process.stdout.write(process.cwd()); break;
  case 'sleep': setTimeout(()=>process.stdout.write('natural-end'),350); break;
  case 'ready': fs.writeFileSync(path.join(root, `${caseId}.ready`),'ready'); setTimeout(()=>process.stdout.write('natural-end'),350); break;
  case 'ignore-term': process.on('SIGTERM',()=>process.stdout.write('term-observed')); setTimeout(()=>process.stdout.write('natural-end'),350); break;
  case 'self-term': process.kill(process.pid,'SIGTERM'); break;
  case 'descendant-quiet':
  case 'descendant-active': {
    const child=spawn(process.execPath,[fileURLToPath(import.meta.url), mode==='descendant-quiet'?'quiet':'active',root,`${caseId}-descendant`,nonce],{stdio:mode==='descendant-quiet'?['ignore',process.stdout,process.stderr]:['ignore',process.stdout,process.stderr,'ipc'],detached:true,windowsHide:true});
    if(mode==='descendant-active')child.once('message',()=>child.disconnect());
    child.unref();
    break;
  }
  case 'quiet': setTimeout(()=>{},400); break;
  case 'active': process.stdout.write('a');if(process.send)process.send('ready');for(const [ms,text] of [[80,'b'],[160,'c'],[240,'d']]) setTimeout(()=>process.stdout.write(text),ms); setTimeout(()=>process.stderr.write('end'),260); break;
  default: throw Error(`Unknown owned child mode ${mode}`);
}
