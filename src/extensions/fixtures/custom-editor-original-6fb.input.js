const results=[];
const identity=text=>text;
const make=(options,bindings={})=>{const calls=[],kb={matches(data,action){calls.push([data,action,this===kb]);return bindings[action]?.includes(data)??false;}},e=new CustomEditor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:identity},kb,options);return{e,kb,calls};};
{
 const{e}=make();results.push({name:'custom exact class shape',value:{name:CustomEditor.name,length:CustomEditor.length,own:Object.keys(e),methods:Object.fromEntries(Object.getOwnPropertyNames(CustomEditor.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:CustomEditor.prototype[k].name,length:CustomEditor.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(CustomEditor.prototype,k).enumerable}]))}});
}
for(const width of[0,1,3,5,10,20,40,80])for(const hidden of[0,7])for(const status of['','work','long working status']){
 const{e}=make({embedWorkingStatus:true}),calls=[];const indicator={renderInBorder(width){calls.push(['full',this===indicator,width]);return status;},renderSpinnerInBorder(width){calls.push(['spinner',this===indicator,width]);return'*';}};e.setWorkingStatusIndicator(indicator);e.borderColor=function(text){calls.push(['color',this===e,text]);return'<'+text+'>';};results.push({name:'working border '+width+' '+hidden+' '+status,value:{text:e.renderTopBorder(width,hidden),calls}});
}
{
 const{e,calls}=make({}, {'app.interrupt':['E'],'app.exit':['D'],'app.clipboard.pasteImage':['P'],'app.action':['A']});const events=[];e.onAction('app.action',function(){'use strict';events.push(['action',this===undefined]);});e.onAction('app.interrupt',function(){'use strict';events.push(['registeredEscape',this===undefined]);});e.onAction('app.exit',function(){'use strict';events.push(['registeredExit',this===undefined]);});e.onPasteImage=function(){events.push(['paste',this===e]);};e.onExtensionShortcut=function(data){events.push(['shortcut',this===e,data]);return data==='S';};for(const input of['S','P','E','D','A','x'])e.handleInput(input);results.push({name:'app input ordering optional handlers and action receiver',value:{events,calls,text:e.getText()}});
}
{
 const{e}=make({}, {'app.interrupt':['E']});const events=[];e.onEscape=function(){'use strict';events.push(this===undefined);};e.handleInput('E');e.onEscape=undefined;e.autocompleteState='regular';e.autocompleteList={handleInput(){events.push('list');}};e.handleInput('E');results.push({name:'dynamic escape handler and picker fallthrough',value:{events,text:e.getText(),state:e.autocompleteState}});
}
{
 const{e}=make(),calls=[];e.keybindings={matches(data,action){calls.push([data,action,this===e.keybindings]);return action==='app.exit';}};e.onCtrlD=function(){'use strict';calls.push(['exit',this===undefined]);};e.handleInput('anything');results.push({name:'ordinary replaced keybinding field controls dispatch',value:calls});
}
{
 const{e}=make({embedWorkingStatus:false}),raw={raw:true};e.onExtensionShortcut=function(){throw raw;};let same=false;try{e.handleInput('x');}catch(error){same=error===raw;}results.push({name:'raw custom shortcut throw',value:{same}});
}
globalThis.customEditorResult=results;
