// Installed SDK idle control. Admission is one byte x after live process capture.
// Read-only clipboard outcomes are validated by type; contents are never printed.
import { getNativeClipboard } from "pi-tui";

const helper = getNativeClipboard();
if (!helper) throw new Error("Installed native clipboard helper unavailable");
function text(value) {
    if (value !== null && value !== undefined && typeof value !== "string")
        throw new Error("Clipboard text result type");
}
function image(value) {
    if (value !== null && value !== undefined && !Buffer.isBuffer(value))
        throw new Error("Clipboard image result type");
}
function failure(error) {
    if (!(error instanceof Error)) throw new Error("Clipboard rejection type");
}
function admit(chunk) {
    if (chunk.length !== 1 || chunk[0] !== 120) throw new Error("Invalid clipboard idle admission");
    process.stdin.removeListener("data", admit);
    process.stdin.pause();
    // Five jobs exceed the four-worker limit and the single data/EOF turns.
    // No top-level await, timer, or live input listener keeps this work alive.
    const jobs = [
        helper.getImage().then(image, failure),
        helper.getText().then(text, failure),
        helper.getText().then(text, failure),
        helper.getText().then(text, failure),
        helper.getText().then(text, failure),
    ];
    Promise.all(jobs).then(() => console.log("PI_TUI_CLIPBOARD_IDLE_COMPLETE"));
}
process.stdin.on("data", admit);
process.stdin.resume();
console.log("PI_TUI_CLIPBOARD_IDLE_READY");
