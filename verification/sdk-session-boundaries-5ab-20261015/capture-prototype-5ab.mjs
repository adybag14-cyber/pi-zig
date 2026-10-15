// Run under the admitted latest immutable observer. These are raw outputs:
// accept/copy the new reference only after the enclosing full posthash is zero.
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
const [inventoryOutput,deltaOutput,historicalPath,configuredRoot,expectedPlatform]=process.argv.slice(2);
if(!inventoryOutput||!deltaOutput||!historicalPath)throw Error('Arguments: inventory-output delta-output historical-fixture [source-root] [expected-platform]');
if(expectedPlatform&&expectedPlatform!==process.platform)throw Error('Actual platform differs from admitted platform');
const root=realpathSync(configuredRoot??'C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015');
const {AgentSession}=await import(pathToFileURL(resolve(root,'packages/coding-agent/src/core/agent-session.ts')));
const historicalBytes=readFileSync(historicalPath),historical=JSON.parse(historicalBytes);
if(historical.descriptors.length!==166)throw Error('Historical Source166 fixture required');
const describeFunction=fn=>fn===undefined?undefined:({name:fn.name,length:fn.length,async:Object.getPrototypeOf(fn)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(fn,'prototype')});
const descriptors=Reflect.ownKeys(AgentSession.prototype).map(key=>{
 const d=Object.getOwnPropertyDescriptor(AgentSession.prototype,key);
 return{key:typeof key==='symbol'?{symbol:String(key),globalKey:Symbol.keyFor(key)}:key,kind:'value'in d?'data':'accessor',enumerable:d.enumerable,configurable:d.configurable,...('writable'in d?{writable:d.writable}:{}),...('value'in d?{valueType:typeof d.value,function:typeof d.value==='function'?describeFunction(d.value):undefined}:{get:describeFunction(d.get),set:describeFunction(d.set)})};
});
const serialKey=key=>JSON.stringify(key),before=new Map(historical.descriptors.map(row=>[serialKey(row.key),row])),after=new Map(descriptors.map(row=>[serialKey(row.key),row]));
const added=descriptors.filter(row=>!before.has(serialKey(row.key))).map(row=>row.key);
const removed=historical.descriptors.filter(row=>!after.has(serialKey(row.key))).map(row=>row.key);
const changed=descriptors.filter(row=>before.has(serialKey(row.key))&&JSON.stringify(row)!==JSON.stringify(before.get(serialKey(row.key)))).map(row=>({key:row.key,before:before.get(serialKey(row.key)),after:row}));
const beforeKeys=historical.descriptors.map(row=>row.key),afterKeys=descriptors.map(row=>row.key);
const delta={source:'5ab7fe74c400097b386662205cd93900695b8a71',historicalSource:historical.source,historicalFixtureSha256:createHash('sha256').update(historicalBytes).digest('hex'),historicalCount:historical.descriptors.length,actualCount:descriptors.length,exactDescriptorSequenceEqual:JSON.stringify(historical.descriptors)===JSON.stringify(descriptors),keyOrderEqual:JSON.stringify(beforeKeys)===JSON.stringify(afterKeys),added,removed,changed,beforeKeys,afterKeys};
writeFileSync(inventoryOutput,JSON.stringify({source:delta.source,platform:process.platform,scope:'Reflect.ownKeys/Object.getOwnPropertyDescriptor of the actual original exported AgentSession.prototype from the admitted latest immutable Source; no Source body rewrite or native replacement. Full factory behavior remains separate.',descriptors},null,2));
writeFileSync(deltaOutput,JSON.stringify(delta,null,2));
process.stdout.write(JSON.stringify({actualCount:delta.actualCount,historicalCount:delta.historicalCount,exactDescriptorSequenceEqual:delta.exactDescriptorSequenceEqual,keyOrderEqual:delta.keyOrderEqual,added,removed,changedCount:changed.length})+'\n');
