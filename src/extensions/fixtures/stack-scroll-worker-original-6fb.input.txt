import {Loader,CancellableLoader,Image,setCapabilities,setCellDimensions,isFocusable,isViewportTUI,formatProgramStatus,parseTerminalColorSchemeReport,renderLatex,HStack,VStack,ScrollView} from '@earendil-works/pi-tui';
setCapabilities({images:null,trueColor:true,hyperlinks:false});setCellDimensions({widthPx:8,heightPx:16});
const events=[],ui={requestRender(){events.push('render');}};
const loader=new CancellableLoader(ui,text=>text,text=>text,'working',{frames:[]});
loader.onAbort=function(){events.push(['abort',this===loader,this.aborted]);};
const before=loader.render(12);loader.handleInput('\x1b');loader.dispose();
const image=new Image('unknown','image/test',{fallbackColor:text=>text},{filename:'pixel'},{widthPx:4,heightPx:3});const imageLines=image.render(40);
let realLoader,resolveTick;const tickDone=new Promise(resolve=>resolveTick=resolve);let ticks=0;
realLoader=new Loader({requestRender(){ticks++;if(realLoader){realLoader.stop();resolveTick();}}},text=>text,text=>text,'actual',{frames:['a','b'],intervalMs:1});
let deadline;try{await Promise.race([tickDone,new Promise((_,reject)=>deadline=setTimeout(()=>reject(Error('TUI real-worker timer deadline')),5000))]);}finally{clearTimeout(deadline);realLoader.stop();}
const layoutSymbol=Symbol.for('@earendil-works/pi-tui/layout-node');
const leaf=name=>({render(width){return[name.slice(0,Math.max(0,width))];},invalidate(){}});
const horizontal=new HStack([{component:leaf('left'),basis:4},{component:leaf('right'),basis:5}],{gap:1});
const vertical=new VStack([{component:leaf('top'),basis:2},leaf('bottom')],{gap:1});
let resolveHidden;const hiddenDone=new Promise(resolve=>resolveHidden=resolve);
const scrolling=new ScrollView(leaf('scroll'),{follow:'end',scrollbar:'auto',scrollbarHideDelayMs:1});
scrolling.updateLayout(10,3,()=>{if(!scrolling.isScrollbarVisible)resolveHidden();});scrolling.scrollBy(-1);
const scrollbarBefore=scrolling.isScrollbarVisible;let scrollDeadline;
try{await Promise.race([hiddenDone,new Promise((_,reject)=>scrollDeadline=setTimeout(()=>reject(Error('scroll real-worker timer deadline')),5000))]);}finally{clearTimeout(scrollDeadline);}
const layoutObserved={horizontal:horizontal.render(12),vertical:vertical.render(12),baseName:Object.getPrototypeOf(HStack).name,entryIdentity:horizontal[layoutSymbol]().entries===horizontal.entries,scroll:{top:scrolling.scrollTop,following:scrolling.isFollowingEnd,visibleBefore:scrollbarBefore,visibleAfter:scrolling.isScrollbarVisible,active:scrolling.isScrollbarActive,stateIdentity:scrolling[layoutSymbol]().state===scrolling}};
export const observed={before,events,aborted:loader.aborted,imageLines,imageCache:imageLines===image.render(40),focus:isFocusable({focused:false}),viewport:isViewportTUI({[Symbol.for('@earendil-works/pi-tui/viewport')]:true}),status:formatProgramStatus({state:'working',app:'pi',message:' live '}),scheme:parseTerminalColorSchemeReport('\x1b[?997;2n'),latex:renderLatex('x^2'),layouts:layoutObserved,timer:{frame:realLoader.currentFrame,text:realLoader.text,ticks,active:!!realLoader.intervalId}};
console.log(JSON.stringify(observed));
