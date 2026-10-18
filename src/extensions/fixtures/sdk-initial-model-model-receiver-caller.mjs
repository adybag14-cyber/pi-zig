(function prepareActualInitialModelReceiver(actualImports, subject, hooks) {
  const actualRow = subject.actualScopedRow;
  const actualModel = actualRow.model;
  const levels = subject.actualModelThinkingLevels;
  if (!actualModel || levels === null || levels === undefined) throw Error('real scoped model and real per-model settings map required');
  let modelReads = 0, coercions = 0, temporaryModel;
  const provider = { toString() {
    hooks.record.coercionReached = true;
    hooks.visit(4);
    coercions++;
    if (hooks.count(2) !== 1 || modelWeak.deref() !== undefined) throw Error('temporary native model receiver retained into provider ToString');
    return actualModel.provider;
  } };
  temporaryModel = hooks.make(2); // Actual native sole model-receiver holder.
  Object.defineProperty(temporaryModel, 'provider', { value: provider });
  const modelWeak = new WeakRef(temporaryModel);
  const borrowedRow = {
    get model() {
      modelReads++;
      if (modelReads === 1) { const current = temporaryModel; temporaryModel = undefined; return current; }
      return actualModel;
    },
    get thinkingLevel() { return actualRow.thinkingLevel; }
  };
  const options = { ...subject.options, scopedModels: [borrowedRow], isContinuing: false, modelThinkingLevels: levels };
  if (subject.fatalModelReceiverRetirement) hooks.armFatal(2);
  // Root ends the preparation job before calling this runner, preserving the
  // real WeakRef kept-object rule instead of manually clearing any references.
  return function runActualInitialModelReceiver() {
    return actualImports.findInitialModel(options).then(value => {
      if (value.model !== actualModel || modelReads !== 3 || coercions !== 1 || hooks.count(2) !== 1) throw Error('actual scoped resolver/coercion path was not exercised');
      return { id: 'borrowed-scoped-model-native-receiver-before-provider-coercion',
        scope: 'borrowed-scoped-row-with-genuine-model-and-settings', modelReads, coercions,
        retiredNativeModel: hooks.count(2), modelIdentity: value.model === actualModel,
        actualModel: { provider: value.model.provider, id: value.model.id }, thinkingLevel: value.thinkingLevel };
    });
  };
})
