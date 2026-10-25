// Focused source/native comparisons. Genuine imported resolver, CLI and Chalk
// owners are acquired in both realms. "controlled" cases perturb a member of
// the real resolver namespace before capture to isolate this wrapper's output
// destructuring/iterator seam. They do not qualify a physical model service.
"use strict";
function mswCheck(value, message) { if (!value) throw new Error(message); }
function mswPrepare(name) {
    const state = globalThis.__mswState = {
        name, events: [], warnings: [], scoped: [{tag:"scoped"}],
        model: {provider:"p",id:"item",name:"Item"},
        reason: {tag:"original"}, closeReason: {tag:"close"},
        diagnostics: [], options: {tag:"options"}
    };
    __mswChalk.level = 0;
    const output = {
        warn(value) {
            mswCheck(this === output, "console warning receiver");
            state.warnings.push(value);
            state.events.push("warn");
        }
    };
    globalThis.console = output;
    state.runtime = {
        getAvailable(unused, options) {
            mswCheck(this === state.runtime && arguments.length === 2 && unused === undefined,
                "actual diagnostics resolver receiver and argument count");
            mswCheck(options === state.options, "original options identity");
            state.events.push("available");
            return [state.model];
        }
    };
    state.patterns = ["p/item"];
    if (name === "empty") state.patterns = [];
    if (["missing","colored","deferred","console-order","warning-reentry"].includes(name))
        state.patterns = ["absent"];
    if (name === "colored") __mswChalk.level = 1;
    if (name === "ambiguous") {
        state.patterns = ["shared"];
        state.runtime.getAvailable = function() {
            return [{provider:"zeta",id:"shared"},{provider:"alpha",id:"shared"}];
        };
    }
    if (name === "deferred") state.runtime.getAvailable = function() {
        state.events.push("available");
        return new Promise(resolve => { state.resume = resolve; });
    };
    if (name === "rejected") state.runtime.getAvailable = function() {
        state.events.push("available"); return Promise.reject(state.reason);
    };
    if (name === "actual-data") state.runtime.getAvailable = function() {
        state.reason = __mswHooks.freshPrivateData();
        return Promise.reject(state.reason);
    };

    const ordinary = new Set([
        "shape","empty","match","missing","colored","ambiguous","options",
        "deferred","rejected","actual-data","capture-import","warning-reentry"
    ]);
    state.controlled = !ordinary.has(name);
    if (state.controlled) {
        __mswResolver.resolveModelScopeWithDiagnostics = function(patterns, runtime, options) {
            mswCheck(this === undefined, "captured named resolver receiver");
            mswCheck(arguments.length === 3, "three forwarded arguments");
            mswCheck(patterns === state.patterns && runtime === state.runtime &&
                options === state.options, "forwarded values preserved");
            state.events.push("resolve");
            return state.result;
        };
        state.result = {scopedModels:state.scoped, diagnostics:state.diagnostics};
    }
    if (name === "result-order") state.result = {
        get scopedModels(){state.events.push("scoped");return state.scoped;},
        get diagnostics(){state.events.push("diagnostics");return [];}
    };
    if (name === "boxed-once") {
        state.receivers = [];
        Object.defineProperties(Number.prototype, {
            scopedModels:{configurable:true,get(){
                state.receivers.push(this);return state.scoped;
            }},
            diagnostics:{configurable:true,get(){
                state.receivers.push(this);return [];
            }}
        });
        state.result = 1;
    }
    if (name === "null-result") state.result = null;
    if (name === "missing-diagnostics") state.result = {scopedModels:state.scoped};
    if (name === "getter-throw") state.result = {
        get scopedModels(){state.events.push("scoped");throw state.reason;},
        get diagnostics(){state.events.push("unexpected");return [];}
    };
    if (name === "diagnostics-throw") state.result = {
        get scopedModels(){state.events.push("scoped");return state.scoped;},
        get diagnostics(){state.events.push("diagnostics");throw state.reason;}
    };
    if (name === "result-thenable") state.result = {
        then(resolve){state.events.push("then");resolve({scopedModels:state.scoped,diagnostics:[]});}
    };
    if (name === "return-thenable") {
        state.final = {tag:"final"};
        state.scoped = {then(resolve){state.events.push("returned then");resolve(state.final);}};
        state.result = {scopedModels:state.scoped,diagnostics:[]};
    }
    const iteratorCases = ["cached-next","next-throw","done-throw","value-throw",
        "warn-throw","close-throw","message-symbol","message-coercion","console-order",
        "yellow-value","message-lifetime","yellow-lifetime","head-lifetime",
        "current-fatal","retirement-fatal","retirement-cancel",
        "pending-reason","deleted-console","lexical-console","console-tdz"];
    if (iteratorCases.includes(name)) {
        const iterator = {
            step:0,
            next(){
                state.events.push("next");
                if (name === "next-throw") throw state.reason;
                if (name === "done-throw") return {get done(){throw state.reason;}};
                if (name === "value-throw") return {done:false,get value(){throw state.reason;}};
                if (this.step++ === 0) {
                    if (name === "cached-next") this.next = function(){throw Error("reloaded next");};
                    return {done:false,value:state.diagnostic};
                }
                if (name === "head-lifetime")
                    mswCheck(__mswHooks.count(0) === 0, "loop head retained during final next");
                return {done:true};
            },
            return(){
                state.events.push("close");
                if (name === "close-throw") throw state.closeReason;
                return 13;
            }
        };
        state.diagnostic = {message:"detail"};
        state.result.diagnostics = {
            [Symbol.iterator](){state.events.push("iterator");return iterator;}
        };
        if (name === "warn-throw" || name === "close-throw")
            output.warn = function(){state.events.push("warn throw");throw state.reason;};
        if (name === "message-symbol") state.diagnostic.message = Symbol("message");
        if (name === "message-coercion") state.diagnostic.message = {
            [Symbol.toPrimitive](hint) {
                state.events.push("coerce:"+hint);
                mswCheck(hint === "string", "template ToString hint");
                return "converted";
            }
        };
        if (name === "console-order") {
            Object.defineProperty(output,"warn",{configurable:true,get(){
                state.events.push("warn get");
                return function(value) {
                    mswCheck(this === output && value === "Warning: converted","outer reference captured");
                    state.events.push("old warn");
                };
            }});
            Object.defineProperty(__mswChalk,"yellow",{configurable:true,get(){
                state.events.push("yellow get");
                return function(value){
                    mswCheck(this === __mswChalk,"color reference receiver");
                    state.events.push("yellow call");return value;
                };
            }});
            Object.defineProperty(state.diagnostic,"message",{configurable:true,get(){
                state.events.push("message get");
                globalThis.console = {warn(){throw Error("late console");}};
                return {[Symbol.toPrimitive](hint){state.events.push("coerce:"+hint);return "converted";}};
            }});
        }
        if (name === "yellow-value") {
            state.colored = {tag:"uncoerced"};
            Object.defineProperty(__mswChalk,"yellow",{configurable:true,value:function(value) {
                mswCheck(value === "Warning: detail","exact color argument");
                return state.colored;
            }});
        }
        if (name === "message-lifetime" || name === "retirement-fatal" || name === "retirement-cancel") {
            Object.defineProperty(state.diagnostic,"message",{configurable:true,get(){
                const holder=__mswHooks.make(0);
                holder[Symbol.toPrimitive]=function(){return "retired";};
                if (name === "retirement-fatal") __mswHooks.armFatal(0);
                if (name === "retirement-cancel") __mswHooks.armCancel(0);
                return holder;
            }});
            Object.defineProperty(__mswChalk,"yellow",{configurable:true,value:function(value){
                if (name !== "message-lifetime") __mswHooks.visit(1);
                mswCheck(__mswHooks.count(0) === 1,"message temporary retired before color call");
                state.events.push("message retired");return value;
            }});
        }
        if (name === "yellow-lifetime") {
            Object.defineProperty(__mswChalk,"yellow",{configurable:true,get(){
                const holder=__mswHooks.make(0);
                return function(value){mswCheck(Boolean(holder),"live color closure");return value;};
            }});
            output.warn=function(){
                mswCheck(__mswHooks.count(0) === 1,"color callable retired before outer warn");
                state.events.push("yellow retired");
            };
        }
        if (name === "head-lifetime") {
            // Keep no extra reference to the diagnostic; the iterator returns a
            // fresh native holder, while the wrapper owns its for-of binding.
            iterator.next=function(){
                state.events.push("next");
                if (this.step++ === 0) {
                    const holder=__mswHooks.make(0);holder.message="head";
                    return {done:false,value:holder};
                }
                mswCheck(__mswHooks.count(0) === 0,"head retained until terminal");
                return {done:true};
            };
        }
        if (name === "current-fatal") Object.defineProperty(state.diagnostic,"message",{
            configurable:true,get(){return __mswHooks.raiseNativeFatal();}
        });
        if (name === "pending-reason") Object.defineProperty(state.diagnostic,"message",{
            configurable:true,get(){return __mswPending();}
        });
        if (name === "deleted-console") delete globalThis.console;
        if (name === "lexical-console") {
            // Fixture setup evaluates a global lexical declaration before call.
            state.lexicalConsole={warn(value){state.events.push("lexical warn");state.warnings.push(value);}};
            globalThis.console={warn(){throw Error("global object shadow used");}};
        }
    }
    if (name === "warning-reentry") {
        let once=false;
        output.warn=function(value){
            state.warnings.push(value);
            if(!once){once=true;state.nested=__mswSubject([],state.runtime,state.options);}
        };
    }
}
async function mswObserve(name, subject) {
    const s=__mswState;
    if (name === "shape") {
        mswCheck(subject.name === "resolveModelScope" && subject.length === 3,"original async shape");
        mswCheck(Object.getPrototypeOf(subject) === Object.getPrototypeOf(async function(){}),"genuine AsyncFunction");
        mswCheck(!Object.hasOwn(subject,"prototype"),"async is nonconstructor");
    }
    if (name === "capture-import")
        __mswResolver.resolveModelScopeWithDiagnostics=function(){throw Error("late resolver read");};
    let result, caught;
    try {
        const pending=subject(s.patterns,s.runtime,s.options);
        mswCheck(pending instanceof Promise,"actual promise result");
        if (name === "deferred") {
            mswCheck(s.events.join() === "available" && s.warnings.length === 0,"suspends before warnings");
            s.events.push("before resume");s.resume([]);
        }
        result=await pending;
    } catch(error){caught=error;}
    if (name === "boxed-once") {
        delete Number.prototype.scopedModels;delete Number.prototype.diagnostics;
        mswCheck(s.receivers.length===2 && s.receivers[0]===s.receivers[1] &&
            typeof s.receivers[0]==="object","destructuring boxes exactly once");
    }
    const sameReason=["rejected","actual-data","getter-throw","diagnostics-throw","next-throw",
        "done-throw","value-throw","warn-throw","close-throw","pending-reason"].includes(name);
    const typeReason=["null-result","missing-diagnostics","message-symbol"].includes(name);
    if(sameReason) {
        mswCheck(caught===s.reason,"original thrown identity");
        if(name==="actual-data") mswCheck(__mswHooks.isUnmarkedPrivateData(caught),"native DATA remains ordinary");
    } else if(typeReason) mswCheck(caught instanceof TypeError,"ordinary TypeError");
    else if(name==="deleted-console" || name==="console-tdz") mswCheck(caught instanceof ReferenceError,"missing identifier ReferenceError");
    else if(caught) throw caught;
    if(["next-throw","done-throw","value-throw"].includes(name))
        mswCheck(!s.events.includes("close"),"iterator step failure has no close");
    if(["warn-throw","close-throw","message-symbol","pending-reason","deleted-console","console-tdz"].includes(name))
        mswCheck(s.events.filter(x=>x==="close").length===1,"body throw closes iterator once");
    if(name==="empty") mswCheck(result.length===0 && s.warnings.length===0,"empty scope");
    if(["shape","match","options","capture-import"].includes(name))
        mswCheck(result.length===1 && result[0].model===s.model,"actual model identity");
    if(name==="missing" || name==="deferred")
        mswCheck(result.length===0 && s.warnings[0]==='Warning: No models match pattern "absent"',"exact missing warning");
    if(name==="colored")
        mswCheck(s.warnings[0]==='\u001b[33mWarning: No models match pattern "absent"\u001b[39m',"real Chalk color output");
    if(name==="ambiguous")
        mswCheck(result.length===2 && s.warnings.length===1 &&
            s.warnings[0]==='Warning: Pattern "shared" matches several providers: alpha, zeta. Use provider/id to choose one.',
            "actual ambiguity ordering");
    if(s.controlled && !sameReason && !typeReason && name!=="deleted-console" && name!=="console-tdz" && name!=="return-thenable")
        mswCheck(result===s.scoped,"return scoped object identity");
    if(name==="return-thenable") mswCheck(result===s.final,"async return adopts thenable");
    if(name==="yellow-value") mswCheck(s.warnings[0]===s.colored,"console receives exact color result");
    if(name==="head-lifetime") mswCheck(__mswHooks.count(0)===1,"head retires after terminal");
    if(name==="result-order") mswCheck(s.events.join()==="resolve,scoped,diagnostics","result property order");
    if(name==="getter-throw") mswCheck(s.events.join()==="resolve,scoped","first getter failure stops second");
    if(name==="console-order")
        mswCheck(s.events.join()==="resolve,iterator,next,warn get,yellow get,message get,coerce:string,yellow call,old warn,next",
            "nested expression reference order");
    if(name==="warning-reentry") {
        await s.nested;mswCheck(s.warnings.length===1,"reentrant wrapper does not alias state");
    }
    return {events:s.events,warnings:s.warnings.map(value=>typeof value==="object"?"object":value),
        caught:sameReason?"original":caught?caught.name:null,
        result:s.controlled?"identity":result?result.length:null};
}
async function mswFatal(subject) {
    const s=__mswState;
    try { await subject(s.patterns,s.runtime,s.options); }
    catch(error) { __mswHooks.visit(2);throw error; }
    __mswHooks.visit(3);
}
