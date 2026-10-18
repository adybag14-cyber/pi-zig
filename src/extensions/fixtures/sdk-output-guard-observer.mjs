// Actual Source/native export observer. Writable stream methods and timers are
// explicit adversarial guest inputs; the observer supplies no output queue.
export async function observeRawOutput(api, mode) {
    const NativePromise=Promise, NativeError=Error;
    const processObject=process, output=process.stdout;
    const writeDescriptor=Object.getOwnPropertyDescriptor(output,"write");
    const exitDescriptor=Object.getOwnPropertyDescriptor(processObject,"exit");
    const timerDescriptor=Object.getOwnPropertyDescriptor(globalThis,"setTimeout");
    const stringDescriptor=Object.getOwnPropertyDescriptor(globalThis,"String");
    const trace=[],timers=[];
    let attempts=0,settled=false,failure;
    const error=new NativeError("actual write failure");
    error.code=mode==="ENOBUFS"||mode==="EAGAIN"||mode==="EWOULDBLOCK"?mode:mode==="sync-retry"?"EAGAIN":"EPIPE";
    const record=text=>trace.push(text);
    try {
        Object.defineProperty(processObject,"exit",{configurable:true,writable:true,value:function(code){record("exit:"+code+":"+(this===processObject))}});
        Object.defineProperty(globalThis,"setTimeout",{configurable:true,writable:true,value:function(callback,delay){
            record("retry.timer:"+delay+":"+callback.length);timers.push(callback);return {timer:true};
        }});
        Object.defineProperty(output,"write",{configurable:true,get(){
            record("write:get");
            return function(text,callback){
                record("write:call:"+text+":"+(this===output)+":"+callback.name+":"+callback.length+":"+("prototype"in callback));
                if(text==="A"&&attempts++===0&&mode!=="success"&&mode!=="queue"){
                    if(mode==="sync-retry")throw error;
                    if(mode==="throw-string")throw "plain failure";
                    callback(error);return false;
                }
                callback();return true;
            };
        }});
        if(mode==="throw-string")Object.defineProperty(globalThis,"String",{configurable:true,writable:true,value:function(value){record("String:"+value);return value}});
        if(api.writeRawStdout("")!==undefined)throw new NativeError("Empty write must return");
        if(api.writeRawStdout("A")!==undefined)throw new NativeError("Ordinary write return");
        if(mode==="queue")api.writeRawStdout("B");
        const waiting=api.waitForRawStdoutBackpressure();
        waiting.then(()=>record("wait:fulfilled"),()=>record("wait:rejected"));
        const flushed=api.flushRawStdout();
        flushed.then(()=>{record("flush:fulfilled");settled=true},reason=>{failure=reason;record("flush:rejected");settled=true});
        record("caller:return");
        NativePromise.resolve().then(()=>record("caller:microtask"));
        for(let step=0;!settled&&step<200;step++){
            await NativePromise.resolve();
            if(timers.length){record("retry:fire");timers.shift()()}
        }
        if(!settled)throw new NativeError("Actual output did not settle within bounded jobs");
        return {mode,sameFailure:failure===error,message:failure?failure.message:null,trace};
    } finally {
        writeDescriptor?Object.defineProperty(output,"write",writeDescriptor):delete output.write;
        exitDescriptor?Object.defineProperty(processObject,"exit",exitDescriptor):delete processObject.exit;
        timerDescriptor?Object.defineProperty(globalThis,"setTimeout",timerDescriptor):delete globalThis.setTimeout;
        stringDescriptor?Object.defineProperty(globalThis,"String",stringDescriptor):delete globalThis.String;
    }
}
export async function compareRawOutput(native,source,mode){
    const expected=await observeRawOutput(source,mode),actual=await observeRawOutput(native,mode);
    if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({mode,expected,actual}));
    return actual;
}
