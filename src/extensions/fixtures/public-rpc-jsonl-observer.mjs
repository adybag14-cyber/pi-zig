// Caller-owned stream/method observers around the real JSONL functions and
// actual StringDecoder. Each comparison branch runs in a fresh Engine.
const JsonlObject = Object;
const JsonlJSON = JSON;
const JsonlError = Error;
const JsonlMap = Map;
function assert(value, message) { if (!value) throw new JsonlError(message); }
function observerStream(trace) {
    const handlers = new JsonlMap();
    const stream = {
        get on() {
            trace.push(["get-on"]);
            return function(event, handler) {
                trace.push(["on", this === stream, event, handler.name, handler.length, Object.hasOwn(handler, "prototype")]);
                handlers.set(event, handler);
                return this;
            };
        },
        get off() {
            trace.push(["get-off"]);
            return function(event, handler) {
                trace.push(["off", this === stream, event, handlers.get(event) === handler]);
                handlers.delete(event);
                return this;
            };
        },
    };
    return {stream, handlers};
}
export function observeJsonlFraming(subject) {
    const trace = [], lines = [];
    const {stream, handlers} = observerStream(trace);
    const detach = subject.attachJsonlLineReader(stream, line => lines.push(line));
    const data = handlers.get("data"), end = handlers.get("end");
    data.call(stream, '{"text":"A\u2028B\u2029C"}\n');
    data.call(stream, "first\r\n\nsecond");
    data.call(stream, "\r\n");
    data.call(stream, new Uint8Array([0xe2]));
    data.call(stream, new Uint8Array([0x82, 0xac, 0x0a, 0xe2, 0x82]));
    end.call(stream);
    end.call(stream);
    detach();
    assert(JsonlJSON.stringify(lines) === JsonlJSON.stringify(['{"text":"A\u2028B\u2029C"}', "first", "", "second", "€", "\ufffd"]), "Actual LF framing, CR stripping and decoder flush");
    assert(handlers.size === 0, "Both actual registered callbacks detached");
    const expected=[["get-on"],["on",true,"data","onData",1,false],["get-on"],["on",true,"end","onEnd",0,false],["get-off"],["off",true,"data",true],["get-off"],["off",true,"end",true]];
    assert(JsonlJSON.stringify(trace)===JsonlJSON.stringify(expected),"Actual stream getter, receiver, handler identity and arrow order");
    assert(detach.name===""&&detach.length===0&&!JsonlObject.hasOwn(detach,"prototype"),"Actual returned detach arrow");
    return {trace, lines, detachShape:[detach.name,detach.length,JsonlObject.hasOwn(detach,"prototype")]};
}
export function observeJsonlSerialize(subject) {
    const rows = [undefined, null, 7, true, "A\u2028B\u2029C", {a:1,b:["x\n",2]}].map(value => subject.serializeJsonLine(value));
    assert(rows[0] === "undefined\n" && rows[4] === '"A\u2028B\u2029C"\n', "Exact template result and LF-only serialization");
    let circular = {}; circular.self = circular;
    let failed = false;
    try { subject.serializeJsonLine(circular); } catch(error) { failed = error instanceof TypeError; }
    assert(failed, "Real JSON circular error");
    return rows;
}
export function observeJsonlReentry(subject) {
    const trace = [], lines = [];
    const {stream,handlers} = observerStream(trace);
    let entered = false;
    const detach = subject.attachJsonlLineReader(stream, line => {
        lines.push(line);
        if (!entered) { entered = true; handlers.get("data")("B\n"); }
    });
    handlers.get("data")("A\n");
    handlers.get("end")();
    detach();
    assert(JsonlJSON.stringify(lines)==='["A","A","B"]', "Reentry sees and mutates the same Source buffer cell");
    return {trace,lines};
}
export function observeJsonlCallbackFailure(subject) {
    const trace = [], lines = [];
    const {stream,handlers} = observerStream(trace);
    const reason = {};
    let failed = false;
    const detach = subject.attachJsonlLineReader(stream,line=>{
        lines.push(line);
        if (!failed) { failed=true; throw reason; }
    });
    let caught;
    try { handlers.get("data")("A\nB\n"); } catch(error) { caught=error; }
    assert(caught===reason,"onLine identity remains ordinary");
    handlers.get("data")("");
    detach();
    assert(JsonlJSON.stringify(lines)==='["A","A","B"]',"Throw skips the remaining-buffer assignment");
    return {trace,lines};
}
export function observeJsonlRegistrationFailure(subject) {
    const reason = {}, lines = [];
    let data, called=0;
    const stream={
        on(name,handler) {
            called++;
            if(name==="data") { data=handler; return this; }
            throw reason;
        },
        off(){throw new JsonlError("Source does not undo partial registration")},
    };
    let caught;
    try { subject.attachJsonlLineReader(stream,line=>lines.push(line)); } catch(error) { caught=error; }
    assert(caught===reason && called===2 && typeof data==="function","Actual second registration failure");
    data("still-live\n");
    assert(lines[0]==="still-live","Escaped callback cells close correctly on abrupt attach completion");
    return {called,lines};
}
export function observeJsonlNewlineSlot(subject) {
    const trace = [], lines = [];
    const {stream,handlers} = observerStream(trace);
    const detach=subject.attachJsonlLineReader(stream,line=>{
        lines.push(line);
        assert(jsonlHooks.count(0)===0,"Body const newlineIndex is live through emitLine");
    });
    const descriptor=JsonlObject.getOwnPropertyDescriptor(String.prototype,"indexOf");
    let calls=0;
    JsonlObject.defineProperty(String.prototype,"indexOf",{configurable:true,writable:true,value:function(needle){
        if(needle!=="\n")return descriptor.value.call(this,needle);
        if(++calls===1)return {holder:jsonlHooks.make(0),valueOf(){return 1}};
        assert(jsonlHooks.count(0)===1,"Next true body entry retires prior newlineIndex before indexOf");
        return -1;
    }});
    try { handlers.get("data")("X\nrest"); } finally { JsonlObject.defineProperty(String.prototype,"indexOf",descriptor); detach(); }
    assert(calls===2 && lines.length===1 && lines[0]==="X","Both actual loop entries executed");
    return {calls,lines,retired:jsonlHooks.count(0)};
}
export function observeJsonlSerializeRetirement(subject) {
    const saved=JsonlObject.getOwnPropertyDescriptor(globalThis,"JSON");
    let visited=false;
    JsonlObject.defineProperty(globalThis,"JSON",{configurable:true,get(){
        const receiver={holder:jsonlHooks.make(0),get stringify(){
            const callable=function(){
                return {[Symbol.toPrimitive](hint){
                    assert(hint==="string" && jsonlHooks.count(0)===1 && jsonlHooks.count(1)===1,"JSON receiver and callable retire before template coercion");
                    visited=true; return "controlled";
                }};
            };
            callable.prototype=null;callable.holder=jsonlHooks.make(1);return callable;
        }};
        return receiver;
    }});
    let line;
    try { line=subject.serializeJsonLine({}); } finally { JsonlObject.defineProperty(globalThis,"JSON",saved); }
    assert(visited && line==="controlled\n","Actual nested stringify result");
    return {visited,line,retired:[jsonlHooks.count(0),jsonlHooks.count(1)]};
}
export function observeJsonlPrivateData(subject) {
    let reason,caught;
    const stream={get on(){reason=jsonlHooks.freshPrivateData();throw reason}};
    try { subject.attachJsonlLineReader(stream,()=>{}); } catch(error) { caught=error; }
    assert(reason===caught && jsonlHooks.isUnmarkedPrivateData(reason),"Same getter-created DATA is ordinary");
    return true;
}
