// Shared ambient-input observer; expected rows are executed upstream observations.
const EnvObject=Object, EnvMap=Map, EnvError=Error, EnvJSON=JSON;
export function observeProviderEnv(subject,route) {
    const names=["process","require","Map","Object"];
    const saved=names.map(name=>[name,EnvObject.getOwnPropertyDescriptor(globalThis,name)]);
    const trace=[];
    function install(name,value){EnvObject.defineProperty(globalThis,name,{value,writable:true,configurable:true})}
    let reads=0;
    try {
        const normal=new Proxy(route==="normal" ? {KEY:"process-value"} : {},{get(target,key){trace.push(["env.get",String(key)]);return target[key]}});
        install("process",route==="missing-process"?undefined:{env:normal,versions:{bun:route!=="no-bun"}});
        install("Object",{keys(value){trace.push(["Object.keys",value===normal]);return EnvObject.keys(value)}});
        install("Map",class extends EnvMap {
            constructor(){trace.push(["Map.new"]);if(route==="map-throws")throw new EnvError("map constructor");super()}
            set(key,value){trace.push(["Map.set",key,value]);return super.set(key,value)}
            get(key){trace.push(["Map.get",key]);if(route==="get-throws")throw new EnvError("cache get");return super.get(key)}
        });
        install("require",function(name){trace.push(["require",name,this===undefined]);if(route==="require-throws")throw new EnvError("controlled require");return {get readFileSync(){trace.push(["readFileSync.get"]);return function(path,encoding){trace.push(["readFileSync.call",path,encoding,this===undefined]);reads++;if(route==="read-throws")throw new EnvError("controlled read");return "KEY=proc-value\0EMPTY=\0INVALID\0=bad\0SECOND=a=b\0"}}}});
        const scoped=new Proxy(route==="override"?{KEY:"scope-value"}:route==="empty-override"?{KEY:""}:{},{get(target,key){trace.push(["scoped",String(key)]);return target[key]}});
        const values=[];
        let error;
        try {
            values.push(subject("KEY",scoped));
            if(route==="cache" || route==="read-throws" || route==="require-throws")values.push(subject("SECOND"),subject("MISSING"));
        } catch(reason){error={name:reason?.name,message:reason?.message??String(reason)}}
        return {route,trace,values,error,reads};
    } finally {
        for(const [name,descriptor] of saved)if(descriptor)EnvObject.defineProperty(globalThis,name,descriptor);else delete globalThis[name];
    }
}
export function compareProviderEnv(native,source,route) {
    const expected=observeProviderEnv(source,route),actual=observeProviderEnv(native,route);
    if(EnvJSON.stringify(actual)!==EnvJSON.stringify(expected))throw new EnvError("Actual provider-env Source mismatch "+route+"\nSource: "+EnvJSON.stringify(expected)+"\nNative: "+EnvJSON.stringify(actual));
    return actual;
}
