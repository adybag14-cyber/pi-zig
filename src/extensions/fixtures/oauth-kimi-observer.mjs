// Observes the actual upstream and native OAuth exports with identical ambient inputs.
// Network responses and timer completion are explicit controls, not live service evidence.
const KimiObject = Object;
const KimiPromise = Promise;
const KimiError = Error;
const KimiMap = Map;
const KimiJSON = JSON;
const kimiAmbientNames = ["process","Date","AbortSignal","URLSearchParams","URL","fetch","setTimeout","clearTimeout"];
export async function observeKimi(subject, route) {
    const saved = kimiAmbientNames.map(name => [name, KimiObject.getOwnPropertyDescriptor(globalThis,name)]);
    const trace = [];
    let clock = 10000, tokenCalls = 0, timerId = 0, aborted = route === "login-aborted" || route === "refresh-aborted";
    const listeners = new KimiMap();
    const timers = new KimiMap();
    const cancellation = new KimiError("controlled cancellation");
    const signal = {
        get aborted() { trace.push(["signal.aborted",aborted]); return aborted; },
        get reason() { trace.push(["signal.reason"]); return cancellation; },
        throwIfAborted() { trace.push(["signal.throwIfAborted",this===signal]); if(aborted)throw cancellation; },
        addEventListener(name, callback, options) { trace.push(["signal.add",name,options.once,this===signal]); listeners.set(callback,name); },
        removeEventListener(name, callback) { trace.push(["signal.remove",name,this===signal,listeners.has(callback)]); listeners.delete(callback); }
    };
    function install(name,value) { KimiObject.defineProperty(globalThis,name,{value,writable:true,configurable:true}); }
    const env = new Proxy({}, {get(_,name) { trace.push(["env",String(name)]); return route === "host-override" && name === "KIMI_CODE_OAUTH_HOST" ? "https://controlled.kimi.test////" : undefined; }});
    const process = { env, versions: {} };
    function taggedJSON(value,label) {
        if(value===null || typeof value!=="object")return value;
        const result=Array.isArray(value)?[]:{};
        for(const key of KimiObject.keys(value))KimiObject.defineProperty(result,key,{enumerable:true,configurable:true,get(){trace.push([label,key]);return value[key]}});
        return result;
    }
    function makeResponse(ok,status,value,label,textValue="controlled text",jsonFailure=false,textMode="normal") {
        const body=taggedJSON(value,label+".json");
        const result={
            get ok(){trace.push([label,"ok"]);return ok},
            get status(){trace.push([label,"status"]);return status},
            get json(){trace.push([label,"json"]);return function(){trace.push([label,"json.call",this===result]);return jsonFailure?KimiPromise.reject(new KimiError("controlled json")):KimiPromise.resolve(body)}},
            get text(){trace.push([label,"text"]);return function(){trace.push([label,"text.call",this===result]);if(textMode==="throw")throw new KimiError("controlled sync text");return textMode==="reject"?KimiPromise.reject(new KimiError("controlled rejected text")):KimiPromise.resolve(textValue)}}
        };
        return result;
    }
    const token = {access_token:"controlled-access",refresh_token:"controlled-refresh",expires_in:60};
    function fetchResult(url) {
        if(url.endsWith("/device_authorization")) {
            if(route==="device-http")return makeResponse(false,503,null,"device");
            if(route==="device-text-reject")return makeResponse(false,503,null,"device","",false,"reject");
            if(route==="device-text-throw")return makeResponse(false,503,null,"device","",false,"throw");
            const device={device_code:"device-code",user_code:"user-code",verification_uri:"https://verify.kimi.test/",verification_uri_complete:"https://verify.kimi.test/?code=user-code",interval:1,expires_in:60};
            if(route==="device-invalid-fields")device.device_code=7;
            if(route==="device-untrusted-url")device.verification_uri_complete="file:///controlled";
            if(route==="device-defaults"){device.interval=0;device.expires_in=Infinity}
            return makeResponse(true,200,device,"device","",route==="device-json-reject");
        }
        const index=++tokenCalls;
        if(index>10)throw new KimiError("controlled fetch route exhausted");
        if(route.startsWith("refresh-")) {
            if(route==="refresh-network-throw" && index===1)throw new KimiError("controlled network");
            if((route==="refresh-network-reject" && index===1) || route==="refresh-network-exhausted")return KimiPromise.reject(new KimiError("controlled network"));
            if(route==="refresh-unauthorized")return makeResponse(false,401,{error:"bad",error_description:"credential expired"},"refresh");
            if(route==="refresh-invalid-grant")return makeResponse(false,400,{error:"invalid_grant",error_description:"credential expired"},"refresh");
            if(route==="refresh-retry-exhausted" || ((route==="refresh-503" || route==="refresh-abort-backoff") && index===1))return makeResponse(false,503,{error:"unavailable"},"refresh");
            if(route==="refresh-429" && index===1)return makeResponse(false,429,{error:"rate"},"refresh");
            if(route==="refresh-other")return makeResponse(false,418,{error:"teapot"},"refresh");
            if(route==="refresh-missing")return makeResponse(true,200,{access_token:"only-access"},"refresh");
            return makeResponse(true,200,token,"refresh","",route==="refresh-json-reject");
        }
        if(route==="login-pending" && index===1)return makeResponse(false,400,{error:"authorization_pending",error_description:"waiting"},"poll");
        if(route==="login-slow" && index===1)return makeResponse(false,400,{error:"slow_down",interval:3},"poll");
        if(route==="login-expired")return makeResponse(false,400,{error:"expired_token"},"poll");
        if(route==="login-denied")return makeResponse(false,400,{error:"access_denied"},"poll");
        if(route==="login-server")return makeResponse(false,503,null,"poll");
        if(route==="login-other")return makeResponse(false,400,{error:"custom_error",error_description:"detail"},"poll");
        if(route==="login-missing")return makeResponse(true,200,{access_token:"only-access"},"poll");
        return makeResponse(true,200,token,"poll");
    }
    try {
        install("process",process);
        install("Date",{now(){trace.push(["Date.now",clock]);return clock}});
        const abort={timeout(ms){trace.push(["AbortSignal.timeout",ms,this===abort]);return {controlledTimeout:ms}},any(values){trace.push(["AbortSignal.any",this===abort,values.length,values[0].controlledTimeout,values[1]===signal]);return signal}};
        install("AbortSignal",abort);
        install("URLSearchParams",function URLSearchParams(fields){trace.push(["URLSearchParams",KimiObject.keys(fields)]);const entries=KimiObject.keys(fields).map(k=>[k,fields[k]]);return {toString(){trace.push(["URLSearchParams.toString",entries]);return entries.map(([k,v])=>encodeURIComponent(k)+"="+encodeURIComponent(String(v))).join("&")}}});
        install("URL",function URL(value){trace.push(["URL",value]);const protocol=String(value).split(":")[0]+":";return {get protocol(){trace.push(["URL.protocol",protocol]);return protocol},get href(){trace.push(["URL.href",value]);return value}}});
        install("setTimeout",(callback,ms)=>{const id=++timerId;trace.push(["setTimeout",ms]);timers.set(id,callback);KimiPromise.resolve().then(()=>{if(!timers.has(id))return;timers.delete(id);clock+=ms;if(route==="refresh-abort-backoff")aborted=true;trace.push(["timer",ms]);callback()});return id});
        install("clearTimeout",id=>{trace.push(["clearTimeout",id]);timers.delete(id)});
        install("fetch",function(url,options){trace.push(["fetch",this===undefined,url,options.method,KimiObject.keys(options.headers),options.headers["Content-Type"],options.headers.Accept,options.body,options.signal===signal]);return KimiPromise.resolve(fetchResult(url))});
        let value, error;
        try {
            value=route.startsWith("refresh-")?await subject.refresh({refresh:"stored-refresh"},signal):await subject.login({get signal(){trace.push(["interaction.signal"]);return signal},notify(input){trace.push(["notify",input])}});
        } catch(reason) { error={name:reason?.name,message:reason?.message ?? String(reason)}; }
        return {route,trace,value,error};
    } finally {
        for(const [name,descriptor] of saved)if(descriptor)KimiObject.defineProperty(globalThis,name,descriptor);else delete globalThis[name];
    }
}
export async function compareKimi(native,source,routes) {
    const rows=[];
    for(const route of routes) {
        const expected=await observeKimi(source,route);
        const actual=await observeKimi(native,route);
        if(KimiJSON.stringify(actual)!==KimiJSON.stringify(expected))throw new KimiError("Actual Kimi Source mismatch "+route+"\nSource: "+KimiJSON.stringify(expected)+"\nNative: "+KimiJSON.stringify(actual));
        rows.push({route,observation:actual});
    }
    return rows;
}
