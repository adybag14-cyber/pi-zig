// Alternative actual physical user module: rejection occurs during real import,
// before the default factory runs, exercising loadExtensionModule's own Await.
const controller=globalThis.ActualSdkSettledController;
controller.calls++;
await controller.gate;
export default function actualNotReachedFactory(){throw new Error('rejected import must not invoke a factory');}
