// Prepared original PUBLIC jiti caller; no copied factory or intercepted methods.
// Inputs are the genuine imported jiti package and retained physical fixture root.
export function observeOriginalJiti(actualCreateJiti,physicalRoot){
 const jiti=actualCreateJiti(physicalRoot+'/entry.cjs',{tsconfigPaths:physicalRoot+'/simple',fsCache:false,moduleCache:false});
 return{resolved:jiti.resolve('exact'),extensions:Object.keys(jiti.extensions)};
}
