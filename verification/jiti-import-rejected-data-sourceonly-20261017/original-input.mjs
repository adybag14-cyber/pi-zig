// Original user module source for actual factory evaluation. Its real Module
// cache exports this exact intrinsic Promise; no fake jitiRequire/importer.
export const cachedModuleSource = `module.exports = new Promise((resolve, reject) => {
  globalThis.ActualJitiImportRelease = {resolve, reject};
});`;
export function ordinaryReason() {
  const diagnosticCounter = {reads:0};
  const reason = new Error("original rejected data");
  Object.defineProperty(reason,"toString",{configurable:true,get(){
    diagnosticCounter.reads++;
    return function(){return "original rejected data";};
  }});
  return {reason,diagnosticCounter};
}
export function sameObjectRethrowOptions(reason) {
  return Object.defineProperty({},"default",{get(){throw reason;}});
}
export function freshFaultOptions() {
  return Object.defineProperty({},"default",{get(){return globalThis.ActualJitiImportFreshOOM();}});
}
// Reference only: hidden native flags/tags are driver-side mutations, never
// substitute JS fields. Native pending-hook/budget-interrupt controls use actual
// trusted VM events and require separate native qualification, not Node goldens.
