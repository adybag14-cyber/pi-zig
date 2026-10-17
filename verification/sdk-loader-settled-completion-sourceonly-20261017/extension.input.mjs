// Import through the genuine native jiti/module/loader graph, not a fake input.
const controller=globalThis.ActualSdkSettledController;
export default function actualSettledExtension(pi){
  controller.calls++;
  pi.events.on('actual-sdk-settled-completion',()=>{controller.delivered++;});
  return controller.gate;
}
