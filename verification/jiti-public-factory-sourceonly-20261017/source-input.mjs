// Inert prospective genuine-reference input; no expected output exists.
// Runner supplies an original verified jiti2.7 lib/jiti.mjs URL and a real
// owned factory filename. No substitute factory/transform/bootstrap is accepted.
export async function observeActualPublicFactory(originalPackageURL, actualFactoryFilename) {
  const {createJiti, default: defaultFactory} = await import(originalPackageURL);
  const rows = [];
  const prior = new Map();
  for (const [key, value] of Object.entries({JITI_FS_CACHE:'false', JITI_CACHE:'false', JITI_TSCONFIG_PATHS:'false', JITI_DEBUG:'false'})) {
    prior.set(key, Object.hasOwn(process.env, key) ? process.env[key] : undefined);
    process.env[key] = value;
  }
  function observe(name, body) {
    try { rows.push({name, value:body()}); }
    catch (error) { rows.push({name, error:{name:error?.name, message:error?.message}}); }
  }
  try {
    observe('same-public-default', () => defaultFactory === createJiti);
    observe('factory-metadata', () => [createJiti.name, createJiti.length, typeof createJiti.prototype, Object.getPrototypeOf(createJiti).constructor.name]);
    observe('undefined-default-options', () => { const jiti = createJiti(actualFactoryFilename); return [typeof jiti, jiti.options.transform.name, jiti.options.transform.length]; });
    observe('explicit-undefined-options', () => typeof createJiti(actualFactoryFilename, undefined));
    observe('null-options-throws', () => createJiti(actualFactoryFilename, null));
    observe('new-factory-returns-jiti', () => typeof new createJiti(actualFactoryFilename, {fsCache:false}));
    observe('lazy-shared-between-instances', () => createJiti(actualFactoryFilename).options.transform === createJiti(actualFactoryFilename).options.transform);
    observe('truthy-custom-transform-retained', () => { const custom = options => ({code:options.source}); return createJiti(actualFactoryFilename, {transform:custom}).options.transform === custom; });
    observe('falsy-transform-spread-read-order', () => { const trace=[]; const options={fsCache:false}; Object.defineProperty(options,'transform',{enumerable:true,get(){trace.push('transform');return false;}}); Object.defineProperty(options,'debug',{enumerable:true,get(){trace.push('debug');return false;}}); const jiti=createJiti(actualFactoryFilename,options); return [trace,jiti.options.transform.name]; });
    observe('proxy-spread-events', () => { const trace=[]; const key=Symbol('owned'); const options=new Proxy({transform:0,fsCache:false,[key]:7},{get(t,k,r){trace.push(['get',typeof k==='symbol'?'symbol':k]);return Reflect.get(t,k,r)},ownKeys(t){trace.push(['keys']);return Reflect.ownKeys(t)},getOwnPropertyDescriptor(t,k){trace.push(['descriptor',typeof k==='symbol'?'symbol':k]);return Reflect.getOwnPropertyDescriptor(t,k)}}); const jiti=createJiti(actualFactoryFilename,options);return [trace,jiti.options[key]]; });
    observe('sync-builtin-actual-identity', () => {const jiti=createJiti(actualFactoryFilename);return typeof jiti('node:path').join;});
    const jiti = createJiti(actualFactoryFilename);
    const imported = await jiti.import('node:path');
    rows.push({name:'async-builtin-actual-namespace',value:[typeof imported.join,typeof imported.default]});
    observe('actual-default-transform-result', () => { const result=jiti.options.transform({source:'export const value: number = 7;',filename:actualFactoryFilename+'.ts',ts:true,async:false,interopDefault:true,retainLines:true,babel:{}});return {keys:Object.keys(result),code:result.code,error:result.error}; });
    observe('actual-default-transform-raw-error', () => { const result=jiti.options.transform({source:'export const = ;',filename:actualFactoryFilename+'.ts',ts:true,async:false,interopDefault:true,retainLines:true,babel:{}});return {keys:Object.keys(result),code:result.code,error:result.error}; });
    return rows;
  } finally {
    for (const [key,value] of prior) if (value === undefined) delete process.env[key]; else process.env[key]=value;
  }
}
