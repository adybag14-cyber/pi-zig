// The actual callback module and actual page bodies execute in both realms.
// Only the imported HTTP host operations, timers and explicit hostile inputs
// are controlled. No callback helper is replaced by a success stub.
function callbackAssert(value,label){if(!value)throw Error(label)}
function callbackEqual(actual,expected,label){callbackAssert(JSON.stringify(actual)===JSON.stringify(expected),label)}
async function callbackThrown(call){try{await call()}catch(reason){return reason}throw Error("expected callback rejection")}
function callbackDeferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return{promise,resolve,reject}}
async function callbackUntil(done,label){for(let i=0;i<64&&!done();i++)await Promise.resolve();callbackAssert(done(),label)}
function callbackOptions(extra={}){return{providerName:"Example",host:"127.0.0.1",port:0,path:"/oauth/callback",complete(code){return{code}},...extra}}
function callbackHost(control,options={}){
    const trace=[],responses=[],once=new Map(),listeners=new Map();
    const host={trace,responses,listener:undefined,ready:undefined,closed:0,address:options.address??{port:18273}};
    const server={
        once(event,fn){trace.push("once:"+event);once.set(event,fn);return this},
        off(event,fn){trace.push("off:"+event);if(once.get(event)===fn)once.delete(event);return this},
        on(event,fn){trace.push("on:"+event);listeners.set(event,fn);return this},
        listen(port,name,fn){trace.push(["listen",port,name]);host.ready=fn;if(options.inline)fn();return this},
        address(){trace.push("address");return host.address},
        close(){trace.push("close");host.closed++;return this},
    };
    host.server=server;
    host.listen=function(){const fn=host.ready;host.ready=undefined;callbackAssert(typeof fn==="function","actual listen callback was installed");fn()};
    host.fail=function(reason){const fn=once.get("error")??listeners.get("error");callbackAssert(typeof fn==="function","real error listener selected");fn(reason)};
    host.request=function(target,method="GET",fields={}){
        const response={status:undefined,html:undefined,headers:undefined,
            writeHead(status,headers){trace.push(["writeHead",status]);this.status=status;this.headers=headers;return this},
            end(html){trace.push("end");this.html=html;responses.push(this);return this},
        };
        const request={url:target,method,...fields};
        callbackAssert(host.listener(request,response)===undefined,"request listener returns void");
        return response;
    };
    control.createServer=function(listener){trace.push("createServer");host.listener=listener;return server};
    return host;
}
function callbackTimers(){
    const descriptors=["setTimeout","clearTimeout"].map(name=>Object.getOwnPropertyDescriptor(globalThis,name)),trace=[],pending=[];
    globalThis.setTimeout=(fn,ms)=>{trace.push(["set",ms]);pending.push(fn);return pending.length};
    globalThis.clearTimeout=id=>{trace.push(["clear",id]);pending[id-1]=undefined};
    return{trace,pending,fire(index=0){const fn=pending[index];pending[index]=undefined;callbackAssert(typeof fn==="function","real timer callback installed");return fn()},
        restore(){["setTimeout","clearTimeout"].forEach((name,i)=>{if(descriptors[i])Object.defineProperty(globalThis,name,descriptors[i]);else delete globalThis[name]})}};
}
async function callbackStarted(api,host,options){const pending=api.startOAuthCallbackServer(options);host.listen();return await pending}
async function observeCallbackShapes(api){
    for(const[name,length]of[["startOAuthCallbackServer",1],["waitForCallbackOrManualInput",3]]){
        const fn=api[name];callbackAssert(fn.name===name&&fn.length===length&&Object.getPrototypeOf(fn)===Object.getPrototypeOf(async function(){})&&!Object.hasOwn(fn,"prototype"),"genuine async declaration "+name);
    }
}
async function observeCallbackListen(api,control){
    const host=callbackHost(control),pending=api.startOAuthCallbackServer(callbackOptions({redirectHost:"::1"}));
    callbackEqual(host.trace,["createServer","once:error",["listen",0,"127.0.0.1"]],"listen happens before first suspension");
    host.listen();const callback=await pending;
    callbackAssert(callback.redirectUri==="http://[::1]:18273/oauth/callback","live bound port and IPv6 redirect");
    callbackEqual(host.trace.slice(3),["off:error","address","on:error"],"listen callback completes before post Await body");
    for(const name of["wait","cancel","close"]){callbackAssert(callback[name].name===name&&callback[name].length===0&&!Object.hasOwn(callback[name],"prototype"),"actual returned arrow "+name)}
    callbackAssert(callback.wait()===callback.wait(),"wait returns original shared Promise");
    callback.cancel();callbackAssert(await callback.wait()===undefined,"cancel resolves actual waiter");
    callback.close();callbackAssert(host.closed===1,"close calls actual server method");
}
async function observeCallbackRoutes(api,control,page){
    for(const[method,target,status,message]of[
        ["POST","/oauth/callback",404,"Callback route not found."],
        ["GET","/other",404,"Callback route not found."],
        ["GET","/oauth/callback?state=wrong&code=x",400,"State mismatch."],
        ["GET","/oauth/callback?state=expected",400,"Missing authorization code."],
    ]){
        const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions({state:"expected"}));
        const response=host.request(target,method);await callbackUntil(()=>response.html!==undefined,"synchronous pre-Await page");
        callbackAssert(response.status===status&&response.html===page.oauthErrorHtml(message),"actual complete failure page");
        callbackEqual(response.headers,{"content-type":"text/html; charset=utf-8","cache-control":"no-store"},"actual sendPage header object");
        callback.cancel();await callback.wait();callback.close();
    }
    const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions());
    const wait=callback.wait().catch(reason=>reason);
    const response=host.request("/oauth/callback?error=denied&error_description=No%20thanks");
    const reason=await wait;
    callbackAssert(reason instanceof Error&&reason.message==="Example authorization failed: No thanks","actual provider error");
    callbackAssert(response.status===400&&response.html===page.oauthErrorHtml("Example authorization failed.","No thanks"),"actual provider error page");
    callback.close();
}
async function observeCallbackCompletion(api,control,page){
    const host=callbackHost(control),gate=callbackDeferred(),value={accepted:true};let calls=0;
    const callback=await callbackStarted(api,host,callbackOptions({complete(code){calls++;callbackAssert(this.path==="/oauth/callback"&&code==="the-code","actual complete receiver and code");return gate.promise}}));
    const response=host.request("/oauth/callback?code=the-code");
    callbackAssert(calls===1&&response.html===undefined,"real request Await is pending");
    const duplicate=host.request("/oauth/callback?code=again");
    callbackAssert(duplicate.status===409,"claimed state shared across request closures");
    callback.cancel();let settled=false;callback.wait().then(()=>{settled=true});
    await Promise.resolve();callbackAssert(!settled,"cancel does not settle a claimed request");
    gate.resolve(value);callbackAssert(await callback.wait()===value,"exact completed identity");
    callbackAssert(response.status===200&&response.html===page.oauthSuccessHtml("Signed in to Example. You may now close this page."),"actual completed page");
    callback.close();
}
async function observeCallbackRequestCatch(api,control,page){
    for(const reason of[new Error("backend rejected"),{toString(){return"ordinary reason"}}]){
        const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions({complete(){throw reason}}));
        const waiting=callback.wait().catch(value=>value),response=host.request("/oauth/callback?code=x"),failure=await waiting;
        callbackAssert(failure instanceof Error&&failure.message===(reason instanceof Error?reason.message:String(reason)),"actual request catch normalizes the reason");
        if(reason instanceof Error)callbackAssert(failure===reason,"existing Error identity");
        callbackAssert(response.status===502&&response.html===page.oauthErrorHtml("Example sign-in failed.",failure.message),"actual catch page");
        callback.close();
    }
}
async function observeCallbackStartFailures(api,control){
    control.createServer=()=>{throw Error("aborted start created a server")};
    const cancelled=await callbackThrown(()=>api.startOAuthCallbackServer(callbackOptions({signal:{aborted:true}})));
    callbackAssert(cancelled.message==="Login cancelled","initial cancellation before Promise/server");
    const error={},failed=callbackHost(control),waiting=api.startOAuthCallbackServer(callbackOptions());
    failed.fail(error);callbackAssert(await callbackThrown(()=>waiting)===error,"listen rejection identity");
    callbackEqual(failed.trace,["createServer","once:error",["listen",0,"127.0.0.1"]],"listen failure skips later address and close");
    for(const address of[null,"pipe"]){
        const host=callbackHost(control);host.address=address;
        const reason=await callbackThrown(()=>callbackStarted(api,host,callbackOptions()));
        callbackAssert(reason.message==="OAuth callback server did not bind to TCP"&&host.closed===1,"non TCP address closes then rejects");
    }
}
async function observeCallbackAbortTimeout(api,control){
    const timers=callbackTimers();try{
        const trace=[],signal={aborted:false,addEventListener(event,fn,options){trace.push(["add",event,options.once]);this.callback=fn},
            removeEventListener(event,fn){callbackEqual(timers.trace,[["set",7],["clear",1]],"timer cleared before live removeEventListener");trace.push(["remove",event,fn===this.callback])}};
        const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions({signal,timeoutMs:7}));
        const waiting=callback.wait().catch(reason=>reason);signal.callback();const reason=await waiting;
        callbackAssert(reason.message==="Login cancelled","abort resolves through actual finish");
        callbackEqual(timers.trace,[["set",7],["clear",1]],"actual finish clears timer before removing abort listener");
        callbackEqual(trace,[["add","abort",true],["remove","abort",true]],"same actual listener removed");
        callback.close();callbackAssert(trace.length===2,"settled finish does not clean twice");
        const secondHost=callbackHost(control),second=await callbackStarted(api,secondHost,callbackOptions({providerName:"Timed",timeoutMs:11}));
        const timeout=second.wait().catch(value=>value);timers.fire(1);
        callbackAssert((await timeout).message==="Timed sign-in timed out","actual timeout template and finish");
        second.close();
    }finally{timers.restore()}
}
async function observeCallbackPromise(api,control){
    const NativePromise=Promise,descriptor=Object.getOwnPropertyDescriptor(globalThis,"Promise"),trace=[];
    function Selected(executor){trace.push(["construct",executor.length,!Object.hasOwn(executor,"prototype")]);return new NativePromise(executor)}
    Object.defineProperty(globalThis,"Promise",{configurable:true,value:Selected,writable:true});
    try{
        const host=callbackHost(control),pending=api.startOAuthCallbackServer(callbackOptions());
        callbackAssert(pending instanceof NativePromise&&!(pending instanceof Selected),"actual intrinsic outer Promise");
        callbackEqual(trace,[["construct",2,true],["construct",2,true]],"two actual live Promise constructors");
        host.listen();const callback=await pending;callback.cancel();await callback.wait();callback.close();
    }finally{Object.defineProperty(globalThis,"Promise",descriptor)}
}
async function observeCallbackBindings(api,control,hooks){
    const names=["providerName","signal","port","host","timeoutMs","redirectHost","path"],saved=names.map(name=>Object.getOwnPropertyDescriptor(Number.prototype,name));
    let box,timeoutReads=0;const trace=[];
    for(const name of names)Object.defineProperty(Number.prototype,name,{configurable:true,get(){
        "use strict";trace.push(name);
        if(name==="providerName"){box=this;Object.defineProperty(this,"holder",{value:hooks.make(0)});return "Box"}
        if(name==="signal"){callbackAssert(this===box,"one actual destructuring receiver");box=null;return undefined}
        if(name==="port"){callbackAssert(hooks.count(0)===1,"binding receiver retires before later port lookup");return 0}
        if(name==="host")return"127.0.0.1";if(name==="path")return"/callback";
        if(name==="timeoutMs"){timeoutReads++;return undefined}
        return undefined;
    }});
    try{
        const host=callbackHost(control),callback=await callbackStarted(api,host,17);
        callbackAssert(callback.redirectUri==="http://127.0.0.1:18273/callback","actual primitive input later getters");
        callbackEqual(trace,["providerName","signal","port","host","timeoutMs","redirectHost","host","path"],"one BindingPattern and live subsequent reads");
        callbackAssert(timeoutReads===1,"undefined timeout avoids second read");callback.cancel();await callback.wait();callback.close();
    }finally{names.forEach((name,i)=>{if(saved[i])Object.defineProperty(Number.prototype,name,saved[i]);else delete Number.prototype[name]})}
    for(const input of[null,undefined])callbackAssert(await callbackThrown(()=>api.startOAuthCallbackServer(input)) instanceof TypeError,"nullish BindingPattern rejects");
}
async function observeCallbackManual(api,control){
    const callbackValue={},gate=callbackDeferred(),events=[];let promptRecord;
    const interaction={prompt(options){events.push("prompt");promptRecord=options;return gate.promise}};
    const callback={wait(){events.push("wait");return callbackValue},cancel(){events.push("cancel")}};
    const input={type:"custom_type",title:"Copied",signal:"must be replaced"};
    const pending=api.waitForCallbackOrManualInput(interaction,callback,input);
    callbackEqual(events,["prompt","wait"],"manual request begins before callback Await");
    const result=await pending;
    callbackAssert(result.type==="callback"&&result.value===callbackValue&&promptRecord.type==="custom_type"&&promptRecord.title==="Copied","actual spread and callback result");
    callbackAssert(promptRecord.signal instanceof AbortSignal&&promptRecord.signal.aborted,"actual finally aborts prompt signal");
    gate.resolve("late manual");await callbackUntil(()=>events.includes("cancel"),"real late manual then handler");
    const manual=await api.waitForCallbackOrManualInput({prompt(){return Promise.resolve(null)}},undefined,{});
    callbackEqual(manual,{type:"manual",input:""},"no callback still performs actual first Await and manual nullish result");
}
async function observeCallbackManualFailures(api){
    const original={message:"ordinary"},events=[],callback={wait(){events.push("wait");return new Promise(resolve=>{this.release=resolve})},cancel(){events.push("cancel");this.release()}};
    const pending=api.waitForCallbackOrManualInput({prompt(){return Promise.reject(original)}},callback,{});
    const reason=await callbackThrown(()=>pending);
    callbackAssert(reason instanceof Error&&reason.message==="[object Object]","manual catch performs actual Error(String)");
    callbackEqual(events,["wait","cancel"],"manual catch cancels after original wait call");
    const rejected={},kept=Promise.reject(rejected);kept.catch(()=>{});
    const same=await callbackThrown(()=>api.waitForCallbackOrManualInput({prompt(){return new Promise(()=>{})}},{wait(){return kept}},{}));
    callbackAssert(same===rejected,"callback Await rejection remains raw through normal finally");
    const before=Object.getOwnPropertyDescriptor(AbortController.prototype,"abort"),override={};
    Object.defineProperty(AbortController.prototype,"abort",{configurable:true,value(){throw override}});
    try{
        const reason=await callbackThrown(()=>api.waitForCallbackOrManualInput({prompt(){return new Promise(()=>{})}},{wait(){return 7}},{}));
        callbackAssert(reason===override,"ordinary finally failure replaces returned completion");
    }finally{Object.defineProperty(AbortController.prototype,"abort",before)}
}
async function observeCallbackPromptOutsideTry(api){
    const before=Object.getOwnPropertyDescriptor(AbortController.prototype,"abort"),reason={},trace=[];
    Object.defineProperty(AbortController.prototype,"abort",{configurable:true,value(){trace.push("abort")}});
    try{
        const thrown=await callbackThrown(()=>api.waitForCallbackOrManualInput({get prompt(){trace.push("prompt");throw reason}},undefined,{}));
        callbackAssert(thrown===reason&&trace.join()==="prompt","initial chain failure is outside Source try/finally");
        trace.length=0;
        const result=await callbackThrown(()=>api.waitForCallbackOrManualInput({prompt(){return {get then(){trace.push("then");throw reason}}}},undefined,{}));
        callbackAssert(result===reason&&trace.join()==="then","then lookup failure also precedes try");
    }finally{Object.defineProperty(AbortController.prototype,"abort",before)}
}
async function observeCallbackLateExecutor(api,control){
    const NativePromise=Promise,before=Object.getOwnPropertyDescriptor(globalThis,"Promise"),seen=[];let count=0,executor;
    function Selected(body){
        if(count++===0){executor=body;return{catch(){return undefined}}}
        return new NativePromise(body);
    }
    Object.defineProperty(globalThis,"Promise",{configurable:true,writable:true,value:Selected});
    try{
        const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions());
        executor(value=>seen.push(["resolve",value]),reason=>seen.push(["reject",reason]));
        executor=undefined;callback.cancel();callbackEqual(seen,[["resolve",undefined]],"late constructor executor assigns the original closed lexical cells");
        callback.close();
    }finally{Object.defineProperty(globalThis,"Promise",before)}
}
async function observeCallbackInheritedError(api,control){
    const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions()),token={},before=Object.getOwnPropertyDescriptor(Object.prototype,"error");
    const waiting=callback.wait().catch(reason=>reason);
    Object.defineProperty(Object.prototype,"error",{configurable:true,get(){return token}});
    try{callback.cancel();callbackAssert(await waiting===token,"actual in operator sees inherited error on value record")}
    finally{if(before)Object.defineProperty(Object.prototype,"error",before);else delete Object.prototype.error;callback.close()}
}

async function observeCallbackRequestOperands(api,control,hooks){
    const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions());
    const NativeURL=URL,before=Object.getOwnPropertyDescriptor(globalThis,"URL");let methodReads=0;
    Object.defineProperty(globalThis,"URL",{configurable:true,get(){
        const holder=hooks.make(0);return function(input,base){void holder;return new NativeURL(input,base)};
    }});
    try{
        const response={writeHead(status){callbackAssert(status===404,"actual route rejection");return this},end(){return this}};
        const request={get url(){const value=hooks.make(1);value.toString=()=>"/oauth/callback";return value},
            get method(){methodReads++;callbackAssert(hooks.count(0)===1&&hooks.count(1)===1,"URL constructor and input retire before method getter");return"POST"}};
        callbackAssert(host.listener(request,response)===undefined&&methodReads===1,"actual request body ran synchronously to return");
    }finally{Object.defineProperty(globalThis,"URL",before);callback.cancel();await callback.wait();callback.close()}
}
async function observeCallbackStatePredicate(api,control,hooks){
    const host=callbackHost(control),options=callbackOptions(),before=Object.getOwnPropertyDescriptor(globalThis,"URL");let reads=0,params=0;
    Object.defineProperty(options,"state",{get(){
        if(reads++===0)return hooks.make(0);
        callbackAssert(hooks.count(1)===1&&hooks.count(2)===1,"searchParams receiver and callee retire before second state getter");return"expected";
    }});
    function SelectedURL(){return{pathname:"/oauth/callback",get searchParams(){
        if(params++===0){
            callbackAssert(hooks.count(0)===1,"first state predicate retires before searchParams");
            const result=hooks.make(1);result.expectedReceiver=true;Object.defineProperty(result,"get",{get(){const holder=hooks.make(2);return function(name){void holder;callbackAssert(name==="state"&&this.expectedReceiver===true,"actual state method receiver");return"expected"}}});return result;
        }
        return{get(name){return name==="code"?"the-code":null}};
    }}}
    const callback=await callbackStarted(api,host,options);
    Object.defineProperty(globalThis,"URL",{configurable:true,writable:true,value:SelectedURL});
    try{
        host.request("/oauth/callback?state=expected&code=the-code");
        callbackAssert((await callback.wait()).code==="the-code"&&reads===2,"actual state branch and completion");
    }finally{Object.defineProperty(globalThis,"URL",before);callback.close()}
}
async function observeCallbackManualChain(api,hooks){
    const interaction={get prompt(){
        const holder=hooks.make(0);
        return function(){
            void holder;const result=hooks.make(1);
            Object.defineProperty(result,"then",{get(){
                callbackAssert(hooks.count(0)===1,"prompt callee retires before then getter");
                const callee=hooks.make(2);
                return function(){
                    void callee;const next=hooks.make(3);
                    Object.defineProperty(next,"catch",{get(){
                        callbackAssert(hooks.count(1)===1&&hooks.count(2)===1,"then receiver and callee retire before catch getter");
                        const last=hooks.make(4);return function(){void last;return Promise.resolve("manual-chain")};
                    }});return next;
                };
            }});return result;
        };
    }};
    const result=await api.waitForCallbackOrManualInput(interaction,undefined,{});
    callbackEqual(result,{type:"manual",input:"manual-chain"},"real manual chain output");
    callbackAssert(hooks.count(3)===1&&hooks.count(4)===1,"catch receiver and callee retire after call");
}
async function observeCallbackNormalizedError(api,hooks){
    const NativeError=Error,errorBefore=Object.getOwnPropertyDescriptor(globalThis,"Error"),stringBefore=Object.getOwnPropertyDescriptor(globalThis,"String"),reason={};let reads=0;
    Object.defineProperty(globalThis,"Error",{configurable:true,get(){
        if(reads++===0){const predicate=hooks.make(0);predicate[Symbol.hasInstance]=()=>false;return predicate}
        callbackAssert(reads===2&&hooks.count(0)===1,"instanceof constructor retires before constructor selection");
        const holder=hooks.make(1);return function(message){void holder;callbackAssert(hooks.count(2)===1,"String callee retires before Error construction");return new NativeError(message)};
    }});
    Object.defineProperty(globalThis,"String",{configurable:true,get(){
        callbackAssert(reads===2&&hooks.count(0)===1&&hooks.count(1)===0,"Error constructor selected before String lookup");
        const holder=hooks.make(2);return function(value){void holder;callbackAssert(value===reason,"raw caught reason passed to String");return"normalized"};
    }});
    try{
        const failure=await callbackThrown(()=>api.waitForCallbackOrManualInput({prompt(){return Promise.reject(reason)}},undefined,{}));
        callbackAssert(failure instanceof NativeError&&failure.message==="normalized"&&hooks.count(1)===1,"normalized result and completed constructor");
    }finally{Object.defineProperty(globalThis,"Error",errorBefore);Object.defineProperty(globalThis,"String",stringBefore)}
}
async function observeCallbackStartCaptures(api,control,hooks){
    const host=callbackHost(control);
    const pending=api.startOAuthCallbackServer.call(hooks.make(2),Object.assign(hooks.make(0),callbackOptions()),hooks.make(1));
    callbackAssert([0,1,2].every(slot=>hooks.count(slot)===0),"argument and receiver roots survive actual listen Await");
    host.listen();const callback=await pending;
    callbackAssert(hooks.count(0)===0&&hooks.count(1)===1&&hooks.count(2)===1,"terminal closes locals and uncaptured args while listener retains options");
    host.listener=undefined;
    callbackAssert(hooks.count(0)===1,"dropping escaped listener retires immutable options capture immediately");
    callback.cancel();await callback.wait();callback.close();
}
async function observeCallbackRequestCaptures(api,control,hooks){
    const host=callbackHost(control),gate=callbackDeferred(),callback=await callbackStarted(api,host,callbackOptions({complete(){return gate.promise}}));
    const NativeURL=URL,before=Object.getOwnPropertyDescriptor(globalThis,"URL");let pageEnded=false;
    function SelectedURL(input,base){const value=new NativeURL(input,base);Object.defineProperty(value,"actualHolder",{value:hooks.make(2)});return value}
    Object.defineProperty(globalThis,"URL",{configurable:true,writable:true,value:SelectedURL});
    try{
        host.listener(Object.assign(hooks.make(0),{url:"/oauth/callback?code=x",method:"GET"}),
            Object.assign(hooks.make(1),{writeHead(){return this},end(){callbackAssert([0,1,2].every(slot=>hooks.count(slot)===0),"request captures and local URL live through final page");pageEnded=true;return this}}));
        callbackAssert([0,1,2].every(slot=>hooks.count(slot)===0),"actual completion Await retains request captures and URL local");
        gate.resolve("accepted");callbackAssert(await callback.wait()==="accepted"&&pageEnded,"actual completion and send");
        callbackAssert([0,1,2].every(slot=>hooks.count(slot)===1),"request terminal retires its sole capture and local owners");
    }finally{Object.defineProperty(globalThis,"URL",before);callback.close()}
}
async function observeCallbackPrivateData(api,control,hooks,mode){
    let reason;
    function fail(){reason=hooks.freshPrivateData();callbackAssert(hooks.isUnmarkedPrivateData(reason),"actual fresh private DATA");throw reason}
    let observed;
    if(mode==="start"){const options=callbackOptions();Object.defineProperty(options,"providerName",{get:fail});observed=await callbackThrown(()=>api.startOAuthCallbackServer(options))}
    else if(mode==="manual"){observed=await callbackThrown(()=>api.waitForCallbackOrManualInput({get prompt(){return fail()}},undefined,{}))}
    else{
        const host=callbackHost(control),callback=await callbackStarted(api,host,callbackOptions({complete:fail}));
        const pending=callback.wait().catch(value=>value);host.request("/oauth/callback?code=x");observed=await pending;callback.close();
    }
    callbackAssert(observed===reason&&hooks.isUnmarkedPrivateData(reason),"same operation DATA stays ordinary with exact identity");
}
async function observeCallbackCurrentFatal(api,control,hooks,mode){
    const prior=hooks.freshPrivateData();callbackAssert(hooks.isUnmarkedPrivateData(prior),"successful prior private DATA");
    function fail(){hooks.raiseNativeFatal();hooks.record.guestReached=true;throw prior}
    try{
        if(mode==="start"){const options=callbackOptions();Object.defineProperty(options,"providerName",{get:fail});await api.startOAuthCallbackServer(options)}
        else await api.waitForCallbackOrManualInput({get prompt(){return fail()}},undefined,{});
    }catch(reason){hooks.visit(3);throw reason}
    hooks.record.guestReached=true;
}
async function observeCallbackPredicateFatal(api,control,hooks){
    const host=callbackHost(control),options=callbackOptions();let reads=0;
    Object.defineProperty(options,"state",{get(){if(reads++===0){const holder=hooks.make(0);hooks.armFatal(0);return holder}hooks.record.guestReached=true;return"expected"}});
    const callback=await callbackStarted(api,host,options);void callback;
    try{host.request("/oauth/callback?state=expected&code=x")}catch(reason){hooks.record.guestReached=true;hooks.visit(3);throw reason}
    hooks.record.guestReached=true;
}
