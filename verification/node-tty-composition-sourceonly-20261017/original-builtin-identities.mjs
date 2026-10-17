// ORIGINAL Node24.14 caller inputs only; no captured results or expected values.
// Root must capture this through its admitted bounded reference owner later.
import tty, * as ttyNamespace from 'node:tty';
import ttyBare, * as ttyBareNamespace from 'tty';
import util from 'node:util';
import readline from 'node:readline';
import net from 'node:net';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const rows = [];
rows.push({name:'actual-import-carrier-identities', ttyDefault:tty === ttyBare,
  prefixedRequire:require('node:tty') === tty, bareRequire:require('tty') === tty,
  ctor:ttyNamespace.WriteStream === tty.WriteStream,
  bareCtor:ttyBareNamespace.WriteStream === tty.WriteStream,
  namespaces:ttyNamespace === ttyBareNamespace,
  util:require('util') === util, readline:require('readline') === readline});
rows.push({name:'canonical-socket-class-chain',
  read:Object.getPrototypeOf(tty.ReadStream) === net.Socket,
  write:Object.getPrototypeOf(tty.WriteStream) === net.Socket,
  readPrototype:Object.getPrototypeOf(tty.ReadStream.prototype) === net.Socket.prototype,
  writePrototype:Object.getPrototypeOf(tty.WriteStream.prototype) === net.Socket.prototype});
rows.push({name:'actual-jiti-prototype-call', value:tty?.WriteStream?.prototype?.hasColors?.() ?? false});
const trace = [];
const sink = {write(...args) { trace.push(['write', args[0], typeof args[1]]); return 'actual-write-return'; }};
for (const [name,args] of [['cursorTo',[1,2]],['moveCursor',[-2,3]],['clearLine',[-1]],['clearScreenDown',[]]]) {
  rows.push({name:`prototype-${name}`,value:Reflect.apply(tty.WriteStream.prototype[name],sink,args)});
}
rows.push({name:'live-write-trace',trace});
const noops=[];
const returned=readline.moveCursor(null,0,0,error=>noops.push(['callback',error]));
noops.push(['return',returned]);
await new Promise(resolve=>process.nextTick(resolve));
rows.push({name:'actual-nextTick-noop-order',trace:noops});
// This records the actual host capability. Absence is not a successful native
// console construction/control, and cannot qualify the frontend/backend.
rows.push({name:'actual-stdio-capabilities',fd0:tty.isatty(0),fd1:tty.isatty(1),fd2:tty.isatty(2)});
console.log(JSON.stringify(rows));
