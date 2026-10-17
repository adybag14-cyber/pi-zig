// PREPARED ONLY. Real official default Babel backend and public jiti wrapper,
// not custom opts.transform, identity callbacks, fake compiler or native oracle.
import {createRequire} from 'node:module';
import * as fs from 'node:fs';
import {join,resolve,relative,isAbsolute} from 'node:path';
const originalProcess=globalThis.process;
const root=resolve(originalProcess.argv[4]),nonce=originalProcess.argv[5];
const rel=relative(root,originalProcess.cwd());
if(!nonce||originalProcess.env.PI_JITI_DEFAULT_CAPTURE_OWNED!==nonce||(rel!==''&&(rel.startsWith('..')||isAbsolute(rel))))throw Error('separate owned start fence required');
const require=createRequire(import.meta.url);
const backend=require(resolve(originalProcess.argv[2]));
const createJiti=require(resolve(originalProcess.argv[3]));
const inputs=JSON.parse(fs.readFileSync(new URL('./inputs.json',import.meta.url),'utf8'));
const rows=[];
const previous=originalProcess.env.PI_JITI_DEFAULT_OWNED_VALUE;
originalProcess.env.PI_JITI_DEFAULT_OWNED_VALUE='owned-default-transform';
function failure(error){return{type:typeof error,name:error?.name,message:error?.message,code:error?.code,loc:error?.loc,stack:error?.stack}}
try{
  for(const [profile,cases]of [['consumed-profile',inputs.supported_execution_inputs],['native-frontier',inputs.declared_native_frontier_inputs]])for(const item of cases){
    const directory=join(root,item.id);fs.mkdirSync(directory,{recursive:true});
    const filename=join(directory,item.ts?'entry.ts':'entry.js');fs.writeFileSync(filename,item.source);
    for(const [name,bytes]of Object.entries(item.files??{}))fs.writeFileSync(join(directory,name),bytes);
    const options={...item,filename,interopDefault:true};delete options.id;delete options.files;delete options.args;
    const row={id:item.id,profile};
    try{
      const transformed=backend(options);
      // Exact default-backend code and actual error descriptor retained. No
      // formatting projection or native-produced expected value is introduced.
      row.result={keys:Reflect.ownKeys(transformed).map(String),code:transformed.code,error:transformed.error?failure(transformed.error):undefined};
      if(profile==='consumed-profile'&&!transformed.error){
        const jiti=createJiti(filename,{fsCache:false,tsconfigPaths:false});
        const exported=await jiti.evalModule(item.source,{filename,ext:item.ts?'.ts':'.js',forceTranspile:true,async:!!item.async});
        const fn=exported.default;
        row.execution={keys:Object.keys(exported),defaultType:typeof fn,name:fn?.name,length:fn?.length,functionSource:typeof fn==='function'?Function.prototype.toString.call(fn):undefined,value:typeof fn==='function'?await Reflect.apply(fn,undefined,item.args??[]):undefined};
      }
    }catch(error){row.thrown=failure(error)}
    rows.push(row);
  }
}finally{if(previous===undefined)delete originalProcess.env.PI_JITI_DEFAULT_OWNED_VALUE;else originalProcess.env.PI_JITI_DEFAULT_OWNED_VALUE=previous}
originalProcess.stdout.write(JSON.stringify({authority:'official-jiti2.7-default-babel-no-custom-transform',rows})+'\n');
