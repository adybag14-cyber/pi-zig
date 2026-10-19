// Authored genuine Node capture entrypoint. Execution needs Root's separate grant.
// argv[2] is an existing, contained parent for this runner's fresh fixture only.
import fs, {realpathSync as namedRealpath} from "node:fs";
import paths from "node:path";
import {Buffer} from "node:buffer";
import {URL} from "node:url";
import crypto from "node:crypto";
import vm from "node:vm";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
if (process.version !== "v24.13.0") throw new Error("Pinned Node v24.13.0 is required");
const hash = data => crypto.createHash("sha256").update(data).digest("hex");
const authority = fs.readFileSync(new URL("./authority/selected-node-fs.json", import.meta.url));
if (hash(authority) !== "6c79695b2e03bf56525f2ad5eb31e8cbf2bc91a68a109729a060bb3dc7f7ecf7")
  throw new Error("Classic realpath Source authority changed");
const selected = JSON.parse(authority.toString("utf8"));
if (selected.version !== "v24.13.0" ||
    selected.source_sha256 !== "a278a9082b2cd97bbb0638413f81838e5de691e7562aef5de81f29b4cc7990d4")
  throw new Error("Unexpected original Node fs Source pin");
const observer = fs.readFileSync(new URL("../../src/extensions/fixtures/native-node-classic-realpath-observer.mjs", import.meta.url));
if (hash(observer) !== "8fbdab8cf6a49ec009587f8c88d858fa10527b7e1ec8cf659227bbb7c2d96cd0")
  throw new Error("Classic realpath observer changed");
const parentInput = process.argv[2];
if (!parentInput || !paths.isAbsolute(parentInput))
  throw new Error("An absolute existing fixture parent inside C:/Users/adyba/pi-zig is required");
const workspace = fs.realpathSync.native("C:/Users/adyba/pi-zig");
const parent = fs.realpathSync.native(parentInput);
const relative = paths.relative(workspace, parent);
if (relative === ".." || relative.startsWith(".." + paths.sep) || paths.isAbsolute(relative) ||
    !fs.statSync(parent).isDirectory())
  throw new Error("Fixture parent must resolve inside the approved container");
const utils = require("internal/fs/utils");
const names = [
  "observeClassicShape", "observeClassicPlain", "observeClassicFileLinks",
  "observeClassicDirectoryLinks", "observeClassicPathInputs", "observeClassicOptionFailure",
  "observeClassicTruthyCache", "observeClassicLiveResolve", "observeClassicCacheOrder",
  "observeClassicCachedLink", "observeClassicEncoding", "observeClassicBuiltinEncoding",
  "observeClassicNativeErrors", "observeClassicLinkLoop", "observeClassicCapturedIntrinsics",
  "observeClassicCacheSetFailure",
];
vm.runInThisContext(observer.toString("utf8"), {filename:"actual-node-classic-realpath-observer.mjs"});
const root = fs.mkdtempSync(paths.join(parent, "classic-realpath-"));
const observations = [];
try {
  fs.mkdirSync(paths.join(root, "dir", "nested"), {recursive:true});
  fs.writeFileSync(paths.join(root, "dir", "file.txt"), "classic\n");
  fs.writeFileSync(paths.join(root, "dir", "nested", "end.txt"), "end\n");
  const links = [
    [paths.join("dir", "file.txt"), "relative-file", "file"],
    [paths.join(root, "dir", "file.txt"), "absolute-file", "file"],
    ["relative-file", "chain-file", "file"],
    ["dir", "directory-link", "dir"],
    ["directory-link", "second-directory", "dir"],
    ["missing-target", "broken-link", "file"],
    ["loop-b", "loop-a", "file"],
    ["loop-a", "loop-b", "file"],
  ];
  for (const [target, name, type] of links)
    fs.symlinkSync(target, paths.join(root, name), type);
  const actual = {
    fs, paths, Buffer, URL, root, platform:process.platform,
    realpath:fs.realpathSync, namedRealpath,
    nativeOriginal:fs.realpathSync.native, key:utils.realpathCacheKey,
  };
  for (const name of names) {
    globalThis[name](actual);
    observations.push({name, passed:true});
  }
} finally {
  // root is the exact fresh mkdtemp owner above. Directory links are removed
  // as links; this cleanup never traverses or removes the parent directory.
  fs.rmSync(root, {recursive:true, force:true});
}
process.stdout.write(JSON.stringify({
  runtime:process.version, executable:process.execPath, platform:process.platform,
  declared:names.length, authority_sha256:hash(authority),
  original_fs_sha256:selected.source_sha256, observer_sha256:hash(observer),
  fixture_parent:parent, fixture_removed:true, observations,
}) + "\n");
