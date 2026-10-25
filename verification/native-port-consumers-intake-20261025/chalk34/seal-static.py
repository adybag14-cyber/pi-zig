from pathlib import Path, PurePosixPath
import datetime, difflib, hashlib, json, re, subprocess
P=Path(__file__).resolve().parent
MAIN=Path(r'C:\Users\adyba\pi-zig\main')
BASE='c248553d15282e1e8ad896382c78132b6a501dd9'
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def pin(path):
    path=Path(path);b=path.read_bytes()
    return {'path':str(path),'bytes':len(b),'sha256':sha(b)}
def write(rel,s):
    out=P/rel;out.parent.mkdir(parents=True,exist_ok=True)
    out.write_bytes(s if isinstance(s,bytes) else s.encode('utf-8'))
def base(path):
    r=subprocess.run(['git','show',BASE+':'+path],cwd=MAIN,capture_output=True)
    if r.returncode:
        assert b'does not exist' in r.stderr or b'exists on disk, but not in' in r.stderr,(path,r.stderr)
        return b''
    return r.stdout
def check(condition,reason):
    assert condition,reason
def jsonwrite(rel,obj): write(rel,json.dumps(obj,indent=2)+'\n')
build=base('build.zig')
snippet=(P/'build-insertion.zig.txt').read_text(encoding='utf-8')
anchor='    const chalk_ignore_guest = b.addTest(.{\n'
check(build.decode().count(anchor)==1,'unique build anchor')
projected_build=build.decode().replace(anchor,snippet+anchor)
write('original/build.zig',build)
write('projected/build.zig',projected_build)
check(projected_build.replace(snippet,'').encode()==build,'exact build inverse')
jsonwrite('build-inverse.json',{'base':BASE,'exact_inverse':True,'anchor':anchor,'insertion':snippet,
    'install_only_target':'build-native-sdk-chalk-project-trust-colors',
    'windows_artifact':'native-sdk-chalk-project-trust-colors.exe','run_step':False})
owner=(P/'projected/src/extensions/native_sdk_chalk.zig').read_text(encoding='utf-8')
inverse=json.loads((P/'owner-inverse.json').read_text(encoding='utf-8'))
restored=owner
for change in reversed(inverse['changes']):
    check(restored.count(change['after'])==1,'unique owner inverse')
    restored=restored.replace(change['after'],change['before'])
check(restored.encode()==base('src/extensions/native_sdk_chalk.zig'),'complete owner inverse')
check('styles.color' not in owner,'no invented source namespace')
for name,code in [('red',31),('yellow',33),('cyan',36)]:
    ansi=(P/'authority/chalk/source/vendor/ansi-styles/index.js').read_text(encoding='utf-8')
    check(f'{name}: [{code}, 39]' in ansi,'exact original color pair')
    check(f'.{name} => "\\x1b[{code}m"' in owner,'exact native open code')
reference=(P/'projected/src/extensions/fixtures/sdk-chalk-project-trust-colors-original.mjs').read_text(encoding='utf-8')
ansi=(P/'authority/chalk/source/vendor/ansi-styles/index.js').read_text(encoding='utf-8')
utility=(P/'authority/chalk/source/utilities.js').read_text(encoding='utf-8')
index=(P/'authority/chalk/source/index.js').read_text(encoding='utf-8')
seams=json.loads((P/'fixture-inverse.json').read_text(encoding='utf-8'))
check(ansi.replace('export const ','const ').replace('export default ansiStyles;','return ansiStyles;') in reference,'whole ansi source retained')
check(utility.replace('export function ','function ') in reference,'whole utility source retained')
index_body=index[len(seams['imports_removed']):-len(seams['exports_removed'])].replace('export class Chalk {','class Chalk {').replace('export const chalkStderr =','const chalkStderr =')
check(index_body in reference,'whole Chalk source body retained')
old_corpus=(P/'authority/chalk-consumed-callers.mjs').read_text(encoding='utf-8')
yellow=(P/'projected/src/extensions/fixtures/sdk-chalk-project-trust-yellow-regression.mjs').read_text(encoding='utf-8')
check(yellow.replace('function runChalkConsumedCases','export function runChalkConsumedCases')==old_corpus,'exact yellow caller inverse')
consumer=json.loads((P/'consumer-authority.json').read_text(encoding='utf-8'))
notify=(P/'projected/src/extensions/fixtures/sdk-chalk-project-trust-notify-original.mjs').read_text(encoding='utf-8')
check(consumer['selected_arrow'] in notify,'whole original notify arrow retained')
test=(P/'projected/src/native_sdk_chalk_project_trust_colors_test.zig').read_text(encoding='utf-8')
observer=(P/'projected/src/extensions/fixtures/sdk-chalk-project-trust-colors-observer.mjs').read_text(encoding='utf-8')
names=re.findall(r'^test "([^"]+)"',test,re.M)
both=re.findall(r'try both\("([^"]+)"\)',test)
cases=re.findall(r'case "([^"]+)":',observer)
check(len(names)==34 and len(set(names))==34,'34 unique controls')
check(len(both)==29 and len(set(both))==29,'29 unique differential controls')
check(set(cases)==set(both),'every declared differential case has exactly one observer')
check(len(cases)==len(set(cases)),'no duplicate observer cases')
check(test.count('try fatal(')==4,'4 actual fatal controls')
check('observations.length===86' in observer,'complete old yellow corpus asserted')
main_source=Path(r'C:\Users\adyba\pi-zig\upstream\snapshots\4954d76-20261015\packages\coding-agent\src\main.ts')
main_lines=main_source.read_bytes().decode('utf-8').splitlines(keepends=True)
runtime=''.join(main_lines[732:864])
check('const createRuntime: CreateAgentSessionRuntimeFactory = async' in runtime,'exact original runtime region')
check('createProjectTrustContext({' in runtime and 'await resolveModelScope(' in runtime,'both actual consumers in source')
write('authority/main-create-runtime-original.ts',runtime)
assessment={
    'base':BASE,'source_only':True,'original_main':pin(main_source),'original_lines':[733,864],
    'selected_region':pin(P/'authority/main-create-runtime-original.ts'),
    'actual_next_graph':[
        {'symbol':'Main createRuntime closure','state':'No actual native application closure found; current generic SDK factory consumes a caller-provided createRuntime.'},
        {'symbol':'createProjectTrustContext','state':'Absent from native src search; invoked when no projectTrustContext override is supplied.'},
        {'symbol':'createProjectTrustContext.notify','state':'Complete original arrow uses real red/yellow/cyan; this packet adds the two absent styles to the existing actual Chalk owner.'},
        {'symbol':'showStartupSelector / showStartupInput','state':'No native implementations found in src; required by interactive select/confirm/input branches.'},
        {'symbol':'collectSettingsDiagnostics / buildSessionOptions / resolveCliPaths / resolveProjectTrusted','state':'Actual native implementations already present; not missing suppliers.'},
        {'symbol':'resolveModelScope warning wrapper','state':'Separate completed source-only packet sdk-model-scope-warning-sourceonly-20261025; no shared files modified here.'}
    ],
    'startup_UI_prerequisites':['createStartupTui','startup themes and package resolution','ExtensionSelectorComponent','ExtensionInputComponent','actual terminal and TUI lifecycle'],
    'whole_application_or_context_qualification':False
}
jsonwrite('create-runtime-next-gap-assessment.json',assessment)
paths=sorted(p.relative_to(P/'projected').as_posix() for p in (P/'projected').rglob('*') if p.is_file())
check(len(paths)==7,'seven projected source/build files')
changes=[]
patch=[]
for relative in paths:
    original=base(relative)
    projected=(P/'projected'/relative).read_bytes()
    if original: write('original/'+relative,original)
    if original==projected:continue
    changes.append({'relative':relative,'base_bytes':len(original),'base_sha256':sha(original) if original else None,
        'projected':pin(P/'projected'/relative)})
    for line in difflib.unified_diff(original.decode('utf-8').splitlines(keepends=True),projected.decode('utf-8').splitlines(keepends=True),
        fromfile='a/'+relative if original else '/dev/null',tofile='b/'+relative):
        patch.append(line if line.endswith('\n') else line+'\n\\ No newline at end of file\n')
write('chalk-project-trust-colors.patch',''.join(patch))
read_status=subprocess.run(['git','status','--short'],cwd=MAIN,text=True,capture_output=True,check=True).stdout
read_head=subprocess.run(['git','rev-parse','HEAD'],cwd=MAIN,text=True,capture_output=True,check=True).stdout.strip()
applied=subprocess.run(['git','apply','--check',str(P/'chalk-project-trust-colors.patch')],cwd=MAIN,text=True,capture_output=True)
check(applied.returncode==0,'read-only git apply check: '+applied.stderr)
jsonwrite('git-apply-check.json',{'command':['git','apply','--check',str(P/'chalk-project-trust-colors.patch')],
    'working_dir':str(MAIN),'exit_code':applied.returncode,'stdout':applied.stdout,'stderr':applied.stderr,
    'read_head':read_head,'read_status':read_status,'mutation':False})
imports=[]
for rel in paths:
    if not rel.endswith('.zig') or rel=='build.zig':continue
    text=(P/'projected'/rel).read_text(encoding='utf-8')
    for kind,spelling in re.findall(r'@(import|embedFile)\("([^"]+)"\)',text):
        if spelling in ['std','builtin','catalog_tool']:continue
        candidate=(P/'projected'/rel).parent/spelling
        if candidate.exists():
            chosen=candidate;origin='packet projected'
        else:
            chosen=(MAIN/rel).parent/spelling;origin='unchanged Main import'
        check(chosen.exists(),f'import exists: {rel} {spelling}')
        info=pin(chosen)
        imports.append({'source':rel,'kind':kind,'spelling':spelling,'origin':origin,**info})
all_static={'complete_owner_inverse':True,'full_original_Chalk_source_body_inverses':True,
    'existing_yellow_caller_inverse':True,'original_notify_arrow_exact':True,'build_inverse':True,
    'projected_file_count':len(paths),'unique_control_declarations':len(names),'differential_cases':len(both),
    'native_fatal_controls':4,'native_identity_controls':1,'prior_yellow_observations':86,
    'all_direct_import_embed_resolutions_exist':True,'direct_import_embed_resolutions':len(imports),
    'git_apply_check_passed':True,'native_Node_capture_compiler_formatter_run':False}
jsonwrite('static-checks.json',all_static)
documents=['README.md','prepare-static.py','seal-static.py','owner-inverse.json','fixture-inverse.json','build-inverse.json',
    'primary-provenance.json','consumer-authority.json','create-runtime-next-gap-assessment.json',
    'static-checks.json','git-apply-check.json','build-insertion.zig.txt','chalk-project-trust-colors.patch']
authority=[pin(f) for f in sorted((P/'authority').rglob('*')) if f.is_file()]
originals=[pin(f) for f in sorted((P/'original').rglob('*')) if f.is_file()]
manifest={
    'scope':'actual native Chalk consumed foreground red/yellow/cyan successor for original project trust notify',
    'base':BASE,'packet':str(P),'source_only':True,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'authorization':'Root packet-only source ownership; no native/Node/reference capture/production generator execution',
    'main_mutated':False,'upstream_mutated':False,'accepted_warning_packet_mutated':False,
    'static_checks':all_static,'projected_changes':changes,'authority':authority,'originals':originals,
    'direct_import_embed_resolutions':imports,'controls':names,'differential_cases':both,
    'build_target':'build-native-sdk-chalk-project-trust-colors',
    'planned_windows_executable':'native-sdk-chalk-project-trust-colors.exe',
    'documents':[pin(P/name) for name in documents],
    'unexecuted_gates':['Root source acceptance and combined-head integration','native compilation and actual metadata',
        'native semantic controls and original-source observation equality','independent original detector reference',
        'complete project-trust context and Main application startup integration']
}
jsonwrite('source-intake.json',manifest)
print(json.dumps({'source_intake':pin(P/'source-intake.json'),'patch':pin(P/'chalk-project-trust-colors.patch'),
    'static_checks':all_static,'main_head':read_head,'main_status':read_status}))
