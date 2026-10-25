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
