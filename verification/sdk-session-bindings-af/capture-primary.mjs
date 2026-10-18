// PREPARED/UNRUN. Root's exact qualified Source module closure must import the
// original AgentSession. This observer never evaluates the copied TS excerpt.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import {runSessionBindingsAF} from './original-callers.mjs';
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
if(config.execution_authorized!==true||config.source_revision!=='c268154ca1171c2f9eefe75d3d7372a68aada2d5'||!config.qualified_source_closure_receipt) throw Error('Root qualified Source closure and grant required');
const {AgentSession}=await import(pathToFileURL(config.actual_agent_session_module).href);
if(typeof AgentSession!=='function') throw Error('Actual Source AgentSession required');
const rows=await runSessionBindingsAF(AgentSession.prototype);
fs.writeFileSync(config.output,JSON.stringify({scope:'borrowed actual Source prototype methods',source:config.source_revision,rows})+'\n',{flag:'wx'});
