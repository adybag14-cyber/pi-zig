//! Generated model catalog shard 14 for package ai.
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

pub const shard_index: u32 = 14;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-1400", .provider = "openai", .display = "Openai Chat 1400", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-1401", .provider = "anthropic", .display = "Anthropic Code 1401", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1402", .provider = "google", .display = "Google Reason 1402", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1403", .provider = "groq", .display = "Groq Vision 1403", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1404", .provider = "xai", .display = "Xai Embed 1404", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1405", .provider = "deepseek", .display = "Deepseek Audio 1405", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1406", .provider = "mistral", .display = "Mistral Fast 1406", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1407", .provider = "together", .display = "Together Large 1407", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-1408", .provider = "fireworks", .display = "Fireworks Mini 1408", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1409", .provider = "openrouter", .display = "Openrouter Nano 1409", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1410", .provider = "cerebras", .display = "Cerebras Pro 1410", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1411", .provider = "ollama", .display = "Ollama Ultra 1411", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1412", .provider = "lmstudio", .display = "Lmstudio Turbo 1412", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1413", .provider = "vllm", .display = "Vllm Instruct 1413", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1414", .provider = "azure", .display = "Azure Base 1414", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-1415", .provider = "bedrock", .display = "Bedrock Preview 1415", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1416", .provider = "vertex", .display = "Vertex Experimental 1416", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1417", .provider = "perplexity", .display = "Perplexity Stable 1417", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1418", .provider = "cohere", .display = "Cohere Legacy 1418", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1419", .provider = "nvidia", .display = "Nvidia Edge 1419", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1420", .provider = "sambanova", .display = "Sambanova Chat 1420", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1421", .provider = "github", .display = "Github Code 1421", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-1422", .provider = "huggingface", .display = "Huggingface Reason 1422", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1423", .provider = "replicate", .display = "Replicate Vision 1423", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1424", .provider = "anyscale", .display = "Anyscale Embed 1424", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1425", .provider = "databricks", .display = "Databricks Audio 1425", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1426", .provider = "moonshot", .display = "Moonshot Fast 1426", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1427", .provider = "qwen", .display = "Qwen Large 1427", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1428", .provider = "minimax", .display = "Minimax Mini 1428", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-1429", .provider = "zhipu", .display = "Zhipu Nano 1429", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1430", .provider = "baichuan", .display = "Baichuan Pro 1430", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1431", .provider = "yi", .display = "Yi Ultra 1431", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1432", .provider = "siliconflow", .display = "Siliconflow Turbo 1432", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1433", .provider = "novita", .display = "Novita Instruct 1433", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1434", .provider = "lepton", .display = "Lepton Base 1434", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1435", .provider = "deepinfra", .display = "Deepinfra Preview 1435", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-1436", .provider = "friendli", .display = "Friendli Experimental 1436", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1437", .provider = "hyperbolic", .display = "Hyperbolic Stable 1437", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1438", .provider = "lambda", .display = "Lambda Legacy 1438", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1439", .provider = "nebius", .display = "Nebius Edge 1439", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1440", .provider = "openai", .display = "Openai Chat 1440", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1441", .provider = "anthropic", .display = "Anthropic Code 1441", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1442", .provider = "google", .display = "Google Reason 1442", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-1443", .provider = "groq", .display = "Groq Vision 1443", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1444", .provider = "xai", .display = "Xai Embed 1444", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1445", .provider = "deepseek", .display = "Deepseek Audio 1445", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1446", .provider = "mistral", .display = "Mistral Fast 1446", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1447", .provider = "together", .display = "Together Large 1447", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1448", .provider = "fireworks", .display = "Fireworks Mini 1448", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1449", .provider = "openrouter", .display = "Openrouter Nano 1449", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-1450", .provider = "cerebras", .display = "Cerebras Pro 1450", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1451", .provider = "ollama", .display = "Ollama Ultra 1451", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1452", .provider = "lmstudio", .display = "Lmstudio Turbo 1452", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1453", .provider = "vllm", .display = "Vllm Instruct 1453", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1454", .provider = "azure", .display = "Azure Base 1454", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1455", .provider = "bedrock", .display = "Bedrock Preview 1455", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1456", .provider = "vertex", .display = "Vertex Experimental 1456", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-1457", .provider = "perplexity", .display = "Perplexity Stable 1457", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1458", .provider = "cohere", .display = "Cohere Legacy 1458", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1459", .provider = "nvidia", .display = "Nvidia Edge 1459", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1460", .provider = "sambanova", .display = "Sambanova Chat 1460", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1461", .provider = "github", .display = "Github Code 1461", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1462", .provider = "huggingface", .display = "Huggingface Reason 1462", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1463", .provider = "replicate", .display = "Replicate Vision 1463", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-1464", .provider = "anyscale", .display = "Anyscale Embed 1464", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1465", .provider = "databricks", .display = "Databricks Audio 1465", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1466", .provider = "moonshot", .display = "Moonshot Fast 1466", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1467", .provider = "qwen", .display = "Qwen Large 1467", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1468", .provider = "minimax", .display = "Minimax Mini 1468", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1469", .provider = "zhipu", .display = "Zhipu Nano 1469", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1470", .provider = "baichuan", .display = "Baichuan Pro 1470", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-1471", .provider = "yi", .display = "Yi Ultra 1471", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1472", .provider = "siliconflow", .display = "Siliconflow Turbo 1472", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1473", .provider = "novita", .display = "Novita Instruct 1473", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1474", .provider = "lepton", .display = "Lepton Base 1474", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1475", .provider = "deepinfra", .display = "Deepinfra Preview 1475", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1476", .provider = "friendli", .display = "Friendli Experimental 1476", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1477", .provider = "hyperbolic", .display = "Hyperbolic Stable 1477", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-1478", .provider = "lambda", .display = "Lambda Legacy 1478", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1479", .provider = "nebius", .display = "Nebius Edge 1479", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1480", .provider = "openai", .display = "Openai Chat 1480", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1481", .provider = "anthropic", .display = "Anthropic Code 1481", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1482", .provider = "google", .display = "Google Reason 1482", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1483", .provider = "groq", .display = "Groq Vision 1483", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1484", .provider = "xai", .display = "Xai Embed 1484", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-1485", .provider = "deepseek", .display = "Deepseek Audio 1485", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1486", .provider = "mistral", .display = "Mistral Fast 1486", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1487", .provider = "together", .display = "Together Large 1487", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1488", .provider = "fireworks", .display = "Fireworks Mini 1488", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1489", .provider = "openrouter", .display = "Openrouter Nano 1489", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1490", .provider = "cerebras", .display = "Cerebras Pro 1490", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1491", .provider = "ollama", .display = "Ollama Ultra 1491", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1492", .provider = "lmstudio", .display = "Lmstudio Turbo 1492", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1493", .provider = "vllm", .display = "Vllm Instruct 1493", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1494", .provider = "azure", .display = "Azure Base 1494", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1495", .provider = "bedrock", .display = "Bedrock Preview 1495", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1496", .provider = "vertex", .display = "Vertex Experimental 1496", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1497", .provider = "perplexity", .display = "Perplexity Stable 1497", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1498", .provider = "cohere", .display = "Cohere Legacy 1498", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-1499", .provider = "nvidia", .display = "Nvidia Edge 1499", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1400_id() []const u8 {
    return models[0].id;
}
pub fn model_1400_context() u32 {
    return models[0].context_window;
}
pub fn model_1400_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1400_family() []const u8 {
    return models[0].family;
}
pub fn model_1400_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1401_id() []const u8 {
    return models[1].id;
}
pub fn model_1401_context() u32 {
    return models[1].context_window;
}
pub fn model_1401_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1401_family() []const u8 {
    return models[1].family;
}
pub fn model_1401_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1402_id() []const u8 {
    return models[2].id;
}
pub fn model_1402_context() u32 {
    return models[2].context_window;
}
pub fn model_1402_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1402_family() []const u8 {
    return models[2].family;
}
pub fn model_1402_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1403_id() []const u8 {
    return models[3].id;
}
pub fn model_1403_context() u32 {
    return models[3].context_window;
}
pub fn model_1403_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1403_family() []const u8 {
    return models[3].family;
}
pub fn model_1403_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1404_id() []const u8 {
    return models[4].id;
}
pub fn model_1404_context() u32 {
    return models[4].context_window;
}
pub fn model_1404_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1404_family() []const u8 {
    return models[4].family;
}
pub fn model_1404_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1405_id() []const u8 {
    return models[5].id;
}
pub fn model_1405_context() u32 {
    return models[5].context_window;
}
pub fn model_1405_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1405_family() []const u8 {
    return models[5].family;
}
pub fn model_1405_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1406_id() []const u8 {
    return models[6].id;
}
pub fn model_1406_context() u32 {
    return models[6].context_window;
}
pub fn model_1406_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1406_family() []const u8 {
    return models[6].family;
}
pub fn model_1406_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1407_id() []const u8 {
    return models[7].id;
}
pub fn model_1407_context() u32 {
    return models[7].context_window;
}
pub fn model_1407_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1407_family() []const u8 {
    return models[7].family;
}
pub fn model_1407_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1408_id() []const u8 {
    return models[8].id;
}
pub fn model_1408_context() u32 {
    return models[8].context_window;
}
pub fn model_1408_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1408_family() []const u8 {
    return models[8].family;
}
pub fn model_1408_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1409_id() []const u8 {
    return models[9].id;
}
pub fn model_1409_context() u32 {
    return models[9].context_window;
}
pub fn model_1409_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1409_family() []const u8 {
    return models[9].family;
}
pub fn model_1409_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1410_id() []const u8 {
    return models[10].id;
}
pub fn model_1410_context() u32 {
    return models[10].context_window;
}
pub fn model_1410_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1410_family() []const u8 {
    return models[10].family;
}
pub fn model_1410_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1411_id() []const u8 {
    return models[11].id;
}
pub fn model_1411_context() u32 {
    return models[11].context_window;
}
pub fn model_1411_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1411_family() []const u8 {
    return models[11].family;
}
pub fn model_1411_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1412_id() []const u8 {
    return models[12].id;
}
pub fn model_1412_context() u32 {
    return models[12].context_window;
}
pub fn model_1412_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1412_family() []const u8 {
    return models[12].family;
}
pub fn model_1412_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1413_id() []const u8 {
    return models[13].id;
}
pub fn model_1413_context() u32 {
    return models[13].context_window;
}
pub fn model_1413_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1413_family() []const u8 {
    return models[13].family;
}
pub fn model_1413_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1414_id() []const u8 {
    return models[14].id;
}
pub fn model_1414_context() u32 {
    return models[14].context_window;
}
pub fn model_1414_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1414_family() []const u8 {
    return models[14].family;
}
pub fn model_1414_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1415_id() []const u8 {
    return models[15].id;
}
pub fn model_1415_context() u32 {
    return models[15].context_window;
}
pub fn model_1415_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1415_family() []const u8 {
    return models[15].family;
}
pub fn model_1415_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1416_id() []const u8 {
    return models[16].id;
}
pub fn model_1416_context() u32 {
    return models[16].context_window;
}
pub fn model_1416_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1416_family() []const u8 {
    return models[16].family;
}
pub fn model_1416_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1417_id() []const u8 {
    return models[17].id;
}
pub fn model_1417_context() u32 {
    return models[17].context_window;
}
pub fn model_1417_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1417_family() []const u8 {
    return models[17].family;
}
pub fn model_1417_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1418_id() []const u8 {
    return models[18].id;
}
pub fn model_1418_context() u32 {
    return models[18].context_window;
}
pub fn model_1418_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1418_family() []const u8 {
    return models[18].family;
}
pub fn model_1418_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1419_id() []const u8 {
    return models[19].id;
}
pub fn model_1419_context() u32 {
    return models[19].context_window;
}
pub fn model_1419_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1419_family() []const u8 {
    return models[19].family;
}
pub fn model_1419_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1420_id() []const u8 {
    return models[20].id;
}
pub fn model_1420_context() u32 {
    return models[20].context_window;
}
pub fn model_1420_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1420_family() []const u8 {
    return models[20].family;
}
pub fn model_1420_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1421_id() []const u8 {
    return models[21].id;
}
pub fn model_1421_context() u32 {
    return models[21].context_window;
}
pub fn model_1421_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1421_family() []const u8 {
    return models[21].family;
}
pub fn model_1421_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1422_id() []const u8 {
    return models[22].id;
}
pub fn model_1422_context() u32 {
    return models[22].context_window;
}
pub fn model_1422_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1422_family() []const u8 {
    return models[22].family;
}
pub fn model_1422_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1423_id() []const u8 {
    return models[23].id;
}
pub fn model_1423_context() u32 {
    return models[23].context_window;
}
pub fn model_1423_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1423_family() []const u8 {
    return models[23].family;
}
pub fn model_1423_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1424_id() []const u8 {
    return models[24].id;
}
pub fn model_1424_context() u32 {
    return models[24].context_window;
}
pub fn model_1424_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1424_family() []const u8 {
    return models[24].family;
}
pub fn model_1424_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1425_id() []const u8 {
    return models[25].id;
}
pub fn model_1425_context() u32 {
    return models[25].context_window;
}
pub fn model_1425_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1425_family() []const u8 {
    return models[25].family;
}
pub fn model_1425_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1426_id() []const u8 {
    return models[26].id;
}
pub fn model_1426_context() u32 {
    return models[26].context_window;
}
pub fn model_1426_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1426_family() []const u8 {
    return models[26].family;
}
pub fn model_1426_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1427_id() []const u8 {
    return models[27].id;
}
pub fn model_1427_context() u32 {
    return models[27].context_window;
}
pub fn model_1427_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1427_family() []const u8 {
    return models[27].family;
}
pub fn model_1427_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1428_id() []const u8 {
    return models[28].id;
}
pub fn model_1428_context() u32 {
    return models[28].context_window;
}
pub fn model_1428_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1428_family() []const u8 {
    return models[28].family;
}
pub fn model_1428_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1429_id() []const u8 {
    return models[29].id;
}
pub fn model_1429_context() u32 {
    return models[29].context_window;
}
pub fn model_1429_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1429_family() []const u8 {
    return models[29].family;
}
pub fn model_1429_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1430_id() []const u8 {
    return models[30].id;
}
pub fn model_1430_context() u32 {
    return models[30].context_window;
}
pub fn model_1430_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1430_family() []const u8 {
    return models[30].family;
}
pub fn model_1430_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1431_id() []const u8 {
    return models[31].id;
}
pub fn model_1431_context() u32 {
    return models[31].context_window;
}
pub fn model_1431_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1431_family() []const u8 {
    return models[31].family;
}
pub fn model_1431_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1432_id() []const u8 {
    return models[32].id;
}
pub fn model_1432_context() u32 {
    return models[32].context_window;
}
pub fn model_1432_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1432_family() []const u8 {
    return models[32].family;
}
pub fn model_1432_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1433_id() []const u8 {
    return models[33].id;
}
pub fn model_1433_context() u32 {
    return models[33].context_window;
}
pub fn model_1433_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1433_family() []const u8 {
    return models[33].family;
}
pub fn model_1433_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1434_id() []const u8 {
    return models[34].id;
}
pub fn model_1434_context() u32 {
    return models[34].context_window;
}
pub fn model_1434_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1434_family() []const u8 {
    return models[34].family;
}
pub fn model_1434_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1435_id() []const u8 {
    return models[35].id;
}
pub fn model_1435_context() u32 {
    return models[35].context_window;
}
pub fn model_1435_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1435_family() []const u8 {
    return models[35].family;
}
pub fn model_1435_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1436_id() []const u8 {
    return models[36].id;
}
pub fn model_1436_context() u32 {
    return models[36].context_window;
}
pub fn model_1436_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1436_family() []const u8 {
    return models[36].family;
}
pub fn model_1436_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1437_id() []const u8 {
    return models[37].id;
}
pub fn model_1437_context() u32 {
    return models[37].context_window;
}
pub fn model_1437_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1437_family() []const u8 {
    return models[37].family;
}
pub fn model_1437_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1438_id() []const u8 {
    return models[38].id;
}
pub fn model_1438_context() u32 {
    return models[38].context_window;
}
pub fn model_1438_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1438_family() []const u8 {
    return models[38].family;
}
pub fn model_1438_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1439_id() []const u8 {
    return models[39].id;
}
pub fn model_1439_context() u32 {
    return models[39].context_window;
}
pub fn model_1439_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1439_family() []const u8 {
    return models[39].family;
}
pub fn model_1439_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1440_id() []const u8 {
    return models[40].id;
}
pub fn model_1440_context() u32 {
    return models[40].context_window;
}
pub fn model_1440_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1440_family() []const u8 {
    return models[40].family;
}
pub fn model_1440_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1441_id() []const u8 {
    return models[41].id;
}
pub fn model_1441_context() u32 {
    return models[41].context_window;
}
pub fn model_1441_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1441_family() []const u8 {
    return models[41].family;
}
pub fn model_1441_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1442_id() []const u8 {
    return models[42].id;
}
pub fn model_1442_context() u32 {
    return models[42].context_window;
}
pub fn model_1442_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1442_family() []const u8 {
    return models[42].family;
}
pub fn model_1442_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1443_id() []const u8 {
    return models[43].id;
}
pub fn model_1443_context() u32 {
    return models[43].context_window;
}
pub fn model_1443_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1443_family() []const u8 {
    return models[43].family;
}
pub fn model_1443_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1444_id() []const u8 {
    return models[44].id;
}
pub fn model_1444_context() u32 {
    return models[44].context_window;
}
pub fn model_1444_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1444_family() []const u8 {
    return models[44].family;
}
pub fn model_1444_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1445_id() []const u8 {
    return models[45].id;
}
pub fn model_1445_context() u32 {
    return models[45].context_window;
}
pub fn model_1445_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1445_family() []const u8 {
    return models[45].family;
}
pub fn model_1445_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1446_id() []const u8 {
    return models[46].id;
}
pub fn model_1446_context() u32 {
    return models[46].context_window;
}
pub fn model_1446_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1446_family() []const u8 {
    return models[46].family;
}
pub fn model_1446_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1447_id() []const u8 {
    return models[47].id;
}
pub fn model_1447_context() u32 {
    return models[47].context_window;
}
pub fn model_1447_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1447_family() []const u8 {
    return models[47].family;
}
pub fn model_1447_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1448_id() []const u8 {
    return models[48].id;
}
pub fn model_1448_context() u32 {
    return models[48].context_window;
}
pub fn model_1448_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1448_family() []const u8 {
    return models[48].family;
}
pub fn model_1448_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1449_id() []const u8 {
    return models[49].id;
}
pub fn model_1449_context() u32 {
    return models[49].context_window;
}
pub fn model_1449_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1449_family() []const u8 {
    return models[49].family;
}
pub fn model_1449_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1450_id() []const u8 {
    return models[50].id;
}
pub fn model_1450_context() u32 {
    return models[50].context_window;
}
pub fn model_1450_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1450_family() []const u8 {
    return models[50].family;
}
pub fn model_1450_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1451_id() []const u8 {
    return models[51].id;
}
pub fn model_1451_context() u32 {
    return models[51].context_window;
}
pub fn model_1451_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1451_family() []const u8 {
    return models[51].family;
}
pub fn model_1451_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1452_id() []const u8 {
    return models[52].id;
}
pub fn model_1452_context() u32 {
    return models[52].context_window;
}
pub fn model_1452_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1452_family() []const u8 {
    return models[52].family;
}
pub fn model_1452_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1453_id() []const u8 {
    return models[53].id;
}
pub fn model_1453_context() u32 {
    return models[53].context_window;
}
pub fn model_1453_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1453_family() []const u8 {
    return models[53].family;
}
pub fn model_1453_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1454_id() []const u8 {
    return models[54].id;
}
pub fn model_1454_context() u32 {
    return models[54].context_window;
}
pub fn model_1454_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1454_family() []const u8 {
    return models[54].family;
}
pub fn model_1454_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1455_id() []const u8 {
    return models[55].id;
}
pub fn model_1455_context() u32 {
    return models[55].context_window;
}
pub fn model_1455_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1455_family() []const u8 {
    return models[55].family;
}
pub fn model_1455_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1456_id() []const u8 {
    return models[56].id;
}
pub fn model_1456_context() u32 {
    return models[56].context_window;
}
pub fn model_1456_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1456_family() []const u8 {
    return models[56].family;
}
pub fn model_1456_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1457_id() []const u8 {
    return models[57].id;
}
pub fn model_1457_context() u32 {
    return models[57].context_window;
}
pub fn model_1457_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1457_family() []const u8 {
    return models[57].family;
}
pub fn model_1457_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1458_id() []const u8 {
    return models[58].id;
}
pub fn model_1458_context() u32 {
    return models[58].context_window;
}
pub fn model_1458_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1458_family() []const u8 {
    return models[58].family;
}
pub fn model_1458_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1459_id() []const u8 {
    return models[59].id;
}
pub fn model_1459_context() u32 {
    return models[59].context_window;
}
pub fn model_1459_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1459_family() []const u8 {
    return models[59].family;
}
pub fn model_1459_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1460_id() []const u8 {
    return models[60].id;
}
pub fn model_1460_context() u32 {
    return models[60].context_window;
}
pub fn model_1460_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1460_family() []const u8 {
    return models[60].family;
}
pub fn model_1460_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1461_id() []const u8 {
    return models[61].id;
}
pub fn model_1461_context() u32 {
    return models[61].context_window;
}
pub fn model_1461_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1461_family() []const u8 {
    return models[61].family;
}
pub fn model_1461_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1462_id() []const u8 {
    return models[62].id;
}
pub fn model_1462_context() u32 {
    return models[62].context_window;
}
pub fn model_1462_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1462_family() []const u8 {
    return models[62].family;
}
pub fn model_1462_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1463_id() []const u8 {
    return models[63].id;
}
pub fn model_1463_context() u32 {
    return models[63].context_window;
}
pub fn model_1463_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1463_family() []const u8 {
    return models[63].family;
}
pub fn model_1463_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1464_id() []const u8 {
    return models[64].id;
}
pub fn model_1464_context() u32 {
    return models[64].context_window;
}
pub fn model_1464_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1464_family() []const u8 {
    return models[64].family;
}
pub fn model_1464_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1465_id() []const u8 {
    return models[65].id;
}
pub fn model_1465_context() u32 {
    return models[65].context_window;
}
pub fn model_1465_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1465_family() []const u8 {
    return models[65].family;
}
pub fn model_1465_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1466_id() []const u8 {
    return models[66].id;
}
pub fn model_1466_context() u32 {
    return models[66].context_window;
}
pub fn model_1466_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1466_family() []const u8 {
    return models[66].family;
}
pub fn model_1466_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1467_id() []const u8 {
    return models[67].id;
}
pub fn model_1467_context() u32 {
    return models[67].context_window;
}
pub fn model_1467_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1467_family() []const u8 {
    return models[67].family;
}
pub fn model_1467_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1468_id() []const u8 {
    return models[68].id;
}
pub fn model_1468_context() u32 {
    return models[68].context_window;
}
pub fn model_1468_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1468_family() []const u8 {
    return models[68].family;
}
pub fn model_1468_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1469_id() []const u8 {
    return models[69].id;
}
pub fn model_1469_context() u32 {
    return models[69].context_window;
}
pub fn model_1469_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1469_family() []const u8 {
    return models[69].family;
}
pub fn model_1469_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1470_id() []const u8 {
    return models[70].id;
}
pub fn model_1470_context() u32 {
    return models[70].context_window;
}
pub fn model_1470_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1470_family() []const u8 {
    return models[70].family;
}
pub fn model_1470_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1471_id() []const u8 {
    return models[71].id;
}
pub fn model_1471_context() u32 {
    return models[71].context_window;
}
pub fn model_1471_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1471_family() []const u8 {
    return models[71].family;
}
pub fn model_1471_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1472_id() []const u8 {
    return models[72].id;
}
pub fn model_1472_context() u32 {
    return models[72].context_window;
}
pub fn model_1472_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1472_family() []const u8 {
    return models[72].family;
}
pub fn model_1472_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1473_id() []const u8 {
    return models[73].id;
}
pub fn model_1473_context() u32 {
    return models[73].context_window;
}
pub fn model_1473_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1473_family() []const u8 {
    return models[73].family;
}
pub fn model_1473_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1474_id() []const u8 {
    return models[74].id;
}
pub fn model_1474_context() u32 {
    return models[74].context_window;
}
pub fn model_1474_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1474_family() []const u8 {
    return models[74].family;
}
pub fn model_1474_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1475_id() []const u8 {
    return models[75].id;
}
pub fn model_1475_context() u32 {
    return models[75].context_window;
}
pub fn model_1475_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1475_family() []const u8 {
    return models[75].family;
}
pub fn model_1475_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1476_id() []const u8 {
    return models[76].id;
}
pub fn model_1476_context() u32 {
    return models[76].context_window;
}
pub fn model_1476_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1476_family() []const u8 {
    return models[76].family;
}
pub fn model_1476_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1477_id() []const u8 {
    return models[77].id;
}
pub fn model_1477_context() u32 {
    return models[77].context_window;
}
pub fn model_1477_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1477_family() []const u8 {
    return models[77].family;
}
pub fn model_1477_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1478_id() []const u8 {
    return models[78].id;
}
pub fn model_1478_context() u32 {
    return models[78].context_window;
}
pub fn model_1478_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1478_family() []const u8 {
    return models[78].family;
}
pub fn model_1478_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1479_id() []const u8 {
    return models[79].id;
}
pub fn model_1479_context() u32 {
    return models[79].context_window;
}
pub fn model_1479_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1479_family() []const u8 {
    return models[79].family;
}
pub fn model_1479_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 14 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

