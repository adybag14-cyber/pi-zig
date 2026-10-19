// Real c268 branch AF observers. Only module-bound completion/retry/UUID
// inputs are controlled; branch preparation, conversion, text and file owners run.
function branchSummaryAssert(value,label){if(!value)throw Error(label)}
function branchSummarySame(actual,expected,label){branchSummaryAssert(JSON.stringify(actual)===JSON.stringify(expected),label+": "+JSON.stringify(actual))}
async function branchSummaryThrown(callback){try{await callback()}catch(reason){return reason}throw Error("expected branch rejection")}
function branchSummaryReply(text="BRANCH",usage={actual:"usage"}){return {stopReason:"stop",content:[{type:"text",text}],usage}}
function branchSummaryReset(state){state.uuidv7=()=>"branch-route";state.completeSimple=()=>branchSummaryReply();state.retryAssistantCall=produce=>produce()}
function branchSummaryEntries(text="hello"){return [{type:"message",message:{role:"user",content:text,timestamp:1}}]}
function branchSummaryOptions(extra={}){return {model:{contextWindow:128000},reserveTokens:0,...extra}}
function branchSummaryPrompt(context){return context.messages[1].content[0].text}
const branchSummaryPreamble="The user explored a different conversation branch before returning here.\nSummary of that exploration:\n\n";
async function observeBranchSummaryShapes(api,state){
    branchSummaryReset(state);
    branchSummaryAssert(Object.keys(api).join()==="collectEntriesForBranchSummary,prepareBranchEntries,generateBranchSummary","actual export order");
    const fn=api.generateBranchSummary;
    branchSummaryAssert(fn.name==="generateBranchSummary"&&fn.length===2&&Object.getPrototypeOf(fn)===Object.getPrototypeOf(async function(){})&&!Object.hasOwn(fn,"prototype"),"genuine async declaration");
    for(const [name,length]of [["collectEntriesForBranchSummary",3],["prepareBranchEntries",1]]){
        const ordinary=api[name];
        branchSummaryAssert(ordinary.name===name&&ordinary.length===length&&Object.getPrototypeOf(ordinary)===Function.prototype&&Object.hasOwn(ordinary,"prototype"),"actual reused ordinary entry owner");
    }
    const result=await api.generateBranchSummary([],branchSummaryOptions());
    branchSummarySame(result,{summary:"No content to summarize"},"actual empty result");
}
async function observeBranchSummaryEmpty(api,state){
    branchSummaryReset(state);const trace=[],before=Object.getOwnPropertyDescriptor(globalThis,"Promise"),IntrinsicPromise=Promise;
    const options=branchSummaryOptions();
    Object.defineProperty(options,"callbacks",{get(){trace.push("callbacks");return undefined}});
    const entries={[Symbol.iterator](){trace.push("iterator");return {next(){trace.push("next");return {done:true}}}},get length(){trace.push("length");return 0}};
    state.completeSimple=()=>{throw Error("empty branch called complete")};
    Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("async declaration read global Promise")}});
    let pending;
    try{
        pending=api.generateBranchSummary(entries,options);trace.push("returned");
        branchSummaryAssert(pending instanceof IntrinsicPromise,"intrinsic async capability");
        branchSummarySame(trace,["callbacks","iterator","next","length","returned"],"empty body runs before call return");
        branchSummarySame(await pending,{summary:"No content to summarize"},"empty body return adoption");
    }finally{Object.defineProperty(globalThis,"Promise",before)}
}
async function observeBranchSummaryBindings(api,state,hooks){
    branchSummaryReset(state);const names=["model","apiKey","headers","env","signal","customInstructions","replaceInstructions","reserveTokens","streamFn","retry","callbacks"],saved=names.map(name=>Object.getOwnPropertyDescriptor(Number.prototype,name)),trace=[];
    let firstBox=null;
    const model={get contextWindow(){trace.push("contextWindow");branchSummaryAssert(hooks.count(0)===1,"single options box retires before model getter");return 16384}};
    for(const name of names)Object.defineProperty(Number.prototype,name,{configurable:true,get(){
        "use strict";
        trace.push(name);
        if(name==="model"){firstBox=this;Object.defineProperty(this,"carrier",{value:hooks.make(0)});}
        branchSummaryAssert(typeof this==="object"&&this===firstBox,"all bindings share one boxed receiver");
        if(name==="callbacks")firstBox=null;
        return name==="model"?model:undefined;
    }});
    try{
        branchSummarySame(await api.generateBranchSummary([],17),{summary:"No content to summarize"},"primitive options destructuring");
        branchSummarySame(trace,[...names,"contextWindow"],"ordered eleven bindings");
    }finally{for(let i=0;i<names.length;i++){if(saved[i])Object.defineProperty(Number.prototype,names[i],saved[i]);else delete Number.prototype[names[i]]}}
    for(const value of [null,undefined])branchSummaryAssert(await branchSummaryThrown(()=>api.generateBranchSummary([],value)) instanceof TypeError,"nullish BindingPattern rejects");
}
async function observeBranchSummaryBudget(api,state){
    branchSummaryReset(state);const entries=[...branchSummaryEntries("OLDER123"),...branchSummaryEntries("NEW!")];
    for(const [window,reserve,older]of [[16386,undefined,false],[2,0,false],[2,null,false],[0,127998,false],[NaN,127998,false],[1,2,true]]){
        let calls=0;
        state.completeSimple=(model,context)=>{calls++;const prompt=branchSummaryPrompt(context);branchSummaryAssert(prompt.includes("NEW!")&&prompt.includes("OLDER123")===older,"actual default and fallback budget selects newest history");return branchSummaryReply()};
        await api.generateBranchSummary(entries,branchSummaryOptions({model:{contextWindow:window},reserveTokens:reserve}));
        branchSummaryAssert(calls===1,"one actual budgeted request");
    }
    const trace=[];
    const model={get contextWindow(){trace.push("window");return {[Symbol.toPrimitive](hint){trace.push("window:"+hint);return 5}}}};
    const reserve={[Symbol.toPrimitive](hint){trace.push("reserve:"+hint);return 3}};
    const empty={[Symbol.iterator](){trace.push("entries");return {next(){return {done:true}}}},length:0};
    await api.generateBranchSummary(empty,branchSummaryOptions({model,reserveTokens:reserve}));
    branchSummarySame(trace,["window","window:number","reserve:number","entries"],"budget arithmetic before preparation");
}
async function observeBranchSummaryComplete(api,state){
    branchSummaryReset(state);const model={contextWindow:128000},headers={},env={},signal={},retry={},callbacks={},usage={actual:"retained usage"};
    const entries=[
        {type:"branch_summary",summary:"earlier",fromId:"old",timestamp:0,details:{readFiles:["old-read","overlap"],modifiedFiles:["old-mod"]}},
        ...branchSummaryEntries("actual user"),
        {type:"message",message:{role:"assistant",content:[{type:"toolCall",name:"read",arguments:{path:"read"}},{type:"toolCall",name:"write",arguments:{path:"overlap"}},{type:"toolCall",name:"edit",arguments:{path:"edit"}}]}},
    ];
    let calls=0;
    state.retryAssistantCall=(produce,r,s,c)=>{branchSummaryAssert(r===retry&&s===signal&&c===callbacks,"exact retry inputs");return produce()};
    state.completeSimple=(m,context,options)=>{
        calls++;branchSummaryAssert(m===model&&context.messages.length===2&&context.messages[0].role==="system"&&context.messages[1].role==="user","real conversion and transcript");
        const prompt=branchSummaryPrompt(context);
        branchSummaryAssert(prompt.startsWith("<conversation>\n")&&prompt.includes("[User]: actual user")&&prompt.includes("[Assistant tool calls]:")&&prompt.endsWith("Keep each section concise. Preserve exact file paths, function names, and error messages."),"actual serialized prompt");
        branchSummaryAssert(options.apiKey==="key"&&options.headers===headers&&options.env===env&&options.signal===signal&&options.cacheRetention==="none"&&options.sessionId==="branch-route"&&!Object.hasOwn(options,"maxTokens"),"real completeSummarization options");
        return branchSummaryReply("BRANCH",usage);
    };
    const result=await api.generateBranchSummary(entries,branchSummaryOptions({model,apiKey:"key",headers,env,signal,retry,callbacks}));
    branchSummaryAssert(calls===1&&result.usage===usage&&result.summary.startsWith(branchSummaryPreamble+"BRANCH"),"preamble and usage identity");
    branchSummarySame(Object.keys(result),["summary","usage","readFiles","modifiedFiles"],"result order");
    branchSummarySame(result.readFiles,["old-read","read"],"actual read-only deduplication");
    branchSummarySame(result.modifiedFiles,["edit","old-mod","overlap"],"actual modified list");
    branchSummaryAssert(result.summary.endsWith("<modified-files>\nedit\nold-mod\noverlap\n</modified-files>"),"actual file-operation formatting");
}
async function observeBranchSummaryStream(api,state){
    branchSummaryReset(state);const trace=[],model={contextWindow:128000},retry={},callbacks={},signal={},headers={},env={};let release;
    const gate=new Promise(resolve=>{release=resolve});
    const streamFn=(m,context,options)=>{
        trace.push("stream");branchSummaryAssert(m===model&&options.headers===headers&&options.env===env&&options.signal===signal,"actual stream inputs");
        return gate;
    };
    state.completeSimple=()=>{throw Error("stream route used completeSimple")};
    state.retryAssistantCall=(produce,r,s,c)=>{trace.push("retry");branchSummaryAssert(r===retry&&s===signal&&c===callbacks,"actual retry arguments");return produce()};
    const pending=api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions({model,retry,callbacks,signal,headers,env,streamFn}));
    branchSummarySame(trace,["retry","stream"],"actual stream begins in source order");
    release({get result(){trace.push("get-result");return function(){trace.push("result");return branchSummaryReply("STREAM")}}});
    const result=await pending;
    branchSummaryAssert(result.summary===branchSummaryPreamble+"STREAM","actual result value");
    branchSummarySame(trace,["retry","stream","get-result","result"],"result runs after real stream Await");
}
async function observeBranchSummaryTemplates(api,state){
    branchSummaryReset(state);const trace=[],before=Object.getOwnPropertyDescriptor(String.prototype,"concat"),globalString=Object.getOwnPropertyDescriptor(globalThis,"String");
    const custom={[Symbol.toPrimitive](hint){trace.push("custom:"+hint);return "FOCUS"}};
    let reads=0;
    state.completeSimple=(model,context)=>{
        trace.push("request");branchSummaryAssert(branchSummaryPrompt(context).endsWith("Additional focus: FOCUS"),"intrinsic branch prompt");
        return {stopReason:"stop",get content(){
            if(++reads===1)return [];
            return {filter(){return {map(){return {join(){return {[Symbol.toPrimitive](hint){trace.push("summary:"+hint);return "BODY"}}}}}}}};
        },usage:1};
    };
    Object.defineProperty(String.prototype,"concat",{configurable:true,get(){throw Error("untagged branch template called concat")}});
    Object.defineProperty(globalThis,"String",{configurable:true,get(){throw Error("template called global String")}});
    try{
        const result=await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions({customInstructions:custom}));
        branchSummaryAssert(result.summary===branchSummaryPreamble+"BODY","actual generic preamble addition");
        branchSummarySame(trace,["custom:string","request","summary:default"],"template string hint versus generic plus hint");
    }finally{Object.defineProperty(globalThis,"String",globalString);Object.defineProperty(String.prototype,"concat",before)}
}
async function observeBranchSummaryInstructions(api,state){
    branchSummaryReset(state);
    for(const [custom,replace,replaced]of [["ONLY",true,true],["ONLY",false,false],["",true,false],[false,true,false],[null,true,false]]){
        state.completeSimple=(model,context)=>{
            const prompt=branchSummaryPrompt(context);
            branchSummaryAssert(replaced?prompt.endsWith("\n\nONLY")&&!prompt.includes("## Goal"):prompt.includes("## Goal"),"actual instruction branch");
            if(custom&&!replace)branchSummaryAssert(prompt.endsWith("Additional focus: ONLY"),"custom focus appended");
            return branchSummaryReply();
        };
        await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions({customInstructions:custom,replaceInstructions:replace}));
    }
    let calls=0;state.completeSimple=()=>{calls++;return branchSummaryReply()};
    for(const replace of [false,true]){
        const reason=await branchSummaryThrown(()=>api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions({customInstructions:Symbol("focus"),replaceInstructions:replace})));
        branchSummaryAssert(reason instanceof TypeError&&calls===0,"intrinsic Symbol conversion rejects before request");
    }
}
async function observeBranchSummaryStops(api,state){
    branchSummaryReset(state);
    for(const [response,expected]of [
        [{stopReason:"aborted"},{aborted:true}],
        [{stopReason:"error",errorMessage:"broken"},{error:"Branch summarization failed: broken"}],
        [{stopReason:"error",errorMessage:""},{error:"Branch summarization failed: Unknown error"}],
        [{stopReason:"length"},{error:"Branch summarization failed: generation hit the token cap and the summary is incomplete"}],
        [{stopReason:"stop",content:[{type:"toolCall"}]},{error:"Branch summarization attempted to call a tool"}],
    ]){
        Object.defineProperty(response,"usage",{get(){throw Error("early stop read usage")}});
        if(!Object.hasOwn(response,"content"))Object.defineProperty(response,"content",{get(){throw Error("early stop read content")}});
        state.completeSimple=()=>response;
        branchSummarySame(await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions()),expected,"actual early response record");
    }
}
async function observeBranchSummaryResponse(api,state,hooks){
    branchSummaryReset(state);const trace=[];let reads=0;
    state.completeSimple=()=>({
        get stopReason(){trace.push("stop");return "stop"},
        get content(){
            trace.push("content:"+ ++reads);
            if(reads===1)return {get some(){
                trace.push("some");
                const method=function(predicate){trace.push("some:call");branchSummaryAssert(this.marker==="first"&&predicate.length===1&&!Object.hasOwn(predicate,"prototype"),"actual some receiver and arrow");return predicate({get type(){trace.push("type");return "text"}})};
                method.carrier=hooks.make(0);return method;
            },marker:"first"};
            branchSummaryAssert(hooks.count(0)===1,"some callee retires before next content read");
            return {filter(predicate){trace.push("filter");branchSummaryAssert(predicate({type:"text"})&&!predicate({type:"image"}),"real text filter");return {map(mapper){trace.push("map");branchSummaryAssert(mapper({text:"mapped"})==="mapped","actual text mapper");return {join(separator){trace.push("join");branchSummaryAssert(separator==="\n","actual default separator");return "rendered"}}}}}};
        },
        get usage(){trace.push("usage");return 17},
    });
    const result=await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions());
    branchSummaryAssert(result.summary===branchSummaryPreamble+"rendered"&&result.usage===17,"live response result");
    branchSummarySame(trace,["stop","stop","stop","content:1","some","some:call","type","content:2","filter","map","join","usage"],"ordered live response operations");
}
async function observeBranchSummaryDate(api,state,hooks){
    branchSummaryReset(state);const before=Object.getOwnPropertyDescriptor(globalThis,"Date");let reads=0;
    Object.defineProperty(globalThis,"Date",{configurable:true,get(){
        reads++;return {carrier:hooks.make(0),get now(){const method=function(){return 91};method.carrier=hooks.make(1);return method}};
    }});
    state.completeSimple=(model,context)=>{
        branchSummarySame([hooks.count(0),hooks.count(1)],[1,1],"Date receiver and callee retired before actual request");
        branchSummaryAssert(context.messages[1].timestamp===91,"Date result retained");
        return branchSummaryReply();
    };
    try{await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions());branchSummaryAssert(reads===1,"one branch Date expression")}
    finally{Object.defineProperty(globalThis,"Date",before)}
}
async function observeBranchSummaryPredicates(api,state,hooks){
    branchSummaryReset(state);let statuses=0,contents=0;
    const response={
        get stopReason(){
            if(statuses>0)branchSummaryAssert(hooks.count(statuses-1)===1,"previous strict status operand retired");
            return {carrier:hooks.make(statuses++)};
        },
        get content(){
            contents++;
            if(contents===1){
                branchSummaryAssert(statuses===3&&hooks.count(2)===1,"all strict status temporaries finished");
                const value=[{get type(){return {carrier:hooks.make(3)}}}];value.carrier=hooks.make(5);
                const method=function(predicate){return Array.prototype.some.call(this,predicate)};method.carrier=hooks.make(4);value.some=method;return value;
            }
            branchSummarySame([hooks.count(3),hooks.count(4),hooks.count(5)],[1,1,1],"predicate receiver and callee finish before contentText input");
            return [{type:"text",text:"done"}];
        },usage:1,
    };
    state.completeSimple=()=>response;
    const result=await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions());
    branchSummaryAssert(contents===2&&result.summary===branchSummaryPreamble+"done","actual post-predicate route");
}
async function observeBranchSummaryLocals(api,state,hooks){
    branchSummaryReset(state);let release;
    const gate=new Promise(resolve=>{release=resolve});state.completeSimple=()=>gate;
    let entries=branchSummaryEntries(),options=branchSummaryOptions();
    Object.defineProperty(options,"customInstructions",{get(){return {carrier:hooks.make(2),[Symbol.toPrimitive](hint){branchSummaryAssert(hint==="string","custom template hint");return "FOCUS"}}}});
    entries.carrier=hooks.make(0);options.carrier=hooks.make(1);
    const pending=api.generateBranchSummary(entries,options);entries=options=null;
    branchSummarySame([hooks.count(0),hooks.count(1),hooks.count(2)],[0,0,0],"arguments and sole declared custom local stay live during real Await");
    release(branchSummaryReply("done"));await pending;
    branchSummarySame([hooks.count(0),hooks.count(1),hooks.count(2)],[1,1,1],"arguments and locals retire after completion");
}
async function observeBranchSummaryAdoption(api,state,hooks){
    branchSummaryReset(state);let release,adoptions=0;
    const gate=new Promise(resolve=>{release=resolve});state.completeSimple=()=>gate;
    const before=Object.getOwnPropertyDescriptor(Object.prototype,"then");
    Object.defineProperty(Object.prototype,"then",{configurable:true,get(){
        if(Object.hasOwn(this,"summary")){
            adoptions++;branchSummarySame([hooks.count(0),hooks.count(1)],[0,0],"real branch return adoption precedes original argv retirement");
        }
        return undefined;
    }});
    try{
        let entries=branchSummaryEntries(),options=branchSummaryOptions();entries.carrier=hooks.make(0);options.carrier=hooks.make(1);
        const pending=api.generateBranchSummary(entries,options);entries=options=null;
        release(branchSummaryReply());await pending;
        branchSummaryAssert(adoptions===1,"one actual final record adoption");
        branchSummarySame([hooks.count(0),hooks.count(1)],[1,1],"arguments retire after actual adoption");
    }finally{if(before)Object.defineProperty(Object.prototype,"then",before);else delete Object.prototype.then}
}
async function observeBranchSummaryData(api,state,hooks,stage){
    branchSummaryReset(state);let original;
    const options=branchSummaryOptions();
    if(stage==="before")Object.defineProperty(options.model,"contextWindow",{get(){original=hooks.freshPrivateData();throw original}});
    else state.completeSimple=()=>({get stopReason(){original=hooks.freshPrivateData();throw original}});
    const reason=await branchSummaryThrown(()=>api.generateBranchSummary(branchSummaryEntries(),options));
    branchSummaryAssert(reason===original&&hooks.isUnmarkedPrivateData(reason),"same-operation ordinary DATA keeps exact rejection identity");
}
async function observeBranchSummaryFailureValue(api,state){
    branchSummaryReset(state);const trace=[];
    state.completeSimple=()=>({stopReason:"error",get errorMessage(){trace.push("error");return {[Symbol.toPrimitive](hint){trace.push(hint);return "detail"}}}});
    branchSummarySame(await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions()),{error:"Branch summarization failed: detail"},"actual failure interpolation");
    branchSummarySame(trace,["error","string"],"error field is read once then converted with string hint");
}
async function observeBranchSummaryCurrentFatal(api,state,hooks){
    branchSummaryReset(state);hooks.freshPrivateData();
    const options={get model(){hooks.raiseNativeFatal();throw Error("current B returned")},get apiKey(){hooks.visit(1);return undefined},get callbacks(){hooks.visit(2);return undefined}};
    try{await api.generateBranchSummary(branchSummaryEntries(),options)}catch(reason){hooks.visit(3);throw reason}
}
async function observeBranchSummaryStatusStop(api,state,hooks,cancel){
    branchSummaryReset(state);let statuses=0;
    state.completeSimple=()=>({
        get stopReason(){
            if(statuses++!==0){hooks.visit(1);return "stop"}
            const value={carrier:hooks.make(0)};
            if(cancel)hooks.armCancel(0);else hooks.armFatal(0);
            return value;
        },
        get content(){hooks.visit(2);return []},
    });
    try{await api.generateBranchSummary(branchSummaryEntries(),branchSummaryOptions())}catch(reason){hooks.visit(3);throw reason}
}
async function observeBranchSummaryIteratorClose(api,state,hooks){
    branchSummaryReset(state);let reads=0,closes=0,original;
    const entries={[Symbol.iterator](){return {next(){reads++;return {done:false,value:{get type(){original=hooks.freshPrivateData();throw original}}}},return(){closes++;throw {secondary:"close"}}}},get length(){throw Error("abrupt preparation read length")}};
    const reason=await branchSummaryThrown(()=>api.generateBranchSummary(entries,branchSummaryOptions()));
    branchSummaryAssert(reason===original&&hooks.isUnmarkedPrivateData(reason)&&reads===1&&closes===1,"actual branch preparation closes iterator and keeps body DATA");
}
