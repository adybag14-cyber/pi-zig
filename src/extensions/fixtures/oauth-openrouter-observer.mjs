// Actual private c268 OpenRouter bodies; controlled ambient guest operations.
// No callback/login, live account or network acceptance is implied.
const OObject=Object, OPromise=Promise, OError=Error, OJSON=JSON, OArray=Array;
const ambientNames=["AbortController","setTimeout","clearTimeout","fetch","JSON","Number","Array","Error","URL","URLSearchParams"];
function saveAmbient(){return ambientNames.map(name=>[name,OObject.getOwnPropertyDescriptor(globalThis,name)])}
function install(name,value){OObject.defineProperty(globalThis,name,{configurable:true,writable:true,value})}
function restore(saved){for(const [name,descriptor]of saved){if(descriptor)OObject.defineProperty(globalThis,name,descriptor);else delete globalThis[name]}}
function observationError(error,known){return {kind:typeof error,message:error instanceof OError?error.message:undefined,known:error===known}}
export async function observeOpenRouterExchange(subject,route){
    const saved=saveAmbient(),trace=[];
    const failure=new OError("controlled failure"),cleanupFailure=new OError("controlled cleanup"),keyValue={tag:"key"},expiryValue={tag:"expiry"};
    let aborted=route==="pre-aborted",controllerAborted=false,listener,timeoutCallback,okCalls=0,keyCalls=0;
    const timer={timer:true};
    const controllerSignal={get aborted(){trace.push(["controller.aborted",controllerAborted]);if(route==="controller-aborted-throw")throw failure;return controllerAborted}};
    const controller={
        get signal(){trace.push(["controller.signal"]);if(route==="controller-signal-throw")throw failure;return controllerSignal},
        abort(reason){trace.push(["controller.abort",this===controller,reason===failure?true:reason?.message]);controllerAborted=true}
    };
    const signal={
        get aborted(){trace.push(["signal.aborted",aborted]);if(route==="pre-aborted-getter-throw"||(route==="catch-aborted-throw"&&trace.some(x=>x[0]==="fetch")))throw failure;return aborted},
        get reason(){trace.push(["signal.reason"]);return failure},
        get addEventListener(){trace.push(["signal.add.get"]);return function(name,fn,options){trace.push(["signal.add",this===signal,name,fn.name,fn.length,options.once]);listener=fn;if(route==="add-throw")throw failure}},
        get removeEventListener(){trace.push(["signal.remove.get"]);return function(name,fn){trace.push(["signal.remove",this===signal,name,fn===listener]);if(route==="remove-throw")throw cleanupFailure}}
    };
    function tracked(fields,label){
        const result={};
        for(const [key,value]of OObject.entries(fields))OObject.defineProperty(result,key,{enumerable:true,configurable:true,get(){trace.push([label+"."+key]);return value}});
        return result;
    }
    let body=tracked({key:"permanent-key"},"body");
    if(route==="key-empty")body=tracked({key:""},"body");
    if(route==="key-number")body=tracked({key:42},"body");
    if(route==="key-missing")body={};
    if(route==="key-changing")body={get key(){trace.push(["body.key",++keyCalls]);return keyCalls<3?"validated":keyValue}};
    if(route==="key-getter-throw")body={get key(){trace.push(["body.key"]);throw failure}};
    if(route==="body-null")body=null;
    if(route==="body-array")body=[];
    if(route==="body-function")body=function(){};
    const httpFailure=route.startsWith("http-")||route==="json-http-failure"||route==="status-throw";
    if(route==="http-description")body=tracked({error_description:"described",message:"ignored",error:"ignored"},"body");
    if(route==="http-message")body=tracked({message:"message",error:"ignored"},"body");
    if(route==="http-error")body=tracked({error:"oauth-error"},"body");
    if(route==="http-nested")body=tracked({error:tracked({message:"nested"},"nested")},"body");
    if(route==="http-array")body=tracked({error:[]},"body");
    if(route==="http-empty")body={};
    const response={
        get ok(){trace.push(["response.ok",++okCalls]);if(route==="final-ok-throw"||route==="inner-ok-throw")throw failure;return !httpFailure},
        get status(){trace.push(["response.status"]);if(route==="status-throw")throw failure;return 401},
        get json(){trace.push(["response.json.get"]);return function(){
            trace.push(["response.json",this===response]);
            if(route==="json-throw")throw failure;
            if(route==="json-reject"||route==="json-http-failure"||route==="inner-ok-throw")return OPromise.reject(failure);
            if(route==="json-abort"){aborted=true;return OPromise.reject(failure)}
            return OPromise.resolve(body)
        }}
    };
    try{
        OObject.defineProperty(globalThis,"Error",{configurable:true,get(){trace.push(["Error.get"]);return OError}});
        install("AbortController",function(){trace.push(["AbortController",new.target!==undefined]);if(route==="constructor-throw")throw failure;return controller});
        install("setTimeout",function(fn,ms){trace.push(["setTimeout",fn.name,fn.length,ms]);timeoutCallback=fn;if(route==="timeout-throw")throw failure;return timer});
        install("clearTimeout",function(value){trace.push(["clearTimeout",value===timer]);if(route==="clear-throw"||route==="cleanup-replaces-fetch")throw cleanupFailure});
        install("JSON",{get stringify(){trace.push(["JSON.stringify.get"]);return function(payload){trace.push(["JSON.stringify",payload.code,payload.code_verifier,payload.code_challenge_method]);if(route==="stringify-throw")throw failure;return OJSON.stringify(payload)}}});
        install("Number",{get MAX_SAFE_INTEGER(){trace.push(["Number.MAX_SAFE_INTEGER"]);return route==="expiry-value"?expiryValue:9007199254740991}});
        install("Array",{get isArray(){trace.push(["Array.isArray.get"]);return function(value){trace.push(["Array.isArray",typeof value]);if(route==="array-predicate-throw")throw failure;return OArray.isArray(value)}}});
        install("fetch",function(url,init){
            trace.push(["fetch",this===undefined,url,init.method,init.headers.accept,init.headers["content-type"],init.body,init.signal===controllerSignal]);
            if(route==="abort-listener"){listener();return OPromise.reject(failure)}
            if(route==="token-timeout"){timeoutCallback();return OPromise.reject(failure)}
            if(route==="fetch-abort"){aborted=true;return OPromise.reject(failure)}
            if(route==="fetch-throw"||route==="cleanup-replaces-fetch")throw failure;
            if(route==="fetch-reject"||route==="catch-aborted-throw"||route==="controller-aborted-throw")return OPromise.reject(failure);
            return OPromise.resolve(response)
        });
        try{
            const value=await subject.exchangeAuthorizationCode("auth-code","verifier",signal);
            return {trace,result:{type:value.type,access:value.access===keyValue?"<key identity>":value.access,refresh:value.refresh,expires:value.expires===expiryValue?"<expiry identity>":value.expires}}
        }catch(error){return {trace,error:observationError(error,failure),cleanup:error===cleanupFailure}}
    }finally{restore(saved)}
}
export async function compareOpenRouterExchange(native,source,routes){
    const rows=[];
    for(const route of routes){
        const expected=await observeOpenRouterExchange(source,route),actual=await observeOpenRouterExchange(native,route);
        if(OJSON.stringify(expected)!==OJSON.stringify(actual))throw new OError("OpenRouter exchange "+route+" Source="+OJSON.stringify(expected)+" Native="+OJSON.stringify(actual));
        rows.push({route,observation:actual})
    }
    return rows
}
export function observeOpenRouterParse(subject,route){
    const saved=saveAmbient(),trace=[],failure=new OError("controlled parse"),identity={tag:"code"};
    let value=route==="empty"?"":route==="whitespace"?"   ":route==="raw"?"raw-code":route==="query"?"code=query":route==="url"?"https://callback/?code=url":"controlled";
    let trimmed=route==="whitespace"?"":value;
    if(route==="includes-value")trimmed={includes(needle){trace.push(["includes",needle,this===trimmed]);return true}};
    const input={get trim(){trace.push(["trim.get"]);if(route==="trim-getter-throw")throw failure;return function(){trace.push(["trim",this===input]);if(route==="trim-throw")throw failure;return trimmed}}};
    try{
        OObject.defineProperty(globalThis,"URL",{configurable:true,get(){trace.push(["URL.get"]);if(route==="url-getter-throw")throw failure;return function(argument){
            trace.push(["URL.construct",argument===trimmed,new.target!==undefined]);
            if(route==="raw"||route==="query"||route==="includes-value"||route==="query-null"||route==="query-getter-throw"||route==="query-call-throw"||route==="params-constructor-throw")throw failure;
            return {get searchParams(){trace.push(["url.searchParams"]);if(route==="search-throw")throw failure;return {get get(){trace.push(["params.get.get"]);if(route==="url-get-method-throw")throw failure;return function(key){trace.push(["params.get",key]);if(route==="url-get-call-throw")throw failure;return route==="url-null"?null:route==="url-undefined"?undefined:route==="url-identity"?identity:"url-code"}}}}}
        }}});
        OObject.defineProperty(globalThis,"URLSearchParams",{configurable:true,get(){trace.push(["URLSearchParams.get"]);if(route==="query-getter-throw")throw failure;return function(argument){
            trace.push(["URLSearchParams.construct",argument===trimmed,new.target!==undefined]);if(route==="params-constructor-throw")throw failure;
            return {get(key){trace.push(["query.get",key]);if(route==="query-call-throw")throw failure;return route==="query-null"?null:route==="includes-value"?identity:"query-code"}}
        }}});
        // Query failure routes must reach the actual includes branch after URL's
        // empty catch; the input is controlled, not a replacement parser.
        if(route.startsWith("query-")||route==="params-constructor-throw")trimmed="code=query";
        try{const code=subject.parseAuthorizationInput(input);return {trace,result:code===identity?"<identity>":code}}
        catch(error){return {trace,error:observationError(error,failure)}}
    }finally{restore(saved)}
}
export function observeOpenRouterDetail(subject,route){
    const saved=saveAmbient(),trace=[],failure=new OError("controlled detail");let errorGets=0;
    const nested={get message(){trace.push(["nested.message"]);if(route==="nested-throw")throw failure;return route==="nested-number"?7:"nested"}};
    const body={
        get error_description(){trace.push(["body.error_description"]);if(route==="description-throw")throw failure;return route==="description"?"description":undefined},
        get message(){trace.push(["body.message"]);if(route==="message-throw")throw failure;return route==="message"?"message":undefined},
        get error(){trace.push(["body.error",++errorGets]);if(route==="error-throw")throw failure;
            if(route==="error-string")return "string";
            if(route==="error-null")return null;
            if(route==="error-number")return 9;
            if(route==="error-array")return [];
            if(route==="error-function")return function(){};
            if(route==="changing-null-object"&&errorGets===3)return null;
            return nested
        }
    };
    try{
        OObject.defineProperty(globalThis,"Array",{configurable:true,get(){trace.push(["Array.get"]);return {get isArray(){trace.push(["Array.isArray.get"]);return function(value){trace.push(["Array.isArray",value===nested]);if(route==="array-throw")throw failure;return route==="array-truthy"?{}:OArray.isArray(value)}}}}});
        try{return {trace,result:subject.errorDetail(body)}}catch(error){return {trace,error:observationError(error,failure)}}
    }finally{restore(saved)}
}
export function compareOpenRouterSync(native,source,routes,kind){
    const observe=kind==="parse"?observeOpenRouterParse:observeOpenRouterDetail,rows=[];
    for(const route of routes){
        const expected=observe(source,route),actual=observe(native,route);
        if(OJSON.stringify(expected)!==OJSON.stringify(actual))throw new OError("OpenRouter "+kind+" "+route+" Source="+OJSON.stringify(expected)+" Native="+OJSON.stringify(actual));
        rows.push({route,observation:actual})
    }
    return rows
}
