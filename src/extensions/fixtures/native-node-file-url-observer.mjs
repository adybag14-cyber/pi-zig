// Observers shared verbatim by genuine Node 24.13.0 and the selected native
// internal/url owner. Private-class access is an explicit test-only projection.
"use strict";
function urlPathAssert(value, label) { if (!value) throw Error(label); }
function urlPathEqual(value, expected, label) {
    urlPathAssert(JSON.stringify(value) === JSON.stringify(expected), label);
}
function urlPathThrown(call) { try { call(); } catch (reason) { return reason; } }
function urlPathError(reason, code) {
    urlPathAssert(reason instanceof TypeError && reason.code === code, "actual " + code + " family");
}
function urlStructural(pathname, hostname = "") {
    return { href: "file://selected", protocol: "file:", hostname, pathname };
}
function observeUrlStructure(api) {
    const trace = [];
    const subject = {
        get href() { trace.push("href"); return {}; },
        get protocol() { trace.push("protocol"); return "file:"; },
        get auth() { trace.push("auth"); return undefined; },
        get path() { trace.push("path"); return undefined; }
    };
    urlPathAssert(api.isURL(subject) === true, "structural URL predicate");
    urlPathEqual(trace, ["href", "protocol", "auth", "path"], "four ordered structural reads");
    for (const field of ["href", "protocol", "auth", "path"]) {
        const visits = [];
        const target = {};
        for (const name of ["href", "protocol", "auth", "path"]) {
            Object.defineProperty(target, name, {get() {
                visits.push(name);
                if (name === field) return name === "auth" || name === "path" ? null : 0;
                return name === "auth" || name === "path" ? undefined : "present";
            }});
        }
        urlPathAssert(api.isURL(target) === false, "structural short circuit at " + field);
        urlPathEqual(visits, ["href", "protocol", "auth", "path"].slice(0, ["href", "protocol", "auth", "path"].indexOf(field) + 1),
            "no later structural getter");
    }
    for (const value of [null, undefined, false, 0, "", 1n]) urlPathAssert(api.isURL(value) === false, "nullish and ordinary primitive predicate");
}
function observeUrlIdentity(api) {
    for (const value of [undefined, null, false, 0, "", "file:///C:/literal", {}, [], new Uint8Array([1]), Symbol("path")]) {
        urlPathAssert(api.toPathIfFileURL(value) === value, "non URL keeps exact identity");
    }
    const first = {};
    const input = {get href() { throw first; }};
    urlPathAssert(urlPathThrown(() => api.toPathIfFileURL(input)) === first, "predicate throw identity");
}
function observeUrlReadOrder(api) {
    const trace = [];
    const input = {
        get href() { trace.push("href"); return "file://selected"; },
        get protocol() { trace.push("protocol"); return "file:"; },
        get auth() { trace.push("auth"); return undefined; },
        get path() { trace.push("path"); return undefined; },
        get hostname() { trace.push("hostname"); return ""; },
        get pathname() { trace.push("pathname"); return "/selected"; }
    };
    const options = {get windows() { trace.push("windows"); return false; }};
    urlPathAssert(api.fileURLToPath(input, options) === "/selected", "selected POSIX body");
    urlPathEqual(trace, ["windows", "href", "protocol", "auth", "path", "protocol", "hostname", "pathname"],
        "options first and repeated protocol read");
    const token = {};
    let touched = false;
    urlPathAssert(urlPathThrown(() => api.fileURLToPath({get href() { touched = true; }}, {get windows() { throw token; }})) === token && !touched,
        "options failure precedes path inspection");
}
function observeUrlRepeatedGate(api) {
    const trace = [];
    const input = {};
    for (const name of ["href", "protocol", "auth", "path", "hostname", "pathname"]) {
        Object.defineProperty(input, name, {get() {
            trace.push(name);
            return ({href:"file://selected", protocol:"file:", hostname:"", pathname:"/C:/selected"})[name];
        }});
    }
    const result = api.toPathIfFileURL(input);
    urlPathAssert(result === (api.platform === "win32" ? "C:\\selected" : "/C:/selected"), "actual platform default");
    urlPathEqual(trace, ["href", "protocol", "auth", "path", "href", "protocol", "auth", "path", "protocol", "hostname", "pathname"],
        "toPath predicate and actual fileURL predicate are separate");
}
function observeUrlWindowsChoice(api) {
    const input = urlStructural("/C:/selected");
    for (const options of [undefined, null, {}, {windows:undefined}, {windows:null}]) {
        const expected = api.platform === "win32" ? "C:\\selected" : "/C:/selected";
        urlPathAssert(api.fileURLToPath(input, options) === expected, "nullish option uses captured platform");
    }
    urlPathAssert(api.fileURLToPath(input, {windows:false}) === "/C:/selected", "false option selects POSIX");
    const truthy = {valueOf() { throw Error("truthiness coerced"); }, [Symbol.toPrimitive]() { throw Error("truthiness coerced"); }};
    urlPathAssert(api.fileURLToPath(input, {windows:truthy}) === "C:\\selected", "truthy object selects Windows without coercion");
    const before = Object.getOwnPropertyDescriptor(Boolean.prototype, "windows");
    Object.defineProperty(Boolean.prototype, "windows", {configurable:true, get() { return false; }});
    try { urlPathAssert(api.fileURLToPath(input, true) === "/C:/selected", "primitive option boxes for live member"); }
    finally { if (before) Object.defineProperty(Boolean.prototype, "windows", before); else delete Boolean.prototype.windows; }
}
function observeUrlCapturedIntrinsics(api) {
    const beforeURL = Object.getOwnPropertyDescriptor(globalThis, "URL");
    const beforeDecode = Object.getOwnPropertyDescriptor(globalThis, "decodeURIComponent");
    const existing = new api.URL("file:///C:/dir/a%20b?query#fragment");
    Object.defineProperty(globalThis, "URL", {configurable:true, get() { throw Error("late global URL lookup"); }});
    Object.defineProperty(globalThis, "decodeURIComponent", {configurable:true, get() { throw Error("late decoder lookup"); }});
    try {
        urlPathAssert(api.fileURLToPath("file:///C:/dir/a%20b?query#fragment", {windows:true}) === "C:\\dir\\a b", "captured URL constructor and decoder");
        urlPathAssert(api.fileURLToPath(existing, {windows:false}) === "/C:/dir/a b", "genuine URL ignores search and fragment");
    } finally {
        Object.defineProperty(globalThis, "URL", beforeURL);
        Object.defineProperty(globalThis, "decodeURIComponent", beforeDecode);
    }
}
function observeUrlFailures(api) {
    urlPathError(urlPathThrown(() => api.fileURLToPath(7)), "ERR_INVALID_ARG_TYPE");
    const scheme = urlPathThrown(() => api.fileURLToPath({href:"selected", protocol:"https:"}, {windows:false}));
    urlPathError(scheme, "ERR_INVALID_URL_SCHEME");
    urlPathAssert(scheme.message === "The URL must be of scheme file", "genuine scheme message");
    let pathnameReads = 0;
    const host = urlPathThrown(() => api.fileURLToPath({href:"selected", protocol:"file:", hostname:"remote",
        get pathname() { pathnameReads++; return "/unused"; }}, {windows:false}));
    urlPathError(host, "ERR_INVALID_FILE_URL_HOST");
    urlPathAssert(host.message === 'File URL host must be "localhost" or empty on ' + api.platform && pathnameReads === 0,
        "actual host message precedes pathname");
    const absoluteInput = urlStructural("/relative");
    const absolute = urlPathThrown(() => api.fileURLToPath(absoluteInput, {windows:true}));
    urlPathError(absolute, "ERR_INVALID_FILE_URL_PATH");
    urlPathAssert(absolute.input === absoluteInput && absolute.message === "File URL path must be absolute", "actual input assignment and path message");
}
function observeUrlEncodedSeparators(api) {
    for (const spelling of ["%2f", "%2F", "%5c", "%5C"]) {
        const input = urlStructural("/C:/before" + spelling + "after");
        const error = urlPathThrown(() => api.fileURLToPath(input, {windows:true}));
        urlPathError(error, "ERR_INVALID_FILE_URL_PATH");
        urlPathAssert(error.input === input && error.message === "File URL path must not include encoded \\ or / characters", "Windows encoded separator diagnostic");
    }
    urlPathAssert(api.fileURLToPath(urlStructural("/before%5cafter"), {windows:false}) === "/before\\after", "POSIX encoded backslash remains allowed");
    for (const spelling of ["%2f", "%2F"]) {
        const input = urlStructural("/before" + spelling + "after");
        const error = urlPathThrown(() => api.fileURLToPath(input, {windows:false}));
        urlPathError(error, "ERR_INVALID_FILE_URL_PATH");
        urlPathAssert(error.input === input && error.message === "File URL path must not include encoded / characters", "POSIX encoded slash diagnostic");
    }
    const malformed = urlPathThrown(() => api.fileURLToPath(urlStructural("/C:/bad%zz"), {windows:true}));
    urlPathAssert(malformed instanceof URIError && malformed.code === undefined, "actual decoder rejects after the separator scan");
    const separatorFirst = urlPathThrown(() => api.fileURLToPath(urlStructural("/C:/bad%zz%2f"), {windows:true}));
    urlPathError(separatorFirst, "ERR_INVALID_FILE_URL_PATH");
}
function observeUrlUNC(api) {
    urlPathAssert(api.fileURLToPath(urlStructural("/share/a%20b", "xn--bcher-kva.example"), {windows:true}) === "\\\\bücher.example\\share\\a b",
        "actual domain decoder in UNC path");
    urlPathAssert(api.fileURLToPath(urlStructural("/share/a", "[::1]"), {windows:true}) === "\\\\[::1]\\share\\a",
        "actual IPv6 hostname in UNC path");
    urlPathAssert(api.fileURLToPath(urlStructural("/share/a", ""), {windows:false}) === "/share/a", "POSIX complete path");
}
function observeUrlPrivateRegex(api) {
    const trace = [];
    const path = {length:0, [Symbol.toPrimitive](hint) { trace.push(hint); return "/C:/private/leaf"; }};
    const originalRegExp = globalThis.RegExp;
    const exec = Object.getOwnPropertyDescriptor(originalRegExp.prototype, "exec");
    const replace = Object.getOwnPropertyDescriptor(originalRegExp.prototype, Symbol.replace);
    const ctor = Object.getOwnPropertyDescriptor(globalThis, "RegExp");
    Object.defineProperty(originalRegExp.prototype, "exec", {configurable:true, get() { throw Error("main realm exec used"); }});
    Object.defineProperty(originalRegExp.prototype, Symbol.replace, {configurable:true, get() { throw Error("main realm replace used"); }});
    Object.defineProperty(globalThis, "RegExp", {configurable:true, get() { throw Error("late main constructor used"); }});
    try {
        urlPathAssert(api.fileURLToPath(urlStructural(path), {windows:true}) === "C:\\private\\leaf", "actual private realm RegExp replacement");
        urlPathEqual(trace, ["string"], "private replacement performs actual string hint conversion once");
    } finally {
        Object.defineProperty(globalThis, "RegExp", ctor);
        Object.defineProperty(originalRegExp.prototype, Symbol.replace, replace);
        Object.defineProperty(originalRegExp.prototype, "exec", exec);
    }
}
function observeUrlSymbolAndShapes(api) {
    for (const [name,length] of [["isURL",1],["fileURLToPath",1],["toPathIfFileURL",1]]) {
        urlPathAssert(typeof api[name] === "function" && api[name].name === name && api[name].length === length &&
            Object.hasOwn(api[name], "prototype"), "actual ordinary function " + name);
    }
    const names = ["href","protocol","auth","path","hostname","pathname"];
    const saved = names.map(name => Object.getOwnPropertyDescriptor(Symbol.prototype, name));
    const trace = [];
    for (const name of names) Object.defineProperty(Symbol.prototype, name, {configurable:true, get() {
        trace.push(name); return ({href:"selected",protocol:"file:",hostname:"",pathname:"/symbol"})[name];
    }});
    try {
        urlPathAssert(api.fileURLToPath(Symbol("selected"), {windows:false}) === "/symbol", "structural Symbol is not excluded by a brand guard");
        urlPathEqual(trace, ["href","protocol","auth","path","protocol","hostname","pathname"], "boxed primitive repeated member reads");
    } finally {
        names.forEach((name,index) => { if (saved[index]) Object.defineProperty(Symbol.prototype, name, saved[index]); else delete Symbol.prototype[name]; });
    }
}
function observeUrlHostClass(api) {
    const Host = api.errors.ERR_INVALID_FILE_URL_HOST;
    const inspect = api.inspectModule;
    const format = Object.getOwnPropertyDescriptor(inspect, "format");
    const superclass = Object.getPrototypeOf(Host);
    const unshift = Object.getOwnPropertyDescriptor(Array.prototype, "unshift");
    const trace = [];
    function Alternate(message) { trace.push(["base", message, new.target === Host]); this.message = message; }
    class Sub extends Host {}
    Object.defineProperty(inspect, "format", {configurable:true, get() {
        trace.push("format getter");
        Object.setPrototypeOf(Host, Alternate);
        return function(...args) {
            urlPathAssert(this === null, "formatter actual null receiver");
            trace.push(args);
            return "chosen formatted message";
        };
    }});
    Object.defineProperty(Array.prototype, "unshift", {configurable:true, get() { throw Error("late primordial unshift lookup"); }});
    try {
        const first = Reflect.construct(Host, ["platform"], Sub);
        urlPathAssert(first instanceof Sub && first instanceof TypeError && first.code === "ERR_INVALID_FILE_URL_HOST" &&
            first.message === "chosen formatted message", "actual new.target and preselected lexical superclass");
        urlPathEqual(trace, ["format getter", ['File URL host must be "localhost" or empty on %s',"platform']], "real rest was unshifted before formatter");
        trace.length = 0;
        const second = new Host("again");
        urlPathAssert(second.code === "ERR_INVALID_FILE_URL_HOST" && second.message === "chosen formatted message", "next call uses live superclass");
        urlPathEqual(trace, ["format getter", ['File URL host must be "localhost" or empty on %s',"again"], ["base","chosen formatted message",true]], "later superclass selection");
        trace.length = 0;
        const countError = urlPathThrown(() => new Host());
        urlPathAssert(countError !== undefined && trace.length === 0, "argument assertion precedes formatter and superclass call");
    } finally {
        Object.setPrototypeOf(Host, superclass);
        Object.defineProperty(inspect, "format", format);
        Object.defineProperty(Array.prototype, "unshift", unshift);
    }
}
function observeUrlFunctionMessages(api) {
    const trace = [];
    const expected = {
        get length() { trace.push("length"); return 2; },
        get 0() { trace.push("first"); return {[Symbol.toPrimitive](hint) { trace.push("first:" + hint); return "alpha"; }}; },
        get 1() { trace.push("second"); return {[Symbol.toPrimitive](hint) { trace.push("second:" + hint); return "beta"; }}; }
    };
    const scheme = new api.errors.ERR_INVALID_URL_SCHEME(expected);
    urlPathAssert(scheme.message === "The URL must be one of scheme alpha or beta", "actual two-scheme message");
    urlPathEqual(trace, ["length","length","first","first:string","second","second:string"], "length rereads and eager indexed conversions");
    trace.length = 0;
    const input = {};
    class Path extends api.errors.ERR_INVALID_FILE_URL_PATH {
        set input(value) { trace.push(["input", value === input]); }
    }
    const path = new Path({[Symbol.toPrimitive](hint) { trace.push("reason:" + hint); return "selected"; }}, input);
    urlPathAssert(path.code === "ERR_INVALID_FILE_URL_PATH" && path.message === "File URL path selected", "actual function-message family");
    urlPathEqual(trace, [["input",true],"reason:string"], "ordinary input Set precedes reason conversion");
}
