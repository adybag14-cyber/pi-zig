#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const outputPath = resolve(repoRoot, "src/ai/catalog_source.json");

function fail(message) {
  throw new Error(message);
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) fail(`missing ${name} <value>`);
  return process.argv[index + 1];
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

const sourceRoot = resolve(option("--source-root"));
const sourceArchive = resolve(option("--source-archive"));
const upstreamCommit = option("--upstream-commit").toLowerCase();
if (!/^[0-9a-f]{40}$/.test(upstreamCommit)) fail("--upstream-commit must be a full Git SHA");

const packagePath = resolve(sourceRoot, "packages/ai/package.json");
const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
if (packageJson.name !== "@earendil-works/pi-ai") fail(`unexpected package name: ${packageJson.name}`);
if (typeof packageJson.version !== "string" || !/^0\.\d+\.\d+$/.test(packageJson.version)) {
  fail(`unexpected upstream package version: ${packageJson.version}`);
}

const manifestPath = resolve(sourceRoot, "packages/ai/src/providers/data/.manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
if (manifest.schemaVersion !== 3 || typeof manifest.structureHash !== "string") {
  fail("unsupported or malformed upstream model-data manifest");
}

const generatedPath = resolve(sourceRoot, "packages/ai/src/models.generated.ts");
const generated = await import(pathToFileURL(generatedPath).href);
if (!generated.MODELS || typeof generated.MODELS !== "object") fail("upstream MODELS export is missing");

const providers = Object.keys(generated.MODELS);
const models = [];
const identities = new Set();
for (const provider of providers) {
  for (const model of Object.values(generated.MODELS[provider])) {
    if (!model || typeof model !== "object") fail(`${provider}: malformed model entry`);
    if (model.provider !== provider) fail(`${provider}/${model.id}: provider identity mismatch`);
    const identity = `${provider}\0${model.id}`;
    if (identities.has(identity)) fail(`duplicate model identity ${provider}/${model.id}`);
    identities.add(identity);
    models.push(model);
  }
}

const source = {
  schemaVersion: 1,
  upstreamPackage: packageJson.name,
  upstreamVersion: packageJson.version,
  upstreamCommit,
  upstreamReleaseArchiveSha256: sha256File(sourceArchive),
  upstreamModelDataGeneratedAt: manifest.generatedAt,
  upstreamModelDataStructureHash: manifest.structureHash,
  modelCount: models.length,
  providerCount: providers.length,
  models,
};

writeFileSync(outputPath, `${JSON.stringify(source, null, 2)}\n`);
process.stdout.write(
  `upstream_version=${source.upstreamVersion}\n` +
    `upstream_commit=${source.upstreamCommit}\n` +
    `catalog_models=${source.modelCount}\n` +
    `providers=${source.providerCount}\n` +
    `archive_sha256=${source.upstreamReleaseArchiveSha256}\n`,
);
