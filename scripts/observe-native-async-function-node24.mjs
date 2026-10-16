import {registerHooks} from 'node:module';
import {readFileSync,realpathSync,appendFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const manifest=JSON.parse(readFileSync(process.env.PI_ASYNC_SOURCE_CONTROLS,'utf8'));
const frozen=new Map(manifest.map(row=>[realpathSync(row.path),row.sha256.toLowerCase()]));
const seen=new Set();
function observe(url){
 if(url.startsWith('node:'))return;
 if(!url.startsWith('file:'))throw Error('Only frozen controls and Node builtins are permitted: '+url);
 const path=realpathSync(fileURLToPath(url));
 if(!frozen.has(path))throw Error('Unfrozen module import: '+path);
 const sha256=createHash('sha256').update(readFileSync(path)).digest('hex');
 if(frozen.get(path)!==sha256)throw Error('Control changed: '+path);
 if(!seen.has(path)){seen.add(path);appendFileSync(process.env.PI_ASYNC_SOURCE_MODULE_LOG,JSON.stringify({path,sha256})+'\n');}
}
registerHooks({resolve(specifier,context,next){const result=next(specifier,context);observe(result.url);return result;}});
observe(import.meta.url);
