import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
if(process.version!=='v24.14.0')throw Error('Node24.14.0 required');
const path='C:/Users/adyba/pi-zig-upstream-0fb-20261016/src/extensions/fixtures/upstream-0fb-overflow.input.txt';
const input=readFileSync(path),inputSha256=createHash('sha256').update(input).digest('hex');
let timer;try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Bounded source overflow program timed out')),20000)})]);}finally{clearTimeout(timer)}
if(upstream0fbOverflowComplete!==true||upstream0fbOverflowRows.length!==5)throw Error('Incomplete genuine overflow source controls');
const document={sourceHead:'0fbdbd3f8ab1876ac260c0f08226a400759323b8',programs:[{name:'overflow',inputSha256,cases:5,rows:upstream0fbOverflowRows}]};
writeFileSync(process.argv[2],JSON.stringify(document,null,2)+'\n');
process.stdout.write(JSON.stringify({sourceHead:document.sourceHead,cases:5,inputSha256})+'\n');
