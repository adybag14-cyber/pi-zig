// Genuine Source observer driver. Execute only with a Root-granted Source slot
// and the latest immutable Source/dependency/control observer. Expected absent.
import {pathToFileURL} from 'node:url';
import {writeFileSync} from 'node:fs';
import {observe} from '../../src/extensions/fixtures/model-runtime-ordinary-4954.input.mjs';
const root=process.env.PI_SOURCE_ROOT??'C:/Users/adyba/pi-upstream-source-4954d76-20261015';
const runtime=await import(pathToFileURL(root+'/packages/coding-agent/src/core/model-runtime.ts'));
const abort=await import(pathToFileURL(root+'/packages/coding-agent/src/utils/abort.ts'));
const output=await observe({...runtime,...abort});
output.actualNode={version:process.version,execPath:process.execPath};
if(!process.argv[2])throw Error('Explicit fresh output path required');
writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n',{flag:'wx'});
