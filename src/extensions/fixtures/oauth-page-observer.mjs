// Literal observers for the actual c268 OAuth HTML helpers. Inputs and live
// prototype mutations are explicit; the Source fixture remains unchanged.
function pageAssert(value,label){if(!value)throw Error(label)}
function pageEqual(actual,expected,label){pageAssert(JSON.stringify(actual)===JSON.stringify(expected),label)}
function observePageBasic(api,source){
    pageAssert(api.oauthSuccessHtml.name==="oauthSuccessHtml"&&api.oauthSuccessHtml.length===1,"success declaration");
    pageAssert(api.oauthErrorHtml.name==="oauthErrorHtml"&&api.oauthErrorHtml.length===2,"error declaration");
    pageAssert(Object.hasOwn(api.oauthSuccessHtml,"prototype")&&Object.hasOwn(api.oauthErrorHtml,"prototype"),"ordinary function shapes");
    const message="<&>\"'\nwide: \u{1F642}",details="detail<&>";
    pageAssert(api.oauthSuccessHtml(message)===source.oauthSuccessHtml(message),"exact complete success HTML");
    pageAssert(api.oauthErrorHtml(message,details)===source.oauthErrorHtml(message,details),"exact complete error HTML");
    const result=api.oauthErrorHtml(message,details);
    pageAssert(result.includes("&lt;&amp;&gt;&quot;&#39;\nwide: \u{1F642}")&&result.includes('<div class="details">detail&lt;&amp;&gt;</div>'),"actual escaping and details");
    for(const absent of [undefined,null,false,0,""])pageAssert(!api.oauthErrorHtml("message",absent).includes('<div class="details">'),"false details omitted");
}
function pageChain(label,trace,last){
    function step(index){
        const receiver={};
        Object.defineProperty(receiver,"replaceAll",{get(){
            trace.push(label+":get:"+index);
            return function(needle,replacement){
                pageAssert(this===receiver,"actual replaceAll receiver");
                trace.push([label,index,needle,replacement]);
                return index===4?last():step(index+1);
            };
        }});
        return receiver;
    }
    return step(0);
}
function observePageChain(api){
    const trace=[],input=pageChain("message",trace,()=>"<already prepared>");
    input.toString=()=>{throw Error("eager input String conversion")};
    const result=api.oauthSuccessHtml(input);
    const expected=[];const pairs=[["&","&amp;"],["<","&lt;"],[">","&gt;"],['"',"&quot;"],["'","&#39;"]];
    for(let i=0;i<5;i++){expected.push("message:get:"+i);expected.push(["message",i,...pairs[i]])}
    pageEqual(trace,expected,"five live chained calls");
    pageAssert(result.includes("<p><already prepared></p>"),"escape result is used directly");
}
function observePageInputFailures(api){
    for(const input of [undefined,null,2,false,Symbol("input"),{}]){
        let reason;try{api.oauthSuccessHtml(input)}catch(error){reason=error}
        pageAssert(reason instanceof TypeError,"missing live replaceAll fails synchronously");
    }
    const token={};let calls=0;
    const input={get replaceAll(){calls++;throw token}};
    let reason;try{api.oauthErrorHtml(input,"details")}catch(error){reason=error}
    pageAssert(reason===token&&calls===1,"first getter abrupt skips following operations");
}
function observePagePredicate(api,hooks){
    const before=Object.getOwnPropertyDescriptor(Object.prototype,"details");
    let reads=0;
    Object.defineProperty(Object.prototype,"details",{configurable:true,get(){
        reads++;if(reads===1)return {carrier:hooks.make(0)};
        pageAssert(hooks.count(0)===1,"details predicate root retires before second getter");
        return "inherited detail";
    }});
    try{
        const result=api.oauthSuccessHtml("message");
        pageAssert(reads===2&&result.includes('<div class="details">inherited detail</div>'),"live inherited details is read twice");
    }finally{if(before)Object.defineProperty(Object.prototype,"details",before);else delete Object.prototype.details}
}
function observePageCallRetirement(api,hooks){
    let third=0;
    const input={replaceAll(){
        const receiver={carrier:hooks.make(0)};
        const method=function(){
            return {get replaceAll(){
                third++;pageEqual([hooks.count(0),hooks.count(1)],[1,1],"previous receiver and callee retire before next getter");
                return function(){return {replaceAll(){return {replaceAll(){return "done"}}}}};
            }};
        };
        method.carrier=hooks.make(1);receiver.replaceAll=method;return receiver;
    }};
    pageAssert(api.oauthSuccessHtml(input).includes("<p>done</p>")&&third===1,"actual full chain completed");
}
function observePageLocalsAndTemplates(api,hooks){
    const trace=[],before=Object.getOwnPropertyDescriptor(String.prototype,"concat");
    const globalString=Object.getOwnPropertyDescriptor(globalThis,"String");
    function finalValue(label,slot){return {carrier:hooks.make(slot),[Symbol.toPrimitive](hint){
        pageEqual([hooks.count(0),hooks.count(1)],[0,0],"declared escaped locals live during final template");
        trace.push(label+":"+hint);return label;
    }}}
    const message=pageChain("m",[],()=>finalValue("message",0));
    const details=pageChain("d",[],()=>finalValue("details",1));
    Object.defineProperty(String.prototype,"concat",{configurable:true,get(){throw Error("untagged template used live concat")}});
    Object.defineProperty(globalThis,"String",{configurable:true,get(){throw Error("intrinsic template used global String")}});
    try{
        const result=api.oauthErrorHtml(message,details);
        pageEqual(trace,["message:string","details:string"],"eager intrinsic template order");
        pageAssert(result.includes("<p>message</p>")&&result.includes('<div class="details">details</div>'),"actual nested template output");
        pageEqual([hooks.count(0),hooks.count(1)],[1,1],"declared render locals retire after return");
    }finally{
        Object.defineProperty(globalThis,"String",globalString);
        Object.defineProperty(String.prototype,"concat",before);
    }
}
function observePagePrivateData(api,hooks){
    let original,reason;
    const input={get replaceAll(){original=hooks.freshPrivateData();throw original}};
    try{api.oauthSuccessHtml(input)}catch(error){reason=error}
    pageAssert(reason===original&&hooks.isUnmarkedPrivateData(reason),"same getter private DATA remains ordinary");
}
function observePageCurrentFatal(api,hooks){
    hooks.freshPrivateData();
    const input={get replaceAll(){hooks.raiseNativeFatal();throw Error("native B returned")}};
    try{api.oauthSuccessHtml(input)}catch(error){hooks.visit(3);throw error}
}
function observePageRetirementFatal(api,hooks){
    hooks.armFatal(0);
    const input={replaceAll(){return {carrier:hooks.make(0),replaceAll(){return {get replaceAll(){
        hooks.record.guestReached=true;throw Error("next getter after retirement fatal");
    }}}}}};
    try{api.oauthSuccessHtml(input)}catch(error){hooks.visit(2);throw error}
}

function observePageTemplateThrow(api,hooks){
    const token={},trace=[];
    const message=pageChain("m",[],()=>({carrier:hooks.make(0),[Symbol.toPrimitive](hint){trace.push("message:"+hint);throw token}}));
    const details=pageChain("d",[],()=>({carrier:hooks.make(1),[Symbol.toPrimitive](hint){trace.push("details:"+hint);return "unused"}}));
    let reason;try{api.oauthErrorHtml(message,details)}catch(error){reason=error}
    pageAssert(reason===token,"template conversion preserves original abrupt value");
    pageEqual(trace,["message:string"],"later detail interpolation is skipped");
    pageEqual([hooks.count(0),hooks.count(1)],[1,1],"all declared render locals retire through the abrupt completion");
}
