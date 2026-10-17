// Verification input only. Both original and native collectors must supply the
// actual class and the SAME real Durable Object storage capability contract.
// No storage emulator, Node SQLite wrapper, canned cursor or D1 alias exists.
export default async function observeCloudflare({DurableObjectSqliteDatabase:Database},storage,label){
  if(typeof label!=='string'||!/^[A-Za-z_][A-Za-z0-9_]{0,40}$/.test(label))throw new Error('owned fixture table label required');
  const table=`"${label}"`,log=[],rows=[];
  let lastNextRow,lastAllRows;
  const sql=storage.sql;
  const observedSql=new Proxy(sql,{get(target,key,receiver){
    const value=Reflect.get(target,key,target);
    if(key!=='exec')return value;
    return function(...args){
      log.push(['exec',args[0],args.slice(1).map(value=>value instanceof ArrayBuffer?['ArrayBuffer',...new Uint8Array(value)]:typeof value==='bigint'?['bigint',String(value)]:value)]);
      const cursor=Reflect.apply(value,target,args);
      return new Proxy(cursor,{get(target,key,receiver){
        const method=Reflect.get(target,key,target);
        if(key==='next')return function(...args){log.push(['next']);const result=Reflect.apply(method,target,args);if(!result.done)lastNextRow=result.value;return result};
        if(key==='toArray')return function(...args){log.push(['toArray']);lastAllRows=Reflect.apply(method,target,args);return lastAllRows};
        return method;
      }});
    };
  }});
  const observed=new Proxy(storage,{get(target,key,receiver){
    if(key==='sql')return observedSql;
    const value=Reflect.get(target,key,target);
    if(key==='transaction')return function(...args){log.push(['transaction']);return Reflect.apply(value,target,args)};
    return value;
  }});
  const database=new Database(observed),other=new Database(observed);
  const proto=Database.prototype,base=Object.getPrototypeOf(proto),serial=database.queue;
  const shape=value=>({name:value.name,length:value.length,async:Object.getPrototypeOf(value).constructor.name,prototype:Object.hasOwn(value,'prototype')});
  rows.push({case:'class-and-shared-queue',exports:Object.keys({DurableObjectSqliteDatabase:Database}),class:shape(Database),constructorBase:Object.getPrototypeOf(Database).name,baseConstructor:base.constructor.name,basePrototype:Object.getPrototypeOf(base)===Object.prototype,own:Object.keys(database),storage:database.storage===observed,shared:other.queue===serial,queueConstructor:serial.constructor.name,queueOwn:Object.keys(serial),queueMethods:['run','hold','enqueue'].map(name=>[name,shape(Object.getPrototypeOf(serial)[name])]),databaseMethods:['exec','run','get','all','transaction','close'].map(name=>[name,shape(proto[name]),Object.getOwnPropertyDescriptor(proto,name)]).map(([name,shape,descriptor])=>[name,shape,{enumerable:descriptor.enumerable,writable:descriptor.writable,configurable:descriptor.configurable}]),executorMethods:['exec','run','get','all','check'].map(name=>[name,shape(base[name])])});
  await database.exec(`CREATE TABLE ${table} (id INTEGER PRIMARY KEY, data BLOB, n INTEGER)`);
  const bytes=new Uint8Array([9,1,2,3,8]),slice=bytes.subarray(1,4);
  const write=database.run(`INSERT INTO ${table} (id,data,n) VALUES (?,?,?)`,1,slice,7n);
  const immediate=storage.sql.exec(`SELECT id,n FROM ${table} ORDER BY id`).next();
  bytes.fill(0);rows.push({case:'idle-exec-before-promise',promise:write instanceof Promise,immediate:immediate.value});
  rows.push({case:'run-return',value:await write});
  const first=await database.get(`SELECT id,data,n FROM ${table} ORDER BY id`);
  rows.push({case:'get-first-row-in-place',same:first===lastNextRow,row:{id:first.id,data:[...first.data],dataType:first.data.constructor.name,n:first.n},log:log.splice(0)});
  await database.run(`INSERT INTO ${table} (id,data,n) VALUES (?,?,?)`,2,new Uint8Array([4]),8);
  const all=await database.all(`SELECT id,data,n FROM ${table} ORDER BY id`);
  rows.push({case:'all-map-row-identities',newArray:all!==lastAllRows,sameRows:all.every((value,index)=>value===lastAllRows[index]),rows:all.map(value=>({id:value.id,data:[...value.data],n:value.n})),log:log.splice(0)});
  rows.push({case:'missing-get',value:await database.get(`SELECT id FROM ${table} WHERE id=-1`),log:log.splice(0)});
  for(const value of [9007199254740991n,-9007199254740991n,9007199254740992n,-9007199254740992n]){
    const before=log.length;let result;
    try{await database.run(`INSERT INTO ${table} (id,n) VALUES (?,?)`,10,value);await database.run(`DELETE FROM ${table} WHERE id=10`);result={resolved:true}}catch(error){result={name:error.name,message:error.message}}
    rows.push({case:'bigint-bound',value:String(value),result,execCalls:log.slice(before).filter(value=>value[0]==='exec').length});
  }
  const reason={ownedRollback:true},order=[];let handle,release;
  const gate=new Promise(resolve=>{release=resolve});
  const held=database.transaction(async transaction=>{handle=transaction;await transaction.run(`INSERT INTO ${table} (id,n) VALUES (?,?)`,20,20);await gate;order.push('callback');throw reason});
  const outside=other.run(`INSERT INTO ${table} (id,n) VALUES (?,?)`,21,21).then(()=>order.push('outside'));
  const read=other.all(`SELECT id FROM ${table} WHERE id>=20 ORDER BY id`);
  const closed=database.close().then(()=>order.push('close'));
  release();let caught;try{await held}catch(error){caught=error}
  await outside;const readRows=await read;await closed;
  rows.push({case:'rollback-shared-queue-close',sameReason:caught===reason,rows:readRows,order,active:handle.active,handleOwn:Object.keys(handle),transactionConstructor:handle.constructor.name,transactionBase:Object.getPrototypeOf(Object.getPrototypeOf(handle))===base});
  try{await handle.run(`INSERT INTO ${table} (id) VALUES (?)`,22);rows.push({case:'inactive-handle',resolved:true})}catch(error){rows.push({case:'inactive-handle',name:error.name,message:error.message})}
  let sync=false,invalid;try{invalid=database.exec(`SELECT FROM ${table}`)}catch(error){sync=true;invalid=Promise.reject(error)}
  try{await invalid;rows.push({case:'sql-error-async',sync,resolved:true})}catch(error){rows.push({case:'sql-error-async',sync,name:error.name,message:error.message})}
  rows.push({case:'after-rejection',rows:await other.all(`SELECT id FROM ${table} WHERE id>=20 ORDER BY id`),pending:serial.pending});
  await database.exec(`DROP TABLE ${table}`);await database.close();return rows;
}
