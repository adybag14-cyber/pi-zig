// Additive genuine caller cases. The original25 observer is unchanged.
// The native VM supplies real flagged/private Error DATA via makeReason;
// original Node supplies an ordinary Error. The Source algorithm must perform
// the same cleanup and preserve the exact rejected input in either case.
export async function observeCorrections(api, sqlite, makeReason) {
  const rows=[];
  async function record(id,action){const trace=[];try{rows.push({id,trace,value:await action(trace)})}catch(error){rows.push({id,trace,error:{name:error?.name,code:error?.code,message:error?.message}})}}
  await record('rejected-data-still-rolls-back',async trace=>{
    const raw=new sqlite.DatabaseSync(':memory:'),db=new api.NodeSqliteDatabase(raw);let reason,handle;
    const exec=raw.exec;
    raw.exec=function(sql){trace.push(sql);return Reflect.apply(exec,this,[sql])};
    try{
      await db.exec('CREATE TABLE owned(n INTEGER)');
      let caught;
      try{await db.transaction(async tx=>{handle=tx;await tx.run('INSERT INTO owned VALUES(?)',1);reason=makeReason();return Promise.reject(reason)})}catch(error){caught=error}
      const row=await db.get('SELECT count(*) AS n FROM owned');
      return{same:caught===reason,active:handle.scope.active,n:row.n,pending:db.access.pending};
    }finally{await db.close()}
  });
  await record('rejected-configuration-data-still-closes',async trace=>{
    const prototype=api.NodeSqliteDatabase.prototype;
    const own=Object.getOwnPropertyDescriptor(prototype,'exec'),execute=prototype.exec;
    const closeDescriptor=Object.getOwnPropertyDescriptor(sqlite.DatabaseSync.prototype,'close');
    let reason,closeCalls=0,closed=false;
    try{
      Object.defineProperty(prototype,'exec',{configurable:true,writable:true,value:function(sql){
        if(sql==='PRAGMA journal_mode = WAL'){trace.push(sql);reason=makeReason();return Promise.reject(reason)}
        return Reflect.apply(execute,this,[sql]);
      }});
      Object.defineProperty(sqlite.DatabaseSync.prototype,'close',{...closeDescriptor,value:function(){
        closeCalls++;trace.push('actual-close');const result=Reflect.apply(closeDescriptor.value,this,[]);closed=!this.isOpen;return result;
      }});
      let caught;try{await api.openNodeSqliteDatabase(':memory:')}catch(error){caught=error}
      return{same:caught===reason,closeCalls,closed};
    }finally{
      if(own)Object.defineProperty(prototype,'exec',own);else delete prototype.exec;
      Object.defineProperty(sqlite.DatabaseSync.prototype,'close',closeDescriptor);
    }
  });
  await record('superclass-selected-before-Map-construction',async trace=>{
    const Ctor=api.NodeSqliteDatabase,base=Object.getPrototypeOf(Ctor),MapCtor=globalThis.Map;
    const raw=new sqlite.DatabaseSync(':memory:');let db;
    function OtherBase(){trace.push('wrong-base');this.wrongBase=true}
    try{
      globalThis.Map=new Proxy(MapCtor,{construct(target,args,newTarget){trace.push('Map');Object.setPrototypeOf(Ctor,OtherBase);return Reflect.construct(target,args,newTarget)}});
      db=new Ctor(raw);
      return{database:db.database===raw,statements:db.statements instanceof MapCtor,wrongBase:db.wrongBase===true};
    }finally{globalThis.Map=MapCtor;Object.setPrototypeOf(Ctor,base);if(db)await db.close();else raw.close()}
  });
  await record('queue-primitive-newtarget-prototype-fallback',async()=>{
    const raw=new sqlite.DatabaseSync(':memory:'),db=new api.NodeSqliteDatabase(raw);
    try{
      const Queue=db.access.constructor;function NewTarget(){}NewTarget.prototype=13;
      const queue=Reflect.construct(Queue,[],NewTarget);
      return{intrinsic:Object.getPrototypeOf(queue)===Object.prototype,pending:queue.pending,tail:queue.tail instanceof Promise,own:Object.keys(queue)};
    }finally{await db.close()}
  });
  return{authority:'actual-c268-Chord-Node-SQLite-corrections',rows};
}
