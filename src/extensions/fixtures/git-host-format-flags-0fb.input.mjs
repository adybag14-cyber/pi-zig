// Prepared genuine formatter hook observation, separate from full-class input.
const {hosted}=GitAPI,trace=[];
const value={replace(pattern,replacement){trace.push({source:pattern.source,flags:pattern.flags,replacement});return this}};
const input={toLowerCase(){trace.push({operation:'toLowerCase'});return value}};
const instance=hosted.fromUrl('github:formatter-observation/repo');
const result=instance.hashformat(input);
globalThis.gitHostFormatFlagRows=[{name:'actual-formatHashFragment-literal-flags',same:result===value,trace}];
globalThis.gitSourceHostedRows=gitHostFormatFlagRows;globalThis.gitSourceHostedComplete=true;
