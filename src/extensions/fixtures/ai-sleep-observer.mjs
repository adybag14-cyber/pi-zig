// Executes the actual Source and native ordinary producer under the same live
// constructor, timer, receiver and rejection observations.
async function observeSleep(fn, mode) {
    const savedPromise=globalThis.Promise, savedTimer=globalThis.setTimeout, savedClear=globalThis.clearTimeout;
    const trace=[];
    const reason={cancel:mode};
    let elapsed, onAbort, pending, outcome;
    const signal={
        get throwIfAborted(){trace.push("get:throwIfAborted");return function(){
            trace.push(["call:throwIfAborted",this===signal,arguments.length]);
            if(mode==="already-aborted")throw reason;
        }},
        get reason(){trace.push("get:reason");return reason},
        get addEventListener(){trace.push("get:add");return function(name,callback,options){
            onAbort=callback;
            trace.push(["call:add",this===signal,name,callback.name,callback.length,Object.keys(options),options.once,arguments.length]);
            if(mode==="abort-register")callback();
        }},
        get removeEventListener(){trace.push("get:remove");return function(name,callback){
            trace.push(["call:remove",this===signal,name,callback.name,callback.length,arguments.length]);
            if(mode==="tdz")callback();
        }}
    };
    try {
        globalThis.setTimeout=function(callback,ms){
            trace.push(["timer",callback.name,callback.length,ms,arguments.length]);
            elapsed=callback;
            if(mode==="tdz")callback();
            return 51;
        };
        globalThis.clearTimeout=function(handle){trace.push(["clear",handle,arguments.length])};
        if(mode==="live-constructor")globalThis.Promise=function(executor){
            trace.push(["construct",executor.name,executor.length,"prototype" in executor]);
            return {marker:"custom"};
        };
        if(mode==="constructor-throws")globalThis.Promise=function(){trace.push("construct:throw");throw reason};
        try {
            pending=mode==="constructible"?new fn(17,signal):fn(17,signal);
            trace.push(["return",pending instanceof savedPromise]);
        }catch(error){trace.push(["synchronous",error===reason]);outcome="sync"}
        if(pending instanceof savedPromise){
            if(mode==="elapsed"||mode==="constructible")elapsed();
            try{const result=await pending;outcome=["fulfilled",result===undefined]}
            catch(error){outcome=["rejected",error===reason,error instanceof ReferenceError,error?.message]}
        }else if(pending)outcome=["custom",pending.marker];
        return {trace,outcome};
    }finally{globalThis.Promise=savedPromise;globalThis.setTimeout=savedTimer;globalThis.clearTimeout=savedClear}
}
async function compareSleep(native, source) {
    const modes=["elapsed","constructible","already-aborted","abort-register","tdz","live-constructor","constructor-throws"];
    const rows=[];
    for(const mode of modes){
        const actual=await observeSleep(native,mode),expected=await observeSleep(source,mode);
        if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(mode+" sleep observation mismatch\nactual="+JSON.stringify(actual)+"\nsource="+JSON.stringify(expected));
        rows.push({mode,actual,expected});
    }
    return rows;
}
