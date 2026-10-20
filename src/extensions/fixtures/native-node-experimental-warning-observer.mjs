'use strict';
import process from 'node:process';
function warningAssert(value, message) {
  if (!value) throw new Error(message);
}
function warningRestore(object, key, descriptor) {
  if (descriptor) Object.defineProperty(object, key, descriptor);
  else delete object[key];
}
function warningWithEmitter(run) {
  const descriptor = Object.getOwnPropertyDescriptor(process, "emitWarning");
  const calls = [];
  Object.defineProperty(process, "emitWarning", {configurable:true, value:function() {
    calls.push({receiver:this, args:Array.from(arguments)});
  }});
  try { return run(calls); }
  finally { warningRestore(process, "emitWarning", descriptor); }
}
function observeExperimentalWarningShape(warn) {
  warningWithEmitter(calls => {
    warningAssert(warn.name === "emitExperimentalWarning" && warn.length === 4, "original ordinary function shape");
    const descriptor = Object.getOwnPropertyDescriptor(warn, "prototype");
    warningAssert(descriptor && descriptor.writable && !descriptor.enumerable && !descriptor.configurable,
      "original constructible prototype descriptor");
    const receiver = new warn("constructor feature");
    warningAssert(Object.getPrototypeOf(receiver) === warn.prototype && calls.length === 1, "actual ordinary constructor receiver");
    warningAssert(warn("constructor feature") === undefined && calls.length === 1, "seen feature early return");
  });
}
function observeExperimentalWarningMessage(warn) {
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  const trace = [], code = {}, ctor = function selectedConstructor() {};
  const feature = {[Symbol.toPrimitive](hint) {
    trace.push(["feature", hint]); return "custom feature";
  }};
  const prefix = {[Symbol.toPrimitive](hint) {
    trace.push(["prefix", hint]); return "prefix: ";
  }};
  Object.defineProperty(process, "emitWarning", {configurable:true, get() {
    trace.push(["get"]);
    return function(message, kind, actualCode, actualCtor) {
      trace.push(["call"]);
      warningAssert(this === process && arguments.length === 4, "original warning receiver and arity");
      warningAssert(message === "prefix: custom feature is an experimental feature and might change at any time",
        "eager template then ordinary prefix addition");
      warningAssert(kind === "ExperimentalWarning" && actualCode === code && actualCtor === ctor, "unchanged original warning operands");
      return 42;
    };
  }});
  try {
    warningAssert(warn(feature, prefix, code, ctor) === undefined, "warning result is discarded");
    warningAssert(JSON.stringify(trace) === '[["feature","string"],["prefix","default"],["get"],["call"]]',
      "actual coercion and callee order");
  } finally { warningRestore(process, "emitWarning", original); }
}
function observeExperimentalWarningMembership(warn) {
  warningWithEmitter(calls => {
    warn(NaN); warn(NaN); warn(-0); warn(0); warn("0");
    const one = {toString(){return "same text";}}, two = {toString(){return "same text";}};
    warn(one); warn(one); warn(two);
    warningAssert(calls.length === 5, "SafeSet uses SameValueZero and original object identity");
    warningAssert(calls[3].args[0] === calls[4].args[0], "equal message text does not merge distinct object keys");
  });
}
function observeExperimentalWarningConversionFailure(warn) {
  warningWithEmitter(calls => {
    const reason = {};
    let conversions = 0;
    const feature = {[Symbol.toPrimitive]() { conversions++; throw reason; }};
    let caught;
    try { warn(feature); } catch (error) { caught = error; }
    warningAssert(caught === reason && conversions === 1 && calls.length === 0, "actual first feature conversion failure");
    warningAssert(warn(feature) === undefined && conversions === 1 && calls.length === 0, "membership precedes and survives failed conversion");
    const symbol = Symbol("symbol feature");
    caught = undefined;
    try { warn(symbol); } catch (error) { caught = error; }
    warningAssert(caught instanceof TypeError && warn(symbol) === undefined && calls.length === 0, "actual template Symbol conversion and remembered key");
  });
}
function observeExperimentalWarningPrefix(warn) {
  warningWithEmitter(calls => {
    let index = 0;
    for (const prefix of [undefined, null, false, 0, -0, NaN, ""]) {
      const feature = "prefix case " + index++;
      warn(feature, prefix);
      warningAssert(calls[calls.length - 1].args[0] === feature + " is an experimental feature and might change at any time",
        "falsy prefix skips addition");
    }
    const reason = {};
    const feature = "failing prefix";
    let conversions = 0, caught;
    const prefix = {[Symbol.toPrimitive](hint) {
      warningAssert(hint === "default", "prefix ordinary addition hint"); conversions++; throw reason;
    }};
    try { warn(feature, prefix); } catch (error) { caught = error; }
    warningAssert(caught === reason && conversions === 1 && calls.length === 7, "prefix throws after feature is remembered");
    warn(feature, prefix);
    warningAssert(conversions === 1 && calls.length === 7, "failed prefix is not retried for the same feature");
  });
}
function observeExperimentalWarningEmissionFailure(warn) {
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  const reason = {};
  let lookups = 0, calls = 0, caught;
  Object.defineProperty(process, "emitWarning", {configurable:true, get() {
    lookups++;
    if (lookups === 1) throw reason;
    return function() { calls++; throw reason; };
  }});
  try {
    try { warn("getter failure"); } catch (error) { caught = error; }
    warningAssert(caught === reason && warn("getter failure") === undefined && lookups === 1,
      "failed warning getter does not roll back membership");
    caught = undefined;
    try { warn("call failure"); } catch (error) { caught = error; }
    warningAssert(caught === reason && warn("call failure") === undefined && lookups === 2 && calls === 1,
      "failed warning call does not roll back membership");
  } finally { warningRestore(process, "emitWarning", original); }
}
function observeExperimentalWarningReentry(warn) {
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  let conversions = 0, calls = 0;
  const feature = {[Symbol.toPrimitive]() {
    conversions++;
    warningAssert(warn(feature) === undefined, "same feature already published during conversion");
    return "reentrant feature";
  }};
  Object.defineProperty(process, "emitWarning", {configurable:true, value:function() {
    calls++;
    warningAssert(warn(feature) === undefined, "same feature already published during warning call");
  }});
  try {
    warn(feature);
    warningAssert(conversions === 1 && calls === 1, "actual nested calls perform no later conversion or warning");
  } finally { warningRestore(process, "emitWarning", original); }
}
function observeExperimentalWarningPrimordials(warn) {
  const actualSet = Set;
  const add = Object.getOwnPropertyDescriptor(actualSet.prototype, "add");
  const has = Object.getOwnPropertyDescriptor(actualSet.prototype, "has");
  const globalSet = Object.getOwnPropertyDescriptor(globalThis, "Set");
  let visits = 0;
  warningWithEmitter(calls => {
    try {
      globalThis.Set = function() { visits++; throw "late Set"; };
      Object.defineProperty(actualSet.prototype, "add", {configurable:true, value:function() { visits++; throw "late add"; }});
      Object.defineProperty(actualSet.prototype, "has", {configurable:true, value:function() { visits++; throw "late has"; }});
      warn("captured SafeSet"); warn("captured SafeSet");
      warningAssert(visits === 0 && calls.length === 1, "original SafeSet owns captured methods and constructor");
    } finally {
      warningRestore(actualSet.prototype, "add", add);
      warningRestore(actualSet.prototype, "has", has);
      warningRestore(globalThis, "Set", globalSet);
    }
  });
}
function observeExperimentalWarningProcess(warn) {
  const globalProcess = Object.getOwnPropertyDescriptor(globalThis, "process");
  let globalReads = 0;
  warningWithEmitter(calls => {
    try {
      Object.defineProperty(globalThis, "process", {configurable:true, get() {
        globalReads++; throw "late global process";
      }});
      warn("global getter replacement");
      Object.defineProperty(globalThis, "process", {configurable:true, value:{
        get emitWarning() { throw "replacement process"; },
      }});
      warn("global object replacement");
      warningAssert(globalReads === 0 && calls.length === 2 && calls.every(call => call.receiver === process),
        "actual builtin process parameter survives both global replacements");
    } finally { warningRestore(globalThis, "process", globalProcess); }
  });
}
function installExperimentalWarningTdz() {
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  const record = {calls:0, tdz:false, result:false};
  Object.defineProperty(process, "emitWarning", {configurable:true, value:function() {
    warningAssert(this === process, "TDZ retained process receiver"); record.calls++;
  }});
  globalThis.actualWarningTdzRecord = record;
  globalThis.actualWarningRestoreTdz = function() {
    warningRestore(process, "emitWarning", original);
    delete globalThis.actualWarningRestoreTdz;
  };
}
function observeExperimentalWarningRetirement(warn) {
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  let calls = 0;
  Object.defineProperty(process, "emitWarning", {configurable:true, get() {
    const holder = actualWarningHolder(0);
    return function() {
      void holder; calls++;
      return actualWarningHolder(1);
    };
  }});
  try {
    warn("retirement");
    warningAssert(calls === 1 && actualWarningFreedCount(0) === 1 && actualWarningFreedCount(1) === 1,
      "actual selected warning callee and discarded result retire before caller resumes");
  } finally { warningRestore(process, "emitWarning", original); }
}
function observeExperimentalWarningPrivateData(warn, route) {
  const reason = actualWarningPrivateData();
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  let caught = 0;
  const throwing = {[Symbol.toPrimitive]() { throw reason; }};
  Object.defineProperty(process, "emitWarning", {configurable:true, get() {
    if (route === 2) throw reason;
    return function() { if (route === 3) throw reason; };
  }});
  try {
    try { warn(route === 0 ? throwing : "private route", route === 1 ? throwing : undefined); }
    catch (error) { warningAssert(error === reason, "exact private DATA identity"); caught++; }
    warningAssert(caught === 1, "actual private DATA remains ordinary at each selected callback");
  } finally { warningRestore(process, "emitWarning", original); }
}
function observeExperimentalWarningFlaggedReturn(warn) {
  const reason = actualWarningFlaggedData();
  globalThis.actualWarningSelectedData = reason;
  const original = Object.getOwnPropertyDescriptor(process, "emitWarning");
  let caught = 0, result;
  Object.defineProperty(process, "emitWarning", {configurable:true, value:function() { return reason; }});
  try {
    try { result = warn("flagged successful return"); } catch { caught++; }
    warningAssert(result === undefined && caught === 0, "successful flagged warning result stays discarded DATA");
  } finally { warningRestore(process, "emitWarning", original); }
}
function installExperimentalWarningFatal(retireCallee) {
  const record = globalThis.actualWarningProgress;
  Object.defineProperty(process, "emitWarning", {configurable:true, get() {
    record.getter++;
    if (!retireCallee) return actualWarningFatal();
    const holder = actualWarningHolder(0);
    return function() {
      void holder;
      record.callback++;
    };
  }});
  globalThis.actualWarningFeature = {[Symbol.toPrimitive]() {
    record.conversion++; return "fatal warning feature";
  }};
}
function observeExperimentalWarningRetainedFeature(warn) {
  warningWithEmitter(calls => {
    const feature = actualWarningHolder(2);
    Object.defineProperty(feature, Symbol.toPrimitive, {value:function() { return "retained feature"; }});
    warn(feature);
    warningAssert(calls.length === 1, "real feature reached the warning");
  });
  warningAssert(actualWarningFreedCount(2) === 0, "actual private SafeSet retains the feature after caller scope ends");
}
