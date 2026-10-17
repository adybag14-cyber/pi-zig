// Caller-only observations of the actual c268 adapter and actual node:sqlite.
// No candidate import, reference implementation or expected output is embedded.
export async function observeNodeSqlite(api, sqlite, ownedFile) {
  if (typeof ownedFile !== 'string' || !ownedFile.includes('chord-sqlite-owned-')) {
    throw Error('A separately granted fresh owned database filename is required');
  }
  const rows = [];
  const isAsync = value => Object.getPrototypeOf(value) === Object.getPrototypeOf(async () => {});
  rows.push({id:'metadata', constructor:api.NodeSqliteDatabase.name, length:api.NodeSqliteDatabase.length,
    open:{name:api.openNodeSqliteDatabase.name,length:api.openNodeSqliteDatabase.length,async:isAsync(api.openNodeSqliteDatabase)},
    executor:Object.getPrototypeOf(api.NodeSqliteDatabase.prototype).constructor.name,
    methods:['exec','run','get','all','transaction','close','runOperation'].map(name=>({name,length:api.NodeSqliteDatabase.prototype[name].length,async:isAsync(api.NodeSqliteDatabase.prototype[name]),prototype:Object.hasOwn(api.NodeSqliteDatabase.prototype[name],'prototype')}))});
  function fake(trace, fail) {
    const row={owned:'row'}, all=[row]; let prepares=0;
    return {row,all,get prepares(){return prepares},exec(sql){trace.push('exec:'+sql);if(fail)fail(sql)},close(){trace.push('close');if(fail)fail('close')},prepare(sql){prepares++;trace.push('prepare:'+sql);return{
      run(...args){trace.push('run:'+sql+':'+args.map(x=>typeof x).join(','));return{then(){throw Error('run result must be ignored')}}},
      get(...args){trace.push('get:'+sql+':'+args.length);return row},all(...args){trace.push('all:'+sql+':'+args.length);return all}}}};
  }
  async function record(id, body) {
    const trace=[],marker={id},second={second:id};
    try { rows.push({id,trace,value:await body(trace,marker,second)}); }
    catch(error){rows.push({id,trace,error:{marker:error===marker,second:error===second,name:error?.name,code:error?.code,message:error?.message}})}
  }
  await record('cached-statements-and-raw-results', async trace=>{
    const raw=fake(trace), db=new api.NodeSqliteDatabase(raw);
    const first=db.run('same',1,'x',null);trace.push('after-call');
    const result=await first, row=await db.get('same',2), all=await db.all('same');
    return{ignored:result===undefined,row:row===raw.row,all:all===raw.all,prepares:raw.prepares,mapSize:db.statements.size,database:db.database===raw};
  });
  await record('transaction-publishes-barrier-before-reentrant-call', async trace=>{
    const db=new api.NodeSqliteDatabase(fake(trace));let queued,handle;
    const pending=db.transaction(async tx=>{handle=tx;trace.push('callback');queued=db.exec('outside');await tx.exec('inside');return'answer'});
    trace.push('returned');const result=await pending;await queued;
    return{result,scope:handle.scope.active,sameStatements:handle.statements===db.statements,txOperationAsync:isAsync(handle.runOperation),pending:db.access.pending};
  });
  await record('transaction-gate-serializes-unrelated-work', async trace=>{
    const release=Promise.withResolvers(), entered=Promise.withResolvers();const db=new api.NodeSqliteDatabase(fake(trace));
    const tx=db.transaction(async handle=>{trace.push('entered');entered.resolve();await release.promise;await handle.exec('inside');return 7});
    await entered.promise;const outside=db.exec('outside');trace.push('releasing');release.resolve();await tx;await outside;return db.access.pending;
  });
  await record('expired-transaction-handle', async trace=>{
    const db=new api.NodeSqliteDatabase(fake(trace));let saved;await db.transaction(async tx=>{saved=tx});await saved.exec('late');
  });
  for(const mode of ['callback','begin','commit','rollback']) await record('transaction-error-'+mode, async(trace,marker,second)=>{
    const raw=fake(trace,sql=>{if(mode==='begin'&&sql==='BEGIN IMMEDIATE')throw marker;if(mode==='commit'&&sql==='COMMIT')throw marker;if(mode==='rollback'&&sql==='ROLLBACK')throw second});
    const db=new api.NodeSqliteDatabase(raw);
    try{await db.transaction(async tx=>{trace.push('callback');if(mode==='callback'||mode==='rollback')throw marker;await tx.exec('inside')})}
    catch(error){return{marker:error===marker,aggregate:error instanceof AggregateError,errors:error instanceof AggregateError?error.errors.map(value=>value===marker?'first':value===second?'second':'other'):undefined,message:error?.message,pending:db.access.pending}}
  });
  await record('rollback-getter-failure-is-aggregate',async(trace,marker,second)=>{
    const raw=fake(trace),db=new api.NodeSqliteDatabase(raw);let reads=0;
    Object.defineProperty(db,'database',{get(){trace.push('database:'+reads);if(++reads===3)throw second;return raw}});
    try{await db.transaction(async()=>{throw marker})}catch(error){return{aggregate:error instanceof AggregateError,first:error?.errors?.[0]===marker,second:error?.errors?.[1]===second}}
  });
  await record('close-checkpoint-clear-and-idempotence', async trace=>{
    const db=new api.NodeSqliteDatabase(fake(trace));await db.get('cached');await db.close();await db.close();return{closed:db.closed,mapSize:db.statements.size,pending:db.access.pending};
  });
  for(const mode of ['checkpoint','close']) await record('close-error-'+mode, async(trace,marker,second)=>{
    const db=new api.NodeSqliteDatabase(fake(trace,sql=>{if(sql==='PRAGMA wal_checkpoint(TRUNCATE)')throw marker;if(mode==='close'&&sql==='close')throw second}));
    try{await db.close()}catch(error){return{marker:error===marker,second:error===second,closed:db.closed,pending:db.access.pending}}
  });
  await record('checkpoint-getter-still-runs-finally',async(trace,marker)=>{
    const raw=fake(trace),db=new api.NodeSqliteDatabase(raw);let reads=0;
    Object.defineProperty(db,'database',{get(){trace.push('database:'+reads);if(++reads===1)throw marker;return raw}});
    try{await db.close()}catch(error){return{same:error===marker,reads}}
  });
  await record('selected-runOperation-and-operation-arrow',async trace=>{
    const db=new api.NodeSqliteDatabase(fake(trace));db.runOperation=function(operation){trace.push('operation:'+String(this===db)+':'+operation.name+':'+operation.length+':'+Object.hasOwn(operation,'prototype'));return Promise.resolve(operation())};
    await db.run('owned');return true;
  });
  await record('live-Promise-resolve-and-thenable-adoption',async trace=>{
    const original=Object.getOwnPropertyDescriptor(Promise,'resolve');
    try{Object.defineProperty(Promise,'resolve',{configurable:true,get(){trace.push('resolve:get');return function(value){trace.push('resolve:call:'+String(this===Promise));return Reflect.apply(original.value,this,[value])}}});
      const db=new api.NodeSqliteDatabase(fake(trace));db.database.prepare=()=>({get(){trace.push('get');return{then(resolve){trace.push('thenable');resolve('adopted')}}}});return await db.get('owned');
    }finally{Object.defineProperty(Promise,'resolve',original)}
  });
  await record('transaction-callback-thenable',async trace=>{
    const db=new api.NodeSqliteDatabase(fake(trace));return await db.transaction(()=>({then(resolve){trace.push('callback:then');resolve('value')}}));
  });
  await record('real-memory-parameters-rows-and-cache',async()=>{
    const db=await api.openNodeSqliteDatabase(':memory:');
    try{await db.exec('CREATE TABLE owned(n INTEGER, f REAL, s TEXT, b BLOB, z TEXT, i INTEGER)');
      await db.run('INSERT INTO owned VALUES(?,?,?,?,?,?)',7,1.25,'a\0b',new Uint8Array([0,1,255]),null,9n);
      const version=await db.get('SELECT sqlite_version() AS version');const row=await db.get('SELECT * FROM owned');const all=await db.all('SELECT * FROM owned');const none=await db.get('SELECT * FROM owned WHERE 0');
      return{version:version.version,prototype:Object.getPrototypeOf(row)===null,n:row.n,f:row.f,s:row.s,b:Array.from(row.b),blob:row.b instanceof Uint8Array,z:row.z,i:row.i,all:all.length,none:none===undefined,cache:db.statements.size};
    }finally{await db.close()}
  });
  await record('real-commit-and-rollback',async(trace,marker)=>{
    const db=await api.openNodeSqliteDatabase(':memory:');try{await db.exec('CREATE TABLE owned(n INTEGER)');
      await db.transaction(async tx=>{await tx.run('INSERT INTO owned VALUES(?)',1)});try{await db.transaction(async tx=>{await tx.run('INSERT INTO owned VALUES(?)',2);throw marker})}catch(error){trace.push('same:'+String(error===marker))}
      return await db.all('SELECT n FROM owned ORDER BY n');
    }finally{await db.close()}
  });
  await record('real-SQLite-error-properties',async()=>{
    const db=await api.openNodeSqliteDatabase(':memory:');try{await db.exec('CREATE TABLE owned(n INTEGER UNIQUE)');await db.run('INSERT INTO owned VALUES(?)',1);try{await db.run('INSERT INTO owned VALUES(?)',1)}catch(error){return{name:error.name,code:error.code,errcode:error.errcode,errstr:error.errstr,message:error.message}}}finally{await db.close()}
  });
  await record('real-node-positional-reset-and-owned-blob',async()=>{
    const raw=new sqlite.DatabaseSync(':memory:');try{const statement=raw.prepare('SELECT ? AS a, ? AS b');const first=statement.get(new Uint8Array([3,4]),'first');const second=statement.get(5);const noRows=raw.prepare('SELECT 1 WHERE 0').get();return{a:Array.from(first.a),retained:Array.from(first.a),s:first.b,second,noRows:noRows===undefined};}finally{raw.close()}
  });
  await record('real-node-named-and-DataView-bindings',async()=>{
    const raw=new sqlite.DatabaseSync(':memory:');try{const bytes=new Uint8Array([5,6,7]);const row=raw.prepare('SELECT :a AS a, ? AS b').get({a:4},new DataView(bytes.buffer,1,2));return{a:row.a,b:Array.from(row.b),prototype:Object.getPrototypeOf(row)===null}}finally{raw.close()}
  });
  await record('real-node-large-integer-range',async()=>{
    const raw=new sqlite.DatabaseSync(':memory:');try{try{return raw.prepare('SELECT 9007199254740993 AS n').get()}catch(error){return{name:error.name,code:error.code,message:error.message}}}finally{raw.close()}
  });
  await record('real-owned-file-open-and-configuration',async()=>{
    const db=await api.openNodeSqliteDatabase(ownedFile,{walAutoCheckpointPages:11,busyTimeoutMs:27});
    try{const mode=await db.get('PRAGMA journal_mode'),checkpoint=await db.get('PRAGMA wal_autocheckpoint'),timeout=await db.get('PRAGMA busy_timeout');return{mode,checkpoint,timeout}}finally{await db.close()}
  });
  await record('invalid-timeout-preserves-Node-error',async()=>{await api.openNodeSqliteDatabase(':memory:',{busyTimeoutMs:1.5})});
  return{authority:'actual-c268-Chord-node-SQLite-Node24.14',rows};
}
