import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys

proof = pathlib.Path(__file__).resolve().parent
candidate = proof.parent.parent
evidence = pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003')
source = pathlib.Path('C:/Users/adyba/pi-upstream-source-4954d76-20261015')
runtime = pathlib.Path('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012')
compiler = pathlib.Path('C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0')
load = lambda path: json.loads(path.read_text(encoding='utf-8-sig'))
save = lambda path, value: path.write_text(json.dumps(value, indent=2) + '\n')
def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()
def rows(paths):
    return [{'path': str(path), 'sha256': sha(path)} for path in sorted(set(paths))]
def check(items):
    return [row['path'] for row in items if not pathlib.Path(row['path']).is_file() or sha(pathlib.Path(row['path'])) != row['sha256'].upper()]
def git_paths():
    return [p.decode() for p in subprocess.check_output(['git', '-C', str(candidate), 'ls-files', '-z']).split(b'\0') if p]
def inventory(root, excluded=()):
    found, links = [], []
    for parent, dirs, names in os.walk(root, followlinks=False):
        kept = []
        for name in dirs:
            path = pathlib.Path(parent) / name
            if name in excluded:
                continue
            if path.is_junction() or path.is_symlink():
                links.append({'path': str(path), 'raw_target': os.readlink(path), 'resolved_target': str(path.resolve())})
            else:
                kept.append(name)
        dirs[:] = kept
        found.extend(str(pathlib.Path(parent) / name) for name in names if name != '.git')
    return {'files': sorted(found), 'links': sorted(links, key=lambda value: value['path'])}
def absence_paths():
    audit = load(evidence / 'source4954-dependency-contract-audit-20261015.json')
    assert audit['latestHead'] == '4954d760504c11df9b2cbdc040346107b6a8153d'
    absent = [r['path'] for r in audit['pins'] if r.get('status') == 'platform_optional_absent'] + [r['path'] for r in audit['mismatches']]
    assert len(absent) == 84
    return [str(root / path) for root in [source, runtime] for path in absent]
mode, name = sys.argv[1:]
pre_path = proof / (name + '-prehash.json')
if mode == 'pre':
    assert not pre_path.exists()
    assert not subprocess.check_output(['git', '-C', str(candidate), 'status', '--porcelain']), 'Clean committed candidate required'
    assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD']).decode().strip() == '4954d760504c11df9b2cbdc040346107b6a8153d'
    sets = {'candidate': rows(candidate / path for path in git_paths()), 'source': load(evidence / 'source4954-full-manifest-20261015.json'), 'dependencies': load(evidence / 'source4954-runtime-manifest-20261015.json'), 'node': load(evidence / 'source4954-node-tools-before-20261015.json')}
    assert len(sets['source']) == 1970 and len(sets['dependencies']) == 31064 and len(sets['node']) == 1774
    compiler_inventory = inventory(compiler)
    sets['compiler'] = rows(pathlib.Path(path) for path in compiler_inventory['files'])
    assert len(sets['compiler']) == 19546
    assert sha(pathlib.Path('C:/Program Files/nodejs/node.exe')) == '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'
    assert sha(compiler / 'zig.exe') == '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'
    controls = [proof / path for path in ['run-source.ps1', 'Invoke-ExactSourceProcess.ps1', 'freeze-inputs.py', 'capture-source.mjs', 'static-review.md']] + [candidate / 'src/extensions/fixtures/ai-model-operations-4954.input.txt', candidate / 'src/native_ai_model_operations_source_test.zig'] + [evidence / path for path in ['source4954-observe-20261015.mjs', 'source4954-full-manifest-20261015.json', 'source4954-runtime-manifest-20261015.json', 'source4954-node-tools-before-20261015.json', 'source4954-dependency-contract-audit-20261015.json', 'source4954-reference-controls-20261015.json']]
    sets['controls'] = rows(controls)
    for key, values in sets.items():
        assert len(values) == len({r['path'] for r in values})
        assert not check(values), key
    source_inventory = inventory(source, ('.git', 'node_modules'))
    assert set(source_inventory['files']) == {row['path'] for row in sets['source']}
    runtime_inventory = inventory(runtime, ('.git',))
    assert set(runtime_inventory['files']) == {row['path'] for row in sets['dependencies']}
    assert not any(pathlib.Path(path).exists() for path in absence_paths())
    junction = source / 'node_modules'
    assert junction.is_junction() and junction.resolve() == runtime / 'node_modules'
    save(pre_path, {'candidate_head': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD']).decode().strip(), 'sets': sets, 'candidate_tracked_paths': git_paths(), 'source_inventory': source_inventory, 'dependency_inventory': runtime_inventory, 'compiler_inventory': compiler_inventory, 'source_junction_target': os.readlink(junction), 'absences': absence_paths(), 'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
    controls_path = proof / (name + '-oracle-controls.json')
    save(controls_path, sets['controls'])
    save(proof / (name + '-launch-pins.json'), {'control_manifest': str(controls_path), 'control_manifest_sha256': sha(controls_path), 'candidate_head': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD']).decode().strip()})
elif mode == 'post':
    before = load(pre_path)
    pins = load(proof / (name + '-launch-pins.json'))
    report = {'manifests': [{'name': key, 'files': len(values), 'drift': len(changed), 'changed': changed} for key, values in before['sets'].items() for changed in [check(values)]], 'candidate_tracked_inventory_drift': git_paths() != before['candidate_tracked_paths'], 'candidate_head_drift': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD']).decode().strip() != before['candidate_head'], 'source_inventory_drift': inventory(source, ('.git', 'node_modules')) != before['source_inventory'], 'dependency_inventory_drift': inventory(runtime, ('.git',)) != before['dependency_inventory'], 'compiler_inventory_drift': inventory(compiler) != before['compiler_inventory'], 'source_junction_drift': os.readlink(source / 'node_modules') != before['source_junction_target'], 'absence_drift': [path for path in before['absences'] if pathlib.Path(path).exists()], 'control_manifest_drift': sha(pathlib.Path(pins['control_manifest'])) != pins['control_manifest_sha256'], 'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    report['declared_absence_records'] = 84
    report['absence_locations_checked'] = len(before['absences'])
    extra = [p.decode() for p in subprocess.check_output(['git', '-C', str(candidate), 'ls-files', '--others', '--exclude-standard', '-z']).split(b'\0') if p]
    allowed_prefix = 'verification/ai-model-operations-4954-20261015/' + name
    report['unexpected_candidate_untracked_paths'] = [path for path in extra if not path.startswith(allowed_prefix)]
    save(proof / (name + '-posthash.json'), report)
    assert not any(row['drift'] for row in report['manifests'])
    assert not any(value for key, value in report.items() if key.endswith('_drift'))
    assert not report['unexpected_candidate_untracked_paths']
    print(json.dumps(report, indent=2))
else:
    raise AssertionError(mode)
