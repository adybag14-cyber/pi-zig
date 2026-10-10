//! Source ordinary TUI function signatures with genuine native construction.
//! The bodies remain their native Zig implementations. Constructor return
//! override, new.target and prototype behavior share the qualified Node helper.
const js = @import("native_js_values.zig");
const c = js.c;
fn original(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return js.call(engine, values[0], receiver, args);
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    // Ported from the actual Source6fb function declarations. The separate
    // captured Source metadata test rejects signature or descriptor drift.
    inline for (.{
        .{ "allocateImageId", "allocateImageId", 0 },
        .{ "backgroundAnsi", "backgroundAnsi", 2 },
        .{ "calculateImageRows", "calculateImageRows", 2 },
        .{ "colorToHex", "colorToHex", 1 },
        .{ "colorToOkhsl", "colorToOkhsl", 1 },
        .{ "colorToOklch", "colorToOklch", 1 },
        .{ "colorToRgb", "colorToRgb", 1 },
        .{ "compositeTuiLine", "compositeTuiLine", 5 },
        .{ "decodeKittyPrintable", "decodeKittyPrintable", 1 },
        .{ "deleteAllKittyImages", "deleteAllKittyImages", 0 },
        .{ "deleteKittyImage", "deleteKittyImage", 1 },
        .{ "detectCapabilities", "detectCapabilities", 0 },
        .{ "encodeITerm2", "encodeITerm2", 1 },
        .{ "encodeKitty", "encodeKitty", 1 },
        .{ "foregroundAnsi", "foregroundAnsi", 2 },
        .{ "formatProgramStatus", "formatProgramStatus", 1 },
        .{ "fuzzyFilter", "fuzzyFilter", 3 },
        .{ "fuzzyMatch", "fuzzyMatch", 2 },
        .{ "getCapabilities", "getCapabilities", 0 },
        .{ "getCellDimensions", "getCellDimensions", 0 },
        .{ "getGifDimensions", "getGifDimensions", 1 },
        .{ "getImageDimensions", "getImageDimensions", 2 },
        .{ "getJpegDimensions", "getJpegDimensions", 1 },
        .{ "getKeybindings", "getKeybindings", 0 },
        .{ "getNativeClipboard", "getNativeClipboard", 0 },
        .{ "getOsc8LinkAtColumn", "getOsc8LinkAtColumn", 2 },
        .{ "getPngDimensions", "getPngDimensions", 1 },
        .{ "getTerminalColorMode", "getTerminalColorMode", 0 },
        .{ "getWebpDimensions", "getWebpDimensions", 1 },
        .{ "hyperlink", "hyperlink", 2 },
        .{ "imageFallback", "imageFallback", 3 },
        .{ "indexedColor", "indexedColor", 1 },
        .{ "isAppleTerminalSession", "isAppleTerminalSession", 0 },
        .{ "isFocusable", "isFocusable", 1 },
        .{ "isKeyRelease", "isKeyRelease", 1 },
        .{ "isKeyRepeat", "isKeyRepeat", 1 },
        .{ "isKittyProtocolActive", "isKittyProtocolActive", 0 },
        .{ "isViewportTUI", "isViewportTUI", 1 },
        .{ "matchesKey", "matchesKey", 2 },
        .{ "mixColors", "mixColors", 3 },
        .{ "okhslColor", "okhslColor", 3 },
        .{ "oklchColor", "oklchColor", 3 },
        .{ "parseColor", "parseColor", 1 },
        .{ "parseKey", "parseKey", 1 },
        .{ "parseTerminalColorSchemeReport", "parseTerminalColorSchemeReport", 1 },
        .{ "renderFakeCursor", "renderFakeCursor", 1 },
        .{ "renderImage", "renderImage", 2 },
        .{ "renderLatex", "renderLatex", 1 },
        .{ "resetCapabilitiesCache", "resetCapabilitiesCache", 0 },
        .{ "rgbColor", "rgbColor", 3 },
        .{ "setCapabilities", "setCapabilities", 1 },
        .{ "setCapabilityOverrides", "setCapabilityOverrides", 1 },
        .{ "setCellDimensions", "setCellDimensions", 1 },
        .{ "setImageTranscoder", "setImageTranscoder", 1 },
        .{ "setKeybindings", "setKeybindings", 1 },
        .{ "setKittyProtocolActive", "setKittyProtocolActive", 1 },
        .{ "sliceByColumn", "sliceByColumn", 3 },
        .{ "stripTerminalSequences", "stripTerminalSequences", 1 },
        .{ "styleText", "styleText", 3 },
        .{ "styleTextWithAnsi", "styleTextWithAnsi", 4 },
        .{ "truncateToWidth", "truncateToWidth", 2 },
        .{ "visibleWidth", "visibleWidth", 1 },
        .{ "wrapTextWithAnsi", "wrapTextWithAnsi", 2 },
    }) |entry| {
        const value = try js.get(engine, exports, entry[0]);
        defer engine.freeValue(value);
        // Clipboard is implemented by a separate native platform packet.
        const clipboard = comptime @import("std").mem.eql(u8, entry[0], "getNativeClipboard");
        if (!(clipboard and c.JS_IsUndefined(value))) {
            if (!c.JS_IsFunction(engine.context, value)) return error.NativeTuiOrdinaryFunctionMissing;
            try js.define(engine, exports, entry[0], try @import("native_node_function.zig").create(engine, entry[1], entry[2], original, &.{value}));
        }
    }
}
