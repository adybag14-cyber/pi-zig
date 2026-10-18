// Causal observers for the exact c268 Session helpers. They invoke each real
// Source/native subject in its own realm and use native sole-holder finalizers.
function sessionAssert(value, message) { if (!value) throw Error(message); }
function observeSessionProjection(api) {
    const timestamp = "2025-01-02T03:04:05.000Z";
    const rows = [
        { id: "s", parentId: null, type: "message", message: { role: "system", content: null } },
        { id: "t", parentId: "s", type: "thinking_level_change", thinkingLevel: "low" },
        { id: "m", parentId: "t", type: "model_change", provider: "old-provider", modelId: "old-model" },
        { id: "u", parentId: "m", type: "message", message: { role: "user", content: null, retained: 1 } },
        { id: "a", parentId: "u", type: "message", message: { role: "assistant", content: [], provider: "new-provider", model: "new-model" } },
        { id: "c", parentId: "a", type: "compaction", firstKeptEntryId: "u", summary: "checkpoint", tokensBefore: 99, timestamp },
        { id: "x", parentId: "c", type: "custom_message", customType: "status", content: null, display: true, details: { actual: 1 }, timestamp },
        { id: "b", parentId: "x", type: "branch_summary", summary: "branch", fromId: "elsewhere", timestamp },
        { id: "e", parentId: "b", type: "context_edit", targetId: "a", replacement: { content: "edited" } },
    ];
    const context = api.buildContextEntries(rows);
    sessionAssert(context.map(e => e.id).join() === "c,u,a,x,b,e", "compaction kept path");
    const result = api.buildSessionProjection(rows);
    sessionAssert(result.entries.length === 6 && result.messages.length === 5, "actual projected shape");
    for (let i = 0; i < context.length; i++) sessionAssert(result.entries[i].sourceEntry === context[i], "provenance identity");
    sessionAssert(result.messages[0].role === "compactionSummary" && result.messages[0].summary === "checkpoint" && result.messages[0].timestamp === 1735787045000, "real summary and Date");
    sessionAssert(Array.isArray(result.messages[1].content) && result.messages[1].content.length === 0 && result.messages[1].retained === 1, "repair missing user content");
    sessionAssert(result.messages[2].content[0].type === "text" && result.messages[2].content[0].text === "edited" && result.messages[2] !== rows[4].message, "actual context edit");
    sessionAssert(result.messages[3].role === "custom" && result.messages[3].details === rows[6].details && result.messages[3].content.length === 0, "actual custom message");
    sessionAssert(result.messages[4].role === "branchSummary" && result.messages[4].fromId === "elsewhere", "actual branch message");
    sessionAssert(result.thinkingLevel === "low" && result.model.provider === "new-provider" && result.model.modelId === "new-model", "settings follow full path");
    const finished = api.buildSessionContext(rows);
    sessionAssert(Object.keys(finished).join() === "messages,thinkingLevel,model" && finished.messages.length === 5, "canonical final context");
    rows[8].replacement = null;
    sessionAssert(api.buildSessionProjection(rows).messages.length === 4, "null edit suppresses messages");
    const token = { role: "assistant", content: "kept" };
    sessionAssert(api.sessionEntryToContextMessages({ type: "message", message: token })[0] === token, "unmodified message identity");
    sessionAssert(api.sessionEntryToContextMessages(rows[0])[0].content === "", "system repair");
    sessionAssert(api.sessionEntryToContextMessages({ type: "custom", data: 1 }).length === 0, "display entry excluded");
    const old = { id: "old", type: "compaction", parentId: null, summary: "old", timestamp };
    const newest = { id: "new", type: "compaction", parentId: "old", firstKeptEntryId: "old", summary: "new", timestamp };
    const nested = api.buildSessionProjection([old, newest]);
    sessionAssert(nested.entries.length === 2 && nested.entries[1].sourceEntry === old && nested.entries[1].messages.length === 0 && nested.messages.length === 1, "older retained compaction contributes no duplicate summary");
}
function observeSessionPath(api) {
    const originalMap = globalThis.Map;
    let constructions = 0, iterations = 0, setReads = 0, ids = 0, setCalls = 0;
    const row = { get id() { ids++; return "id"; } };
    const entries = { [Symbol.iterator]() { iterations++; let next = 0; return { next() { return next++ ? { done: true } : { value: row, done: false }; } }; } };
    globalThis.Map = function () {
        constructions++;
        return { get set() { setReads++; return function (id, value) { sessionAssert(this !== undefined && id === "id" && value === row, "real Map set receiver"); setCalls++; }; } };
    };
    try {
        sessionAssert(api.buildContextEntries(entries, null).length === 0, "null leaf path");
        sessionAssert(constructions === 1 && iterations === 1 && setReads === 1 && ids === 1 && setCalls === 1, "build index before null leaf");
    } finally { globalThis.Map = originalMap; }
    const root = { id: "root", type: "custom", parentId: null };
    let parents = 0, indexGets = 0;
    const leaf = { id: "leaf", type: "custom", get parentId() { parents++; return "root"; } };
    const byId = { get(id) { sessionAssert(this === byId, "supplied map receiver"); indexGets++; return id === "root" ? root : leaf; } };
    const unreachable = { get [Symbol.iterator]() { throw Error("supplied index rebuilt"); } };
    const path = api.buildContextEntries(unreachable, "leaf", byId);
    sessionAssert(path[0] === root && path[1] === leaf && parents === 2 && indexGets === 2, "repeated parent getter and real map");
    let fallback = 0;
    const missing = { get() { return undefined; } };
    const selected = { length: 1, get 0() { fallback++; return root; } };
    sessionAssert(api.buildContextEntries(selected, "missing", missing)[0] === root && fallback === 1, "missing leaf falls back to last entry");
}
function observeSessionLatest(api, h) {
    let calls = 0;
    const returned = {};
    const entries = {
        get length() {
            return Object.assign(h.make(0), { [Symbol.toPrimitive]() { return 1; } });
        },
        get 0() {
            calls++;
            sessionAssert(h.count(0) === 1, "length temporary retires before index");
            if (calls === 1) return Object.assign(h.make(1), { type: "compaction" });
            sessionAssert(h.count(1) === 1, "comparison entry retires before return getter");
            return returned;
        },
    };
    sessionAssert(api.getLatestCompactionEntry(entries) === returned && calls === 2, "latest rereads actual index");
    sessionAssert(api.getLatestCompactionEntry([]) === null, "empty latest");
}
function observeSessionParse(api) {
    const parse = JSON.parse, push = Array.prototype.push;
    const log = [];
    let parses = 0, pushes = 0;
    const add = value => { log[log.length] = value; };
    const first = { trim() { add("line:first"); return true; } };
    const second = { trim() { add("line:second"); return true; } };
    const third = { trim() { add("line:third"); return ""; } };
    const content = { trim() { add("outer:trim"); return { split(separator) { sessionAssert(separator === "\n", "split delimiter"); add("split"); return [first, second, third]; } }; } };
    JSON.parse = function (line) { sessionAssert(this === JSON, "JSON.parse receiver"); add("parse"); parses++; return line === first ? 10 : 20; };
    Array.prototype.push = function (entry) {
        add("push"); pushes++;
        if (entry === 10) throw Error("push is inside Source catch");
        return Reflect.apply(push, this, [entry]);
    };
    let result;
    try { result = api.parseSessionEntries(content); }
    finally { JSON.parse = parse; Array.prototype.push = push; }
    sessionAssert(parses === 2 && pushes === 2 && result.length === 1 && result[0] === 20, "live parser with swallowed ordinary push error");
    sessionAssert(log.join() === "outer:trim,split,line:first,parse,push,line:second,parse,push,line:third", "live parser expression order");
}
function observeSessionParseLocals(api, h) {
    const parse = JSON.parse, push = Array.prototype.push;
    let next = 0;
    const lines = {
        [Symbol.iterator]() { return this; },
        next() {
            next++;
            if (next === 1) return { done: false, value: Object.assign(h.make(0), { trim() { return "nonempty"; } }) };
            sessionAssert(h.count(1) === 0, "try entry survives blank line and final done");
            if (next === 2) {
                sessionAssert(h.count(0) === 0, "previous line survives next");
                return { done: false, value: Object.assign(h.make(2), { trim() { sessionAssert(h.count(0) === 1, "head assigned before trim"); return ""; } }) };
            }
            sessionAssert(h.count(2) === 0, "final line survives done");
            return { done: true };
        },
    };
    const content = { trim() { return { split() { return lines; } }; } };
    JSON.parse = function () { return h.make(1); };
    Array.prototype.push = function () { return 0; }; // The actual Source entries local cannot retain the parsed carrier.
    try { sessionAssert(api.parseSessionEntries(content).length === 0, "observed parse result"); }
    finally { JSON.parse = parse; Array.prototype.push = push; }
    sessionAssert(next === 3 && h.count(0) === 1 && h.count(1) === 1 && h.count(2) === 1, "all final lexical owners retire at function return");
}
function observeSessionCompactionHead(api, h) {
    const iterator = Array.prototype[Symbol.iterator], find = Array.prototype.findIndex;
    const root = { id: "root", parentId: null, type: "custom" };
    const map = { get() { return root; } };
    let step = 0, findCalls = 0;
    Array.prototype[Symbol.iterator] = function () {
        return { next() {
            step++;
            if (step === 1) return { done: false, value: { id: "c", type: "compaction" } };
            if (step === 2) return { done: false, value: Object.assign(h.make(0), { type: "custom" }) };
            sessionAssert(h.count(0) === 0, "final scan head survives done");
            return { done: true };
        } };
    };
    Array.prototype.findIndex = function () { findCalls++; sessionAssert(h.count(0) === 0, "final scan head survives next statement"); return -1; };
    try { sessionAssert(api.buildContextEntries([], "root", map)[0] === root, "original path returned after missing compaction"); }
    finally { Array.prototype[Symbol.iterator] = iterator; Array.prototype.findIndex = find; }
    sessionAssert(step === 3 && findCalls === 1 && h.count(0) === 1, "scan head retires at return");
}
function sessionContextBodySetup(api, h, fatal) {
    const find = Array.prototype.findIndex;
    const compaction = { id: "c", parentId: null, type: "compaction", firstKeptEntryId: "kept" };
    const byId = { get() { return compaction; } };
    let comparisons = 0, firstReads = 0, secondReads = 0, sliceReads = 0;
    const cut = { [Symbol.toPrimitive](hint) {
        comparisons++;
        if (comparisons >= 3) sessionAssert(h.count(0) === 0, "body local survives condition or following expression");
        return fatal ? 2 : 1;
    } };
    Array.prototype.findIndex = function () {
        Object.defineProperty(this, "0", { configurable: true, get() {
            firstReads++;
            if (fatal) h.armFatal(0);
            return Object.assign(h.make(0), { id: "kept", type: "message", message: { role: "system" } });
        } });
        Object.defineProperty(this, "1", { configurable: true, get() { secondReads++; h.visit(2); throw Error("next index reached after fatal reset"); } });
        Object.defineProperty(this, "slice", { configurable: true, get() {
            sliceReads++;
            sessionAssert(h.count(0) === 0, "final body local survives slice getter");
            return function (start) { sessionAssert(start === 2, "actual compactionIdx addition"); return []; };
        } });
        return cut;
    };
    try {
        const result = api.buildContextEntries([], "c", byId);
        sessionAssert(!fatal && result.length === 1 && result[0] === compaction, "system entry excluded");
    } finally { Array.prototype.findIndex = find; }
    sessionAssert(firstReads === 1 && secondReads === 0 && sliceReads === 1 && comparisons === 4 && h.count(0) === 1, "body survives false condition and post-loop expression");
}
function observeSessionContextBody(api, h) { sessionContextBodySetup(api, h, false); }
function observeSessionContextFatal(api, h) { sessionContextBodySetup(api, h, true); }
function observeSessionMigration(api) {
    const OriginalSet = globalThis.Set, slice = String.prototype.slice;
    let uuidSlices = 0, has = 0, versionReads = 0, comparisons = 0, messageReads = 0;
    const assigned = [], original = { valueOf() { comparisons++; return 1; } };
    const header = { type: "session", get version() { versionReads++; return original; }, set version(value) { assigned[assigned.length] = value; } };
    const target = { role: "hookMessage", content: "unchanged" };
    const message = { type: "message", get message() { messageReads++; return messageReads === 1 ? {} : messageReads === 2 ? { role: "hookMessage" } : target; } };
    const compaction = { type: "compaction", firstKeptEntryIndex: 1 };
    const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    globalThis.Set = function () { return { has(id) { sessionAssert(this !== undefined && /^id[0-9]+$/.test(id), "actual Set.has receiver"); has++; return false; }, get add() { throw Error("Source does not add generated ids"); } }; };
    String.prototype.slice = function (start, end) { sessionAssert(start === 0 && end === 8 && pattern.test(this), "actual secure UUID binding"); return "id" + (++uuidSlices); };
    try { sessionAssert(api.migrateSessionEntries([header, message, compaction]) === undefined, "public migration returns void"); }
    finally { globalThis.Set = OriginalSet; String.prototype.slice = slice; }
    sessionAssert(versionReads === 1 && comparisons === 3 && assigned.join() === "2,3", "one version slot with three live comparisons and two passes");
    sessionAssert(uuidSlices === 2 && has === 2 && message.id === "id1" && message.parentId === null && compaction.id === "id2" && compaction.parentId === "id1", "sequential Source ids");
    sessionAssert(compaction.firstKeptEntryId === "id1" && !("firstKeptEntryIndex" in compaction), "v1 compaction migration");
    sessionAssert(messageReads === 3 && target.role === "custom", "v2 reads message three times");
}
function observeSessionMigrationCollisions(api) {
    const OriginalSet = globalThis.Set, slice = String.prototype.slice;
    let slices = 0, has = 0;
    const message = { type: "custom" };
    globalThis.Set = function () { return { has(value) { has++; sessionAssert(value === "collision", "collision key"); return true; } }; };
    String.prototype.slice = function () { slices++; return "collision"; };
    try { api.migrateSessionEntries([{ type: "session", version: 1 }, message]); }
    finally { globalThis.Set = OriginalSet; String.prototype.slice = slice; }
    sessionAssert(slices === 100 && has === 100 && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(message.id), "100 collisions then actual full UUID fallback");
}
function observeSessionMigrationDelete(api) {
    const header = { type: "session", version: 1 };
    const compaction = Object.defineProperty({ type: "compaction" }, "firstKeptEntryIndex", { value: 0, configurable: false });
    let next = 0, closes = 0;
    const entries = {
        0: header,
        find(callback) { return callback(header) ? header : undefined; },
        [Symbol.iterator]() { return { next() { return next++ === 0 ? { done: false, value: compaction } : { done: true }; }, return() { closes++; return {}; } }; },
    };
    let reason;
    try { api.migrateSessionEntries(entries); } catch (error) { reason = error; }
    sessionAssert(reason instanceof TypeError && closes === 1 && next === 1, "strict delete fails and actual iterator closes once");
}
function observeSessionComputedMigration(api, h) {
    const header = { type: "session", version: 1 }, target = { type: "custom", id: "old" };
    let fieldReads = 0, armed = false, lookupReads = 0;
    const compaction = {
        type: "compaction",
        get firstKeptEntryIndex() {
            fieldReads++;
            if (fieldReads === 1) return 1;
            return Object.assign(h.make(0), { [Symbol.toPrimitive](hint) { sessionAssert(hint === "string", "computed property key hint"); armed = true; return "1"; } });
        },
    };
    const entries = [header, target, compaction];
    Object.defineProperty(entries, "1", { configurable: true, get() {
        if (armed) { lookupReads++; sessionAssert(h.count(0) === 1, "computed operand retires before indexed getter"); armed = false; }
        return target;
    } });
    api.migrateSessionEntries(entries);
    sessionAssert(fieldReads === 2 && lookupReads === 1 && compaction.firstKeptEntryId === target.id && h.count(0) === 1, "actual repeated compaction key lookup");
}
function observeSessionParsePrivateData(api, h) {
    const parse = JSON.parse;
    let calls = 0, reason;
    JSON.parse = function () {
        calls++;
        if (calls === 1) { reason = h.freshPrivateData(); throw reason; }
        return 17;
    };
    let result;
    try { result = api.parseSessionEntries("first\nsecond"); }
    finally { JSON.parse = parse; }
    sessionAssert(calls === 2 && result.length === 1 && result[0] === 17 && h.isUnmarkedPrivateData(reason), "ordinary same-operation private DATA reaches Source empty catch");
}
function observeSessionParseCurrentFatal(api, h) {
    JSON.parse = function () {
        const reason = h.freshPrivateData();
        h.raiseNativeFatal();
        throw reason;
    };
    try { api.parseSessionEntries("first\nsecond"); }
    catch (reason) { h.visit(3); throw reason; }
    h.record.guestReached = true;
}
function observeSessionIteratorClose(api, h) {
    const OriginalMap = globalThis.Map;
    const original = {}, closeError = {};
    let step = 0, closes = 0;
    globalThis.Map = function () { return { set() { throw Error("id getter should run first"); } }; };
    const entries = { [Symbol.iterator]() { return {
        next() {
            step++;
            return { done: false, value: Object.defineProperty(h.make(0), "id", { get() { throw original; } }) };
        },
        get return() {
            sessionAssert(h.count(0) === 0, "abrupt head survives return getter");
            return function () { closes++; sessionAssert(h.count(0) === 0, "abrupt head survives return call"); throw closeError; };
        },
    }; } };
    let caught;
    try { api.buildContextEntries(entries, null); } catch (reason) { caught = reason; }
    finally { globalThis.Map = OriginalMap; }
    sessionAssert(caught === original && step === 1 && closes === 1 && h.count(0) === 1, "original throw wins IteratorClose and head retires at return");
}
function observeSessionCancellation(api, h) {
    globalThis.Map = function () { return { set() {} }; };
    let step = 0;
    const entries = { [Symbol.iterator]() { return {
        next() {
            step++;
            if (step === 1) { h.armCancel(0); return { done: false, value: Object.assign(h.make(0), { id: "first" }) }; }
            return { done: false, value: { get id() { h.visit(1); return "second"; } } };
        },
        return() { h.visit(2); return {}; },
    }; } };
    api.buildContextEntries(entries, null);
    throw Error("cancellation was swallowed");
}
