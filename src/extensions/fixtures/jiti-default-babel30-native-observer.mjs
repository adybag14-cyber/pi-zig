// Verification only. Original caller structure, exact unchanged original input
// objects and accepted raw authority. No successful transform/require substitute.
export default async function observe(inputs, original, fixtureRoot, backend, createJiti, join) {
  if (typeof backend !== 'function' || typeof join !== 'function') throw Error('actual native default backend and Node path.join required');
  const all = [...inputs.supported_execution_inputs, ...inputs.declared_native_frontier_inputs];
  if (all.length !== 30 || original.rows.length !== 30 || inputs.supported_execution_inputs.length !== 12) throw Error('exact original12+18 required');
  const rows = [], comparisons = [];
  const processObject = globalThis.process;
  const env = createJiti === undefined ? undefined : processObject?.env;
  if (createJiti !== undefined && (typeof createJiti !== 'function' || !env)) throw Error('genuine completed public profile and process required');
  const previous = env === undefined ? undefined : Object.getOwnPropertyDescriptor(env, 'PI_JITI_DEFAULT_OWNED_VALUE');
  if (env !== undefined) env.PI_JITI_DEFAULT_OWNED_VALUE = 'owned-default-transform';
  function failure(error) { return {type:typeof error, name:error?.name, message:error?.message, code:error?.code, loc:error?.loc, stack:error?.stack}; }
  function same(a,b) { return JSON.stringify(a) === JSON.stringify(b); }
  try {
    for (let index = 0; index < all.length; index++) {
      const item = all[index], authority = original.rows[index];
      const profile = index < 12 ? 'consumed-profile' : 'native-frontier';
      if (item.id !== authority.id || authority.profile !== profile) throw Error('original order/profile mismatch at '+index);
      // Exact physical labels from the accepted original plan, with its existing
      // immutable fixtures. Backend observation performs no filesystem writes.
      const filename = join(fixtureRoot, item.id, item.ts ? 'entry.ts' : 'entry.js');
      const options = {...item, filename, interopDefault:true};
      delete options.id; delete options.files; delete options.args;
      const row = {id:item.id, profile};
      try {
        const transformed = backend(options);
        row.result = {keys:Reflect.ownKeys(transformed).map(String), code:transformed.code, error:transformed.error ? failure(transformed.error) : undefined};
        if (index < 12 && !transformed.error && createJiti !== undefined) {
          const jiti = createJiti(filename, {fsCache:false, tsconfigPaths:false});
          const exported = await jiti.evalModule(item.source, {filename, ext:item.ts ? '.ts' : '.js', forceTranspile:true, async:!!item.async});
          const fn = exported.default;
          row.execution = {keys:Object.keys(exported), defaultType:typeof fn, name:fn?.name, length:fn?.length, functionSource:typeof fn === 'function' ? Function.prototype.toString.call(fn) : undefined, value:typeof fn === 'function' ? await Reflect.apply(fn,undefined,item.args??[]) : undefined};
        }
      } catch(error) { row.thrown = failure(error); }
      rows.push(row);
      const expectedError = authority.result?.error, actualError = row.result?.error;
      const comparison = {
        id:item.id, profile,
        backendCompletion:same({result:!!row.result,thrown:!!row.thrown},{result:!!authority.result,thrown:!!authority.thrown}),
        resultKeys:same(row.result?.keys,authority.result?.keys),
        codeIsString:typeof row.result?.code==='string',
        errorCategory:same(actualError && {type:actualError.type,name:actualError.name},expectedError && {type:expectedError.type,name:expectedError.name}),
        codeBytes:same(row.result?.code,authority.result?.code),
        diagnostic:same(expectedError,actualError) && same(authority.thrown,row.thrown)
      };
      if(index < 12) {
        comparison.executionPresent=!!row.execution;
        comparison.executionShape=same(row.execution && {keys:row.execution.keys,defaultType:row.execution.defaultType,name:row.execution.name,length:row.execution.length}, {keys:authority.execution.keys,defaultType:authority.execution.defaultType,name:authority.execution.name,length:authority.execution.length});
        comparison.executionValue=same(row.execution?.value,authority.execution.value);
        comparison.functionSourceBytes=same(row.execution?.functionSource,authority.execution.functionSource);
      }
      comparisons.push(comparison);
    }
  } finally {
    if(env !== undefined) {
      if(previous === undefined) delete env.PI_JITI_DEFAULT_OWNED_VALUE;
      else Object.defineProperty(env,'PI_JITI_DEFAULT_OWNED_VALUE',previous);
    }
  }
  const backendMismatches=comparisons.filter(row=>!row.backendCompletion||!row.resultKeys||!row.codeBytes||!row.diagnostic).map(row=>row.id);
  const completionMismatches=comparisons.filter(row=>!row.backendCompletion||!row.resultKeys||!row.codeIsString||!row.errorCategory).map(row=>row.id);
  const semanticMismatches=comparisons.slice(0,12).filter(row=>!row.executionPresent||!row.executionShape||!row.executionValue).map(row=>row.id);
  const functionTextMismatches=comparisons.slice(0,12).filter(row=>!row.functionSourceBytes).map(row=>row.id);
  return {authority:'native-default-Babel30-observation-versus-accepted-original', originalAuthority:original.authority,
    mode:createJiti===undefined?'backend-only-genuine-public-bootstrap-unavailable':'genuine-completed-public-profile',
    fixtureRoot, rows, comparisons, completionMismatches, compilerCompletionsMatched:completionMismatches.length===0, backendMismatches, semanticMismatches, functionTextMismatches,
    fullComparisonPassed:createJiti!==undefined && backendMismatches.length===0 && semanticMismatches.length===0 && functionTextMismatches.length===0,
    nativeRows:rows.length, evaluatedRows:rows.filter(row=>!!row.execution).length,
    original:original, expectedFixtureCreated:false, outputProjectionOrFormattingNormalization:false};
}
