function assertCompaction(value, message) { if (!value) throw Error(message); }
function observeCompactionUsage(api) {
    const events = [];
    const usage = {
        get totalTokens() { events.push("total"); return 0; },
        get input() { events.push("input"); return { valueOf() { events.push("input:value"); return 2; } }; },
        get output() { events.push("output"); return { valueOf() { events.push("output:value"); return 3; } }; },
        get cacheRead() { events.push("read"); return 5; },
        get cacheWrite() { events.push("write"); return 7; },
    };
    assertCompaction(api.calculateContextTokens(usage) === 17, "actual additive usage");
    assertCompaction(events.join() === "total,input,output,input:value,output:value,read,write", "live usage evaluation and left-associative coercion");
    const sentinel = {};
    assertCompaction(api.calculateContextTokens({ totalTokens: sentinel, get input() { throw Error("fallback"); } }) === sentinel, "truthy total keeps identity");
    assertCompaction(api.calculateContextTokens({totalTokens: 0, input: "2", output: 3, cacheRead: 4, cacheWrite: 5}) === "2345", "Source additive string semantics");
}
function observeCompactionLastUsage(api) {
    const events = [], chosen = { totalTokens: 9 };
    const message = {
        get role() { events.push("role"); return "assistant"; },
        get stopReason() { events.push("stop"); return "stop"; },
        get usage() { events.push("usage"); return chosen; },
    };
    const entries = [
        { type: "message", message },
        { type: "message", message: { role: "assistant", stopReason: "error", get usage() { throw Error("error usage"); } } },
        { type: "message", message: { role: "assistant", stopReason: "aborted", get usage() { throw Error("aborted usage"); } } },
        { type: "message", message: { role: "assistant", stopReason: "stop", usage: { totalTokens: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } } },
        { type: "session" },
    ];
    assertCompaction(api.getLastAssistantUsage(entries) === chosen, "last usable assistant exact identity");
    assertCompaction(events.join() === "role,stop,stop,usage,usage,usage", "repeated assistant usage and stop getters remain live");
    assertCompaction(api.getLastAssistantUsage([]) === undefined, "empty usage");
}
function observeCompactionThreshold(api, hooks) {
    let compared = false;
    const tokens = { valueOf() { compared = true; assertCompaction(hooks.count(0) === 1, "reserve operand retires before outer token comparison"); return 9; } };
    const settings = { enabled: true, get reserveTokens() { return { holder: hooks.make(0), valueOf() { return 2; } }; } };
    assertCompaction(api.shouldCompact(tokens, 10, settings) && compared, "actual strict threshold");
    assertCompaction(!api.shouldCompact(8, 10, {enabled:true,reserveTokens:2}), "threshold equality is false");
    assertCompaction(!api.shouldCompact(tokens, 10, {enabled:false,get reserveTokens(){throw Error("disabled");}}), "disabled short circuit");
}
function observeCompactionEstimates(api) {
    const cases = [
        [{role:"user",content:"abcde"},2],
        [{role:"user",content:[{type:"text",text:"abcd"},{type:"image"},{type:"text",text:""}]},1201],
        [{role:"custom",content:"abcd"},1],
        [{role:"toolResult",content:[{type:"image"}]},1200],
        [{role:"assistant",content:[{type:"text",text:"abcd"},{type:"thinking",thinking:"abcd"},{type:"toolCall",name:"tool",arguments:{}}]},4],
        [{role:"system",content:"abcd",sections:{one:"abcd",empty:"",two:"12345678"},toolsAdded:{}},5],
        [{role:"bashExecution",command:"abcd",output:"abcde"},3],
        [{role:"branchSummary",summary:"abcde"},2],
        [{role:"compactionSummary",summary:"abcd"},1],
        [{role:"unknown",get content(){throw Error("unknown content");}},0],
    ];
    for (const [message, expected] of cases) assertCompaction(api.estimateTokens(message) === expected, "actual role estimate: " + message.role);
}
function observeCompactionJSONRetirement(api, hooks, fatal) {
    const previous = Object.getOwnPropertyDescriptor(JSON, "stringify");
    let lengths = 0, calls = 0;
    const block = {
        type:"toolCall",
        get name() { return {holder:hooks.make(0),length:8}; },
        get arguments() { assertCompaction(hooks.count(0) === 1, "nested name receiver retires before argument getter"); return {}; },
    };
    Object.defineProperty(JSON, "stringify", {configurable:true,get() {
        assertCompaction(hooks.count(0) === 1, "name receiver retires before JSON callee");
        const callable = function () {
            calls++;
            assertCompaction(this === JSON && arguments.length === 1, "actual JSON receiver and argument count");
            return {holder:hooks.make(2),get length() {
                lengths++;
                if (fatal) hooks.visit(2);
                assertCompaction(hooks.count(1) === 1, "JSON callable retires before returned length getter");
                return {valueOf() { assertCompaction(hooks.count(2) === 1, "JSON result receiver retires before length coercion"); return 4; }};
            }};
        };
        callable.holder = hooks.make(1);
        return callable;
    }});
    if (fatal) hooks.armFatal(1);
    try {
        const result = api.estimateTokens({role:"assistant",content:[block]});
        assertCompaction(result === 3 && calls === 1 && lengths === 1 && hooks.count(0) === 1 && hooks.count(1) === 1 && hooks.count(2) === 1, "actual nested expression retirement");
    } catch (error) {
        if (fatal) hooks.visit(3);
        throw error;
    } finally {
        Object.defineProperty(JSON, "stringify", previous);
    }
}
function observeCompactionTextHeads(api, hooks) {
    let nexts = 0;
    const content = {[Symbol.iterator]() { return {next() {
        nexts++;
        if (nexts === 2) assertCompaction(hooks.count(0) === 0, "text helper old block survives next");
        if (nexts === 3) {
            assertCompaction(hooks.count(1) === 0, "text helper final block survives done");
            return {done:true};
        }
        const slot = nexts - 1;
        return {done:false,value:{holder:hooks.make(slot),get type() {
            if (slot === 1) assertCompaction(hooks.count(0) === 1, "new text head replaces old before body");
            return "image";
        }}};
    }}}};
    const descriptor = Object.getOwnPropertyDescriptor(Math, "ceil");
    Object.defineProperty(Math, "ceil", {configurable:true,get() {
        assertCompaction(hooks.count(0) === 1 && hooks.count(1) === 1, "helper lexical heads retire before caller Math getter");
        return descriptor.value;
    }});
    try { assertCompaction(api.estimateTokens({role:"user",content}) === 2400 && nexts === 3, "actual iterable text helper"); }
    finally { Object.defineProperty(Math, "ceil", descriptor); }
}
function observeCompactionSystemHeads(api, hooks) {
    const values = Object.getOwnPropertyDescriptor(Object, "values"), ceil = Object.getOwnPropertyDescriptor(Math, "ceil");
    let nexts = 0, sectionReads = 0, toolReads = 0;
    Object.defineProperty(Object, "values", {configurable:true,value:function (sections) {
        assertCompaction(this === Object && sections === "actual-sections", "actual Object.values receiver");
        return {[Symbol.iterator]() { return {next() {
            nexts++;
            if (nexts === 2) assertCompaction(hooks.count(0) === 0, "system section survives next");
            if (nexts === 3) { assertCompaction(hooks.count(1) === 0, "system section survives done"); return {done:true}; }
            const slot = nexts - 1;
            return {done:false,value:{holder:hooks.make(slot),get length() {
                if (slot === 1) assertCompaction(hooks.count(0) === 1, "section head assignment precedes body");
                return 4;
            }}};
        }}}};
    }});
    Object.defineProperty(Math, "ceil", {configurable:true,get() {
        assertCompaction(hooks.count(1) === 0, "outer system section survives later Math lookup");
        return ceil.value;
    }});
    try {
        const message = {role:"system",content:"",get sections(){sectionReads++;return "actual-sections";},get toolsAdded(){
            toolReads++; assertCompaction(hooks.count(1) === 0, "outer section survives post-loop tools check"); return undefined;
        }};
        assertCompaction(api.estimateTokens(message) === 2, "actual system sections");
        assertCompaction(sectionReads === 2 && toolReads === 1 && nexts === 3 && hooks.count(1) === 1, "system head retires at outer function exit");
    } finally {
        Object.defineProperty(Object, "values", values); Object.defineProperty(Math, "ceil", ceil);
    }
}
function compactionEntries() {
    return [
        {type:"session"},
        {type:"message",message:{role:"user",content:"abcd"}},
        {type:"model_change",provider:"p",modelId:"m"},
        {type:"message",message:{role:"assistant",content:[{type:"toolCall",name:"read",arguments:{}}]}},
        {type:"message",message:{role:"toolResult",content:"x".repeat(80)}},
    ];
}
function observeCompactionCuts(api) {
    const entries = compactionEntries();
    let result = api.findCutPoint(entries,1,entries.length,1);
    assertCompaction(result.firstKeptEntryIndex === 2 && result.turnStartIndex === 1 && result.isSplitTurn, "tool result fallback keeps its assistant and adjacent metadata");
    result = api.findCutPoint(entries,1,entries.length,10000);
    assertCompaction(result.firstKeptEntryIndex === 1 && result.turnStartIndex === -1 && !result.isSplitTurn, "full turn at large budget");
    entries[2] = {type:"compaction"};
    result = api.findCutPoint(entries,1,entries.length,1);
    assertCompaction(result.firstKeptEntryIndex === 3 && result.turnStartIndex === 1 && result.isSplitTurn, "metadata scan stops at compaction");
    result = api.findCutPoint([{type:"session"},{type:"model_change"}],0,2,10);
    assertCompaction(result.firstKeptEntryIndex === 0 && result.turnStartIndex === -1 && !result.isSplitTurn, "no valid cut point");
    assertCompaction(api.findTurnStartIndex(entries,4,1) === 1, "context-visible turn lookup");
}
function observeCompactionMethods(api) {
    const some = Object.getOwnPropertyDescriptor(Array.prototype,"some"), reduce = Object.getOwnPropertyDescriptor(Array.prototype,"reduce"), find = Object.getOwnPropertyDescriptor(Array.prototype,"find");
    let cut, turn, someCalls = 0, reduceCalls = 0, findCalls = 0;
    Object.defineProperty(Array.prototype,"some",{configurable:true,value:function(callback) {
        someCalls++; assertCompaction(Array.isArray(this) && callback.length === 1 && Object.hasOwn(callback,"prototype"), "actual some receiver and ordinary helper");
        if (callback.name === "isCutPointMessage") { if(cut)assertCompaction(cut === callback,"one cut helper binding");cut=callback; }
        else { assertCompaction(callback.name === "isTurnStartMessage","actual turn helper");if(turn)assertCompaction(turn===callback,"one turn helper binding");turn=callback; }
        return Reflect.apply(some.value,this,arguments);
    }});
    Object.defineProperty(Array.prototype,"reduce",{configurable:true,value:function(callback,initial) {
        reduceCalls++; assertCompaction(Array.isArray(this) && callback.length === 2 && !Object.hasOwn(callback,"prototype") && initial === 0, "actual reduce arrow and arguments");
        return Reflect.apply(reduce.value,this,arguments);
    }});
    Object.defineProperty(Array.prototype,"find",{configurable:true,value:function(callback) {
        findCalls++; assertCompaction(Array.isArray(this) && callback.length === 1 && !Object.hasOwn(callback,"prototype"), "actual find arrow");
        return Reflect.apply(find.value,this,arguments);
    }});
    try {
        const result = api.findCutPoint(compactionEntries(),1,5,1);
        assertCompaction(result.firstKeptEntryIndex === 2 && someCalls >= 5 && reduceCalls === 1 && findCalls === 1 && cut && turn, "actual live array methods are reached");
    } finally {
        Object.defineProperty(Array.prototype,"some",some); Object.defineProperty(Array.prototype,"reduce",reduce); Object.defineProperty(Array.prototype,"find",find);
    }
}
function observeCompactionTurnNumeric(api, hooks) {
    let conditions = 0;
    const entries = {
        get 2() { return {holder:hooks.make(0),type:"message",message:{role:"assistant",content:[]}}; },
        get 1() { return {holder:hooks.make(1),type:"message",message:{role:"user",content:""}}; },
    };
    const start = {valueOf() {
        conditions++;
        if (conditions === 2) assertCompaction(hooks.count(0) === 1, "temporary turn entry retires before next loop comparison");
        return 0n;
    }};
    assertCompaction(api.findTurnStartIndex(entries,2n,start) === 1n, "real decrement retains BigInt numeric type");
    assertCompaction(conditions === 2 && hooks.count(0) === 1 && hooks.count(1) === 1, "actual turn expression owners retire");
}
function observeCompactionClose(api, hooks, nextThrows) {
    const original = {}, replacement = {};
    let closes = 0;
    const content = {[Symbol.iterator]() { return {next() {
        if (nextThrows) throw original;
        return {done:false,value:{holder:hooks.make(0),get type(){throw original;}}};
    },get return() {
        closes++; assertCompaction(hooks.count(0) === 0, "head survives IteratorClose getter");
        return function(){throw replacement;};
    }};}};
    let caught;
    try { api.estimateTokens({role:"user",content}); } catch(error) { caught=error; }
    assertCompaction(caught === original && closes === (nextThrows ? 0 : 1) && hooks.count(0) === (nextThrows ? 0 : 1), "actual close and original abrupt completion precedence");
}
function observeCompactionPrivateData(api, hooks) {
    let data, caught;
    const usage = {get totalTokens(){data=hooks.freshPrivateData();throw data;}};
    try { api.calculateContextTokens(usage); } catch(error) {caught=error;}
    assertCompaction(caught === data && hooks.isUnmarkedPrivateData(data), "same getter operation preserves ordinary private DATA identity");
}
function observeCompactionCurrentFatal(api, hooks) {
    const message = {role:"user",get content(){const data=hooks.freshPrivateData();hooks.raiseNativeFatal();throw data;}};
    try { api.estimateTokens(message); } catch(error) {hooks.visit(3);}
}
function observeCompactionCancellation(api, hooks) {
    let nexts = 0;
    const content = {[Symbol.iterator]() {return {next() {
        nexts++; if(nexts>2)hooks.visit(1);
        return {done:false,value:{holder:hooks.make(nexts-1),get type(){if(nexts===2)hooks.visit(1);return "text";},text:"abcd"}};
    },return(){hooks.visit(2);return {done:true};}};}};
    hooks.armCancel(0);
    api.estimateTokens({role:"assistant",content});
}
