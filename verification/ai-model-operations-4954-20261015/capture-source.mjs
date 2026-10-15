import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import * as operations from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/utils/model-operations.ts';
import { ModelsError } from 'file:///C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/ai/src/utils/models-error.ts';
import { ModelsError as PublicModelsError } from '@earendil-works/pi-ai';

if (process.version !== 'v24.14.0') throw Error('Pinned Node24.14.0 required');
if (ModelsError !== PublicModelsError) throw Error('Canonical Source ModelsError identity differs');
globalThis.modelOperationNamespace = operations;
globalThis.CanonicalModelsError = ModelsError;
const input = readFileSync(process.argv[3]);
let timer;
try {
  await Promise.race([import('data:text/javascript,' + encodeURIComponent(input.toString('utf8'))), new Promise((_, reject) => {timer = setTimeout(() => reject(Error('Model operation capture10s deadline')), 10000);})]);
} finally {clearTimeout(timer);}
if (modelOperationCaptureComplete !== true || modelOperationRows.length !== 88 || new Set(modelOperationRows.map(row => row.name)).size !== modelOperationRows.length) throw Error('Complete unique88 model-operation corpus required');
for (const name of Object.keys(operations)) if (!modelOperationRows.some(row => row.name === 'metadata:' + name)) throw Error('Original exported function missing ' + name);
const document = {sourceHead: '4954d760504c11df9b2cbdc040346107b6a8153d', cases: modelOperationRows.length, inputSha256: createHash('sha256').update(input).digest('hex'), canonicalModelsErrorIdentity: ModelsError === PublicModelsError, scope: 'Actual original eight model-operation functions and canonical ModelsError. Explicit VM-error cases compare error class only; full original name/message/stack diagnostics retained separately without rewriting.', rows: modelOperationRows};
writeFileSync(process.argv[2], JSON.stringify(document, null, 2) + '\n');
writeFileSync(process.argv[2] + '.raw-diagnostics.json', JSON.stringify({sourceHead: document.sourceHead, inputSha256: document.inputSha256, diagnostics: modelOperationRawDiagnostics}, null, 2) + '\n');
