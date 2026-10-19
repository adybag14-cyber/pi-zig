(function () {
"use strict";
function parseSkillBlock(text) {
    const match = text.match(/^<skill name="([^"]+)" location="([^"]+)">\n([\s\S]*?)\n<\/skill>(?:\n\n([\s\S]+))?$/);
    if (!match)
        return null;
    return {
        name: match[1],
        location: match[2],
        content: match[3],
        userMessage: match[4]?.trim() || undefined,
    };
}

function parseLineNumber(value) {
	if (typeof value === "string" && value.trim() !== "") value = Number(value);
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function formatReadLineRange(offset, limit) {
	// Strict schemas represent omitted optional arguments as null.
	if (offset == null && limit == null) return "";
	const start = offset == null ? 1 : parseLineNumber(offset);
	if (start === undefined) return "";
	if (limit == null) return `:${start}`;
	const count = parseLineNumber(limit);
	if (count === undefined) return "";
	const end = start + count - 1;
	return `:${start}${end ? `-${end}` : ""}`;
}

/** Prefix of built-in tool and extension paths, such as `builtin:read` or `builtin:mcp`. */
const BUILTIN_PATH_PREFIX = "builtin:";
/**
 * Source of a path that names no file: `builtin` for `builtin:<name>`, or the prefix of an
 * angle-bracket path such as `inline` for `<inline:name>`. Undefined for file paths.
 */
function getSyntheticPathSource(path) {
    if (path.startsWith(BUILTIN_PATH_PREFIX))
        return "builtin";
    if (path.startsWith("<") && path.endsWith(">"))
        return path.slice(1, -1).split(":")[0] || "temporary";
    return undefined;
}
function isSyntheticPath(path) {
    return path.startsWith(BUILTIN_PATH_PREFIX) || path.startsWith("<");
}
function createSourceInfo(path, metadata) {
    return {
        path,
        source: metadata.source,
        scope: metadata.scope,
        origin: metadata.origin,
        baseDir: metadata.baseDir,
    };
}
function createSyntheticSourceInfo(path, options) {
    return {
        path,
        source: options.source,
        scope: options.scope ?? "temporary",
        origin: options.origin ?? "top-level",
        baseDir: options.baseDir,
    };
}
return {parseSkillBlock,formatReadLineRange,createSyntheticSourceInfo,sourceInfo:{BUILTIN_PATH_PREFIX,getSyntheticPathSource,isSyntheticPath,createSourceInfo,createSyntheticSourceInfo}};
})
