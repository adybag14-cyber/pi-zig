// Genuine primary SDK constructor observer, prepared and unexecuted.
import OpenAI from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/index.mjs';
import {buildHeaders} from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/internal/headers.mjs';
import {VERSION} from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/version.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {observeClientOptionCases} from './primary-client-callers.mjs';
function capture(provided){
 const client=new OpenAI({...provided,dangerouslyAllowBrowser:true});
 const defaults=client._options.defaultHeaders;
 const prepared=!!defaults&&typeof defaults==='object'&&Object.getOwnPropertySymbols(defaults).some(symbol=>symbol.description==='brand.privateNullableHeaders');
 return {baseURL:client.baseURL,apiKey:client.apiKey,adminAPIKey:client.adminAPIKey,organization:client.organization,project:client.project,webhookSecret:client.webhookSecret,logger:client.logger,logLevel:client.logLevel,fetch:client.fetch,defaultHeaders:prepared?defaults.values:defaults,headerNulls:prepared?defaults.nulls:undefined,headersPrepared:prepared};
}
const rows=observeClientOptionCases(capture,buildHeaders);
if(rows.length!==32||VERSION!=='6.40.0'||process.version!=='v24.14.0')throw Error('Pinned SDK/Node/constructor caller inventory changed');
const primary='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/client.mjs';
writeFileSync(process.argv[2],JSON.stringify({authority:'Actual pinned OpenAI6.40.0 constructor accessed option projection; controlled dummy environment only, no transport execution',actualNode:{pid:process.pid,version:process.version,execPath:process.execPath},sdkVersion:VERSION,primaryFile:primary,primarySha256:createHash('sha256').update(readFileSync(primary)).digest('hex'),driverSha256:createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),cases:rows.length,rows,network:false,nativeQualified:false},null,2));
