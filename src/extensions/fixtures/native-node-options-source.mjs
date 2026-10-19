'use strict';
// Selected declarations copied byte-for-byte from retained Node24.14 options.js.
// The two imported callables below are the actual native options serializers in
// both branches. process is the original BuiltinLoader wrapper parameter.
// This test projection is not an internal/options namespace.
export function createNodeOptionsSource(binding, process) {
const getCLIOptionsValues = binding.values;
const getEmbedderOptionsFromBinding = binding.embedder;
let warnOnAllowUnauthorized = true;
let optionsDict;
let embedderOptions;

function getCLIOptionsFromBinding() {
  return optionsDict ??= getCLIOptionsValues();
}

function getEmbedderOptions() {
  return embedderOptions ??= getEmbedderOptionsFromBinding();
}

function refreshOptions() {
  optionsDict = undefined;
}

function getOptionValue(optionName) {
  return getCLIOptionsFromBinding()[optionName];
}

function getAllowUnauthorized() {
  const allowUnauthorized = process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0';

  if (allowUnauthorized && warnOnAllowUnauthorized) {
    warnOnAllowUnauthorized = false;
    process.emitWarning(
      'Setting the NODE_TLS_REJECT_UNAUTHORIZED ' +
      'environment variable to \'0\' makes TLS connections ' +
      'and HTTPS requests insecure by disabling ' +
      'certificate verification.');
  }
  return allowUnauthorized;
}

return { getOptionValue, getEmbedderOptions, refreshOptions, getAllowUnauthorized };
}
