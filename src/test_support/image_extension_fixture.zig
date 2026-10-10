//! Original user-authored post-tool image hook input.
pub const source =
    \\import { readFileSync } from "node:fs";
    \\import { join } from "node:path";
    \\export default function (pi: any) {
    \\  pi.registerTool({
    \\    name: "image174", label: "Image 174",
    \\    description: "Return a result replaced by an oversized post-hook image",
    \\    parameters: { type: "object", properties: {}, additionalProperties: false },
    \\    async execute() { return { content: [{ type: "text", text: "pre-hook" }] }; },
    \\  });
    \\  pi.on("tool_result", (event: any) => {
    \\    if (event.toolName !== "image174") return;
    \\    const data = readFileSync(join(process.cwd(), "large-hook.png")).toString("base64");
    \\    return { content: [
    \\      { type: "text", text: "post-hook-174" },
    \\      { type: "image", data, mimeType: "image/png" },
    \\    ], details: { checkpoint: 174 } };
    \\  });
    \\}
    \\
;
