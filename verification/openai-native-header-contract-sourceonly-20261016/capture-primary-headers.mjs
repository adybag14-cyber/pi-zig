// Prepared genuine primary-dependency observer. Execution has not been granted.
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {buildHeaders} from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/internal/headers.mjs';
import {VERSION} from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/version.mjs';
import {observeHeaderCases} from './primary-header-callers.mjs';
const primary='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/openai/internal/headers.mjs';
const rows=observeHeaderCases(buildHeaders);
if(rows.length!==18||VERSION!=='6.40.0'||process.version!=='v24.14.0')throw Error('Pinned primary SDK/Node/caller inventory changed');
writeFileSync(process.argv[2],JSON.stringify({authority:'Actual pinned OpenAI6.40.0 internal/headers export over Node24.14 Headers; Source caller controls only',actualNode:{pid:process.pid,version:process.version,execPath:process.execPath},sdkVersion:VERSION,primaryFile:primary,primarySha256:createHash('sha256').update(readFileSync(primary)).digest('hex'),driverSha256:createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),cases:rows.length,rows,nativeQualified:false},null,2));
