// Import the actual immutable Source loader, never a reconstructed provider.
import fs from 'node:fs';
import {setTimeout as ownerSetTimeout,clearTimeout as ownerClearTimeout} from 'node:timers';
import * as api from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/load.ts';
import {lazyOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/helpers.ts';
import {run} from '../../src/extensions/native_ai_oauth_loader_fixture.mjs';
const [,output]=process.argv.slice(2);
if(!output||fs.existsSync(output))throw Error('Fresh unique Source graph output required');
const timer=ownerSetTimeout(()=>{throw Error('Owned OAuth graph Source fixture exceeded ten seconds')},10000);
let rows;
try{rows=await run(api,lazyOAuth)}finally{ownerClearTimeout(timer)}
if(rows.length!==18)throw Error('OAuth graph Source18 inventory');
fs.writeFileSync(output,JSON.stringify({authority:'actual immutable ae7 auth/oauth/load.ts and helpers.ts; nine real dynamically imported Source flow modules',sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',actualNode:{version:process.version,executable:process.execPath},cases:rows.length,rows},null,2),{flag:'wx'});
