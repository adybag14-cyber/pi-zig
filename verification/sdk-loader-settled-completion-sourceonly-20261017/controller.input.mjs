// Genuine user module; import before the actual physical guest extension.
export const controller={calls:0,delivered:0,messageReads:0,diagnosticReads:0,closeGets:0,closeCalls:0};
controller.gate=new Promise((resolve,reject)=>{controller.resolve=resolve;controller.reject=reject;});
controller.reason=new Error('actual-user-extension-error');
Object.defineProperty(controller.reason,'toString',{get(){controller.diagnosticReads++;return Error.prototype.toString;}});
controller.observeMessage=(reason,message)=>Object.defineProperty(reason,'message',{configurable:true,get(){controller.messageReads++;return message;}});
controller.throwMessage=reason=>Object.defineProperty(reason,'message',{configurable:true,get(){controller.messageReads++;throw reason;}});
controller.fatalMessage=()=>Object.defineProperty(controller.reason,'message',{configurable:true,get(){controller.messageReads++;return ActualSdkSettledFatal();}});
controller.makeClosingPaths=path=>({[Symbol.iterator](){let first=true;return{next(){if(first){first=false;return{value:path,done:false}}return{done:true}},get return(){controller.closeGets++;return function(){controller.closeCalls++;throw new Error('ordinary IteratorClose override must be suppressed')}}}}});
globalThis.ActualSdkSettledController=controller;
