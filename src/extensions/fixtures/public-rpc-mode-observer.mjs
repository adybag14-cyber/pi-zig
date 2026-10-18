// Complete c268 RPC Source and actual native body, each in a fresh realm.
// The host/session objects below are explicit guest protocol observers. Stdio,
// shell, Theme, crypto and JSONL dependencies are their genuine native owners.
const assertRpc = (condition, message) => { if (!condition) throw new Error(message); };
const rpcParse = JSON.parse, rpcStringify = JSON.stringify;
const rpcPackets = () => rpcWrites.filter(text => text.length !== 0).map(text => Reflect.apply(rpcParse, JSON, [text]));
const drainRpc = async (count = 20) => { for (let index = 0; index < count; index++) await Promise.resolve(); };
const settleRpc = async (predicate, label) => {
    for (let turn = 0; turn < 128 && !predicate(); turn++) await Promise.resolve();
    assertRpc(predicate(), "bounded RPC continuation: " + label);
};
function rpcHost() {
    const row = { trace: [], calls: [], bindings: [], events: [], backpressures: [], exits: [], signals: [], input: [],
        disposals: 0, unsubscribes: 0, backpressureUnsubscribes: 0, nextId: 0, leaf: "entry-2",
        entries: [{id:"entry-1",type:"message"},{id:"entry-2",type:"message"}],
        model: {provider:"actual-provider",id:"actual-model"}, transition: {cancelled:true,selectedText:"selected"},
    };
    const record = (name, receiver, args) => { row.calls.push({name,receiver,args:Array.from(args)}); };
    const session = {
        model: row.model, thinkingLevel:"medium", isStreaming:false, isCompacting:false, steeringMode:"one-at-a-time",
        followUpMode:"all", sessionFile:"actual.session.jsonl", sessionId:"actual-session", sessionName:"Actual",
        autoCompactionEnabled:true, messages:[{role:"user",content:"actual"}], pendingMessageCount:2,
        modelRuntime: {getAvailableSnapshot() {record("available",this,arguments);return [row.model];}},
        async bindExtensions(options) {row.trace.push("bind");record("bind",this,arguments);row.binding=options;row.bindings.push(options);},
        subscribe(callback) {row.trace.push("subscribe");row.events.push(callback);return () => {row.trace.push("unsubscribe");row.unsubscribes++;};},
        agent: {subscribe(callback) {row.trace.push("agent-subscribe");row.backpressures.push(callback);return () => {row.trace.push("agent-unsubscribe");row.backpressureUnsubscribes++;};}},
        prompt(message,options) {record("prompt",this,arguments);options.preflightResult("accepted");return Promise.resolve();},
        async steer() {record("steer",this,arguments);return "steered";},
        async followUp() {record("followUp",this,arguments);return "followed";},
        async abort() {record("abort",this,arguments);},
        clearQueue() {record("clearQueue",this,arguments);return {steering:1,followUp:2};},
        async setModel() {record("setModel",this,arguments);},
        async cycleModel() {record("cycleModel",this,arguments);return row.cycleModelResult;},
        setThinkingLevel() {record("setThinkingLevel",this,arguments);},
        cycleThinkingLevel() {record("cycleThinkingLevel",this,arguments);return row.cycleThinkingResult;},
        getAvailableThinkingLevels() {record("getAvailableThinkingLevels",this,arguments);return ["off","medium"];},
        setSteeringMode() {record("setSteeringMode",this,arguments);},
        setFollowUpMode() {record("setFollowUpMode",this,arguments);},
        async compact() {record("compact",this,arguments);return {tokensBefore:9};},
        setAutoCompactionEnabled() {record("setAutoCompactionEnabled",this,arguments);},
        setAutoRetryEnabled() {record("setAutoRetryEnabled",this,arguments);},
        abortRetry() {record("abortRetry",this,arguments);},
        extensionRunner: {
            async emitUserBash(event) {record("emitUserBash",this,arguments);return row.bashEvent;},
            getRegisteredCommands() {record("registeredCommands",this,arguments);return [{invocationName:"extension",description:"extension description",sourceInfo:{path:"extension.ts"}}];},
        },
        recordBashResult() {record("recordBashResult",this,arguments);},
        async executeBash() {record("executeBash",this,arguments);return {output:"actual bash observer",exitCode:0};},
        abortBash() {record("abortBash",this,arguments);},
        getSessionStats() {record("getSessionStats",this,arguments);return {messages:3};},
        async exportToHtml(path) {record("exportToHtml",this,arguments);return path || "actual-export.html";},
        getUserMessagesForForking() {record("getUserMessagesForForking",this,arguments);return [{entryId:"entry-1",text:"user"}];},
        sessionManager: {
            getEntries() {record("getEntries",this,arguments);return row.entries;},
            getLeafId() {record("getLeafId",this,arguments);return row.leaf;},
            getTree() {record("getTree",this,arguments);return [{entry:"tree"}];},
            getCwd() {record("getCwd",this,arguments);return "C:/actual-rpc-observer";},
        },
        getLastAssistantText() {record("getLastAssistantText",this,arguments);return "last assistant";},
        setSessionName() {record("setSessionName",this,arguments);},
        promptTemplates:[{name:"template",description:"prompt description",sourceInfo:{path:"template.md"}}],
        resourceLoader:{getSkills(){record("getSkills",this,arguments);return {skills:[{name:"read",description:"skill description",sourceInfo:{path:"SKILL.md"}}]};}},
        waitForIdle() {record("waitForIdle",this,arguments);return "idle";},
        async navigateTree() {record("navigateTree",this,arguments);return {cancelled:false,other:"excluded"};},
        async reload() {record("reload",this,arguments);return "discarded";},
    };
    const host = {
        session,
        setRebindSession(callback) {record("setRebindSession",this,arguments);row.trace.push("set-rebind");row.rebind=callback;},
        async newSession() {record("newSession",this,arguments);return row.transition;},
        async fork() {record("fork",this,arguments);return row.transition;},
        async switchSession() {record("switchSession",this,arguments);return row.transition;},
        async dispose() {record("dispose",this,arguments);row.trace.push("dispose");row.disposals++;},
    };
    row.host=host;row.session=session;return row;
}
function instrumentRpc(row) {
    const stdin=process.stdin, original={on:process.on,off:process.off,exit:process.exit,
        inputOn:stdin.on,inputOff:stdin.off,pause:stdin.pause};
    row.stdin=stdin;
    process.on=function(signal,handler){assertRpc(this===process,"process.on receiver");row.signals.push(["on",signal,handler]);return Reflect.apply(original.on,this,[signal,handler]);};
    process.off=function(signal,handler){assertRpc(this===process,"process.off receiver");row.signals.push(["off",signal,handler]);return Reflect.apply(original.off,this,[signal,handler]);};
    process.exit=function(code){row.trace.push("exit");row.exits.push(code);};
    stdin.on=function(name,callback){assertRpc(this===stdin,"stdin.on receiver");const result=Reflect.apply(original.inputOn,this,[name,callback]);row.input.push(["on",name,callback]);return result;};
    stdin.off=function(name,callback){assertRpc(this===stdin,"stdin.off receiver");row.input.push(["off",name,callback]);return Reflect.apply(original.inputOff,this,[name,callback]);};
    stdin.pause=function(){assertRpc(this===stdin,"stdin.pause receiver");row.trace.push("pause");return Reflect.apply(original.pause,this,[]);};
    row.restore=()=>{
        for(const entry of row.signals)if(entry[0]==="on")Reflect.apply(original.off,process,[entry[1],entry[2]]);
        for(const entry of row.input)if(entry[0]==="on")Reflect.apply(original.inputOff,stdin,[entry[1],entry[2]]);
        process.on=original.on;process.off=original.off;process.exit=original.exit;
        stdin.on=original.inputOn;stdin.off=original.inputOff;stdin.pause=original.pause;rpcRawWriteControl=undefined;
    };
}
async function startRpc(row=rpcHost(), expectedFailure=false) {
    instrumentRpc(row);
    row.running=selectedRpc.runRpcMode(row.host);
    row.running.then(value=>{row.ended=true;row.endValue=value;},error=>{row.failed=true;row.failure=error;});
    await settleRpc(()=>row.failed||row.input.filter(item=>item[0]==="on"&&item[1]==="end").length===2,"mode activation");
    if(!expectedFailure)assertRpc(!row.failed&&!row.ended,"RPC remains pending after real activation");
    return row;
}
async function stopRpc(row) {
    if(row.exits.length===0){row.stdin.emit("end");await settleRpc(()=>row.exits.length>0,"EOF shutdown");}
    await drainRpc();
    assertRpc(!row.ended&&!row.failed,"runRpcMode still adopts its never-settled final Promise");
}
async function rpcRequest(row,command) {
    const input={id:"rpc-"+(++row.nextId),...command}, id=input.id;
    row.stdin.emit("data",Reflect.apply(rpcStringify,JSON,[input])+"\n");
    await settleRpc(()=>rpcPackets().some(packet=>packet.type==="response"&&packet.id===id),"response "+input.type);
    await drainRpc(8);
    const matches=rpcPackets().filter(packet=>packet.type==="response"&&packet.id===id);
    assertRpc(matches.length===1,"single response for "+input.type);
    return matches[0];
}
function rpcCall(row,name) {const values=row.calls.filter(item=>item.name===name);assertRpc(values.length>0,"actual call "+name);return values[values.length-1];}
async function observeRpcCoreCommands() {
    const row=await startRpc();
    try {
        const cases=[
            [{type:"steer",message:"steer",images:["image"]},{disposition:"steered"},"steer"],
            [{type:"follow_up",message:"follow",images:[]},{disposition:"followed"},"followUp"],
            [{type:"abort"},undefined,"abort"],[{type:"clear_queue"},{steering:1,followUp:2},"clearQueue"],
            [{type:"set_thinking_level",level:"high"},undefined,"setThinkingLevel"],
            [{type:"get_available_thinking_levels"},{levels:["off","medium"]},"getAvailableThinkingLevels"],
            [{type:"set_steering_mode",mode:"all"},undefined,"setSteeringMode"],
            [{type:"set_follow_up_mode",mode:"one-at-a-time"},undefined,"setFollowUpMode"],
            [{type:"compact",customInstructions:"retain details"},{tokensBefore:9},"compact"],
            [{type:"set_auto_compaction",enabled:false},undefined,"setAutoCompactionEnabled"],
            [{type:"set_auto_retry",enabled:true},undefined,"setAutoRetryEnabled"],
            [{type:"abort_retry"},undefined,"abortRetry"],[{type:"abort_bash"},undefined,"abortBash"],
        ];
        for(const [command,data,method]of cases){
            const response=await rpcRequest(row,command);
            assertRpc(response.success===true&&response.command===command.type,"core command response "+command.type);
            assertRpc(Reflect.apply(rpcStringify,JSON,[response.data])===Reflect.apply(rpcStringify,JSON,[data]),"core data "+command.type);
            assertRpc(rpcCall(row,method).receiver===row.session,"live session receiver "+method);
            assertRpc(Object.hasOwn(response,"data")===(data!==undefined),"omitted data differs from null "+method);
        }
        const steer=rpcCall(row,"steer"),follow=rpcCall(row,"followUp");
        assertRpc(steer.args.length===3&&steer.args[0]==="steer"&&steer.args[2].source==="rpc","steer ordered arguments");
        assertRpc(follow.args.length===3&&follow.args[2].source==="rpc","follow-up source");
        assertRpc(rpcCall(row,"abort").args.length===0&&rpcCall(row,"compact").args[0]==="retain details","zero and one arguments");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcStateAndModels() {
    const row=await startRpc();
    try {
        let response=await rpcRequest(row,{type:"get_state"});
        assertRpc(response.success&&response.data.model.id==="actual-model"&&response.data.messageCount===1&&response.data.pendingMessageCount===2&&response.data.sessionName==="Actual","complete session state");
        assertRpc(Object.keys(response.data).join()==="model,thinkingLevel,isStreaming,isCompacting,steeringMode,followUpMode,sessionFile,sessionId,sessionName,autoCompactionEnabled,messageCount,pendingMessageCount","state field order");
        response=await rpcRequest(row,{type:"get_available_models"});assertRpc(response.data.models[0].provider==="actual-provider","actual model snapshot");
        response=await rpcRequest(row,{type:"set_model",provider:"actual-provider",modelId:"actual-model"});
        assertRpc(response.success&&rpcCall(row,"setModel").args[0]===row.model,"selected snapshot model identity");
        response=await rpcRequest(row,{type:"set_model",provider:"missing",modelId:"model"});
        assertRpc(!response.success&&response.error==="Model not found: missing/model","missing model diagnostic");
        response=await rpcRequest(row,{type:"cycle_model"});assertRpc(response.data===null,"empty model cycle uses null");
        row.cycleModelResult={model:row.model,thinkingLevel:"low"};
        response=await rpcRequest(row,{type:"cycle_model"});assertRpc(response.data.model.id==="actual-model","nonempty model cycle");
        response=await rpcRequest(row,{type:"cycle_thinking_level"});assertRpc(response.data===null,"empty thinking cycle uses null");
        row.cycleThinkingResult="high";
        response=await rpcRequest(row,{type:"cycle_thinking_level"});assertRpc(response.data.level==="high","nonempty thinking cycle");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcSessions() {
    const row=await startRpc();
    try {
        for(const command of[{type:"new_session",parentSession:"parent"},{type:"switch_session",sessionPath:"path"},{type:"fork",entryId:"entry-1"},{type:"clone"}]){
            const response=await rpcRequest(row,command);
            assertRpc(response.success&&response.data.cancelled===true,"cancelled session command "+command.type);
        }
        assertRpc(row.bindings.length===1,"cancelled transitions do not rebind");
        assertRpc(rpcCall(row,"newSession").args[0].parentSession==="parent","new session options");
        const clone=rpcCall(row,"fork");assertRpc(clone.args[0]==="entry-2"&&clone.args[1].position==="at","clone exact leaf and position");
        row.transition={cancelled:false,selectedText:"selected",extra:1};
        for(const type of["new_session","switch_session","fork","clone"]){
            const response=await rpcRequest(row,{type,entryId:"entry-1",sessionPath:"other"});
            assertRpc(response.success&&response.data.cancelled===false,"successful transition "+type);
        }
        assertRpc(row.bindings.length===5&&row.unsubscribes===4&&row.backpressureUnsubscribes===4,"successful transitions await rebind and retire old subscriptions");
        let response=await rpcRequest(row,{type:"get_session_stats"});assertRpc(response.data.messages===3,"session statistics");
        response=await rpcRequest(row,{type:"export_html",outputPath:"chosen.html"});assertRpc(response.data.path==="chosen.html","export path");
        response=await rpcRequest(row,{type:"get_fork_messages"});assertRpc(response.data.messages[0].entryId==="entry-1","fork messages");
        row.leaf=null;response=await rpcRequest(row,{type:"clone"});assertRpc(response.error==="Cannot clone session: no current entry selected","clone requires live leaf");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcEntriesAndCommands() {
    const row=await startRpc();
    try {
        let response=await rpcRequest(row,{type:"get_entries"});assertRpc(response.data.entries.length===2&&response.data.leafId==="entry-2","all entries");
        response=await rpcRequest(row,{type:"get_entries",since:"entry-1"});assertRpc(response.data.entries.length===1&&response.data.entries[0].id==="entry-2","entries since match");
        response=await rpcRequest(row,{type:"get_entries",since:"absent"});assertRpc(response.error==="Entry not found: absent","entries missing diagnostic");
        response=await rpcRequest(row,{type:"get_tree"});assertRpc(response.data.tree[0].entry==="tree"&&response.data.leafId==="entry-2","tree and leaf");
        response=await rpcRequest(row,{type:"get_last_assistant_text"});assertRpc(response.data.text==="last assistant","last assistant text");
        response=await rpcRequest(row,{type:"set_session_name",name:"  renamed  "});assertRpc(response.success&&rpcCall(row,"setSessionName").args[0]==="renamed","trim session name");
        response=await rpcRequest(row,{type:"set_session_name",name:" \t "});assertRpc(response.error==="Session name cannot be empty","empty name diagnostic");
        response=await rpcRequest(row,{type:"get_messages"});assertRpc(response.data.messages[0].content==="actual","messages");
        response=await rpcRequest(row,{type:"get_commands"});
        assertRpc(response.data.commands.map(command=>command.name).join()==="extension,template,skill:read","all three actual command lists");
        assertRpc(response.data.commands.map(command=>command.source).join()==="extension,prompt,skill","command sources");
        response=await rpcRequest(row,{type:"unknown"});assertRpc(response.error==="Unknown command: unknown"&&response.command==="unknown","unknown command diagnostic");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcBash() {
    const row=await startRpc();
    try {
        row.bashEvent={operations:{marker:"ops"}};
        let response=await rpcRequest(row,{type:"bash",command:"actual command",excludeFromContext:null});
        assertRpc(response.success&&response.data.output==="actual bash observer","actual execution path");
        const event=rpcCall(row,"emitUserBash"),execution=rpcCall(row,"executeBash");
        assertRpc(event.args[0].excludeFromContext===false&&event.args[0].cwd==="C:/actual-rpc-observer","event nullish default and cwd");
        assertRpc(execution.args.length===3&&execution.args[1]===undefined&&execution.args[2].excludeFromContext===null&&execution.args[2].operations===row.bashEvent.operations,"execute preserves raw options and real operations");
        row.bashEvent={result:{output:"extension result",exitCode:3}};
        response=await rpcRequest(row,{type:"bash",command:"intercepted",excludeFromContext:true});
        const recorded=rpcCall(row,"recordBashResult");
        assertRpc(response.data.output==="extension result"&&recorded.args[1]===row.bashEvent.result&&recorded.args[2].excludeFromContext===true,"extension override identity and record");
        assertRpc(row.calls.filter(call=>call.name==="executeBash").length===1,"override bypasses actual execute");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcPrompt() {
    const row=await startRpc();
    try {
        let response=await rpcRequest(row,{type:"prompt",message:"accepted",images:["actual-image"],streamingBehavior:"steer"});
        assertRpc(response.data.disposition==="accepted","authoritative preflight response");
        const call=rpcCall(row,"prompt");
        assertRpc(call.args.length===2&&call.args[0]==="accepted"&&call.args[1].source==="rpc"&&call.args[1].images[0]==="actual-image","prompt argument contract");
        let options, reject;
        row.session.prompt=(message,value)=>{options=value;return new Promise((resolve,fail)=>{reject=fail;});};
        const waiting=rpcRequest(row,{type:"prompt",message:"held"});
        await settleRpc(()=>options!==undefined,"escaped preflight");
        options.preflightResult("queued");reject(new Error("late prompt error"));
        response=await waiting;assertRpc(response.success&&response.data.disposition==="queued","escaped preflight settles response");
        await drainRpc();assertRpc(rpcPackets().filter(packet=>packet.command==="prompt").length===2,"late rejection after success has no second response");
        row.session.prompt=()=>Promise.reject(new Error("preflight failed"));
        response=await rpcRequest(row,{type:"prompt",message:"failed"});assertRpc(!response.success&&response.error==="preflight failed","early rejection response");
        await stopRpc(row);
    } finally {row.restore();}
}

async function observeRpcActionsAndEvents() {
    const row=await startRpc();
    try {
        const actions=row.binding.commandContextActions;
        assertRpc(row.binding.mode==="rpc"&&actions.waitForIdle()==="idle","actual command actions");
        const newResult=await actions.newSession({parentSession:"action-parent"});
        assertRpc(newResult===row.transition&&rpcCall(row,"newSession").args[0].parentSession==="action-parent","new action adoption and identity");
        const forked=await actions.fork("entry",{position:"before"});
        assertRpc(Object.keys(forked).join()==="cancelled"&&forked.cancelled,"fork action projection");
        const navigated=await actions.navigateTree("target",{summarize:true,customInstructions:"details",replaceInstructions:false,label:"label",ignored:1});
        const navigation=rpcCall(row,"navigateTree");
        assertRpc(navigated.cancelled===false&&Object.keys(navigated).join()==="cancelled"&&navigation.args[0]==="target","navigation result");
        assertRpc(Object.keys(navigation.args[1]).join()==="summarize,customInstructions,replaceInstructions,label","navigation option projection");
        assertRpc(await actions.switchSession("path",{resume:true})===row.transition,"switch action identity");
        assertRpc(await actions.reload()===undefined&&rpcCall(row,"reload").args.length===0,"reload discards awaited return");
        const event={type:"other",marker:"actual-event"};
        row.events[0](event);
        row.binding.onError({extensionPath:"extension.ts",event:"command",error:"actual-error",extra:"excluded"});
        await settleRpc(()=>rpcPackets().some(packet=>packet.type==="extension_error"),"extension event output");
        assertRpc(rpcPackets().some(packet=>packet.marker==="actual-event"),"real JSON event projection");
        await row.backpressures[0]();
        const previous=row.binding;
        await row.rebind();
        assertRpc(row.binding!==previous&&row.unsubscribes===1&&row.backpressureUnsubscribes===1,"closed rebind updates actual main cells");
        assertRpc(row.trace.indexOf("unsubscribe")>row.trace.lastIndexOf("bind"),"bind Await completes before old subscriptions retire");
        await stopRpc(row);
    } finally {row.restore();}
}
async function rpcUiPacket(method,oldCount) {
    await settleRpc(()=>rpcPackets().filter(packet=>packet.type==="extension_ui_request"&&packet.method===method).length>oldCount,"UI "+method);
    const matching=rpcPackets().filter(packet=>packet.type==="extension_ui_request"&&packet.method===method);
    return matching[matching.length-1];
}
function rpcUiReply(row,packet,reply) {
    row.stdin.emit("data",Reflect.apply(rpcStringify,JSON,[{type:"extension_ui_response",id:packet.id,...reply}])+"\n");
}
async function observeRpcDialogs() {
    const row=await startRpc();
    try {
        const ui=row.binding.uiContext;
        const selected=ui.select("Choose",["one","two"]);
        const selectPacket=await rpcUiPacket("select",0);
        assertRpc(selectPacket.title==="Choose"&&selectPacket.options.join()==="one,two"&&/^[0-9a-f-]{36}$/.test(selectPacket.id),"genuine UUID and select payload");
        rpcUiReply(row,selectPacket,{value:"two"});assertRpc(await selected==="two","select response");
        const confirmed=ui.confirm("Confirm","Proceed?");
        const confirmPacket=await rpcUiPacket("confirm",0);
        assertRpc(confirmPacket.message==="Proceed?"&&confirmPacket.id!==selectPacket.id,"distinct real request identity");
        rpcUiReply(row,confirmPacket,{confirmed:true});assertRpc(await confirmed===true,"confirm response");
        const input=ui.input("Input","placeholder");
        const inputPacket=await rpcUiPacket("input",0);
        rpcUiReply(row,inputPacket,{cancelled:true,value:"ignored"});assertRpc(await input===undefined,"cancelled input wins value");
        const editor=ui.editor("Edit","prefill");
        const editorPacket=await rpcUiPacket("editor",0);
        assertRpc(editorPacket.prefill==="prefill","editor prefill");
        rpcUiReply(row,editorPacket,{value:"edited"});assertRpc(await editor==="edited","genuine editor Await adoption");
        row.stdin.emit("data",Reflect.apply(rpcStringify,JSON,[{type:"extension_ui_response",id:"unknown",value:"ignored"}])+"\n");
        await drainRpc();assertRpc(rpcPackets().filter(packet=>packet.type==="response").length===0,"UI replies never become command responses");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcUiShapes() {
    const row=await startRpc();
    try {
        const ui=row.binding.uiContext;
        const names="select,confirm,input,notify,onTerminalInput,setStatus,setWorkingMessage,setWorkingVisible,setWorkingIndicator,setHiddenThinkingLabel,setWidget,setFooter,setHeader,setTitle,custom,pasteToEditor,setEditorText,getEditorText,editor,addAutocompleteProvider,setEditorComponent,getEditorComponent,theme,getAllThemes,getTheme,setTheme,getToolsExpanded,setToolsExpanded";
        assertRpc(Object.keys(ui).join()===names,"complete actual RPC UI context property order");
        for(const [name,length]of[["select",3],["confirm",3],["input",3],["notify",2],["setWidget",3],["setStatus",2],["editor",2],["custom",0],["pasteToEditor",1]]){
            const fn=ui[name];assertRpc(fn.name===name&&fn.length===length&&!Object.hasOwn(fn,"prototype"),"actual method shape "+name);
        }
        assertRpc(Object.prototype.toString.call(ui.custom)==="[object AsyncFunction]"&&Object.prototype.toString.call(ui.editor)==="[object AsyncFunction]","actual async custom/editor functions");
        assertRpc(ui.theme===actualRpcTheme&&Object.getOwnPropertyDescriptor(ui,"theme").enumerable,"original Theme proxy identity");
        assertRpc(await ui.custom()===undefined&&ui.getEditorText()===""&&ui.getEditorComponent()===undefined,"actual Source returns");
        assertRpc(ui.getAllThemes().length===0&&ui.getAllThemes()!==ui.getAllThemes()&&ui.getTheme("anything")===undefined,"fresh theme list and unsupported lookup");
        const switched=ui.setTheme(actualRpcTheme);assertRpc(!switched.success&&switched.error==="Theme switching not supported in RPC mode"&&!ui.getToolsExpanded(),"Source theme and tools decisions");
        const remove=ui.onTerminalInput(()=>{throw Error("must not invoke callback");});assertRpc(typeof remove==="function"&&!Object.hasOwn(remove,"prototype")&&remove()===undefined,"real no-op cleanup arrow");
        for(const name of["setWorkingMessage","setWorkingVisible","setWorkingIndicator","setHiddenThinkingLabel","setFooter","setHeader","addAutocompleteProvider","setEditorComponent","setToolsExpanded"])assertRpc(ui[name]("actual")===undefined,"authored Source no-op "+name);
        ui.notify("notice","warning");ui.setStatus("key","value");ui.setWidget("lines",["a","b"],{placement:"aboveEditor"});
        ui.setWidget("ignored",()=>{});ui.setWidget("removed",undefined);ui.setTitle("title");ui.pasteToEditor("pasted");
        await settleRpc(()=>rpcPackets().filter(packet=>packet.type==="extension_ui_request").length===6,"all UI output methods");
        const packets=rpcPackets();
        assertRpc(packets.map(packet=>packet.method).join()==="notify,setStatus,setWidget,setWidget,setTitle,set_editor_text","fire-and-forget order");
        assertRpc(packets[0].notifyType==="warning"&&packets[1].statusKey==="key"&&packets[2].widgetPlacement==="aboveEditor"&&packets[5].text==="pasted","wire field names");
        let receiver;
        ui.pasteToEditor.call({setEditorText(text){receiver=this;assertRpc(text==="custom receiver","paste value");}},"custom receiver");
        assertRpc(receiver!==ui,"paste uses live this.setEditorText");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcUiAbortTimeout() {
    const row=await startRpc(), oldSet=setTimeout,oldClear=clearTimeout;
    try {
        const ui=row.binding.uiContext,trace=[];let timeout,abort,timeoutReads=0;
        globalThis.setTimeout=function(callback,delay){trace.push("timer:"+delay);timeout=callback;return {timer:"actual-observer"};};
        globalThis.clearTimeout=function(token){assertRpc(token.timer==="actual-observer","same timer token");trace.push("clear");};
        const signal={aborted:false,addEventListener(name,callback,options){assertRpc(name==="abort"&&options.once===true,"signal subscription");trace.push("add");abort=callback;},
            removeEventListener(name,callback){assertRpc(name==="abort"&&callback===abort,"same abort callback");trace.push("remove");}};
        const options={signal,get timeout(){return ++timeoutReads;}};
        const pending=ui.select("Timed",["one"],options);
        const packet=await rpcUiPacket("select",0);
        assertRpc(packet.timeout===1&&timeoutReads===3&&trace.join()==="add,timer:3","live repeated timeout reads");
        timeout();assertRpc(await pending===undefined&&trace.join()==="add,timer:3,clear,remove","timeout cleanup order");
        const second=ui.confirm("Abort","message",{signal});
        await rpcUiPacket("confirm",0);abort();assertRpc(await second===false,"abort default value");
        const before=rpcPackets().length;
        assertRpc(await ui.confirm("Already aborted","message",{signal:{aborted:true}})===false,"pre-aborted default");
        await drainRpc();assertRpc(rpcPackets().length===before,"pre-aborted path publishes no request");
        await stopRpc(row);
    } finally {globalThis.setTimeout=oldSet;globalThis.clearTimeout=oldClear;row.restore();}
}
async function observeRpcPendingPublication() {
    const row=await startRpc(), set=Map.prototype.set,descriptor=Object.getOwnPropertyDescriptor(JSON,"stringify");
    let map,id,pending;
    try {
        Map.prototype.set=function(key,value){if(value&&typeof value.resolve==="function"&&typeof value.reject==="function"){map=this;id=key;pending=value;}return Reflect.apply(set,this,[key,value]);};
        const marker={marker:"dialog serialization failure"};
        Object.defineProperty(JSON,"stringify",{configurable:true,value:function(value){if(value&&value.type==="extension_ui_request")throw marker;return Reflect.apply(rpcStringify,JSON,[value]);}});
        const dialog=row.binding.uiContext.input("Fails after set");
        let caught;try{await dialog;}catch(error){caught=error;}
        assertRpc(caught===marker&&map instanceof Map&&map.get(id)===pending,"actual pending record is published before output failure");
        Object.defineProperty(JSON,"stringify",descriptor);Map.prototype.set=set;
        row.stdin.emit("data",Reflect.apply(rpcStringify,JSON,[{type:"extension_ui_response",id,value:"late"}])+"\n");
        await drainRpc();
        assertRpc(!map.has(id),"escaped real resolve cleanup remains callable after rejected construction");
        await stopRpc(row);
    } finally {Map.prototype.set=set;Object.defineProperty(JSON,"stringify",descriptor);row.restore();}
}
async function observeRpcParseAndCommandFailures() {
    const row=await startRpc(),descriptor=Object.getOwnPropertyDescriptor(JSON,"parse");
    try {
        row.stdin.emit("data","{malformed\n");
        await settleRpc(()=>rpcPackets().some(packet=>packet.command==="parse"),"real parse diagnostic");
        const parse=rpcPackets().find(packet=>packet.command==="parse");
        assertRpc(!parse.success&&!Object.hasOwn(parse,"id")&&parse.error.startsWith("Failed to parse command: "),"parse error reply");
        const marker={toString(){return "ordinary command reason";}};
        row.session.abort=()=>{throw marker;};
        let response=await rpcRequest(row,{type:"abort"});assertRpc(!response.success&&response.error==="ordinary command reason","non-Error reason uses live String");
        row.session.abort=()=>Promise.reject(new Error("async command failure"));
        response=await rpcRequest(row,{type:"abort"});assertRpc(response.error==="async command failure","rejected Await enters command catch");
        Object.defineProperty(JSON,"parse",{configurable:true,value:function(){throw {toString(){return "ordinary parse reason";}};}});
        row.stdin.emit("data","ignored\n");
        await settleRpc(()=>rpcPackets().some(packet=>packet.error==="Failed to parse command: ordinary parse reason"),"ordinary parse reason conversion");
        Object.defineProperty(JSON,"parse",descriptor);
        await stopRpc(row);
    } finally {Object.defineProperty(JSON,"parse",descriptor);row.restore();}
}
async function observeRpcTdz() {
    const row=rpcHost();let early;
    row.host.setRebindSession=function(callback){row.rebind=callback;early=callback().then(()=>({ok:true}),error=>({error}));};
    await startRpc(row);
    try {
        const result=await early;
        assertRpc(result.error instanceof ReferenceError&&String(result.error).includes("rebindSession"),"actual closed rebind cell preserves Source TDZ");
        await row.rebind();assertRpc(row.bindings.length===2,"the same escaped callback sees later initialized binding");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcShutdown(signal) {
    const row=await startRpc();
    try {
        if(signal==="EOF")row.stdin.emit("end");
        else {
            const handler=row.signals.find(item=>item[0]==="on"&&item[1]===signal);
            assertRpc(handler!==undefined,"actual signal registration");
            handler[2]();
        }
        await settleRpc(()=>row.exits.length===1,"shutdown exit");
        await drainRpc();
        const expected=signal==="EOF"?0:signal==="SIGHUP"?129:143;
        assertRpc(row.exits[0]===expected&&row.disposals===1&&row.unsubscribes===1&&row.backpressureUnsubscribes===1,"actual shutdown code and owners");
        assertRpc(rpcWrites.filter(text=>text==="").length===(signal==="SIGTERM"?0:1),"real empty-chunk flush is skipped only for SIGTERM");
        const registered=row.signals.filter(item=>item[0]==="on"),removed=row.signals.filter(item=>item[0]==="off");
        assertRpc(registered.length===removed.length,"all Source signal cleanups");
        for(let index=0;index<registered.length;index++)assertRpc(registered[index][1]===removed[index][1]&&registered[index][2]===removed[index][2],"same cleanup signal and handler");
        assertRpc(row.trace.indexOf("dispose")<row.trace.indexOf("pause")&&row.trace.indexOf("pause")<row.trace.indexOf("exit"),"dispose Await precedes detach pause and exit");
        assertRpc(row.input.filter(item=>item[0]==="on").length===row.input.filter(item=>item[0]==="off").length,"both real JSONL listeners and EOF listener detached");
    } finally {row.restore();}
}
async function observeRpcShutdownRequest() {
    const row=await startRpc();
    try {
        row.binding.shutdownHandler();
        const response=await rpcRequest(row,{type:"abort"});
        await settleRpc(()=>row.exits.length>0,"post-command requested shutdown");
        assertRpc(response.success&&row.disposals===1&&row.exits[0]===0,"command response precedes requested shutdown");
        await drainRpc();
    } finally {row.restore();}
}
async function observeRpcBackpressure() {
    const row=await startRpc();let callback;
    try {
        rpcRawWriteControl=(text,done)=>{callback=done;return true;};
        const waiting=rpcRequest(row,{type:"get_state"});
        await settleRpc(()=>callback!==undefined,"actual stdout write callback");
        let settled=false;
        const backpressure=row.backpressures[0]().then(()=>{settled=true;});
        await drainRpc();assertRpc(!settled,"real agent callback waits for the actual output queue tail");
        rpcRawWriteControl=undefined;callback();
        await backpressure;assertRpc((await waiting).success&&settled,"real callback completion resumes both owners");
        await stopRpc(row);
    } finally {rpcRawWriteControl=undefined;row.restore();}
}

async function observeRpcIntrinsicAdoption() {
    const original=Promise,constructed=[];
    function Observed(executor){assertRpc(new.target!==undefined,"actual new Promise");constructed.push(executor);return new original(executor);}
    Observed.resolve=value=>original.resolve(value);Observed.prototype=original.prototype;
    globalThis.Promise=Observed;
    let row;
    try {
        row=await startRpc();
        assertRpc(row.running instanceof original&&Object.getPrototypeOf(row.running)===original.prototype,"outer genuine AF uses intrinsic Promise");
        assertRpc(constructed.length===1&&constructed[0].length===0&&!Object.hasOwn(constructed[0],"prototype"),"final pending Promise uses live constructor and actual empty executor");
        await stopRpc(row);
    } finally {globalThis.Promise=original;if(row)row.restore();}
}
async function observeRpcRebindRetirement() {
    const row=rpcHost(),actualBind=row.session.bindExtensions;let reads=0;
    Object.defineProperty(row.host,"session",{configurable:true,get(){reads++;return reads===1?{holder:rpcHooks.make(0)}:row.session;}});
    Object.defineProperty(row.session,"bindExtensions",{configurable:true,get(){
        assertRpc(rpcHooks.count(0)===1,"new session assignment retires previous initial session before bind getter");
        const fn=function(options){return Reflect.apply(actualBind,this,[options]);};fn.holder=rpcHooks.make(1);return fn;
    }});
    const subscribe=row.session.subscribe;
    Object.defineProperty(row.session,"subscribe",{configurable:true,get(){assertRpc(rpcHooks.count(1)===1,"bind callable retires before the resumed subscribe lookup");return subscribe;}});
    await startRpc(row);
    try {
        assertRpc(reads===2&&rpcHooks.count(0)===1&&rpcHooks.count(1)===1,"actual repeated session selection and callee retirement");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcCommandRetirement() {
    const row=await startRpc();
    try {
        Object.defineProperty(row.session,"messages",{configurable:true,get(){return {holder:rpcHooks.make(0),length:3};}});
        Object.defineProperty(row.session,"pendingMessageCount",{configurable:true,get(){assertRpc(rpcHooks.count(0)===1,"messages receiver retires before later state field");return 4;}});
        let response=await rpcRequest(row,{type:"get_state"});
        assertRpc(response.data.messageCount===3&&response.data.pendingMessageCount===4,"actual state receiver control");
        Object.defineProperty(row.session,"sessionManager",{configurable:true,get(){
            return {holder:rpcHooks.make(2),get getTree(){
                const fn=function(){return ["actual tree"];};fn.holder=rpcHooks.make(1);return fn;
            },get getLeafId(){
                assertRpc(rpcHooks.count(1)===1&&rpcHooks.count(2)===0,"tree callable retires while declared manager stays live");
                return function(){return "leaf";};
            }};
        }});
        response=await rpcRequest(row,{type:"get_tree"});
        assertRpc(response.data.tree[0]==="actual tree"&&response.data.leafId==="leaf"&&rpcHooks.count(2)===1,"manager retires at command return");
        await stopRpc(row);
    } finally {row.restore();}
}
function rpcCommandIterable(slot,field,value,onDone) {
    let calls=0;
    return {[Symbol.iterator](){return {next(){
        calls++;if(calls===2){assertRpc(rpcHooks.count(slot)===0,"command head survives actual done");if(onDone)onDone();return {done:true};}
        return {done:false,value:{holder:rpcHooks.make(slot),[field]:value,description:"description",sourceInfo:{path:"actual"}}};
    }}}};
}
async function observeRpcCommandHeads() {
    const row=await startRpc();
    try {
        row.session.extensionRunner.getRegisteredCommands=()=>rpcCommandIterable(0,"invocationName","extension");
        Object.defineProperty(row.session,"promptTemplates",{configurable:true,get(){
            assertRpc(rpcHooks.count(0)===0,"extension head remains live through the later template iterable");
            return rpcCommandIterable(1,"name","template");
        }});
        row.session.resourceLoader.getSkills=()=>{
            assertRpc(rpcHooks.count(0)===0&&rpcHooks.count(1)===0,"earlier heads remain live through later skills getter");
            return {skills:rpcCommandIterable(2,"name","skill")};
        };
        const response=await rpcRequest(row,{type:"get_commands"});
        assertRpc(response.data.commands.map(command=>command.name).join()==="extension,template,skill:skill","all genuine iterators");
        assertRpc(rpcHooks.count(0)===1&&rpcHooks.count(1)===1&&rpcHooks.count(2)===1,"all final command heads retire at command completion");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcCommandClose(nextThrows) {
    const row=await startRpc();let closes=0,reads=0;
    try {
        const reason=new Error();
        Object.defineProperty(reason,"message",{get(){
            assertRpc(rpcHooks.count(0)===1&&closes===(nextThrows?0:1),"command frame retirement and IteratorClose precede error description");
            if(!nextThrows)assertRpc(rpcHooks.count(1)===1,"IteratorClose callee retires before caller catch");
            return "actual command iterator failure";
        }});
        row.session.extensionRunner.getRegisteredCommands=()=>({[Symbol.iterator](){return {
            next(){reads++;if(reads===2)throw reason;return {done:false,value:{holder:rpcHooks.make(0),invocationName:"head",get description(){if(!nextThrows)throw reason;return "first";}}};},
            get return(){const fn=function(){closes++;assertRpc(rpcHooks.count(0)===0,"abrupt close observes live Source head");return 1;};fn.holder=rpcHooks.make(1);return fn;},
        };}});
        const response=await rpcRequest(row,{type:"get_commands"});
        assertRpc(!response.success&&response.error==="actual command iterator failure"&&closes===(nextThrows?0:1),"actual next versus body abrupt close");
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcParseRetirement() {
    const row=await startRpc(),parseDescriptor=Object.getOwnPropertyDescriptor(JSON,"parse"),stringifyDescriptor=Object.getOwnPropertyDescriptor(JSON,"stringify");
    try {
        const failure=new Error();
        Object.defineProperty(failure,"message",{get(){
            assertRpc(rpcHooks.count(0)===1,"parse callable retires before catch message getter");
            return {holder:rpcHooks.make(1),[Symbol.toPrimitive](hint){assertRpc(hint==="string","parse template string coercion");return "held parse message";}};
        }});
        Object.defineProperty(JSON,"parse",{configurable:true,get(){const fn=function(){throw failure;};fn.holder=rpcHooks.make(0);return fn;}});
        Object.defineProperty(JSON,"stringify",{configurable:true,get(){
            assertRpc(rpcHooks.count(1)===1,"parse message operand retires before output serialization");
            return rpcStringify;
        }});
        row.stdin.emit("data","ignored\n");
        await settleRpc(()=>rpcPackets().some(packet=>packet.error==="Failed to parse command: held parse message"),"parse expression retirement");
        Object.defineProperty(JSON,"parse",parseDescriptor);Object.defineProperty(JSON,"stringify",stringifyDescriptor);
        await stopRpc(row);
    } finally {Object.defineProperty(JSON,"parse",parseDescriptor);Object.defineProperty(JSON,"stringify",stringifyDescriptor);row.restore();}
}
async function observeRpcPrivateData(kind) {
    const row=await startRpc();let data;
    try {
        if(kind==="command") {
            Object.defineProperty(row.session,"steer",{configurable:true,get(){data=rpcHooks.freshPrivateData();throw data;}});
            const response=await rpcRequest(row,{type:"steer",message:"ordinary"});
            assertRpc(!response.success&&response.error===data.message&&rpcHooks.isUnmarkedPrivateData(data),"same getter private DATA remains an ordinary command reason");
        } else {
            assertRpc(kind==="dialog","explicit private DATA scenario");
            const opts={get signal(){data=rpcHooks.freshPrivateData();throw data;}};
            let caught;try{row.binding.uiContext.confirm("ordinary","dialog",opts);}catch(error){caught=error;}
            assertRpc(caught===data&&rpcHooks.isUnmarkedPrivateData(data),"ordinary dialog function throws before constructing a Promise");
        }
        await stopRpc(row);
    } finally {row.restore();}
}
async function observeRpcSetupFailure() {
    const row=rpcHost();let data;
    Object.defineProperty(row.host,"session",{get(){data=rpcHooks.freshPrivateData();throw data;}});
    await startRpc(row,true);
    try {
        assertRpc(row.failure===data&&rpcHooks.isUnmarkedPrivateData(data),"initial session getter rejection identity");
        assertRpc(row.bindings.length===0&&row.signals.length===0&&row.input.length===0&&row.disposals===0,"setup failure precedes registration without invented cleanup");
    } finally {row.restore();}
}
async function observeRpcCurrentFatal() {
    const row=rpcHost();
    Object.defineProperty(row.host,"session",{get(){const prior=rpcHooks.freshPrivateData();rpcHooks.raiseNativeFatal();throw prior;}});
    row.host.dispose=async()=>{rpcHooks.record.guestReached=true;rpcHooks.visit(3);};
    try{await selectedRpc.runRpcMode(row.host);}catch(error){rpcHooks.record.guestReached=true;rpcHooks.visit(3);}
}
async function observeRpcCancellation() {
    const row=await startRpc();let calls=0;
    row.session.extensionRunner.getRegisteredCommands=()=>({[Symbol.iterator](){return {
        next(){calls++;if(calls===1)return {done:false,value:{holder:rpcHooks.make(0),invocationName:"first",description:"first"}};
            if(calls===2)return {done:false,value:{get invocationName(){rpcHooks.visit(1);return "second";}}};
            rpcHooks.visit(1);return {done:true};},
        return(){rpcHooks.visit(2);return {};},
    };}});
    rpcHooks.armCancel(0);
    row.stdin.emit("data",Reflect.apply(rpcStringify,JSON,[{id:"cancel",type:"get_commands"}])+"\n");
    await drainRpc();
    rpcHooks.visit(3);
}
