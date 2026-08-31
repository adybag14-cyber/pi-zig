#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const args = process.argv.slice(2);
const rootIndex = args.indexOf("--upstream-root");
const commitIndex = args.indexOf("--expected-commit");
if (rootIndex < 0 || rootIndex + 1 >= args.length || commitIndex < 0 || commitIndex + 1 >= args.length) {
  fail("usage: import_upstream_changelog.mjs --upstream-root <pi checkout> --expected-commit <sha>");
}

const upstreamRoot = resolve(args[rootIndex + 1]);
const expectedCommit = args[commitIndex + 1].toLowerCase();
const actualCommit = execFileSync("git", ["-C", upstreamRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim().toLowerCase();
if (actualCommit !== expectedCommit) fail(`upstream checkout mismatch: expected ${expectedCommit}, got ${actualCommit}`);

const sourcePath = resolve(upstreamRoot, "packages", "coding-agent", "CHANGELOG.md");
const destinationPath = resolve(import.meta.dirname, "..", "src", "coding_agent", "assets", "UPSTREAM-CHANGELOG.md");
const bytes = readFileSync(sourcePath);
if (!bytes.includes(Buffer.from("## [0.84.4] - 2026-08-28"))) fail("upstream changelog does not contain the pinned 0.84.4 release");
writeFileSync(destinationPath, bytes);
process.stdout.write(`Imported ${bytes.length} changelog bytes from ${actualCommit}\n`);
