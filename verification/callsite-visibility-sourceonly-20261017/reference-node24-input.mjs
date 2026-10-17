// Original Node/V8 observer only. No candidate implementation is imported.
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const filename = fileURLToPath(import.meta.url);
const saved = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
const rows = [];
const run = (name, body) => {
  const value = new vm.Script(body, { filename }).runInThisContext();
  rows.push({ name, value });
};
try {
  Error.prepareStackTrace = (error, frames) => frames;
  new vm.Script(`globalThis.ownedCapture = function ownedCapture(){const target={};Error.captureStackTrace(target,ownedCapture);return target.stack}`, { filename }).runInThisContext();
  run('sloppy-object', `globalThis.ownedReceiver={};function ownedSloppy(){return ownedCapture()}globalThis.ownedFrames=ownedSloppy.call(ownedReceiver);({sameFunction:ownedFrames[0].getFunction()===ownedSloppy,sameReceiver:ownedFrames[0].getThis()===ownedReceiver,topLevelFunctionUndefined:ownedFrames[1].getFunction()===undefined,topLevelReceiverGlobal:ownedFrames[1].getThis()===globalThis})`);
  run('strict-poison', `globalThis.ownedYoungReceiver={};function ownedYoung(){return ownedCapture()}function ownedStrict(){'use strict';return ownedYoung.call(ownedYoungReceiver)}function ownedOlder(){return ownedStrict()}globalThis.ownedFrames=ownedOlder();ownedFrames.slice(0,3).map((frame,index)=>({index,functionUndefined:frame.getFunction()===undefined,receiverUndefined:frame.getThis()===undefined,youngerFunction:frame.getFunction()===ownedYoung,youngerReceiver:frame.getThis()===ownedYoungReceiver}))`);
  run('method-eval-spelling', `globalThis.ownedMethod={'<eval>'(){return ownedCapture()}};globalThis.ownedFrames=ownedMethod['<eval>']();({sameFunction:ownedFrames[0].getFunction()===ownedMethod['<eval>'],sameReceiver:ownedFrames[0].getThis()===ownedMethod,topLevelUndefined:ownedFrames[1].getFunction()===undefined})`);
  run('sloppy-box-identity', `function ownedUsesThis(){return [ownedCapture(),ownedCapture(),this]}function ownedUnusedThis(){return [ownedCapture(),ownedCapture()]}globalThis.ownedUsed=ownedUsesThis.call('boxed');globalThis.ownedUnused=ownedUnusedThis.call('unused');({usedSame:ownedUsed[0][0].getThis()===ownedUsed[2]&&ownedUsed[1][0].getThis()===ownedUsed[2],unusedSame:ownedUnused[0][0].getThis()===ownedUnused[1][0].getThis(),unusedValue:ownedUnused[0][0].getThis().valueOf()})`);
  await new vm.Script(`globalThis.ownedAsyncReceiver={};async function ownedAsync(){await 0;globalThis.ownedAsyncFrames=ownedCapture()}ownedAsync.call(ownedAsyncReceiver)`, { filename }).runInThisContext();
  run('async-resume', `({sameFunction:ownedAsyncFrames[0].getFunction()===ownedAsync,sameReceiver:ownedAsyncFrames[0].getThis()===ownedAsyncReceiver})`);
  await import('./fixtures/module-probe.mjs');
  rows.push({ name: 'actual-es-module-body', value: globalThis.ownedModuleObservation });
  process.stdout.write(JSON.stringify({ node: process.version, execPath: process.execPath, rows }, null, 2) + '\n');
} finally {
  if (saved) Object.defineProperty(Error, 'prepareStackTrace', saved);
  else delete Error.prepareStackTrace;
}
