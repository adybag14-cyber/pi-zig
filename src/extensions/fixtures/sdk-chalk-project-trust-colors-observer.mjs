// Authored caller inputs and causal assertions. Expected observation bytes are
// produced by the complete pinned original Chalk source in a separate fresh VM.
// Only red/yellow/cyan are consumed; named model/modifier APIs are outside scope.
"use strict";
function ccCheck(value, message) { if (!value) throw new Error(message); }
function ccSymbols(root) {
    const builder=root.yellow;
    const find=(value,name)=>Reflect.ownKeys(value).find(k=>typeof k==="symbol"&&k.description===name);
    return {GENERATOR:find(builder,"GENERATOR"),STYLER:find(builder,"STYLER"),
        IS_EMPTY:find(builder,"IS_EMPTY"),LEVEL:find(root,"LEVEL")};
}
function ccCase(name, shared) {
    const make=options=>shared.constructor(options);
    const events=[];
    const plainSamples=["","text","a\nb","a\r\nb","a\rb","\nx\n","\r\nx\r\n",
        "\x1b[39mx\x1b[39m","a\x1b[39mb\r\nc","\x1b[31mred\x1b[0m",
        "\ufeff雪\ud800\udc00\udfff\u0000"];
    switch(name) {
    case "yellow-regression": {
        const observations=runChalkConsumedCases(shared);
        ccCheck(observations.length===86&&new Set(observations.map(x=>x.id)).size===86,
            "complete preserved yellow corpus");
        return observations;
    }
    case "red-matrix":
    case "cyan-matrix": {
        const style=name==="red-matrix"?"red":"cyan",observations=[];
        for(const level of [0,1,2,3]) {
            const root=make({level});
            for(const sample of plainSamples) observations.push({level,sample,out:root[style](sample)});
            ccCheck(root[style]("x")===(level===0?"x":"\x1b["+(style==="red"?"31":"36")+"mx\x1b[39m"),
                "actual primary foreground code");
        }
        return observations;
    }
    case "mixed-chains": {
        const observations=[];
        for(const level of [0,1,2,3]) {
            const root=make({level});
            for(const chain of [["red","cyan"],["cyan","red"],["red","yellow","cyan"],
                ["cyan","yellow","red"],["red","red"],["cyan","cyan"]]) {
                let builder=root;
                for(const style of chain) builder=builder[style];
                observations.push({level,chain,out:builder("a\x1b[39mb\r\nc\n")});
            }
        }
        return observations;
    }
    case "descriptors": {
        const root=make({level:1}),proto=Object.getPrototypeOf(root),rows=[];
        for(const style of ["red","yellow","cyan"]) {
            ccCheck(!Object.hasOwn(root,style),"style remains lazy");
            const getter=Object.getOwnPropertyDescriptor(proto,style);
            const builder=root[style],cached=Object.getOwnPropertyDescriptor(root,style);
            const childGetter=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(builder),style);
            rows.push({style,getName:getter.get.name,getLength:getter.get.length,
                getEnumerable:getter.enumerable,getConfigurable:getter.configurable,
                sharedGetter:getter.get===childGetter.get,
                name:builder.name,length:builder.length,callable:typeof builder,
                cached:builder===root[style],writable:cached.writable,
                enumerable:cached.enumerable,configurable:cached.configurable,
                constructorPrototype:Object.hasOwn(builder,"prototype")});
        }
        return {name:root.name,length:root.length,constructor:root.constructor.name,
            keys:Object.keys(root),rows};
    }
    case "cache-isolation": {
        const first=make({level:1}),second=make({level:1}),rows=[];
        for(const style of ["red","yellow","cyan"]) {
            const a=first[style],b=second[style];let rejected=false;
            try{first[style]=b}catch(error){rejected=error instanceof TypeError}
            ccCheck(a!==b&&first[style]===a&&rejected,"immutable per-instance lazy cache");
            rows.push({style,own:Object.hasOwn(first,style),output:a("x"),rejected});
        }
        ccCheck(first.red!==first.cyan&&first.red!==first.yellow,"style identities are distinct");
        return rows;
    }
    case "live-levels": {
        const root=make({level:1}),red=root.red,cyan=root.cyan,nested=red.cyan;
        const before=[red("x"),cyan("x"),nested("x")];
        nested.level=0;
        const disabled=[red("x"),cyan("x"),nested("x")];
        cyan.level=3;
        return {before,disabled,enabled:[red("x"),cyan("x"),nested("x")],
            levels:[root.level,red.level,cyan.level,nested.level]};
    }
    case "public-level": {
        const root=make({level:1}),red=root.red,cyan=root.cyan;
        Object.defineProperty(root,"level",{configurable:true,get(){events.push("public");return 0}});
        return {paint:[red("x"),cyan("x")],read:[red.level,cyan.level],events};
    }
    case "builder-call-forms": {
        const rows=[];
        for(const style of ["red","cyan"]) for(const level of [0,1,2,3]) {
            const root=make({level}),builder=root[style];
            rows.push({style,level,zero:builder(),one:builder(undefined),two:builder(null,2),
                many:builder("a",null,undefined,3),root:root("a",null,undefined,3)});
        }
        return rows;
    }
    case "coercion-hints": {
        const rows=[];
        for(const style of ["red","cyan"]) for(const level of [0,1]) {
            for(const count of [1,2,3]) {
                const trace=[],root=make({level}),value=label=>({
                    [Symbol.toPrimitive](hint){trace.push(label+":"+hint);return label;}
                }),args=[value("a"),value("b"),value("c")].slice(0,count);
                rows.push({style,level,count,output:root[style](...args),trace});
            }
        }
        return rows;
    }
    case "coercion-throw": {
        const rows=[],reason={tag:"conversion"};
        for(const style of ["red","cyan"]) for(const level of [0,1]) {
            for(const count of [1,2,3]) {
                const trace=[],root=make({level}),bad={
                    [Symbol.toPrimitive](hint){trace.push(hint);throw reason;}
                },args=count===1?[bad]:count===2?["first",bad]:["first","second",bad];
                let same=false;
                try{root[style](...args)}catch(error){same=error===reason}
                ccCheck(same,"raw conversion reason survives");
                rows.push({style,level,count,trace,same});
            }
        }
        return rows;
    }
    case "symbol-input": {
        const rows=[];
        for(const style of ["red","cyan"]) for(const level of [0,1]) for(const count of [1,2,3]) {
            const root=make({level}),args=count===1?[Symbol("x")]:
                count===2?["first",Symbol("x")]:["first","second",Symbol("x")];
            let typeError=false;
            try{root[style](...args)}catch(error){typeError=error instanceof TypeError}
            ccCheck(typeError,"disabled and enabled builders still reject Symbol conversion");
            rows.push({style,level,count,typeError});
        }
        return rows;
    }
    case "coercion-reentry": {
        const root=make({level:1}),value={
            [Symbol.toPrimitive](hint){events.push("outer:"+hint);return root.cyan("inside");}
        };
        const output=root.red(value);
        return {output,events};
    }
    case "getter-order": {
        const seed=make({level:1}),keys=ccSymbols(seed),reason={tag:"no"},
            parent={get openAll(){events.push("openAll");return "P";},
                    get closeAll(){events.push("closeAll");return "C";}},
            receiver=new Proxy({},{
                get(target,key){
                    if(key===keys.STYLER){events.push("STYLER");return parent;}
                    if(key===keys.IS_EMPTY){events.push("IS_EMPTY");return false;}
                    if(key===keys.GENERATOR){events.push("GENERATOR");return seed;}
                    throw reason;
                },
                defineProperty(target,key,descriptor){
                    events.push("cache:"+key);return Reflect.defineProperty(target,key,descriptor);
                }
            });
        const get=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(seed),"cyan").get;
        const builder=get.call(receiver);
        ccCheck(typeof builder==="function","borrowed getter returns actual callable");
        return {events,own:Object.hasOwn(receiver,"cyan"),output:builder("x")};
    }
    case "getter-throw": {
        const seed=make({level:1}),keys=ccSymbols(seed),rows=[];
        for(const style of ["red","cyan"]) {
            const root=make({level:1}),trace=[],reason={};
            Object.defineProperty(root,keys.STYLER,{get(){trace.push("STYLER");throw reason}});
            Object.defineProperty(root,keys.IS_EMPTY,{get(){trace.push("unexpected");return false}});
            let same=false;try{root[style]}catch(error){same=error===reason}
            ccCheck(same&&!Object.hasOwn(root,style),"failed getter publishes no cache");
            rows.push({style,same,trace});
        }
        return rows;
    }
    case "getter-same-reentry": {
        const rows=[];
        for(const style of ["red","cyan"]) {
            const root=make({level:1}),keys=ccSymbols(root),trace=[];
            let inside=false,nested,threw=false;
            Object.defineProperty(root,keys.STYLER,{get(){
                trace.push("STYLER");
                if(!inside){inside=true;nested=root[style];inside=false;}
                return undefined;
            }});
            try{root[style]}catch(error){threw=error instanceof TypeError}
            ccCheck(threw&&root[style]===nested,"inner cache survives failing outer redefinition");
            rows.push({style,trace,threw,output:nested("x")});
        }
        return rows;
    }
    case "getter-cross-reentry": {
        const root=make({level:1}),keys=ccSymbols(root);let inside=false,nested;
        Object.defineProperty(root,keys.STYLER,{get(){
            events.push("STYLER");
            if(!inside){inside=true;nested=root.cyan;inside=false;}
            return undefined;
        }});
        const outer=root.red;
        ccCheck(outer!==nested&&root.red===outer&&root.cyan===nested,"independent nested caches");
        return {events,outputs:[outer("x"),nested("x")]};
    }
    case "cache-throw": {
        const root=make({level:1}),get=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(root),"red").get;
        const reason={},receiver=new Proxy({},{
            get(){return undefined;},
            defineProperty(){events.push("define");throw reason}
        });
        let same=false;try{get.call(receiver)}catch(error){same=error===reason}
        ccCheck(same&&!Object.hasOwn(receiver,"red"),"cache definition throw remains original");
        return {same,events};
    }
    case "borrowed-getter": {
        const root=make({level:1}),keys=ccSymbols(root),rows=[];
        for(const style of ["red","cyan"]) {
            const get=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(root),style).get;
            const receiver={[keys.GENERATOR]:root};
            const builder=get.call(receiver);
            let constructorError=false;try{Reflect.construct(builder,[])}catch(error){constructorError=error instanceof TypeError}
            ccCheck(receiver[style]===builder&&constructorError,"borrowed cache and nonconstructor");
            rows.push({style,output:builder.call({level:0},"x"),constructorError,
                receiverIgnored:builder.call(null,"x")===builder("x")});
        }
        return rows;
    }
    case "primitive-receiver": {
        const root=make({level:1}),rows=[];
        for(const style of ["red","cyan"]) {
            const get=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(root),style).get;
            for(const receiver of [null,undefined,7,"x",true,Symbol("s")]) {
                let typeError=false;try{get.call(receiver)}catch(error){typeError=error instanceof TypeError}
                ccCheck(typeError,"style accessor requires cacheable receiver");
                rows.push({style,kind:receiver===null?"null":typeof receiver,typeError});
            }
        }
        return rows;
    }
    case "generator-capture": {
        const root=make({level:1}),other=make({level:2}),keys=ccSymbols(root);
        Object.defineProperty(root,keys.GENERATOR,{get(){events.push("GENERATOR");return other;}});
        const red=root.red,cyan=root.cyan;
        other.level=0;
        return {events,disabled:[red("x"),cyan("x")],levels:[root.level,red.level,cyan.level]};
    }
    case "symbol-level": {
        const root=make({level:1}),keys=ccSymbols(root),red=root.red,cyan=root.cyan;
        Object.defineProperty(root,keys.LEVEL,{configurable:true,get(){
            events.push("LEVEL");return {[Symbol.toPrimitive](hint){events.push(hint);return 1;}};
        }});
        return {outputs:[red("x"),cyan("x")],events};
    }
    case "symbol-level-throw": {
        const root=make({level:1}),keys=ccSymbols(root),red=root.red,cyan=root.cyan,reason={};
        Object.defineProperty(root,keys.LEVEL,{configurable:true,get(){events.push("LEVEL");throw reason;}});
        const rows=[];
        for(const builder of [red,cyan]) {
            let same=false;
            try{builder({[Symbol.toPrimitive](hint){events.push("coerce:"+hint);return "x";}})}
            catch(error){same=error===reason}
            ccCheck(same,"level lookup raw throw survives after input coercion");rows.push(same);
        }
        return {rows,events};
    }
    case "string-method-order": {
        const root=make({level:1}),builder=root.red.cyan;
        const originals={includes:String.prototype.includes,indexOf:String.prototype.indexOf,slice:String.prototype.slice};
        let output;
        try{
            for(const method of Object.keys(originals)) String.prototype[method]=function(...args){
                events.push([method,...args]);return Reflect.apply(originals[method],this,args);
            };
            output=builder("a\x1b[39mb\r\nc");
        }finally{for(const method of Object.keys(originals))String.prototype[method]=originals[method]}
        return {output,events};
    }
    case "string-method-throw": {
        const rows=[],reason={};
        for(const style of ["red","cyan"]) for(const method of ["includes","indexOf","slice"]) {
            const root=make({level:1}),saved=String.prototype[method];let same=false;
            try{String.prototype[method]=function(){throw reason};root[style]("a\x1b[39mb\nc")}
            catch(error){same=error===reason}
            finally{String.prototype[method]=saved}
            ccCheck(same,"live String method throw remains original");rows.push({style,method,same});
        }
        return rows;
    }
    case "string-method-reentry": {
        const root=make({level:1}),saved=String.prototype.includes;let inside=false,output,inner;
        try{
            String.prototype.includes=function(...args){
                events.push(inside?"inner includes":"outer includes");
                if(!inside){inside=true;inner=root.cyan("nested");inside=false;}
                return Reflect.apply(saved,this,args);
            };
            output=root.red("outer");
        }finally{String.prototype.includes=saved}
        return {output,inner,events};
    }
    case "native-data": {
        const rows=[];
        for(const style of ["red","cyan"]) {
            const root=make({level:1}),reason=__ccHooks.freshPrivateData();let same=false,ordinary=false;
            try{root[style]({[Symbol.toPrimitive](){throw reason;}})}
            catch(error){same=error===reason;ordinary=__ccHooks.isUnmarkedPrivateData(error)}
            ccCheck(same&&ordinary,"actual private DATA stays ordinary");
            rows.push({style,same,ordinary});
        }
        return rows;
    }
    case "notify-colors": {
        const root=make({level:1}),warnings=[],saved=Object.getOwnPropertyDescriptor(globalThis,"console");
        const output={error(value){ccCheck(this===output,"original console error receiver");warnings.push(value)}};
        try{
            globalThis.console=output;
            for(const mode of ["print","rpc","interactive"]) {
                const notify=__ccNotifyFactory({mode},root);
                for(const type of [undefined,"error","warning","info","other",null]) notify(mode+":"+type,type);
            }
        }finally{Object.defineProperty(globalThis,"console",saved)}
        ccCheck(warnings.length===12,"interactive suppresses notifications");
        return warnings;
    }
    case "notify-order": {
        const root=make({level:1}),paint=make({level:1}).red;
        Object.defineProperty(root,"red",{get(){events.push("red get");return paint}});
        const options={get mode(){events.push("mode");return "print";}};
        const output={get error(){events.push("error get");return function(value){
            ccCheck(this===output,"captured console error receiver");events.push("error:"+value);
        }}};
        const saved=Object.getOwnPropertyDescriptor(globalThis,"console");
        try{
            globalThis.console=output;
            __ccNotifyFactory(options,root)({[Symbol.toPrimitive](hint){
                events.push("coerce:"+hint);globalThis.console={error(){throw Error("late console")}};return "detail";
            }},"error");
        }finally{Object.defineProperty(globalThis,"console",saved)}
        return events;
    }
    default: throw new Error("Unknown foreground control: "+name);
    }
}
function ccFreshFatal(style, phase) {
    const root=__ccRoot.constructor({level:1});
    const keys=ccSymbols(root);
    if(phase==="getter")Object.defineProperty(root,keys.STYLER,{get(){return __ccHooks.raiseNativeFatal()}});
    try{
        if(phase==="getter")root[style];
        else root[style]({[Symbol.toPrimitive](){return __ccHooks.raiseNativeFatal()}});
    }catch(error){__ccHooks.visit(1);throw error}
    __ccHooks.visit(2);
}
