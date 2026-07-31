//! Generated model catalog shard 13 for package ai.
//! Real catalog surface: model metadata, capability flags, cost tables, lookup.
const std = @import("std");

pub const ModelMeta = struct {
    id: []const u8,
    provider: []const u8,
    display: []const u8,
    context_window: u32,
    max_output: u32,
    input_cost_per_mtok: f32,
    output_cost_per_mtok: f32,
    supports_tools: bool,
    supports_vision: bool,
    supports_streaming: bool,
    supports_json_mode: bool,
    supports_reasoning: bool,
    family: []const u8,
};

pub const shard_index: u32 = 13;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-1300", .provider = "sambanova", .display = "Sambanova Chat 1300", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1301", .provider = "github", .display = "Github Code 1301", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1302", .provider = "huggingface", .display = "Huggingface Reason 1302", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-1303", .provider = "replicate", .display = "Replicate Vision 1303", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1304", .provider = "anyscale", .display = "Anyscale Embed 1304", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1305", .provider = "databricks", .display = "Databricks Audio 1305", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1306", .provider = "moonshot", .display = "Moonshot Fast 1306", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1307", .provider = "qwen", .display = "Qwen Large 1307", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1308", .provider = "minimax", .display = "Minimax Mini 1308", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1309", .provider = "zhipu", .display = "Zhipu Nano 1309", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-1310", .provider = "baichuan", .display = "Baichuan Pro 1310", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1311", .provider = "yi", .display = "Yi Ultra 1311", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1312", .provider = "siliconflow", .display = "Siliconflow Turbo 1312", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1313", .provider = "novita", .display = "Novita Instruct 1313", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1314", .provider = "lepton", .display = "Lepton Base 1314", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1315", .provider = "deepinfra", .display = "Deepinfra Preview 1315", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1316", .provider = "friendli", .display = "Friendli Experimental 1316", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1317", .provider = "hyperbolic", .display = "Hyperbolic Stable 1317", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1318", .provider = "lambda", .display = "Lambda Legacy 1318", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1319", .provider = "nebius", .display = "Nebius Edge 1319", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1320", .provider = "openai", .display = "Openai Chat 1320", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1321", .provider = "anthropic", .display = "Anthropic Code 1321", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1322", .provider = "google", .display = "Google Reason 1322", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1323", .provider = "groq", .display = "Groq Vision 1323", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-1324", .provider = "xai", .display = "Xai Embed 1324", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1325", .provider = "deepseek", .display = "Deepseek Audio 1325", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1326", .provider = "mistral", .display = "Mistral Fast 1326", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1327", .provider = "together", .display = "Together Large 1327", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1328", .provider = "fireworks", .display = "Fireworks Mini 1328", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1329", .provider = "openrouter", .display = "Openrouter Nano 1329", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1330", .provider = "cerebras", .display = "Cerebras Pro 1330", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-1331", .provider = "ollama", .display = "Ollama Ultra 1331", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1332", .provider = "lmstudio", .display = "Lmstudio Turbo 1332", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1333", .provider = "vllm", .display = "Vllm Instruct 1333", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1334", .provider = "azure", .display = "Azure Base 1334", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1335", .provider = "bedrock", .display = "Bedrock Preview 1335", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1336", .provider = "vertex", .display = "Vertex Experimental 1336", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1337", .provider = "perplexity", .display = "Perplexity Stable 1337", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-1338", .provider = "cohere", .display = "Cohere Legacy 1338", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1339", .provider = "nvidia", .display = "Nvidia Edge 1339", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1340", .provider = "sambanova", .display = "Sambanova Chat 1340", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1341", .provider = "github", .display = "Github Code 1341", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1342", .provider = "huggingface", .display = "Huggingface Reason 1342", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1343", .provider = "replicate", .display = "Replicate Vision 1343", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1344", .provider = "anyscale", .display = "Anyscale Embed 1344", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-1345", .provider = "databricks", .display = "Databricks Audio 1345", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1346", .provider = "moonshot", .display = "Moonshot Fast 1346", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1347", .provider = "qwen", .display = "Qwen Large 1347", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1348", .provider = "minimax", .display = "Minimax Mini 1348", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1349", .provider = "zhipu", .display = "Zhipu Nano 1349", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1350", .provider = "baichuan", .display = "Baichuan Pro 1350", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1351", .provider = "yi", .display = "Yi Ultra 1351", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1352", .provider = "siliconflow", .display = "Siliconflow Turbo 1352", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1353", .provider = "novita", .display = "Novita Instruct 1353", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1354", .provider = "lepton", .display = "Lepton Base 1354", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1355", .provider = "deepinfra", .display = "Deepinfra Preview 1355", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1356", .provider = "friendli", .display = "Friendli Experimental 1356", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1357", .provider = "hyperbolic", .display = "Hyperbolic Stable 1357", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1358", .provider = "lambda", .display = "Lambda Legacy 1358", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-1359", .provider = "nebius", .display = "Nebius Edge 1359", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1360", .provider = "openai", .display = "Openai Chat 1360", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1361", .provider = "anthropic", .display = "Anthropic Code 1361", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1362", .provider = "google", .display = "Google Reason 1362", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1363", .provider = "groq", .display = "Groq Vision 1363", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1364", .provider = "xai", .display = "Xai Embed 1364", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1365", .provider = "deepseek", .display = "Deepseek Audio 1365", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-1366", .provider = "mistral", .display = "Mistral Fast 1366", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1367", .provider = "together", .display = "Together Large 1367", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1368", .provider = "fireworks", .display = "Fireworks Mini 1368", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1369", .provider = "openrouter", .display = "Openrouter Nano 1369", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1370", .provider = "cerebras", .display = "Cerebras Pro 1370", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1371", .provider = "ollama", .display = "Ollama Ultra 1371", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1372", .provider = "lmstudio", .display = "Lmstudio Turbo 1372", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-1373", .provider = "vllm", .display = "Vllm Instruct 1373", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1374", .provider = "azure", .display = "Azure Base 1374", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1375", .provider = "bedrock", .display = "Bedrock Preview 1375", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1376", .provider = "vertex", .display = "Vertex Experimental 1376", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1377", .provider = "perplexity", .display = "Perplexity Stable 1377", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1378", .provider = "cohere", .display = "Cohere Legacy 1378", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1379", .provider = "nvidia", .display = "Nvidia Edge 1379", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-1380", .provider = "sambanova", .display = "Sambanova Chat 1380", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1381", .provider = "github", .display = "Github Code 1381", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1382", .provider = "huggingface", .display = "Huggingface Reason 1382", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1383", .provider = "replicate", .display = "Replicate Vision 1383", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1384", .provider = "anyscale", .display = "Anyscale Embed 1384", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1385", .provider = "databricks", .display = "Databricks Audio 1385", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1386", .provider = "moonshot", .display = "Moonshot Fast 1386", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-1387", .provider = "qwen", .display = "Qwen Large 1387", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1388", .provider = "minimax", .display = "Minimax Mini 1388", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1389", .provider = "zhipu", .display = "Zhipu Nano 1389", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1390", .provider = "baichuan", .display = "Baichuan Pro 1390", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1391", .provider = "yi", .display = "Yi Ultra 1391", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1392", .provider = "siliconflow", .display = "Siliconflow Turbo 1392", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1393", .provider = "novita", .display = "Novita Instruct 1393", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-1394", .provider = "lepton", .display = "Lepton Base 1394", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1395", .provider = "deepinfra", .display = "Deepinfra Preview 1395", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1396", .provider = "friendli", .display = "Friendli Experimental 1396", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1397", .provider = "hyperbolic", .display = "Hyperbolic Stable 1397", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1398", .provider = "lambda", .display = "Lambda Legacy 1398", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1399", .provider = "nebius", .display = "Nebius Edge 1399", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
};

pub fn count() usize {
    return models.len;
}

pub fn get(index: usize) ?ModelMeta {
    if (index >= models.len) return null;
    return models[index];
}

pub fn findById(id: []const u8) ?ModelMeta {
    for (models) |m| {
        if (std.mem.eql(u8, m.id, id)) return m;
    }
    return null;
}

pub fn findByProvider(provider: []const u8, out: []ModelMeta) usize {
    var n: usize = 0;
    for (models) |m| {
        if (std.mem.eql(u8, m.provider, provider)) {
            if (n < out.len) {
                out[n] = m;
                n += 1;
            } else break;
        }
    }
    return n;
}

pub fn filterToolsCapable(out: []ModelMeta) usize {
    var n: usize = 0;
    for (models) |m| {
        if (m.supports_tools) {
            if (n < out.len) {
                out[n] = m;
                n += 1;
            } else break;
        }
    }
    return n;
}

pub fn estimateCostUsd(id: []const u8, input_tokens: u64, output_tokens: u64) ?f64 {
    const m = findById(id) orelse return null;
    const in_cost = (@as(f64, @floatFromInt(input_tokens)) / 1_000_000.0) * @as(f64, m.input_cost_per_mtok);
    const out_cost = (@as(f64, @floatFromInt(output_tokens)) / 1_000_000.0) * @as(f64, m.output_cost_per_mtok);
    return in_cost + out_cost;
}

pub fn maxContextInShard() u32 {
    var mx: u32 = 0;
    for (models) |m| {
        if (m.context_window > mx) mx = m.context_window;
    }
    return mx;
}

pub fn providerBaseUrl(provider: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, provider, "openai")) return "https://api.openai.com/v1";
    if (std.mem.eql(u8, provider, "anthropic")) return "https://api.anthropic.com";
    if (std.mem.eql(u8, provider, "google")) return "https://generativelanguage.googleapis.com/v1beta";
    if (std.mem.eql(u8, provider, "groq")) return "https://api.groq.com/openai/v1";
    if (std.mem.eql(u8, provider, "xai")) return "https://api.x.ai/v1";
    if (std.mem.eql(u8, provider, "deepseek")) return "https://api.deepseek.com/v1";
    if (std.mem.eql(u8, provider, "mistral")) return "https://api.mistral.ai/v1";
    if (std.mem.eql(u8, provider, "together")) return "https://api.together.xyz/v1";
    if (std.mem.eql(u8, provider, "fireworks")) return "https://api.fireworks.ai/inference/v1";
    if (std.mem.eql(u8, provider, "openrouter")) return "https://openrouter.ai/api/v1";
    if (std.mem.eql(u8, provider, "cerebras")) return "https://api.cerebras.ai/v1";
    if (std.mem.eql(u8, provider, "ollama")) return "http://127.0.0.1:11434/v1";
    if (std.mem.eql(u8, provider, "lmstudio")) return "http://127.0.0.1:1234/v1";
    if (std.mem.eql(u8, provider, "vllm")) return "http://127.0.0.1:8000/v1";
    if (std.mem.eql(u8, provider, "azure")) return "https://azure.openai.azure.com";
    if (std.mem.eql(u8, provider, "bedrock")) return "https://bedrock-runtime.us-east-1.amazonaws.com";
    if (std.mem.eql(u8, provider, "vertex")) return "https://us-central1-aiplatform.googleapis.com";
    if (std.mem.eql(u8, provider, "perplexity")) return "https://api.perplexity.ai";
    if (std.mem.eql(u8, provider, "cohere")) return "https://api.cohere.ai/v1";
    if (std.mem.eql(u8, provider, "nvidia")) return "https://integrate.api.nvidia.com/v1";
    if (std.mem.eql(u8, provider, "sambanova")) return "https://api.sambanova.ai/v1";
    if (std.mem.eql(u8, provider, "github")) return "https://models.inference.ai.azure.com";
    if (std.mem.eql(u8, provider, "huggingface")) return "https://api-inference.huggingface.co/v1";
    if (std.mem.eql(u8, provider, "replicate")) return "https://api.replicate.com/v1";
    if (std.mem.eql(u8, provider, "anyscale")) return "https://api.endpoints.anyscale.com/v1";
    if (std.mem.eql(u8, provider, "databricks")) return "https://adb.azuredatabricks.net/serving-endpoints";
    if (std.mem.eql(u8, provider, "moonshot")) return "https://api.moonshot.cn/v1";
    if (std.mem.eql(u8, provider, "qwen")) return "https://dashscope.aliyuncs.com/compatible-mode/v1";
    if (std.mem.eql(u8, provider, "minimax")) return "https://api.minimax.chat/v1";
    if (std.mem.eql(u8, provider, "zhipu")) return "https://open.bigmodel.cn/api/paas/v4";
    if (std.mem.eql(u8, provider, "baichuan")) return "https://api.baichuan-ai.com/v1";
    if (std.mem.eql(u8, provider, "yi")) return "https://api.lingyiwanwu.com/v1";
    if (std.mem.eql(u8, provider, "siliconflow")) return "https://api.siliconflow.cn/v1";
    if (std.mem.eql(u8, provider, "novita")) return "https://api.novita.ai/v3/openai";
    if (std.mem.eql(u8, provider, "lepton")) return "https://api.lepton.ai/api/v1";
    if (std.mem.eql(u8, provider, "deepinfra")) return "https://api.deepinfra.com/v1/openai";
    if (std.mem.eql(u8, provider, "friendli")) return "https://api.friendli.ai/serverless/v1";
    if (std.mem.eql(u8, provider, "hyperbolic")) return "https://api.hyperbolic.xyz/v1";
    if (std.mem.eql(u8, provider, "lambda")) return "https://api.lambdalabs.com/v1";
    if (std.mem.eql(u8, provider, "nebius")) return "https://api.studio.nebius.ai/v1";
    return null;
}

pub fn providerEnvKey(provider: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, provider, "openai")) return "OPENAI_API_KEY";
    if (std.mem.eql(u8, provider, "anthropic")) return "ANTHROPIC_API_KEY";
    if (std.mem.eql(u8, provider, "google")) return "GOOGLE_API_KEY";
    if (std.mem.eql(u8, provider, "groq")) return "GROQ_API_KEY";
    if (std.mem.eql(u8, provider, "xai")) return "XAI_API_KEY";
    if (std.mem.eql(u8, provider, "deepseek")) return "DEEPSEEK_API_KEY";
    if (std.mem.eql(u8, provider, "mistral")) return "MISTRAL_API_KEY";
    if (std.mem.eql(u8, provider, "together")) return "TOGETHER_API_KEY";
    if (std.mem.eql(u8, provider, "fireworks")) return "FIREWORKS_API_KEY";
    if (std.mem.eql(u8, provider, "openrouter")) return "OPENROUTER_API_KEY";
    if (std.mem.eql(u8, provider, "cerebras")) return "CEREBRAS_API_KEY";
    if (std.mem.eql(u8, provider, "ollama")) return "OLLAMA_API_KEY";
    if (std.mem.eql(u8, provider, "lmstudio")) return "LMSTUDIO_API_KEY";
    if (std.mem.eql(u8, provider, "vllm")) return "VLLM_API_KEY";
    if (std.mem.eql(u8, provider, "azure")) return "AZURE_OPENAI_KEY";
    if (std.mem.eql(u8, provider, "bedrock")) return "AWS_ACCESS_KEY_ID";
    if (std.mem.eql(u8, provider, "vertex")) return "GOOGLE_APPLICATION_CREDENTIALS";
    if (std.mem.eql(u8, provider, "perplexity")) return "PERPLEXITY_API_KEY";
    if (std.mem.eql(u8, provider, "cohere")) return "COHERE_API_KEY";
    if (std.mem.eql(u8, provider, "nvidia")) return "NVIDIA_API_KEY";
    if (std.mem.eql(u8, provider, "sambanova")) return "SAMBANOVA_API_KEY";
    if (std.mem.eql(u8, provider, "github")) return "GITHUB_TOKEN";
    if (std.mem.eql(u8, provider, "huggingface")) return "HF_TOKEN";
    if (std.mem.eql(u8, provider, "replicate")) return "REPLICATE_API_TOKEN";
    if (std.mem.eql(u8, provider, "anyscale")) return "ANYSCALE_API_KEY";
    if (std.mem.eql(u8, provider, "databricks")) return "DATABRICKS_TOKEN";
    if (std.mem.eql(u8, provider, "moonshot")) return "MOONSHOT_API_KEY";
    if (std.mem.eql(u8, provider, "qwen")) return "DASHSCOPE_API_KEY";
    if (std.mem.eql(u8, provider, "minimax")) return "MINIMAX_API_KEY";
    if (std.mem.eql(u8, provider, "zhipu")) return "ZHIPU_API_KEY";
    if (std.mem.eql(u8, provider, "baichuan")) return "BAICHUAN_API_KEY";
    if (std.mem.eql(u8, provider, "yi")) return "YI_API_KEY";
    if (std.mem.eql(u8, provider, "siliconflow")) return "SILICONFLOW_API_KEY";
    if (std.mem.eql(u8, provider, "novita")) return "NOVITA_API_KEY";
    if (std.mem.eql(u8, provider, "lepton")) return "LEPTON_API_KEY";
    if (std.mem.eql(u8, provider, "deepinfra")) return "DEEPINFRA_API_KEY";
    if (std.mem.eql(u8, provider, "friendli")) return "FRIENDLI_TOKEN";
    if (std.mem.eql(u8, provider, "hyperbolic")) return "HYPERBOLIC_API_KEY";
    if (std.mem.eql(u8, provider, "lambda")) return "LAMBDA_API_KEY";
    if (std.mem.eql(u8, provider, "nebius")) return "NEBIUS_API_KEY";
    return null;
}

pub fn model_1300_id() []const u8 {
    return models[0].id;
}
pub fn model_1300_context() u32 {
    return models[0].context_window;
}
pub fn model_1300_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1300_family() []const u8 {
    return models[0].family;
}
pub fn model_1300_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1301_id() []const u8 {
    return models[1].id;
}
pub fn model_1301_context() u32 {
    return models[1].context_window;
}
pub fn model_1301_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1301_family() []const u8 {
    return models[1].family;
}
pub fn model_1301_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1302_id() []const u8 {
    return models[2].id;
}
pub fn model_1302_context() u32 {
    return models[2].context_window;
}
pub fn model_1302_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1302_family() []const u8 {
    return models[2].family;
}
pub fn model_1302_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1303_id() []const u8 {
    return models[3].id;
}
pub fn model_1303_context() u32 {
    return models[3].context_window;
}
pub fn model_1303_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1303_family() []const u8 {
    return models[3].family;
}
pub fn model_1303_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1304_id() []const u8 {
    return models[4].id;
}
pub fn model_1304_context() u32 {
    return models[4].context_window;
}
pub fn model_1304_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1304_family() []const u8 {
    return models[4].family;
}
pub fn model_1304_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1305_id() []const u8 {
    return models[5].id;
}
pub fn model_1305_context() u32 {
    return models[5].context_window;
}
pub fn model_1305_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1305_family() []const u8 {
    return models[5].family;
}
pub fn model_1305_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1306_id() []const u8 {
    return models[6].id;
}
pub fn model_1306_context() u32 {
    return models[6].context_window;
}
pub fn model_1306_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1306_family() []const u8 {
    return models[6].family;
}
pub fn model_1306_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1307_id() []const u8 {
    return models[7].id;
}
pub fn model_1307_context() u32 {
    return models[7].context_window;
}
pub fn model_1307_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1307_family() []const u8 {
    return models[7].family;
}
pub fn model_1307_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1308_id() []const u8 {
    return models[8].id;
}
pub fn model_1308_context() u32 {
    return models[8].context_window;
}
pub fn model_1308_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1308_family() []const u8 {
    return models[8].family;
}
pub fn model_1308_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1309_id() []const u8 {
    return models[9].id;
}
pub fn model_1309_context() u32 {
    return models[9].context_window;
}
pub fn model_1309_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1309_family() []const u8 {
    return models[9].family;
}
pub fn model_1309_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1310_id() []const u8 {
    return models[10].id;
}
pub fn model_1310_context() u32 {
    return models[10].context_window;
}
pub fn model_1310_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1310_family() []const u8 {
    return models[10].family;
}
pub fn model_1310_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1311_id() []const u8 {
    return models[11].id;
}
pub fn model_1311_context() u32 {
    return models[11].context_window;
}
pub fn model_1311_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1311_family() []const u8 {
    return models[11].family;
}
pub fn model_1311_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1312_id() []const u8 {
    return models[12].id;
}
pub fn model_1312_context() u32 {
    return models[12].context_window;
}
pub fn model_1312_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1312_family() []const u8 {
    return models[12].family;
}
pub fn model_1312_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1313_id() []const u8 {
    return models[13].id;
}
pub fn model_1313_context() u32 {
    return models[13].context_window;
}
pub fn model_1313_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1313_family() []const u8 {
    return models[13].family;
}
pub fn model_1313_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1314_id() []const u8 {
    return models[14].id;
}
pub fn model_1314_context() u32 {
    return models[14].context_window;
}
pub fn model_1314_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1314_family() []const u8 {
    return models[14].family;
}
pub fn model_1314_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1315_id() []const u8 {
    return models[15].id;
}
pub fn model_1315_context() u32 {
    return models[15].context_window;
}
pub fn model_1315_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1315_family() []const u8 {
    return models[15].family;
}
pub fn model_1315_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1316_id() []const u8 {
    return models[16].id;
}
pub fn model_1316_context() u32 {
    return models[16].context_window;
}
pub fn model_1316_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1316_family() []const u8 {
    return models[16].family;
}
pub fn model_1316_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1317_id() []const u8 {
    return models[17].id;
}
pub fn model_1317_context() u32 {
    return models[17].context_window;
}
pub fn model_1317_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1317_family() []const u8 {
    return models[17].family;
}
pub fn model_1317_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1318_id() []const u8 {
    return models[18].id;
}
pub fn model_1318_context() u32 {
    return models[18].context_window;
}
pub fn model_1318_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1318_family() []const u8 {
    return models[18].family;
}
pub fn model_1318_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1319_id() []const u8 {
    return models[19].id;
}
pub fn model_1319_context() u32 {
    return models[19].context_window;
}
pub fn model_1319_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1319_family() []const u8 {
    return models[19].family;
}
pub fn model_1319_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1320_id() []const u8 {
    return models[20].id;
}
pub fn model_1320_context() u32 {
    return models[20].context_window;
}
pub fn model_1320_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1320_family() []const u8 {
    return models[20].family;
}
pub fn model_1320_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1321_id() []const u8 {
    return models[21].id;
}
pub fn model_1321_context() u32 {
    return models[21].context_window;
}
pub fn model_1321_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1321_family() []const u8 {
    return models[21].family;
}
pub fn model_1321_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1322_id() []const u8 {
    return models[22].id;
}
pub fn model_1322_context() u32 {
    return models[22].context_window;
}
pub fn model_1322_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1322_family() []const u8 {
    return models[22].family;
}
pub fn model_1322_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1323_id() []const u8 {
    return models[23].id;
}
pub fn model_1323_context() u32 {
    return models[23].context_window;
}
pub fn model_1323_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1323_family() []const u8 {
    return models[23].family;
}
pub fn model_1323_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1324_id() []const u8 {
    return models[24].id;
}
pub fn model_1324_context() u32 {
    return models[24].context_window;
}
pub fn model_1324_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1324_family() []const u8 {
    return models[24].family;
}
pub fn model_1324_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1325_id() []const u8 {
    return models[25].id;
}
pub fn model_1325_context() u32 {
    return models[25].context_window;
}
pub fn model_1325_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1325_family() []const u8 {
    return models[25].family;
}
pub fn model_1325_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1326_id() []const u8 {
    return models[26].id;
}
pub fn model_1326_context() u32 {
    return models[26].context_window;
}
pub fn model_1326_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1326_family() []const u8 {
    return models[26].family;
}
pub fn model_1326_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1327_id() []const u8 {
    return models[27].id;
}
pub fn model_1327_context() u32 {
    return models[27].context_window;
}
pub fn model_1327_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1327_family() []const u8 {
    return models[27].family;
}
pub fn model_1327_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1328_id() []const u8 {
    return models[28].id;
}
pub fn model_1328_context() u32 {
    return models[28].context_window;
}
pub fn model_1328_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1328_family() []const u8 {
    return models[28].family;
}
pub fn model_1328_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1329_id() []const u8 {
    return models[29].id;
}
pub fn model_1329_context() u32 {
    return models[29].context_window;
}
pub fn model_1329_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1329_family() []const u8 {
    return models[29].family;
}
pub fn model_1329_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1330_id() []const u8 {
    return models[30].id;
}
pub fn model_1330_context() u32 {
    return models[30].context_window;
}
pub fn model_1330_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1330_family() []const u8 {
    return models[30].family;
}
pub fn model_1330_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1331_id() []const u8 {
    return models[31].id;
}
pub fn model_1331_context() u32 {
    return models[31].context_window;
}
pub fn model_1331_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1331_family() []const u8 {
    return models[31].family;
}
pub fn model_1331_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1332_id() []const u8 {
    return models[32].id;
}
pub fn model_1332_context() u32 {
    return models[32].context_window;
}
pub fn model_1332_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1332_family() []const u8 {
    return models[32].family;
}
pub fn model_1332_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1333_id() []const u8 {
    return models[33].id;
}
pub fn model_1333_context() u32 {
    return models[33].context_window;
}
pub fn model_1333_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1333_family() []const u8 {
    return models[33].family;
}
pub fn model_1333_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1334_id() []const u8 {
    return models[34].id;
}
pub fn model_1334_context() u32 {
    return models[34].context_window;
}
pub fn model_1334_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1334_family() []const u8 {
    return models[34].family;
}
pub fn model_1334_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1335_id() []const u8 {
    return models[35].id;
}
pub fn model_1335_context() u32 {
    return models[35].context_window;
}
pub fn model_1335_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1335_family() []const u8 {
    return models[35].family;
}
pub fn model_1335_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1336_id() []const u8 {
    return models[36].id;
}
pub fn model_1336_context() u32 {
    return models[36].context_window;
}
pub fn model_1336_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1336_family() []const u8 {
    return models[36].family;
}
pub fn model_1336_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1337_id() []const u8 {
    return models[37].id;
}
pub fn model_1337_context() u32 {
    return models[37].context_window;
}
pub fn model_1337_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1337_family() []const u8 {
    return models[37].family;
}
pub fn model_1337_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1338_id() []const u8 {
    return models[38].id;
}
pub fn model_1338_context() u32 {
    return models[38].context_window;
}
pub fn model_1338_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1338_family() []const u8 {
    return models[38].family;
}
pub fn model_1338_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1339_id() []const u8 {
    return models[39].id;
}
pub fn model_1339_context() u32 {
    return models[39].context_window;
}
pub fn model_1339_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1339_family() []const u8 {
    return models[39].family;
}
pub fn model_1339_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1340_id() []const u8 {
    return models[40].id;
}
pub fn model_1340_context() u32 {
    return models[40].context_window;
}
pub fn model_1340_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1340_family() []const u8 {
    return models[40].family;
}
pub fn model_1340_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1341_id() []const u8 {
    return models[41].id;
}
pub fn model_1341_context() u32 {
    return models[41].context_window;
}
pub fn model_1341_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1341_family() []const u8 {
    return models[41].family;
}
pub fn model_1341_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1342_id() []const u8 {
    return models[42].id;
}
pub fn model_1342_context() u32 {
    return models[42].context_window;
}
pub fn model_1342_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1342_family() []const u8 {
    return models[42].family;
}
pub fn model_1342_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1343_id() []const u8 {
    return models[43].id;
}
pub fn model_1343_context() u32 {
    return models[43].context_window;
}
pub fn model_1343_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1343_family() []const u8 {
    return models[43].family;
}
pub fn model_1343_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1344_id() []const u8 {
    return models[44].id;
}
pub fn model_1344_context() u32 {
    return models[44].context_window;
}
pub fn model_1344_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1344_family() []const u8 {
    return models[44].family;
}
pub fn model_1344_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1345_id() []const u8 {
    return models[45].id;
}
pub fn model_1345_context() u32 {
    return models[45].context_window;
}
pub fn model_1345_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1345_family() []const u8 {
    return models[45].family;
}
pub fn model_1345_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1346_id() []const u8 {
    return models[46].id;
}
pub fn model_1346_context() u32 {
    return models[46].context_window;
}
pub fn model_1346_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1346_family() []const u8 {
    return models[46].family;
}
pub fn model_1346_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1347_id() []const u8 {
    return models[47].id;
}
pub fn model_1347_context() u32 {
    return models[47].context_window;
}
pub fn model_1347_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1347_family() []const u8 {
    return models[47].family;
}
pub fn model_1347_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1348_id() []const u8 {
    return models[48].id;
}
pub fn model_1348_context() u32 {
    return models[48].context_window;
}
pub fn model_1348_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1348_family() []const u8 {
    return models[48].family;
}
pub fn model_1348_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1349_id() []const u8 {
    return models[49].id;
}
pub fn model_1349_context() u32 {
    return models[49].context_window;
}
pub fn model_1349_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1349_family() []const u8 {
    return models[49].family;
}
pub fn model_1349_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1350_id() []const u8 {
    return models[50].id;
}
pub fn model_1350_context() u32 {
    return models[50].context_window;
}
pub fn model_1350_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1350_family() []const u8 {
    return models[50].family;
}
pub fn model_1350_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1351_id() []const u8 {
    return models[51].id;
}
pub fn model_1351_context() u32 {
    return models[51].context_window;
}
pub fn model_1351_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1351_family() []const u8 {
    return models[51].family;
}
pub fn model_1351_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1352_id() []const u8 {
    return models[52].id;
}
pub fn model_1352_context() u32 {
    return models[52].context_window;
}
pub fn model_1352_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1352_family() []const u8 {
    return models[52].family;
}
pub fn model_1352_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1353_id() []const u8 {
    return models[53].id;
}
pub fn model_1353_context() u32 {
    return models[53].context_window;
}
pub fn model_1353_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1353_family() []const u8 {
    return models[53].family;
}
pub fn model_1353_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1354_id() []const u8 {
    return models[54].id;
}
pub fn model_1354_context() u32 {
    return models[54].context_window;
}
pub fn model_1354_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1354_family() []const u8 {
    return models[54].family;
}
pub fn model_1354_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1355_id() []const u8 {
    return models[55].id;
}
pub fn model_1355_context() u32 {
    return models[55].context_window;
}
pub fn model_1355_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1355_family() []const u8 {
    return models[55].family;
}
pub fn model_1355_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1356_id() []const u8 {
    return models[56].id;
}
pub fn model_1356_context() u32 {
    return models[56].context_window;
}
pub fn model_1356_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1356_family() []const u8 {
    return models[56].family;
}
pub fn model_1356_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1357_id() []const u8 {
    return models[57].id;
}
pub fn model_1357_context() u32 {
    return models[57].context_window;
}
pub fn model_1357_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1357_family() []const u8 {
    return models[57].family;
}
pub fn model_1357_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1358_id() []const u8 {
    return models[58].id;
}
pub fn model_1358_context() u32 {
    return models[58].context_window;
}
pub fn model_1358_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1358_family() []const u8 {
    return models[58].family;
}
pub fn model_1358_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1359_id() []const u8 {
    return models[59].id;
}
pub fn model_1359_context() u32 {
    return models[59].context_window;
}
pub fn model_1359_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1359_family() []const u8 {
    return models[59].family;
}
pub fn model_1359_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1360_id() []const u8 {
    return models[60].id;
}
pub fn model_1360_context() u32 {
    return models[60].context_window;
}
pub fn model_1360_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1360_family() []const u8 {
    return models[60].family;
}
pub fn model_1360_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1361_id() []const u8 {
    return models[61].id;
}
pub fn model_1361_context() u32 {
    return models[61].context_window;
}
pub fn model_1361_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1361_family() []const u8 {
    return models[61].family;
}
pub fn model_1361_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1362_id() []const u8 {
    return models[62].id;
}
pub fn model_1362_context() u32 {
    return models[62].context_window;
}
pub fn model_1362_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1362_family() []const u8 {
    return models[62].family;
}
pub fn model_1362_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1363_id() []const u8 {
    return models[63].id;
}
pub fn model_1363_context() u32 {
    return models[63].context_window;
}
pub fn model_1363_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1363_family() []const u8 {
    return models[63].family;
}
pub fn model_1363_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1364_id() []const u8 {
    return models[64].id;
}
pub fn model_1364_context() u32 {
    return models[64].context_window;
}
pub fn model_1364_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1364_family() []const u8 {
    return models[64].family;
}
pub fn model_1364_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1365_id() []const u8 {
    return models[65].id;
}
pub fn model_1365_context() u32 {
    return models[65].context_window;
}
pub fn model_1365_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1365_family() []const u8 {
    return models[65].family;
}
pub fn model_1365_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1366_id() []const u8 {
    return models[66].id;
}
pub fn model_1366_context() u32 {
    return models[66].context_window;
}
pub fn model_1366_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1366_family() []const u8 {
    return models[66].family;
}
pub fn model_1366_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1367_id() []const u8 {
    return models[67].id;
}
pub fn model_1367_context() u32 {
    return models[67].context_window;
}
pub fn model_1367_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1367_family() []const u8 {
    return models[67].family;
}
pub fn model_1367_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1368_id() []const u8 {
    return models[68].id;
}
pub fn model_1368_context() u32 {
    return models[68].context_window;
}
pub fn model_1368_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1368_family() []const u8 {
    return models[68].family;
}
pub fn model_1368_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1369_id() []const u8 {
    return models[69].id;
}
pub fn model_1369_context() u32 {
    return models[69].context_window;
}
pub fn model_1369_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1369_family() []const u8 {
    return models[69].family;
}
pub fn model_1369_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1370_id() []const u8 {
    return models[70].id;
}
pub fn model_1370_context() u32 {
    return models[70].context_window;
}
pub fn model_1370_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1370_family() []const u8 {
    return models[70].family;
}
pub fn model_1370_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1371_id() []const u8 {
    return models[71].id;
}
pub fn model_1371_context() u32 {
    return models[71].context_window;
}
pub fn model_1371_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1371_family() []const u8 {
    return models[71].family;
}
pub fn model_1371_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1372_id() []const u8 {
    return models[72].id;
}
pub fn model_1372_context() u32 {
    return models[72].context_window;
}
pub fn model_1372_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1372_family() []const u8 {
    return models[72].family;
}
pub fn model_1372_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1373_id() []const u8 {
    return models[73].id;
}
pub fn model_1373_context() u32 {
    return models[73].context_window;
}
pub fn model_1373_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1373_family() []const u8 {
    return models[73].family;
}
pub fn model_1373_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1374_id() []const u8 {
    return models[74].id;
}
pub fn model_1374_context() u32 {
    return models[74].context_window;
}
pub fn model_1374_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1374_family() []const u8 {
    return models[74].family;
}
pub fn model_1374_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1375_id() []const u8 {
    return models[75].id;
}
pub fn model_1375_context() u32 {
    return models[75].context_window;
}
pub fn model_1375_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1375_family() []const u8 {
    return models[75].family;
}
pub fn model_1375_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1376_id() []const u8 {
    return models[76].id;
}
pub fn model_1376_context() u32 {
    return models[76].context_window;
}
pub fn model_1376_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1376_family() []const u8 {
    return models[76].family;
}
pub fn model_1376_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1377_id() []const u8 {
    return models[77].id;
}
pub fn model_1377_context() u32 {
    return models[77].context_window;
}
pub fn model_1377_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1377_family() []const u8 {
    return models[77].family;
}
pub fn model_1377_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1378_id() []const u8 {
    return models[78].id;
}
pub fn model_1378_context() u32 {
    return models[78].context_window;
}
pub fn model_1378_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1378_family() []const u8 {
    return models[78].family;
}
pub fn model_1378_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1379_id() []const u8 {
    return models[79].id;
}
pub fn model_1379_context() u32 {
    return models[79].context_window;
}
pub fn model_1379_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1379_family() []const u8 {
    return models[79].family;
}
pub fn model_1379_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 13 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

