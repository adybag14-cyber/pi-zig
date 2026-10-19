// Controlled lexical-import observations of the unchanged actual c268 bodies.
// These compare function behavior; they do not claim real HTTP or account login.
function anthropicCheck(value, message) {
    if (!value) throw new Error(message);
}
function anthropicAmbient(trace, route = "success") {
    const RealError = Error;
    function ObservedError(message) {
        const reason = new RealError(message);
        Object.defineProperty(reason, "stack", { value: undefined, configurable: true, writable: true });
        return reason;
    }
    ObservedError.prototype = RealError.prototype;
    globalThis.Error = ObservedError;
    globalThis.atob = (value) => {
        trace.push(["atob", value]);
        return "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    };
    globalThis.Date.now = () => { trace.push(["now"]); return 1_000_000; };
    globalThis.AbortSignal = {
        get any() {
            trace.push(["any:get"]);
            if (route === "any-get-throw") throw new Error("any getter");
            return function(signals) { trace.push(["any", signals.length, signals[0].tag, signals[1].tag]); return {tag:"combined"}; };
        },
        get timeout() {
            trace.push(["timeout:get"]);
            return function(ms) {
                trace.push(["timeout", ms]);
                if (route === "timeout-throw") throw new Error("timeout call");
                return {tag:"timeout"};
            };
        },
    };
    const stringify = JSON.stringify;
    globalThis.JSON.stringify = function(value) {
        trace.push(["stringify", value.grant_type ?? "body", Object.keys(value)]);
        if (route === "stringify-throw") throw new Error("stringify call");
        return stringify(value);
    };
    const parse = JSON.parse;
    globalThis.JSON.parse = function(text) {
        trace.push(["parse", typeof text]);
        if (route === "json-throw") throw new Error("json parse");
        return parse(text);
    };
    const tokenText = '{"refresh_token":"new-refresh","access_token":"new-access","expires_in":900}';
    globalThis.fetch = function(url, init) {
        trace.push(["fetch", typeof url === "string" ? url : "url-object", init.method, Object.keys(init.headers), init.body, init.signal.tag]);
        if (route === "fetch-throw") throw new Error("fetch call");
        if (route === "fetch-reject") return Promise.reject(new Error("fetch reject"));
        const response = {
            get text() {
                trace.push(["text:get"]);
                if (route === "text-get-throw") throw new Error("text getter");
                return function() {
                    trace.push(["text:call", this === response]);
                    if (route === "text-throw") throw new Error("text call");
                    if (route === "text-reject") return Promise.reject(new Error("text reject"));
                    if (route === "body-object") return Promise.resolve({
                        [Symbol.toPrimitive](hint) { trace.push(["body:hint",hint]); return "body-value"; },
                    });
                    return Promise.resolve(tokenText);
                };
            },
            get ok() { trace.push(["ok"]); if (route === "ok-throw") throw new Error("ok getter"); return !["http-failure","status-throw","body-object","url-object"].includes(route); },
            get status() {
                trace.push(["status"]);
                if (route === "status-throw") throw new Error("status getter");
                return { [Symbol.toPrimitive](hint) { trace.push(["status:hint",hint]); return 418; } };
            },
        };
        return Promise.resolve(response);
    };
    globalThis.URL = function(value) {
        trace.push(["URL", typeof value === "string" ? value : "object"]);
        if (route === "url-property-throw") return {get searchParams(){throw new Error("search params");}};
        if (typeof value !== "string" || !value.startsWith("https://return/")) throw new Error("not URL");
        return {get searchParams(){
            trace.push(["searchParams"]);
            return {get(name){trace.push(["url:get",name]);return name === "code" ? "url-code" : "verifier";}};
        }};
    };
    globalThis.URLSearchParams = function(input) {
        trace.push(["params",typeof input === "string" ? input : Object.keys(input).map(key=>[key,input[key]])]);
        if (route === "params-throw") throw new Error("params constructor");
        return {
            get(name){trace.push(["params:get",name]);return name==="code" ? "query-code" : "verifier";},
            toString(){
                trace.push(["params:toString"]);
                if (route === "params-text-object") return {[Symbol.toPrimitive](hint){trace.push(["params:hint",hint]);return "serialized";}};
                return "serialized";
            },
        };
    };
    return {stringify, parse, tokenText};
}
function anthropicImports(trace, route = "success") {
    let starts = 0;
    const callback = {
        get redirectUri() {
            trace.push(["redirectUri"]);
            if (route === "redirect-get-throw") throw new Error("redirect getter");
            return "http://localhost:45678/callback";
        },
        close() { trace.push(["close",this===callback]); if(route==="close-throw")throw new Error("close failure"); },
    };
    return {
        getProviderEnvValue(name) { trace.push(["env",name]); return undefined; },
        generatePKCE() {
            trace.push(["pkce"]);
            if(route==="pkce-reject")return Promise.reject(new Error("pkce reject"));
            return Promise.resolve({
                get verifier(){trace.push(["verifier"]);return "verifier";},
                get challenge(){trace.push(["challenge"]);return "challenge";},
            });
        },
        startOAuthCallbackServer(options) {
            trace.push(["start",options.providerName,options.host,options.port,options.path,options.redirectHost,options.state,options.signal.tag,
                options.complete.name,options.complete.length,anthropicIsAsync(options.complete)]);
            const complete=options.complete("completed");
            anthropicCheck(Object.getPrototypeOf(complete)===Promise.prototype,"actual zero Await complete promise");
            ++starts;
            if(route==="fallback-all"||(route==="fallback-once"&&starts===1))return Promise.reject(new Error("bind failure"));
            return Promise.resolve(callback);
        },
        waitForCallbackOrManualInput(interaction, actual, prompt) {
            trace.push(["wait",actual===callback,actual===undefined,prompt.message,prompt.placeholder,interaction.signal.tag]);
            if(route==="wait-reject")return Promise.reject(new Error("wait rejection"));
            if(route==="manual-mismatch")return Promise.resolve({type:"manual",input:"manual-code#wrong"});
            if(route==="manual-missing")return Promise.resolve({type:"manual",input:""});
            if(route==="manual")return Promise.resolve({type:"manual",input:"manual-code#verifier"});
            return Promise.resolve({type:"callback",value:"callback-code"});
        },
    };
}
function anthropicReason(reason) {
    return {name:reason?.name,message:reason?.message};
}
async function observeAnthropicToken(make, which, route) {
    const trace=[], ambient=anthropicAmbient(trace,route), subject=make(anthropicImports(trace,route));
    const signal={tag:"caller"};
    let outcome;
    try {
        const value=which==="post"
            ? await subject.postJson(route==="url-object" ? {[Symbol.toPrimitive](hint){trace.push(["url:hint",hint]);return "url-value";}} : "https://request/",{field:"value"},signal)
            : which==="exchange" ? await subject.exchangeAuthorizationCode("code","state","verifier","http://redirect/",signal)
            : await subject.refreshAnthropicToken("old-refresh",signal);
        outcome={value};
        if(which!=="post"&&route==="success")anthropicCheck(value.access==="new-access"&&value.refresh==="new-refresh"&&value.expires===1_600_000,"actual token fields and expiry");
    } catch(reason) {outcome={error:anthropicReason(reason)};}
    if(route==="http-failure"&&which==="post")anthropicCheck(outcome.error.message.startsWith("HTTP request failed. status=418; url=https://request/; body="),"actual post error text");
    return {trace,outcome};
}
async function observeAnthropicLogin(make, which, route) {
    const trace=[];anthropicAmbient(trace,route);const subject=make(anthropicImports(trace,route));
    const interaction={
        get signal(){trace.push(["signal"]);return {tag:"interaction"};},
        prompt(options){
            trace.push(["prompt",options.type,options.message,options.placeholder??null,options.signal?.tag??null,
                options.options?.map(x=>[x.id,x.label])??null]);
            if(route==="prompt-reject")return Promise.reject(new Error("prompt rejection"));
            if(options.type==="select")return Promise.resolve(which==="public-copy" ? "copy_code" : route==="unknown-method" ? {
                [Symbol.toPrimitive](hint){trace.push(["method:hint",hint]);return "unknown";}
            } : "browser");
            return Promise.resolve(route==="manual-mismatch" ? "manual-code#wrong" : route==="manual-missing" ? "" : "manual-code#verifier");
        },
        notify(value){
            trace.push(["notify",value.type,value.url??null,value.instructions??null,value.message??null]);
            if(route==="notify-throw")throw new Error("notify failure");
        },
    };
    let outcome;
    try {
        const value=which.startsWith("public") ? await subject.anthropicOAuth.login(interaction)
            : which==="copy" ? await subject.loginAnthropicCopyCode(interaction)
            : await subject.loginAnthropic(interaction);
        outcome={value};
    }catch(reason){outcome={error:anthropicReason(reason)};}
    const starts=trace.filter(x=>x[0]==="start").map(x=>x[3]);
    if(which==="browser"&&route==="fallback-once")anthropicCheck(starts.length===2&&starts[0]===53692&&starts[1]===0,"actual callback fallback ports");
    if(which==="browser"&&route==="fallback-all")anthropicCheck(starts.length===2&&!trace.some(x=>x[0]==="close"),"actual manual fallback has no callback close");
    if(which==="browser"&&route==="redirect-get-throw")anthropicCheck(!trace.some(x=>x[0]==="close"),"redirect selection precedes Source try/finally");
    if(which==="browser"&&route==="close-throw")anthropicCheck(outcome.error?.message==="close failure","actual finally replaces token result");
    if(which==="copy"||which==="public-copy")anthropicCheck(starts.length===0&&!trace.some(x=>x[0]==="close"),"copy-code uses no callback server");
    return {trace,outcome};
}
function observeAnthropicParser(make, route) {
    const trace=[];anthropicAmbient(trace,route);const subject=make(anthropicImports(trace,route));
    let input=({
        empty:"  ",raw:"bare-code",hash:"manual-code#verifier#discarded",url:"https://return/?code=x",
        query:"code=query-code&state=verifier","url-property-throw":"code=query-code","params-throw":"code=query-code",
    })[route]??"raw";
    if(route==="trim-throw")input={get trim(){trace.push(["trim:get"]);throw new Error("trim getter");}};
    if(route==="split-iterator"){
        input={trim(){return {
            includes(s){trace.push(["includes",s]);return s==="#";},
            split(separator,limit){
                trace.push(["split",separator,limit]);
                return {[Symbol.iterator](){
                    let n=0;return {next(){trace.push(["next",n]);return {done:false,value:n++===0?"code":"state"};},
                        get return(){trace.push(["return:get"]);return function(){trace.push(["return:call"]);return {};};}};
                }};
            },
        };}};
    }
    let outcome;try{outcome={value:subject.parseAuthorizationInput(input)};}catch(reason){outcome={error:anthropicReason(reason)};}
    if(route==="hash")anthropicCheck(outcome.value.code==="manual-code"&&outcome.value.state==="verifier","actual split limit");
    if(route==="split-iterator")anthropicCheck(trace.filter(x=>x[0]==="next").length===2&&trace.some(x=>x[0]==="return:call"),"actual two bindings and IteratorClose");
    return {trace,outcome};
}
function observeAnthropicDetails(make, route) {
    const trace=[];anthropicAmbient(trace,route);const subject=make(anthropicImports(trace,route));
    let value;
    const primitive=(name,result)=>({[Symbol.toPrimitive](hint){trace.push([name+":hint",hint]);if(route===name+"-hint-throw")throw new Error(name+" conversion");return result;}});
    if(route==="non-error")value=primitive("ordinary","plain");
    else{
        value=new Error("unused");
        Object.defineProperties(value,{
            name:{configurable:true,get(){trace.push(["name"]);return primitive("name","N");}},
            message:{configurable:true,get(){trace.push(["message"]);return primitive("message","M");}},
            code:{configurable:true,get(){trace.push(["code"]);return route==="no-extras" ? 0 : primitive("code","C");}},
            errno:{configurable:true,get(){trace.push(["errno"]);return route==="no-extras" ? undefined : 5;}},
            cause:{configurable:true,get(){trace.push(["cause"]);return route==="recursive" ? "nested" : undefined;}},
            stack:{configurable:true,get(){trace.push(["stack"]);return route==="no-extras" ? "" : primitive("stack","S");}},
        });
    }
    const string=String;globalThis.String=function(input){trace.push(["String",typeof input]);if(route==="errno-string-object"&&typeof input==="number")return primitive("String-result","five");return string(input);};
    let outcome;try{outcome={value:subject.formatErrorDetails(value)};}catch(reason){outcome={error:anthropicReason(reason)};}
    if(route==="no-extras")anthropicCheck(outcome.value==="N: M","actual minimal detail");
    if(route==="errno-string-object")anthropicCheck(outcome.value.includes("errno=five"),"explicit String result receives intrinsic template ToString");
    const nameHint=trace.findIndex(x=>x[0]==="name:hint"),message=trace.findIndex(x=>x[0]==="message");
    if(nameHint>=0&&message>=0)anthropicCheck(nameHint<message,"name ToString occurs before message getter");
    return {trace,outcome};
}
function observeAnthropicTemplateRetirement(make,hooks) {
    const trace=[];anthropicAmbient(trace);const subject=make(anthropicImports(trace));
    let reached=false;
    const reason=new Error("");
    Object.defineProperties(reason,{
        name:{get(){return {holder:hooks.make(0),[Symbol.toPrimitive](hint){anthropicCheck(hint==="string","intrinsic hint");return "Name";}};}},
        message:{get(){reached=hooks.count(0)===1;return "message";}},
        stack:{value:undefined,configurable:true},
    });
    const old=String.prototype.concat;
    Object.defineProperty(String.prototype,"concat",{configurable:true,get(){throw new Error("concat must not be selected");}});
    const value=subject.formatErrorDetails(reason);
    Object.defineProperty(String.prototype,"concat",{configurable:true,writable:true,value:old});
    anthropicCheck(value==="Name: message"&&reached,"temporary name retires before next substitution");
}
async function observeAnthropicOrdinaryData(make,hooks) {
    const trace=[];anthropicAmbient(trace);const subject=make(anthropicImports(trace));
    let reason,caught;
    try{await subject.anthropicOAuth.toAuth({get access(){reason=hooks.freshPrivateData();throw reason;}});}catch(error){caught=error;}
    anthropicCheck(caught===reason&&hooks.isUnmarkedPrivateData(caught),"same-operation DATA remains ordinary");
}
async function observeAnthropicActualFatal(make,hooks) {
    const trace=[];anthropicAmbient(trace);const subject=make(anthropicImports(trace));
    const progress=hooks.record;
    globalThis.fetch=()=>{const data=hooks.freshPrivateData();try{hooks.raiseNativeFatal();}catch{progress.guestReached=true;}throw data;};
    try{await subject.exchangeAuthorizationCode("code","state","verifier","uri",{tag:"caller"});}catch{progress.guestReached=true;hooks.visit(3);}
}

async function observeAnthropicEscapedRetry(make,hooks,terminal) {
    const trace=[];anthropicAmbient(trace);
    // This input does not retain the challenge after URL parameter construction.
    globalThis.URLSearchParams=function(){return {toString(){return "serialized";}};};
    const imports=anthropicImports(trace);
    imports.generatePKCE=()=>Promise.resolve({verifier:"verifier",challenge:{holder:hooks.make(0)}});
    let starts=0;
    const callback={redirectUri:"http://localhost:45678/callback",close(){}};
    imports.startOAuthCallbackServer=()=>{
        ++starts;
        if(starts>1)return Promise.resolve(callback);
        return {
            catch(retry){
                globalThis.anthropicEscapedRetry=retry;
                return {catch(){
                    return terminal ? Promise.resolve(callback) : new Promise(()=>{});
                }};
            },
        };
    };
    imports.waitForCallbackOrManualInput=()=>Promise.resolve({type:"callback",value:"code"});
    const s=make(imports);
    const interaction={signal:{tag:"interaction"},notify(){}};
    if(terminal){
        const result=await s.loginAnthropic(interaction);
        anthropicCheck(result.access==="new-access","browser reaches terminal exchange");
        anthropicCollect();
        anthropicCheck(hooks.count(0)===1,"closed retry capture must release uncaptured challenge");
        await anthropicEscapedRetry();
        anthropicCheck(starts===2&&hooks.count(0)===1,"closed retry retains only its original captured bindings");
    }else{
        // The returned login Promise is intentionally not retained. Only the
        // real escaped retry callback may keep the suspended activation alive.
        s.loginAnthropic(interaction);
        await 0;await 0;await 0;
        anthropicCheck(typeof anthropicEscapedRetry==="function","actual retry callback escaped");
        anthropicCollect();
        anthropicCheck(hooks.count(0)===0,"escaped retry keeps uncaptured suspended challenge alive");
        await anthropicEscapedRetry();
        anthropicCheck(starts===2&&hooks.count(0)===0,"live retry leaves original suspended activation retained");
    }
    delete globalThis.anthropicEscapedRetry;
    anthropicCollect();
    anthropicCheck(hooks.count(0)===1,"unreachable pending activation is collected after the last capture");
}


async function observeAnthropicExplicitErrorThrow(make,route,reason,progress) {
    const trace=[];
    const selected=route.endsWith("-state") ? "manual-mismatch" : route.endsWith("-code") ? "manual-missing" : "success";
    anthropicAmbient(trace,selected);
    const imports=anthropicImports(trace,selected);
    const wait=imports.waitForCallbackOrManualInput;
    imports.waitForCallbackOrManualInput=function(interaction,callback,prompt) {
        if(callback)callback.close=function(){progress.closed=true;};
        return wait(interaction,callback,prompt);
    };
    const subject=make(imports), originalError=Error;
    function SelectedError(message) { progress.constructed++; progress.message=message; return reason; }
    SelectedError.prototype=originalError.prototype;
    globalThis.Error=SelectedError;
    if(route==="browser-state"||route==="copy-state")globalThis.URL=function(){throw {url:"ordinary parse rejection"};};
    if(route==="post")globalThis.fetch=()=>Promise.resolve({ok:false,status:418,text(){return Promise.resolve("body");}});
    if(route.endsWith("-request"))globalThis.fetch=()=>Promise.reject({request:"ordinary"});
    if(route.endsWith("-json"))globalThis.JSON.parse=()=>{throw {json:"ordinary"};};
    const interaction={
        signal:{tag:"caller"},notify(){},
        prompt(options){return Promise.resolve(options.type==="select" ? "unknown-method" : selected==="manual-missing" ? "" : "manual-code#wrong");},
    };
    try {
        if(route==="post")await subject.postJson("url",{},{tag:"caller"});
        else if(route.startsWith("exchange-"))await subject.exchangeAuthorizationCode("code","state","verifier","uri",{tag:"caller"});
        else if(route.startsWith("refresh-"))await subject.refreshAnthropicToken("refresh",{tag:"caller"});
        else if(route.startsWith("browser-"))await subject.loginAnthropic(interaction);
        else if(route.startsWith("copy-"))await subject.loginAnthropicCopyCode(interaction);
        else await subject.anthropicOAuth.login(interaction);
        progress.guestReached=true;
    } catch { progress.guestReached=true; }
}
