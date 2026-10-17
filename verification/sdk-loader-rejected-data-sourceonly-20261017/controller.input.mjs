// Actual guest user module. Owned runner imports this exact body to create the
// real controller before importing the retained physical extension module.
export const controller = {calls:0,delivered:0,messageReads:0,diagnosticReads:0};
controller.gate = new Promise((resolve,reject) => { controller.resolve=resolve; controller.reject=reject; });
controller.reason = new Error('actual-controlled-extension-rejection');
controller.expectedError = 'Failed to load extension: actual-controlled-extension-rejection';
Object.defineProperty(controller.reason,'toString',{configurable:true,get(){controller.diagnosticReads++;return Error.prototype.toString;}});
controller.installSameObjectMessageRethrow = () => Object.defineProperty(controller.reason,'message',{configurable:true,get(){controller.messageReads++;throw controller.reason;}});
controller.installActualDiscardFault = runtime => {
  const original=runtime.trackEventBusSubscription;
  runtime.trackEventBusSubscription=function(unsubscribe){
    return original.call(this,()=>{unsubscribe();ActualSdkLoaderFreshOOM();});
  };
};
globalThis.ActualSdkLoaderController=controller;
