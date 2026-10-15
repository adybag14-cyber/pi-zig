// Real guest entry for Source and native fork-driver observations. The host
// supplies the genuine module specifier for its own runtime, never a fake API.
const {childControl}=await import(process.env.CHORD_GUEST_NODE_API);
const control=childControl();
try{
 await control.lock();
 const init=await control.init;
 process.stdout.write('child stdout\n');
 process.stderr.write('child stderr\n');
 process.send({meta:{payload:init.payload,args:process.argv.slice(2),lockPresent:process.env.CHORD2_LOCK!==undefined,lockMatches:(process.env.CHORD2_LOCK??null)===init.expectedLock,privateTransportExposed:process.env.PI_NATIVE_CHORD_IPC_PORT!==undefined||process.env.PI_NATIVE_CHORD_IPC_TOKEN!==undefined}});
 control.report({activeCalls:1,viewers:2,durableTasks:3});
 control.onShutdown(()=>{
  control.report({activeCalls:0,viewers:0,durableTasks:0});
  process.send({final:true},()=>process.exit(0));
 });
 control.ready();
}catch(error){control.fatal(error);process.exit(1)}
