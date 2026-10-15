import collections
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess

tree = pathlib.Path('C:/Users/adyba/pi-zig-ai-model-operations-source-20261015')
proof = tree / 'verification/ai-model-operations-4954-20261015'
evidence = pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003')
source = pathlib.Path('C:/Users/adyba/pi-upstream-source-4954d76-20261015')
name = 'ai-model-operations-4954-source-first-20261015'
load = lambda path: json.loads(path.read_text(encoding='utf-8-sig'))
sha = lambda data: hashlib.sha256(data).hexdigest().upper()
output = proof / (name + '-output.json')
expected = tree / 'src/extensions/fixtures/ai-model-operations-4954.json'
assert output.read_bytes() == expected.read_bytes()
document = load(output)
assert document['cases'] == len(document['rows']) == 88
assert document['sourceHead'] == '4954d760504c11df9b2cbdc040346107b6a8153d'
assert document['canonicalModelsErrorIdentity'] is True
input_path = tree / 'src/extensions/fixtures/ai-model-operations-4954.input.txt'
assert sha(input_path.read_bytes()).lower() == document['inputSha256']
rows = {row['name']: row for row in document['rows']}
assert len(rows) == 88
thrown = {'type:raw-getter', 'type:null-model', 'is:getter-raw', 'assert:wrong:chat', 'assert:wrong:image', 'assert:wrong:classifier', 'assert:symbol-template', 'assert:provider-conversion-raw', 'assert:id-getter-raw', 'assert:canonical-class-setter-raw', 'input:reject-order', 'input:images-raw', 'input:length-raw', 'input:model-input-raw', 'input:includes-getter-raw', 'input:includes-call-raw', 'input:missing-context', 'input:missing-input'}
for method in ['imageErrorResult', 'classifierErrorResult']:
    for control in ['instanceof-raw', 'String-getter-raw', 'Date-getter-raw', 'message-getter-raw', 'model-getter-raw', 'invalid-Error', 'invalid-Date-now']:
        thrown.add('result:' + control + ':' + method)
assert {row['name'] for row in document['rows'] if 'thrown' in row} == thrown
diagnostics_path = pathlib.Path(str(output) + '.raw-diagnostics.json')
diagnostics = load(diagnostics_path)['diagnostics']
assert {row['name'] for row in diagnostics} == thrown
diagnostic_counts = collections.Counter(row['kind'] for row in diagnostics)
assert diagnostic_counts == {'raw-sentinel': 20, 'vm-error': 8, 'ModelsError': 4}
assert all(row.get('identityPreserved') is True for row in diagnostics if row['kind'] == 'raw-sentinel')
for row in diagnostics:
    if row['kind'] != 'raw-sentinel':
        assert isinstance(row['message'], str) and isinstance(row['stack'], str)
for row in document['rows']:
    if row['name'].startswith('metadata:'):
        assert 'returned' in row
    if row['name'].startswith('construct:'):
        assert 'returned' in row
owner = load(proof / (name + '-owner.json'))
assert owner['status'] == 'passed' and owner['exit_code'] == 0 and owner['retained_handle']
assert owner['raw_initial_command_line'] and owner['timeout_seconds'] == 300 and owner['settle_seconds'] == 10
pre = load(proof / (name + '-prehash.json'))
post = load(proof / (name + '-posthash.json'))
assert pre['candidate_head'] == 'f4a9a3937594b8129b90181e136ffcf9945274ec'
counts = {key: len(value) for key, value in pre['sets'].items()}
assert counts == {'candidate': 7685, 'source': 1970, 'dependencies': 31064, 'node': 1774, 'compiler': 19546, 'controls': 13}
assert not any(row['drift'] for row in post['manifests'])
assert not any(value for key, value in post.items() if key.endswith('_drift'))
assert not post['unexpected_candidate_untracked_paths']
for key, values in pre['sets'].items():
    for row in values:
        assert sha(pathlib.Path(row['path']).read_bytes()) == row['sha256'].upper(), (key, row['path'])
logs = sorted(evidence.glob('source4954-modules-' + str(owner['pid']) + '-*-20261015.jsonl'))
assert logs
source_modules = set()
workspace_maps = []
for log in logs:
    shutil.copyfile(log, proof / log.name)
    for line in log.read_text().splitlines():
        row = json.loads(line)
        if row['kind'] == 'observed-module':
            path = pathlib.Path(row['path'])
            assert sha(path.read_bytes()).lower() == row['sha256']
            if path.is_relative_to(source):
                source_modules.add(path.relative_to(source).as_posix())
                destination = proof / 'original-source' / path.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
        elif row['kind'] == 'official-workspace-export-map':
            workspace_maps.append(row)
assert {'packages/ai/src/utils/model-operations.ts', 'packages/ai/src/utils/models-error.ts', 'packages/ai/src/index.ts'}.issubset(source_modules)
assert any(row['specifier'] == '@earendil-works/pi-ai' and row['packageVersion'] == '1.3.0' for row in workspace_maps)
assert not subprocess.check_output(['git', '-C', str(tree), 'diff', '--name-only', '3b479da0a86a20c5fd1baf15969777733ded95c9', '--', 'src/extensions/native_ai_model_operations.zig', 'src/extensions/engine.zig', 'src/extensions/native_sdk.zig', 'src/extensions/native_node_function.zig', 'build.zig', 'vendor'])
report = {'status': 'passed_original_source88_native_unrun', 'source_head': document['sourceHead'], 'tested_candidate': pre['candidate_head'], 'cases': 88, 'expected_sha256': sha(expected.read_bytes()), 'raw_diagnostics_sha256': sha(diagnostics_path.read_bytes()), 'raw_diagnostic_counts': dict(diagnostic_counts), 'unexpected_outcomes': [], 'canonical_original_models_error_reexport_identity': True, 'observed_original_source_modules': len(source_modules), 'observed_workspace_mappings': len(workspace_maps), 'frozen_counts': counts, 'all_file_and_inventory_drift': 0, 'owner_pid': owner['pid'], 'owner_created_utc': owner['created_utc'], 'owner_completed_utc': owner['completed_utc'], 'posthash_completed_utc': post['completed_utc'], 'native_compilation_performed': False, 'native_replay_performed': False, 'actual_native_models_error_dependency': 'Federation3e46e0af actual shared file is absent from base3b479; native entry requires owner intake, not a substitute', 'full_pi_qualified': False, 'public_activation': False, 'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
(proof / 'independent-source-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
