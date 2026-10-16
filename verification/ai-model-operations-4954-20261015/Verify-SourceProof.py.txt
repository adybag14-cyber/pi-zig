import hashlib
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent
load = lambda path: json.loads(path.read_text(encoding='utf-8-sig'))
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest().upper()
manifest = load(root / 'proof-manifest.json')
actual = {path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file() and path.name not in ['proof-manifest.json', 'source88-proof.zip']}
assert actual == {row['relative'] for row in manifest}
for row in manifest:
    path = root / row['relative']
    assert path.resolve().is_relative_to(root.resolve())
    assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
name = 'ai-model-operations-4954-source-first-20261015'
document = load(root / (name + '-output.json'))
assert document['sourceHead'] == '4954d760504c11df9b2cbdc040346107b6a8153d'
assert document['cases'] == len(document['rows']) == 88 and document['canonicalModelsErrorIdentity']
assert sha(root / (name + '-output.json')) == '99244517F5B7A85811380EE6BE2D587D962402F16ADF94D341F1F287DEAD6AE0'
assert sha(root / (name + '-output.json.raw-diagnostics.json')) == 'C2583EEFFBDC88796A9149C7692C6A158A3FDA36934DBE0B69855FD9920C9320'
owner = load(root / (name + '-owner.json'))
assert owner['status'] == 'passed' and owner['exit_code'] == 0 and owner['pid'] == 56660
assert owner['raw_initial_command_line'] and owner['retained_handle']
post = load(root / (name + '-posthash.json'))
assert not any(row['drift'] for row in post['manifests'])
assert not any(value for key, value in post.items() if key.endswith('_drift'))
assert not post['unexpected_candidate_untracked_paths']
audit = load(root / 'independent-source-audit.json')
assert audit['status'] == 'passed_original_source88_native_unrun'
assert audit['raw_diagnostic_counts'] == {'raw-sentinel': 20, 'vm-error': 8, 'ModelsError': 4}
assert not audit['unexpected_outcomes'] and not audit['native_compilation_performed'] and not audit['native_replay_performed']
print('MODEL_OPERATION_SOURCE88_OFFLINE_PROOF_PASSED files=' + str(len(manifest)))
