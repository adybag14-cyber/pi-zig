(function(actualYamlParse) {
"use strict";
const parse = actualYamlParse;
/** Split a leading UTF-8 byte order mark from decoded text. */
function splitBom(content) {
    return content.startsWith("\uFEFF") ? { bom: "\uFEFF", text: content.slice(1) } : { bom: "", text: content };
}
/** Remove a leading UTF-8 byte order mark from decoded text. */
function stripBom(content) {
    return splitBom(content).text;
}
const normalizeNewlines = (value) => value.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
const extractFrontmatter = (content) => {
    const normalized = normalizeNewlines(stripBom(content));
    if (!normalized.startsWith("---")) {
        return { yamlString: null, body: normalized };
    }
    const endIndex = normalized.indexOf("\n---", 3);
    if (endIndex === -1) {
        return { yamlString: null, body: normalized };
    }
    return {
        yamlString: normalized.slice(4, endIndex),
        body: normalized.slice(endIndex + 4).trim(),
    };
};
const parseFrontmatter = (content) => {
    const { yamlString, body } = extractFrontmatter(content);
    if (!yamlString) {
        return { frontmatter: {}, body };
    }
    const parsed = parse(yamlString);
    return { frontmatter: (parsed ?? {}), body };
};
const stripFrontmatter = (content) => parseFrontmatter(content).body;
return {parseFrontmatter, stripFrontmatter, text: {splitBom, stripBom}};
})
