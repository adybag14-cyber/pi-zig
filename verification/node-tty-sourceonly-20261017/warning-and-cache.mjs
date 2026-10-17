// Prepared fresh-process Node24 Source control, NOT executed/captured.
import tty from 'node:tty';
import os from 'node:os';
const depth=tty.WriteStream.prototype.getColorDepth;
const trace=[];const reason={};const emit=process.emitWarning;
try {
  process.emitWarning=function(...args){trace.push(['warning',this===process,...args]);throw reason};
  try{depth({FORCE_COLOR:'1',NODE_DISABLE_COLORS:'1',NO_COLOR:'1'})}catch(error){trace.push(['first-throws-same',error===reason])}
  process.emitWarning=function(...args){trace.push(['warning',this===process,...args]);return undefined};
  trace.push(['retry-depth',depth({FORCE_COLOR:'2',NODE_DISABLE_COLORS:'1',NO_COLOR:'1'})]);
  trace.push(['once-depth',depth({FORCE_COLOR:'3',NODE_DISABLE_COLORS:'1',NO_COLOR:'1'})]);
}finally{process.emitWarning=emit}
// getColorDepth's lexical OSRelease is initially untouched (FORCE_COLOR above).
const platform=Object.getOwnPropertyDescriptor(process,'platform');
const release=os.release;let calls=0;
try{
  Object.defineProperty(process,'platform',{...platform,value:'win32'});
  os.release=function(){calls++;trace.push(['release',this===undefined]);return release()};
  trace.push(['actual-release-depth',depth({}),calls]);
  os.release=()=>{throw reason};
  trace.push(['cached-depth',depth({}),calls]);
}finally{os.release=release;Object.defineProperty(process,'platform',platform)}
process.stdout.write(JSON.stringify(trace)+'\n');
