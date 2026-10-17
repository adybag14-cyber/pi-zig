const frames = globalThis.ownedCapture();
globalThis.ownedModuleObservation = {
  functionUndefined: frames[0].getFunction() === undefined,
  receiverUndefined: frames[0].getThis() === undefined,
  filename: frames[0].getFileName(),
};
