// Authored separate Source runner. Run only under Root's explicit supervised
// Node-source grant. It invokes one observer, creates no child or output file,
// and never loads a candidate production Module implementation.
import fs from "node:fs";
import crypto from "node:crypto";
import Module from "node:module";
import path from "node:path";
import process from "node:process";
import * as observers from "../../src/extensions/fixtures/native-node-module-creation-observer.mjs";

const names = [
  "observeModuleConstructor","observeModuleAssignments","observeModuleParent","observeModuleDescriptors",
  "observeModulePaths","observeModulePathIndexedPrototype","observeModulePathIndexedThrow","observeModulePathsPrimordials",
  "observeCreateRequireContexts","observeCreateRequireURL","observeCreateRequirePathCallees","observeCreateRequireFailures",
  "observeCreateRequireCapturedURL","observeRequireCopiedFields","observeRequireLiveDispatch",
  "observeModuleWarnings","observeModuleWarningFailure",
];
if (process.versions.node !== "24.14.0") throw Error("Pinned genuine Node 24.14.0 required");
const executableSha256 = crypto.createHash("sha256").update(fs.readFileSync(process.execPath)).digest("hex").toUpperCase();
if (executableSha256 !== "63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088")
  throw Error("Pinned independently admitted original Node executable required");
const name = process.argv[2];
if (process.argv.length !== 3 || !names.includes(name)) throw Error("Exactly one declared Module observer name required");
const pending = name === "observeModuleWarnings" || name === "observeModuleWarningFailure";
if (process.execArgv.includes("--pending-deprecation") !== pending || process.noDeprecation)
  throw Error("Only the two warning observers require the explicit --pending-deprecation flag");
if (process.env.NODE_PENDING_DEPRECATION === "1" && !pending)
  throw Error("Normal observer requires the original non-pending startup option");
observers[name]({Module,path,process});
process.stdout.write(JSON.stringify({
  kind:"genuine-node-module-creation-source-observer",
  node_version:process.version,
  executable_sha256:executableSha256,
  observer:name,
  pending_deprecation:pending,
  completed:true,
  native_candidate_executed:false,
}) + "\n");
