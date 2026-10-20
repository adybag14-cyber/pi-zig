'use strict';
// Actual selected Node24.14 internal/util declaration. SafeSet is the original
// primordial import; process is the genuine BuiltinLoader wrapper parameter.
// This private fixture projection does not publish an internal/util namespace.
export function createExperimentalWarningSource(SafeSet, process) {
const experimentalWarnings = new SafeSet();

function emitExperimentalWarning(feature, messagePrefix, code, ctor) {
  if (experimentalWarnings.has(feature)) return;
  experimentalWarnings.add(feature);
  let msg = `${feature} is an experimental feature and might change at any time`;
  if (messagePrefix) {
    msg = messagePrefix + msg;
  }
  process.emitWarning(msg, 'ExperimentalWarning', code, ctor);
}

return emitExperimentalWarning;
}
