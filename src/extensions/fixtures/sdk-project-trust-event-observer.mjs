const trustAssert = (condition, message) => { if (!condition) throw new Error(message); };
const trustSame = (actual, expected, message) =>
  trustAssert(JSON.stringify(actual) === JSON.stringify(expected), message + ": " + JSON.stringify(actual));
const trustExtension = (path, handlers) => ({ path, handlers: new Map([["project_trust", handlers]]) });
const trustInput = handlers => ({ extensions: [trustExtension("/extension", handlers)] });
const trustEvent = () => ({ type: "project_trust", cwd: "/project" });
async function trustRejected(promise) {
  try { await promise; } catch (reason) { return reason; }
  throw new Error("Expected actual rejection");
}
async function observeTrustEventShape(subject) {
  trustAssert(trustEventIsAsync(subject), "actual AsyncFunction brand");
  trustAssert(subject.name === "emitProjectTrustEvent" && subject.length === 3, "original function shape");
  trustAssert(!Object.hasOwn(subject, "prototype"), "async function is not a constructor");
  let constructorRejected = false;
  try { Reflect.construct(subject, []); } catch (e) { constructorRejected = e instanceof TypeError; }
  trustAssert(constructorRejected, "genuine nonconstructor");
  const a = await subject({ extensions: [] }, trustEvent(), {});
  const b = await subject({ extensions: [] }, trustEvent(), {});
  trustSame(Object.keys(a), ["errors"], "only original empty result field");
  trustAssert(Array.isArray(a.errors) && a.errors.length === 0 && a.errors !== b.errors, "fresh errors");
}
async function observeTrustEventSnapshot(subject) {
  const log = [], rows = [], input = {};
  const event = trustEvent(), ctx = {}, winner = { trusted: "yes" };
  function ext(label) {
    return { path: label, get handlers() {
      log.push(label + ".handlers");
      return { get get() {
        log.push(label + ".get");
        return function(key) {
          trustAssert(this !== undefined && key === "project_trust", "get receiver and event");
          log.push(label + ".get()");
          return { get slice() {
            log.push(label + ".slice");
            return function() {
              trustAssert(this !== undefined && arguments.length === 0, "slice receiver and arity");
              log.push(label + ".slice()");
              return [function(e, c) { "use strict";
                log.push(label + ".handler");
                trustAssert(this === undefined && e === event && c === ctx, "exact call inputs");
                return winner;
              }];
            };
          }};
        };
      }};
    }};
  }
  const one = ext("one"), two = ext("two");
  Object.defineProperty(input, "extensions", { get() {
    log.push("extensions");
    return { get map() { log.push("map"); return function(callback) {
      log.push("map()");
      trustAssert(callback.length === 1 && !Object.hasOwn(callback, "prototype"), "source arrow shape");
      rows.push(callback.call({ ignored: true }, one), callback(two));
      return rows;
    }; }};
  }});
  const result = await subject(input, event, ctx);
  trustAssert(result.result === winner && rows[0].ext === one && rows[1].ext === two, "identity");
  trustSame(log, ["extensions","map","map()","one.handlers","one.get","one.get()","one.slice","one.slice()",
    "two.handlers","two.get","two.get()","two.slice","two.slice()","one.handler"], "snapshot all first");
}
async function observeTrustEventNullish(subject) {
  const rows = [];
  const selections = [undefined, null, { slice() { return undefined; } }, { slice() { return null; } }];
  const input = { extensions: { map(callback) {
    for (const selected of selections) rows.push(callback({ handlers: { get() { return selected; } } }));
    return rows;
  }}};
  const result = await subject(input, trustEvent(), {});
  trustAssert(result.errors.length === 0 && rows.length === 4, "nullish cases");
  trustAssert(rows.every(row => Array.isArray(row.handlers) && row.handlers.length === 0), "nullish fresh arrays");
  trustAssert(new Set(rows.map(row => row.handlers)).size === 4, "each fallback allocates its own array");
}
async function observeTrustEventSnapshotMutation(subject) {
  const log = [];
  let resume;
  const gate = new Promise(resolve => { resume = resolve; });
  const second = [() => { log.push("original-second"); return { trusted: "yes" }; }];
  const first = [() => { log.push("first"); return gate; }];
  const input = { extensions: [trustExtension("first", first), trustExtension("second", second)] };
  const pending = subject(input, trustEvent(), {});
  trustSame(log, ["first"], "one handler entered before Await");
  first.push(() => { throw Error("new first must not run"); });
  second.splice(0, 1, () => { throw Error("replacement must not run"); });
  input.extensions.push(trustExtension("new", [() => { throw Error("new extension"); }]));
  resume({ trusted: "undecided" });
  const result = await pending;
  trustSame(log, ["first","original-second"], "initial snapshot retained across Await");
  trustAssert(result.result.trusted === "yes", "original winner");
}
async function observeTrustEventPlainAwait(subject) {
  const log = [];
  const result = { get trusted() { log.push("trusted"); return "yes"; } };
  const pending = subject(trustInput([() => { log.push("handler"); return result; }]), trustEvent(), {});
  log.push("caller");
  const output = await pending;
  trustSame(log, ["handler","caller","trusted"], "plain values still Await");
  trustAssert(output.result === result, "unwrapped result identity");
}
async function observeTrustEventThenable(subject) {
  const log = [], result = { trusted: "yes" }, original = Promise.prototype.then;
  try {
    Promise.prototype.then = function() { throw Error("public Promise.then is not intrinsic Await"); };
    const output = await subject(trustInput([() => ({ get then() {
      log.push("get-then"); return function(resolve) {
        log.push("call-then"); resolve(result);
      };
    }})]), trustEvent(), {});
    trustAssert(output.result === result, "actual thenable adoption");
  } finally { Promise.prototype.then = original; }
  trustSame(log, ["get-then","call-then"], "genuine Await thenable protocol");
}
async function observeTrustEventFailures(subject, asynchronous) {
  const reason = new Error("first failure"); reason.stack = "fixed-stack";
  const log = [], winner = { trusted: "no" }, event = trustEvent();
  const pending = subject(trustInput([
    () => { log.push("first"); if (asynchronous) return Promise.reject(reason); throw reason; },
    () => { log.push("undecided"); return { trusted: "undecided" }; },
    () => { log.push("winner"); return winner; },
    () => { throw Error("late handler"); }
  ]), event, {});
  if (!asynchronous) trustSame(log, ["first","undecided"], "ordinary synchronous catch continues immediately");
  const output = await pending;
  trustSame(log, ["first","undecided","winner"], "sequential failures and winner");
  trustAssert(output.result === winner, "first deciding object unchanged");
  trustSame(output.errors, [{ extensionPath: "/extension", event: "project_trust",
    error: "first failure", stack: "fixed-stack" }], "original error record");
}
async function observeTrustEventLooseResult(subject) {
  const winner = {}, event = trustEvent();
  const output = await subject(trustInput([
    () => null,
    () => winner,
    () => { throw Error("undefined trusted already wins"); }
  ]), event, {});
  trustAssert(output.result === winner && output.errors.length === 1, "no added yes/no validation");
  trustAssert(typeof output.errors[0].error === "string" && Object.hasOwn(output.errors[0], "stack"), "null result caught");
}
async function observeTrustEventTrustedFailure(subject) {
  const marker = { toString() { return "trusted-get failure"; } }, winner = { trusted: "yes" };
  const output = await subject(trustInput([
    () => ({ get trusted() { throw marker; } }),
    () => winner
  ]), trustEvent(), {});
  trustAssert(output.result === winner, "trusted Get remains inside catch");
  trustSame(Object.keys(output.errors[0]), ["extensionPath","event","error","stack"], "record property order");
  trustAssert(output.errors[0].error === "trusted-get failure" && output.errors[0].stack === undefined, "String fallback");
}
async function observeTrustEventFormatOrder(subject, fallback) {
  const savedError = Object.getOwnPropertyDescriptor(globalThis, "Error");
  const savedString = Object.getOwnPropertyDescriptor(globalThis, "String");
  const savedPush = Object.getOwnPropertyDescriptor(Array.prototype, "push");
  const append = savedPush.value, log = [], add = value => Reflect.apply(append, log, [value]);
  let checks = 0, savedRow;
  const reason = { get message() { add("message"); return "message"; }, get stack() { add("stack"); return "stack"; } };
  const event = { get type() { add("event"); return "kind"; } };
  const ext = { get path() { add("path"); return "where"; }, handlers: new Map([["project_trust", [() => { throw reason; }]]]) };
  try {
    Object.defineProperty(Array.prototype, "push", { configurable: true, get() {
      add("push"); return function(row) { add("push()"); savedRow = row; return Reflect.apply(append, this, [row]); };
    }});
    Object.defineProperty(globalThis, "Error", { configurable: true, get() {
      add("Error"); return { [Symbol.hasInstance](value) {
        add("instanceof"); if (value !== reason) throw new savedError.value("reason identity");
        return ++checks === 1 ? !fallback : true;
      }};
    }});
    Object.defineProperty(globalThis, "String", { configurable: true, get() {
      add("String"); return function(value) { "use strict"; add("String()");
        if (this !== undefined || value !== reason) throw new savedError.value("String call inputs"); return "coerced"; };
    }});
    const output = await subject({ extensions: [ext] }, event, {});
    if (output.errors[0] !== savedRow) throw new savedError.value("push receives actual error row");
  } finally {
    Object.defineProperty(globalThis, "Error", savedError);
    Object.defineProperty(globalThis, "String", savedString);
    Object.defineProperty(Array.prototype, "push", savedPush);
  }
  trustSame(log, fallback ?
    ["push","path","event","Error","instanceof","String","String()","Error","instanceof","stack","push()"] :
    ["push","path","event","Error","instanceof","message","Error","instanceof","stack","push()"], "live formatting order");
  trustSame(Object.keys(savedRow), ["extensionPath","event","error","stack"], "actual object literal order");
  trustAssert(savedRow.error === (fallback ? "coerced" : "message") && savedRow.stack === "stack", "independent instanceof decisions");
}
async function observeTrustEventSnapshotFailure(subject) {
  let called = false; const marker = {};
  const input = { extensions: [trustExtension("first", [() => { called = true; }]),
    { get handlers() { throw marker; } }] };
  trustAssert(await trustRejected(subject(input, trustEvent(), {})) === marker && !called, "snapshot errors precede all handlers");
}
function trustLoops(log, handler, changes = {}) {
  const add = value => { log[log.length] = value; };
  const ext = { get path() { add("path"); if (changes.pathFailure) throw changes.pathFailure; return "/loop"; } };
  let innerIndex = 0, outerIndex = 0;
  const inner = {
    [Symbol.iterator]() { add("inner.iterator"); return this; },
    get next() { add("inner.get-next"); if (changes.nextGetterFailure) throw changes.nextGetterFailure;
      return function() {
        add("inner.next"); if (changes.innerStepFailure) throw changes.innerStepFailure;
        if (changes.nonobjectStep) return 1;
        if (innerIndex++) return { done: true };
        return { get done() { add("inner.done"); if (changes.doneFailure) throw changes.doneFailure; return false; },
          get value() { add("inner.value"); if (changes.valueFailure) throw changes.valueFailure; return handler; } };
      };
    },
    get return() { add("inner.get-return"); if (changes.innerReturnGetterFailure) throw changes.innerReturnGetterFailure;
      if (changes.innerReturnValue !== undefined) return changes.innerReturnValue;
      return function() { add("inner.return"); trustAssert(this === inner, "inner close receiver");
        if (changes.innerCloseFailure) throw changes.innerCloseFailure;
        return changes.innerPrimitive ? 7 : {};
      };
    }
  };
  const row = { get ext() { add("row.ext"); return ext; },
    get handlers() { add("row.handlers"); return changes.notIterable ? {} : inner; } };
  const outer = {
    [Symbol.iterator]() { add("outer.iterator"); return this; },
    get next() { add("outer.get-next"); return function() {
      add("outer.next"); if (changes.outerStepFailure) throw changes.outerStepFailure;
      return outerIndex++ ? { done: true } : { get done() { add("outer.done"); return false; },
        get value() { add("outer.value"); return row; } };
    }; },
    get return() { add("outer.get-return"); return function() { add("outer.return");
      trustAssert(this === outer, "outer close receiver");
      if (changes.outerCloseFailure) throw changes.outerCloseFailure;
      return changes.outerPrimitive ? 8 : {};
    }; }
  };
  return { input: { extensions: { map() { add("map"); return outer; } } }, inner, outer, ext };
}
async function observeTrustEventGenericIteration(subject) {
  const log = [];
  const loops = trustLoops(log, () => { log.push("handler"); return { trusted: "undecided" }; });
  const output = await subject(loops.input, trustEvent(), {});
  trustSame(Object.keys(output), ["errors"], "exhaustion result");
  trustSame(log, ["map","outer.iterator","outer.get-next","outer.next","outer.done","outer.value",
    "row.ext","row.handlers","inner.iterator","inner.get-next","inner.next","inner.done","inner.value",
    "handler","inner.next","outer.next"], "cached next and full for-of order");
}
async function observeTrustEventPrimitiveRow(subject) {
  let wrapper;
  const extDescriptor = Object.getOwnPropertyDescriptor(Number.prototype, "ext");
  const handlersDescriptor = Object.getOwnPropertyDescriptor(Number.prototype, "handlers");
  const winner = { trusted: "yes" };
  try {
    Object.defineProperty(Number.prototype, "ext", { configurable: true, get() { "use strict";
      trustAssert(typeof this === "object" && +this === 13, "object-binding ToObject");
      wrapper = this; return {};
    }});
    Object.defineProperty(Number.prototype, "handlers", { configurable: true, get() { "use strict";
      trustAssert(this === wrapper, "both destructuring Gets use one wrapper");
      return [() => winner];
    }});
    const result = await subject({ extensions: { map() { return [13]; } } }, trustEvent(), {});
    trustAssert(result.result === winner, "primitive row accepted by original object binding");
  } finally {
    if (extDescriptor) Object.defineProperty(Number.prototype, "ext", extDescriptor); else delete Number.prototype.ext;
    if (handlersDescriptor) Object.defineProperty(Number.prototype, "handlers", handlersDescriptor); else delete Number.prototype.handlers;
  }
}
async function observeTrustEventStepFailure(subject, kind) {
  const log = [], marker = {}, changes = { [kind]: marker };
  if (kind === "nonobjectStep") changes.nonobjectStep = true;
  const loops = trustLoops(log, () => { throw Error("handler must not run"); }, changes);
  const reason = await trustRejected(subject(loops.input, trustEvent(), {}));
  trustAssert(kind === "nonobjectStep" ? reason instanceof TypeError : reason === marker, "actual step completion");
  trustAssert(!log.includes("inner.get-return"), "failing next/value never closes its own iterator");
  if (kind === "outerStepFailure") trustAssert(!log.includes("outer.get-return"), "outer next failure does not close itself");
  else trustSame(log.slice(-2), ["outer.get-return","outer.return"], "enclosing outer closes");
}
async function observeTrustEventStartFailure(subject, missing) {
  const log = [], marker = {};
  const loops = trustLoops(log, () => ({}), missing ? { notIterable: true } : { nextGetterFailure: marker });
  const reason = await trustRejected(subject(loops.input, trustEvent(), {}));
  trustAssert(missing ? reason instanceof TypeError : reason === marker, "start failure reason");
  trustAssert(!log.includes("inner.get-return"), "no inner catch record on failed start");
  trustSame(log.slice(-2), ["outer.get-return","outer.return"], "outer record still closes");
}
async function observeTrustEventReturnClose(subject) {
  const log = [], winner = { get trusted() { log.push("trusted"); return "yes"; } };
  const loops = trustLoops(log, () => winner);
  const output = await subject(loops.input, trustEvent(), {});
  trustAssert(output.result === winner, "selected result survives both closes");
  trustSame(log.slice(-5), ["trusted","inner.get-return","inner.return","outer.get-return","outer.return"], "normal close order");
}
async function observeTrustEventBadClose(subject, kind) {
  const log = [], marker = {};
  const changes = kind === "inner" ? { innerPrimitive: true, outerCloseFailure: marker } :
    kind === "outer" ? { outerPrimitive: true } : { innerReturnValue: 1, outerCloseFailure: marker };
  const loops = trustLoops(log, () => ({ trusted: "yes" }), changes);
  const reason = await trustRejected(subject(loops.input, trustEvent(), {}));
  trustAssert(reason instanceof TypeError, "invalid normal close rejects with TypeError");
  trustSame(log.slice(-2), ["outer.get-return","outer.return"], "outer close still happens and keeps original inner failure");
  trustAssert(!log.includes("path"), "iterator-close failure is outside handler catch");
}
async function observeTrustEventFormattingFailure(subject, pushFailure) {
  const log = [], marker = {}, later = {};
  const changes = { innerCloseFailure: later, outerCloseFailure: later };
  if (!pushFailure) changes.pathFailure = marker;
  const loops = trustLoops(log, () => { throw "handler"; }, changes);
  const savedPush = Object.getOwnPropertyDescriptor(Array.prototype, "push");
  let reason;
  try {
    if (pushFailure) Object.defineProperty(Array.prototype, "push", { configurable: true,
      get() { log[log.length] = "push-get"; throw marker; } });
    reason = await trustRejected(subject(loops.input, trustEvent(), {}));
  } finally { Object.defineProperty(Array.prototype, "push", savedPush); }
  trustAssert(reason === marker, "ordinary close failures cannot replace formatting throw");
  trustSame(log.slice(-4), ["inner.get-return","inner.return","outer.get-return","outer.return"], "throw closes inner then outer");
  if (pushFailure) trustAssert(!log.includes("path"), "push lookup is before object literal fields");
}
async function observeTrustEventThrowClosePrimitive(subject) {
  const log = [], marker = {};
  const loops = trustLoops(log, () => { throw "handler"; }, {
    pathFailure: marker, innerPrimitive: true, outerPrimitive: true
  });
  trustAssert(await trustRejected(subject(loops.input, trustEvent(), {})) === marker, "throw close ignores primitive result");
  trustSame(log.slice(-4), ["inner.get-return","inner.return","outer.get-return","outer.return"], "both throw-close methods called");
}
async function observeTrustEventReentry(subject) {
  const log = [], innerResult = { trusted: "yes", inner: true }, outerResult = { trusted: "no" };
  const input = trustInput([async () => {
    log.push("outer");
    const inner = await subject(trustInput([() => { log.push("inner"); return innerResult; }]), trustEvent(), {});
    trustAssert(inner.result === innerResult, "independent nested activation");
    return { trusted: "undecided" };
  }, () => { log.push("outer-next"); return outerResult; }]);
  const output = await subject(input, trustEvent(), {});
  trustAssert(output.result === outerResult && output.errors.length === 0, "outer state survived nested Await");
  trustSame(log, ["outer","inner","outer-next"], "reentry order");
}
async function observeTrustEventPrivateData(subject, hooks, asynchronous) {
  const data = hooks.freshPrivateData(), winner = { trusted: "yes" };
  trustAssert(hooks.isUnmarkedPrivateData(data), "real successful native private DATA");
  const output = await subject(trustInput([
    () => { if (asynchronous) return Promise.reject(data); throw data; }, () => winner
  ]), trustEvent(), {});
  trustAssert(output.result === winner && output.errors.length === 1, "DATA caught and dispatch continues");
  trustAssert(output.errors[0].error === data.message && hooks.isUnmarkedPrivateData(data), "private provenance did not become fatal");
}
async function observeTrustEventAwaitRoots(subject, hooks) {
  let resolve;
  const gate = new Promise(r => { resolve = r; });
  const pending = Reflect.apply(subject, hooks.make(4), [
    Object.assign(hooks.make(3), { extensions: [trustExtension("/roots", [() => gate])] }),
    hooks.make(0), hooks.make(1), hooks.make(2)
  ]);
  trustEventGC();
  for (let slot = 0; slot < 5; slot++) trustAssert(hooks.count(slot) === 0, "actual argument/receiver root before Await");
  resolve({ trusted: "yes" });
  const output = await pending;
  trustAssert(output.result.trusted === "yes", "genuine resumed body");
  trustEventGC();
  for (let slot = 0; slot < 5; slot++) trustAssert(hooks.count(slot) === 1, "all original argument roots retired once");
}
async function observeTrustEventAbandonedRoots(subject, hooks) {
  globalThis.trustAbandonedGate = new Promise(() => {});
  const pending = subject(Object.assign(hooks.make(0), {
    extensions: [trustExtension("/abandoned", [() => globalThis.trustAbandonedGate])]
  }), hooks.make(1), hooks.make(2));
  trustEventGC();
  for (let slot = 0; slot < 3; slot++) trustAssert(hooks.count(slot) === 0, "suspended owner roots retained");
  delete globalThis.trustAbandonedGate;
  trustEventGC();
  for (let slot = 0; slot < 3; slot++) trustAssert(hooks.count(slot) === 1, "abandoned activation releases original roots");
  trustAssert(trustEventPromisePending(pending), "outer Promise remains genuinely unsettled");
}
async function observeTrustEventFatal(subject, hooks, afterAwait) {
  hooks.freshPrivateData();
  const log = [];
  const loops = trustLoops(log, () => {
    if (afterAwait) return { get trusted() { hooks.raiseNativeFatal(); } };
    hooks.raiseNativeFatal();
  });
  Object.defineProperty(loops.inner, "return", { get() { hooks.visit(2); return () => ({}); } });
  Object.defineProperty(loops.ext, "path", { get() { hooks.visit(1); return "/unexpected-catch"; } });
  try { await subject(loops.input, trustEvent(), {}); }
  catch (_) { hooks.visit(3); }
  hooks.record.guestReached = true;
}
async function observeTrustEventRetirementFatal(subject, hooks, cancel) {
  hooks.freshPrivateData();
  const loops = trustLoops([], () => ({ get trusted() {
    if (cancel) hooks.armCancel(0); else hooks.armFatal(0);
    return hooks.make(0);
  }}));
  Object.defineProperty(loops.inner, "return", { get() { hooks.visit(2); return () => ({}); } });
  Object.defineProperty(loops.ext, "path", { get() { hooks.visit(1); return "/unexpected-catch"; } });
  try { await subject(loops.input, trustEvent(), {}); }
  catch (_) { hooks.visit(3); }
  hooks.record.guestReached = true;
}
async function observeTrustEventPendingNormal(subject) {
  const marker = new Error("actual ordinary pending"), winner = { trusted: "yes" };
  globalThis.trustPendingReason = marker;
  const output = await subject(trustInput([trustEventPendingNormal, () => winner]), trustEvent(), {});
  trustAssert(output.result === winner && output.errors.length === 1 &&
    output.errors[0].error === marker.message, "pending exception beats successful native return");
  delete globalThis.trustPendingReason;
}
async function observeTrustEventEscapedSnapshot(subject) {
  let captured;
  const first = await subject({ extensions: { map(callback) { captured = callback; return []; } } }, trustEvent(), {});
  trustAssert(first.errors.length === 0, "snapshot invocation completed");
  let observed;
  const handler = () => ({ trusted: "yes" });
  const ext = { handlers: { get(event) { observed = event; return [handler]; } } };
  const row = captured.call({ ignored: true }, ext);
  trustAssert(observed === "project_trust" && row.ext === ext && row.handlers[0] === handler, "escaped arrow keeps original import-call capture");
}
async function observeTrustEventConstructorRetirement(subject, hooks) {
  const saved = Object.getOwnPropertyDescriptor(globalThis, "Error");
  const RealError = saved.value;
  let count = 0;
  const reason = {
    get message() { if (hooks.count(0) !== 1) throw new RealError("first constructor operand retained"); return "message"; },
    get stack() { if (hooks.count(1) !== 1) throw new RealError("second constructor operand retained"); return "stack"; }
  };
  let output;
  try {
    Object.defineProperty(globalThis, "Error", { configurable: true, get() {
      return Object.assign(hooks.make(count++), { [Symbol.hasInstance](value) { return value === reason; } });
    }});
    output = await subject(trustInput([() => { throw reason; }]), trustEvent(), {});
  } finally { Object.defineProperty(globalThis, "Error", saved); }
  trustAssert(output.errors.length === 1 && output.errors[0].error === "message" &&
    output.errors[0].stack === "stack" && count === 2, "instanceof operand retirement before branch Gets");
}
async function observeTrustEventTrustedRetirement(subject, hooks) {
  const loops = trustLoops([], () => ({ get trusted() { return hooks.make(0); } }));
  Object.defineProperty(loops.inner, "return", { get() {
    trustAssert(hooks.count(0) === 1, "comparison operand retired before IteratorClose");
    return () => ({});
  }});
  const output = await subject(loops.input, trustEvent(), {});
  trustAssert(Object.hasOwn(output, "result") && output.errors.length === 0, "non-undecided object still wins");
}
