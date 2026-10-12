Error.stackTraceLimit=1;
function ownedFrame(){return new Error('source-frame')}
const originalError=ownedFrame();let observed;
Error.prepareStackTrace=(error,frames)=>{observed={same:error===originalError,count:frames.length,frames:frames.map(frame=>({name:frame.getFunctionName(),file:frame.getFileName(),line:frame.getLineNumber(),column:frame.getColumnNumber(),native:frame.isNative(),constructor:frame.isConstructor(),originalFunction:frame.getFunction()===ownedFrame}))};return'prepared-source-frame'};
globalThis.ownedErrorFrameResult={stack:originalError.stack,observed,second:originalError.stack};