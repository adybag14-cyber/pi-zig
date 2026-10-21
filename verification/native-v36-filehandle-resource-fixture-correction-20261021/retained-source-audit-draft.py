"""Independent bounded source audit. No project code, preparer, or native tests run.
Only FINAL OUTPUT creates this audit's new evidence JSON; all earlier operations read.
"""
from pathlib import Path
import hashlib, json, re, subprocess

MAIN = Path(r"C:\Users\adyba\pi-zig\main")
PACKET = Path(r"C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018\verification\v36-file-handle-outer-scope-sourceonly-20261021")
OUT = Path(__file__).resolve().parent
HEAD = "a6b6c37680d4b66f8cb90b9eb03a6efff6d0bef8"
ROOT_REVIEW = Path(r"C:\Users\adyba\pi-zig\evidence\root-v36-filehandle-outer-resource-fixture-static-review-20261021.json")
pins = []
raws = {}

def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()

def read_pin(row, label):
    p = Path(row["path"])
    raw = p.read_bytes()
    assert len(raw) == row["bytes"], (label, "bytes", len(raw))
    assert sha(raw) == row["sha256"], (label, "sha256", sha(raw))
    pins.append({"label": label, "path": str(p), "bytes": len(raw), "sha256": sha(raw)})
    raws[label] = raw
    return raw

def pin(path, count, digest, label):
    return read_pin({"path": str(path), "bytes": count, "sha256": digest}, label)

def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-c", "core.fsmonitor=false",
                        "-C", str(MAIN), *args],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=20)
    return r.stdout

proposal = json.loads(pin(PACKET / "proposal.json", 11951,
    "E40157BF97BD043A541247B885680820560135EE4286F896F031B268C6B5FEFB", "proposal"))
ownership = json.loads(pin(PACKET / "ownership-proof.json", 14106,
    "D12FC3C071251FC75B1CAD32E684522F443E903167C6055765E862BCE5475D73", "sdk_ownership"))
pin(ROOT_REVIEW, 6480,
    "D19CB4DEA35E842D5BEB45BC0FA5A310B14A48CA432F0037211FE9A63C80386D", "root_review")
assert proposal["base_head"] == HEAD
assert proposal["source_target"] == "src/native_node_file_handle_owner_test_support.zig"
assert git("rev-parse", "HEAD").decode().strip() == HEAD
original = read_pin(proposal["original"], "original")
candidate = read_pin(proposal["projected"], "candidate")
live = read_pin(proposal["input"], "main_fixture")
committed = git("show", HEAD + ":" + proposal["source_target"])
assert original == live == committed
for key, row in ownership["sources"].items():
    read_pin(row, "ownership_" + key)
pin(MAIN / "src/extensions/native_sdk_owned_completion.zig", 15176,
    "BED505F14A7E0E0792802DA8EB915404C2E7AAFC77D8274108A6B916A8C0E6CC", "completion")

expected_edits = [
    (
        b"        const bootstrap_result = try a.expression(self.engine, bootstrap, .{self});\n"
        b"        self.engine.freeValue(bootstrap_result);\n",
        b"        const outer_resource = try a.expression(self.engine, bootstrap, .{self});\n"
        b"        defer self.engine.freeValue(outer_resource);\n", 13624,
        "62B7E5A76E3CE04C60B6FD313EBC6C9D91845AECA8993328D713A31E090B6C30"
    ),
    (
        b"        self.outer.init(self.env(), c.pi_js_undefined(),\n",
        b"        self.outer.init(self.env(), outer_resource,\n", 14304,
        "526DF1D1391A4C03C50D85E1B970FB12EDCE972732467DA29BEF9DFE3A39CBD0"
    ),
    (
        b"        try s.boundary.checkPendingSince(class_generation);\n"
        b"        return c.pi_js_undefined();\n",
        b"        try s.boundary.checkPendingSince(class_generation);\n"
        b"        return a.duplicate(s.engine, try s.object());\n", 16720,
        "EEDD73ADC5B2F260B07DD3877658FABE2C11A6AAC2BF4216E17E7328E27CA47F"
    ),
]
assert len(proposal["edits"]) == len(expected_edits) == 3
steps = []
current = original
for index, (edit, expected) in enumerate(zip(proposal["edits"], expected_edits), 1):
    before, after, offset, digest = expected
    assert edit == {"before": before.decode(), "after": after.decode(), "offset_before_step": offset}
    assert current.count(before) == 1 and current.index(before) == offset
    prior = current
    current = current[:offset] + after + current[offset + len(before):]
    assert sha(current) == digest
    steps.append({"step": index, "offset": offset, "before_bytes": len(before),
                  "after_bytes": len(after), "before_sha256": sha(prior),
                  "after_sha256": sha(current)})
assert current == candidate
for before, after, offset, digest in reversed(expected_edits):
    assert current[offset:offset + len(after)] == after
    current = current[:offset] + before + current[offset + len(after):]
assert current == original

imports = lambda raw: [x.decode() for x in re.findall(rb'@import\("([^"]+)"\)', raw)]
embeds = lambda raw: [x.decode() for x in re.findall(rb'@embedFile\("([^"]+)"\)', raw)]
assert imports(original) == imports(candidate) == proposal["unchanged_import_literals"]
assert embeds(original) == embeds(candidate)
assert sum(x.endswith(".zig") for x in imports(candidate)) == 16
assert imports(candidate).count("std") == 1

def section(raw, first, until):
    assert raw.count(first) == 1 and raw.count(until) == 1
    return raw[raw.index(first):raw.index(until)]

unchanged_sections = []
for label, first, until in [
    ("partial_scope_init_catch", b"            undefined) catch |err| {", b"        self.outer_initialized = true;"),
    ("handle_and_binding_gc_helpers", b"    pub fn collectHandle(", b"    pub fn pendingClose("),
    ("fixture_deinit", b"    pub fn deinit(", b"    fn drop(self:"),
]:
    b = section(original, first, until)
    assert b == section(candidate, first, until)
    unchanged_sections.append({"label": label, "bytes": len(b), "sha256": sha(b)})

root_results = []
for r in proposal["declared_roots"]:
    raw = read_pin(r["source"], "root_" + r["name"])
    rel = Path(r["source"]["path"]).relative_to(MAIN).as_posix()
    assert git("show", HEAD + ":" + rel) == raw
    names = [x.decode() for x in re.findall(rb'(?m)^test\s+"([^"\r\n]+)"\s*\{', raw)]
    assert names == r["declared_names"] and len(names) == r["declarations"]
    root_results.append({"name": r["name"], "source": r["source"],
                         "declarations": len(names),
                         "names_sha256": sha(json.dumps(names, separators=(",", ":")).encode())})
assert [r["declarations"] for r in root_results] == [18, 3, 24, 13]
assert sum(r["declarations"] for r in root_results) == proposal["unchanged_declared_controls"] == 58
read_pin(proposal["catalog"], "catalog")

excerpts = []
for e in ownership["exact_excerpt_ranges"]:
    raw = raws["ownership_" + e["source_key"]]
    lines = raw.splitlines(keepends=True)
    first, last = e["first_line"], e["last_line"]
    assert 1 <= first <= last <= len(lines)
    selected = b"".join(lines[first - 1:last])
    assert len(selected) == e["bytes"] and sha(selected) == e["sha256"]
    excerpts.append({"id": e["id"], "source_key": e["source_key"],
                     "first_line": first, "last_line": last,
                     "bytes": len(selected), "sha256": sha(selected)})
assert len(ownership["sources"]) == 13 and len(excerpts) == 17
assert git("rev-parse", "HEAD").decode().strip() == HEAD
assert git("status", "--porcelain=v1", "--untracked-files=no") == b""
proof = {
    "schema": "pi-zig-independent-v36-outer-resource-fixture-checks-v1",
    "status": "passed source-only finite checks",
    "main_head": HEAD,
    "main_tracked_status_clean": True,
    "live_fixture_equals_raw_committed_preimage": True,
    "pins": pins,
    "edit_steps": steps,
    "whole_forward_and_inverse_exact": True,
    "all_other_fixture_bytes_unchanged": True,
    "unchanged_sections": unchanged_sections,
    "literal_imports": imports(candidate),
    "literal_embeds": embeds(candidate),
    "root_results": root_results,
    "unchanged_declared_controls": 58,
    "sdk_ownership_source_pins": 13,
    "sdk_ownership_exact_excerpts": excerpts,
    "graph_claim": "Only the unchanged literal import/embed topology and four unchanged root sources are asserted; no graph or native metadata recount was executed.",
    "scope": {
        "Main_written": False, "production_changed": False,
        "project_native_compiler_reference_generator_executed": False,
        "reviewed_preparer_adapter_or_auditor_executed": False,
        "runtime_qualified": False,
        "checks": "Python byte/hash/source checks and read-only Git only."
    }
}
raw = (json.dumps(proof, indent=2, ensure_ascii=False) + "\n").encode()
# FINAL OUTPUT: create only this fresh evidence file, never overwrite.
with (OUT / "source-audit.json").open("xb") as f:
    f.write(raw)
print(json.dumps({"path": str(OUT / "source-audit.json"), "bytes": len(raw), "sha256": sha(raw),
                  "pins": len(pins), "edits": len(steps), "excerpts": len(excerpts),
                  "declarations": 58, "passed": True}))
