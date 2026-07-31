//! Generated model catalog shard 12 for package ai.
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

pub const shard_index: u32 = 12;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-1200", .provider = "openai", .display = "Openai Chat 1200", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1201", .provider = "anthropic", .display = "Anthropic Code 1201", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1202", .provider = "google", .display = "Google Reason 1202", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1203", .provider = "groq", .display = "Groq Vision 1203", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1204", .provider = "xai", .display = "Xai Embed 1204", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-1205", .provider = "deepseek", .display = "Deepseek Audio 1205", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1206", .provider = "mistral", .display = "Mistral Fast 1206", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1207", .provider = "together", .display = "Together Large 1207", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1208", .provider = "fireworks", .display = "Fireworks Mini 1208", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1209", .provider = "openrouter", .display = "Openrouter Nano 1209", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1210", .provider = "cerebras", .display = "Cerebras Pro 1210", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1211", .provider = "ollama", .display = "Ollama Ultra 1211", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1212", .provider = "lmstudio", .display = "Lmstudio Turbo 1212", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1213", .provider = "vllm", .display = "Vllm Instruct 1213", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1214", .provider = "azure", .display = "Azure Base 1214", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1215", .provider = "bedrock", .display = "Bedrock Preview 1215", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1216", .provider = "vertex", .display = "Vertex Experimental 1216", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1217", .provider = "perplexity", .display = "Perplexity Stable 1217", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1218", .provider = "cohere", .display = "Cohere Legacy 1218", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-1219", .provider = "nvidia", .display = "Nvidia Edge 1219", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1220", .provider = "sambanova", .display = "Sambanova Chat 1220", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1221", .provider = "github", .display = "Github Code 1221", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1222", .provider = "huggingface", .display = "Huggingface Reason 1222", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1223", .provider = "replicate", .display = "Replicate Vision 1223", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1224", .provider = "anyscale", .display = "Anyscale Embed 1224", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1225", .provider = "databricks", .display = "Databricks Audio 1225", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-1226", .provider = "moonshot", .display = "Moonshot Fast 1226", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1227", .provider = "qwen", .display = "Qwen Large 1227", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1228", .provider = "minimax", .display = "Minimax Mini 1228", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1229", .provider = "zhipu", .display = "Zhipu Nano 1229", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1230", .provider = "baichuan", .display = "Baichuan Pro 1230", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1231", .provider = "yi", .display = "Yi Ultra 1231", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1232", .provider = "siliconflow", .display = "Siliconflow Turbo 1232", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-1233", .provider = "novita", .display = "Novita Instruct 1233", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1234", .provider = "lepton", .display = "Lepton Base 1234", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1235", .provider = "deepinfra", .display = "Deepinfra Preview 1235", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1236", .provider = "friendli", .display = "Friendli Experimental 1236", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1237", .provider = "hyperbolic", .display = "Hyperbolic Stable 1237", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1238", .provider = "lambda", .display = "Lambda Legacy 1238", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1239", .provider = "nebius", .display = "Nebius Edge 1239", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-1240", .provider = "openai", .display = "Openai Chat 1240", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1241", .provider = "anthropic", .display = "Anthropic Code 1241", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1242", .provider = "google", .display = "Google Reason 1242", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1243", .provider = "groq", .display = "Groq Vision 1243", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1244", .provider = "xai", .display = "Xai Embed 1244", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1245", .provider = "deepseek", .display = "Deepseek Audio 1245", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1246", .provider = "mistral", .display = "Mistral Fast 1246", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-1247", .provider = "together", .display = "Together Large 1247", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1248", .provider = "fireworks", .display = "Fireworks Mini 1248", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1249", .provider = "openrouter", .display = "Openrouter Nano 1249", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1250", .provider = "cerebras", .display = "Cerebras Pro 1250", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1251", .provider = "ollama", .display = "Ollama Ultra 1251", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1252", .provider = "lmstudio", .display = "Lmstudio Turbo 1252", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1253", .provider = "vllm", .display = "Vllm Instruct 1253", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-1254", .provider = "azure", .display = "Azure Base 1254", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1255", .provider = "bedrock", .display = "Bedrock Preview 1255", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1256", .provider = "vertex", .display = "Vertex Experimental 1256", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1257", .provider = "perplexity", .display = "Perplexity Stable 1257", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1258", .provider = "cohere", .display = "Cohere Legacy 1258", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1259", .provider = "nvidia", .display = "Nvidia Edge 1259", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1260", .provider = "sambanova", .display = "Sambanova Chat 1260", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-1261", .provider = "github", .display = "Github Code 1261", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1262", .provider = "huggingface", .display = "Huggingface Reason 1262", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1263", .provider = "replicate", .display = "Replicate Vision 1263", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1264", .provider = "anyscale", .display = "Anyscale Embed 1264", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1265", .provider = "databricks", .display = "Databricks Audio 1265", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1266", .provider = "moonshot", .display = "Moonshot Fast 1266", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1267", .provider = "qwen", .display = "Qwen Large 1267", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-1268", .provider = "minimax", .display = "Minimax Mini 1268", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1269", .provider = "zhipu", .display = "Zhipu Nano 1269", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1270", .provider = "baichuan", .display = "Baichuan Pro 1270", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1271", .provider = "yi", .display = "Yi Ultra 1271", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1272", .provider = "siliconflow", .display = "Siliconflow Turbo 1272", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1273", .provider = "novita", .display = "Novita Instruct 1273", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1274", .provider = "lepton", .display = "Lepton Base 1274", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-1275", .provider = "deepinfra", .display = "Deepinfra Preview 1275", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1276", .provider = "friendli", .display = "Friendli Experimental 1276", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1277", .provider = "hyperbolic", .display = "Hyperbolic Stable 1277", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1278", .provider = "lambda", .display = "Lambda Legacy 1278", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1279", .provider = "nebius", .display = "Nebius Edge 1279", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1280", .provider = "openai", .display = "Openai Chat 1280", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1281", .provider = "anthropic", .display = "Anthropic Code 1281", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-1282", .provider = "google", .display = "Google Reason 1282", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1283", .provider = "groq", .display = "Groq Vision 1283", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1284", .provider = "xai", .display = "Xai Embed 1284", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1285", .provider = "deepseek", .display = "Deepseek Audio 1285", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1286", .provider = "mistral", .display = "Mistral Fast 1286", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1287", .provider = "together", .display = "Together Large 1287", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1288", .provider = "fireworks", .display = "Fireworks Mini 1288", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-1289", .provider = "openrouter", .display = "Openrouter Nano 1289", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1290", .provider = "cerebras", .display = "Cerebras Pro 1290", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1291", .provider = "ollama", .display = "Ollama Ultra 1291", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1292", .provider = "lmstudio", .display = "Lmstudio Turbo 1292", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1293", .provider = "vllm", .display = "Vllm Instruct 1293", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1294", .provider = "azure", .display = "Azure Base 1294", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1295", .provider = "bedrock", .display = "Bedrock Preview 1295", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-1296", .provider = "vertex", .display = "Vertex Experimental 1296", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1297", .provider = "perplexity", .display = "Perplexity Stable 1297", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1298", .provider = "cohere", .display = "Cohere Legacy 1298", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1299", .provider = "nvidia", .display = "Nvidia Edge 1299", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1200_id() []const u8 {
    return models[0].id;
}
pub fn model_1200_context() u32 {
    return models[0].context_window;
}
pub fn model_1200_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1200_family() []const u8 {
    return models[0].family;
}
pub fn model_1200_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1201_id() []const u8 {
    return models[1].id;
}
pub fn model_1201_context() u32 {
    return models[1].context_window;
}
pub fn model_1201_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1201_family() []const u8 {
    return models[1].family;
}
pub fn model_1201_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1202_id() []const u8 {
    return models[2].id;
}
pub fn model_1202_context() u32 {
    return models[2].context_window;
}
pub fn model_1202_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1202_family() []const u8 {
    return models[2].family;
}
pub fn model_1202_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1203_id() []const u8 {
    return models[3].id;
}
pub fn model_1203_context() u32 {
    return models[3].context_window;
}
pub fn model_1203_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1203_family() []const u8 {
    return models[3].family;
}
pub fn model_1203_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1204_id() []const u8 {
    return models[4].id;
}
pub fn model_1204_context() u32 {
    return models[4].context_window;
}
pub fn model_1204_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1204_family() []const u8 {
    return models[4].family;
}
pub fn model_1204_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1205_id() []const u8 {
    return models[5].id;
}
pub fn model_1205_context() u32 {
    return models[5].context_window;
}
pub fn model_1205_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1205_family() []const u8 {
    return models[5].family;
}
pub fn model_1205_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1206_id() []const u8 {
    return models[6].id;
}
pub fn model_1206_context() u32 {
    return models[6].context_window;
}
pub fn model_1206_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1206_family() []const u8 {
    return models[6].family;
}
pub fn model_1206_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1207_id() []const u8 {
    return models[7].id;
}
pub fn model_1207_context() u32 {
    return models[7].context_window;
}
pub fn model_1207_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1207_family() []const u8 {
    return models[7].family;
}
pub fn model_1207_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1208_id() []const u8 {
    return models[8].id;
}
pub fn model_1208_context() u32 {
    return models[8].context_window;
}
pub fn model_1208_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1208_family() []const u8 {
    return models[8].family;
}
pub fn model_1208_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1209_id() []const u8 {
    return models[9].id;
}
pub fn model_1209_context() u32 {
    return models[9].context_window;
}
pub fn model_1209_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1209_family() []const u8 {
    return models[9].family;
}
pub fn model_1209_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1210_id() []const u8 {
    return models[10].id;
}
pub fn model_1210_context() u32 {
    return models[10].context_window;
}
pub fn model_1210_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1210_family() []const u8 {
    return models[10].family;
}
pub fn model_1210_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1211_id() []const u8 {
    return models[11].id;
}
pub fn model_1211_context() u32 {
    return models[11].context_window;
}
pub fn model_1211_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1211_family() []const u8 {
    return models[11].family;
}
pub fn model_1211_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1212_id() []const u8 {
    return models[12].id;
}
pub fn model_1212_context() u32 {
    return models[12].context_window;
}
pub fn model_1212_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1212_family() []const u8 {
    return models[12].family;
}
pub fn model_1212_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1213_id() []const u8 {
    return models[13].id;
}
pub fn model_1213_context() u32 {
    return models[13].context_window;
}
pub fn model_1213_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1213_family() []const u8 {
    return models[13].family;
}
pub fn model_1213_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1214_id() []const u8 {
    return models[14].id;
}
pub fn model_1214_context() u32 {
    return models[14].context_window;
}
pub fn model_1214_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1214_family() []const u8 {
    return models[14].family;
}
pub fn model_1214_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1215_id() []const u8 {
    return models[15].id;
}
pub fn model_1215_context() u32 {
    return models[15].context_window;
}
pub fn model_1215_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1215_family() []const u8 {
    return models[15].family;
}
pub fn model_1215_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1216_id() []const u8 {
    return models[16].id;
}
pub fn model_1216_context() u32 {
    return models[16].context_window;
}
pub fn model_1216_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1216_family() []const u8 {
    return models[16].family;
}
pub fn model_1216_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1217_id() []const u8 {
    return models[17].id;
}
pub fn model_1217_context() u32 {
    return models[17].context_window;
}
pub fn model_1217_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1217_family() []const u8 {
    return models[17].family;
}
pub fn model_1217_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1218_id() []const u8 {
    return models[18].id;
}
pub fn model_1218_context() u32 {
    return models[18].context_window;
}
pub fn model_1218_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1218_family() []const u8 {
    return models[18].family;
}
pub fn model_1218_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1219_id() []const u8 {
    return models[19].id;
}
pub fn model_1219_context() u32 {
    return models[19].context_window;
}
pub fn model_1219_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1219_family() []const u8 {
    return models[19].family;
}
pub fn model_1219_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1220_id() []const u8 {
    return models[20].id;
}
pub fn model_1220_context() u32 {
    return models[20].context_window;
}
pub fn model_1220_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1220_family() []const u8 {
    return models[20].family;
}
pub fn model_1220_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1221_id() []const u8 {
    return models[21].id;
}
pub fn model_1221_context() u32 {
    return models[21].context_window;
}
pub fn model_1221_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1221_family() []const u8 {
    return models[21].family;
}
pub fn model_1221_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1222_id() []const u8 {
    return models[22].id;
}
pub fn model_1222_context() u32 {
    return models[22].context_window;
}
pub fn model_1222_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1222_family() []const u8 {
    return models[22].family;
}
pub fn model_1222_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1223_id() []const u8 {
    return models[23].id;
}
pub fn model_1223_context() u32 {
    return models[23].context_window;
}
pub fn model_1223_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1223_family() []const u8 {
    return models[23].family;
}
pub fn model_1223_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1224_id() []const u8 {
    return models[24].id;
}
pub fn model_1224_context() u32 {
    return models[24].context_window;
}
pub fn model_1224_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1224_family() []const u8 {
    return models[24].family;
}
pub fn model_1224_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1225_id() []const u8 {
    return models[25].id;
}
pub fn model_1225_context() u32 {
    return models[25].context_window;
}
pub fn model_1225_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1225_family() []const u8 {
    return models[25].family;
}
pub fn model_1225_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1226_id() []const u8 {
    return models[26].id;
}
pub fn model_1226_context() u32 {
    return models[26].context_window;
}
pub fn model_1226_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1226_family() []const u8 {
    return models[26].family;
}
pub fn model_1226_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1227_id() []const u8 {
    return models[27].id;
}
pub fn model_1227_context() u32 {
    return models[27].context_window;
}
pub fn model_1227_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1227_family() []const u8 {
    return models[27].family;
}
pub fn model_1227_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1228_id() []const u8 {
    return models[28].id;
}
pub fn model_1228_context() u32 {
    return models[28].context_window;
}
pub fn model_1228_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1228_family() []const u8 {
    return models[28].family;
}
pub fn model_1228_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1229_id() []const u8 {
    return models[29].id;
}
pub fn model_1229_context() u32 {
    return models[29].context_window;
}
pub fn model_1229_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1229_family() []const u8 {
    return models[29].family;
}
pub fn model_1229_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1230_id() []const u8 {
    return models[30].id;
}
pub fn model_1230_context() u32 {
    return models[30].context_window;
}
pub fn model_1230_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1230_family() []const u8 {
    return models[30].family;
}
pub fn model_1230_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1231_id() []const u8 {
    return models[31].id;
}
pub fn model_1231_context() u32 {
    return models[31].context_window;
}
pub fn model_1231_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1231_family() []const u8 {
    return models[31].family;
}
pub fn model_1231_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1232_id() []const u8 {
    return models[32].id;
}
pub fn model_1232_context() u32 {
    return models[32].context_window;
}
pub fn model_1232_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1232_family() []const u8 {
    return models[32].family;
}
pub fn model_1232_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1233_id() []const u8 {
    return models[33].id;
}
pub fn model_1233_context() u32 {
    return models[33].context_window;
}
pub fn model_1233_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1233_family() []const u8 {
    return models[33].family;
}
pub fn model_1233_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1234_id() []const u8 {
    return models[34].id;
}
pub fn model_1234_context() u32 {
    return models[34].context_window;
}
pub fn model_1234_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1234_family() []const u8 {
    return models[34].family;
}
pub fn model_1234_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1235_id() []const u8 {
    return models[35].id;
}
pub fn model_1235_context() u32 {
    return models[35].context_window;
}
pub fn model_1235_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1235_family() []const u8 {
    return models[35].family;
}
pub fn model_1235_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1236_id() []const u8 {
    return models[36].id;
}
pub fn model_1236_context() u32 {
    return models[36].context_window;
}
pub fn model_1236_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1236_family() []const u8 {
    return models[36].family;
}
pub fn model_1236_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1237_id() []const u8 {
    return models[37].id;
}
pub fn model_1237_context() u32 {
    return models[37].context_window;
}
pub fn model_1237_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1237_family() []const u8 {
    return models[37].family;
}
pub fn model_1237_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1238_id() []const u8 {
    return models[38].id;
}
pub fn model_1238_context() u32 {
    return models[38].context_window;
}
pub fn model_1238_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1238_family() []const u8 {
    return models[38].family;
}
pub fn model_1238_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1239_id() []const u8 {
    return models[39].id;
}
pub fn model_1239_context() u32 {
    return models[39].context_window;
}
pub fn model_1239_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1239_family() []const u8 {
    return models[39].family;
}
pub fn model_1239_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1240_id() []const u8 {
    return models[40].id;
}
pub fn model_1240_context() u32 {
    return models[40].context_window;
}
pub fn model_1240_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1240_family() []const u8 {
    return models[40].family;
}
pub fn model_1240_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1241_id() []const u8 {
    return models[41].id;
}
pub fn model_1241_context() u32 {
    return models[41].context_window;
}
pub fn model_1241_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1241_family() []const u8 {
    return models[41].family;
}
pub fn model_1241_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1242_id() []const u8 {
    return models[42].id;
}
pub fn model_1242_context() u32 {
    return models[42].context_window;
}
pub fn model_1242_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1242_family() []const u8 {
    return models[42].family;
}
pub fn model_1242_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1243_id() []const u8 {
    return models[43].id;
}
pub fn model_1243_context() u32 {
    return models[43].context_window;
}
pub fn model_1243_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1243_family() []const u8 {
    return models[43].family;
}
pub fn model_1243_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1244_id() []const u8 {
    return models[44].id;
}
pub fn model_1244_context() u32 {
    return models[44].context_window;
}
pub fn model_1244_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1244_family() []const u8 {
    return models[44].family;
}
pub fn model_1244_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1245_id() []const u8 {
    return models[45].id;
}
pub fn model_1245_context() u32 {
    return models[45].context_window;
}
pub fn model_1245_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1245_family() []const u8 {
    return models[45].family;
}
pub fn model_1245_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1246_id() []const u8 {
    return models[46].id;
}
pub fn model_1246_context() u32 {
    return models[46].context_window;
}
pub fn model_1246_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1246_family() []const u8 {
    return models[46].family;
}
pub fn model_1246_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1247_id() []const u8 {
    return models[47].id;
}
pub fn model_1247_context() u32 {
    return models[47].context_window;
}
pub fn model_1247_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1247_family() []const u8 {
    return models[47].family;
}
pub fn model_1247_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1248_id() []const u8 {
    return models[48].id;
}
pub fn model_1248_context() u32 {
    return models[48].context_window;
}
pub fn model_1248_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1248_family() []const u8 {
    return models[48].family;
}
pub fn model_1248_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1249_id() []const u8 {
    return models[49].id;
}
pub fn model_1249_context() u32 {
    return models[49].context_window;
}
pub fn model_1249_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1249_family() []const u8 {
    return models[49].family;
}
pub fn model_1249_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1250_id() []const u8 {
    return models[50].id;
}
pub fn model_1250_context() u32 {
    return models[50].context_window;
}
pub fn model_1250_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1250_family() []const u8 {
    return models[50].family;
}
pub fn model_1250_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1251_id() []const u8 {
    return models[51].id;
}
pub fn model_1251_context() u32 {
    return models[51].context_window;
}
pub fn model_1251_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1251_family() []const u8 {
    return models[51].family;
}
pub fn model_1251_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1252_id() []const u8 {
    return models[52].id;
}
pub fn model_1252_context() u32 {
    return models[52].context_window;
}
pub fn model_1252_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1252_family() []const u8 {
    return models[52].family;
}
pub fn model_1252_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1253_id() []const u8 {
    return models[53].id;
}
pub fn model_1253_context() u32 {
    return models[53].context_window;
}
pub fn model_1253_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1253_family() []const u8 {
    return models[53].family;
}
pub fn model_1253_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1254_id() []const u8 {
    return models[54].id;
}
pub fn model_1254_context() u32 {
    return models[54].context_window;
}
pub fn model_1254_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1254_family() []const u8 {
    return models[54].family;
}
pub fn model_1254_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1255_id() []const u8 {
    return models[55].id;
}
pub fn model_1255_context() u32 {
    return models[55].context_window;
}
pub fn model_1255_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1255_family() []const u8 {
    return models[55].family;
}
pub fn model_1255_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1256_id() []const u8 {
    return models[56].id;
}
pub fn model_1256_context() u32 {
    return models[56].context_window;
}
pub fn model_1256_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1256_family() []const u8 {
    return models[56].family;
}
pub fn model_1256_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1257_id() []const u8 {
    return models[57].id;
}
pub fn model_1257_context() u32 {
    return models[57].context_window;
}
pub fn model_1257_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1257_family() []const u8 {
    return models[57].family;
}
pub fn model_1257_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1258_id() []const u8 {
    return models[58].id;
}
pub fn model_1258_context() u32 {
    return models[58].context_window;
}
pub fn model_1258_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1258_family() []const u8 {
    return models[58].family;
}
pub fn model_1258_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1259_id() []const u8 {
    return models[59].id;
}
pub fn model_1259_context() u32 {
    return models[59].context_window;
}
pub fn model_1259_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1259_family() []const u8 {
    return models[59].family;
}
pub fn model_1259_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1260_id() []const u8 {
    return models[60].id;
}
pub fn model_1260_context() u32 {
    return models[60].context_window;
}
pub fn model_1260_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1260_family() []const u8 {
    return models[60].family;
}
pub fn model_1260_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1261_id() []const u8 {
    return models[61].id;
}
pub fn model_1261_context() u32 {
    return models[61].context_window;
}
pub fn model_1261_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1261_family() []const u8 {
    return models[61].family;
}
pub fn model_1261_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1262_id() []const u8 {
    return models[62].id;
}
pub fn model_1262_context() u32 {
    return models[62].context_window;
}
pub fn model_1262_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1262_family() []const u8 {
    return models[62].family;
}
pub fn model_1262_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1263_id() []const u8 {
    return models[63].id;
}
pub fn model_1263_context() u32 {
    return models[63].context_window;
}
pub fn model_1263_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1263_family() []const u8 {
    return models[63].family;
}
pub fn model_1263_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1264_id() []const u8 {
    return models[64].id;
}
pub fn model_1264_context() u32 {
    return models[64].context_window;
}
pub fn model_1264_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1264_family() []const u8 {
    return models[64].family;
}
pub fn model_1264_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1265_id() []const u8 {
    return models[65].id;
}
pub fn model_1265_context() u32 {
    return models[65].context_window;
}
pub fn model_1265_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1265_family() []const u8 {
    return models[65].family;
}
pub fn model_1265_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1266_id() []const u8 {
    return models[66].id;
}
pub fn model_1266_context() u32 {
    return models[66].context_window;
}
pub fn model_1266_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1266_family() []const u8 {
    return models[66].family;
}
pub fn model_1266_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1267_id() []const u8 {
    return models[67].id;
}
pub fn model_1267_context() u32 {
    return models[67].context_window;
}
pub fn model_1267_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1267_family() []const u8 {
    return models[67].family;
}
pub fn model_1267_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1268_id() []const u8 {
    return models[68].id;
}
pub fn model_1268_context() u32 {
    return models[68].context_window;
}
pub fn model_1268_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1268_family() []const u8 {
    return models[68].family;
}
pub fn model_1268_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1269_id() []const u8 {
    return models[69].id;
}
pub fn model_1269_context() u32 {
    return models[69].context_window;
}
pub fn model_1269_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1269_family() []const u8 {
    return models[69].family;
}
pub fn model_1269_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1270_id() []const u8 {
    return models[70].id;
}
pub fn model_1270_context() u32 {
    return models[70].context_window;
}
pub fn model_1270_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1270_family() []const u8 {
    return models[70].family;
}
pub fn model_1270_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1271_id() []const u8 {
    return models[71].id;
}
pub fn model_1271_context() u32 {
    return models[71].context_window;
}
pub fn model_1271_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1271_family() []const u8 {
    return models[71].family;
}
pub fn model_1271_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1272_id() []const u8 {
    return models[72].id;
}
pub fn model_1272_context() u32 {
    return models[72].context_window;
}
pub fn model_1272_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1272_family() []const u8 {
    return models[72].family;
}
pub fn model_1272_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1273_id() []const u8 {
    return models[73].id;
}
pub fn model_1273_context() u32 {
    return models[73].context_window;
}
pub fn model_1273_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1273_family() []const u8 {
    return models[73].family;
}
pub fn model_1273_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1274_id() []const u8 {
    return models[74].id;
}
pub fn model_1274_context() u32 {
    return models[74].context_window;
}
pub fn model_1274_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1274_family() []const u8 {
    return models[74].family;
}
pub fn model_1274_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1275_id() []const u8 {
    return models[75].id;
}
pub fn model_1275_context() u32 {
    return models[75].context_window;
}
pub fn model_1275_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1275_family() []const u8 {
    return models[75].family;
}
pub fn model_1275_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1276_id() []const u8 {
    return models[76].id;
}
pub fn model_1276_context() u32 {
    return models[76].context_window;
}
pub fn model_1276_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1276_family() []const u8 {
    return models[76].family;
}
pub fn model_1276_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1277_id() []const u8 {
    return models[77].id;
}
pub fn model_1277_context() u32 {
    return models[77].context_window;
}
pub fn model_1277_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1277_family() []const u8 {
    return models[77].family;
}
pub fn model_1277_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1278_id() []const u8 {
    return models[78].id;
}
pub fn model_1278_context() u32 {
    return models[78].context_window;
}
pub fn model_1278_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1278_family() []const u8 {
    return models[78].family;
}
pub fn model_1278_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1279_id() []const u8 {
    return models[79].id;
}
pub fn model_1279_context() u32 {
    return models[79].context_window;
}
pub fn model_1279_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1279_family() []const u8 {
    return models[79].family;
}
pub fn model_1279_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 12 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

