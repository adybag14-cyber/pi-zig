//! Exact ASCII protocol grammar from Source8a9's anchored terminal reply regex.
//! Payload remains opaque; only a complete recognized header suppresses timeout.
pub fn isControlString(comptime Unit: type, data: []const Unit) bool {
    return data.len >= 2 and data[0] == 0x1b and (data[1] == ']' or data[1] == 'P' or data[1] == '_');
}
fn starts(comptime Unit: type, data: []const Unit, prefix: []const u8) bool {
    if (data.len < prefix.len) return false;
    for (prefix, 0..) |byte, index| if (data[index] != byte) return false;
    return true;
}
pub fn recognized(comptime Unit: type, data: []const Unit) bool {
    if (starts(Unit, data, "\x1b]10;") or starts(Unit, data, "\x1b]11;") or starts(Unit, data, "\x1b]7501;?") or starts(Unit, data, "\x1bP>|")) return true;
    if (starts(Unit, data, "\x1b]4;")) {
        var index: usize = 4;
        const begin = index;
        while (index < data.len and data[index] >= '0' and data[index] <= '9') : (index += 1) {}
        return index > begin and index - begin <= 3 and index < data.len and data[index] == ';';
    }
    if (!starts(Unit, data, "\x1b_G")) return false;
    var index: usize = 3;
    while (index < data.len) {
        if (data[index] < 'a' or data[index] > 'z') return false;
        index += 1;
        if (index == data.len or data[index] != '=') return false;
        index += 1;
        const begin = index;
        while (index < data.len and data[index] >= '0' and data[index] <= '9') : (index += 1) {}
        if (index == begin or index == data.len) return false;
        if (data[index] == ';') return true;
        if (data[index] != ',') return false;
        index += 1;
    }
    return false;
}
