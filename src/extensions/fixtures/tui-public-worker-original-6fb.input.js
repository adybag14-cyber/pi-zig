import {Loader,CancellableLoader,Image,setCapabilities,setCellDimensions,isFocusable,isViewportTUI,formatProgramStatus,parseTerminalColorSchemeReport,renderLatex} from '@earendil-works/pi-tui';
setCapabilities({images:null,trueColor:true,hyperlinks:false});setCellDimensions({widthPx:8,heightPx:16});
const events=[],ui={requestRender(){events.push('render');}};
const loader=new CancellableLoader(ui,text=>text,text=>text,'working',{frames:[]});
loader.onAbort=function(){events.push(['abort',this===loader,this.aborted]);};
const before=loader.render(12);loader.handleInput('\x1b');loader.dispose();
const image=new Image('unknown','image/test',{fallbackColor:text=>text},{filename:'pixel'},{widthPx:4,heightPx:3});const imageLines=image.render(40);
let realLoader,resolveTick;const tickDone=new Promise(resolve=>resolveTick=resolve);let ticks=0;
realLoader=new Loader({requestRender(){ticks++;if(realLoader){realLoader.stop();resolveTick();}}},text=>text,text=>text,'actual',{frames:['a','b'],intervalMs:1});
let deadline;try{await Promise.race([tickDone,new Promise((_,reject)=>deadline=setTimeout(()=>reject(Error('TUI real-worker timer deadline')),5000))]);}finally{clearTimeout(deadline);realLoader.stop();}
export const observed={before,events,aborted:loader.aborted,imageLines,imageCache:imageLines===image.render(40),focus:isFocusable({focused:false}),viewport:isViewportTUI({[Symbol.for('@earendil-works/pi-tui/viewport')]:true}),status:formatProgramStatus({state:'working',app:'pi',message:' live '}),scheme:parseTerminalColorSchemeReport('\x1b[?997;2n'),latex:renderLatex('x^2'),timer:{frame:realLoader.currentFrame,text:realLoader.text,ticks,active:!!realLoader.intervalId}};
console.log(JSON.stringify(observed));
