// Additive genuine Source caller. Supply the actual published parseGitUrl.
// Optional makeData is the linked-VM native DATA producer in native controls;
// the original Node caller defaults to an ordinary real Error, never a URL fake.
export default function observeGitGuestOperation(parseGitUrl, mode, makeData = () => new Error('ordinary same-operation DATA')) {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'URL');
  const RealURL = globalThis.URL;
  let calls = 0;
  let reason;
  const throwData = () => { calls++; reason = makeData(); throw reason; };
  try {
    if (mode === 'getter') Object.defineProperty(globalThis, 'URL', { configurable: true, get: throwData });
    else if (mode === 'constructor') globalThis.URL = new Proxy(RealURL, { construct: throwData });
    else throw new TypeError('Unknown genuine Git guest-operation profile');
    const input = 'git:https://example.org/team/repo@next';
    let result;
    let escaped = false;
    let escapedSame = false;
    try { result = parseGitUrl(input); }
    catch (error) { escaped = true; escapedSame = error === reason; }
    return { input, mode, result, escaped, escapedSame, calls };
  } finally {
    Object.defineProperty(globalThis, 'URL', descriptor);
  }
}

// This route calls the genuine published DefaultPackageManager instance's
// emitted private method. The caller must construct that real instance; no
// substitute PM, filesystem, supplier or parser result is authored here.
export function observeActualPackageManagerGuestOperation(packageManager, mode, makeData) {
  return observeGitGuestOperation(source => Reflect.apply(packageManager.parseSource, packageManager, [source]), mode, makeData);
}
