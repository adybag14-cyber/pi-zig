(async function observeActualInitialModel(actualImports, subject) {
  const findInitialModel = actualImports.findInitialModel;
  const rows = [];
  for (const id of ['actual-scoped-model', 'actual-saved-default', 'actual-default-snapshot', 'actual-empty-snapshot']) {
    if (!subject.actualCases.some(entry => entry.id === id)) throw Error('missing genuine input case: ' + id);
  }
  const encode = value => ({
    model: value.model === undefined ? undefined : { provider: value.model.provider, id: value.model.id },
    thinkingLevel: value.thinkingLevel,
    fallbackMessage: value.fallbackMessage,
    keys: Object.keys(value)
  });
  for (const entry of subject.actualCases) {
    const trace = [];
    // This is a borrowed options receiver over caller-owned real inputs. All
    // runtime/model/auth methods remain the actual instance's own methods.
    const options = new Proxy(entry.options, { get(target, key, receiver) {
      trace.push(String(key)); return Reflect.get(target, key, receiver);
    } });
    let escaped = false, pending;
    try { pending = findInitialModel(options); } catch { escaped = true; }
    if (escaped) throw Error('actual findInitialModel escaped its async entry');
    rows.push({ id: entry.id, scope: 'borrowed-options-with-actual-model-runtime', trace, value: encode(await pending) });
  }
  const reason = { original: 'borrowed option getter' };
  let reads = 0, escaped = false, pending;
  try { pending = findInitialModel(new Proxy(subject.actualCases[0].options, { get() { reads++; throw reason; } })); }
  catch { escaped = true; }
  let rejection;
  try { await pending; } catch (error) { rejection = error; }
  if (escaped || reads !== 1 || rejection !== reason) throw Error('raw option rejection identity/order');
  rows.push({ id: 'borrowed-options-raw-rejection', scope: 'borrowed-options-negative', escaped, reads, sameReason: rejection === reason });
  let constructionRejected = false;
  try { Reflect.construct(findInitialModel, [subject.actualCases[0].options]); } catch (error) { constructionRejected = error instanceof TypeError; }
  if (!constructionRejected) throw Error('actual AsyncFunction was constructible');
  rows.push({ id: 'actual-async-function-metadata', name: findInitialModel.name, length: findInitialModel.length,
    async: Object.prototype.toString.call(findInitialModel), prototype: Object.hasOwn(findInitialModel, 'prototype'), constructionRejected });
  // The original result is an ordinary object literal. A prototype then getter
  // observes genuine AsyncFunction Return adoption with no extra Source Await.
  // Restore the realm before awaiting or constructing observation rows.
  const descriptor = Object.getOwnPropertyDescriptor(Object.prototype, 'then');
  if (descriptor && !descriptor.configurable) throw Error('fresh disposable realm required for return-adoption control');
  const token = Object.create(null); token.adopted = true;
  const effects = [];
  try {
    Object.defineProperty(Object.prototype, 'then', { configurable: true, get() {
      if (!Object.hasOwn(this, 'fallbackMessage') || !Object.hasOwn(this, 'thinkingLevel')) return undefined;
      effects.push('get-result-then');
      return function(resolve) { effects.push('call-result-then'); resolve(token); };
    } });
    pending = findInitialModel(subject.actualCases[0].options);
    effects.push('after-call');
  } finally {
    if (descriptor) Object.defineProperty(Object.prototype, 'then', descriptor);
    else delete Object.prototype.then;
  }
  const adopted = await pending;
  if (adopted !== token) throw Error('raw return adoption lost');
  rows.push({ id: 'actual-zero-await-return-adoption', effects, adopted: adopted === token });
  return rows;
})
