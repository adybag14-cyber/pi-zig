(function prepareActualInitialModelRetirement(actualImports, subject, hooks) {
  const find = actualImports.findInitialModel;
  const defaults = subject.actualDefaultModelPerProvider;
  const originalKeys = Object.keys;
  const provider = originalKeys(defaults)[0];
  const descriptor = Object.getOwnPropertyDescriptor(defaults, provider);
  if (!descriptor || !descriptor.configurable || !Object.hasOwn(descriptor, 'value')) throw Error('actual mutable default binding required');
  if (!subject.options.modelRuntime.getAvailableSnapshot().length) throw Error('genuine nonempty availability required');
  let method, step, returned = 0, nextRead = 0, defaultRead = 0;
  const assertRetired = (slot, weak, frontier) => {
    if (hooks.count(slot) !== 1 || weak.deref() !== undefined) throw Error('native soleholder/WeakRef retained past ' + frontier);
  };
  const iterator = {
    get next() {
      hooks.visit(0);
      nextRead++;
      assertRetired(0, methodWeak, 'cached next getter');
      return function() {
        hooks.visit(1);
        if (step !== undefined) { const current = step; step = undefined; return current; }
        return { done: true };
      };
    },
    return() { hooks.visit(2); returned++; return {}; }
  };
  method = function() { return iterator; };
  Object.defineProperty(method, 'nativeSoleHolder', { value: hooks.make(0) });
  const methodWeak = new WeakRef(method);
  step = { done: false, value: provider };
  Object.defineProperty(step, 'nativeSoleHolder', { value: hooks.make(1) });
  const stepWeak = new WeakRef(step);
  if (subject.retirementFatalSlot !== undefined) hooks.armFatal(subject.retirementFatalSlot);
  if (subject.cancelAtMethodRetirement) hooks.armCancel(0);
  // The real owner ends the preparation job before calling this closure, so
  // NewWeakRef's kept-object rule cannot hide temporary retention differences.
  return function runActualInitialModelRetirement() {
    const iterable = { get [Symbol.iterator]() { const current = method; method = undefined; return current; } };
    Object.keys = function(value) { return value === defaults ? iterable : originalKeys(value); };
    Object.defineProperty(defaults, provider, { configurable: true, enumerable: descriptor.enumerable, get() {
      defaultRead++;
      assertRetired(1, stepWeak, 'for-of body default lookup');
      return descriptor.value;
    } });
    let pending;
    try { pending = find(subject.options); }
    finally { Object.keys = originalKeys; Object.defineProperty(defaults, provider, descriptor); }
    return pending.then(value => {
      if (nextRead !== 1 || defaultRead !== 1 || hooks.count(0) !== 1 || hooks.count(1) !== 1) throw Error('genuine iterator/model lookup path was not exercised');
      return ({
      id: 'borrowed-iterator-with-actual-defaults-and-runtime-native-soleholders',
      scope: 'borrowed-iterator-control-over-genuine-model-runtime',
      nextRead, defaultRead, returned,
      nativeMethodRetired: hooks.count(0), nativeStepRetired: hooks.count(1),
      actualModel: value.model === undefined ? undefined : { provider: value.model.provider, id: value.model.id },
      thinkingLevel: value.thinkingLevel
      });
    });
  };
})
