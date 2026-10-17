// Prepared ORIGINAL Node24.14 actual-console control. Never run against an
// arbitrary interactive terminal: Root's owned native fixture must supply a
// private console screen buffer as real stdout and a separate inherited fd3.
import tty from 'node:tty';
import fs from 'node:fs';
if(!tty.isatty(1))throw Error('Actual owned stdout console required');
const trace=[];
const stream=new tty.WriteStream(1);
const note=value=>trace.push(value);
stream.on('error',error=>note(['error',error.name,error.code,error.errno,error.syscall]));
note(['size',stream.getWindowSize(),stream.columns,stream.rows]);
note(['before-write',stream.writableLength,stream.bytesWritten]);
const returned=stream.write(Buffer.from('A\n'),()=>note(['callback',stream.writableLength,stream.bytesWritten]));
note(['after-write',returned,stream.writableLength,stream.bytesWritten]);
await Promise.resolve();note(['promise',stream.writableLength,stream.bytesWritten]);
await new Promise(setImmediate);note(['immediate',stream.writableLength,stream.bytesWritten]);
// Real cross-write UTF8 carry, CR/LF folding and libuv permissive decoding.
for(const bytes of [[0xf0],[0x9f,0x98],[0x80],[0x0d],[0x0a],[0x0d],[0x0a],[0xc0,0x80],[0xe2,0x41],[0xff],[0xed,0xa0,0x80]]){
  const buffer=Buffer.from(bytes);
  const ok=stream.write(buffer);
  note(['write',bytes,ok,stream.writableLength,stream.bytesWritten]);
}
// Source also distinguishes native String fast-dispatch counters from Buffer
// counters on failure. The fixture's independent negative case supplies a real
// output error; this successful case does not fabricate such a failure.
stream.write('STRING\n');
stream.write(Buffer.from('BUFFER\n'));
await new Promise(resolve=>stream.end(()=>{note(['finish',stream.writableLength,stream.bytesWritten]);resolve()}));
const closed=new Promise(resolve=>stream.once('close',()=>{note(['close',stream.destroyed]);resolve()}));
stream.destroy();await closed;
// Owned fd3 is a genuine native report pipe, not the console or a fake fd.
fs.writeSync(3,JSON.stringify(trace)+'\n');
