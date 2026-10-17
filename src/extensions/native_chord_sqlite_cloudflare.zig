//! Actual c268 chord/sqlite/cloudflare Durable Object adapter.
//! The caller supplies the real storage capability; this leaf contains no SQL
//! emulator, D1 prepare alias, Node host or durable backend substitution.
const h=@import("native_chord_sqlite_cloudflare_values.zig");
const v=h.v;
const c=h.c;
const f=h.functions;
const af=h.af;
const Op=enum(i32){exec,run,get,all};
fn readOp(engine:*v.em.Engine,value:c.JSValue)!Op{var code:i32=0;if(c.JS_ToInt32(engine.context,&code,value)<0)return v.js.capture(engine);return @enumFromInt(code);}
fn arg(args:[]const c.JSValue,index:usize)c.JSValue{return if(index<args.len)args[index]else c.pi_js_undefined();}
fn dup(engine:*v.em.Engine,value:c.JSValue)c.JSValue{return c.JS_DupValue(engine.context,value);}
fn nullObject(engine:*v.em.Engine)!c.JSValue{return engine.checked(c.JS_NewObjectProto(engine.context,c.pi_js_null()));}
fn method(engine:*v.em.Engine,prototype:c.JSValue,name:[*:0]const u8,length:c_int,callback:f.Callback,roots:[]const c.JSValue)!void{
    const function=try f.createMethod(engine,name,length,callback,roots);defer engine.freeValue(function);try h.define(engine,prototype,name,function,c.JS_PROP_CONFIGURABLE|c.JS_PROP_WRITABLE);
}
fn asyncMethod(engine:*v.em.Engine,prototype:c.JSValue,name:[*:0]const u8,op:Op,owner:c.JSValue)!void{
    const function=try af.createResumable(engine,name,1,execute,&.{c.JS_NewInt32(engine.context,@intFromEnum(op)),owner});defer engine.freeValue(function);try h.define(engine,prototype,name,function,c.JS_PROP_CONFIGURABLE|c.JS_PROP_WRITABLE);
}
fn objectFor(engine:*v.em.Engine,target:c.JSValue)!c.JSValue{
    // Normalize the genuine prototype getter's pending event BEFORE allocation.
    const prototype=try h.get(engine,target,"prototype");defer engine.freeValue(prototype);
    return h.current(engine,try engine.checked(if(c.JS_IsObject(prototype))c.JS_NewObjectProto(engine.context,prototype)else c.JS_NewObject(engine.context)));
}
fn superConstruct(engine:*v.em.Engine,owner:c.JSValue,class_name:[*:0]const u8,target:c.JSValue,args:[]const c.JSValue)!c.JSValue{
    const constructor=try h.get(engine,owner,class_name);defer engine.freeValue(constructor);
    const base=try h.current(engine,try engine.checked(c.JS_GetPrototype(engine.context,constructor)));defer engine.freeValue(base);
    return h.current(engine,try engine.checked(c.JS_CallConstructor2(engine.context,base,target,@intCast(args.len),@constCast(args.ptr))));
}
fn executorConstruct(engine:*v.em.Engine,target:c.JSValue,args:[]const c.JSValue,_:c.JSValue)!c.JSValue{
    const instance=try objectFor(engine,target);errdefer engine.freeValue(instance);try h.field(engine,instance,"storage",c.pi_js_undefined());try h.set(engine,instance,"storage",arg(args,0));return instance;
}
fn databaseConstruct(engine:*v.em.Engine,target:c.JSValue,args:[]const c.JSValue,owner:c.JSValue)!c.JSValue{
    const storage=arg(args,0);const instance=try superConstruct(engine,owner,"databaseClass",target,&.{storage});errdefer engine.freeValue(instance);
    try h.field(engine,instance,"queue",c.pi_js_undefined());const queue=try queueFor(engine,owner,storage);defer engine.freeValue(queue);try h.set(engine,instance,"queue",queue);return instance;
}
fn transactionConstruct(engine:*v.em.Engine,target:c.JSValue,args:[]const c.JSValue,owner:c.JSValue)!c.JSValue{
    const instance=try superConstruct(engine,owner,"transactionClass",target,args);errdefer engine.freeValue(instance);try h.field(engine,instance,"active",c.JS_NewBool(engine.context,true));return instance;
}
fn queueConstruct(engine:*v.em.Engine,target:c.JSValue,_:[]const c.JSValue,_:c.JSValue)!c.JSValue{
    const instance=try objectFor(engine,target);errdefer engine.freeValue(instance);
    const tail=try promiseMethod(engine,"resolve",&.{});defer engine.freeValue(tail);try h.field(engine,instance,"tail",tail);try h.field(engine,instance,"pending",c.JS_NewInt32(engine.context,0));return instance;
}
fn promiseMethod(engine:*v.em.Engine,name:[*:0]const u8,args:[]const c.JSValue)!c.JSValue{
    const promise=try h.global(engine,"Promise");defer engine.freeValue(promise);return h.invoke(engine,promise,name,args);
}
fn queueFor(engine:*v.em.Engine,owner:c.JSValue,storage:c.JSValue)!c.JSValue{
    const queues=try h.get(engine,owner,"storageQueues");defer engine.freeValue(queues);
    const previous=try h.invoke(engine,queues,"get",&.{storage});if(!c.JS_IsUndefined(previous))return previous;engine.freeValue(previous);
    const constructor=try h.get(engine,owner,"queueClass");defer engine.freeValue(constructor);
    const queue=try h.new(engine,constructor,&.{});errdefer engine.freeValue(queue);
    const ignored=try h.invoke(engine,queues,"set",&.{storage,queue});engine.freeValue(ignored);return queue;
}
fn baseCheck(_: *v.em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return c.pi_js_undefined();}
fn transactionCheck(engine:*v.em.Engine,receiver:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const active=try h.get(engine,receiver,"active");defer engine.freeValue(active);
    if(c.JS_ToBool(engine.context,active)==0)return h.textError(engine,"Error","SQLite transaction handle is no longer active");return c.pi_js_undefined();
}
fn queueRun(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const pending=try h.get(engine,receiver,"pending");const greater=h.binary(engine,6,pending,c.JS_NewInt32(engine.context,0)) catch|err|{engine.freeValue(pending);return err;};engine.freeValue(pending);
    const queued=c.JS_ToBool(engine.context,greater)!=0;engine.freeValue(greater);if(queued)return h.invoke(engine,receiver,"enqueue",&.{arg(args,0)});
    const generation=engine.native_allocation_generation;
    return immediate(engine,arg(args,0)) catch|err|{
        const reason=try h.caught(engine,err,generation);defer engine.freeValue(reason);return promiseMethod(engine,"reject",&.{reason});
    };
}
fn immediate(engine:*v.em.Engine,operation:c.JSValue)!c.JSValue{
    // Resolve callee/receiver before evaluating operation(), exactly as Source.
    const promise=try h.global(engine,"Promise");defer engine.freeValue(promise);const resolve=try h.get(engine,promise,"resolve");defer engine.freeValue(resolve);
    const value=try h.call(engine,operation,c.pi_js_undefined(),&.{});defer engine.freeValue(value);return h.call(engine,resolve,promise,&.{value});
}
fn queueHold(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{try h.pending(engine);return h.invoke(engine,receiver,"enqueue",&.{arg(args,0)});}
fn updatePending(engine:*v.em.Engine,queue:c.JSValue,increment:bool)!void{
    const old=try h.get(engine,queue,"pending");defer engine.freeValue(old);
    const value=try h.current(engine,try engine.checked(if(increment)c.JS_PiIncrement(engine.context,old)else c.JS_PiDecrement(engine.context,old)));defer engine.freeValue(value);try h.set(engine,queue,"pending",value);
}
fn decrement(engine:*v.em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{try h.pending(engine);try updatePending(engine,roots[0],false);return c.pi_js_undefined();}
fn empty(engine:*v.em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{try h.pending(engine);return c.pi_js_undefined();}
fn queueEnqueue(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);try updatePending(engine,receiver,true);
    const result=try enqueueResult(engine,receiver,arg(args,0));defer engine.freeValue(result);
    const tail=try healedTail(engine,result);defer engine.freeValue(tail);try h.set(engine,receiver,"tail",tail);return dup(engine,result);
}
fn enqueueResult(engine:*v.em.Engine,queue:c.JSValue,operation:c.JSValue)!c.JSValue{
    const then_result=try tailThen(engine,queue,operation);defer engine.freeValue(then_result);
    const finalizer=try h.get(engine,then_result,"finally");defer engine.freeValue(finalizer);
    const callback=try f.createArrow(engine,"",0,decrement,&.{queue});defer engine.freeValue(callback);return h.call(engine,finalizer,then_result,&.{callback});
}
fn tailThen(engine:*v.em.Engine,queue:c.JSValue,operation:c.JSValue)!c.JSValue{
    const tail=try h.get(engine,queue,"tail");defer engine.freeValue(tail);return h.invoke(engine,tail,"then",&.{operation});
}
fn healedTail(engine:*v.em.Engine,result:c.JSValue)!c.JSValue{
    const then=try h.get(engine,result,"then");defer engine.freeValue(then);
    const success=try f.createArrow(engine,"",0,empty,&.{});defer engine.freeValue(success);const failure=try f.createArrow(engine,"",0,empty,&.{});defer engine.freeValue(failure);return h.call(engine,then,result,&.{success,failure});
}
fn bindValue(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const value=arg(args,0);const typed=try instanceOfGlobal(engine,value,"Uint8Array");if(typed){const sliced=try h.invoke(engine,value,"slice",&.{});defer engine.freeValue(sliced);return h.get(engine,sliced,"buffer");}
    if(!c.JS_IsBigInt(value))return dup(engine,value);
    if(try outsideSafe(engine,value,"MIN_SAFE_INTEGER",4) or try outsideSafe(engine,value,"MAX_SAFE_INTEGER",6)){
        const constructor=try h.global(engine,"RangeError");defer engine.freeValue(constructor);
        var s:v.Scope=.{.engine=engine};defer s.deinit();const prefix=try s.text("Durable Object SQL cannot bind ");const decimal=try s.own(try h.current(engine,try engine.checked(c.JS_ToString(engine.context,value))));
        const first=try s.own(try h.binary(engine,0,prefix,decimal));const message=try s.own(try h.binary(engine,0,first,try s.text(" without losing precision")));const reason=try s.own(try h.new(engine,constructor,&.{message}));return h.throw(engine,reason);
    }
    const number=try h.global(engine,"Number");defer engine.freeValue(number);return h.call(engine,number,c.pi_js_undefined(),&.{value});
}
fn outsideSafe(engine:*v.em.Engine,value:c.JSValue,field:[*:0]const u8,op:c_int)!bool{
    const bound=try safeBound(engine,field);defer engine.freeValue(bound);const test=try h.binary(engine,op,value,bound);defer engine.freeValue(test);return c.JS_ToBool(engine.context,test)!=0;
}
fn safeBound(engine:*v.em.Engine,name:[*:0]const u8)!c.JSValue{
    const bigint=try h.global(engine,"BigInt");defer engine.freeValue(bigint);const bound=try numberBound(engine,name);defer engine.freeValue(bound);return h.call(engine,bigint,c.pi_js_undefined(),&.{bound});
}
fn numberBound(engine:*v.em.Engine,name:[*:0]const u8)!c.JSValue{
    const number=try h.global(engine,"Number");defer engine.freeValue(number);return h.get(engine,number,name);
}
fn instanceOfGlobal(engine:*v.em.Engine,value:c.JSValue,name:[*:0]const u8)!bool{
    const constructor=try h.global(engine,name);defer engine.freeValue(constructor);const result=c.JS_IsInstanceOf(engine.context,value,constructor);if(result<0)return v.js.capture(engine);try h.pending(engine);return result!=0;
}
fn convertRow(engine:*v.em.Engine,row:c.JSValue)!c.JSValue{
    var iterator=try @import("native_chord_sqlite_cloudflare_row_keys.zig").Iterator.init(engine,row);defer iterator.deinit();
    while(try iterator.next())|key|{defer engine.freeValue(key);const value=try h.current(engine,try v.js.getKey(engine,row,key));defer engine.freeValue(value);
        if(try instanceOfGlobal(engine,value,"ArrayBuffer")){
            const constructor=try h.global(engine,"Uint8Array");defer engine.freeValue(constructor);const converted=try h.new(engine,constructor,&.{value});defer engine.freeValue(converted);
            try v.js.setKey(engine,row,key,converted);try h.pending(engine);
        }
    }
    return dup(engine,row);
}
fn rowMapper(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{try h.pending(engine);return convertRow(engine,arg(args,0));}
fn execCursor(engine:*v.em.Engine,owner:c.JSValue,receiver:c.JSValue,sql:c.JSValue,params:?c.JSValue)!c.JSValue{
    const sql_binding=try sqlBinding(engine,receiver);defer engine.freeValue(sql_binding);const exec=try h.get(engine,sql_binding,"exec");defer engine.freeValue(exec);
    if(params)|arguments|{
        const bindings=try bindParams(engine,owner,arguments);defer engine.freeValue(bindings);return h.callSpread(engine,exec,sql_binding,sql,bindings);
    }
    return h.call(engine,exec,sql_binding,&.{sql});
}
fn sqlBinding(engine:*v.em.Engine,receiver:c.JSValue)!c.JSValue{
    const storage=try h.get(engine,receiver,"storage");defer engine.freeValue(storage);return h.get(engine,storage,"sql");
}
fn cursorResult(engine:*v.em.Engine,owner:c.JSValue,receiver:c.JSValue,sql:c.JSValue,params:c.JSValue,name:[*:0]const u8)!c.JSValue{
    const cursor=try execCursor(engine,owner,receiver,sql,params);defer engine.freeValue(cursor);return h.invoke(engine,cursor,name,&.{});
}
fn bindParams(engine:*v.em.Engine,owner:c.JSValue,params:c.JSValue)!c.JSValue{
    // bindValue is a single module-level declaration, retained by each method's
    // function captures, not a new per-row/per-argument callback identity.
    const mapper=try h.get(engine,owner,"bindValue");defer engine.freeValue(mapper);
    return h.invoke(engine,params,"map",&.{mapper});
}
fn execute(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue,_:*c.JSValue,completion:af.Completion,_:c.JSValue)!af.Action{
    if(completion!=.start)return error.CloudflareUnexpectedExecutorResume;const generation=engine.native_allocation_generation;
    const op=try readOp(engine,roots[0]);return .{.returned=executeBody(engine,roots[1],receiver,args,op) catch|err|return h.reject(engine,err,generation)};
}
fn executeBody(engine:*v.em.Engine,owner:c.JSValue,receiver:c.JSValue,args:[]const c.JSValue,op:Op)!c.JSValue{
    try h.pending(engine);
    const params=if(op==.exec)c.pi_js_undefined()else try h.argsArray(engine,if(args.len>0)args[1..]else &.{});defer engine.freeValue(params);
    const check=try h.invoke(engine,receiver,"check",&.{});engine.freeValue(check);
    switch(op){
        .exec,.run=>{const ignored=try execCursor(engine,owner,receiver,arg(args,0),if(op==.exec)null else params);engine.freeValue(ignored);return c.pi_js_undefined();},
        .get=>{
            const result=try cursorResult(engine,owner,receiver,arg(args,0),params,"next");defer engine.freeValue(result);const done=try h.get(engine,result,"done");const finished=c.JS_ToBool(engine.context,done)!=0;engine.freeValue(done);if(finished)return c.pi_js_undefined();
            const row=try h.get(engine,result,"value");defer engine.freeValue(row);return convertRow(engine,row);
        },
        .all=>{
            const rows=try cursorResult(engine,owner,receiver,arg(args,0),params,"toArray");defer engine.freeValue(rows);const map=try h.get(engine,rows,"map");defer engine.freeValue(map);const mapper=try f.createArrow(engine,"",1,rowMapper,&.{});defer engine.freeValue(mapper);return h.call(engine,map,rows,&.{mapper});
        },
    }
}
fn operation(engine:*v.em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const op=try readOp(engine,roots[2]);const home=try h.get(engine,roots[0],"databasePrototype");defer engine.freeValue(home);
    const callee=try h.superGet(engine,home,roots[1],@tagName(op).ptr);defer engine.freeValue(callee);
    if(op==.exec)return h.call(engine,callee,roots[1],&.{roots[3]});return h.callSpread(engine,callee,roots[1],roots[3],roots[4]);
}
fn databaseMethod(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const op=try readOp(engine,roots[1]);
    const params=if(op==.exec)c.pi_js_undefined()else try h.argsArray(engine,if(args.len>0)args[1..]else &.{});defer engine.freeValue(params);
    const queue=try h.get(engine,receiver,"queue");defer engine.freeValue(queue);const run=try h.get(engine,queue,"run");defer engine.freeValue(run);
    const callback=try f.createArrow(engine,"",0,operation,&.{roots[0],receiver,roots[1],arg(args,0),params});defer engine.freeValue(callback);return h.call(engine,run,queue,&.{callback});
}
fn close(engine:*v.em.Engine,receiver:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const queue=try h.get(engine,receiver,"queue");defer engine.freeValue(queue);const run=try h.get(engine,queue,"run");defer engine.freeValue(run);const callback=try f.createArrow(engine,"",0,empty,&.{});defer engine.freeValue(callback);return h.call(engine,run,queue,&.{callback});
}
fn transaction(engine:*v.em.Engine,receiver:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const queue=try h.get(engine,receiver,"queue");defer engine.freeValue(queue);const hold=try h.get(engine,queue,"hold");defer engine.freeValue(hold);
    const callback=try f.createArrow(engine,"",0,transactionOperation,&.{roots[0],receiver,arg(args,0)});defer engine.freeValue(callback);return h.call(engine,hold,queue,&.{callback});
}
fn transactionOperation(engine:*v.em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.pending(engine);const storage=try h.get(engine,roots[1],"storage");defer engine.freeValue(storage);const callee=try h.get(engine,storage,"transaction");defer engine.freeValue(callee);
    const closure=try af.createResumableArrow(engine,"",0,transactionClosure,roots,roots[1]);defer engine.freeValue(closure);return h.call(engine,callee,storage,&.{closure});
}
fn transactionClosure(engine:*v.em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue,state:*c.JSValue,completion:af.Completion,input:c.JSValue)!af.Action{
    const generation=engine.native_allocation_generation;
    return transactionBody(engine,roots,state,completion,input) catch|err|h.reject(engine,err,generation);
}
fn transactionBody(engine:*v.em.Engine,roots:[]const c.JSValue,state:*c.JSValue,completion:af.Completion,input:c.JSValue)!af.Action{
    try h.pending(engine);
    if(completion==.start){
        const constructor=try h.get(engine,roots[0],"transactionClass");defer engine.freeValue(constructor);const storage=try h.get(engine,roots[1],"storage");defer engine.freeValue(storage);const handle=try h.new(engine,constructor,&.{storage});defer engine.freeValue(handle);
        const job=try nullObject(engine);defer engine.freeValue(job);af.replaceState(engine,state,dup(engine,job));try h.field(engine,job,"handle",handle);
        const boundary=engine.native_allocation_generation;
        const value=h.call(engine,roots[2],c.pi_js_undefined(),&.{handle}) catch|err|{
            const reason=try h.caught(engine,err,boundary);defer engine.freeValue(reason);try h.set(engine,handle,"active",c.JS_NewBool(engine.context,false));return .{.thrown=dup(engine,reason)};
        };
        return .{.awaited=value};
    }
    const handle=try h.get(engine,state.*,"handle");defer engine.freeValue(handle);
    // Await rejection input is DATA. Old private tags/uncatchable flags do not
    // identify an actual current native event and cannot skip Source finally.
    // Current pending/captured events are handled by h.pending and the outer
    // exact invocation boundary; a same-object new throw takes that path.
    try h.set(engine,handle,"active",c.JS_NewBool(engine.context,false));return if(completion==.rejected).{.thrown=dup(engine,input)}else .{.returned=dup(engine,input)};
}
/// Namespace owner calls once per realm, then reexports this SAME class from
/// chord/sqlite/cloudflare and durable/storage/sqlite/cloudflare. No bindings
/// are probed at factory time; storage is supplied only to the real constructor.
pub fn create(engine:*v.em.Engine)!c.JSValue{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;try h.pending(engine);
    var s:v.Scope=.{.engine=engine};defer s.deinit();const owner=try s.own(try nullObject(engine));
    const queue_prototype=try s.object();const queue_class=try s.own(try h.class(engine,"SerialQueue",0,queue_prototype,null,queueConstruct,owner));try h.field(engine,owner,"queueClass",queue_class);
    try method(engine,queue_prototype,"run",1,queueRun,&.{});try method(engine,queue_prototype,"hold",1,queueHold,&.{});try method(engine,queue_prototype,"enqueue",1,queueEnqueue,&.{});
    const weak=try s.own(try h.global(engine,"WeakMap"));const queues=try s.own(try h.new(engine,weak,&.{}));try h.field(engine,owner,"storageQueues",queues);
    const binding_mapper=try s.own(try f.create(engine,"bindValue",1,bindValue,&.{}));try h.field(engine,owner,"bindValue",binding_mapper);
    const executor_prototype=try s.object();const executor_class=try s.own(try h.class(engine,"DurableObjectSqliteExecutor",1,executor_prototype,null,executorConstruct,owner));
    inline for(.{Op.exec,Op.run,Op.get,Op.all})|op|try asyncMethod(engine,executor_prototype,@tagName(op).ptr,op,owner);try method(engine,executor_prototype,"check",0,baseCheck,&.{});
    const tx_prototype=try s.own(try engine.checked(c.JS_NewObjectProto(engine.context,executor_prototype)));const tx_class=try s.own(try h.class(engine,"DurableObjectSqliteTransaction",0,tx_prototype,executor_class,transactionConstruct,owner));try h.field(engine,owner,"transactionClass",tx_class);try method(engine,tx_prototype,"check",0,transactionCheck,&.{});
    const db_prototype=try s.own(try engine.checked(c.JS_NewObjectProto(engine.context,executor_prototype)));try h.field(engine,owner,"databasePrototype",db_prototype);
    const db_class=try s.own(try h.class(engine,"DurableObjectSqliteDatabase",1,db_prototype,executor_class,databaseConstruct,owner));try h.field(engine,owner,"databaseClass",db_class);
    inline for(.{Op.exec,Op.run,Op.get,Op.all})|op|try method(engine,db_prototype,@tagName(op).ptr,1,databaseMethod,&.{owner,c.JS_NewInt32(engine.context,@intFromEnum(op))});try method(engine,db_prototype,"transaction",1,transaction,&.{owner});try method(engine,db_prototype,"close",0,close,&.{});
    const exports=try s.object();try h.field(engine,exports,"DurableObjectSqliteDatabase",db_class);return dup(engine,exports);
}
