//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_legacy_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "guard/guard.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "guard/guard.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "guard/guard.mjs", bindings);
    const v1767 = try s.own(try ordinary.create(e, "IsArray", 1, body1759, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1719", v1767);
    const v1776 = try s.own(try ordinary.create(e, "IsBigInt", 1, body1768, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1720", v1776);
    const v1785 = try s.own(try ordinary.create(e, "IsBoolean", 1, body1777, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1721", v1785);
    const v1824 = try s.own(try ordinary.create(e, "IsConstructor", 1, body1786, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1722", v1824);
    const v1833 = try s.own(try ordinary.create(e, "IsFunction", 1, body1825, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1723", v1833);
    const v1842 = try s.own(try ordinary.create(e, "IsInteger", 1, body1834, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1724", v1842);
    const v1849 = try s.own(try ordinary.create(e, "IsNull", 1, body1843, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1725", v1849);
    const v1858 = try s.own(try ordinary.create(e, "IsNumber", 1, body1850, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1726", v1858);
    const v1870 = try s.own(try ordinary.create(e, "IsObjectNotArray", 1, body1859, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1727", v1870);
    const v1884 = try s.own(try ordinary.create(e, "IsObject", 1, body1871, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1728", v1884);
    const v1893 = try s.own(try ordinary.create(e, "IsString", 1, body1885, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1729", v1893);
    const v1902 = try s.own(try ordinary.create(e, "IsSymbol", 1, body1894, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1730", v1902);
    const v1909 = try s.own(try ordinary.create(e, "IsUndefined", 1, body1903, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1731", v1909);
    const v1917 = try s.own(try ordinary.create(e, "IsEqual", 2, body1910, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1732", v1917);
    const v1926 = try s.own(try ordinary.create(e, "IsGreaterThan", 2, body1918, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1733", v1926);
    const v1935 = try s.own(try ordinary.create(e, "IsLessThan", 2, body1927, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1734", v1935);
    const v1944 = try s.own(try ordinary.create(e, "IsLessEqualThan", 2, body1936, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1735", v1944);
    const v1953 = try s.own(try ordinary.create(e, "IsGreaterEqualThan", 2, body1945, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1736", v1953);
    const v2020 = try s.own(try ordinary.create(e, "IsMultipleOf", 2, body1954, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1737", v2020);
    const v2066 = try s.own(try ordinary.create(e, "IsClassInstance", 1, body2021, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1738", v2066);
    const v2098 = try s.own(try ordinary.create(e, "IsValueLike", 1, body2067, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1739", v2098);
    const v2107 = try s.own(try ordinary.create(e, "GraphemeCount", 1, body2099, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1740", v2107);
    const v2119 = try s.own(try ordinary.create(e, "IsMaxLength", 2, body2108, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1741", v2119);
    const v2131 = try s.own(try ordinary.create(e, "IsMinLength", 2, body2120, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1742", v2131);
    const v2159 = try s.own(try ordinary.create(e, "Every", 3, body2132, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1743", v2159);
    const v2190 = try s.own(try ordinary.create(e, "EveryAll", 3, body2160, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1744", v2190);
    const v2211 = try s.own(try ordinary.create(e, "Some", 2, body2191, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1745", v2211);
    const v2235 = try s.own(try ordinary.create(e, "SomeAll", 2, body2212, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1746", v2235);
    const v2263 = try s.own(try ordinary.create(e, "Counted", 2, body2236, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1747", v2263);
    const v2289 = try s.own(try ordinary.create(e, "ShiftLeft", 3, body2264, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1748", v2289);
    const v2309 = try s.own(try ordinary.create(e, "IsUnsafePropertyKey", 1, body2290, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1749", v2309);
    const v2333 = try s.own(try ordinary.create(e, "HasPropertyKey", 2, body2310, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1750", v2333);
    const v2361 = try s.own(try ordinary.create(e, "EntriesRegExp", 1, body2334, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1751", v2361);
    const v2370 = try s.own(try ordinary.create(e, "Entries", 1, body2362, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1752", v2370);
    const v2379 = try s.own(try ordinary.create(e, "Keys", 1, body2371, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1753", v2379);
    const v2388 = try s.own(try ordinary.create(e, "Symbols", 1, body2380, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1754", v2388);
    const v2397 = try s.own(try ordinary.create(e, "Values", 1, body2389, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1755", v2397);
    const v2442 = try s.own(try ordinary.create(e, "DeepEqualObject", 2, body2398, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1756", v2442);
    const v2484 = try s.own(try ordinary.create(e, "DeepEqualArray", 2, body2443, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1757", v2484);
    const v2512 = try s.own(try ordinary.create(e, "IsDeepEqual", 2, body2485, &.{ graph, frame }));
    try o.assign(&s, frame, "binding1758", v2512);
    const v2513 = try o.lookup(&s, frame, "binding1719");
    try s.put(namespace, "IsArray", v2513);
    const v2514 = try o.lookup(&s, frame, "binding1720");
    try s.put(namespace, "IsBigInt", v2514);
    const v2515 = try o.lookup(&s, frame, "binding1721");
    try s.put(namespace, "IsBoolean", v2515);
    const v2516 = try o.lookup(&s, frame, "binding1722");
    try s.put(namespace, "IsConstructor", v2516);
    const v2517 = try o.lookup(&s, frame, "binding1723");
    try s.put(namespace, "IsFunction", v2517);
    const v2518 = try o.lookup(&s, frame, "binding1724");
    try s.put(namespace, "IsInteger", v2518);
    const v2519 = try o.lookup(&s, frame, "binding1725");
    try s.put(namespace, "IsNull", v2519);
    const v2520 = try o.lookup(&s, frame, "binding1726");
    try s.put(namespace, "IsNumber", v2520);
    const v2521 = try o.lookup(&s, frame, "binding1727");
    try s.put(namespace, "IsObjectNotArray", v2521);
    const v2522 = try o.lookup(&s, frame, "binding1728");
    try s.put(namespace, "IsObject", v2522);
    const v2523 = try o.lookup(&s, frame, "binding1729");
    try s.put(namespace, "IsString", v2523);
    const v2524 = try o.lookup(&s, frame, "binding1730");
    try s.put(namespace, "IsSymbol", v2524);
    const v2525 = try o.lookup(&s, frame, "binding1731");
    try s.put(namespace, "IsUndefined", v2525);
    const v2526 = try o.lookup(&s, frame, "binding1732");
    try s.put(namespace, "IsEqual", v2526);
    const v2527 = try o.lookup(&s, frame, "binding1733");
    try s.put(namespace, "IsGreaterThan", v2527);
    const v2528 = try o.lookup(&s, frame, "binding1734");
    try s.put(namespace, "IsLessThan", v2528);
    const v2529 = try o.lookup(&s, frame, "binding1735");
    try s.put(namespace, "IsLessEqualThan", v2529);
    const v2530 = try o.lookup(&s, frame, "binding1736");
    try s.put(namespace, "IsGreaterEqualThan", v2530);
    const v2531 = try o.lookup(&s, frame, "binding1737");
    try s.put(namespace, "IsMultipleOf", v2531);
    const v2532 = try o.lookup(&s, frame, "binding1738");
    try s.put(namespace, "IsClassInstance", v2532);
    const v2533 = try o.lookup(&s, frame, "binding1739");
    try s.put(namespace, "IsValueLike", v2533);
    const v2534 = try o.lookup(&s, frame, "binding1740");
    try s.put(namespace, "GraphemeCount", v2534);
    const v2535 = try o.lookup(&s, frame, "binding1741");
    try s.put(namespace, "IsMaxLength", v2535);
    const v2536 = try o.lookup(&s, frame, "binding1742");
    try s.put(namespace, "IsMinLength", v2536);
    const v2537 = try o.lookup(&s, frame, "binding1743");
    try s.put(namespace, "Every", v2537);
    const v2538 = try o.lookup(&s, frame, "binding1744");
    try s.put(namespace, "EveryAll", v2538);
    const v2539 = try o.lookup(&s, frame, "binding1745");
    try s.put(namespace, "Some", v2539);
    const v2540 = try o.lookup(&s, frame, "binding1746");
    try s.put(namespace, "SomeAll", v2540);
    const v2541 = try o.lookup(&s, frame, "binding1747");
    try s.put(namespace, "Counted", v2541);
    const v2542 = try o.lookup(&s, frame, "binding1748");
    try s.put(namespace, "ShiftLeft", v2542);
    const v2543 = try o.lookup(&s, frame, "binding1749");
    try s.put(namespace, "IsUnsafePropertyKey", v2543);
    const v2544 = try o.lookup(&s, frame, "binding1750");
    try s.put(namespace, "HasPropertyKey", v2544);
    const v2545 = try o.lookup(&s, frame, "binding1751");
    try s.put(namespace, "EntriesRegExp", v2545);
    const v2546 = try o.lookup(&s, frame, "binding1752");
    try s.put(namespace, "Entries", v2546);
    const v2547 = try o.lookup(&s, frame, "binding1753");
    try s.put(namespace, "Keys", v2547);
    const v2548 = try o.lookup(&s, frame, "binding1754");
    try s.put(namespace, "Symbols", v2548);
    const v2549 = try o.lookup(&s, frame, "binding1755");
    try s.put(namespace, "Values", v2549);
    const v2550 = try o.lookup(&s, frame, "binding1758");
    try s.put(namespace, "IsDeepEqual", v2550);
    const v2551 = try o.lookup(&s, frame, "binding1719");
    try s.put(namespace, "IsArray", v2551);
    const v2552 = try o.lookup(&s, frame, "binding1720");
    try s.put(namespace, "IsBigInt", v2552);
    const v2553 = try o.lookup(&s, frame, "binding1721");
    try s.put(namespace, "IsBoolean", v2553);
    const v2554 = try o.lookup(&s, frame, "binding1722");
    try s.put(namespace, "IsConstructor", v2554);
    const v2555 = try o.lookup(&s, frame, "binding1723");
    try s.put(namespace, "IsFunction", v2555);
    const v2556 = try o.lookup(&s, frame, "binding1724");
    try s.put(namespace, "IsInteger", v2556);
    const v2557 = try o.lookup(&s, frame, "binding1725");
    try s.put(namespace, "IsNull", v2557);
    const v2558 = try o.lookup(&s, frame, "binding1726");
    try s.put(namespace, "IsNumber", v2558);
    const v2559 = try o.lookup(&s, frame, "binding1727");
    try s.put(namespace, "IsObjectNotArray", v2559);
    const v2560 = try o.lookup(&s, frame, "binding1728");
    try s.put(namespace, "IsObject", v2560);
    const v2561 = try o.lookup(&s, frame, "binding1729");
    try s.put(namespace, "IsString", v2561);
    const v2562 = try o.lookup(&s, frame, "binding1730");
    try s.put(namespace, "IsSymbol", v2562);
    const v2563 = try o.lookup(&s, frame, "binding1731");
    try s.put(namespace, "IsUndefined", v2563);
    const v2564 = try o.lookup(&s, frame, "binding1732");
    try s.put(namespace, "IsEqual", v2564);
    const v2565 = try o.lookup(&s, frame, "binding1733");
    try s.put(namespace, "IsGreaterThan", v2565);
    const v2566 = try o.lookup(&s, frame, "binding1734");
    try s.put(namespace, "IsLessThan", v2566);
    const v2567 = try o.lookup(&s, frame, "binding1735");
    try s.put(namespace, "IsLessEqualThan", v2567);
    const v2568 = try o.lookup(&s, frame, "binding1736");
    try s.put(namespace, "IsGreaterEqualThan", v2568);
    const v2569 = try o.lookup(&s, frame, "binding1737");
    try s.put(namespace, "IsMultipleOf", v2569);
    const v2570 = try o.lookup(&s, frame, "binding1738");
    try s.put(namespace, "IsClassInstance", v2570);
    const v2571 = try o.lookup(&s, frame, "binding1739");
    try s.put(namespace, "IsValueLike", v2571);
    const v2572 = try o.lookup(&s, frame, "binding1740");
    try s.put(namespace, "GraphemeCount", v2572);
    const v2573 = try o.lookup(&s, frame, "binding1741");
    try s.put(namespace, "IsMaxLength", v2573);
    const v2574 = try o.lookup(&s, frame, "binding1742");
    try s.put(namespace, "IsMinLength", v2574);
    const v2575 = try o.lookup(&s, frame, "binding1743");
    try s.put(namespace, "Every", v2575);
    const v2576 = try o.lookup(&s, frame, "binding1744");
    try s.put(namespace, "EveryAll", v2576);
    const v2577 = try o.lookup(&s, frame, "binding1745");
    try s.put(namespace, "Some", v2577);
    const v2578 = try o.lookup(&s, frame, "binding1746");
    try s.put(namespace, "SomeAll", v2578);
    const v2579 = try o.lookup(&s, frame, "binding1747");
    try s.put(namespace, "Counted", v2579);
    const v2580 = try o.lookup(&s, frame, "binding1748");
    try s.put(namespace, "ShiftLeft", v2580);
    const v2581 = try o.lookup(&s, frame, "binding1749");
    try s.put(namespace, "IsUnsafePropertyKey", v2581);
    const v2582 = try o.lookup(&s, frame, "binding1750");
    try s.put(namespace, "HasPropertyKey", v2582);
    const v2583 = try o.lookup(&s, frame, "binding1751");
    try s.put(namespace, "EntriesRegExp", v2583);
    const v2584 = try o.lookup(&s, frame, "binding1752");
    try s.put(namespace, "Entries", v2584);
    const v2585 = try o.lookup(&s, frame, "binding1753");
    try s.put(namespace, "Keys", v2585);
    const v2586 = try o.lookup(&s, frame, "binding1754");
    try s.put(namespace, "Symbols", v2586);
    const v2587 = try o.lookup(&s, frame, "binding1755");
    try s.put(namespace, "Values", v2587);
    const v2588 = try o.lookup(&s, frame, "binding1758");
    try s.put(namespace, "IsDeepEqual", v2588);
    try s.put(bindings, "IsArray", try s.text("binding1719"));
    try s.put(bindings, "IsBigInt", try s.text("binding1720"));
    try s.put(bindings, "IsBoolean", try s.text("binding1721"));
    try s.put(bindings, "IsConstructor", try s.text("binding1722"));
    try s.put(bindings, "IsFunction", try s.text("binding1723"));
    try s.put(bindings, "IsInteger", try s.text("binding1724"));
    try s.put(bindings, "IsNull", try s.text("binding1725"));
    try s.put(bindings, "IsNumber", try s.text("binding1726"));
    try s.put(bindings, "IsObjectNotArray", try s.text("binding1727"));
    try s.put(bindings, "IsObject", try s.text("binding1728"));
    try s.put(bindings, "IsString", try s.text("binding1729"));
    try s.put(bindings, "IsSymbol", try s.text("binding1730"));
    try s.put(bindings, "IsUndefined", try s.text("binding1731"));
    try s.put(bindings, "IsEqual", try s.text("binding1732"));
    try s.put(bindings, "IsGreaterThan", try s.text("binding1733"));
    try s.put(bindings, "IsLessThan", try s.text("binding1734"));
    try s.put(bindings, "IsLessEqualThan", try s.text("binding1735"));
    try s.put(bindings, "IsGreaterEqualThan", try s.text("binding1736"));
    try s.put(bindings, "IsMultipleOf", try s.text("binding1737"));
    try s.put(bindings, "IsClassInstance", try s.text("binding1738"));
    try s.put(bindings, "IsValueLike", try s.text("binding1739"));
    try s.put(bindings, "GraphemeCount", try s.text("binding1740"));
    try s.put(bindings, "IsMaxLength", try s.text("binding1741"));
    try s.put(bindings, "IsMinLength", try s.text("binding1742"));
    try s.put(bindings, "Every", try s.text("binding1743"));
    try s.put(bindings, "EveryAll", try s.text("binding1744"));
    try s.put(bindings, "Some", try s.text("binding1745"));
    try s.put(bindings, "SomeAll", try s.text("binding1746"));
    try s.put(bindings, "Counted", try s.text("binding1747"));
    try s.put(bindings, "ShiftLeft", try s.text("binding1748"));
    try s.put(bindings, "IsUnsafePropertyKey", try s.text("binding1749"));
    try s.put(bindings, "HasPropertyKey", try s.text("binding1750"));
    try s.put(bindings, "EntriesRegExp", try s.text("binding1751"));
    try s.put(bindings, "Entries", try s.text("binding1752"));
    try s.put(bindings, "Keys", try s.text("binding1753"));
    try s.put(bindings, "Symbols", try s.text("binding1754"));
    try s.put(bindings, "Values", try s.text("binding1755"));
    try s.put(bindings, "IsDeepEqual", try s.text("binding1758"));
}
fn body1759(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1761 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1760", v1761);
    const v1762 = try s.global("Array");
    const v1763 = try s.text("isArray");
    const v1764 = try s.own(try js.getKey(e, v1762, v1763));
    const v1765 = try o.lookup(&s, frame, "binding1760");
    const v1766 = try s.call(v1764, v1762, &.{v1765});
    return c.JS_DupValue(e.context, v1766);
}
fn body1768(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1770 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1769", v1770);
    const v1771 = try s.global("IsEqual");
    const v1772 = try o.lookup(&s, frame, "binding1769");
    const v1773 = try o.typeOf(&s, v1772);
    const v1774 = try s.text("bigint");
    const v1775 = try s.call(v1771, c.pi_js_undefined(), &.{ v1773, v1774 });
    return c.JS_DupValue(e.context, v1775);
}
fn body1777(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1779 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1778", v1779);
    const v1780 = try s.global("IsEqual");
    const v1781 = try o.lookup(&s, frame, "binding1778");
    const v1782 = try o.typeOf(&s, v1781);
    const v1783 = try s.text("boolean");
    const v1784 = try s.call(v1780, c.pi_js_undefined(), &.{ v1782, v1783 });
    return c.JS_DupValue(e.context, v1784);
}
fn body1786(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1789 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1787", v1789);
    const v1791 = try s.global("IsUndefined");
    const v1792 = try o.lookup(&s, frame, "binding1787");
    const v1793 = try s.call(v1791, c.pi_js_undefined(), &.{v1792});
    const v1795 = logical1794: {
        if (s.truthy(v1793)) break :logical1794 v1793;
        const v1796 = try s.global("IsFunction");
        const v1797 = try o.lookup(&s, frame, "binding1787");
        const v1798 = try s.call(v1796, c.pi_js_undefined(), &.{v1797});
        break :logical1794 o.boolean(&s, !s.truthy(v1798));
    };
    if (s.truthy(v1795)) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v1799 = try s.global("Function");
    const v1800 = try s.text("prototype");
    const v1801 = try s.own(try js.getKey(e, v1799, v1800));
    const v1802 = try s.text("toString");
    const v1803 = try s.own(try js.getKey(e, v1801, v1802));
    const v1804 = try s.text("call");
    const v1805 = try s.own(try js.getKey(e, v1803, v1804));
    const v1806 = try o.lookup(&s, frame, "binding1787");
    const v1807 = try s.call(v1805, v1803, &.{v1806});
    try o.assign(&s, frame, "binding1790", v1807);
    const v1808 = try s.text("^class\\s");
    const v1809 = try s.text("");
    const v1810 = try s.global("RegExp");
    const v1811 = try o.construct(&s, v1810, &.{ v1808, v1809 });
    const v1812 = try s.text("test");
    const v1813 = try s.own(try js.getKey(e, v1811, v1812));
    const v1814 = try o.lookup(&s, frame, "binding1790");
    const v1815 = try s.call(v1813, v1811, &.{v1814});
    if (s.truthy(v1815)) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    const v1816 = try s.text("\\[native code\\]");
    const v1817 = try s.text("");
    const v1818 = try s.global("RegExp");
    const v1819 = try o.construct(&s, v1818, &.{ v1816, v1817 });
    const v1820 = try s.text("test");
    const v1821 = try s.own(try js.getKey(e, v1819, v1820));
    const v1822 = try o.lookup(&s, frame, "binding1790");
    const v1823 = try s.call(v1821, v1819, &.{v1822});
    if (s.truthy(v1823)) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    return c.JS_DupValue(e.context, o.boolean(&s, false));
}
fn body1825(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1827 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1826", v1827);
    const v1828 = try s.global("IsEqual");
    const v1829 = try o.lookup(&s, frame, "binding1826");
    const v1830 = try o.typeOf(&s, v1829);
    const v1831 = try s.text("function");
    const v1832 = try s.call(v1828, c.pi_js_undefined(), &.{ v1830, v1831 });
    return c.JS_DupValue(e.context, v1832);
}
fn body1834(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1836 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1835", v1836);
    const v1837 = try s.global("Number");
    const v1838 = try s.text("isInteger");
    const v1839 = try s.own(try js.getKey(e, v1837, v1838));
    const v1840 = try o.lookup(&s, frame, "binding1835");
    const v1841 = try s.call(v1839, v1837, &.{v1840});
    return c.JS_DupValue(e.context, v1841);
}
fn body1843(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1845 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1844", v1845);
    const v1846 = try s.global("IsEqual");
    const v1847 = try o.lookup(&s, frame, "binding1844");
    const v1848 = try s.call(v1846, c.pi_js_undefined(), &.{ v1847, c.pi_js_null() });
    return c.JS_DupValue(e.context, v1848);
}
fn body1850(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1852 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1851", v1852);
    const v1853 = try s.global("Number");
    const v1854 = try s.text("isFinite");
    const v1855 = try s.own(try js.getKey(e, v1853, v1854));
    const v1856 = try o.lookup(&s, frame, "binding1851");
    const v1857 = try s.call(v1855, v1853, &.{v1856});
    return c.JS_DupValue(e.context, v1857);
}
fn body1859(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1861 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1860", v1861);
    const v1862 = try s.global("IsObject");
    const v1863 = try o.lookup(&s, frame, "binding1860");
    const v1864 = try s.call(v1862, c.pi_js_undefined(), &.{v1863});
    const v1866 = logical1865: {
        if (!s.truthy(v1864)) break :logical1865 v1864;
        const v1867 = try s.global("IsArray");
        const v1868 = try o.lookup(&s, frame, "binding1860");
        const v1869 = try s.call(v1867, c.pi_js_undefined(), &.{v1868});
        break :logical1865 o.boolean(&s, !s.truthy(v1869));
    };
    return c.JS_DupValue(e.context, v1866);
}
fn body1871(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1873 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1872", v1873);
    const v1874 = try s.global("IsEqual");
    const v1875 = try o.lookup(&s, frame, "binding1872");
    const v1876 = try o.typeOf(&s, v1875);
    const v1877 = try s.text("object");
    const v1878 = try s.call(v1874, c.pi_js_undefined(), &.{ v1876, v1877 });
    const v1880 = logical1879: {
        if (!s.truthy(v1878)) break :logical1879 v1878;
        const v1881 = try s.global("IsNull");
        const v1882 = try o.lookup(&s, frame, "binding1872");
        const v1883 = try s.call(v1881, c.pi_js_undefined(), &.{v1882});
        break :logical1879 o.boolean(&s, !s.truthy(v1883));
    };
    return c.JS_DupValue(e.context, v1880);
}
fn body1885(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1887 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1886", v1887);
    const v1888 = try s.global("IsEqual");
    const v1889 = try o.lookup(&s, frame, "binding1886");
    const v1890 = try o.typeOf(&s, v1889);
    const v1891 = try s.text("string");
    const v1892 = try s.call(v1888, c.pi_js_undefined(), &.{ v1890, v1891 });
    return c.JS_DupValue(e.context, v1892);
}
fn body1894(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1896 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1895", v1896);
    const v1897 = try s.global("IsEqual");
    const v1898 = try o.lookup(&s, frame, "binding1895");
    const v1899 = try o.typeOf(&s, v1898);
    const v1900 = try s.text("symbol");
    const v1901 = try s.call(v1897, c.pi_js_undefined(), &.{ v1899, v1900 });
    return c.JS_DupValue(e.context, v1901);
}
fn body1903(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1905 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1904", v1905);
    const v1906 = try s.global("IsEqual");
    const v1907 = try o.lookup(&s, frame, "binding1904");
    const v1908 = try s.call(v1906, c.pi_js_undefined(), &.{ v1907, c.pi_js_undefined() });
    return c.JS_DupValue(e.context, v1908);
}
fn body1910(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1913 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1911", v1913);
    const v1914 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1912", v1914);
    const v1915 = try o.lookup(&s, frame, "binding1911");
    const v1916 = try o.lookup(&s, frame, "binding1912");
    return c.JS_DupValue(e.context, o.boolean(&s, s.equal(v1915, v1916)));
}
fn body1918(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1921 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1919", v1921);
    const v1922 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1920", v1922);
    const v1923 = try o.lookup(&s, frame, "binding1919");
    const v1924 = try o.lookup(&s, frame, "binding1920");
    const v1925 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v1923, v1924)));
    return c.JS_DupValue(e.context, v1925);
}
fn body1927(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1930 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1928", v1930);
    const v1931 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1929", v1931);
    const v1932 = try o.lookup(&s, frame, "binding1928");
    const v1933 = try o.lookup(&s, frame, "binding1929");
    const v1934 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v1932, v1933)));
    return c.JS_DupValue(e.context, v1934);
}
fn body1936(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1939 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1937", v1939);
    const v1940 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1938", v1940);
    const v1941 = try o.lookup(&s, frame, "binding1937");
    const v1942 = try o.lookup(&s, frame, "binding1938");
    const v1943 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 5, v1941, v1942)));
    return c.JS_DupValue(e.context, v1943);
}
fn body1945(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1948 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1946", v1948);
    const v1949 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1947", v1949);
    const v1950 = try o.lookup(&s, frame, "binding1946");
    const v1951 = try o.lookup(&s, frame, "binding1947");
    const v1952 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v1950, v1951)));
    return c.JS_DupValue(e.context, v1952);
}
fn body1954(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v1959 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1955", v1959);
    const v1960 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding1956", v1960);
    const v1963 = try s.global("IsBigInt");
    const v1964 = try o.lookup(&s, frame, "binding1955");
    const v1965 = try s.call(v1963, c.pi_js_undefined(), &.{v1964});
    const v1967 = logical1966: {
        if (s.truthy(v1965)) break :logical1966 v1965;
        const v1968 = try s.global("IsBigInt");
        const v1969 = try o.lookup(&s, frame, "binding1956");
        const v1970 = try s.call(v1968, c.pi_js_undefined(), &.{v1969});
        break :logical1966 v1970;
    };
    if (s.truthy(v1967)) {
        const v1971 = try s.global("BigInt");
        const v1972 = try o.lookup(&s, frame, "binding1955");
        const v1973 = try s.call(v1971, c.pi_js_undefined(), &.{v1972});
        const v1974 = try s.global("BigInt");
        const v1975 = try o.lookup(&s, frame, "binding1956");
        const v1976 = try s.call(v1974, c.pi_js_undefined(), &.{v1975});
        const v1977 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 8, v1973, v1976)));
        const v1978 = try s.global("BigInt");
        const v1979 = try s.text("0");
        const v1980 = try s.call(v1978, c.pi_js_undefined(), &.{v1979});
        return c.JS_DupValue(e.context, o.boolean(&s, s.equal(v1977, v1980)));
    }
    try o.assign(&s, frame, "binding1961", c.JS_NewFloat64(e.context, 1E-10));
    const v1981 = try s.global("IsNumber");
    const v1982 = try o.lookup(&s, frame, "binding1955");
    const v1983 = try s.call(v1981, c.pi_js_undefined(), &.{v1982});
    if (s.truthy(o.boolean(&s, !s.truthy(v1983)))) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    const v1984 = try s.global("IsInteger");
    const v1985 = try o.lookup(&s, frame, "binding1955");
    const v1986 = try s.call(v1984, c.pi_js_undefined(), &.{v1985});
    const v1988 = logical1987: {
        if (!s.truthy(v1986)) break :logical1987 v1986;
        const v1989 = try o.lookup(&s, frame, "binding1956");
        const v1990 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 3, c.JS_NewFloat64(e.context, 1), v1989)));
        const v1991 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 8, v1990, c.JS_NewFloat64(e.context, 1))));
        break :logical1987 o.boolean(&s, s.equal(v1991, c.JS_NewFloat64(e.context, 0)));
    };
    if (s.truthy(v1988)) {
        return c.JS_DupValue(e.context, o.boolean(&s, true));
    }
    const v1992 = try o.lookup(&s, frame, "binding1955");
    const v1993 = try o.lookup(&s, frame, "binding1956");
    const v1994 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 8, v1992, v1993)));
    try o.assign(&s, frame, "binding1962", v1994);
    const v1995 = try s.global("Math");
    const v1996 = try s.text("min");
    const v1997 = try s.own(try js.getKey(e, v1995, v1996));
    const v1998 = try s.global("Math");
    const v1999 = try s.text("abs");
    const v2000 = try s.own(try js.getKey(e, v1998, v1999));
    const v2001 = try o.lookup(&s, frame, "binding1962");
    const v2002 = try s.call(v2000, v1998, &.{v2001});
    const v2003 = try s.global("Math");
    const v2004 = try s.text("abs");
    const v2005 = try s.own(try js.getKey(e, v2003, v2004));
    const v2006 = try o.lookup(&s, frame, "binding1962");
    const v2007 = try o.lookup(&s, frame, "binding1956");
    const v2008 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v2006, v2007)));
    const v2009 = try s.call(v2005, v2003, &.{v2008});
    const v2010 = try s.global("Math");
    const v2011 = try s.text("abs");
    const v2012 = try s.own(try js.getKey(e, v2010, v2011));
    const v2013 = try o.lookup(&s, frame, "binding1962");
    const v2014 = try o.lookup(&s, frame, "binding1956");
    const v2015 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v2013, v2014)));
    const v2016 = try s.call(v2012, v2010, &.{v2015});
    const v2017 = try s.call(v1997, v1995, &.{ v2002, v2009, v2016 });
    const v2018 = try o.lookup(&s, frame, "binding1961");
    const v2019 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v2017, v2018)));
    return c.JS_DupValue(e.context, v2019);
}
fn body2021(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2024 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2022", v2024);
    const v2026 = try s.global("IsObject");
    const v2027 = try o.lookup(&s, frame, "binding2022");
    const v2028 = try s.call(v2026, c.pi_js_undefined(), &.{v2027});
    if (s.truthy(o.boolean(&s, !s.truthy(v2028)))) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v2029 = try s.global("globalThis");
    const v2030 = try s.text("Object");
    const v2031 = try s.own(try js.getKey(e, v2029, v2030));
    const v2032 = try s.text("getPrototypeOf");
    const v2033 = try s.own(try js.getKey(e, v2031, v2032));
    const v2034 = try o.lookup(&s, frame, "binding2022");
    const v2035 = try s.call(v2033, v2031, &.{v2034});
    try o.assign(&s, frame, "binding2025", v2035);
    const v2036 = try s.global("IsNull");
    const v2037 = try o.lookup(&s, frame, "binding2025");
    const v2038 = try s.call(v2036, c.pi_js_undefined(), &.{v2037});
    if (s.truthy(v2038)) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v2039 = try s.global("IsEqual");
    const v2040 = try o.lookup(&s, frame, "binding2025");
    const v2041 = try s.text("constructor");
    const v2042 = try s.own(try js.getKey(e, v2040, v2041));
    const v2043 = try o.typeOf(&s, v2042);
    const v2044 = try s.text("function");
    const v2045 = try s.call(v2039, c.pi_js_undefined(), &.{ v2043, v2044 });
    const v2047 = logical2046: {
        if (!s.truthy(v2045)) break :logical2046 v2045;
        const v2048 = try s.global("IsEqual");
        const v2049 = try o.lookup(&s, frame, "binding2025");
        const v2050 = try s.text("constructor");
        const v2051 = try s.own(try js.getKey(e, v2049, v2050));
        const v2052 = try s.global("globalThis");
        const v2053 = try s.text("Object");
        const v2054 = try s.own(try js.getKey(e, v2052, v2053));
        const v2055 = try s.call(v2048, c.pi_js_undefined(), &.{ v2051, v2054 });
        const v2057 = logical2056: {
            if (s.truthy(v2055)) break :logical2056 v2055;
            const v2058 = try s.global("IsEqual");
            const v2059 = try o.lookup(&s, frame, "binding2025");
            const v2060 = try s.text("constructor");
            const v2061 = try s.own(try js.getKey(e, v2059, v2060));
            const v2062 = try s.text("name");
            const v2063 = try s.own(try js.getKey(e, v2061, v2062));
            const v2064 = try s.text("Object");
            const v2065 = try s.call(v2058, c.pi_js_undefined(), &.{ v2063, v2064 });
            break :logical2056 v2065;
        };
        break :logical2046 o.boolean(&s, !s.truthy(v2057));
    };
    return c.JS_DupValue(e.context, v2047);
}
fn body2067(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2069 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2068", v2069);
    const v2070 = try s.global("IsBigInt");
    const v2071 = try o.lookup(&s, frame, "binding2068");
    const v2072 = try s.call(v2070, c.pi_js_undefined(), &.{v2071});
    const v2074 = logical2073: {
        if (s.truthy(v2072)) break :logical2073 v2072;
        const v2075 = try s.global("IsBoolean");
        const v2076 = try o.lookup(&s, frame, "binding2068");
        const v2077 = try s.call(v2075, c.pi_js_undefined(), &.{v2076});
        break :logical2073 v2077;
    };
    const v2079 = logical2078: {
        if (s.truthy(v2074)) break :logical2078 v2074;
        const v2080 = try s.global("IsNull");
        const v2081 = try o.lookup(&s, frame, "binding2068");
        const v2082 = try s.call(v2080, c.pi_js_undefined(), &.{v2081});
        break :logical2078 v2082;
    };
    const v2084 = logical2083: {
        if (s.truthy(v2079)) break :logical2083 v2079;
        const v2085 = try s.global("IsNumber");
        const v2086 = try o.lookup(&s, frame, "binding2068");
        const v2087 = try s.call(v2085, c.pi_js_undefined(), &.{v2086});
        break :logical2083 v2087;
    };
    const v2089 = logical2088: {
        if (s.truthy(v2084)) break :logical2088 v2084;
        const v2090 = try s.global("IsString");
        const v2091 = try o.lookup(&s, frame, "binding2068");
        const v2092 = try s.call(v2090, c.pi_js_undefined(), &.{v2091});
        break :logical2088 v2092;
    };
    const v2094 = logical2093: {
        if (s.truthy(v2089)) break :logical2093 v2089;
        const v2095 = try s.global("IsUndefined");
        const v2096 = try o.lookup(&s, frame, "binding2068");
        const v2097 = try s.call(v2095, c.pi_js_undefined(), &.{v2096});
        break :logical2093 v2097;
    };
    return c.JS_DupValue(e.context, v2094);
}
fn body2099(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2101 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2100", v2101);
    const v2102 = try o.importValue(&s, graph, "guard/string.mjs", "*");
    const v2103 = try s.text("GraphemeCount");
    const v2104 = try s.own(try js.getKey(e, v2102, v2103));
    const v2105 = try o.lookup(&s, frame, "binding2100");
    const v2106 = try s.call(v2104, v2102, &.{v2105});
    return c.JS_DupValue(e.context, v2106);
}
fn body2108(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2111 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2109", v2111);
    const v2112 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2110", v2112);
    const v2113 = try o.importValue(&s, graph, "guard/string.mjs", "*");
    const v2114 = try s.text("IsMaxLength");
    const v2115 = try s.own(try js.getKey(e, v2113, v2114));
    const v2116 = try o.lookup(&s, frame, "binding2109");
    const v2117 = try o.lookup(&s, frame, "binding2110");
    const v2118 = try s.call(v2115, v2113, &.{ v2116, v2117 });
    return c.JS_DupValue(e.context, v2118);
}
fn body2120(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2123 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2121", v2123);
    const v2124 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2122", v2124);
    const v2125 = try o.importValue(&s, graph, "guard/string.mjs", "*");
    const v2126 = try s.text("IsMinLength");
    const v2127 = try s.own(try js.getKey(e, v2125, v2126));
    const v2128 = try o.lookup(&s, frame, "binding2121");
    const v2129 = try o.lookup(&s, frame, "binding2122");
    const v2130 = try s.call(v2127, v2125, &.{ v2128, v2129 });
    return c.JS_DupValue(e.context, v2130);
}
fn body2142(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2146 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2144", v2146);
    const v2147 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2145", v2147);
    const v2148 = try o.lookup(&s, frame, "binding2145");
    const v2149 = try o.lookup(&s, frame, "binding2134");
    const v2150 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v2148, v2149)));
    const v2152 = logical2151: {
        if (s.truthy(v2150)) break :logical2151 v2150;
        const v2153 = try o.lookup(&s, frame, "binding2135");
        const v2154 = try o.lookup(&s, frame, "binding2144");
        const v2155 = try o.lookup(&s, frame, "binding2145");
        const v2156 = try s.call(v2153, c.pi_js_undefined(), &.{ v2154, v2155 });
        break :logical2151 v2156;
    };
    return c.JS_DupValue(e.context, v2152);
}
fn body2142C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2142(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2132(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2136 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2133", v2136);
    const v2137 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2134", v2137);
    const v2138 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2135", v2138);
    const v2139 = try o.lookup(&s, frame, "binding2133");
    const v2140 = try s.text("every");
    const v2141 = try s.own(try js.getKey(e, v2139, v2140));
    const v2157 = try o.arrow(&s, "", 2, body2142C, &.{ graph, frame });
    const v2158 = try s.call(v2141, v2139, &.{v2157});
    return c.JS_DupValue(e.context, v2158);
}
fn body2172(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2176 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2174", v2176);
    const v2177 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2175", v2177);
    const v2178 = try o.lookup(&s, frame, "binding2175");
    const v2179 = try o.lookup(&s, frame, "binding2162");
    const v2180 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 7, v2178, v2179)));
    const v2182 = logical2181: {
        if (!s.truthy(v2180)) break :logical2181 v2180;
        const v2183 = try o.lookup(&s, frame, "binding2163");
        const v2184 = try o.lookup(&s, frame, "binding2174");
        const v2185 = try o.lookup(&s, frame, "binding2175");
        const v2186 = try s.call(v2183, c.pi_js_undefined(), &.{ v2184, v2185 });
        break :logical2181 o.boolean(&s, !s.truthy(v2186));
    };
    if (s.truthy(v2182)) {
        try o.assign(&s, frame, "binding2168", o.boolean(&s, false));
        _ = o.boolean(&s, false);
    }
    return c.pi_js_undefined();
}
fn body2172C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2172(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2160(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2165 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2161", v2165);
    const v2166 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2162", v2166);
    const v2167 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2163", v2167);
    try o.assign(&s, frame, "binding2168", o.boolean(&s, true));
    const v2169 = try o.lookup(&s, frame, "binding2161");
    const v2170 = try s.text("forEach");
    const v2171 = try s.own(try js.getKey(e, v2169, v2170));
    const v2187 = try o.arrow(&s, "", 2, body2172C, &.{ graph, frame });
    const v2188 = try s.call(v2171, v2169, &.{v2187});
    _ = v2188;
    const v2189 = try o.lookup(&s, frame, "binding2168");
    return c.JS_DupValue(e.context, v2189);
}
fn body2199(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2203 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2201", v2203);
    const v2204 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2202", v2204);
    const v2205 = try o.lookup(&s, frame, "binding2193");
    const v2206 = try o.lookup(&s, frame, "binding2201");
    const v2207 = try o.lookup(&s, frame, "binding2202");
    const v2208 = try s.call(v2205, c.pi_js_undefined(), &.{ v2206, v2207 });
    return c.JS_DupValue(e.context, v2208);
}
fn body2199C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2199(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2191(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2194 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2192", v2194);
    const v2195 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2193", v2195);
    const v2196 = try o.lookup(&s, frame, "binding2192");
    const v2197 = try s.text("some");
    const v2198 = try s.own(try js.getKey(e, v2196, v2197));
    const v2209 = try o.arrow(&s, "", 2, body2199C, &.{ graph, frame });
    const v2210 = try s.call(v2198, v2196, &.{v2209});
    return c.JS_DupValue(e.context, v2210);
}
fn body2222(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2226 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2224", v2226);
    const v2227 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2225", v2227);
    const v2228 = try o.lookup(&s, frame, "binding2214");
    const v2229 = try o.lookup(&s, frame, "binding2224");
    const v2230 = try o.lookup(&s, frame, "binding2225");
    const v2231 = try s.call(v2228, c.pi_js_undefined(), &.{ v2229, v2230 });
    if (s.truthy(v2231)) {
        try o.assign(&s, frame, "binding2218", o.boolean(&s, true));
        _ = o.boolean(&s, true);
    }
    return c.pi_js_undefined();
}
fn body2222C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2222(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2212(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2216 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2213", v2216);
    const v2217 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2214", v2217);
    try o.assign(&s, frame, "binding2218", o.boolean(&s, false));
    const v2219 = try o.lookup(&s, frame, "binding2213");
    const v2220 = try s.text("forEach");
    const v2221 = try s.own(try js.getKey(e, v2219, v2220));
    const v2232 = try o.arrow(&s, "", 2, body2222C, &.{ graph, frame });
    const v2233 = try s.call(v2221, v2219, &.{v2232});
    _ = v2233;
    const v2234 = try o.lookup(&s, frame, "binding2218");
    return c.JS_DupValue(e.context, v2234);
}
fn body2244(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2249 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2246", v2249);
    const v2250 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2247", v2250);
    const v2251 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2248", v2251);
    const v2252 = try o.lookup(&s, frame, "binding2238");
    const v2253 = try o.lookup(&s, frame, "binding2247");
    const v2254 = try o.lookup(&s, frame, "binding2248");
    const v2255 = try s.call(v2252, c.pi_js_undefined(), &.{ v2253, v2254 });
    const v2257 = conditional2256: {
        if (s.truthy(v2255)) {
            const v2258 = try o.lookup(&s, frame, "binding2246");
            const v2259 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v2258)));
            try o.assign(&s, frame, "binding2246", v2259);
            break :conditional2256 v2259;
        } else {
            const v2260 = try o.lookup(&s, frame, "binding2246");
            break :conditional2256 v2260;
        }
    };
    return c.JS_DupValue(e.context, v2257);
}
fn body2244C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2244(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2236(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2239 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2237", v2239);
    const v2240 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2238", v2240);
    const v2241 = try o.lookup(&s, frame, "binding2237");
    const v2242 = try s.text("reduce");
    const v2243 = try s.own(try js.getKey(e, v2241, v2242));
    const v2261 = try o.arrow(&s, "", 3, body2244C, &.{ graph, frame });
    const v2262 = try s.call(v2243, v2241, &.{ v2261, c.JS_NewFloat64(e.context, 0) });
    return c.JS_DupValue(e.context, v2262);
}
fn body2264(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2268 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2265", v2268);
    const v2269 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2266", v2269);
    const v2270 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2267", v2270);
    const v2271 = try s.global("IsEqual");
    const v2272 = try o.lookup(&s, frame, "binding2265");
    const v2273 = try s.text("length");
    const v2274 = try s.own(try js.getKey(e, v2272, v2273));
    const v2275 = try s.call(v2271, c.pi_js_undefined(), &.{ v2274, c.JS_NewFloat64(e.context, 0) });
    const v2277 = conditional2276: {
        if (s.truthy(v2275)) {
            const v2278 = try o.lookup(&s, frame, "binding2267");
            const v2279 = try s.call(v2278, c.pi_js_undefined(), &.{});
            break :conditional2276 v2279;
        } else {
            const v2280 = try o.lookup(&s, frame, "binding2266");
            const v2281 = try o.lookup(&s, frame, "binding2265");
            const v2282 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
            const v2283 = try s.own(try js.getKey(e, v2281, v2282));
            const v2284 = try o.lookup(&s, frame, "binding2265");
            const v2285 = try s.text("slice");
            const v2286 = try s.own(try js.getKey(e, v2284, v2285));
            const v2287 = try s.call(v2286, v2284, &.{c.JS_NewFloat64(e.context, 1)});
            const v2288 = try s.call(v2280, c.pi_js_undefined(), &.{ v2283, v2287 });
            break :conditional2276 v2288;
        }
    };
    return c.JS_DupValue(e.context, v2277);
}
fn body2290(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2292 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2291", v2292);
    const v2293 = try s.global("IsEqual");
    const v2294 = try o.lookup(&s, frame, "binding2291");
    const v2295 = try s.text("__proto__");
    const v2296 = try s.call(v2293, c.pi_js_undefined(), &.{ v2294, v2295 });
    const v2298 = logical2297: {
        if (s.truthy(v2296)) break :logical2297 v2296;
        const v2299 = try s.global("IsEqual");
        const v2300 = try o.lookup(&s, frame, "binding2291");
        const v2301 = try s.text("constructor");
        const v2302 = try s.call(v2299, c.pi_js_undefined(), &.{ v2300, v2301 });
        break :logical2297 v2302;
    };
    const v2304 = logical2303: {
        if (s.truthy(v2298)) break :logical2303 v2298;
        const v2305 = try s.global("IsEqual");
        const v2306 = try o.lookup(&s, frame, "binding2291");
        const v2307 = try s.text("prototype");
        const v2308 = try s.call(v2305, c.pi_js_undefined(), &.{ v2306, v2307 });
        break :logical2303 v2308;
    };
    return c.JS_DupValue(e.context, v2304);
}
fn body2310(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2313 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2311", v2313);
    const v2314 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2312", v2314);
    const v2315 = try s.global("IsUnsafePropertyKey");
    const v2316 = try o.lookup(&s, frame, "binding2312");
    const v2317 = try s.call(v2315, c.pi_js_undefined(), &.{v2316});
    const v2319 = conditional2318: {
        if (s.truthy(v2317)) {
            const v2320 = try s.global("Object");
            const v2321 = try s.text("prototype");
            const v2322 = try s.own(try js.getKey(e, v2320, v2321));
            const v2323 = try s.text("hasOwnProperty");
            const v2324 = try s.own(try js.getKey(e, v2322, v2323));
            const v2325 = try s.text("call");
            const v2326 = try s.own(try js.getKey(e, v2324, v2325));
            const v2327 = try o.lookup(&s, frame, "binding2311");
            const v2328 = try o.lookup(&s, frame, "binding2312");
            const v2329 = try s.call(v2326, v2324, &.{ v2327, v2328 });
            break :conditional2318 v2329;
        } else {
            const v2330 = try o.lookup(&s, frame, "binding2312");
            const v2331 = try o.lookup(&s, frame, "binding2311");
            const v2332 = o.boolean(&s, try js.hasKey(e, v2331, v2330));
            break :conditional2318 v2332;
        }
    };
    return c.JS_DupValue(e.context, v2319);
}
fn body2342(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2345 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2344", v2345);
    const v2346 = try s.array();
    const v2347 = try s.global("RegExp");
    const v2348 = try s.text("^");
    const v2349 = try o.lookup(&s, frame, "binding2344");
    const v2350 = try s.stringify(v2349);
    const v2351 = try s.concat(v2348, v2350);
    const v2352 = try s.text("$");
    const v2353 = try s.concat(v2351, v2352);
    const v2354 = try o.construct(&s, v2347, &.{v2353});
    try o.append(&s, v2346, v2354);
    const v2355 = try o.lookup(&s, frame, "binding2335");
    const v2356 = try o.lookup(&s, frame, "binding2344");
    const v2357 = try o.propertyKey(&s, v2356);
    const v2358 = try s.own(try js.getKey(e, v2355, v2357));
    try o.append(&s, v2346, v2358);
    return c.JS_DupValue(e.context, v2346);
}
fn body2342C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2342(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2334(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2336 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2335", v2336);
    const v2337 = try s.global("Keys");
    const v2338 = try o.lookup(&s, frame, "binding2335");
    const v2339 = try s.call(v2337, c.pi_js_undefined(), &.{v2338});
    const v2340 = try s.text("map");
    const v2341 = try s.own(try js.getKey(e, v2339, v2340));
    const v2359 = try o.arrow(&s, "", 1, body2342C, &.{ graph, frame });
    const v2360 = try s.call(v2341, v2339, &.{v2359});
    return c.JS_DupValue(e.context, v2360);
}
fn body2362(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2364 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2363", v2364);
    const v2365 = try s.global("Object");
    const v2366 = try s.text("entries");
    const v2367 = try s.own(try js.getKey(e, v2365, v2366));
    const v2368 = try o.lookup(&s, frame, "binding2363");
    const v2369 = try s.call(v2367, v2365, &.{v2368});
    return c.JS_DupValue(e.context, v2369);
}
fn body2371(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2373 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2372", v2373);
    const v2374 = try s.global("Object");
    const v2375 = try s.text("getOwnPropertyNames");
    const v2376 = try s.own(try js.getKey(e, v2374, v2375));
    const v2377 = try o.lookup(&s, frame, "binding2372");
    const v2378 = try s.call(v2376, v2374, &.{v2377});
    return c.JS_DupValue(e.context, v2378);
}
fn body2380(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2382 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2381", v2382);
    const v2383 = try s.global("Object");
    const v2384 = try s.text("getOwnPropertySymbols");
    const v2385 = try s.own(try js.getKey(e, v2383, v2384));
    const v2386 = try o.lookup(&s, frame, "binding2381");
    const v2387 = try s.call(v2385, v2383, &.{v2386});
    return c.JS_DupValue(e.context, v2387);
}
fn body2389(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2391 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2390", v2391);
    const v2392 = try s.global("Object");
    const v2393 = try s.text("values");
    const v2394 = try s.own(try js.getKey(e, v2392, v2393));
    const v2395 = try o.lookup(&s, frame, "binding2390");
    const v2396 = try s.call(v2394, v2392, &.{v2395});
    return c.JS_DupValue(e.context, v2396);
}
fn body2426(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2429 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2428", v2429);
    const v2430 = try s.global("IsDeepEqual");
    const v2431 = try o.lookup(&s, frame, "binding2399");
    const v2432 = try o.lookup(&s, frame, "binding2428");
    const v2433 = try o.propertyKey(&s, v2432);
    const v2434 = try s.own(try js.getKey(e, v2431, v2433));
    const v2435 = try o.lookup(&s, frame, "binding2400");
    const v2436 = try o.lookup(&s, frame, "binding2428");
    const v2437 = try o.propertyKey(&s, v2436);
    const v2438 = try s.own(try js.getKey(e, v2435, v2437));
    const v2439 = try s.call(v2430, c.pi_js_undefined(), &.{ v2434, v2438 });
    return c.JS_DupValue(e.context, v2439);
}
fn body2426C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2426(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2398(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2402 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2399", v2402);
    const v2403 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2400", v2403);
    const v2405 = try s.global("IsObject");
    const v2406 = try o.lookup(&s, frame, "binding2400");
    const v2407 = try s.call(v2405, c.pi_js_undefined(), &.{v2406});
    if (s.truthy(o.boolean(&s, !s.truthy(v2407)))) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v2408 = try s.global("Keys");
    const v2409 = try o.lookup(&s, frame, "binding2399");
    const v2410 = try s.call(v2408, c.pi_js_undefined(), &.{v2409});
    try o.assign(&s, frame, "binding2404", v2410);
    const v2411 = try s.global("IsEqual");
    const v2412 = try o.lookup(&s, frame, "binding2404");
    const v2413 = try s.text("length");
    const v2414 = try s.own(try js.getKey(e, v2412, v2413));
    const v2415 = try s.global("Keys");
    const v2416 = try o.lookup(&s, frame, "binding2400");
    const v2417 = try s.call(v2415, c.pi_js_undefined(), &.{v2416});
    const v2418 = try s.text("length");
    const v2419 = try s.own(try js.getKey(e, v2417, v2418));
    const v2420 = try s.call(v2411, c.pi_js_undefined(), &.{ v2414, v2419 });
    const v2422 = logical2421: {
        if (!s.truthy(v2420)) break :logical2421 v2420;
        const v2423 = try o.lookup(&s, frame, "binding2404");
        const v2424 = try s.text("every");
        const v2425 = try s.own(try js.getKey(e, v2423, v2424));
        const v2440 = try o.arrow(&s, "", 1, body2426C, &.{ graph, frame });
        const v2441 = try s.call(v2425, v2423, &.{v2440});
        break :logical2421 v2441;
    };
    return c.JS_DupValue(e.context, v2422);
}
fn body2466(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v2470 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2468", v2470);
    const v2471 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2469", v2471);
    const v2472 = try s.global("IsDeepEqual");
    const v2473 = try o.lookup(&s, frame, "binding2444");
    const v2474 = try o.lookup(&s, frame, "binding2469");
    const v2475 = try o.propertyKey(&s, v2474);
    const v2476 = try s.own(try js.getKey(e, v2473, v2475));
    const v2477 = try o.lookup(&s, frame, "binding2445");
    const v2478 = try o.lookup(&s, frame, "binding2469");
    const v2479 = try o.propertyKey(&s, v2478);
    const v2480 = try s.own(try js.getKey(e, v2477, v2479));
    const v2481 = try s.call(v2472, c.pi_js_undefined(), &.{ v2476, v2480 });
    return c.JS_DupValue(e.context, v2481);
}
fn body2466C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body2466(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body2443(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2446 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2444", v2446);
    const v2447 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2445", v2447);
    const v2448 = try s.global("IsArray");
    const v2449 = try o.lookup(&s, frame, "binding2445");
    const v2450 = try s.call(v2448, c.pi_js_undefined(), &.{v2449});
    const v2452 = logical2451: {
        if (!s.truthy(v2450)) break :logical2451 v2450;
        const v2453 = try s.global("IsEqual");
        const v2454 = try o.lookup(&s, frame, "binding2444");
        const v2455 = try s.text("length");
        const v2456 = try s.own(try js.getKey(e, v2454, v2455));
        const v2457 = try o.lookup(&s, frame, "binding2445");
        const v2458 = try s.text("length");
        const v2459 = try s.own(try js.getKey(e, v2457, v2458));
        const v2460 = try s.call(v2453, c.pi_js_undefined(), &.{ v2456, v2459 });
        break :logical2451 v2460;
    };
    const v2462 = logical2461: {
        if (!s.truthy(v2452)) break :logical2461 v2452;
        const v2463 = try o.lookup(&s, frame, "binding2444");
        const v2464 = try s.text("every");
        const v2465 = try s.own(try js.getKey(e, v2463, v2464));
        const v2482 = try o.arrow(&s, "", 2, body2466C, &.{ graph, frame });
        const v2483 = try s.call(v2465, v2463, &.{v2482});
        break :logical2461 v2483;
    };
    return c.JS_DupValue(e.context, v2462);
}
fn body2485(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2488 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2486", v2488);
    const v2489 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2487", v2489);
    const v2490 = try s.global("IsArray");
    const v2491 = try o.lookup(&s, frame, "binding2486");
    const v2492 = try s.call(v2490, c.pi_js_undefined(), &.{v2491});
    const v2494 = conditional2493: {
        if (s.truthy(v2492)) {
            const v2495 = try s.global("DeepEqualArray");
            const v2496 = try o.lookup(&s, frame, "binding2486");
            const v2497 = try o.lookup(&s, frame, "binding2487");
            const v2498 = try s.call(v2495, c.pi_js_undefined(), &.{ v2496, v2497 });
            break :conditional2493 v2498;
        } else {
            const v2499 = try s.global("IsObject");
            const v2500 = try o.lookup(&s, frame, "binding2486");
            const v2501 = try s.call(v2499, c.pi_js_undefined(), &.{v2500});
            const v2503 = conditional2502: {
                if (s.truthy(v2501)) {
                    const v2504 = try s.global("DeepEqualObject");
                    const v2505 = try o.lookup(&s, frame, "binding2486");
                    const v2506 = try o.lookup(&s, frame, "binding2487");
                    const v2507 = try s.call(v2504, c.pi_js_undefined(), &.{ v2505, v2506 });
                    break :conditional2502 v2507;
                } else {
                    const v2508 = try s.global("IsEqual");
                    const v2509 = try o.lookup(&s, frame, "binding2486");
                    const v2510 = try o.lookup(&s, frame, "binding2487");
                    const v2511 = try s.call(v2508, c.pi_js_undefined(), &.{ v2509, v2510 });
                    break :conditional2502 v2511;
                }
            };
            break :conditional2493 v2503;
        }
    };
    return c.JS_DupValue(e.context, v2494);
}
