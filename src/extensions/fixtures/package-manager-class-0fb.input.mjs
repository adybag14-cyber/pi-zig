// Prepared full ordinary-class authority. This inspects the actual original
// or complete actual native class; it manufactures no missing methods.
const {DefaultPackageManager,SettingsManager}=PackageAPI;
const prototype=DefaultPackageManager.prototype,describe=fn=>({name:fn.name,length:fn.length,async:PackageAPI.isAsyncFunction(fn),ownPrototype:Object.hasOwn(fn,'prototype')});
const descriptors=Reflect.ownKeys(prototype).map(name=>{const d=Object.getOwnPropertyDescriptor(prototype,name);return{name,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,function:describe(d.value)}});
const manager=new DefaultPackageManager({cwd:PackageAPI.cwd,agentDir:PackageAPI.agentDir,settingsManager:SettingsManager.inMemory(),builtinExtensions:['mcp']});
globalThis.packageClassRows=[{name:'complete-class-declaration-order-and-brands',descriptors,parent:Object.getPrototypeOf(prototype)===Object.prototype,ownFields:Object.keys(manager),builtinExtensions:manager.builtinExtensions}];
globalThis.packageClassComplete=true;
