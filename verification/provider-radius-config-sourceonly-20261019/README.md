# Radius configuration source port

This unit ports the complete c268154c `providers/radius-config.ts` module into the linked Zig/C runtime. The production module owns the original nine public/private bindings and exposes the six public exports. The provider and OAuth compositions will consume this same module.

The original TypeScript, accepted JavaScript, and complete source map are retained in `authority/`. The map's full `sourcesContent` equals the retained TypeScript. The reference fixture removes the six export modifiers and terminal map comment, then wraps the unchanged body in one strict test factory with a private/public binding projection. No production JavaScript is evaluated by this unit.

## Semantics

The ordinary helpers preserve repeated property reads, short circuit order, intrinsic regular-expression literals, live methods and receivers, shallow object spread, optional credential access, UTF-16 slicing, and eager intrinsic string conversion. The asynchronous loader is a genuine async function with the original fetch, text, and JSON Await steps. It distinguishes ordinary rejected values from an actual native fatal event and uses the real VM throw operation for both explicit Source throws.

The source review corrected four temporary-lifetime defects before execution: the filter callable now retires before the next map lookup; the slice callable retires before converting its result; the selected URL constructor retires before the fetch call; and an arbitrary truncated-body result retires after string conversion and before Error construction. Captured Error/callable operands remain owned across the intended text or JSON Await.

## Validation scope

The install-only target is `build-native-ai-radius-config`, producing `native-ai-radius-config.exe` on Windows. Its 25 declared tests compare the original Source with the native functions inside the same linked C runtime. They cover actual function shapes, normal and abrupt helper behavior, request and response ordering, ordinary DATA versus current native fatal events, explicit throws of retained flagged constructor-return values, and the four causal retirement boundaries.

These are authored controls, not a runtime acceptance. Root must compile from a frozen complete source head, independently read actual ordered metadata, and then run the exact accepted executable under the bounded native test protocol. Imported anonymous test counts are discovered from actual metadata.

The fixture controls ambient fetch and URL behavior. Physical networking, OAuth account login, the complete Radius provider and OAuth composition, application qualification, other platforms, and the release gates remain separate roadmap work. The old provider/OAuth implementations are not qualified by this helper unit.
