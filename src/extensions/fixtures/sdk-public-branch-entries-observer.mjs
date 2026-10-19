function assertBranch(condition,message){if(!condition)throw Error(message);}
function observeBranchCollectBasic(api) {
    const root={id:"root",parentId:null},fork={id:"fork",parentId:"root"},left={id:"left",parentId:"fork"},leaf={id:"leaf",parentId:"left"};
    const right={id:"right",parentId:"fork"},target={id:"target",parentId:"right"};
    const records={root,fork,left,leaf,right,target};
    let entriesRead=0;
    const session={
        getBranch(id){assertBranch(this===session,"real session branch receiver");return id==="leaf"?[root,fork,left,leaf]:id==="target"?[root,fork,right,target]:[];},
        getEntry(id){assertBranch(this===session,"real session entry receiver");entriesRead++;return records[id];},
    };
    const result=api.collectEntriesForBranchSummary(session,"leaf","target");
    assertBranch(Object.keys(result).join()==="entries,commonAncestorId"&&result.commonAncestorId==="fork"&&result.entries.length===2&&result.entries[0]===left&&result.entries[1]===leaf&&entriesRead===2,"deepest common ancestor and chronological actual entries");
    entriesRead=0;
    const unchanged=api.collectEntriesForBranchSummary(session,"leaf","leaf");
    assertBranch(unchanged.commonAncestorId==="leaf"&&unchanged.entries.length===0&&entriesRead===0,"same branch has no entry traversal");
    const missing=api.collectEntriesForBranchSummary(session,"missing","target");
    assertBranch(missing.commonAncestorId===null&&missing.entries.length===0,"missing old entry stops actual traversal");
    const unopened=new Proxy({},{get(){throw Error("empty old position must not touch session")}});
    for(const old of [null,undefined,"",0,false,NaN]){
        const empty=api.collectEntriesForBranchSummary(unopened,old,"ignored");
        assertBranch(empty.commonAncestorId===null&&empty.entries.length===0,"all actual falsy old positions");
    }
}
function observeBranchCollectExpressions(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set");let branches=0;
    const session={get getBranch(){
        if(branches===0){
            const method=function(id){
                assertBranch(this===session&&id==="old","actual first getBranch receiver and argument");branches++;
                return {holder:hooks.make(0),marker:"branch",get map(){
                    assertBranch(hooks.count(5)===1,"getBranch callee retires before map getter");
                    const mapper=function(callback){
                        assertBranch(this.marker==="branch"&&callback.length===1&&!Object.hasOwn(callback,"prototype")&&callback({id:"mapped-id"})==="mapped-id","actual map receiver and arrow callback");
                        return {holder:hooks.make(2),marker:"mapped"};
                    };mapper.holder=hooks.make(1);return mapper;
                }};
            };method.holder=hooks.make(5);return method;
        }
        assertBranch(hooks.count(0)===1&&hooks.count(1)===1&&hooks.count(2)===1&&hooks.count(3)===1&&hooks.count(4)===0,"old path expression completes before target getBranch");
        return function(id){assertBranch(this===session&&id==="target","actual second getBranch receiver");branches++;return [];};
    },getEntry(){return undefined;}};
    Object.defineProperty(globalThis,"Set",{configurable:true,get(){
        assertBranch(branches===0,"Set constructor lookup precedes getBranch");
        const constructor=function(mapped){
            assertBranch(mapped.marker==="mapped"&&hooks.count(0)===1&&hooks.count(1)===1,"mapped receiver and method retire before construction");
            return {holder:hooks.make(4),has(){throw Error("empty target must not call has")}};
        };constructor.prototype=null;constructor.holder=hooks.make(3);return constructor;
    }});
    try{api.collectEntriesForBranchSummary(session,"old","target");}finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertBranch(branches===2&&hooks.count(4)===1,"old Set lexical owner retires at function completion");
}
function observeBranchCollectRepeatedId(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set");let indices=0,branches=0;
    const target={length:1,get 0(){
        indices++;
        if(indices===1)return {holder:hooks.make(1),id:"membership-id"};
        assertBranch(hooks.count(1)===1&&hooks.count(0)===1&&hooks.count(2)===1,"matching has expression retires before repeated id lookup");
        return {id:"selected-id"};
    }};
    Object.defineProperty(globalThis,"Set",{configurable:true,value:function(){
        return {get has(){
            assertBranch(indices===0,"has callee selected before indexed id argument");
            const method=function(id){assertBranch(id==="membership-id"&&hooks.count(1)===1&&hooks.count(0)===0,"indexed receiver retires before has call");return {holder:hooks.make(2)};};
            method.holder=hooks.make(0);return method;
        }};
    }});
    let result;
    try{result=api.collectEntriesForBranchSummary({getBranch(){return ++branches===1?[]:target},getEntry(){return undefined}},"old","target");}
    finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertBranch(indices===2&&result.commonAncestorId==="selected-id","matching target entry id remains a live second read");
}
function observeBranchCollectEntrySlots(api,hooks) {
    const push=Object.getOwnPropertyDescriptor(Array.prototype,"push"),reverse=Object.getOwnPropertyDescriptor(Array.prototype,"reverse");let gets=0,pushes=0,reverses=0;
    Object.defineProperty(Array.prototype,"push",{configurable:true,writable:true,value:function(entry){pushes++;return undefined;}});
    Object.defineProperty(Array.prototype,"reverse",{configurable:true,writable:true,value:function(){
        reverses++;assertBranch(hooks.count(0)===1&&hooks.count(1)===0,"final while entry survives normal loop exit and reverse");return this;
    }});
    try{
        const session={getBranch(){return []},getEntry(id){
            gets++;
            if(gets===1){assertBranch(id==="old","first old entry id");return {holder:hooks.make(0),parentId:"parent"};}
            assertBranch(id==="parent"&&hooks.count(0)===1,"while entry resets before next getEntry");
            return {holder:hooks.make(1),parentId:null};
        }};
        const result=api.collectEntriesForBranchSummary(session,"old","target");
        assertBranch(result.entries.length===0&&result.commonAncestorId===null,"live push and reverse methods determine returned entries");
    }finally{Object.defineProperty(Array.prototype,"push",push);Object.defineProperty(Array.prototype,"reverse",reverse);}
    assertBranch(gets===2&&pushes===2&&reverses===1&&hooks.count(1)===1,"final while entry retires at function completion");
}
function observeBranchPrepareBasic(api) {
    const timestamp="1970-01-01T00:00:00.000Z",details={kept:"identity"};
    const user={role:"user",content:"hello",timestamp:0};
    const assistant={role:"assistant",content:[{type:"toolCall",name:"read",arguments:{path:"assistant-read"}}]};
    const entries=[
        {type:"branch_summary",summary:"old",fromId:"origin",timestamp,details:{readFiles:["old-read"],modifiedFiles:["old-mod"]}},
        {type:"branch_summary",summary:"hook",fromId:"hook-origin",timestamp,fromHook:true,details:{readFiles:["ignored-hook"],modifiedFiles:["ignored-hook-mod"]}},
        {type:"message",message:user},
        {type:"message",message:{role:"toolResult",content:"ignored"}},
        {type:"custom_message",customType:"actual",content:"custom",display:false,details,timestamp},
        {type:"compaction",summary:"saved",tokensBefore:99,timestamp},
        {type:"thinking_level_change",thinkingLevel:"high"},
        {type:"message",message:assistant},
    ];
    const result=api.prepareBranchEntries(entries);
    assertBranch(Object.keys(result).join()==="messages,fileOps,totalTokens"&&result.totalTokens===16,"actual prepared result order and estimates");
    assertBranch(result.messages.map(message=>message.role).join()==="branchSummary,branchSummary,user,custom,compactionSummary,assistant","chronological actual message conversions");
    assertBranch(result.messages[2]===user&&result.messages[5]===assistant,"real message identities are preserved");
    assertBranch(result.messages[0].fromId==="origin"&&result.messages[0].timestamp===0&&result.messages[3].details===details&&result.messages[3].customType==="actual"&&result.messages[3].display===false&&result.messages[4].tokensBefore===99,"real branch custom and compaction records");
    assertBranch([...result.fileOps.read].join()==="old-read,assistant-read"&&[...result.fileOps.edited].join()==="old-mod"&&result.fileOps.written.size===0,"all previous generated tracking and actual assistant extraction");
}
function observeBranchPrepareBudget(api) {
    const entries=[
        {type:"branch_summary",summary:"old",fromId:"root",timestamp:0,details:{readFiles:["outside-budget"],modifiedFiles:[]}},
        {type:"compaction",summary:"0123456789abcdef",tokensBefore:200,timestamp:0},
        {type:"message",message:{role:"user",content:"12345678"}},
    ];
    const include=api.prepareBranchEntries(entries,3),exclude=api.prepareBranchEntries(entries,2);
    assertBranch(include.totalTokens===6&&include.messages.length===2&&include.messages[0].role==="compactionSummary"&&include.messages[1]===entries[2].message,"important summary may cross a partially unused budget");
    assertBranch(exclude.totalTokens===2&&exclude.messages.length===1&&exclude.messages[0]===entries[2].message,"full budget excludes an older summary");
    assertBranch(include.fileOps.read.has("outside-budget")&&exclude.fileOps.read.has("outside-budget"),"all branch tracking is collected before message budget selection");
}
function observeBranchOuterHead(api,hooks) {
    let nexts=0,lengths=0;
    const entries={[Symbol.iterator](){return {next(){
        nexts++;
        if(nexts===2)assertBranch(hooks.count(0)===0,"first branch head survives next");
        if(nexts===3){assertBranch(hooks.count(0)===1&&hooks.count(1)===0,"last branch head survives final done");return {done:true};}
        return {done:false,value:{holder:hooks.make(nexts-1),type:"ignored"}};
    }}},get length(){lengths++;assertBranch(hooks.count(1)===0,"first-pass final head survives second-pass length getter");return 0;}};
    const result=api.prepareBranchEntries(entries);
    assertBranch(nexts===3&&lengths===1&&result.messages.length===0&&hooks.count(0)===1&&hooks.count(1)===1,"first-pass final head retires only at preparation completion");
}
function observeBranchDetailAndPathHeads(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set");let constructors=0,entryNexts=0,detailReads=0,readReads=0,pathNexts=0,adds=0;
    Object.defineProperty(globalThis,"Set",{configurable:true,value:function(){constructors++;return {add(value){adds++;}};}});
    const paths={[Symbol.iterator](){return {next(){
        pathNexts++;
        if(pathNexts===2)assertBranch(hooks.count(0)===0,"read path head survives next");
        if(pathNexts===3){assertBranch(hooks.count(0)===1&&hooks.count(1)===0,"last read path head survives done");return {done:true};}
        return {done:false,value:{holder:hooks.make(pathNexts-1)}};
    }}}};
    const entries={[Symbol.iterator](){return {next(){
        entryNexts++;
        if(entryNexts===1)return {done:false,value:{type:"branch_summary",fromHook:false,get details(){
            detailReads++;
            if(detailReads===1)return {holder:hooks.make(2)};
            assertBranch(hooks.count(2)===1,"condition details temporary retires before declaration getter");
            return {holder:hooks.make(3),get readFiles(){return ++readReads===1?[]:paths;},get modifiedFiles(){
                assertBranch(hooks.count(0)===1&&hooks.count(1)===0&&hooks.count(3)===0,"read head and details survive later predicate");
                return undefined;
            }};
        }}};
        assertBranch(hooks.count(1)===0&&hooks.count(3)===0,"nested head and details survive following outer next");
        return entryNexts===2?{done:false,value:{type:"ignored"}}:{done:true};
    }}},get length(){assertBranch(hooks.count(1)===0&&hooks.count(3)===0,"final path and details survive first-pass normal exit");return 0;}};
    try{api.prepareBranchEntries(entries);}finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertBranch(constructors===3&&adds===2&&detailReads===2&&readReads===2&&entryNexts===3&&pathNexts===3&&hooks.count(1)===1&&hooks.count(3)===1,"nested path and details slots retire at function completion");
}
function observeBranchReverseSlots(api,hooks) {
    const ceil=Object.getOwnPropertyDescriptor(Math,"ceil"),unshift=Object.getOwnPropertyDescriptor(Array.prototype,"unshift");let reads=0,estimates=0,pushes=0;
    Object.defineProperty(Math,"ceil",{configurable:true,writable:true,value:function(value){
        estimates++;return {holder:hooks.make(0),valueOf(){return 1;}};
    }});
    Object.defineProperty(Array.prototype,"unshift",{configurable:true,writable:true,value:function(){pushes++;return 1;}});
    const entries={[Symbol.iterator](){return {next(){return {done:true}}}},length:2,get 1(){
        return {holder:hooks.make(2),type:"message",get message(){
            if(++reads===1)return {role:"user"};
            return {holder:hooks.make(1),role:"user",content:"x"};
        }};
    },get 0(){
        assertBranch(hooks.count(0)===1&&hooks.count(1)===1&&hooks.count(2)===1,"tokens message and entry slots reset before next index getter");return {type:"ignored"};
    }};
    let result;
    try{result=api.prepareBranchEntries(entries);}finally{Object.defineProperty(Math,"ceil",ceil);Object.defineProperty(Array.prototype,"unshift",unshift);}
    assertBranch(estimates===1&&pushes===1&&reads===2&&result.totalTokens===1&&result.messages.length===0,"actual reverse branch body slots and discarded message");
}
function observeBranchRecordOrder(api,hooks,kind) {
    const date=Object.getOwnPropertyDescriptor(globalThis,"Date"),trace=[];
    Object.defineProperty(globalThis,"Date",{configurable:true,writable:true,value:function(value){
        assertBranch(new.target&&value==="actual-time","real Date construction argument");trace.push("Date");
        return {marker:"date",get getTime(){trace.push("getTime");return function(){assertBranch(this.marker==="date","real date method receiver");trace.push("callTime");return 123;};}};
    }});
    const entry={},fields=kind==="custom_message"?["customType","content","display","details","timestamp"]:kind==="branch_summary"?["summary","fromId","timestamp"]:["summary","tokensBefore","timestamp"];
    Object.defineProperty(entry,"type",{get(){trace.push("type");return kind;}});
    if(kind==="branch_summary")Object.defineProperty(entry,"fromHook",{get(){trace.push("fromHook");return true;}});
    const values={customType:"custom-kind",content:"abcd",display:false,details:undefined,timestamp:"actual-time",summary:"abcd",fromId:"from",tokensBefore:5};
    for(const name of fields)Object.defineProperty(entry,name,{get(){trace.push(name);return values[name];}});
    let result;
    try{result=api.prepareBranchEntries([entry]);}finally{Object.defineProperty(globalThis,"Date",date);}
    const prefix=kind==="branch_summary"?["type","fromHook","type"]:["type","type"];
    assertBranch(JSON.stringify(trace)===JSON.stringify([...prefix,...fields,"Date","getTime","callTime"]),"actual entry record getter and Date ordering");
    assertBranch(result.messages.length===1&&result.messages[0].timestamp===123&&result.totalTokens===1,"real converted record timestamp and estimation");
}
function observeBranchRepeatedMessage(api,hooks,role) {
    let reads=0;
    const selected={role:"user",content:"abcd"},entry={type:"message",get message(){
        if(++reads===1)return {holder:hooks.make(0),role};
        assertBranch(hooks.count(0)===1,"first message receiver retires before repeated message getter");return selected;
    }};
    const result=api.prepareBranchEntries([entry]);
    assertBranch(hooks.count(0)===1&&(role==="toolResult"?reads===1&&result.messages.length===0:reads===2&&result.messages.length===1&&result.messages[0]===selected),"actual message role check and live repeated getter");
}
function observeBranchBudgetCoercion(api,hooks) {
    const ceil=Object.getOwnPropertyDescriptor(Math,"ceil"),unshift=Object.getOwnPropertyDescriptor(Array.prototype,"unshift"),trace=[];
    const budget={valueOf(){trace.push("budget");return 1;}};
    Object.defineProperty(Math,"ceil",{configurable:true,writable:true,value:function(){return {holder:hooks.make(0),valueOf(){trace.push("token");return 2;}};}});
    Object.defineProperty(Array.prototype,"unshift",{configurable:true,writable:true,value:function(value){
        trace.push("unshift");assertBranch(hooks.count(0)===0,"token lexical value survives insertion");return unshift.value.call(this,value);
    }});
    let result;
    try{result=api.prepareBranchEntries([{type:"compaction",summary:"x",tokensBefore:0,timestamp:0}],budget);}
    finally{Object.defineProperty(Math,"ceil",ceil);Object.defineProperty(Array.prototype,"unshift",unshift);}
    assertBranch(trace.join()==="budget,token,budget,budget,unshift,token"&&result.totalTokens===2&&result.messages.length===1&&hooks.count(0)===1,"live budget comparisons threshold and total coercion order");
}
function observeBranchNestedClose(api,hooks,kind) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set"),trace=[];let sets=0,readReads=0,entryNexts=0,pathNexts=0,reason,caught;
    Object.defineProperty(globalThis,"Set",{configurable:true,value:function(){
        const index=sets++;
        return {add(){
            if(index!==0)throw Error("unexpected branch file set");
            reason=kind==="ordinary"?{actual:"body"}:hooks.freshPrivateData();
            if(kind==="fatal")hooks.raiseNativeFatal();
            throw reason;
        }};
    }});
    const paths={[Symbol.iterator](){return {next(){pathNexts++;return {done:false,value:"path"}},return(){
        if(kind==="fatal")hooks.visit(2);trace.push("path-return");throw {secondary:"path"};
    }}}};
    const details={get readFiles(){return ++readReads===1?[]:paths;}};
    const entries={[Symbol.iterator](){return {next(){entryNexts++;return {done:false,value:{type:"branch_summary",details}}},return(){
        if(kind==="fatal")hooks.visit(2);trace.push("entry-return");throw {secondary:"entry"};
    }}},get length(){throw Error("abrupt first pass must not reach length")}};
    try{
        try{api.prepareBranchEntries(entries);}catch(error){if(kind==="fatal")hooks.visit(3);caught=error;}
    }finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertBranch(kind!=="fatal"&&caught===reason&&sets===3&&entryNexts===1&&pathNexts===1&&trace.join()==="path-return,entry-return","nested branch IteratorClose keeps actual body reason");
    if(kind==="data")assertBranch(hooks.isUnmarkedPrivateData(reason),"same-call private DATA stays ordinary through both close boundaries");
}
function observeBranchSlotStop(api,hooks,cancel) {
    const ceil=Object.getOwnPropertyDescriptor(Math,"ceil"),unshift=Object.getOwnPropertyDescriptor(Array.prototype,"unshift");
    Object.defineProperty(Math,"ceil",{configurable:true,writable:true,value:function(){
        const token={holder:hooks.make(0),valueOf(){return 1;}};
        if(cancel)hooks.armCancel(0);else hooks.armFatal(0);
        return token;
    }});
    Object.defineProperty(Array.prototype,"unshift",{configurable:true,writable:true,value:function(){return 1;}});
    const entries={[Symbol.iterator](){return {next(){return {done:true}},return(){hooks.visit(2);return {};}}},length:2,
        get 1(){return {type:"message",message:{role:"user",content:"x"}};},
        get 0(){hooks.visit(1);hooks.visit(2);return {type:"ignored"};}
    };
    try{api.prepareBranchEntries(entries);}catch(error){hooks.visit(2);}
    finally{Object.defineProperty(Math,"ceil",ceil);Object.defineProperty(Array.prototype,"unshift",unshift);}
    throw Error("actual branch slot stop returned to guest");
}
