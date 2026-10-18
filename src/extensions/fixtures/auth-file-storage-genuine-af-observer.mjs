import path from 'node:path';

function assert(value, label) { if (!value) throw new Error(label); }
function held() { let resolve, reject; const promise=new Promise((a,b)=>{resolve=a;reject=b}); return {promise,resolve,reject}; }
async function until(predicate) { for(let i=0;i<100&&!predicate();i++) await Promise.resolve(); assert(predicate(),'actual phase did not progress'); }
function overrideAcquire(backend, release) {
  Object.defineProperty(backend,'acquireLockAsync',{configurable:true,writable:true,value:async function(){return release}});
}

// The constructor is the real FileAuthStorageBackend. Overridden INSTANCE
// methods below are explicit Source caller inputs, not dependency facades.
export async function observeFileBackend(FileAuthStorageBackend, fixtureRoot) {
  const rows=[];
  const prototype=FileAuthStorageBackend.prototype;
  rows.push({kind:'shape',methods:['acquireLockAsync','withLockAsync'].map(name=>({name:prototype[name].name,length:prototype[name].length,tag:Object.prototype.toString.call(prototype[name]),ownPrototype:Object.hasOwn(prototype[name],'prototype')}))});

  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'actual-file.json'));
    const first=await backend.withLockAsync(async current=>({result:current,next:'owned-file-value'}));
    const second=await backend.withLockAsync(async current=>({result:current}));
    assert(first==='{}'&&second==='owned-file-value','actual filesystem roundtrip');
    const release=await backend.acquireLockAsync(undefined,()=>{});
    assert(typeof release==='function','actual acquired release');await release();
    rows.push({kind:'actual-file-roundtrip',first,second,release:typeof release});
  }
  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'held-finally.json'));
    const release=held();let releaseEntered=false,settled=false;const log=[];
    overrideAcquire(backend,function(){releaseEntered=true;log.push('release');return release.promise});
    const callback=held();
    const pending=backend.withLockAsync(function(current){log.push(`callback:${current}`);return callback.promise}).then(value=>{settled=true;return value});
    await until(()=>log.length>0);assert(!settled,'callback Await missing');
    callback.resolve({result:'held-result'});await until(()=>releaseEntered);
    assert(!settled,'real finally Await missing');release.resolve();
    assert(await pending==='held-result','real finally return');
    rows.push({kind:'held-finally',log,settled});
  }
  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'ordinary-finally.json'));
    const original={toString(){throw Error('original coercion')}};const unlock={identity:'ignored-unlock'};
    let releases=0;overrideAcquire(backend,function(){releases++;return Promise.reject(unlock)});
    let caught;try{await backend.withLockAsync(()=>Promise.reject(original))}catch(error){caught=error}
    assert(caught===original&&releases===1,'Source catch/finally reason precedence');
    rows.push({kind:'ordinary-finally',sameOriginal:caught===original,releases});
  }
  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'sync-unlock.json'));
    const unlock={identity:'synchronous-unlock'};let releases=0;
    overrideAcquire(backend,function(){releases++;throw unlock});
    const result=await backend.withLockAsync(async()=>({result:'kept-result'}));
    assert(result==='kept-result'&&releases===1,'Source ignores sync unlock failure');
    rows.push({kind:'sync-unlock',result,releases});
  }
  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'preflight.json'));
    const original={identity:'preflight'};let directories=0,acquires=0,synchronous=false;
    const ensure=backend.ensureParentDir,acquire=backend.acquireLockAsync;
    backend.ensureParentDir=function(){directories++;return ensure.call(this)};
    backend.acquireLockAsync=function(...args){acquires++;return acquire.apply(this,args)};
    let promise;try{promise=backend.withLockAsync(async()=>({result:1}),{signal:{throwIfAborted(){throw original}}})}catch{synchronous=true}
    let caught;try{await promise}catch(error){caught=error}
    assert(!synchronous&&caught===original&&directories===0&&acquires===0,'preflight real async throw');
    rows.push({kind:'preflight',synchronous,sameOriginal:caught===original,directories,acquires});
  }
  {
    const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'aborted-after-acquire.json'));
    backend.ensureParentDir();backend.ensureFileExists();
    const release=await backend.acquireLockAsync(undefined,()=>{});await release();
    // The supplied getter sequence is actual Source input; it does not alter
    // lockfile, fs, path, timers or the constructor's imported dependencies.
    const original={identity:'cancel-before-lock'};let checks=0,caught;
    try{await backend.acquireLockAsync({throwIfAborted(){checks++;throw original}},()=>{})}catch(error){caught=error}
    assert(caught===original&&checks===1,'actual acquisition abort check');
    rows.push({kind:'acquire-abort',sameOriginal:caught===original,checks});
  }
  return rows;
}

// Marked private errors are supplied as successful native DATA, then passed to
// Promise.reject. An actual new JS/native throw is intentionally a different
// control. No bit is cleared and no message/name is used as an OOM oracle.
export async function verifyFileRejectedData(FileAuthStorageBackend,fixtureRoot,makeData) {
  const backend=new FileAuthStorageBackend(path.join(fixtureRoot,'native-rejected-data.json'));
  const data=makeData();let releases=0;
  overrideAcquire(backend,function(){releases++;return Promise.resolve()});
  let caught;try{await backend.withLockAsync(()=>Promise.reject(data))}catch(error){caught=error}
  assert(caught===data&&releases===1,'callback DATA must execute Source finally');
  const original={identity:'ordinary callback'};
  overrideAcquire(backend,function(){releases++;return Promise.resolve().then(()=>Promise.reject(makeData()))});
  try{await backend.withLockAsync(()=>Promise.reject(original))}catch(error){caught=error}
  assert(caught===original&&releases===2,'unlock DATA must not replace original');
  assert(await backend.withLockAsync(async()=>({result:'ordinary return'}))==='ordinary return'&&releases===3,'unlock DATA must not replace return');
  const acquireData=makeData();backend.acquireLockAsync=function(){return Promise.reject(acquireData)};
  try{await backend.withLockAsync(async()=>({result:0}))}catch(error){caught=error}
  assert(caught===acquireData&&releases===3,'acquire DATA cannot invent release');
  return {sameCallbackData:true,ignoredUnlockData:true,sameAcquireData:true,releases};
}
