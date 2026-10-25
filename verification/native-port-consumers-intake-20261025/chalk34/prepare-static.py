from pathlib import Path
import hashlib, json, subprocess
P=Path(__file__).resolve().parent
MAIN=Path(r'C:\Users\adyba\pi-zig\main')
BASE='c248553d15282e1e8ad896382c78132b6a501dd9'
AUTH=Path(r'C:\Users\adyba\pi-zig\upstream\runtime\19cb534-full-prebuild-root-full28293-v3-20261017-203626\node_modules\chalk')
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def write(rel, content):
    out=P/rel;out.parent.mkdir(parents=True,exist_ok=True)
    out.write_bytes(content if isinstance(content,bytes) else content.encode('utf-8'))
def base(path):
    return subprocess.run(['git','show',BASE+':'+path],cwd=MAIN,capture_output=True,check=True).stdout
owner=base('src/extensions/native_sdk_chalk.zig')
assert sha(owner)=='3789CF7E66DB2F8D554403792E297166EA5EC6B3B5B389D7F68492D4CBFFF135'
s=owner.decode('utf-8')
changes=[]
def replace(old,new):
    global s
    assert s.count(old)==1,(old[:100],s.count(old))
    s=s.replace(old,new)
    changes.append({'before':old,'after':new})
replace('//! Private actual consumed Chalk6 default: callable factory, yellow builders and\n',
        '//! Private actual consumed Chalk6 default: callable factory, red/yellow/cyan builders and\n')
replace('const Symbol = enum { GENERATOR, STYLER, IS_EMPTY, LEVEL };\n',
        'const Symbol = enum { GENERATOR, STYLER, IS_EMPTY, LEVEL };\nconst Foreground = enum { red, yellow, cyan };\n')
replace('fn cacheStyle(s: *Scope, receiver: c.JSValue, builder: c.JSValue) !void {',
        'fn cacheStyle(comptime color: Foreground, s: *Scope, receiver: c.JSValue, builder: c.JSValue) !void {')
replace('try s.text("yellow"), descriptor','try s.text(@tagName(color)), descriptor')
replace('fn styler(s: *Scope, parent: c.JSValue) !c.JSValue {\n    const open = try s.text("\\x1b[33m"); const close = try s.text("\\x1b[39m");',
        'fn styler(comptime color: Foreground, s: *Scope, parent: c.JSValue) !c.JSValue {\n    const open = try s.text(switch (color) {\n        .red => "\\x1b[31m", .yellow => "\\x1b[33m", .cyan => "\\x1b[36m",\n    });\n    const close = try s.text("\\x1b[39m");')
replace('fn yellowGet(s: *Scope, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {',
        'fn styleGetter(comptime color: Foreground) Body {\n    return struct {\n        fn get(s: *Scope, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {\n            return styleGet(color, s, receiver, roots);\n        }\n    }.get;\n}\nfn styleGet(comptime color: Foreground, s: *Scope, receiver: c.JSValue, roots: []const c.JSValue) !c.JSValue {')
replace('const paint = try styler(s, try slot(s, state, receiver, .STYLER));',
        'const paint = try styler(color, s, try slot(s, state, receiver, .STYLER));')
replace('try cacheStyle(s, receiver, builder);','try cacheStyle(color, s, receiver, builder);')
replace('    const yellow = try makeMethod(s, "get", 0, yellowGet, &.{state});\n    try accessor(s, root_proto, "yellow", yellow, c.pi_js_undefined(), false); try accessor(s, builder_proto, "yellow", yellow, c.pi_js_undefined(), false);',
        '    // The consumed foreground styles retain the primary enumeration order.\n    // Each getter creates and caches the same genuine builder algorithm.\n    inline for (.{ Foreground.red, Foreground.yellow, Foreground.cyan }) |color| {\n        const getter = try makeMethod(s, "get", 0, styleGetter(color), &.{state});\n        try accessor(s, root_proto, @tagName(color), getter, c.pi_js_undefined(), false);\n        try accessor(s, builder_proto, @tagName(color), getter, c.pi_js_undefined(), false);\n    }')
restored=s
for change in reversed(changes):
    assert restored.count(change['after'])==1
    restored=restored.replace(change['after'],change['before'])
assert restored.encode('utf-8')==owner
write('original/src/extensions/native_sdk_chalk.zig',owner)
write('projected/src/extensions/native_sdk_chalk.zig',s)
write('owner-inverse.json',json.dumps({'base':BASE,'complete_inverse_exact':True,'changes':changes},indent=2)+'\n')
pins={
'source/index.js':'08E92F2330A34D232F8AA987DA4D953893094BE5B2AA8CC39DDB4313743F206E',
'source/utilities.js':'A58D81494366211509EA2C373328CF68A6365A94BE8645F33C1ED49F1288650A',
'source/vendor/ansi-styles/index.js':'F28F1EDE59BE327626E4AE5F9F05387AB8072F298BA1AB7F9C9262D39923A25D',
'package.json':'5A853FC6DC0C529BC126F97645989E9D60D06A2E9B20F66A6B48B0E8EF9DA3EF',
'license':'5C932D88256B4AB958F64A856FA48E8BD1F55BC1D96B8149C65689E0C61789D3'}
raw={}
primary=[]
for path,pinned in pins.items():
    data=(AUTH/path).read_bytes();assert sha(data)==pinned,(path,sha(data))
    raw[path]=data.decode('utf-8')
    write('authority/chalk/'+path,data)
    primary.append({'path':str(AUTH/path),'bytes':len(data),'sha256':pinned,'original_manifest_exact':True})
ansi=raw['source/vendor/ansi-styles/index.js']
assert ansi.count('export const ')==5 and ansi.count('export default ansiStyles;')==1
ansi_body=ansi.replace('export const ','const ').replace('export default ansiStyles;','return ansiStyles;')
utilities=raw['source/utilities.js']
assert utilities.count('export function ')==2
utilities_body=utilities.replace('export function ','function ')
index=raw['source/index.js']
prefix="import {\n\tstringReplaceAll,\n\tstringEncaseCRLFWithFirstIndex,\n} from './utilities.js';\nimport ansiStyles from '#ansi-styles';\nimport supportsColor from '#supports-color';\n\n"
suffix=index[index.index("export {\n\tmodifierNames,"):]
assert index.startswith(prefix) and suffix.endswith('export default chalk;\n')
index_body=index[len(prefix):-len(suffix)].replace('export class Chalk {','class Chalk {').replace('export const chalkStderr =','const chalkStderr =')
fixture='// Exact pinned Chalk 6.0.0 source bodies; only module syntax is adapted.\n// supportsColor is the genuine installed native detector output, shared input\n// for this style-only comparison. No detector or unconsumed style parity claim.\n(function originalChalkSource(supportsColor) {\n"use strict";\nconst ansiStyles = (() => {\n'+ansi_body+'\n})();\n'+utilities_body+'\n'+index_body+'\nreturn chalk;\n})\n'
assert ansi_body.replace('return ansiStyles;','export default ansiStyles;').replace('const modifierNames','export const modifierNames').replace('const foregroundColorNames','export const foregroundColorNames').replace('const backgroundColorNames','export const backgroundColorNames').replace('const underlineColorNames','export const underlineColorNames').replace('const colorNames','export const colorNames')==ansi
assert utilities_body.replace('function stringReplaceAll','export function stringReplaceAll').replace('function stringEncaseCRLFWithFirstIndex','export function stringEncaseCRLFWithFirstIndex')==utilities
assert prefix+index_body.replace('class Chalk {','export class Chalk {').replace('const chalkStderr =','export const chalkStderr =')+suffix==index
write('projected/src/extensions/fixtures/sdk-chalk-project-trust-colors-original.mjs',fixture)
write('fixture-inverse.json',json.dumps({'all_original_bodies_retained':True,'full_source_inverses_exact':True,'imports_removed':prefix,'exports_removed':suffix,'index_export_erasure':['export class Chalk','export const chalkStderr'],'ansi_const_export_erasure_count':5,'utilities_export_erasure_count':2,'style_test_input':'actual native supportsColor provider output; explicit levels in all comparisons'},indent=2)+'\n')
old_corpus=base('verification/sdk-chalk6/chalk-consumed-callers.mjs').decode('utf-8')
assert old_corpus.count('export function runChalkConsumedCases')==1
yellow=old_corpus.replace('export function runChalkConsumedCases','function runChalkConsumedCases')
write('authority/chalk-consumed-callers.mjs',old_corpus)
write('projected/src/extensions/fixtures/sdk-chalk-project-trust-yellow-regression.mjs',yellow)
write('primary-provenance.json',json.dumps({'base':BASE,'primary_sources':primary,'source_only':True,'native_or_Node_run':False},indent=2)+'\n')
project_path=Path(r'C:\Users\adyba\pi-zig\upstream\snapshots\4954d76-20261015\packages\coding-agent\src\cli\project-trust.ts')
project=project_path.read_bytes()
assert sha(project)=='F53DACE044983EF779B0C99EA3F1A75155116ACE6E4569C623B95D6C24972C3B'
project_text=project.decode('utf-8')
begin=project_text.index('\t\t\tnotify: ')+len('\t\t\tnotify: ')
end=project_text.index('\n\t\t\t},',begin)+len('\n\t\t\t}')
notify=project_text[begin:end]
write('authority/project-trust.ts',project)
write('authority/project-trust-notify-original.js',notify+'\n')
write('projected/src/extensions/fixtures/sdk-chalk-project-trust-notify-original.mjs','// Exact original createProjectTrustContext.notify arrow; options and chalk\n// are its genuine lexical inputs. Startup UI methods are outside this fixture.\n(function originalProjectTrustNotify(options, chalk) {\n"use strict";\nreturn '+notify+';\n})\n')
write('consumer-authority.json',json.dumps({'path':str(project_path),'bytes':len(project),'sha256':sha(project),'selected_arrow':notify,'exact_notify_body':True,'full_context_or_startup_UI_qualification':False},indent=2)+'\n')
print(json.dumps({'owner_bytes':len(s.encode()),'owner_sha256':sha(s.encode()),'full_original_fixture_bytes':len(fixture.encode()),'original_inverses_exact':True,'primary_members':len(primary)}))
