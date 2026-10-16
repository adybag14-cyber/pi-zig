// Prepared six actual class caller cases. Requires a fresh owned physicalRoot.
import {mkdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const {DefaultPackageManager,SettingsManager,physicalRoot}=PackageAPI;
if(typeof physicalRoot!=='string')throw Error('Actual owned physical root required');
const root=join(physicalRoot,'pattern-callers'),prompt=join(root,'nested','prompt.md'),skill=join(root,'skills','my-skill','SKILL.md');
mkdirSync(join(root,'nested'),{recursive:true});mkdirSync(join(root,'skills','my-skill'),{recursive:true});
writeFileSync(prompt,'prompt');writeFileSync(skill,'---\nname: my-skill\ndescription: actual fixture\n---\nskill');
writeFileSync(join(root,'package.json'),JSON.stringify({pi:{prompts:['nested/prompt.md'],skills:['skills/my-skill']}}));
const manager=new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()});
const metadata={source:'local',scope:'project',origin:'package',baseDir:root},rows=[];
for(const [name,type,pattern] of [
 ['relative-file','prompts','nested/prompt.md'],['basename-file','prompts','prompt.md'],['absolute-file','prompts',prompt],
 ['relative-skill-parent','skills','skills/my-skill'],['basename-skill-parent','skills','my-skill'],['absolute-skill-parent','skills',join(root,'skills','my-skill')],
]){const target=new Map();manager.applyPackageFilter(root,[pattern],type,target,metadata);rows.push({name,pattern,resources:[...target].map(([path,value])=>({path,enabled:value.enabled}))})}
globalThis.packagePatternCallerRows=rows;globalThis.packagePatternCallerComplete=true;
