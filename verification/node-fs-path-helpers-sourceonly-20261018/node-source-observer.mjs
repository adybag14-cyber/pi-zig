// Authored Source capture entrypoint. Run only under Root's separate grant.
import fs from "node:fs";
import crypto from "node:crypto";
import vm from "node:vm";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
if (process.version !== "v24.13.0") throw new Error("Pinned Node v24.13.0 is required");
const hash = data => crypto.createHash("sha256").update(data).digest("hex");
const authority = fs.readFileSync(new URL("./authority/fs_utils.js.txt",import.meta.url));
if (hash(authority) !== "d8d4d3a3f2a7ff89f14366c9ed02e379fd09351a9a1781d1d552875cc80bfce7") throw new Error("FS Source authority changed");
const emptyAuthority = JSON.parse(fs.readFileSync(new URL("./authority/internal-util-empty-object.json",import.meta.url),"utf8"));
if (emptyAuthority.source.content_sha256 !== "ebd5e67c4b31e484b157239f7a7e38cbe29f175afb53d2b95e19acc2520d43b5") throw new Error("Empty-object Source authority changed");
const observer = fs.readFileSync(new URL("../../src/extensions/fixtures/native-node-fs-path-observer.mjs",import.meta.url));
vm.runInThisContext(observer.toString("utf8"), {filename:"actual-node-fs-path-observer.mjs"});
const utils = require("internal/fs/utils");
const util = require("internal/util");
const {codes} = require("internal/errors");
const actual = {
  getOptions: utils.getOptions, validatePath: utils.validatePath,
  realpathCacheKey: utils.realpathCacheKey, kEmptyObject: util.kEmptyObject,
  Buffer: require("buffer").Buffer,
  invalid_arg_type: codes.ERR_INVALID_ARG_TYPE,
  invalid_arg_value: codes.ERR_INVALID_ARG_VALUE,
};
const names = [
  "observeFsPathDefaults","observeFsPathStringSpread","observeFsPathOptionTypes",
  "observeFsPathEncodingReads","observeFsPathBufferSentinel","observeFsPathLiveBuffer",
  "observeFsPathSignalReads","observeFsPathOrdinaryFailures","observeFsPathValidateShape",
  "observeFsPathValidateInvalid","observeFsPathValidateNul","observeFsPathCapturedIncludes",
];
const observations = [];
for (const name of names) { globalThis[name](actual); observations.push({name, passed:true}); }
process.stdout.write(JSON.stringify({
  runtime:process.version, executable:process.execPath, declared:names.length,
  authority_sha256:hash(authority), observer_sha256:hash(observer), observations,
}) + "\n");
