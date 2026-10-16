// Same user-style input for genuine original Source and composed native APIs.
import * as fs from 'node:fs/promises';
import {join} from 'node:path';
const {configuration:cfg,shell,timing}=globalThis.ActualSdkRuntimeHelpers;
const root=globalThis.ActualSdkRuntimeHelperDir;
if(typeof root!=='string'||!root)throw Error('Owned physical helper fixture directory required');
const rows=[];const add=(name,value)=>rows.push({name,value});
const portable=value=>typeof value==='string'?value.split(root).join('<fixture>'):value;
const call=(name,...args)=>{try{return portable(cfg[name](...args))}catch(error){return {name:error?.name,message:error?.message}}};
const originalPackageDir=process.env.PI_PACKAGE_DIR;
const originalAgentDir=process.env[cfg.ENV_AGENT_DIR];
const originalShare=process.env.PI_SHARE_VIEWER_URL;
try{
  add('configuration-startup-metadata',{PACKAGE_NAME:cfg.PACKAGE_NAME,APP_NAME:cfg.APP_NAME,APP_TITLE:cfg.APP_TITLE,CONFIG_DIR_NAME:cfg.CONFIG_DIR_NAME,VERSION:cfg.VERSION,ENV_AGENT_DIR:cfg.ENV_AGENT_DIR,ENV_SESSION_DIR:cfg.ENV_SESSION_DIR,isBunBinary:cfg.isBunBinary,isBunRuntime:cfg.isBunRuntime});
  add('configuration-function-metadata',Object.fromEntries(['findNodePackageDir','getPackageDir','getDocsPath','getAgentDir','getBinDir','getShareViewerUrl'].map(name=>[name,{name:cfg[name].name,length:cfg[name].length}])));
  process.env.PI_PACKAGE_DIR=root;
  await fs.mkdir(join(root,'src'),{recursive:true});
  for(const name of ['getPackageDir','getPackageJsonPath','getReadmePath','getDocsPath','getExamplesPath','getChangelogPath','getThemesDir','getExportTemplateDir','getInteractiveAssetsDir'])add('configuration-source-path-'+name,call(name));
  add('configuration-bundled-asset',call('getBundledInteractiveAssetPath','asset.txt'));
  process.env[cfg.ENV_AGENT_DIR]=join(root,'agent');
  for(const name of ['getAgentDir','getCustomThemesDir','getModelsPath','getAuthPath','getSettingsPath','getToolsDir','getBinDir','getPromptsDir','getSessionsDir','getDebugLogPath'])add('configuration-user-path-'+name,call(name));
  delete process.env.PI_SHARE_VIEWER_URL;
  add('configuration-default-share',cfg.getShareViewerUrl('fixture'));
  process.env.PI_SHARE_VIEWER_URL='https://share.example.test/view';
  add('configuration-custom-share',cfg.getShareViewerUrl('id#fragment'));
  const packageRoot=join(root,'package');const dist=join(packageRoot,'dist');const nested=join(dist,'nested');
  await fs.mkdir(nested,{recursive:true});await fs.writeFile(join(packageRoot,'package.json'),'{}');await fs.writeFile(join(dist,'package.json'),'{}');
  add('configuration-find-dist-parent',call('findNodePackageDir',nested));
  add('configuration-find-root',call('findNodePackageDir',packageRoot));
  add('configuration-find-absent',call('findNodePackageDir',join(root,'no-package')));
  add('configuration-expand-tilde',cfg.expandTildePath('~').length>0);
  const first=cfg.getDefaultSessionDir('/sdk-helper-project',join(root,'sessions-agent'));
  const second=cfg.getDefaultSessionDir('/sdk-helper-project',join(root,'sessions-agent'));
  add('configuration-real-session-directory',{path:portable(first),stable:first===second,directory:(await fs.stat(first)).isDirectory()});
  add('coding-agent-user-agent-shape',/^pi\/fixture \([^;]+; (?:node|bun)\/[^;]+; [^)]+\)$/.test(cfg.getPiUserAgent('fixture')));
  add('shell-function-metadata',Object.fromEntries(['getShellConfig','getPowerShellConfig','getShellEnv','sanitizeBinaryOutput','trackDetachedChildPid','untrackDetachedChildPid','killTrackedDetachedChildren','killProcessTree'].map(name=>[name,{name:shell[name].name,length:shell[name].length}])));
  add('shell-powershell-args',shell.POWERSHELL_ARGS);
  const existingShell=join(root,'existing-shell.exe');await fs.writeFile(existingShell,'physical existence fixture; never executed\n');
  const custom=shell.getShellConfig(existingShell);add('shell-custom-real-existing',{...custom,shell:portable(custom.shell)});
  try{shell.getShellConfig(join(root,'absent-shell'));add('shell-custom-missing',null)}catch(error){add('shell-custom-missing',{name:error.name,message:portable(error.message)})}
  // Selection invokes the actual host where/which and actual existsSync calls.
  try{const selected=shell.getShellConfig();add('shell-real-default-selection',{shell:typeof selected.shell,args:selected.args,transport:selected.commandTransport})}catch(error){add('shell-real-default-selection',{name:error.name,message:error.message})}
  const env=shell.getShellEnv();const key=Object.keys(env).find(key=>key.toLowerCase()==='path');
  add('shell-real-bin-path',{key,contains:env[key].split(process.platform==='win32'?';':':').includes(cfg.getBinDir()),copied:env!==process.env});
  add('shell-sanitize',shell.sanitizeBinaryOutput('a\x00b\t\nc\r\x0bd\ufff9e\ufffaf\ufffb😀'));
  add('shell-sanitize-clean',shell.sanitizeBinaryOutput('plain 😀 text'));
  // Tracking and removing the current pid does not invoke any process control.
  shell.trackDetachedChildPid(process.pid);shell.untrackDetachedChildPid(process.pid);
  add('shell-empty-owned-cleanup',shell.killTrackedDetachedChildren());
  const savedNow=Date.now;const savedError=console.error;const timingFlag=process.env.PI_TIMING;const logs=[];let tick=100;
  try{
    Date.now=()=>tick++;console.error=(...args)=>logs.push(args);
    timing.resetTimings();timing.time('first');timing.time('second');timing.printTimings();
    add('timing-main-exact-log',logs.splice(0));
    timing.time('extension-first','extensions');timing.time('extension-second','extensions');timing.printTimings();
    add('timing-namespace-exact-log',logs.splice(0));
    process.env.PI_TIMING='0';timing.time('import-gate-remains-enabled');timing.printTimings();
    add('timing-import-time-gate',logs.splice(0));
    const raw={marker:'clock'};Date.now=()=>{throw raw};try{timing.time('throw-clock');add('timing-clock-raw-reason',false)}catch(error){add('timing-clock-raw-reason',error===raw)}
  }finally{Date.now=savedNow;console.error=savedError;if(timingFlag===undefined)delete process.env.PI_TIMING;else process.env.PI_TIMING=timingFlag}
  add('timing-function-metadata',Object.fromEntries(['resetTimings','time','printTimings'].map(name=>[name,{name:timing[name].name,length:timing[name].length}])));
}finally{
  if(originalPackageDir===undefined)delete process.env.PI_PACKAGE_DIR;else process.env.PI_PACKAGE_DIR=originalPackageDir;
  if(originalAgentDir===undefined)delete process.env[cfg.ENV_AGENT_DIR];else process.env[cfg.ENV_AGENT_DIR]=originalAgentDir;
  if(originalShare===undefined)delete process.env.PI_SHARE_VIEWER_URL;else process.env.PI_SHARE_VIEWER_URL=originalShare;
}
globalThis.ActualSdkRuntimeHelperRows=rows;
