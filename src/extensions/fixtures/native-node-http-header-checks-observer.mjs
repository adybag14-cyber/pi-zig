// Actual private _http_common header values, constructed from the unchanged
// Node Source definitions or their native owner in a fresh Engine per branch.
function headerAssert(value,message) { if (!value) throw new Error(message); }
function headerSame(value,expected,message) { headerAssert(Object.is(value,expected),message); }
function headerList(value,expected,message) { headerAssert(value.length===expected.length && value.every((v,i)=>Object.is(v,expected[i])),message); }
function headerRestore(object,key,descriptor) { if(descriptor) Object.defineProperty(object,key,descriptor); else delete object[key]; }
function observeHeaderShapes(subject) {
    headerList(Reflect.ownKeys(subject),["_checkInvalidHeaderChar","_checkIsHttpToken","chunkExpression","continueExpression","CRLF"],"actual selected common values and order");
    for (const [key,name] of [["_checkInvalidHeaderChar","checkInvalidHeaderChar"],["_checkIsHttpToken","checkIsHttpToken"]]) {
        const fn=subject[key]; headerSame(fn.name,name,"actual ordinary helper name"); headerSame(fn.length,1,"actual helper arity");
        headerAssert(Object.hasOwn(fn,"prototype"),"ordinary function declaration");
        const descriptor=Object.getOwnPropertyDescriptor(subject,key);
        headerAssert(descriptor.writable&&descriptor.enumerable&&descriptor.configurable,"actual export data descriptor");
    }
    headerSame(subject.CRLF,"\r\n","exact protocol literal");
    headerSame(subject.chunkExpression.source,"(?:^|\\W)chunked(?:$|\\W)","actual chunk regex");
    headerSame(subject.continueExpression.source,"(?:^|\\W)100-continue(?:$|\\W)","actual continue regex");
    headerSame(subject.chunkExpression.flags,"i","actual chunk flag");
    headerSame(subject.continueExpression.flags,"i","actual continue flag");
    headerAssert(subject.chunkExpression.test("gzip, CHUNKED")&&!subject.chunkExpression.test("xchunked"),"actual token boundaries");
}
function observeHeaderMatrix(subject) {
    const allowed="!#$%&'*+-.^_"+String.fromCharCode(96)+"|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    for(let code=0;code<256;code++) {
        const text=String.fromCharCode(code);
        headerSame(subject._checkIsHttpToken(text),allowed.includes(text),"actual short token byte "+code);
        headerSame(subject._checkInvalidHeaderChar(text),!(code===9||(code>=32&&code<=126)||(code>=128&&code<=255)),"actual header character "+code);
    }
    for(const text of ["content-type","ABCDEFGHIJKLMNOPQRSTUVWXYZ",allowed]) headerSame(subject._checkIsHttpToken(text),true,"actual regex long token");
    for(const text of ["","content type","bad:header","abcdefghij\u0100","abcdefghij\r\n"]) headerSame(subject._checkIsHttpToken(text),false,"actual invalid token");
    headerSame(subject._checkInvalidHeaderChar("tab\t latin\u00ff"),false,"actual obs-text accepted");
    headerSame(subject._checkInvalidHeaderChar("\u0100"),true,"actual wide code unit rejected");
    let caught; try { subject._checkInvalidHeaderChar(Symbol("header")); } catch(error){caught=error;}
    headerAssert(caught instanceof TypeError,"actual regexp string coercion rejects Symbol");
}
function observeHeaderShortOrder(subject) {
    const trace=[]; let reads=0;
    const input={get length(){ trace.push("length:"+ ++reads); return 1; },get charCodeAt(){
        trace.push("method"); return function(index){headerSame(this,input,"actual charCodeAt receiver"); trace.push("call:"+index); return 65;};
    }};
    headerSame(subject._checkIsHttpToken(input),true,"actual short table path");
    headerList(trace,["length:1","length:2","length:3","method","call:0","length:4"],"live repeated length and method order");
    const zero={get length(){trace.push("zero");return 0;},get charCodeAt(){throw new Error("zero must not call");}};
    headerSame(subject._checkIsHttpToken(zero),false,"actual exact-zero early return");
    headerList(trace.slice(-2),["zero","zero"],"first relational and second strict check remain separate");
}
function observeHeaderPredicateRetirement(subject,hooks) {
    let reads=0;
    const input={get length(){
        reads++;
        if(reads===1){const value=hooks.make(0);value.valueOf=()=>1;return value;}
        if(reads===2){headerSame(hooks.count(0),1,"first predicate owner retired");return hooks.make(1);}
        if(reads===3){headerSame(hooks.count(1),1,"strict-zero operand retired");const value=hooks.make(2);value.valueOf=()=>1;return value;}
        if(reads===4){const value=hooks.make(3);value.valueOf=()=>1;return value;}
        throw new Error("unexpected length read");
    },get charCodeAt(){
        headerSame(hooks.count(2),1,"loop predicate retired before method selection");
        return ()=>65;
    }};
    headerSame(subject._checkIsHttpToken(input),true,"actual predicate path");
    headerSame(reads,4,"all four actual reads");
    headerSame(hooks.count(3),1,"false-condition operand retired before return");
}
function observeHeaderLongReturn(subject,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(RegExp.prototype,"test"), returned=hooks.freshPrivateData(), trace=[];
    try {
        Object.defineProperty(RegExp.prototype,"test",{configurable:true,get(){
            const regexp=this; trace.push("get");
            const fn=function(input){ headerSame(this,regexp,"actual test receiver");headerSame(input.length,10,"same input");trace.push("call");return returned; };
            fn.holder=hooks.make(0);return fn;
        }});
        const input={length:10,get charCodeAt(){throw new Error("long branch cannot use table");}};
        headerSame(subject._checkIsHttpToken(input),returned,"actual live test return transfers arbitrary DATA");
        headerAssert(hooks.isUnmarkedPrivateData(returned),"successful private DATA remains ordinary");
        headerSame(hooks.count(0),1,"live callee retired before helper return");
        headerList(trace,["get","call"],"single actual regex test operation");
    } finally {headerRestore(RegExp.prototype,"test",descriptor);}
}
function observeHeaderLiveExec(subject) {
    const descriptor=Object.getOwnPropertyDescriptor(RegExp.prototype,"exec"), trace=[], reason={};
    let fail=false;
    try{
        Object.defineProperty(RegExp.prototype,"exec",{configurable:true,get(){
            const regexp=this;trace.push("get:"+regexp.source);
            return function(input){headerSame(this,regexp,"real regex exec receiver");trace.push("call:"+input);if(fail)throw reason;return {};};
        }});
        headerSame(subject._checkInvalidHeaderChar("abc"),true,"real RegExp.test consumes actual exec result");
        headerSame(trace.length,2,"one exec get and call");
        fail=true;let caught;try{subject._checkIsHttpToken("abcdefghij");}catch(error){caught=error;}
        headerSame(caught,reason,"actual exec abrupt identity");
        headerSame(trace.length,4,"long-token actual exec get and call");
    }finally{headerRestore(RegExp.prototype,"exec",descriptor);}
}
function observeHeaderComputedKeyRetirement(subject,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(Uint8Array.prototype,"headerProbe"), trace=[];let reads=0;
    try{
        Object.defineProperty(Uint8Array.prototype,"headerProbe",{configurable:true,get(){
            trace.push("table");headerSame(hooks.count(1),1,"computed key retired before actual typed-array prototype lookup");
            return hooks.make(2);
        }});
        const input={get length(){reads++;if(reads===4)headerSame(hooks.count(2),1,"lookup truthiness owner retired before next condition");return 1;},
            get charCodeAt(){const fn=function(){const key=hooks.make(1);key[Symbol.toPrimitive]=function(hint){
                trace.push("key:"+hint);headerSame(hooks.count(0),1,"charCodeAt callee retired before ToPropertyKey");return "headerProbe";};return key;};
                fn.holder=hooks.make(0);return fn;}};
        headerSame(subject._checkIsHttpToken(input),true,"computed table key uses actual lookup");
        headerList(trace,["key:string","table"],"exact key-before-property operation");
    }finally{headerRestore(Uint8Array.prototype,"headerProbe",descriptor);}
}
function observeHeaderPrivateData(subject,hooks,regex) {
    let reason,caught;
    const original=Object.getOwnPropertyDescriptor(RegExp.prototype,"test");
    const input={get length(){reason=hooks.freshPrivateData();throw reason;}};
    try{
        if(regex) Object.defineProperty(RegExp.prototype,"test",{configurable:true,get(){reason=hooks.freshPrivateData();throw reason;}});
        try{if(regex)subject._checkInvalidHeaderChar("x");else subject._checkIsHttpToken(input);}catch(error){caught=error;}
        headerSame(caught,reason,"actual same-getter private DATA reason");
        headerAssert(hooks.isUnmarkedPrivateData(caught),"caught private DATA remains unmarked");
    }finally{headerRestore(RegExp.prototype,"test",original);}
}
function observeHeaderCurrentFatal(subject,hooks) {
    let reads=0;
    const input={get length(){if(reads++){hooks.visit(1);return 1;}hooks.freshPrivateData();return hooks.raiseNativeFatal();},
        get charCodeAt(){hooks.visit(2);return ()=>65;}};
    try{subject._checkIsHttpToken(input);hooks.record.guestReached=true;hooks.visit(3);}
    catch(error){hooks.record.guestReached=true;hooks.visit(3);throw error;}
}
function observeHeaderKeyFatal(subject,hooks) {
    Object.defineProperty(Uint8Array.prototype,"headerFatalProbe",{configurable:true,get(){hooks.visit(1);return 1;}});
    const input={length:1,charCodeAt(){const key=hooks.make(0);key[Symbol.toPrimitive]=function(){return "headerFatalProbe";};return key;}};
    hooks.armFatal(0);
    try{subject._checkIsHttpToken(input);hooks.record.guestReached=true;hooks.visit(3);}
    catch(error){hooks.record.guestReached=true;hooks.visit(3);throw error;}
}
function observeHeaderIntrinsicCreation(create) {
    const regexp=Object.getOwnPropertyDescriptor(globalThis,"RegExp"),uint8=Object.getOwnPropertyDescriptor(globalThis,"Uint8Array");
    try{
        Object.defineProperty(globalThis,"RegExp",{configurable:true,writable:true,value:function(){throw new Error("live global RegExp");}});
        Object.defineProperty(globalThis,"Uint8Array",{configurable:true,writable:true,value:function(){throw new Error("live global Uint8Array");}});
        const subject=create();
        headerSame(subject._checkIsHttpToken("content-type"),true,"retained intrinsic regex creation");
        headerSame(subject._checkIsHttpToken("a"),true,"retained actual typed array constructor");
        headerSame(subject._checkInvalidHeaderChar("\r"),true,"actual private header regex");
    }finally{headerRestore(globalThis,"RegExp",regexp);headerRestore(globalThis,"Uint8Array",uint8);}
}
function observeHeaderTableIterator(create) {
    const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator), trace=[];
    try{
        Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,get(){
            const array=this;headerSame(array.length,256,"actual literal table operand");trace.push("get");
            return function(){headerSame(this,array,"actual table iterable receiver");trace.push("call");let next=0;
                return {next(){trace.push("next");return next++===0?{done:false,value:1}:{done:true};}};
            };
        }});
        const subject=create();
        headerSame(subject._checkIsHttpToken({length:1,charCodeAt(){return 0;}}),true,"real constructor uses live literal-array iteration");
        headerSame(subject._checkIsHttpToken("a"),false,"private typed array really contains one produced element");
        headerSame(trace.filter(value=>value==="call").length,1,"actual iterator called once");
        headerSame(trace.filter(value=>value==="next").length,2,"actual iterator exhausted");
        headerAssert(trace[0]==="get"&&trace.includes("call"),"actual iterable lookup precedes call");
    }finally{headerRestore(Array.prototype,Symbol.iterator,descriptor);}
}
