from pathlib import Path
import datetime, hashlib, json, subprocess

OWN = Path(r"C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018")
SDK = Path(r"C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018")
PACKET = Path(r"C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018\verification\native-file-handle-owner-sourceonly-20261020")
OUT = OWN / "verification/native-file-handle-sync-close-source-peer-20261020"
BASIS = "2a45648545c961f9008a783ae352f233869505b4"
def sha(data): return hashlib.sha256(data).hexdigest().upper()
def pin(path):
    raw = path.read_bytes()
    return {"path": str(path), "bytes": len(raw), "sha256": sha(raw)}
def exact(path, expected):
    actual = pin(path)
    assert actual["sha256"] == expected, (str(path), actual)
    return actual
def blob(relative):
    return subprocess.check_output(["git", "show", BASIS + ":" + relative], cwd=OWN)

inputs = {}
shared_path = PACKET / "shared/proposal.json"
production_path = PACKET / "production-proposal.json"
inputs["shared_proposal"] = exact(shared_path, "C195AE5D402ED457AF651D6BEB37B2BB8DBD3DF36CD74106EB172F00B64618FC")
inputs["production_proposal"] = exact(production_path, "061258BF1085004B82EA8D1A9C237402F7D4075A4DE837F9C25B7D39D0D3A804")
shared = json.loads(shared_path.read_bytes())
assert shared["main_predecessor_head"] == BASIS
wanted = {
 "src/extensions/native_uv_fs.h": ("E4DC253302062445270904800B2816374DBF840C2BEF4C66C57D6C42D039A8CE", "D5BB021DFECD726A7FBB6860616753957C1B25B11C4776BAFD24F2C935589D34", 2),
 "src/extensions/native_uv_tcp.c": ("5A8DA6FA8AD86DCB44FD5E0B20A139FEF1B1A7D9A7E0CCBD24545702DC00AE71", "85E49522C7C05764957ADACF6B80F2745D5C06E0A361D33531A8BAF9FEA49F87", 1),
}
delta_results = []
for row in shared["files"]:
    rel = row["relative_path"]
    if rel not in wanted: continue
    old_hash, new_hash, count = wanted[rel]
    old = Path(row["original"]["path"])
    new = Path(row["projected"]["path"])
    inputs[rel + ":original"] = exact(old, old_hash)
    inputs[rel + ":projected"] = exact(new, new_hash)
    original, projected = old.read_bytes(), new.read_bytes()
    assert blob(rel) == original
    assert len(row["edits"]) == count
    current = original
    for edit in row["edits"]:
        assert sha(current) == edit["input_sha256"]
        before, after = edit["before"].encode(), edit["after"].encode()
        offset = edit["offset_in_sequential_input"]
        assert current[offset:offset + len(before)] == before
        assert current.count(before) == 1
        current = current[:offset] + after + current[offset + len(before):]
        assert sha(current) == edit["output_sha256"]
    assert current == projected
    for edit in reversed(row["edits"]):
        before, after = edit["before"].encode(), edit["after"].encode()
        offset = edit["offset_in_sequential_input"]
        assert current[offset:offset + len(after)] == after
        current = current[:offset] + before + current[offset + len(after):]
    assert current == original
    delta_results.append({"relative_path": rel, "edits": count,
        "original_matches_immutable_main_commit": True,
        "all_intermediate_hashes_exact": True, "forward_exact": True, "whole_inverse_exact": True})
assert len(delta_results) == 2

uv_expected = {
 "src/win/fs.c": "60C76976514F427FA0BE21C1C7986C2AB1D9E2E77B9D5BCF8C7AB99ED36B0693",
 "src/win/fs-fd-hash-inl.h": "1365F18D01C4117B0F42CFB2E0065F37AD62E4F5214B150CBF660F986955BB2D",
 "src/unix/fs.c": "FFE2CD709C894083D4E470BCE5248EEE71C5E5594418BE3D7A6D80E44D723A61",
 "src/uv-common.h": "7524F791D5648F3E135340AC61BCB242028947A81A5B8B32042F8561848A5397",
 "include/uv.h": "FDDEC8C096616675B4578D85222663C8624DCE3EE67F5BE1C33BA83EB02A827C",
}
for rel, expected in uv_expected.items():
    file = PACKET / "authority/libuv" / rel
    inputs["libuv/" + rel] = exact(file, expected)
    assert file.read_bytes() == blob("vendor/node-v24.13.0/uv/" + rel)
selected = {
 "handle_owner": (PACKET / "production/src/extensions/native_node_file_handle_owner.zig", "2D90F772D2177C7DB4EF4F945F78529C0061C809E171C22CECC324125C9A461D"),
 "gc_close": (PACKET / "production/src/extensions/native_node_file_handle_gc_close.zig", "86E1100598B32022BB38D2DDAD2ABF904C061E915EC0E955C9CAE62B371B83F4"),
 "retained_controller": (PACKET / "shared/projected/src/extensions/native_node_fs_request_io.zig", "B6792DCB053DDC2CFBC26350D9AD580CC5419CF3BDBEB595AF1F19B0922AF996"),
 "canonical_stream_resource": (SDK / "src/extensions/native_node_stream_resource.zig", "6CA4CF5CD5E71EAD8C9E6F4FCF0D0075190C853E26978B497389F7D29EBE0AC6"),
 "canonical_uv_import": (SDK / "src/extensions/native_node_managed_buffers.zig", "BE567B795D5129373EEFCF2A7C95E9017C481E020F17472E2C35838689F22B88"),
 "service_c_import": (SDK / "src/extensions/native_node_uv_service.zig", "CDA7A2AEBD9B752E38521E72A33F4BEE3A7A7453AA8DA38F33F04A61D0E369D5"),
 "node_file_authority": (SDK / "verification/native-node-file-handle-sourceonly-20261019/authority/node_file.v24.13.cc", "19C497BF90FAD9E04645FCA423BC727F18F0B4B9E3C898C35AE2678D12047C0F"),
}
for key, (file, expected) in selected.items(): inputs[key] = exact(file, expected)

ranges = {
 "libuv/src/win/fs.c": [(74,97),(397,410),(668,695),(3127,3136),(3192,3221),(3241,3245)],
 "libuv/src/win/fs-fd-hash-inl.h": [(167,193)],
 "libuv/src/unix/fs.c": [(90,104),(139,166),(1679,1747),(1814,1821),(2239,2269)],
 "libuv/src/uv-common.h": [(342,357)],
 "libuv/include/uv.h": [(242,249),(1443,1453)],
 "node_file_authority": [(336,391)],
 "handle_owner": [(96,143),(178,220)],
 "retained_controller": [(20,41),(199,229),(300,320)],
 "src/extensions/native_uv_tcp.c:projected": [(127,152),(169,183),(652,657),(711,723)],
 "canonical_stream_resource": [(5,16)],
 "canonical_uv_import": [(1,10)],
 "service_c_import": [(1,20)],
}
excerpts = []
for key, spans in ranges.items():
    lines = Path(inputs[key]["path"]).read_text(encoding="utf-8").splitlines()
    for first, last in spans:
        assert 1 <= first <= last <= len(lines)
        text = "\n".join(lines[first-1:last]) + "\n"
        excerpts.append({"input":key,"first_line":first,"last_line":last,
            "logical_LF_excerpt_sha256":sha(text.encode()),"text":text})
# Additional line-exact body anchors record actual source, not runtime behavior.
gc = selected["gc_close"][0].read_text(encoding="utf-8")
sequence = ["var request: native_uv.uv_fs_t = undefined;", "trace.begin_sync(trace.raw);",
 "const result = uv.pi_uv_fs_close_sync(inputs.controller.service,",
 "trace.end_sync(trace.raw);", "native_uv.uv_fs_req_cleanup(&request);",
 "const descriptor = state.fd;", "handle.afterClose()", "const ticket = try environment.allocator().create(Ticket);"]
positions = [gc.index(x) for x in sequence]
assert positions == sorted(positions)
assert ".task = .{ .refed = result < 0," in gc
assert ".environment = environment.retain()," in gc
assert ".result = result," in gc and ".descriptor = descriptor," in gc
audit = {"schema":1,"kind":"independent source-only synchronous-close replay and pinned excerpts",
 "created_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "reviewer":"/root/module_io_port","review_scope":"two helper C/H projected files, their three edits, canonical request and retained-service premise",
 "main_basis":BASIS,"inputs":inputs,"exact_delta_replay":delta_results,
 "five_libuv_snapshots_match_immutable_main_blobs":True,
 "selected_gc_sequence":sequence,"selected_gc_sequence_offsets":positions,
 "source_excerpts":excerpts,"compiler_preprocessor_native_or_Node_execution":False,
 "Main_or_SDK_source_modified":False}
OUT.mkdir(parents=True,exist_ok=True)
target=OUT/"source-audit.json"
assert not target.exists()
target.write_text(json.dumps(audit,indent=2)+"\n",encoding="utf-8",newline="\n")
print(json.dumps({"audit":pin(target),"input_count":len(inputs),"excerpt_ranges":len(excerpts),
 "C_H_files":2,"edits":3,"forward_inverse_and_commit_bindings":True}))
