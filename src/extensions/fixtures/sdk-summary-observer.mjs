// Observers over genuine c268 owners. Controlled AI imports are explicit test
// inputs; conversion, normalization, serialization, usage and AF bodies are real.
function summaryAssert(value, label) { if (!value) throw Error(label); }
function summarySame(actual, expected, label) { summaryAssert(JSON.stringify(actual) === JSON.stringify(expected), label + ": " + JSON.stringify(actual)); }
async function summaryThrown(callback) { try { await callback(); } catch (reason) { return reason; } throw Error("expected summary rejection"); }
function summaryUsage(n = 1) { return {input:n,output:n,cacheRead:n,cacheWrite:n,totalTokens:4*n,cost:{input:n,output:n,cacheRead:n,cacheWrite:n,total:4*n}}; }
function summaryReply(text = "summary", usage = summaryUsage()) { return {stopReason:"stop",content:[{type:"text",text}],usage}; }
function summaryReset(state) {
    state.uuidv7 = () => "actual-route";
    state.completeSimple = () => summaryReply();
    state.retryAssistantCall = produce => produce();
}
function summaryArgs(messages = [], model = {}) { return [messages,model,undefined,"key",undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,"session"]; }
function summaryPrepare(api, split, messages = [], prefix = [], previous) {
    const value = {firstKeptEntryId:"kept",messagesToSummarize:messages,turnPrefixMessages:prefix,isSplitTurn:split,tokensBefore:40,previousSummary:previous,fileOps:api.createFileOps()};
    Object.defineProperty(value,"settings",{get(){throw Error("obsolete settings read")}});
    return value;
}
function summaryArrow(fn, name, length) {
    summaryAssert(fn.name === name && fn.length === length && !Object.hasOwn(fn,"prototype"), "actual arrow shape");
}
async function observeSummaryShapes(api, state) {
    summaryReset(state);
    const af = Object.getPrototypeOf(async function(){});
    for (const [name,length] of [["completeSummarization",6],["generateSummary",14],["generateSummaryWithUsage",14],["compact",12]]) {
        const fn = api[name];
        summaryAssert(fn.name === name && fn.length === length && Object.getPrototypeOf(fn) === af && !Object.hasOwn(fn,"prototype"), "actual async declaration shape " + name);
    }
    for (const [name,length] of [["convertToLlm",1],["normalizeContext",1],["createInitialSystemMessage",2],["combineUsage",2]]) {
        const fn = api[name];
        summaryAssert(fn.name === name && fn.length === length && Object.getPrototypeOf(fn) === Function.prototype && Object.hasOwn(fn,"prototype"), "actual ordinary declaration shape " + name);
    }
    state.retryAssistantCall = produce => { summaryArrow(produce,"produce",0); summaryAssert(Object.getPrototypeOf(produce) === af,"actual async arrow"); return 4; };
    summaryAssert(await api.completeSummarization({}, {}, {}) === 4, "ordinary retry result adoption");
}
async function observeSummaryCopy(api, state) {
    summaryReset(state);
    const trace = [], symbol = Symbol("option"), model = {}, context = {}, retry = {}, callbacks = {}, signal = {};
    let routingReads = 0;
    const options = new Proxy(Object.defineProperties({other:7,[symbol]:8}, {
        cacheRetention:{enumerable:true,get(){trace.push("cache");return "old"}},
        sessionId:{enumerable:true,get(){trace.push("route");return ++routingReads === 1 ? "copied" : null}},
        signal:{enumerable:true,get(){trace.push("signal");return signal}},
    }), {
        ownKeys(target){trace.push("keys");return Reflect.ownKeys(target)},
        getOwnPropertyDescriptor(target,key){trace.push("desc:"+String(key));return Reflect.getOwnPropertyDescriptor(target,key)},
        get(target,key,receiver){trace.push("get:"+String(key));return Reflect.get(target,key,receiver)},
    });
    let selected;
    state.uuidv7 = () => {trace.push("uuid");return "minted"};
    state.retryAssistantCall = (produce, policy, selectedSignal, observedCallbacks) => {
        trace.push("retry");
        summaryAssert(policy === retry && selectedSignal === signal && observedCallbacks === callbacks, "actual retry argument identity");
        return produce();
    };
    state.completeSimple = (m,c,o) => {
        summaryAssert(m === model && c === context,"actual model/context bindings");
        selected = o;
        return 11;
    };
    summaryAssert(await api.completeSummarization(model,context,options,undefined,retry,callbacks) === 11, "actual simple result");
    summaryAssert(selected !== options && selected.other === 7 && selected[symbol] === 8 && selected.sessionId === "minted" && selected.cacheRetention === "none" && selected.signal === signal,"actual object spread and overwrite");
    summarySame(trace,["keys","desc:other","get:other","desc:cacheRetention","get:cacheRetention","cache","desc:sessionId","get:sessionId","route","desc:signal","get:signal","signal","desc:Symbol(option)","get:Symbol(option)","get:sessionId","route","uuid","retry"],"source spread/routing order");
    state.uuidv7 = () => {throw Error("supplied route must not mint")};
    state.retryAssistantCall = produce => produce();
    for (const sessionId of ["",false,0]) {
        state.completeSimple = (m,c,o) => {summaryAssert(o.sessionId === sessionId,"non-nullish route identity");return 1};
        await api.completeSummarization({}, {}, {sessionId});
    }
}
async function observeSummaryZeroAwait(api, state) {
    summaryReset(state);
    const trace = [];
    const returned = {get then(){trace.push("adopt");return undefined}};
    state.retryAssistantCall = () => {trace.push("retry");return returned};
    const old = globalThis.Promise;
    globalThis.Promise = function(){throw Error("public Promise used for intrinsic async capability")};
    try {
        const pending = api.completeSummarization({}, {}, {});
        trace.push("returned");
        summarySame(trace,["retry","adopt","returned"],"zero-Await body and synchronous adoption getter");
        summaryAssert(await pending === returned,"actual adopted DATA result");
    } finally { globalThis.Promise = old; }
}
async function observeSummaryStreamAwait(api, state) {
    summaryReset(state);
    const trace = [], result = {};
    state.completeSimple = () => {throw Error("stream branch used simple")};
    state.retryAssistantCall = produce => {summaryArrow(produce,"produce",0);const p=produce();trace.push("produce:return");return p};
    const pending = api.completeSummarization({}, {}, {}, function(){trace.push("stream");return {get result(){trace.push("get:result");return function(){trace.push("result");return result}}}});
    trace.push("outer:return");
    summarySame(trace,["stream","produce:return","outer:return"],"actual Await defers result lookup");
    summaryAssert(await pending === result,"actual result method return");
    summarySame(trace,["stream","produce:return","outer:return","get:result","result"],"single producer continuation");
}
async function observeSummaryProducerCapture(api, state, hooks) {
    summaryReset(state);
    state.retryAssistantCall = produce => {globalThis.summarySavedProducer=produce;return 9};
    state.completeSimple = (model,context,options) => {
        summaryAssert(hooks.count(0) === 0 && hooks.count(1) === 0 && hooks.count(2) === 1,"only genuine captured inputs survive");
        summaryAssert(model.carrier && context.carrier && !Object.hasOwn(options,"hidden"),"actual captured input graph");
        return 10;
    };
    summaryAssert(await api.completeSummarization({carrier:hooks.make(0)},{carrier:hooks.make(1)},Object.defineProperty({},"hidden",{value:hooks.make(2)})) === 9,"outer completed before retained producer");
    summarySame([hooks.count(0),hooks.count(1),hooks.count(2)],[0,0,1],"uncaptured caller options retired");
    summaryAssert(await summarySavedProducer() === 10,"escaped actual async producer");
    delete globalThis.summarySavedProducer;
    summarySame([hooks.count(0),hooks.count(1)],[1,1],"actual captured inputs released");
}
async function observeSummaryStreamTemporaries(api, state, hooks) {
    summaryReset(state);
    let adopted = 0;
    const returned = {get then(){summaryAssert(hooks.count(1) === 1,"selected result callee retires before adoption");adopted++;return undefined}};
    const result = await api.completeSummarization({}, {}, {}, function(){
        return {carrier:hooks.make(0),get result(){
            const method = function(){return returned};
            method.carrier=hooks.make(1);
            return method;
        }};
    });
    summaryAssert(result === returned && adopted >= 1,"actual stream result adoption");
    summarySame([hooks.count(0),hooks.count(1)],[1,1],"actual input and result callee released once");
}
async function observeSummaryPrivateData(api, state, hooks, route) {
    summaryReset(state);
    const reason = hooks.freshPrivateData();
    summaryAssert(hooks.isUnmarkedPrivateData(reason),"real ordinary native DATA");
    if (route === "retry") state.retryAssistantCall = () => {throw reason};
    const stream = route === "stream" ? function(){return {get result(){throw reason}}} : undefined;
    summaryAssert(await summaryThrown(() => api.completeSummarization({}, {}, {}, stream)) === reason,"private DATA identity through actual AF path");
}
async function observeSummaryBasic(api, state) {
    summaryReset(state);
    const headers={},env={},signal={},retry={},callbacks={},model={reasoning:true,get maxTokens(){throw Error("obsolete model maxTokens read")}};
    const reserve={valueOf(){throw Error("obsolete reserveTokens coercion")}};
    const usage=summaryUsage(3), calls=[];
    state.uuidv7=()=>{throw Error("supplied summary session route ignored")};
    state.retryAssistantCall=(produce,r,s,c)=>{summaryAssert(r===retry&&s===signal&&c===callbacks,"summary retry forwarding");return produce()};
    state.completeSimple=(m,context,options)=>{
        summaryAssert(m===model&&options.apiKey==="key"&&options.headers===headers&&options.env===env&&options.signal===signal&&options.reasoning==="high"&&options.sessionId==="r"&&options.cacheRetention==="none","c268 options forwarding");
        summaryAssert(!Object.hasOwn(options,"maxTokens"),"removed output limit is absent");
        summaryAssert(context.messages.length===2&&context.messages[0].role==="system"&&context.messages[1].role==="user","actual transcript normalization");
        const prompt=context.messages[1].content[0].text;
        summaryAssert(prompt.startsWith("<conversation>\n[User]: hello\n</conversation>")&&prompt.includes("## Goal"),"actual converter and serializer prompt");
        calls.push(context);return summaryReply("done",usage);
    };
    const args=[[{role:"user",content:"hello",timestamp:1}],model,reserve,"key",headers,signal,undefined,undefined,"high",undefined,env,retry,callbacks,"r"];
    const result=await api.generateSummaryWithUsage(...args);
    summaryAssert(result.text==="done"&&result.usage===usage,"summary result identity");
    summaryAssert(await api.generateSummary(...args)==="done"&&calls.length===2,"actual text-only outer Await");
}
async function observeSummaryTemplates(api, state) {
    summaryReset(state);
    const trace=[], old=Object.getOwnPropertyDescriptor(String.prototype,"concat");
    const instructions={[Symbol.toPrimitive](hint){trace.push("instructions:"+hint);return "focus"}};
    const previous={[Symbol.toPrimitive](hint){trace.push("previous:"+hint);return "prior"}};
    const rows=[];
    Object.defineProperty(rows,"map",{get(){trace.push("map");return Array.prototype.map}});
    state.completeSimple=(m,context)=>{
        trace.push("request");
        const prompt=context.messages[1].content[0].text;
        summaryAssert(prompt.includes("<previous-summary>\nprior\n</previous-summary>")&&prompt.endsWith("Additional focus: focus"),"intrinsic template text");
        return summaryReply();
    };
    Object.defineProperty(String.prototype,"concat",{configurable:true,get(){throw Error("untagged template used live concat")}});
    try {
        const args=summaryArgs(rows);args[6]=instructions;args[7]=previous;
        await api.generateSummaryWithUsage(...args);
        summarySame(trace,["instructions:string","map","previous:string","request"],"eager substitutions precede later expressions");
        let mapped=0;const unopened=[];Object.defineProperty(unopened,"map",{get(){mapped++;return Array.prototype.map}});
        const rejected=summaryArgs(unopened);rejected[6]=Symbol("instruction");
        summaryAssert(await summaryThrown(()=>api.generateSummaryWithUsage(...rejected)) instanceof TypeError&&mapped===0,"Symbol ToString fails before conversion");
    } finally {Object.defineProperty(String.prototype,"concat",old)}
}
async function observeSummaryResponse(api, state, hooks) {
    summaryReset(state);const trace=[];let contents=0;
    const value={
        get stopReason(){trace.push("stop");return "stop"},
        get content(){
            trace.push("content:"+ ++contents);
            if(contents===1)return {get some(){trace.push("some");const fn=function(predicate){trace.push("some:call");summaryArrow(predicate,"",1);return predicate({get type(){trace.push("some:type");return "text"}})};fn.carrier=hooks.make(0);return fn}};
            summaryAssert(hooks.count(0)===1,"some callee retires before second content getter");
            return {filter(predicate){trace.push("filter");summaryArrow(predicate,"",1);summaryAssert(predicate({type:"text"}),"real filter callback");return {map(mapper){trace.push("map");summaryArrow(mapper,"",1);summaryAssert(mapper({text:"body"})==="body","real text callback");return {join(separator){trace.push("join");summaryAssert(separator==="\n","default separator");return "rendered"}}}}}};
        },
        get usage(){trace.push("usage");return 17},
    };
    state.completeSimple=()=>value;
    const result=await api.generateSummaryWithUsage(...summaryArgs());
    summarySame(result,{text:"rendered",usage:17},"actual response result");
    summarySame(trace,["stop","stop","content:1","some","some:call","some:type","content:2","filter","map","join","usage"],"live response expression order");
}
async function observeSummaryErrors(api, state) {
    summaryReset(state);
    for(const [reply,message]of [
        [{stopReason:"error",errorMessage:"broken"},"Summarization failed: broken"],
        [{stopReason:"error",errorMessage:""},"Summarization failed: Unknown error"],
        [{stopReason:"length"},"Summarization failed: generation hit the token cap and the summary is incomplete"],
        [{stopReason:"stop",content:[{type:"toolCall"}]},"Summarization attempted to call a tool"],
    ]){
        state.completeSimple=()=>reply;
        const reason=await summaryThrown(()=>api.generateSummaryWithUsage(...summaryArgs()));
        summaryAssert(reason instanceof Error&&reason.message===message,"actual summary failure message");
    }
    state.completeSimple=()=>({stopReason:"aborted",content:[],usage:3});
    const result=await api.generateSummaryWithUsage(...summaryArgs());
    summarySame(result,{text:"",usage:3},"actual getSummarizationFailure only rejects error and length");
}
async function observeSummaryDate(api, state, hooks) {
    summaryReset(state);
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Date");
    let visits=0;
    Object.defineProperty(globalThis,"Date",{configurable:true,get(){
        visits++;return {carrier:hooks.make(0),get now(){const method=function(){return 71};method.carrier=hooks.make(1);return method}};
    }});
    state.completeSimple=(m,context)=>{
        summarySame([hooks.count(0),hooks.count(1)],[1,1],"Date expression temporaries retire before request");
        summaryAssert(context.messages[1].timestamp===71,"actual Date result");
        return summaryReply();
    };
    try {await api.generateSummaryWithUsage(...summaryArgs());summaryAssert(visits===1,"one live Date lookup")}
    finally {Object.defineProperty(globalThis,"Date",descriptor)}
}
async function observeSummaryLocal(api, state, hooks) {
    summaryReset(state);
    let resolveGate;
    const gate=new Promise(resolve=>{resolveGate=resolve});
    state.completeSimple=()=>gate;
    const args=summaryArgs();args[2]={carrier:hooks.make(0)};args[11]={carrier:hooks.make(1)};
    state.retryAssistantCall=produce=>produce();
    const pending=api.generateSummaryWithUsage(...args);
    args[2]=args[11]=undefined;
    summarySame([hooks.count(0),hooks.count(1)],[0,0],"unused actual arguments stay alive across Await");
    resolveGate(summaryReply("done"));
    const result=await pending;
    summaryAssert(result.text==="done","real suspended generation completed");
    summarySame([hooks.count(0),hooks.count(1)],[1,1],"arguments retire after terminal completion");
}
async function observeSummaryCompactRoutes(api, state) {
    summaryReset(state);
    const expectedSeparator="\n\n---\n\n**Turn Context (split turn):**\n\n";
    for(const mode of ["whole","prefix","split"]){
        const replies=mode==="split"?[summaryReply("history",summaryUsage(2)),summaryReply("turn",summaryUsage(3))]:[summaryReply(mode==="whole"?"whole":"turn",summaryUsage(3))];
        let calls=0;
        state.completeSimple=()=>replies[calls++];
        const preparation=summaryPrepare(api,mode!=="whole",mode==="split"?[{role:"user",content:"old"}]:[],mode!=="whole"?[{role:"user",content:"turn"}]:[],null);
        const result=await api.compact(preparation,{},"key");
        summaryAssert(calls===(mode==="split"?2:1),"actual number of summary requests");
        summaryAssert(result.summary===(mode==="whole"?"whole":(mode==="prefix"?"No prior history.":"history")+expectedSeparator+"turn"),"actual split summary merge");
        summaryAssert(result.usage.input===(mode==="split"?5:3)&&result.firstKeptEntryId==="kept"&&result.tokensBefore===40,"actual compaction record and usage");
        summarySame(result.details,{readFiles:[],modifiedFiles:[]},"actual file operation lists");
    }
    state.completeSimple=()=>summaryReply("rendered");
    const missing=summaryPrepare(api,false);missing.firstKeptEntryId="";
    summaryAssert((await summaryThrown(()=>api.compact(missing,{},"key"))).message==="First kept entry has no UUID - session may need migration","actual missing UUID validation");
}
async function observeSummaryCompactBindings(api, state) {
    summaryReset(state);
    const names=["firstKeptEntryId","messagesToSummarize","turnPrefixMessages","isSplitTurn","tokensBefore","previousSummary","fileOps"];
    const values=["number",[],[],false,8,undefined,api.createFileOps()];
    const descriptors=names.map(name=>Object.getOwnPropertyDescriptor(Number.prototype,name));
    const receivers=[],trace=[];
    names.forEach((name,index)=>Object.defineProperty(Number.prototype,name,{configurable:true,get(){receivers.push(this);trace.push(name);return values[index]}}));
    try {
        const result=await api.compact(4,{});
        summaryAssert(result.firstKeptEntryId==="number","primitive preparation handled by binding pattern");
        summarySame(trace,names,"seven ordered binding getters");
        summaryAssert(receivers.every(receiver=>receiver===receivers[0])&&typeof receivers[0]==="object","single boxed preparation receiver");
    } finally {names.forEach((name,index)=>{if(descriptors[index])Object.defineProperty(Number.prototype,name,descriptors[index]);else delete Number.prototype[name]})}
}
function summaryRawText(raw) {return {some(){return false},filter(){return {map(){return {join(){return raw}}}}}}}
async function observeSummaryCompactTemplates(api, state) {
    summaryReset(state);
    const trace=[];let calls=0;
    const history={[Symbol.toPrimitive](hint){trace.push("history:"+hint);return "H"}};
    const turn={[Symbol.toPrimitive](hint){trace.push("turn:"+hint);return "T"}};
    state.completeSimple=()=>({stopReason:"stop",content:summaryRawText(calls++===0?history:turn),usage:summaryUsage()});
    const preparation=summaryPrepare(api,true,[{role:"user",content:"h"}],[{role:"user",content:"t"}]);
    const result=await api.compact(preparation,{});
    summarySame(trace,["history:string","turn:string"],"eager split template conversion order");
    summaryAssert(result.summary==="H\n\n---\n\n**Turn Context (split turn):**\n\nT","actual intrinsic merged text");
}
async function observeSummaryMessages(api, state) {
    summaryReset(state);
    const trace=[],identity={role:"assistant",content:[]},customContent=[];
    const branch={role:"branchSummary",summary:{[Symbol.toPrimitive](hint){trace.push("branch:"+hint);return "B"}},timestamp:2};
    const bash={role:"bashExecution",command:{[Symbol.toPrimitive](hint){trace.push("command:"+hint);return "ls"}},output:"",exitCode:0,timestamp:1};
    let customReads=0;
    const custom={role:"custom",get content(){customReads++;return customReads===1?"first":customContent},timestamp:3};
    const result=api.convertToLlm([identity,bash,branch,custom,{role:"bashExecution",excludeFromContext:true,get command(){throw Error("excluded command")}}, {role:"unknown"}]);
    summaryAssert(result.length===4&&result[0]===identity,"identity and undefined-only filtering");
    summaryAssert(result[1].content[0].text==="Ran \x60ls\x60\n(no output)","actual Bash text");
    summaryAssert(result[2].content[0].text.includes("B</summary>"),"actual branch wrapper");
    summaryAssert(result[3].content[0].text===customContent&&customReads===2,"custom content tested and reread");
    summarySame(trace,["command:string","branch:default"],"template ToString versus original generic addition");
}
async function observeSummaryMessageCalls(api, state, hooks) {
    summaryReset(state);
    const rows={get map(){
        const method=function(callback){
            summaryAssert(this===rows,"actual map receiver");summaryArrow(callback,"",1);
            return {carrier:hooks.make(0),get filter(){
                const selected=function(predicate){summaryAssert(predicate(null)&&predicate(false)&&!predicate(undefined),"actual undefined-only arrow");summaryArrow(predicate,"",1);return "chosen"};
                selected.carrier=hooks.make(1);return selected;
            }};
        };return method;
    }};
    summaryAssert(api.convertToLlm(rows)==="chosen","actual live map/filter result");
    summarySame([hooks.count(0),hooks.count(1)],[1,1],"map result and filter callee retired");
}
async function observeSummaryNormalize(api) {
    const rows=[{role:"user",content:"x"}];
    summaryAssert(api.normalizeContext({messages:rows}).messages===rows,"empty normalization preserves original messages");
    const tools=[];const initial=api.createInitialSystemMessage("prompt",tools);
    summaryAssert(initial.role==="system"&&initial.content==="prompt"&&!Object.hasOwn(initial,"toolsAdded"),"conditional tool spread absent");
    summaryAssert(api.createInitialSystemMessage(undefined,undefined)===undefined,"empty initial system message");
    summaryAssert(await summaryThrown(()=>api.createInitialSystemMessage(null,undefined)) instanceof TypeError,"undefined-only prompt guard");
    const trace=[],iterable={get [Symbol.iterator](){trace.push("iterator");return function(){trace.push("open");let sent=false;return {next(){trace.push("next");return sent?{done:true}:(sent=true,{done:false,value:rows[0]})}}}}};
    const normalized=api.normalizeContext({get systemPrompt(){trace.push("prompt");return "p"},get tools(){trace.push("tools");return undefined},get messages(){trace.push("messages");return iterable}});
    summaryAssert(normalized.messages.length===2&&normalized.messages[1]===rows[0],"actual spread values");
    summarySame(trace,["prompt","tools","messages","iterator","iterator","open","next","next"],"actual linked array append probe and iteration");
}
async function observeSummaryUsage(api, state, hooks) {
    summaryReset(state);
    const first=summaryUsage(1),second=summaryUsage(2),trace=[];
    let reads=0;
    Object.defineProperty(first,"cacheWrite1h",{get(){trace.push("first:optional");return ++reads===1?0:null}});
    Object.defineProperty(second,"cacheWrite1h",{get(){trace.push("second:optional");return 4}});
    Object.defineProperty(first,"reasoning",{get(){trace.push("first:reasoning");return undefined}});
    Object.defineProperty(second,"reasoning",{get(){trace.push("second:reasoning");return undefined}});
    Object.defineProperty(first,"cost",{get(){
        const ordinal=trace.filter(value=>value==="first:cost").length;trace.push("first:cost");
        const carrier=ordinal===0?hooks.make(0):undefined;
        return {carrier,input:{valueOf(){summaryAssert(hooks.count(0)===1,"cost receiver retires before operand coercion");return 1}},output:1,cacheRead:1,cacheWrite:1,total:4};
    }});
    Object.defineProperty(second,"cost",{get(){trace.push("second:cost");return {input:2,output:2,cacheRead:2,cacheWrite:2,total:8}}});
    const result=api.combineUsage(first,second);
    summaryAssert(result.cacheWrite1h===4&&!Object.hasOwn(result,"reasoning")&&result.input===3&&result.cost.input===3,"actual optional usage merge");
    summarySame(trace.slice(0,5),["first:optional","first:optional","second:optional","first:reasoning","second:reasoning"],"conditional optional rereads");
    summarySame(trace.slice(5),Array.from({length:5},()=>["first:cost","second:cost"]).flat(),"actual repeated nested cost fields");
}
async function observeSummaryResponseData(api, state, hooks, route) {
    summaryReset(state);
    const reason=hooks.freshPrivateData();
    if(route==="response") {
        state.completeSimple=()=>({get stopReason(){throw reason}});
        summaryAssert(await summaryThrown(()=>api.generateSummaryWithUsage(...summaryArgs()))===reason,"ordinary response DATA through Await");
    } else {
        const old=globalThis.Error;
        globalThis.Error=function(){return reason};
        state.completeSimple=()=>({stopReason:"error",errorMessage:"failed"});
        try {summaryAssert(await summaryThrown(()=>api.generateSummaryWithUsage(...summaryArgs()))===reason,"ordinary Error constructor DATA thrown by Source")}
        finally {globalThis.Error=old}
    }
}
async function observeSummaryCurrentFatal(api, state, hooks) {
    summaryReset(state);
    hooks.freshPrivateData();
    state.retryAssistantCall=()=>{hooks.visit(2);return 1};
    const options={get value(){return hooks.raiseNativeFatal()},get sessionId(){hooks.visit(1);return "bad"}};
    try {await api.completeSummarization({}, {}, options)} catch(reason){hooks.visit(3);throw reason}
}
async function observeSummaryPredicateRetirement(api, state, hooks, cancel) {
    summaryReset(state);
    const model={get reasoning(){if(cancel)hooks.armCancel(0);else hooks.armFatal(0);return hooks.make(0)}};
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Date");
    Object.defineProperty(globalThis,"Date",{configurable:true,get(){hooks.visit(1);return {now(){return 0}}}});
    state.completeSimple=()=>{hooks.visit(2);return summaryReply()};
    const args=summaryArgs([],model);args[8]="high";
    // A fatal realm is disposed by its genuine Engine owner; no guest cleanup.
    await api.generateSummaryWithUsage(...args);
    Object.defineProperty(globalThis,"Date",descriptor);
}
