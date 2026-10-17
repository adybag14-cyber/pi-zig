// Actual controlled guest extension, imported by the REAL production pipeline.
// No substitute jiti/API/registry/cache is used. Controller comes from the
// separately evaluated retained genuine guest user-module body.
const controller=globalThis.ActualSdkLoaderController;
export default function actualControlledExtension(pi) {
  controller.calls++;
  pi.events.on('actual-sdk-rejected-data',()=>{controller.delivered++;});
  return controller.gate;
}
