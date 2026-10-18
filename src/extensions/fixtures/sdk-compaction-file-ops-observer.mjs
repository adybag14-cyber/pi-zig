function assertFileOps(condition,message){if(!condition)throw Error(message);}
function observeFileOpsBasic(api) {
    const operations=api.createFileOps();
    assertFileOps(Object.keys(operations).join()==="read,written,edited","actual file-operation field order");
    assertFileOps(operations.read instanceof Set&&operations.written instanceof Set&&operations.edited instanceof Set,"three real sets");
    api.extractFileOpsFromMessage({role:"assistant",content:[
        {type:"toolCall",name:"read",arguments:{path:"only-read"}},
        {type:"toolCall",name:"read",arguments:{path:"modified"}},
        {type:"toolCall",name:"write",arguments:{path:"modified"}},
        {type:"toolCall",name:"edit",arguments:{path:"edited"}},
        null,1,()=>{}, {type:"text",text:"ignore"}, {type:"toolCall",name:"read",arguments:{path:""}},
    ]},operations);
    api.extractFileOpsFromMessage({role:"toolResult",nestedCalls:{calls:[
        {name:"read",arguments:{path:"nested"}},{name:"write",arguments:{path:"written"}},
    ]}},operations);
    api.extractFileOpsFromMessage({role:"toolResult",nestedCalls:null},operations);
    api.extractFileOpsFromMessage({role:"assistant",content:"not array"},operations);
    api.extractFileOpsFromMessage({role:"user",content:[]},operations);
    const result=api.computeFileLists(operations);
    assertFileOps(JSON.stringify(result)==='{"readFiles":["nested","only-read"],"modifiedFiles":["edited","modified","written"]}',"actual file sets and sorted projections");
    assertFileOps(api.formatFileOperations(result.readFiles,result.modifiedFiles)==="\n\n<read-files>\nnested\nonly-read\n</read-files>\n\n<modified-files>\nedited\nmodified\nwritten\n</modified-files>","actual summary XML");
    assertFileOps(api.formatFileOperations([],[])==="","empty file-operation text");
}
function observeFileOpsConstructors(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set"),OriginalSet=Set;let reads=0;
    Object.defineProperty(globalThis,"Set",{configurable:true,get(){
        const slot=reads++;if(slot)assertFileOps(hooks.count(slot-1)===1,"previous Set constructor retires before next lookup");
        const constructor=function(){return new OriginalSet();};constructor.prototype=null;constructor.holder=hooks.make(slot);return constructor;
    }});
    let result;
    try{result=api.createFileOps();}finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertFileOps(reads===3&&hooks.count(2)===1&&result.read!==result.written&&result.written!==result.edited,"three live Set constructions");
}
function observeFileOpsNestedReceiver(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);let iterations=0;
    Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,get(){
        iterations++;assertFileOps(hooks.count(0)===1,"optional-chain receiver retires before fallback iterator lookup");return descriptor.value;
    }});
    try{
        api.extractFileOpsFromMessage({role:"toolResult",get nestedCalls(){return {holder:hooks.make(0),calls:null};}},{});
    }finally{Object.defineProperty(Array.prototype,Symbol.iterator,descriptor);}
    assertFileOps(iterations===1&&hooks.count(0)===1,"actual empty for-of fallback");
}
function observeFileOpsArrayPredicate(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Array");let reads=0;
    Object.defineProperty(globalThis,"Array",{configurable:true,get(){
        const receiver={holder:hooks.make(0),marker:"actual-array-receiver"};
        receiver.isArray=function(value){assertFileOps(this.marker==="actual-array-receiver"&&value.marker,"real live Array.isArray call");return {holder:hooks.make(3)};};
        receiver.isArray.holder=hooks.make(1);return receiver;
    }});
    try{
        api.extractFileOpsFromMessage({role:"assistant",get content(){
            if(++reads===1)return {holder:hooks.make(2),marker:true};
            assertFileOps(hooks.count(0)===1&&hooks.count(1)===1&&hooks.count(2)===1&&hooks.count(3)===1,"predicate operands retire before repeated content getter");return [];
        }},{});
    }finally{Object.defineProperty(globalThis,"Array",descriptor);}
    assertFileOps(reads===2,"actual repeated content getter");
}
function fileOpsHeadIterable(hooks,kind) {
    let nexts=0;
    return {[Symbol.iterator](){return {next(){
        nexts++;
        if(nexts===2)assertFileOps(hooks.count(0)===0,"first plain head survives next");
        if(nexts===3){assertFileOps(hooks.count(0)===1&&hooks.count(1)===0,"final plain head survives done");return {done:true};}
        return {done:false,value:kind==="call"?{holder:hooks.make(nexts-1),name:"unused",arguments:undefined}:{holder:hooks.make(nexts-1),type:"text"}};
    }}}};
}
function observeFileOpsHeads(api,hooks,kind) {
    const iterable=fileOpsHeadIterable(hooks,kind);
    if(kind==="call")api.extractFileOpsFromMessage({role:"toolResult",nestedCalls:{calls:iterable}},{});
    else{
        let reads=0;api.extractFileOpsFromMessage({role:"assistant",get content(){return ++reads===1?[]:iterable;}},{});
        assertFileOps(reads===2,"assistant content remains live");
    }
    assertFileOps(hooks.count(0)===1&&hooks.count(1)===1,"plain heads retire at function completion");
}
function observeFileOpsArgumentOrder(api,hooks) {
    const trace=[];let nexts=0,contents=0,paths=0;
    const iterable={[Symbol.iterator](){return {next(){
        if(++nexts===2){assertFileOps(hooks.count(0)===1&&hooks.count(1)===1&&hooks.count(2)===1&&hooks.count(3)===1&&hooks.count(4)===1&&hooks.count(5)===0,"argument and call temporaries retire before next, head remains");return {done:true};}
        const block={holder:hooks.make(5),type:"toolCall",name:"read",get arguments(){return {holder:hooks.make(0),get path(){return ++paths===1?"check":{holder:hooks.make(1),marker:"path",toString(){throw Error("path must not coerce");}};}};}};
        return {done:false,value:new Proxy(block,{has(target,key){trace.push("has:"+key);return Reflect.has(target,key);},get(target,key,receiver){if(typeof key==="string")trace.push("get:"+key);return Reflect.get(target,key,receiver);}})};
    }}}};
    const operations={get read(){
        const receiver={holder:hooks.make(2),marker:"actual-set-receiver",get add(){const method=function(path){assertFileOps(this.marker==="actual-set-receiver"&&path.marker==="path","repeated path result and add receiver");return {holder:hooks.make(4)};};method.holder=hooks.make(3);return method;}};
        return receiver;
    }};
    api.extractFileOpsFromMessage({role:"assistant",get content(){return ++contents===1?[]:iterable;}},operations);
    assertFileOps(paths===2&&hooks.count(5)===1,"path is read twice and final block retires");
    assertFileOps(trace.join()==="has:type,get:type,has:arguments,has:name,get:name,get:arguments","actual in/get order");
}
function observeFileOpsPrimitiveIn(api) {
    const descriptor=Object.getOwnPropertyDescriptor(Number.prototype,"role");
    Object.defineProperty(Number.prototype,"role",{configurable:true,get(){return "assistant";}});
    let caught;
    try{api.extractFileOpsFromMessage(1,{});}catch(error){caught=error;}
    finally{if(descriptor)Object.defineProperty(Number.prototype,"role",descriptor);else delete Number.prototype.role;}
    assertFileOps(caught instanceof TypeError&&caught.message==="invalid 'in' operand","primitive in operand uses actual intrinsic error");
}
function observeFileOpsSpread(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(globalThis,"Set"),OriginalSet=Set;let symbolReads=0,steps=0;
    Object.defineProperty(globalThis,"Set",{configurable:true,get(){
        const constructor=function(values){assertFileOps(hooks.count(1)===1&&hooks.count(4)===1,"spread completed before Set call");return new OriginalSet(values);};
        constructor.prototype=null;constructor.holder=hooks.make(0);return constructor;
    }});
    const operations={
        get edited(){
            return {holder:hooks.make(1),get [Symbol.iterator](){
                symbolReads++;
                if(symbolReads===1){const probe=function(){throw Error("append probe must not be called");};probe.holder=hooks.make(2);return probe;}
                assertFileOps(symbolReads===2&&hooks.count(2)===1&&hooks.count(1)===0,"actual append probe then second lookup");
                const factory=function(){assertFileOps(hooks.count(1)===0,"append keeps iterable during factory");return {get next(){
                    assertFileOps(hooks.count(3)===1&&hooks.count(1)===0,"factory retires before next getter while iterable lives");
                    const next=function(){steps++;assertFileOps(hooks.count(1)===0,"append iterable survives every next");return steps===1?{done:false,value:"edited"}:{done:true};};
                    next.holder=hooks.make(4);return next;
                }};};factory.holder=hooks.make(3);return factory;
            }};
        },
        get written(){assertFileOps(hooks.count(1)===1&&hooks.count(4)===1&&hooks.count(0)===0,"first spread roots retire before next spread");return new OriginalSet(["written"]);},
        get read(){assertFileOps(hooks.count(0)===1,"Set constructor retires before read spread");return new OriginalSet(["read","edited"]);},
    };
    let result;
    try{result=api.computeFileLists(operations);}finally{Object.defineProperty(globalThis,"Set",descriptor);}
    assertFileOps(symbolReads===2&&steps===2&&JSON.stringify(result)==='{"readFiles":["read"],"modifiedFiles":["edited","written"]}',"actual append and list results");
}
function observeFileOpsSpreadClose(api,hooks) {
    const reason={controlled:"spread next failure"};let symbols=0,closes=0;
    const operations={get edited(){return {holder:hooks.make(0),get [Symbol.iterator](){symbols++;return function(){return {
        next(){throw reason;},
        return(){closes++;assertFileOps(hooks.count(0)===0,"append close sees live iterable");return 1;},
    };};}};},get written(){throw Error("later spread must not run");}};
    let caught;try{api.computeFileLists(operations);}catch(error){caught=error;}
    assertFileOps(caught===reason&&symbols===2&&closes===1&&hooks.count(0)===1,"actual append closes even when next throws and preserves reason");
}
function observeFileOpsListExpressions(api,hooks) {
    const setDescriptor=Object.getOwnPropertyDescriptor(globalThis,"Set"),filterDescriptor=Object.getOwnPropertyDescriptor(Array.prototype,"filter"),OriginalSet=Set;
    Object.defineProperty(globalThis,"Set",{configurable:true,value:function(){return {
        get has(){const method=function(value){assertFileOps(value==="chosen","actual read-only predicate argument");return {holder:hooks.make(3)};};method.holder=hooks.make(2);return method;},
        get [Symbol.iterator](){assertFileOps(hooks.count(4)===1&&hooks.count(5)===1,"read sort receiver and callee retire before modified spread");return function(){return {next(){return {done:true};}};};},
    };}});
    Object.defineProperty(Array.prototype,"filter",{configurable:true,get(){
        this.holder=hooks.make(1);
        const method=function(predicate){
            assertFileOps(predicate.length===1&&!Object.hasOwn(predicate,"prototype")&&predicate("chosen")===false,"actual captured read-only arrow");
            assertFileOps(hooks.count(2)===1&&hooks.count(3)===1,"has call and ToBoolean result retire before callback returns");
            return {holder:hooks.make(4),get sort(){
                assertFileOps(hooks.count(0)===1&&hooks.count(1)===1,"read filter receiver and callee retire before sort getter");
                const sort=function(){return ["readonly"];};sort.holder=hooks.make(5);return sort;
            }};
        };method.holder=hooks.make(0);return method;
    }});
    let result;
    try{result=api.computeFileLists({edited:new OriginalSet(),written:new OriginalSet(),read:new OriginalSet(["chosen"])});}
    finally{Object.defineProperty(globalThis,"Set",setDescriptor);Object.defineProperty(Array.prototype,"filter",filterDescriptor);}
    assertFileOps(result.readFiles[0]==="readonly"&&result.modifiedFiles.length===0,"live list method outputs");
}
function observeFileOpsFormatExpressions(api,hooks) {
    const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,"push");let pushes=0,reads=0;
    Object.defineProperty(Array.prototype,"push",{configurable:true,get(){
        assertFileOps(hooks.count(0)===1,"length comparison operand retires before push getter");
        const method=function(text){pushes++;assertFileOps(hooks.count(2)===1,"join operand retires before actual push");Reflect.apply(descriptor.value,this,[text]);return {holder:hooks.make(4)};};
        method.holder=hooks.make(1);return method;
    }});
    const readFiles={get length(){reads++;return {holder:hooks.make(0),valueOf(){return 1;}};},get join(){
        assertFileOps(hooks.count(1)===0,"push callee resolved before join getter");
        const method=function(separator){assertFileOps(separator==="\n","actual line delimiter");return {holder:hooks.make(2),toString(){assertFileOps(hooks.count(3)===1,"join callee retires before returned ToString");return "a";}};};
        method.holder=hooks.make(3);return method;
    }};
    const modifiedFiles={get length(){assertFileOps(hooks.count(1)===1&&hooks.count(4)===1,"discarded push result retires before next section");return 0;}};
    let result;
    try{result=api.formatFileOperations(readFiles,modifiedFiles);}finally{Object.defineProperty(Array.prototype,"push",descriptor);}
    assertFileOps(reads===1&&pushes===1&&result==="\n\n<read-files>\na\n</read-files>","actual file format method order");
}
function observeFileOpsPrivateData(api,hooks) {
    let data,closes=0;
    const message={role:"toolResult",nestedCalls:{calls:{[Symbol.iterator](){return {
        next(){return {done:false,value:{holder:hooks.make(0),get name(){data=hooks.freshPrivateData();throw data;}}};},
        return(){closes++;assertFileOps(hooks.count(0)===0,"ordinary close retains current head");return 1;},
    };}}}};
    let caught;try{api.extractFileOpsFromMessage(message,{});}catch(error){caught=error;}
    assertFileOps(caught===data&&hooks.isUnmarkedPrivateData(data)&&closes===1&&hooks.count(0)===1,"actual private DATA remains ordinary through iterator retirement");
}
function observeFileOpsCurrentFatal(api,hooks) {
    const message={role:"toolResult",nestedCalls:{calls:{[Symbol.iterator](){return {
        next(){return {done:false,value:{get name(){const old=hooks.freshPrivateData();try{hooks.raiseNativeFatal();}catch(error){}throw old;}}};},
        return(){hooks.record.guestReached=true;hooks.visit(3);return {};},
    };}}}};
    try{api.extractFileOpsFromMessage(message,{});}catch(error){hooks.record.guestReached=true;hooks.visit(3);}
}
function observeFileOpsCancellation(api,hooks) {
    let calls=0;
    const message={role:"toolResult",nestedCalls:{calls:{[Symbol.iterator](){return {
        next(){if(++calls===1)return {done:false,value:{holder:hooks.make(0),name:"unused",arguments:undefined}};
            if(calls===2)return {done:false,value:{get name(){hooks.visit(1);return "unused";}}};hooks.visit(1);return {done:true};},
        return(){hooks.visit(2);return {};},
    };}}}};
    hooks.armCancel(0);api.extractFileOpsFromMessage(message,{});hooks.visit(3);
}
