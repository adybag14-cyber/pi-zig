//! Actual VM controls for target Node primitive Symbol.split / Symbol.replace.
//! Source-only candidate: Root must rebuild QuickJS, query metadata and run it.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");

fn checkScript(source: []const u8) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    const script = try std.mem.concat(std.testing.allocator, u8, &.{
        "\"use strict\";\n(() => {\n", source, "\n})()\n",
    });
    defer std.testing.allocator.free(script);
    const result = try engine.eval(script, "primitive-string-hooks.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsBool(result));
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

fn publishActualFatalHooks(s: *h.Scope) !c.JSValue {
    const hooks = try v.own(s, try retirement.createNativeRetirementHooks(s.engine));
    try v.put(s, try v.global(s, "globalThis"), "primitiveHooks", hooks);
    return v.duplicate(s, try v.get(s, hooks, "record"));
}

fn checkNativeFatal(source: []const u8) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    const record = try h.expression(engine, publishActualFatalHooks, .{});
    defer engine.freeValue(record);
    const script = try std.mem.concat(std.testing.allocator, u8, &.{
        "\"use strict\";\n(() => {\n", source, "\n})()\n",
    });
    defer std.testing.allocator.free(script);
    const result = block: {
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        break :block engine.eval(script, "primitive-string-hooks-fatal.js", c.JS_EVAL_TYPE_GLOBAL);
    };
    if (result) |value| engine.freeValue(value) else |_| {}
    try std.testing.expectError(error.JavaScriptException, result);
    try retirement.verifyRecordedActualNativeFatal(engine, record);
    try retirement.verifyNoVisits(record, .{ 1, 2, 3, 4, 5 });
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "native primitive string hooks string primitive dispatch preserves strict receiver and uncoerced arguments" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const input = { toString() { throw new Error("unexpected input conversion"); } };
        \\const limit = { valueOf() { throw new Error("unexpected limit conversion"); } };
        \\String.prototype[Symbol.split] = function (value, maximum) {
        \\  return [this, value, maximum, arguments.length];
        \\};
        \\const result = split.call(input, ".", limit);
        \\return result[0] === "." && result[1] === input &&
        \\       result[2] === limit && result[3] === 2;
    );
}

test "native primitive string hooks primitive accessor runs once with original primitive receiver" {
    try checkScript(
        \\const split = String.prototype.split;
        \\let gets = 0;
        \\let calls = 0;
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true,
        \\  get() {
        \\    if (this !== "|") throw new Error("boxed getter receiver");
        \\    gets++;
        \\    return function (value, limit) {
        \\      calls++;
        \\      return this === "|" && value === "a|b" && limit === undefined;
        \\    };
        \\  }
        \\});
        \\return split.call("a|b", "|") === true && gets === 1 && calls === 1;
    );
}

test "native primitive string hooks integer floating signed zero and NaN separators use Number prototype" {
    try checkScript(
        \\const split = String.prototype.split;
        \\Number.prototype[Symbol.split] = function () { return this; };
        \\return [7, 7.5, -0, NaN].every(value =>
        \\  Object.is(split.call("unused", value), value));
    );
}

test "native primitive string hooks both Boolean primitive separators dispatch without truthiness filtering" {
    try checkScript(
        \\const split = String.prototype.split;
        \\Boolean.prototype[Symbol.split] = function (value) {
        \\  return [this, value];
        \\};
        \\const a = split.call("unused", false);
        \\const b = split.call("unused", true);
        \\return a[0] === false && b[0] === true && a[1] === "unused" && b[1] === "unused";
    );
}

test "native primitive string hooks BigInt primitive separator preserves original BigInt receiver" {
    try checkScript(
        \\const split = String.prototype.split;
        \\BigInt.prototype[Symbol.split] = function (value, limit) { return [this, value, limit]; };
        \\const result = split.call("unused", 9007199254740993n, 4);
        \\return result[0] === 9007199254740993n && result[1] === "unused" && result[2] === 4;
    );
}

test "native primitive string hooks Symbol primitive hook precedes forbidden Symbol string conversion" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const separator = Symbol("separator");
        \\Symbol.prototype[Symbol.split] = function (value) { return [this, value]; };
        \\const result = split.call("unused", separator);
        \\return result[0] === separator && result[1] === "unused";
    );
}

test "native primitive string hooks Object prototype inherited hook is visible through primitive prototypes" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const symbol = Symbol("inherited");
        \\Object.defineProperty(Object.prototype, Symbol.split, {
        \\  configurable: true,
        \\  value: function () { return this; }
        \\});
        \\return [".", 4, false, 3n, symbol].every(value =>
        \\  Object.is(split.call("unused", value), value));
    );
}

test "native primitive string hooks splitter result identity is returned without array or string conversion" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const marker = {};
        \\let expected;
        \\String.prototype[Symbol.split] = function () { return expected; };
        \\for (const value of [undefined, null, false, 4, Symbol("result"), marker]) {
        \\  expected = value;
        \\  if (split.call("unused", ".") !== value) return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks primitive hook getter abrupt completion precedes input and limit conversion" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const marker = {};
        \\const events = [];
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true, get() { events.push("get"); throw marker; }
        \\});
        \\const input = { toString() { events.push("input"); return "x"; } };
        \\const limit = { valueOf() { events.push("limit"); return 1; } };
        \\try { split.call(input, ".", limit); } catch (error) {
        \\  return error === marker && events.join(",") === "get";
        \\}
        \\return false;
    );
}

test "native primitive string hooks noncallable primitive hook throws before later coercions" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const events = [];
        \\String.prototype[Symbol.split] = {};
        \\const input = { toString() { events.push("input"); return "x"; } };
        \\const limit = { valueOf() { events.push("limit"); return 1; } };
        \\try { split.call(input, ".", limit); } catch (error) {
        \\  return error instanceof TypeError && events.length === 0;
        \\}
        \\return false;
    );
}

test "native primitive string hooks splitter abrupt completion preserves exact thrown value" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const marker = {};
        \\String.prototype[Symbol.split] = function () { throw marker; };
        \\try { split.call("a.b", "."); } catch (error) { return error === marker; }
        \\return false;
    );
}

test "native primitive string hooks null and undefined hook values preserve fallback conversion order" {
    try checkScript(
        \\const split = String.prototype.split;
        \\for (const missing of [null, undefined]) {
        \\  const events = [];
        \\  Object.defineProperty(String.prototype, Symbol.split, {
        \\    configurable: true, get() { events.push("get"); return missing; }
        \\  });
        \\  const input = { toString() { events.push("input"); return "a.b"; } };
        \\  const limit = { valueOf() { events.push("limit"); return 2; } };
        \\  const result = split.call(input, ".", limit);
        \\  if (events.join(",") !== "get,input,limit" || result.join("|") !== "a|b") return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks nullish separators bypass prototype lookup and retain fallback results" {
    try checkScript(
        \\const split = String.prototype.split;
        \\let gets = 0;
        \\Object.defineProperty(Object.prototype, Symbol.split, {
        \\  configurable: true, get() { gets++; throw new Error("nullish lookup"); }
        \\});
        \\const a = split.call("anullb", null);
        \\const b = split.call("a.b", undefined);
        \\return a.join("|") === "a|b" && b.length === 1 && b[0] === "a.b" && gets === 0;
    );
}

test "native primitive string hooks nullish input rejects before primitive hook lookup" {
    try checkScript(
        \\const split = String.prototype.split;
        \\let gets = 0;
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true, get() { gets++; return function () {}; }
        \\});
        \\let rejected = 0;
        \\for (const input of [null, undefined]) {
        \\  try { split.call(input, "."); } catch (error) {
        \\    if (error instanceof TypeError) rejected++;
        \\  }
        \\}
        \\return rejected === 2 && gets === 0;
    );
}

test "native primitive string hooks zero limit remains an uncoerced argument on the hook path" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const input = { toString() { throw new Error("unexpected fallback"); } };
        \\Number.prototype[Symbol.split] = function (value, limit) {
        \\  return this === 0 && value === input && limit === 0;
        \\};
        \\return split.call(input, 0, 0) === true;
    );
}

test "native primitive string hooks self deleting getter and returned method retain their active lifetimes" {
    try checkScript(
        \\const split = String.prototype.split;
        \\let gets = 0;
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true, get() {
        \\    gets++;
        \\    delete String.prototype[Symbol.split];
        \\    return function (value) {
        \\      if (this !== "|") throw new Error("lost primitive");
        \\      return value + ":retained";
        \\    };
        \\  }
        \\});
        \\const first = split.call("original", "|");
        \\const second = split.call("a|b", "|");
        \\return first === "original:retained" && second.join(",") === "a,b" && gets === 1;
    );
}

test "native primitive string hooks reentrant primitive getter retains separate outer arguments" {
    try checkScript(
        \\const split = String.prototype.split;
        \\let gets = 0;
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true, get() {
        \\    gets++;
        \\    const separator = this;
        \\    if (separator === "outer" && split.call("I", "inner", 0) !== "inner:I:0")
        \\      throw new Error("inner call");
        \\    return function (value, limit) { return separator + ":" + value + ":" + limit; };
        \\  }
        \\});
        \\return split.call("R", "outer", 1) === "outer:R:1" && gets === 2;
    );
}

test "native primitive string hooks callable Proxy receives primitive receiver and exact argument pair" {
    try checkScript(
        \\const split = String.prototype.split;
        \\const input = {};
        \\const limit = {};
        \\let calls = 0;
        \\String.prototype[Symbol.split] = new Proxy(function () { throw new Error("target"); }, {
        \\  apply(target, receiver, args) {
        \\    calls++;
        \\    return receiver === "." && args.length === 2 && args[0] === input && args[1] === limit;
        \\  }
        \\});
        \\return split.call(input, ".", limit) === true && calls === 1;
    );
}

test "native primitive string hooks sloppy splitter receives normal primitive receiver boxing" {
    try checkScript(
        \\const split = String.prototype.split;
        \\String.prototype[Symbol.split] = Function("value", "limit",
        \\  "return [typeof this, this.valueOf(), value, limit];");
        \\const result = split.call("text", ".", 3);
        \\return result[0] === "object" && result[1] === "." && result[2] === "text" && result[3] === 3;
    );
}

test "native primitive string hooks ordinary fallback object hooks and RegExp split retain behavior" {
    try checkScript(
        \\const split = String.prototype.split;
        \\if (split.call("a.b.c", ".", 2).join("|") !== "a|b") return false;
        \\if (split.call("ab", "").join("|") !== "a|b") return false;
        \\if (split.call("a,b", /,/).join("|") !== "a|b") return false;
        \\const separator = { [Symbol.split](value, limit) { return [this, value, limit]; } };
        \\const result = split.call("input", separator, 5);
        \\return result[0] === separator && result[1] === "input" && result[2] === 5;
    );
}

test "native primitive string hooks replace and replaceAll preserve every primitive kind and uncoerced arguments" {
    try checkScript(
        \\const methods = [String.prototype.replace, String.prototype.replaceAll];
        \\const symbol = Symbol("search");
        \\const values = [".", 7, 7.5, -0, NaN, false, true, 3n, symbol];
        \\for (const prototype of [String.prototype, Number.prototype, Boolean.prototype, BigInt.prototype, Symbol.prototype]) {
        \\  prototype[Symbol.replace] = function (value, replacement) {
        \\    return [this, value, replacement, arguments.length];
        \\  };
        \\}
        \\const input = { toString() { throw new Error("input conversion"); } };
        \\const replacement = { toString() { throw new Error("replacement conversion"); } };
        \\for (const method of methods) for (const value of values) {
        \\  const result = method.call(input, value, replacement);
        \\  if (!Object.is(result[0], value) || result[1] !== input ||
        \\      result[2] !== replacement || result[3] !== 2) return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks replace accessor reads once with exact primitive receiver before coercions" {
    try checkScript(
        \\for (const method of [String.prototype.replace, String.prototype.replaceAll]) {
        \\  const events = [];
        \\  Object.defineProperty(String.prototype, Symbol.replace, {
        \\    configurable: true, get() {
        \\      events.push("get");
        \\      if (this !== ".") throw new Error("boxed getter");
        \\      return function (input, replacement) {
        \\        events.push("call");
        \\        return this === "." && input === original && replacement === next;
        \\      };
        \\    }
        \\  });
        \\  const original = { toString() { events.push("input"); return "a.b"; } };
        \\  const next = { toString() { events.push("replacement"); return "x"; } };
        \\  if (method.call(original, ".", next) !== true || events.join(",") !== "get,call") return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks replaceAll primitive IsRegExp does not observe match or flags" {
    try checkScript(
        \\const replaceAll = String.prototype.replaceAll;
        \\let forbidden = 0;
        \\for (const key of [Symbol.match, "flags"]) {
        \\  Object.defineProperty(String.prototype, key, {
        \\    configurable: true, get() { forbidden++; throw new Error("primitive IsRegExp"); }
        \\  });
        \\}
        \\String.prototype[Symbol.replace] = function (input, replacement) {
        \\  return this === "." && input === "a.b" && replacement === "x";
        \\};
        \\return replaceAll.call("a.b", ".", "x") === true && forbidden === 0;
    );
}

test "native primitive string hooks replace nullish receivers and searches preserve original guard ordering" {
    try checkScript(
        \\const methods = [String.prototype.replace, String.prototype.replaceAll];
        \\let gets = 0;
        \\Object.defineProperty(Object.prototype, Symbol.replace, {
        \\  configurable: true, get() { gets++; throw new Error("unexpected lookup"); }
        \\});
        \\for (const method of methods) {
        \\  for (const input of [null, undefined]) {
        \\    let rejected = false;
        \\    try { method.call(input, ".", "x"); } catch (error) { rejected = error instanceof TypeError; }
        \\    if (!rejected) return false;
        \\  }
        \\  if (method.call("anullb", null, "X") !== "aXb") return false;
        \\  if (method.call("aundefinedb", undefined, "X") !== "aXb") return false;
        \\}
        \\return gets === 0;
    );
}

test "native primitive string hooks replace hook getter and noncallable failures precede input conversion" {
    try checkScript(
        \\for (const method of [String.prototype.replace, String.prototype.replaceAll]) {
        \\  for (const mode of ["throw", "noncallable"]) {
        \\    const marker = {};
        \\    const events = [];
        \\    Object.defineProperty(String.prototype, Symbol.replace, {
        \\      configurable: true, get() {
        \\        events.push("get");
        \\        if (mode === "throw") throw marker;
        \\        return {};
        \\      }
        \\    });
        \\    const input = { toString() { events.push("input"); return "a.b"; } };
        \\    const replacement = { toString() { events.push("replacement"); return "x"; } };
        \\    let caught = false;
        \\    try { method.call(input, ".", replacement); } catch (error) {
        \\      caught = mode === "throw" ? error === marker : error instanceof TypeError;
        \\    }
        \\    if (!caught || events.join(",") !== "get") return false;
        \\  }
        \\}
        \\return true;
    );
}

test "native primitive string hooks replace hook returns arbitrary identity and preserves exact abrupt value" {
    try checkScript(
        \\for (const method of [String.prototype.replace, String.prototype.replaceAll]) {
        \\  let expected;
        \\  String.prototype[Symbol.replace] = function () { return expected; };
        \\  const marker = {};
        \\  for (const value of [undefined, null, false, 7, Symbol("result"), marker]) {
        \\    expected = value;
        \\    if (method.call("a.b", ".", "x") !== value) return false;
        \\  }
        \\  String.prototype[Symbol.replace] = function () { throw marker; };
        \\  let caught = false;
        \\  try { method.call("a.b", ".", "x"); } catch (error) { caught = error === marker; }
        \\  if (!caught) return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks replace nullish hook fallback preserves coercion order and occurrence semantics" {
    try checkScript(
        \\const methods = [String.prototype.replace, String.prototype.replaceAll];
        \\for (let index = 0; index < methods.length; index++) {
        \\  for (const missing of [null, undefined]) {
        \\    const events = [];
        \\    Object.defineProperty(String.prototype, Symbol.replace, {
        \\      configurable: true, get() { events.push("get"); return missing; }
        \\    });
        \\    const input = { toString() { events.push("input"); return "a.a"; } };
        \\    const replacement = { toString() { events.push("replacement"); return "x"; } };
        \\    const result = methods[index].call(input, "a", replacement);
        \\    if (result !== (index === 0 ? "x.a" : "x.x") ||
        \\        events.join(",") !== "get,input,replacement") return false;
        \\  }
        \\}
        \\return true;
    );
}

test "native primitive string hooks replaceAll retains RegExp global validation before replace lookup" {
    try checkScript(
        \\const replace = String.prototype.replace;
        \\const replaceAll = String.prototype.replaceAll;
        \\const events = [];
        \\let flags = "i";
        \\const search = {
        \\  get [Symbol.match]() { events.push("match"); return true; },
        \\  get flags() { events.push("flags"); return flags; },
        \\  get [Symbol.replace]() { events.push("replace"); return function () { return this; }; }
        \\};
        \\let rejected = false;
        \\try { replaceAll.call("x", search, "y"); } catch (error) { rejected = error instanceof TypeError; }
        \\if (!rejected || events.join(",") !== "match,flags") return false;
        \\events.length = 0; flags = "g";
        \\if (replaceAll.call("x", search, "y") !== search ||
        \\    events.join(",") !== "match,flags,replace") return false;
        \\events.length = 0;
        \\return replace.call("x", search, "y") === search && events.join(",") === "replace";
    );
}

test "native primitive string hooks replace self deleting getter retains current callable and later fallback" {
    try checkScript(
        \\for (const method of [String.prototype.replace, String.prototype.replaceAll]) {
        \\  let gets = 0;
        \\  Object.defineProperty(String.prototype, Symbol.replace, {
        \\    configurable: true, get() {
        \\      gets++;
        \\      delete String.prototype[Symbol.replace];
        \\      return function (value) {
        \\        if (this !== "b") throw new Error("lost receiver");
        \\        return value + ":retained";
        \\      };
        \\    }
        \\  });
        \\  if (method.call("original", "b", "X") !== "original:retained") return false;
        \\  if (method.call("aba", "b", "X") !== "aXa" || gets !== 1) return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks replace reentrant accessor and callable Proxy retain independent argument pairs" {
    try checkScript(
        \\for (const method of [String.prototype.replace, String.prototype.replaceAll]) {
        \\  let gets = 0;
        \\  let calls = 0;
        \\  Object.defineProperty(String.prototype, Symbol.replace, {
        \\    configurable: true, get() {
        \\      gets++;
        \\      const search = this;
        \\      if (search === "outer" && method.call("I", "inner", "N") !== "inner:I:N") throw new Error("inner");
        \\      return new Proxy(function () { throw new Error("target"); }, {
        \\        apply(target, receiver, args) {
        \\          calls++;
        \\          if (receiver !== search || args.length !== 2) throw new Error("call arguments");
        \\          return search + ":" + args[0] + ":" + args[1];
        \\        }
        \\      });
        \\    }
        \\  });
        \\  if (method.call("R", "outer", "X") !== "outer:R:X" || gets !== 2 || calls !== 2) return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks timer trace label primitive backslash and quote replacements observe both live hooks" {
    try checkScript(
        \\const events = [];
        \\Object.defineProperty(String.prototype, Symbol.replace, {
        \\  configurable: true, get() {
        \\    const search = this;
        \\    events.push(["get", search]);
        \\    return function (value, replacement) {
        \\      events.push(["call", this, value, replacement]);
        \\      return value;
        \\    };
        \\  }
        \\});
        \\const label = 'a\\b"c';
        \\const result = label.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
        \\return result === label && events.length === 4 &&
        \\       events[0][0] === "get" && events[0][1] === "\\" &&
        \\       events[1][0] === "call" && events[1][1] === "\\" &&
        \\       events[1][2] === label && events[1][3] === "\\\\" &&
        \\       events[2][0] === "get" && events[2][1] === '"' &&
        \\       events[3][0] === "call" && events[3][1] === '"' &&
        \\       events[3][2] === label && events[3][3] === '\\"';
    );
}

test "native primitive string hooks replace ordinary RegExp object and sloppy primitive behavior remain intact" {
    try checkScript(
        \\const replace = String.prototype.replace;
        \\const replaceAll = String.prototype.replaceAll;
        \\if (replace.call("aba", "a", "x") !== "xba" || replaceAll.call("aba", "a", "x") !== "xbx") return false;
        \\if (replace.call("aba", /a/, "x") !== "xba" || replaceAll.call("aba", /a/g, "x") !== "xbx") return false;
        \\let rejected = false;
        \\try { replaceAll.call("aba", /a/, "x"); } catch (error) { rejected = error instanceof TypeError; }
        \\if (!rejected) return false;
        \\const object = { [Symbol.replace](input, next) { return [this, input, next]; } };
        \\const value = replace.call("A", object, "B");
        \\if (value[0] !== object || value[1] !== "A" || value[2] !== "B") return false;
        \\String.prototype[Symbol.replace] = Function("input", "next",
        \\  "return [typeof this, this.valueOf(), input, next];");
        \\for (const method of [replace, replaceAll]) {
        \\  const result = method.call("A", ".", "B");
        \\  if (result[0] !== "object" || result[1] !== "." || result[2] !== "A" || result[3] !== "B") return false;
        \\}
        \\return true;
    );
}

test "native primitive string hooks split primitive getter preserves actual native fatal before coercion" {
    try checkNativeFatal(
        \\const prior = primitiveHooks.freshPrivateData();
        \\if (!primitiveHooks.isUnmarkedPrivateData(prior)) throw new Error("missing ordinary private data");
        \\const operation = String.prototype.split;
        \\Object.defineProperty(String.prototype, Symbol.split, {
        \\  configurable: true, get() { return primitiveHooks.raiseNativeFatal(); }
        \\});
        \\const input = { toString() { primitiveHooks.visit(4); return "a.b"; } };
        \\const limit = { valueOf() { primitiveHooks.visit(5); return 1; } };
        \\try { operation.call(input, ".", limit); } catch (error) { primitiveHooks.visit(3); }
        \\primitiveHooks.visit(2);
    );
}

test "native primitive string hooks split primitive method preserves actual native fatal through owned call" {
    try checkNativeFatal(
        \\const prior = primitiveHooks.freshPrivateData();
        \\if (!primitiveHooks.isUnmarkedPrivateData(prior)) throw new Error("missing ordinary private data");
        \\const operation = String.prototype.split;
        \\String.prototype[Symbol.split] = function () { return primitiveHooks.raiseNativeFatal(); };
        \\const input = { toString() { primitiveHooks.visit(4); return "a.b"; } };
        \\try { operation.call(input, "."); } catch (error) { primitiveHooks.visit(3); }
        \\primitiveHooks.visit(2);
    );
}

test "native primitive string hooks replaceAll primitive getter preserves actual native fatal before coercion" {
    try checkNativeFatal(
        \\const prior = primitiveHooks.freshPrivateData();
        \\if (!primitiveHooks.isUnmarkedPrivateData(prior)) throw new Error("missing ordinary private data");
        \\const operation = String.prototype.replaceAll;
        \\Object.defineProperty(String.prototype, Symbol.replace, {
        \\  configurable: true, get() { return primitiveHooks.raiseNativeFatal(); }
        \\});
        \\const input = { toString() { primitiveHooks.visit(4); return "a.b"; } };
        \\const replacement = { toString() { primitiveHooks.visit(5); return "x"; } };
        \\try { operation.call(input, ".", replacement); } catch (error) { primitiveHooks.visit(3); }
        \\primitiveHooks.visit(2);
    );
}

test "native primitive string hooks replace primitive method preserves actual native fatal through owned call" {
    try checkNativeFatal(
        \\const prior = primitiveHooks.freshPrivateData();
        \\if (!primitiveHooks.isUnmarkedPrivateData(prior)) throw new Error("missing ordinary private data");
        \\const operation = String.prototype.replace;
        \\String.prototype[Symbol.replace] = function () { return primitiveHooks.raiseNativeFatal(); };
        \\const input = { toString() { primitiveHooks.visit(4); return "a.b"; } };
        \\const replacement = { toString() { primitiveHooks.visit(5); return "x"; } };
        \\try { operation.call(input, ".", replacement); } catch (error) { primitiveHooks.visit(3); }
        \\primitiveHooks.visit(2);
    );
}

