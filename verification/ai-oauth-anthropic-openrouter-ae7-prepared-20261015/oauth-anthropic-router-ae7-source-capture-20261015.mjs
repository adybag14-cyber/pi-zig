import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const evidence='C:/Users/adyba/pi-zig-update-evidence-20261003/';
const tree='C:/Users/adyba/pi-zig-native-oauth-anthropic-router-20261015/';
const source='C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/';
const controls=JSON.parse(readFileSync(evidence+'sourceae7-preparation-controls-20261015.json'));
for(const row of controls){const actual=createHash('sha256').update(readFileSync(row.path)).digest('hex');if(actual!==row.sha256.toLowerCase())throw Error('Source preparation control drift: '+row.path);}
const inputPath=tree+'src/extensions/fixtures/ai-oauth-anthropic-openrouter-ae7.input.txt';
const input=readFileSync(inputPath,'utf8');
const modules=['packages/ai/src/auth/oauth/anthropic.ts','packages/ai/src/auth/oauth/openrouter.ts'];
const sourceIdentity=modules.map(name=>({path:realpathSync(source+name),sha256:createHash('sha256').update(readFileSync(source+name)).digest('hex')}));
const [{anthropicOAuth},{openRouterOAuth}]=await Promise.all(modules.map(name=>import(pathToFileURL(source+name))));
globalThis.oauthAPI={anthropic:anthropicOAuth,openrouter:openRouterOAuth};
await Function('return (async()=>{'+input+'\n})()')();
const output={sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',runtime:process.version,count:oauthObservedRows.length,sourceIdentity,inputSha256:createHash('sha256').update(input).digest('hex'),rows:oauthObservedRows,rawRows:oauthObservedRawRows};
const destination=process.argv[2]??evidence+'oauth-anthropic-router-ae7-source-candidate-20261015.json';
writeFileSync(destination,JSON.stringify(output,null,2)+'\n');
process.stdout.write(JSON.stringify({rows:output.rows.length,sourceHead:output.sourceHead,output:destination})+'\n');
