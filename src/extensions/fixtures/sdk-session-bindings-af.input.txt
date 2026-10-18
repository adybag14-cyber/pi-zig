// Shared authored caller: borrowed receivers ONLY. The API must be actual
// AgentSession.prototype (Source) or the installed genuine native methods.
export async function runSessionBindingsAF(api) {
  const rows=[];
  const ok=(condition,label)=>{ if(!condition) throw new Error(label); };
  const record=(name,trace)=>rows.push({name,trace});
  {
    const trace=[], bindings={}, session={};
    const fields=[['uiContext','_extensionUIContext'],['mode','_extensionMode'],['commandContextActions','_extensionCommandContextActions'],['abortHandler','_extensionAbortHandler'],['shutdownHandler','_extensionShutdownHandler'],['onError','_extensionErrorListener']];
    for(const [key,slot] of fields) {let count=0;Object.defineProperty(bindings,key,{get(){trace.push(key+':'+(++count));return count;}});Object.defineProperty(session,slot,{set(value){trace.push(slot+':'+value);}});}
    const runner={emit(){trace.push('emit');return undefined;},reportUnhandledMcpServers(){trace.push('report');}};
    Object.defineProperties(session,{
      _applyExtensionBindings:{get(){trace.push('get:apply');return function(value){ok(this===session&&value===runner,'apply receiver');trace.push('apply');};}},
      _extensionRunner:{get(){trace.push('get:runner');return runner;}},
      _sessionStartEvent:{get(){trace.push('get:event');return {get reason(){trace.push('get:reason');return 'reload';}};}},
      extendResourcesFromExtensions:{get(){trace.push('get:extend');return function(reason){ok(this===session&&reason==='reload','extend receiver/reason');trace.push('extend');};}},
    });
    const pending=api.bindExtensions.call(session,bindings);trace.push('caller');
    ok(trace.at(-2)==='emit','body synchronous before first await');
    await pending;trace.push('done');
    ok(trace.indexOf('get:extend')<trace.indexOf('get:reason'),'callee before reason');
    ok(trace.indexOf('caller')<trace.indexOf('report')&&trace.indexOf('extend')<trace.indexOf('done'),'two await continuations');
    for(const [key,slot] of fields) ok(trace.includes(key+':2')&&trace.includes(slot+':2'),'double live binding read '+key);
    record('six-double-reads-and-two-awaits',trace);
  }
  {
    const trace=[], bindings={};
    for(const key of ['uiContext','mode','commandContextActions','abortHandler','shutdownHandler','onError']) Object.defineProperty(bindings,key,{get(){trace.push(key);return undefined;}});
    const session={_applyExtensionBindings(){},_extensionRunner:{emit(){},reportUnhandledMcpServers(){}},_sessionStartEvent:{reason:'startup'},extendResourcesFromExtensions(){}};
    await api.bindExtensions.call(session,bindings);
    ok(trace.length===6,'undefined bindings single read');record('undefined-bindings-single-read',trace);
  }
  for(const boundary of ['first','second']) {
    const reason={boundary}, trace=[];
    const session={_applyExtensionBindings(){},_extensionRunner:{emit(){return boundary==='first'?Promise.reject(reason):undefined;},reportUnhandledMcpServers(){trace.push('report');}},_sessionStartEvent:{reason:'startup'},extendResourcesFromExtensions(){trace.push('extend');return Promise.reject(reason);}};
    let caught;try{await api.bindExtensions.call(session,{});}catch(error){caught=error;}
    ok(caught===reason,'raw bind rejection identity');ok(boundary!=='first'||trace.length===0,'first rejection stops continuation');record('bind-rejected-'+boundary,trace);
  }
  {
    const trace=[], session={_extensionRunner:{hasHandlers(event){trace.push(event);return false;}}};
    const promise=api.extendResourcesFromExtensions.call(session,'startup');trace.push('caller');await promise;record('discovery-false-returns-async-void',trace);
  }
  {
    const reason={},session={_cwd:'/cwd',_extensionRunner:{hasHandlers(){return true;},emitResourcesDiscover(){return Promise.reject(reason);}}};
    let caught;try{await api.extendResourcesFromExtensions.call(session,'startup');}catch(error){caught=error;}
    ok(caught===reason,'raw discovery rejection identity');record('discovery-rejected-raw',[]);
  }
  for(const first of [0,'0',1]) {
    const trace=[], lists={};
    for(const [name,length] of [['skillPaths',first],['promptPaths',0],['themePaths',0]]) lists[name]={get length(){trace.push('length:'+name);return length;}};
    const returned={};for(const name of ['skillPaths','promptPaths','themePaths']) Object.defineProperty(returned,name,{get(){trace.push('get:'+name);return lists[name];}});
    const session={_cwd:'/cwd',_extensionRunner:{hasHandlers(){return true;},emitResourcesDiscover(cwd,reason){ok(cwd==='/cwd'&&reason==='reload','discovery args');return returned;}},
      buildExtensionResourcePaths(list){trace.push('build:'+Object.keys(lists).find(k=>lists[k]===list));return list;},
      _resourceLoader:{extendResources(paths){trace.push('extend');ok(paths.skillPaths===lists.skillPaths,'actual paths object');}},
      get getActiveToolNames(){trace.push('get:active');return ()=>{trace.push('active');return ['tool'];};},
      get _rebuildSystemPrompt(){trace.push('get:rebuild');return function(names){ok(this===session&&names[0]==='tool','rebuild args');trace.push('rebuild');};}};
    await api.extendResourcesFromExtensions.call(session,'reload');
    ok(trace.slice(0,3).join(',')==='get:skillPaths,get:promptPaths,get:themePaths','destructure before lengths');
    if(first===0) ok(!trace.includes('extend')&&trace.filter(x=>x.startsWith('length:')).length===3,'all strict zero early return');
    else {ok(trace.filter(x=>x.startsWith('length:')).length===1,'strict zero short circuit');ok(trace.indexOf('get:rebuild')<trace.indexOf('get:active'),'rebuild callee before active argument');}
    record('discovery-length-'+typeof first+'-'+first,trace);
  }
  {
    const trace=[],session={getExtensionSourceLabel(value){trace.push('label:'+value);return 'source';}};
    const entries={get map(){trace.push('get:map');return function(callback){ok(this===entries,'map receiver');ok(!Object.hasOwn(callback,'prototype'),'ordinary arrow callback');return callback({extensionPath:'builtin:x',path:'p'});};}};
    const result=api.buildExtensionResourcePaths.call(session,entries);
    ok(result.path==='p'&&result.metadata.source==='source'&&result.metadata.baseDir===undefined,'ordinary mapping result');record('ordinary-map-callback',trace);
  }
  return rows;
}
