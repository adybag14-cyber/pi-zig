"use strict";
globalThis.makeOriginalModuleLoad = function(debugWithTimer, tracingChannel) {
const Module = actualWrapModule;
function getLazy(initializer) {
  let value;
  let initialized = false;
  return function() {
    if (initialized === false) {
      value = initializer();
      initialized = true;
    }
    return value;
  };
}

let { startTimer, endTimer } = debugWithTimer('module_timer', (start, end) => {
  startTimer = start;
  endTimer = end;
});

const onRequire = getLazy(() => tracingChannel('module.require'));

function wrapModuleLoad(request, parent, isMain, options) {
  const logLabel = `[${parent?.id || ''}] [${request}]`;
  const traceLabel = `require('${request}')`;
  const channel = onRequire();

  startTimer(logLabel, traceLabel);

  try {
    if (channel.hasSubscribers) {
      return onRequire().traceSync(Module._load, {
        __proto__: null,
        parentFilename: parent?.filename,
        id: request,
      }, Module, request, parent, isMain, options);
    }
    // No subscribers, skip the wrapping to avoid clobbering stack traces
    // and debugging steps.
    return Module._load(request, parent, isMain, options);
  } finally {
    endTimer(logLabel, traceLabel);
  }
}

return wrapModuleLoad;
};
