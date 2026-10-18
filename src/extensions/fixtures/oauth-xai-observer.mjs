// Actual c268 Source/native xAI observations with controlled HTTP and timers.
// These controls do not establish live account or network qualification.
const XaiObject=Object, XaiPromise=Promise, XaiError=Error, XaiMap=Map, XaiJSON=JSON, XaiArray=Array;
const xaiAmbientNames=["Date","URLSearchParams","URL","fetch","setTimeout","clearTimeout"];
export async function observeXai(subject,route) {
    const saved=xaiAmbientNames.map(name=>[name,XaiObject.getOwnPropertyDescriptor(globalThis,name)]);
    const trace=[];let clock=10000,pollCalls=0,timerId=0,aborted=route==="login-aborted";
    const listeners=new XaiMap(),timers=new XaiMap();
    const cancellation=new XaiError("controlled cancellation");
    const signal={
        get aborted(){trace.push(["signal.aborted",aborted]);if(route==="login-catch-signal-throw")throw new XaiError("controlled signal");return aborted},
        get reason(){trace.push(["signal.reason"]);return cancellation},
        throwIfAborted(){trace.push(["signal.throwIfAborted",this===signal]);if(aborted)throw cancellation},
        addEventListener(name,callback,options){trace.push(["signal.add",name,options.once,this===signal]);listeners.set(callback,name)},
        removeEventListener(name,callback){trace.push(["signal.remove",name,this===signal,listeners.has(callback)]);listeners.delete(callback)}
    };
    function install(name,value){XaiObject.defineProperty(globalThis,name,{value,writable:true,configurable:true})}
    function tagged(value,label){
        if(value===null||typeof value!=="object"||XaiArray.isArray(value))return value;
        const result={};
        for(const key of XaiObject.keys(value))XaiObject.defineProperty(result,key,{enumerable:true,configurable:true,get(){trace.push([label,key]);return value[key]}});
        return result;
    }
    function response(ok,status,value,label,jsonMode="normal"){
        const body=tagged(value,label+".json");
        const result={
            get ok(){trace.push([label,"ok"]);if(route==="device-ok-throw"&&label==="device")throw new XaiError("controlled ok getter");return ok},
            get status(){trace.push([label,"status"]);if(route==="refresh-status-throw")throw new XaiError("controlled status getter");return status},
            get json(){trace.push([label,"json"]);return function(){
                trace.push([label,"json.call",this===result]);
                if(jsonMode==="throw")throw new XaiError("controlled json");
                if(jsonMode==="abort"){aborted=true;return XaiPromise.reject(cancellation)}
                return jsonMode==="reject"?XaiPromise.reject(new XaiError("controlled json")):XaiPromise.resolve(body)
            }}
        };
        return result;
    }
    function deviceResponse(){
        if(route==="device-http")return response(false,503,{error:"temporarily_unavailable",error_description:" device unavailable "},"device");
        if(route==="device-http-empty-detail")return response(false,418,{error:7,error_description:null},"device");
        if(route==="device-array-body")return response(true,200,[],"device");
        if(route==="device-null-body")return response(true,200,null,"device");
        if(route==="device-function-body")return response(true,200,function invalidBody(){},"device");
        const body={device_code:"device",user_code:"user",verification_uri_complete:"https://verify.xai.test/complete",verification_uri:"https://verify.xai.test/",interval:1,expires_in:60};
        if(route==="device-empty-code")body.device_code="";
        if(route==="device-nonstring-user")body.user_code=7;
        if(route==="device-no-complete")delete body.verification_uri_complete;
        if(route==="device-empty-complete")body.verification_uri_complete="";
        if(route==="device-http-url")body.verification_uri="http://verify.xai.test/";
        if(route==="device-untrusted-url")body.verification_uri_complete="file:///untrusted";
        if(route==="device-malformed-url")body.verification_uri_complete="not a URL";
        if(route==="device-default-interval")body.interval=0;
        if(route==="device-infinite-interval")body.interval=Infinity;
        if(route==="device-zero-expiry")body.expires_in=0;
        return response(true,200,body,"device",route==="device-json-reject"?"reject":route==="device-json-throw"?"throw":route==="device-json-abort"?"abort":"normal");
    }
    function tokenResponse(refresh){
        const label=refresh?"refresh":"poll";
        if(!refresh){
            const count=++pollCalls;if(count>8)throw new XaiError("controlled polling exhausted");
            if(route==="login-pending"&&count===1)return response(false,400,{error:"authorization_pending"},label);
            if((route==="login-slow"||route==="login-slow-zero")&&count===1)return response(false,400,{error:"slow_down",interval:route==="login-slow-zero"?0:3},label);
            if(route==="login-denied")return response(false,400,{error:"access_denied"},label);
            if(route==="login-authorization-denied")return response(false,400,{error:"authorization_denied"},label);
            if(route==="login-expired")return response(false,400,{error:"expired_token"},label);
            if(route==="login-token-http")return response(false,500,{error:"unknown_error",error_description:" token unavailable "},label);
        }
        if(route==="refresh-http")return response(false,401,{error:"invalid_grant",error_description:" sign in "},label);
        if(route==="refresh-array-body")return response(true,200,[],label);
        const body={access_token:"access-token",refresh_token:"new-refresh",expires_in:3600};
        if(route==="login-token-empty-access"||route==="refresh-empty-access")body.access_token="";
        if(route==="login-token-empty-refresh"||route==="refresh-empty-refresh")body.refresh_token="";
        if(route==="refresh-omitted-token"||route==="refresh-previous-object")delete body.refresh_token;
        if(route==="login-token-default-expiry"||route==="refresh-default-expiry")delete body.expires_in;
        if(route==="login-token-zero-expiry"||route==="refresh-zero-expiry")body.expires_in=0;
        if(route==="refresh-infinite-expiry")body.expires_in=Infinity;
        if(route==="refresh-nonstring-access")body.access_token=17;
        return response(true,200,body,label,route==="login-token-json"||route==="refresh-json-reject"?"reject":route==="refresh-json-throw"?"throw":route==="refresh-json-abort"?"abort":"normal");
    }
    try {
        install("Date",{now(){trace.push(["Date.now",clock]);return clock}});
        install("URLSearchParams",function(fields){
            const entries=XaiObject.keys(fields).map(key=>[key,fields[key]]);
            trace.push(["URLSearchParams.new",entries]);
            return {entries,get toString(){throw new XaiError("xAI does not stringify its form body explicitly")}};
        });
        install("URL",function(input){
            trace.push(["URL.new",input]);
            const match=/^([a-z]+:)/i.exec(input);if(!match)throw new XaiError("controlled invalid URL");
            return {get protocol(){trace.push(["URL.protocol",input]);if(route==="device-protocol-throw")throw new XaiError("controlled protocol");return match[1]},
                get href(){trace.push(["URL.href",input]);if(route==="device-href-throw")throw new XaiError("controlled href");return input}};
        });
        install("fetch",function(url,options){
            trace.push(["fetch",url,options.method,XaiObject.keys(options.headers).map(key=>[key,options.headers[key]]),options.body.entries,options.signal===signal]);
            const device=url.endsWith("/device/code");
            if(device&&(route==="login-fetch-throw"||route==="login-catch-signal-throw"))throw new XaiError("controlled network");
            if(device&&route==="login-fetch-reject")return XaiPromise.reject(new XaiError("controlled network"));
            if(device&&route==="login-fetch-abort"){aborted=true;return XaiPromise.reject(cancellation)}
            if(!device&&route==="refresh-fetch-throw")throw new XaiError("controlled refresh network");
            if(!device&&route==="refresh-fetch-reject")return XaiPromise.reject(new XaiError("controlled refresh network"));
            if(!device&&route==="refresh-fetch-abort"){aborted=true;return XaiPromise.reject(cancellation)}
            if(device)return XaiPromise.resolve(deviceResponse());
            if(url.endsWith("/token"))return XaiPromise.resolve(tokenResponse(route.startsWith("refresh-")));
            throw new XaiError("Unexpected controlled endpoint");
        });
        install("setTimeout",(callback,ms)=>{
            const id=++timerId;timers.set(id,true);trace.push(["setTimeout",ms,id]);
            XaiPromise.resolve().then(()=>{
                if(!timers.has(id))return;timers.delete(id);clock+=ms;trace.push(["timer.fire",id]);
                if(route==="login-abort-poll"){aborted=true;for(const listener of [...listeners.keys()])listener();return}
                callback();
            });
            return id;
        });
        install("clearTimeout",id=>{trace.push(["clearTimeout",id]);timers.delete(id)});
        const interaction={get signal(){trace.push(["interaction.signal"]);return signal},notify(message){
            trace.push(["notify",message]);if(route==="login-notify-throw")throw new XaiError("controlled notify");
        }};
        const previous=route==="refresh-previous-object"?{retained:"previous-refresh"}:"previous-refresh";
        let result;
        try{
            const output=route.startsWith("refresh-")?await subject.refresh({get refresh(){trace.push(["credential.refresh"]);return previous}},signal):await subject.login(interaction);
            if(route==="refresh-previous-object"&&output.refresh!==previous)throw new XaiError("Original previous token identity was replaced");
            result={ok:true,value:output};
        }catch(error){result={ok:false,name:error?.name??typeof error,message:error?.message??String(error)}}
        return {trace,result};
    }finally{
        for(const [name,descriptor]of saved){if(descriptor)XaiObject.defineProperty(globalThis,name,descriptor);else delete globalThis[name]}
    }
}
export async function compareXai(native,source,routes){
    const rows=[];
    for(const route of routes){
        const expected=await observeXai(source,route),actual=await observeXai(native,route);
        if(XaiJSON.stringify(actual)!==XaiJSON.stringify(expected))throw new XaiError("xAI Source mismatch "+route+"\nexpected="+XaiJSON.stringify(expected)+"\nactual="+XaiJSON.stringify(actual));
        rows.push({route,observed:actual});
    }
    return rows;
}
