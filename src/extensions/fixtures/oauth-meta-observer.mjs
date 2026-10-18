// Actual Source/native Meta OAuth observations with controlled HTTP and timers.
// These controls do not establish live provider credentials or network qualification.
const MetaObject=Object, MetaPromise=Promise, MetaError=Error, MetaMap=Map, MetaJSON=JSON;
const metaAmbientNames=["Date","AbortSignal","URLSearchParams","URL","fetch","setTimeout","clearTimeout"];
export async function observeMeta(subject,route) {
    const saved=metaAmbientNames.map(name=>[name,MetaObject.getOwnPropertyDescriptor(globalThis,name)]);
    const trace=[];let clock=10000,pollCalls=0,timerId=0,aborted=route==="login-aborted";
    const listeners=new MetaMap(), timers=new MetaMap();
    const cancellation=new MetaError("controlled cancellation");
    const signal={
        get aborted(){trace.push(["signal.aborted",aborted]);return aborted},
        get reason(){trace.push(["signal.reason"]);return cancellation},
        throwIfAborted(){trace.push(["signal.throwIfAborted",this===signal]);if(aborted)throw cancellation},
        addEventListener(name,callback,options){trace.push(["signal.add",name,options.once,this===signal]);listeners.set(callback,name)},
        removeEventListener(name,callback){trace.push(["signal.remove",name,this===signal,listeners.has(callback)]);listeners.delete(callback)}
    };
    function install(name,value){MetaObject.defineProperty(globalThis,name,{value,writable:true,configurable:true})}
    function tagged(value,label) {
        if(value===null||typeof value!=="object")return value;
        const result={};
        for(const key of MetaObject.keys(value))MetaObject.defineProperty(result,key,{enumerable:true,configurable:true,get(){trace.push([label,key]);return value[key]}});
        return result;
    }
    function response(ok,status,value,label,jsonMode="normal") {
        const body=tagged(value,label+".json");
        const result={
            get ok(){trace.push([label,"ok"]);return ok},
            get status(){trace.push([label,"status"]);return status},
            get json(){trace.push([label,"json"]);return function(){
                trace.push([label,"json.call",this===result]);
                if(jsonMode==="throw")throw new MetaError("controlled json");
                return jsonMode==="reject"?MetaPromise.reject(new MetaError("controlled json")):MetaPromise.resolve(body)
            }}
        };
        return result;
    }
    function deviceResponse() {
        if(route==="device-http")return response(false,503,{error_description:" device unavailable "},"device");
        if(route==="device-error-fallback")return response(false,418,{error_description:" ",detail:7,message:" selected detail ",error:"later"},"device");
        const body={device_code:"device",user_code:"user",verification_uri_complete:"https://verify.meta.test/complete",verification_uri:"https://verify.meta.test/",interval:1,expires_in:60};
        if(route==="device-empty-code")body.device_code="";
        if(route==="device-nonstring-user")body.user_code=7;
        if(route==="device-fallback-url")body.verification_uri_complete="file:///untrusted";
        if(route==="device-untrusted-url"){body.verification_uri_complete="file:///untrusted";body.verification_uri="javascript:untrusted"}
        if(route==="device-malformed-url")body.verification_uri_complete="not a URL";
        if(route==="device-default-numbers"){body.interval=0;body.expires_in=Infinity}
        return response(true,200,body,"device",route==="device-json-reject"?"reject":route==="device-json-throw"?"throw":"normal");
    }
    function pollResponse() {
        const count=++pollCalls;if(count>8)throw new MetaError("controlled polling exhausted");
        if(route==="login-pending"&&count===1)return response(false,400,{error:"authorization_pending"},"poll");
        if(route==="login-slow"&&count===1)return response(false,400,{error:"slow_down",interval:3},"poll");
        if(route==="login-denied")return response(false,400,{error:"access_denied"},"poll");
        if(route==="login-expired")return response(false,400,{error:"expired_token"},"poll");
        if(route==="login-token-http")return response(false,500,{detail:" token unavailable "},"poll");
        if(route==="login-token-empty")return response(true,200,{access_token:"",message:" token absent "},"poll");
        if(route==="login-token-json")return response(false,500,null,"poll","reject");
        return response(true,200,{access_token:"identity-token"},"poll");
    }
    function mintResponse() {
        if(route==="mint-401"||route==="login-mint-401")return response(false,401,{error_description:" sign in "},"mint");
        if(route==="mint-403")return response(false,403,{detail:"expired"},"mint");
        if(route==="mint-http")return response(false,502,{message:" service unavailable "},"mint");
        if(route==="mint-missing")return response(true,200,{},"mint");
        if(route==="mint-action")return response(true,200,{action_url:"https://setup.meta.test/"},"mint");
        if(route==="mint-untrusted-action")return response(true,200,{action_url:"file:///untrusted"},"mint");
        if(route==="mint-empty-key")return response(true,200,{api_key:""},"mint");
        if(route==="mint-nonstring-key")return response(true,200,{api_key:7},"mint");
        return response(true,200,{api_key:"model-api-key"},"mint",route==="mint-json-reject"?"reject":route==="mint-json-throw"?"throw":"normal");
    }
    try {
        install("Date",{now(){trace.push(["Date.now",clock]);return clock}});
        const abort={timeout(ms){trace.push(["AbortSignal.timeout",ms,this===abort]);return {timeout:ms}},any(values){trace.push(["AbortSignal.any",this===abort,values.length,values[0].timeout,values[1]===signal]);return signal}};
        install("AbortSignal",abort);
        install("URLSearchParams",function(fields){
            trace.push(["URLSearchParams.new",MetaObject.keys(fields).map(key=>[key,fields[key]])]);
            const result={get toString(){trace.push(["URLSearchParams.toString"]);return function(){trace.push(["URLSearchParams.toString.call",this===result]);return "controlled-form"}}};
            return result;
        });
        install("URL",function(input){
            trace.push(["URL.new",input]);
            const match=/^([a-z]+:)/i.exec(input);if(!match)throw new MetaError("controlled invalid URL");
            return {get protocol(){trace.push(["URL.protocol",input]);return match[1]},get href(){trace.push(["URL.href",input]);return input}};
        });
        install("fetch",function(url,options){
            trace.push(["fetch",url,options.method,MetaObject.keys(options.headers).map(key=>[key,options.headers[key]]),options.body,options.signal===signal]);
            if(route==="login-fetch-throw"&&url.endsWith("/authorization/"))throw new MetaError("controlled network");
            if(route==="login-fetch-reject"&&url.endsWith("/authorization/"))return MetaPromise.reject(new MetaError("controlled network"));
            if(route==="login-fetch-abort"&&url.endsWith("/authorization/")){aborted=true;return MetaPromise.reject(cancellation)}
            if(route==="mint-fetch-throw"&&url.endsWith("/key"))throw new MetaError("controlled mint network");
            if(route==="mint-fetch-reject"&&url.endsWith("/key"))return MetaPromise.reject(new MetaError("controlled mint network"));
            if(url.endsWith("/authorization/"))return MetaPromise.resolve(deviceResponse());
            if(url.endsWith("/token/"))return MetaPromise.resolve(pollResponse());
            if(url.endsWith("/key"))return MetaPromise.resolve(mintResponse());
            throw new MetaError("Unexpected controlled endpoint");
        });
        install("setTimeout",(callback,ms)=>{
            const id=++timerId;timers.set(id,true);trace.push(["setTimeout",ms,id]);
            MetaPromise.resolve().then(()=>{
                if(!timers.has(id))return;timers.delete(id);clock+=ms;trace.push(["timer.fire",id]);
                if(route==="login-abort-poll"){aborted=true;for(const listener of [...listeners.keys()])listener();return}
                callback();
            });
            return id;
        });
        install("clearTimeout",id=>{trace.push(["clearTimeout",id]);timers.delete(id)});
        const interaction={get signal(){trace.push(["interaction.signal"]);return signal},notify(message){
            trace.push(["notify",message]);
            if(route==="login-notify-throw"&&message.type==="device_code")throw new MetaError("controlled notify");
            if(route==="login-progress-throw"&&message.type==="progress")throw new MetaError("controlled progress");
        }};
        let result;
        try {
            const output=route.startsWith("mint-")?await subject.refresh({get refresh(){trace.push(["credential.refresh"]);return "identity-token"}},signal):await subject.login(interaction);
            result={ok:true,value:output};
        } catch(error) {result={ok:false,name:error?.name??typeof error,message:error?.message??String(error)}}
        return {trace,result};
    } finally {
        for(const [name,descriptor]of saved){if(descriptor)MetaObject.defineProperty(globalThis,name,descriptor);else delete globalThis[name]}
    }
}
export async function compareMeta(native,source,routes) {
    const rows=[];
    for(const route of routes){
        const expected=await observeMeta(source,route),actual=await observeMeta(native,route);
        if(MetaJSON.stringify(actual)!==MetaJSON.stringify(expected))throw new MetaError("Meta Source mismatch "+route+"\nexpected="+MetaJSON.stringify(expected)+"\nactual="+MetaJSON.stringify(actual));
        rows.push({route,observed:actual});
    }
    return rows;
}
