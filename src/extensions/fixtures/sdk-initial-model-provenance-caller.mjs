(function observeSameOperationInitialModelProvenance(actualImports, actualOptions, hooks, fatal) {
  let originalA, getterReads = 0, escaped = false, pending;
  const options = new Proxy(actualOptions, { get(target, key, receiver) {
    if (key !== 'scopedModels') return Reflect.get(target, key, receiver);
    getterReads++;
    originalA = hooks.freshPrivateData();
    if (!hooks.isUnmarkedPrivateData(originalA)) throw Error('genuine new private DATA A required');
    if (fatal) return hooks.raiseNativeFatal();
    throw originalA; // SAME property operation, after successful native return.
  } });
  try { pending = actualImports.findInitialModel(options); }
  catch (error) { escaped = true; hooks.record.guestReached = true; hooks.visit(3); throw error; }
  return pending.then(
    () => { throw Error('injected getter unexpectedly fulfilled'); },
    error => {
      if (fatal) { hooks.record.guestReached = true; hooks.visit(3); throw Error('actual native fatal reached guest rejection handler'); }
      if (escaped || getterReads !== 1 || error !== originalA || !hooks.isUnmarkedPrivateData(error)) throw Error('same-operation private DATA guest throw was reclassified or coerced');
      return { id: 'same-getter-fresh-private-data-maker-then-ordinary-throw-A',
        scope: 'borrowed-options-getter-with-genuine-native-DATA-maker', getterReads, escaped, sameReason: error === originalA, privateAndUnmarked: true };
    }
  );
})
