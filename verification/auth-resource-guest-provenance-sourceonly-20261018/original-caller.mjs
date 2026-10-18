// Original modules only. Root supplies exact admitted physical module URLs and
// a real owned Auth path. No native candidate, replacement class or expected.
const [authURL, resourceURL, authPath] = process.argv.slice(2);
if (!authURL || !resourceURL || !authPath) throw new Error('actual module URLs and owned auth path required');
const { AuthStorage, ReadOnlyAuthStorage } = await import(authURL);
const { DefaultResourceLoader } = await import(resourceURL);
const rows = [];
for (const route of ['auth-getter', 'auth-call', 'readonly-getter', 'reload-getter']) {
  let reason, calls = 0, coercions = 0;
  function throwing() {
    calls++;
    reason = new Error('actual Source ordinary creation and throw in one operation');
    reason.toString = () => { coercions++; return 'observed coercion'; };
    throw reason;
  }
  let operation;
  if (route === 'reload-getter') {
    operation = DefaultResourceLoader.prototype.reload.call({ loaded: false }, { get resolveProjectTrust() { return throwing(); } });
  } else {
    const store = route === 'readonly-getter' ? new ReadOnlyAuthStorage(authPath) : AuthStorage.inMemory();
    const options = route === 'auth-call' ? { signal: { throwIfAborted: throwing } } : { get signal() { return throwing(); } };
    operation = store.read('fixture', options);
  }
  const promiseTag = Object.prototype.toString.call(operation);
  try {
    const value = await operation;
    rows.push({ route, promiseTag, completion: 'fulfilled', value, calls, coercions });
  } catch (caught) {
    rows.push({ route, promiseTag, completion: 'rejected', same: caught === reason, name: caught?.name, message: caught?.message, stack: caught?.stack, calls, coercions });
  }
}
console.log(JSON.stringify({ rows }));
