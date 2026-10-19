// Authored Source runner: Root's distinct supervised Node-source grant only.
// One observer per fresh admitted Node process. No child or candidate load.
import fs from "node:fs";
import crypto from "node:crypto";
import Module from "node:module";
import path from "node:path";
import process from "node:process";
import {debuglog} from "node:util";
import * as observers from "../../src/extensions/fixtures/native-node-module-search-paths-observer.mjs";

const names = [
  "observeSearchPathShapes",
  "observeLookupBuiltinCoercion",
  "observeLookupParentArrayLike",
  "observeLookupOptionalPaths",
  "observeLookupRelativeOrder",
  "observeLookupRelativeShortCircuit",
  "observeLookupAbruptOrder",
  "observeLookupWindowsSpelling",
  "observeInitPathsClone",
  "observeInitPathsEvaluation",
  "observeInitPathsFailurePublication",
  "observeSearchCapturedPrimordials"
];
if (process.versions.node !== "24.14.0" || process.platform !== "win32")
  throw Error("Pinned genuine Windows Node 24.14.0 required");
const executableSha256 = crypto.createHash("sha256").update(fs.readFileSync(process.execPath)).digest("hex").toUpperCase();
if (executableSha256 !== "63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088")
  throw Error("Pinned independently admitted original Node executable required");
if (debuglog("module").enabled) throw Error("Selected Module debug-disabled authority required");
if (process.execArgv.includes("--expose-internals")) throw Error("Default public builtin policy required");
const name = process.argv[2];
if (process.argv.length !== 3 || !names.includes(name)) throw Error("Exactly one declared search-path observer required");
observers[name]({Module,path,process});
process.stdout.write(JSON.stringify({
  kind:"genuine-node-module-search-paths-source-observer",
  node_version:process.version,
  executable_sha256:executableSha256,
  observer:name,
  module_debug_enabled:false,
  completed:true,
  native_candidate_executed:false,
}) + "\n");
