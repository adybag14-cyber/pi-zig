let loaderRealItem,loaderRealCount=0,loaderRealResolve;
const loaderRealEvents=[];
const loaderRealDone=new Promise(resolve=>loaderRealResolve=resolve);
const loaderRealUi={requestRender(){loaderRealCount++;loaderRealEvents.push(['render',loaderRealCount]);if(loaderRealItem){loaderRealItem.stop();loaderRealResolve();}}};
loaderRealItem=new Loader(loaderRealUi,text=>text,text=>text,'run',{frames:['a','b'],intervalMs:1});
let loaderRealTimeout;
try{await Promise.race([loaderRealDone,new Promise((_,reject)=>loaderRealTimeout=setTimeout(()=>reject(Error('loader real timer deadline')),5000))]);}finally{clearTimeout(loaderRealTimeout);loaderRealItem.stop();}
const loaderRealTimerResult={frame:loaderRealItem.currentFrame,text:loaderRealItem.text,active:!!loaderRealItem.intervalId,count:loaderRealCount,events:loaderRealEvents};
