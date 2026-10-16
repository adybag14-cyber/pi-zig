//! Actual highlight.js 10.7.3 CSS factory; source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const regex = @import("native_highlight_regex.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const module_data_key = "pi-native:highlight-css-module-data-10.7.3";

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn mode(s: *Scope, class_name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(class_name));
    return result;
}
fn spreadInto(s: *Scope, array: c.JSValue, index: *u32, iterable: c.JSValue) !void {
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try s.index(array, index.*, value);
        index.* += 1;
    }
}
fn moduleData(engine: *em.Engine) !c.JSValue {
    if (engine.native_module_values.get(module_data_key)) |data| return data;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try s.object();
    inline for (.{ .{ "tags", &tags }, .{ "media", &media_features }, .{ "classes", &pseudo_classes }, .{ "elements", &pseudo_elements }, .{ "attributes", &attributes } }) |entry| {
        const array = try s.array();
        for (entry[1], 0..) |text, index| try s.index(array, @intCast(index), try s.text(text));
        // Source's top-level ATTRIBUTES = [...].reverse() runs once at load.
        const value = if (comptime @import("std").mem.eql(u8, entry[0], "attributes")) try s.invoke(array, "reverse", &.{}) else array;
        try s.put(data, entry[0], value);
    }
    try engine.registerValueModule(module_data_key, data);
    return engine.native_module_values.get(module_data_key).?;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    _ = try moduleData(engine);
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "css", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try moduleData(engine);
    const important = try mode(&s, "meta");
    try s.put(important, "begin", try s.text("!important"));
    const hexcolor = try mode(&s, "number");
    try s.put(hexcolor, "begin", try s.text("#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})"));
    const attribute_selector = try mode(&s, "selector-attr");
    try s.put(attribute_selector, "begin", try literal(&s, "\\["));
    try s.put(attribute_selector, "end", try literal(&s, "\\]"));
    try s.put(attribute_selector, "illegal", try s.text("$"));
    try s.put(attribute_selector, "contains", try list(&s, &.{ try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE") }));
    const dispatch = try mode(&s, "built_in");
    try s.put(dispatch, "begin", try literal(&s, "[\\w-]+(?=\\()"));
    const vendor = try s.object();
    try s.put(vendor, "begin", try literal(&s, "-(webkit|moz|ms|o)-(?=[a-z])"));
    const at_property = try literal(&s, "@-?\\w[\\w]*(-\\w+)*");
    const strings = try list(&s, &.{ try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE") });
    const language = try s.object();
    try s.put(language, "name", try s.text("CSS"));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "illegal", try literal(&s, "[=|'\\$]"));
    const keywords = try s.object();
    try s.put(keywords, "keyframePosition", try s.text("from to"));
    try s.put(language, "keywords", keywords);
    const aliases = try s.object();
    try s.put(aliases, "keyframePosition", try s.text("selector-tag"));
    try s.put(language, "classNameAliases", aliases);
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.index(contains, 1, vendor);
    try s.index(contains, 2, try s.get(hljs, "CSS_NUMBER_MODE"));
    const id = try mode(&s, "selector-id");
    try s.put(id, "begin", try literal(&s, "#[A-Za-z0-9_-]+"));
    try s.put(id, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 3, id);
    const class_selector = try mode(&s, "selector-class");
    try s.put(class_selector, "begin", try s.text("\\.[a-zA-Z-][a-zA-Z0-9_-]*"));
    try s.put(class_selector, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 4, class_selector);
    try s.index(contains, 5, attribute_selector);
    const pseudo = try mode(&s, "selector-pseudo");
    const pseudo_class = try s.object();
    const class_prefix = try s.text(":(");
    const joined_classes = try s.invoke(try s.get(data, "classes"), "join", &.{try s.text("|")});
    try s.put(pseudo_class, "begin", try s.concat(try s.concat(class_prefix, joined_classes), try s.text(")")));
    const pseudo_element = try s.object();
    const element_prefix = try s.text("::(");
    const joined_elements = try s.invoke(try s.get(data, "elements"), "join", &.{try s.text("|")});
    try s.put(pseudo_element, "begin", try s.concat(try s.concat(element_prefix, joined_elements), try s.text(")")));
    try s.put(pseudo, "variants", try list(&s, &.{ pseudo_class, pseudo_element }));
    try s.index(contains, 6, pseudo);
    const attribute = try mode(&s, "attribute");
    const attribute_prefix = try s.text("\\b(");
    const joined_attributes = try s.invoke(try s.get(data, "attributes"), "join", &.{try s.text("|")});
    try s.put(attribute, "begin", try s.concat(try s.concat(attribute_prefix, joined_attributes), try s.text(")\\b")));
    try s.index(contains, 7, attribute);
    const values = try s.object();
    try s.put(values, "begin", try s.text(":"));
    try s.put(values, "end", try s.text("[;}]"));
    const value_modes = try list(&s, &.{ hexcolor, important, try s.get(hljs, "CSS_NUMBER_MODE") });
    var value_index: u32 = 3;
    try spreadInto(&s, value_modes, &value_index, strings);
    const url = try s.object();
    try s.put(url, "begin", try literal(&s, "(url|data-uri)\\("));
    try s.put(url, "end", try literal(&s, "\\)"));
    try s.put(url, "relevance", c.JS_NewInt32(engine.context, 0));
    const url_keywords = try s.object();
    try s.put(url_keywords, "built_in", try s.text("url data-uri"));
    try s.put(url, "keywords", url_keywords);
    const url_string = try mode(&s, "string");
    try s.put(url_string, "begin", try literal(&s, "[^)]"));
    try s.put(url_string, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(url_string, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(url, "contains", try list(&s, &.{url_string}));
    try s.index(value_modes, value_index, url);
    try s.index(value_modes, value_index + 1, dispatch);
    try s.put(values, "contains", value_modes);
    try s.index(contains, 8, values);
    const at_rule = try s.object();
    try s.put(at_rule, "begin", try s.own(try regex.concat(engine, try list(&s, &.{ try s.text("(?="), try literal(&s, "@"), try s.text(")") }))));
    try s.put(at_rule, "end", try s.text("[{;]"));
    try s.put(at_rule, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(at_rule, "illegal", try literal(&s, ":"));
    const at_keyword = try mode(&s, "keyword");
    try s.put(at_keyword, "begin", at_property);
    const at_content = try s.object();
    try s.put(at_content, "begin", try literal(&s, "\\s"));
    try s.put(at_content, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(at_content, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(at_content, "relevance", c.JS_NewInt32(engine.context, 0));
    const at_keywords = try s.object();
    try s.put(at_keywords, "$pattern", try literal(&s, "[a-z-]+"));
    try s.put(at_keywords, "keyword", try s.text("and or not only"));
    try s.put(at_keywords, "attribute", try s.invoke(try s.get(data, "media"), "join", &.{try s.text(" ")}));
    try s.put(at_content, "keywords", at_keywords);
    const at_attribute = try s.object();
    try s.put(at_attribute, "begin", try literal(&s, "[a-z-]+(?=:)"));
    try s.put(at_attribute, "className", try s.text("attribute"));
    const at_modes = try list(&s, &.{at_attribute});
    var at_index: u32 = 1;
    try spreadInto(&s, at_modes, &at_index, strings);
    try s.index(at_modes, at_index, try s.get(hljs, "CSS_NUMBER_MODE"));
    try s.put(at_content, "contains", at_modes);
    try s.put(at_rule, "contains", try list(&s, &.{ at_keyword, at_content }));
    try s.index(contains, 9, at_rule);
    const tag = try mode(&s, "selector-tag");
    const tag_prefix = try s.text("\\b(");
    const joined_tags = try s.invoke(try s.get(data, "tags"), "join", &.{try s.text("|")});
    try s.put(tag, "begin", try s.concat(try s.concat(tag_prefix, joined_tags), try s.text(")\\b")));
    try s.index(contains, 10, tag);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}

const tags = [_][]const u8{
    "a",
    "abbr",
    "address",
    "article",
    "aside",
    "audio",
    "b",
    "blockquote",
    "body",
    "button",
    "canvas",
    "caption",
    "cite",
    "code",
    "dd",
    "del",
    "details",
    "dfn",
    "div",
    "dl",
    "dt",
    "em",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "hgroup",
    "html",
    "i",
    "iframe",
    "img",
    "input",
    "ins",
    "kbd",
    "label",
    "legend",
    "li",
    "main",
    "mark",
    "menu",
    "nav",
    "object",
    "ol",
    "p",
    "q",
    "quote",
    "samp",
    "section",
    "span",
    "strong",
    "summary",
    "sup",
    "table",
    "tbody",
    "td",
    "textarea",
    "tfoot",
    "th",
    "thead",
    "time",
    "tr",
    "ul",
    "var",
    "video",
};
const media_features = [_][]const u8{
    "any-hover",
    "any-pointer",
    "aspect-ratio",
    "color",
    "color-gamut",
    "color-index",
    "device-aspect-ratio",
    "device-height",
    "device-width",
    "display-mode",
    "forced-colors",
    "grid",
    "height",
    "hover",
    "inverted-colors",
    "monochrome",
    "orientation",
    "overflow-block",
    "overflow-inline",
    "pointer",
    "prefers-color-scheme",
    "prefers-contrast",
    "prefers-reduced-motion",
    "prefers-reduced-transparency",
    "resolution",
    "scan",
    "scripting",
    "update",
    "width",
    "min-width",
    "max-width",
    "min-height",
    "max-height",
};
const pseudo_classes = [_][]const u8{
    "active",
    "any-link",
    "blank",
    "checked",
    "current",
    "default",
    "defined",
    "dir",
    "disabled",
    "drop",
    "empty",
    "enabled",
    "first",
    "first-child",
    "first-of-type",
    "fullscreen",
    "future",
    "focus",
    "focus-visible",
    "focus-within",
    "has",
    "host",
    "host-context",
    "hover",
    "indeterminate",
    "in-range",
    "invalid",
    "is",
    "lang",
    "last-child",
    "last-of-type",
    "left",
    "link",
    "local-link",
    "not",
    "nth-child",
    "nth-col",
    "nth-last-child",
    "nth-last-col",
    "nth-last-of-type",
    "nth-of-type",
    "only-child",
    "only-of-type",
    "optional",
    "out-of-range",
    "past",
    "placeholder-shown",
    "read-only",
    "read-write",
    "required",
    "right",
    "root",
    "scope",
    "target",
    "target-within",
    "user-invalid",
    "valid",
    "visited",
    "where",
};
const pseudo_elements = [_][]const u8{
    "after",
    "backdrop",
    "before",
    "cue",
    "cue-region",
    "first-letter",
    "first-line",
    "grammar-error",
    "marker",
    "part",
    "placeholder",
    "selection",
    "slotted",
    "spelling-error",
};
const attributes = [_][]const u8{
    "align-content",
    "align-items",
    "align-self",
    "animation",
    "animation-delay",
    "animation-direction",
    "animation-duration",
    "animation-fill-mode",
    "animation-iteration-count",
    "animation-name",
    "animation-play-state",
    "animation-timing-function",
    "auto",
    "backface-visibility",
    "background",
    "background-attachment",
    "background-clip",
    "background-color",
    "background-image",
    "background-origin",
    "background-position",
    "background-repeat",
    "background-size",
    "border",
    "border-bottom",
    "border-bottom-color",
    "border-bottom-left-radius",
    "border-bottom-right-radius",
    "border-bottom-style",
    "border-bottom-width",
    "border-collapse",
    "border-color",
    "border-image",
    "border-image-outset",
    "border-image-repeat",
    "border-image-slice",
    "border-image-source",
    "border-image-width",
    "border-left",
    "border-left-color",
    "border-left-style",
    "border-left-width",
    "border-radius",
    "border-right",
    "border-right-color",
    "border-right-style",
    "border-right-width",
    "border-spacing",
    "border-style",
    "border-top",
    "border-top-color",
    "border-top-left-radius",
    "border-top-right-radius",
    "border-top-style",
    "border-top-width",
    "border-width",
    "bottom",
    "box-decoration-break",
    "box-shadow",
    "box-sizing",
    "break-after",
    "break-before",
    "break-inside",
    "caption-side",
    "clear",
    "clip",
    "clip-path",
    "color",
    "column-count",
    "column-fill",
    "column-gap",
    "column-rule",
    "column-rule-color",
    "column-rule-style",
    "column-rule-width",
    "column-span",
    "column-width",
    "columns",
    "content",
    "counter-increment",
    "counter-reset",
    "cursor",
    "direction",
    "display",
    "empty-cells",
    "filter",
    "flex",
    "flex-basis",
    "flex-direction",
    "flex-flow",
    "flex-grow",
    "flex-shrink",
    "flex-wrap",
    "float",
    "font",
    "font-display",
    "font-family",
    "font-feature-settings",
    "font-kerning",
    "font-language-override",
    "font-size",
    "font-size-adjust",
    "font-smoothing",
    "font-stretch",
    "font-style",
    "font-variant",
    "font-variant-ligatures",
    "font-variation-settings",
    "font-weight",
    "height",
    "hyphens",
    "icon",
    "image-orientation",
    "image-rendering",
    "image-resolution",
    "ime-mode",
    "inherit",
    "initial",
    "justify-content",
    "left",
    "letter-spacing",
    "line-height",
    "list-style",
    "list-style-image",
    "list-style-position",
    "list-style-type",
    "margin",
    "margin-bottom",
    "margin-left",
    "margin-right",
    "margin-top",
    "marks",
    "mask",
    "max-height",
    "max-width",
    "min-height",
    "min-width",
    "nav-down",
    "nav-index",
    "nav-left",
    "nav-right",
    "nav-up",
    "none",
    "normal",
    "object-fit",
    "object-position",
    "opacity",
    "order",
    "orphans",
    "outline",
    "outline-color",
    "outline-offset",
    "outline-style",
    "outline-width",
    "overflow",
    "overflow-wrap",
    "overflow-x",
    "overflow-y",
    "padding",
    "padding-bottom",
    "padding-left",
    "padding-right",
    "padding-top",
    "page-break-after",
    "page-break-before",
    "page-break-inside",
    "perspective",
    "perspective-origin",
    "pointer-events",
    "position",
    "quotes",
    "resize",
    "right",
    "src",
    "tab-size",
    "table-layout",
    "text-align",
    "text-align-last",
    "text-decoration",
    "text-decoration-color",
    "text-decoration-line",
    "text-decoration-style",
    "text-indent",
    "text-overflow",
    "text-rendering",
    "text-shadow",
    "text-transform",
    "text-underline-position",
    "top",
    "transform",
    "transform-origin",
    "transform-style",
    "transition",
    "transition-delay",
    "transition-duration",
    "transition-property",
    "transition-timing-function",
    "unicode-bidi",
    "vertical-align",
    "visibility",
    "white-space",
    "widows",
    "width",
    "word-break",
    "word-spacing",
    "word-wrap",
    "z-index",
};
