function assertCompactionText(value, message) { if (!value) throw Error(message); }
function observeCompactionTextBasic(api, text) {
    assertCompactionText(text("literal") === "literal" && text([{type:"text",text:"a"},{type:"image"},{type:"text",text:"b"}]) === "a\nb", "actual contentText default");
    assertCompactionText(text([{type:"text",text:"a"},{type:"text",text:"b"}],"") === "ab", "actual empty separator");
    const result = api.serializeConversation([
        {role:"user",content:"hello"},
        {role:"assistant",content:[{type:"thinking",thinking:"hidden"},{type:"text",text:"answer"},{type:"toolCall",name:"read",arguments:{path:"a",count:2}}]},
        {role:"toolResult",content:"x".repeat(2004)},
        {role:"system",content:"omitted"},
    ]);
    const expected = '[User]: hello\n\n[Assistant]: answer\n\n[Assistant tool calls]: read(path="a", count=2)\n\n[Tool result]: ' + "x".repeat(2000) + "\n\n[... 4 more characters truncated]";
    assertCompactionText(result === expected, "actual serialization and truncation");
}
function observeContentTextReceivers(_api, text, hooks) {
    const content = {get filter() {
        const filter = function (predicate) {
            assertCompactionText(this === content && predicate.length === 1 && !Object.hasOwn(predicate,"prototype"), "real filter arrow and receiver");
            assertCompactionText(predicate({type:"text"}) && !predicate({type:"image"}), "actual text predicate");
            return {holder:hooks.make(1),get map() {
                assertCompactionText(hooks.count(0) === 1, "filter callable retires before map getter");
                const map = function (mapper) {
                    assertCompactionText(mapper.length === 1 && !Object.hasOwn(mapper,"prototype") && mapper({text:"actual"}) === "actual", "actual mapper arrow");
                    return {holder:hooks.make(3),get join() {
                        assertCompactionText(hooks.count(1) === 1 && hooks.count(2) === 1, "map receiver and callable retire before join getter");
                        return function(separator) { assertCompactionText(separator === "\n", "actual default separator argument"); return "joined"; };
                    }};
                };
                map.holder=hooks.make(2);return map;
            }};
        };
        filter.holder=hooks.make(0);return filter;
    }};
    assertCompactionText(text(content) === "joined", "actual chained contentText");
    for(let slot=0;slot<4;slot++)assertCompactionText(hooks.count(slot)===1,"all contentText temporaries retire");
}
function observeCompactionTextPair(api, _text, hooks, invalidClose) {
    const entries = Object.getOwnPropertyDescriptor(Object,"entries"), json = Object.getOwnPropertyDescriptor(JSON,"stringify");
    let closes=0,keys=0,values=0;
    const pair = {[Symbol.iterator]() {let position=0;return {next(){
        position++;
        if(position===1)return {done:false,value:{holder:hooks.make(0),toString(){keys++;assertCompactionText(closes===1&&hooks.count(2)===1,"normal close completes before key ToString");return "key";}}};
        if(position===2)return {done:false,value:{holder:hooks.make(1),actualValue:true}};
        throw Error("destructuring read a third value");
    },return(){closes++;return invalidClose ? 1 : {holder:hooks.make(2)};}};}};
    Object.defineProperty(Object,"entries",{configurable:true,value:function(args){assertCompactionText(this===Object&&args.actualArgs,"real Object.entries call");return [pair];}});
    Object.defineProperty(JSON,"stringify",{configurable:true,value:function(value){values++;assertCompactionText(keys===1&&value.actualValue,"key coercion precedes actual JSON argument");return "encoded";}});
    let result,caught;
    try {result=api.serializeConversation([{role:"assistant",content:[{type:"toolCall",name:"tool",arguments:{actualArgs:true}}]}]);}
    catch(error){caught=error;}
    finally {Object.defineProperty(Object,"entries",entries);Object.defineProperty(JSON,"stringify",json);}
    if(invalidClose)assertCompactionText(caught instanceof TypeError&&caught.message==="not an object"&&closes===1&&keys===0&&values===0,"primitive normal IteratorClose result rejects before template");
    else assertCompactionText(result==="[Assistant tool calls]: tool(key=encoded)"&&closes===1&&keys===1&&values===1,"actual two-element destructuring");
    assertCompactionText(hooks.count(0)===1&&hooks.count(1)===1,"destructured parameters retire on completion");
}
function observeCompactionTextExpression(api, _text, hooks) {
    const entries = Object.getOwnPropertyDescriptor(Object,"entries");
    Object.defineProperty(Object,"entries",{configurable:true,get(){
        const call=function(){return {holder:hooks.make(1),get map(){
            assertCompactionText(hooks.count(0)===1,"Object.entries callee retires before map getter");
            const mapper=function(callback){
                assertCompactionText(callback.length===1&&!Object.hasOwn(callback,"prototype"),"real destructuring arrow");
                return {holder:hooks.make(3),get join(){
                    assertCompactionText(hooks.count(1)===1&&hooks.count(2)===1,"entries receiver and map callee retire before join getter");
                    return function(separator){assertCompactionText(separator===", ","actual arguments separator");return "key=value";};
                }};
            };
            mapper.holder=hooks.make(2);return mapper;
        }};};
        call.holder=hooks.make(0);return call;
    }});
    try {
        const block={type:"toolCall",arguments:{},get name(){
            assertCompactionText(hooks.count(3)===1,"mapped receiver retires before later name getter");return "tool";
        }};
        assertCompactionText(api.serializeConversation([{role:"assistant",content:[block]}])==="[Assistant tool calls]: tool(key=value)","actual entries-map-join expression");
    }finally{Object.defineProperty(Object,"entries",entries);}
}
function observeCompactionTextHeads(api, _text, hooks, fatal) {
    const join=Object.getOwnPropertyDescriptor(Array.prototype,"join");
    let argumentJoins=0,nexts=0;
    Object.defineProperty(Array.prototype,"join",{configurable:true,value:function(separator){
        if(separator!==", ")return Reflect.apply(join.value,this,arguments);
        argumentJoins++;const slot=argumentJoins===1?2:5;
        return {holder:hooks.make(slot),toString(){return "arg=value";}};
    }});
    const messages={[Symbol.iterator](){return {next(){
        nexts++;
        if(nexts===2)assertCompactionText(hooks.count(0)===0&&hooks.count(1)===0&&hooks.count(2)===0&&hooks.count(3)===0,"previous message, block and branch locals survive next");
        if(nexts===3){assertCompactionText(hooks.count(6)===0&&hooks.count(4)===0&&hooks.count(5)===0&&hooks.count(7)===0,"final heads and branch locals survive done");return {done:true};}
        const second=nexts===2;let contents=0;
        return {done:false,value:{holder:hooks.make(second?6:0),get role(){
            if(second)assertCompactionText(hooks.count(0)===1&&hooks.count(1)===0,"message replacement precedes branch entry");return "assistant";
        },get content(){
            contents++;
            if(second&&contents===1)assertCompactionText(hooks.count(1)===1&&hooks.count(2)===0&&hooks.count(3)===0,"nested head resets before iterable, inner branch locals remain");
            if(contents>1)return [];
            return [{holder:hooks.make(second?4:1),type:"toolCall",get arguments(){
                if(second){
                    if(fatal)hooks.visit(2);
                    assertCompactionText(hooks.count(2)===1&&hooks.count(3)===1,"matching inner scope resets argsStr then args before new initializer");
                }
                return {holder:hooks.make(second?7:3),arg:1};
            },name:"tool"}];
        }}};
    },return(){if(fatal)hooks.visit(2);return {done:true};}};}};
    if(fatal)hooks.armFatal(2);
    try{
        const result=api.serializeConversation(messages);
        assertCompactionText(result==="[Assistant tool calls]: tool(arg=value)\n\n[Assistant tool calls]: tool(arg=value)"&&nexts===3,"actual branch replay");
        for(let slot=0;slot<8;slot++)assertCompactionText(hooks.count(slot)===1,"all Source locals retire at function return");
    }catch(error){if(fatal)hooks.visit(3);throw error;}
    finally{Object.defineProperty(Array.prototype,"join",join);}
}
function observeCompactionTextFailure(api) {
    const events=[];
    const label={toString(){events.push("label");return "Compaction";}};
    const response={get stopReason(){events.push("stop");return "error";},get errorMessage(){events.push("message");return {toString(){events.push("message:string");return "actual";}};}};
    assertCompactionText(api.getSummarizationFailure(response,label)==="Compaction failed: actual"&&events.join()==="stop,label,message,message:string","actual failure template evaluation");
    assertCompactionText(api.getSummarizationFailure({stopReason:"error",errorMessage:""},"Branch summarization")==="Branch summarization failed: Unknown error","actual fallback");
    assertCompactionText(api.getSummarizationFailure({stopReason:"length"},"Compaction")==="Compaction failed: generation hit the token cap and the summary is incomplete","actual token cap failure");
    assertCompactionText(api.getSummarizationFailure({stopReason:"stop"},"Compaction")===undefined,"actual nonfailure");
}
function observeCompactionTextRoleReads(api) {
    const events=[];let roles=0,contents=0;
    const message={get role(){roles++;events.push("role");return "assistant";},get content(){
        contents++;events.push("content");return [{type:"text",text:"actual"}];
    }};
    assertCompactionText(api.serializeConversation([message])==="[Assistant]: actual","actual text-only assistant");
    assertCompactionText(roles===2&&contents===3&&events.join()==="role,role,content,content,content","three live content reads and repeated role decisions");
}
function observeCompactionTextPrivateData(api, _text, hooks) {
    let data,caught;
    const block={type:"toolCall",get arguments(){data=hooks.freshPrivateData();throw data;}};
    try{api.serializeConversation([{role:"assistant",content:[block]}]);}catch(error){caught=error;}
    assertCompactionText(caught===data&&hooks.isUnmarkedPrivateData(data),"actual ordinary private DATA survives two iterator scopes");
}
function observeCompactionTextClose(api, _text, hooks, nextThrows) {
    const original={},replacement={};let outerCloses=0,innerCloses=0;
    const content={[Symbol.iterator](){return {next(){
        if(nextThrows)throw original;
        return {done:false,value:{holder:hooks.make(0),get type(){throw original;}}};
    },return(){innerCloses++;assertCompactionText(hooks.count(0)===0,"inner head survives inner close");throw replacement;}};}};
    const messages={[Symbol.iterator](){return {next(){return {done:false,value:{role:"assistant",content}};},return(){outerCloses++;throw replacement;}};}};
    let caught;try{api.serializeConversation(messages);}catch(error){caught=error;}
    assertCompactionText(caught===original&&outerCloses===1&&innerCloses===(nextThrows?0:1)&&hooks.count(0)===(nextThrows?0:1),"actual nested IteratorClose precedence");
}
function observeCompactionTextCurrentFatal(api, _text, hooks) {
    const message={get role(){const data=hooks.freshPrivateData();hooks.raiseNativeFatal();throw data;}};
    try{api.serializeConversation([message]);}catch(error){hooks.visit(3);}
}
