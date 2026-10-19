// Actual selected color observers; each function runs in a fresh realm.
function colorAssert(value, message) { if (!value) throw new Error(message); }
const originalColorPairs = [["reset",0,0],["bold",1,22],["dim",2,22],["italic",3,23],["underline",4,24],["blink",5,25],["inverse",7,27],["hidden",8,28],["strikethrough",9,29],["doubleunderline",21,24],["black",30,39],["red",31,39],["green",32,39],["yellow",33,39],["blue",34,39],["magenta",35,39],["cyan",36,39],["white",37,39],["bgBlack",40,49],["bgRed",41,49],["bgGreen",42,49],["bgYellow",43,49],["bgBlue",44,49],["bgMagenta",45,49],["bgCyan",46,49],["bgWhite",47,49],["framed",51,54],["overlined",53,55],["gray",90,39],["redBright",91,39],["greenBright",92,39],["yellowBright",93,39],["blueBright",94,39],["magentaBright",95,39],["cyanBright",96,39],["whiteBright",97,39],["bgGray",100,49],["bgRedBright",101,49],["bgGreenBright",102,49],["bgYellowBright",103,49],["bgBlueBright",104,49],["bgMagentaBright",105,49],["bgCyanBright",106,49],["bgWhiteBright",107,49]];
const originalColorAliases = [["gray","grey"],["gray","blackBright"],["bgGray","bgGrey"],["bgGray","bgBlackBright"],["dim","faint"],["strikethrough","crossedout"],["strikethrough","strikeThrough"],["strikethrough","crossedOut"],["hidden","conceal"],["inverse","swapColors"],["inverse","swapcolors"],["doubleunderline","doubleUnderline"]];
function observeColorTables(inspect, stylize) {
    colorAssert(stylize.name === "stylizeWithColor" && stylize.length === 2 &&
        Object.hasOwn(stylize, "prototype") && stylize.prototype.constructor === stylize,
        "original stylizer function shape");
    colorAssert(Object.getPrototypeOf(inspect.colors) === null &&
        Object.getPrototypeOf(inspect.styles) === null, "null-prototype color and style state");
    colorAssert(Object.keys(inspect.colors).join() === originalColorPairs.map(x=>x[0]).join(), "original 44 enumerable color fields");
    const seen = new Set();
    for (const [name, first, last] of originalColorPairs) {
        const pair = inspect.colors[name], descriptor = Object.getOwnPropertyDescriptor(inspect.colors, name);
        colorAssert(Array.isArray(pair) && Object.getPrototypeOf(pair) === Array.prototype &&
            pair.length === 2 && pair[0] === first && pair[1] === last, name + " original code pair");
        colorAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable, name + " data descriptor");
        colorAssert(!seen.has(pair), "each color has its actual mutable Array"); seen.add(pair);
    }
    colorAssert(Object.keys(inspect.styles).join() === "special,number,bigint,boolean,undefined,null,string,symbol,date,regexp,module", "original styles order");
    colorAssert(Object.values(inspect.styles).join() === "cyan,yellow,yellow,yellow,grey,bold,green,green,magenta,red,underline", "original style values");
}
function observeColorAliases(inspect) {
    for (const [target, alias] of originalColorAliases) {
        const descriptor = Object.getOwnPropertyDescriptor(inspect.colors, alias);
        colorAssert(descriptor.configurable && !descriptor.enumerable &&
            descriptor.get.name === "get" && descriptor.get.length === 0 &&
            descriptor.set.name === "set" && descriptor.set.length === 1 &&
            !Object.hasOwn(descriptor.get,"prototype") && !Object.hasOwn(descriptor.set,"prototype"), alias + " accessor shape");
        colorAssert(inspect.colors[alias] === inspect.colors[target], alias + " actual identity");
        let reads = 0, writes = 0, assigned;
        const receiver = {get [target]() { reads++; return alias; }, set [target](value) { writes++; assigned=value; }};
        colorAssert(descriptor.get.call(receiver) === alias && reads === 1, alias + " call receiver");
        const value = {};
        colorAssert(descriptor.set.call(receiver, value) === undefined && writes === 1 && assigned === value, alias + " assignment and void return");
        const readonly = Object.defineProperty({},target,{value:1,writable:false});
        let reason; try { descriptor.set.call(readonly, value); } catch(error) { reason=error; }
        colorAssert(reason instanceof TypeError, alias + " strict actual assignment");
    }
}
function observeColorValues(inspect, stylize) {
    for (const [style, name] of Object.entries(inspect.styles)) {
        const codes=inspect.colors[name];
        colorAssert(stylize("value",style) === "\x1b["+codes[0]+"mvalue\x1b["+codes[1]+"m", style + " code selection");
    }
    const marker={};
    colorAssert(stylize(marker,"absent") === marker, "absent style returns original value");
    inspect.styles.missing="unknown";
    colorAssert(stylize(marker,"missing") === marker, "absent code returns original value");
    inspect.styles.zero=0; inspect.colors[0]=[7,8];
    colorAssert(stylize("x","zero") === "\x1b[7mx\x1b[8m", "style guard is undefined-only");
    inspect.styles.empty=""; inspect.colors[""]="";
    colorAssert(stylize("x","empty") === "\x1b[undefinedmx\x1b[undefinedm", "code guard is undefined-only");
}
function observeColorLiveOrder(inspect, stylize) {
    const trace=[];
    const kind={ [Symbol.toPrimitive](hint){trace.push("kind:"+hint);return "picked";} };
    const style={ [Symbol.toPrimitive](hint){trace.push("style:"+hint);return "code";} };
    const styles=new Proxy({}, {get(_,key){trace.push("styles:"+String(key));return style;}});
    const colors=new Proxy({}, {get(_,key){trace.push("colors:"+String(key));return [31,39];}});
    Object.defineProperty(inspect,"styles",{configurable:true,get(){trace.push("styles");return styles;}});
    Object.defineProperty(inspect,"colors",{configurable:true,get(){trace.push("colors");return colors;}});
    colorAssert(stylize("x",kind) === "\x1b[31mx\x1b[39m", "actual live style result");
    colorAssert(trace.join() === "styles,kind:string,styles:picked,colors,style:string,colors:code", "ordered repeated public table and computed-key operations");
}
function observeColorTemplate(inspect, stylize) {
    const trace=[];
    inspect.styles.selected="picked";
    inspect.colors.picked={
        get 0(){trace.push("get0");return {[Symbol.toPrimitive](hint){trace.push("code0:"+hint);return 31;}};},
        get 1(){trace.push("get1");return {[Symbol.toPrimitive](hint){trace.push("code1:"+hint);return 39;}};},
    };
    const input={ [Symbol.toPrimitive](hint){trace.push("input:"+hint);return "payload";} };
    const original=Object.getOwnPropertyDescriptor(String.prototype,"concat");
    try {
        Object.defineProperty(String.prototype,"concat",{configurable:true,get(){throw new Error("live concat selected");}});
        colorAssert(stylize(input,"selected") === "\x1b[31mpayload\x1b[39m", "intrinsic template result");
    } finally { Object.defineProperty(String.prototype,"concat",original); }
    colorAssert(trace.join() === "get0,code0:string,input:string,get1,code1:string", "eager substitution order and string hint");
}
function observeColorAbrupt(inspect, stylize) {
    inspect.styles.selected="picked";
    for(const stop of ["code0","input","code1"]) {
        const trace=[], marker={stop};
        function part(name,value){return {[Symbol.toPrimitive](hint){trace.push(name+":"+hint);if(name===stop)throw marker;return value;}};}
        inspect.colors.picked={get 0(){trace.push("get0");return part("code0",31);},get 1(){trace.push("get1");return part("code1",39);}};
        let caught;
        try { stylize(part("input","x"),"selected"); } catch(reason){caught=reason;}
        colorAssert(caught===marker, "original abrupt substitution identity "+stop);
        const expected=stop==="code0"?"get0,code0:string":stop==="input"?"get0,code0:string,input:string":"get0,code0:string,input:string,get1,code1:string";
        colorAssert(trace.join()===expected, "no later substitution "+stop);
    }
    let second=0,caught;
    inspect.colors.picked={0:31,get 1(){second++;return 39;}};
    try { stylize(Symbol("input"),"selected"); } catch(reason){caught=reason;}
    colorAssert(caught instanceof TypeError && second===0, "Symbol uses intrinsic ToString before next code");
}
function observeColorPrivateData(inspect, stylize) {
    const reason=colorPrivateData();
    Object.defineProperty(inspect,"styles",{get(){throw reason;}});
    let caught;try{stylize("x","selected");}catch(error){caught=error;}
    colorAssert(caught===reason,"ordinary native DATA property failure retains identity");
}
function observeColorFlaggedData(inspect, stylize) {
    const value=colorFlaggedData();
    value[Symbol.toPrimitive]=function(hint){colorAssert(hint==="string","flagged DATA key string hint");return "picked";};
    inspect.styles.selected=value;inspect.colors.picked=[31,39];
    colorAssert(stylize("x","selected")==="\x1b[31mx\x1b[39m","successful flagged key remains DATA");
}
function observeColorReceiverRetirement(inspect, stylize) {
    let styles=colorMake(0);
    Object.defineProperty(styles,"selected",{get(){return "picked";}});
    Object.defineProperty(inspect,"styles",{get(){const value=styles;styles=undefined;return value;}});
    Object.defineProperty(inspect,"colors",{get(){colorAssert(colorCount(0)===1,"style table receiver retired before colors getter");return {picked:[31,39]};}});
    colorAssert(stylize("x","selected")==="\x1b[31mx\x1b[39m","style receiver causal path");
}
function observeColorSubstitutionRetirement(inspect, stylize) {
    inspect.styles.selected="picked";
    let first=colorMake(0);first[Symbol.toPrimitive]=function(hint){colorAssert(hint==="string","first code hint");return 31;};
    inspect.colors.picked={get 0(){const value=first;first=undefined;return value;},get 1(){colorAssert(colorCount(0)===1,"first code root retired before last getter");return 39;}};
    const input={[Symbol.toPrimitive](hint){colorAssert(hint==="string"&&colorCount(0)===1,"first code retires before input conversion");return"x";}};
    colorAssert(stylize(input,"selected")==="\x1b[31mx\x1b[39m","code temporary causal path");
}
function observeColorLocalRetirement(inspect, stylize) {
    let style=colorMake(0);style[Symbol.toPrimitive]=function(){return"picked";};
    let color=colorMake(1);
    Object.defineProperty(color,"0",{get(){colorAssert(colorCount(0)===0&&colorCount(1)===0,"both original locals live in first code");return 31;}});
    Object.defineProperty(color,"1",{get(){colorAssert(colorCount(0)===0&&colorCount(1)===0,"both original locals live in last code");return 39;}});
    Object.defineProperty(inspect.styles,"selected",{get(){const value=style;style=undefined;return value;}});
    Object.defineProperty(inspect.colors,"picked",{get(){const value=color;color=undefined;return value;}});
    colorAssert(stylize("x","selected")==="\x1b[31mx\x1b[39m","original local result");
    colorAssert(colorCount(0)===1&&colorCount(1)===1,"original locals retire at actual terminal");
}
function observeColorCurrentFatal(inspect, stylize) {
    Object.defineProperty(inspect,"styles",{get(){colorFatal();return{};}});
    Object.defineProperty(inspect,"colors",{get(){colorProgress.later=true;return{};}});
    try{stylize("x","selected");}catch(reason){colorProgress.entered=true;}
    colorProgress.later=true;
}
function observeColorRetirementFatal(inspect, stylize) {
    let styles=colorMake(0);
    Object.defineProperty(styles,"selected",{get(){return"picked";}});
    Object.defineProperty(inspect,"styles",{get(){const value=styles;styles=undefined;return value;}});
    Object.defineProperty(inspect,"colors",{get(){colorProgress.later=true;return{picked:[31,39]};}});
    colorFailOn(0);
    try{stylize("x","selected");}catch(reason){colorProgress.entered=true;}
    colorProgress.later=true;
}
function observeColorInspectorIntegration(inspect) {
    colorAssert(inspect(new Uint8Array([1,2]),{colors:true,breakLength:32}) === "Uint8Array(2) [ \x1b[33m1\x1b[39m, \x1b[33m2\x1b[39m ]","original typed colored near-breakLength control");
    colorAssert(inspect(12,{colors:true})==="\x1b[33m12\x1b[39m","actual primitive color dependency");
    colorAssert(inspect(new Uint8Array([1]),{colors:true,depth:-1})==="\x1b[36m[Uint8Array]\x1b[39m","actual special style depth dependency");
    inspect.styles.number="red";inspect.colors.red=[35,0];
    colorAssert(inspect(7,{colors:true})==="\x1b[35m7\x1b[0m","same live public color tables reach real inspector");
}
function observeColorOverride(inspect) {
    let calls=0,reads=0;
    const options={get stylize(){reads++;return function(){calls++;throw new Error("user stylizer selected");};},colors:true};
    colorAssert(inspect(1,options)==="\x1b[33m1\x1b[39m"&&reads===1&&calls===0,"colors overrides the supplied stylizer after original option getter");
}
