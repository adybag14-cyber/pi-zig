//! Generated model catalog shard 15 for package ai.
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

pub const shard_index: u32 = 15;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-1500", .provider = "sambanova", .display = "Sambanova Chat 1500", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1501", .provider = "github", .display = "Github Code 1501", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1502", .provider = "huggingface", .display = "Huggingface Reason 1502", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1503", .provider = "replicate", .display = "Replicate Vision 1503", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1504", .provider = "anyscale", .display = "Anyscale Embed 1504", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1505", .provider = "databricks", .display = "Databricks Audio 1505", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-1506", .provider = "moonshot", .display = "Moonshot Fast 1506", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1507", .provider = "qwen", .display = "Qwen Large 1507", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1508", .provider = "minimax", .display = "Minimax Mini 1508", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1509", .provider = "zhipu", .display = "Zhipu Nano 1509", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1510", .provider = "baichuan", .display = "Baichuan Pro 1510", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1511", .provider = "yi", .display = "Yi Ultra 1511", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1512", .provider = "siliconflow", .display = "Siliconflow Turbo 1512", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-1513", .provider = "novita", .display = "Novita Instruct 1513", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1514", .provider = "lepton", .display = "Lepton Base 1514", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1515", .provider = "deepinfra", .display = "Deepinfra Preview 1515", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1516", .provider = "friendli", .display = "Friendli Experimental 1516", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1517", .provider = "hyperbolic", .display = "Hyperbolic Stable 1517", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1518", .provider = "lambda", .display = "Lambda Legacy 1518", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1519", .provider = "nebius", .display = "Nebius Edge 1519", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-1520", .provider = "openai", .display = "Openai Chat 1520", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1521", .provider = "anthropic", .display = "Anthropic Code 1521", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1522", .provider = "google", .display = "Google Reason 1522", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1523", .provider = "groq", .display = "Groq Vision 1523", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1524", .provider = "xai", .display = "Xai Embed 1524", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1525", .provider = "deepseek", .display = "Deepseek Audio 1525", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1526", .provider = "mistral", .display = "Mistral Fast 1526", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-1527", .provider = "together", .display = "Together Large 1527", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1528", .provider = "fireworks", .display = "Fireworks Mini 1528", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1529", .provider = "openrouter", .display = "Openrouter Nano 1529", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1530", .provider = "cerebras", .display = "Cerebras Pro 1530", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1531", .provider = "ollama", .display = "Ollama Ultra 1531", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1532", .provider = "lmstudio", .display = "Lmstudio Turbo 1532", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1533", .provider = "vllm", .display = "Vllm Instruct 1533", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-1534", .provider = "azure", .display = "Azure Base 1534", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1535", .provider = "bedrock", .display = "Bedrock Preview 1535", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1536", .provider = "vertex", .display = "Vertex Experimental 1536", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1537", .provider = "perplexity", .display = "Perplexity Stable 1537", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1538", .provider = "cohere", .display = "Cohere Legacy 1538", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1539", .provider = "nvidia", .display = "Nvidia Edge 1539", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1540", .provider = "sambanova", .display = "Sambanova Chat 1540", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-1541", .provider = "github", .display = "Github Code 1541", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1542", .provider = "huggingface", .display = "Huggingface Reason 1542", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1543", .provider = "replicate", .display = "Replicate Vision 1543", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1544", .provider = "anyscale", .display = "Anyscale Embed 1544", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1545", .provider = "databricks", .display = "Databricks Audio 1545", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1546", .provider = "moonshot", .display = "Moonshot Fast 1546", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1547", .provider = "qwen", .display = "Qwen Large 1547", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-1548", .provider = "minimax", .display = "Minimax Mini 1548", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1549", .provider = "zhipu", .display = "Zhipu Nano 1549", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1550", .provider = "baichuan", .display = "Baichuan Pro 1550", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1551", .provider = "yi", .display = "Yi Ultra 1551", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1552", .provider = "siliconflow", .display = "Siliconflow Turbo 1552", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1553", .provider = "novita", .display = "Novita Instruct 1553", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1554", .provider = "lepton", .display = "Lepton Base 1554", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-1555", .provider = "deepinfra", .display = "Deepinfra Preview 1555", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1556", .provider = "friendli", .display = "Friendli Experimental 1556", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1557", .provider = "hyperbolic", .display = "Hyperbolic Stable 1557", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1558", .provider = "lambda", .display = "Lambda Legacy 1558", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1559", .provider = "nebius", .display = "Nebius Edge 1559", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1560", .provider = "openai", .display = "Openai Chat 1560", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1561", .provider = "anthropic", .display = "Anthropic Code 1561", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-1562", .provider = "google", .display = "Google Reason 1562", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1563", .provider = "groq", .display = "Groq Vision 1563", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1564", .provider = "xai", .display = "Xai Embed 1564", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1565", .provider = "deepseek", .display = "Deepseek Audio 1565", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1566", .provider = "mistral", .display = "Mistral Fast 1566", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1567", .provider = "together", .display = "Together Large 1567", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1568", .provider = "fireworks", .display = "Fireworks Mini 1568", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-1569", .provider = "openrouter", .display = "Openrouter Nano 1569", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1570", .provider = "cerebras", .display = "Cerebras Pro 1570", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1571", .provider = "ollama", .display = "Ollama Ultra 1571", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1572", .provider = "lmstudio", .display = "Lmstudio Turbo 1572", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1573", .provider = "vllm", .display = "Vllm Instruct 1573", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1574", .provider = "azure", .display = "Azure Base 1574", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1575", .provider = "bedrock", .display = "Bedrock Preview 1575", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-1576", .provider = "vertex", .display = "Vertex Experimental 1576", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1577", .provider = "perplexity", .display = "Perplexity Stable 1577", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1578", .provider = "cohere", .display = "Cohere Legacy 1578", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1579", .provider = "nvidia", .display = "Nvidia Edge 1579", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1580", .provider = "sambanova", .display = "Sambanova Chat 1580", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1581", .provider = "github", .display = "Github Code 1581", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1582", .provider = "huggingface", .display = "Huggingface Reason 1582", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-1583", .provider = "replicate", .display = "Replicate Vision 1583", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1584", .provider = "anyscale", .display = "Anyscale Embed 1584", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1585", .provider = "databricks", .display = "Databricks Audio 1585", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1586", .provider = "moonshot", .display = "Moonshot Fast 1586", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1587", .provider = "qwen", .display = "Qwen Large 1587", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1588", .provider = "minimax", .display = "Minimax Mini 1588", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1589", .provider = "zhipu", .display = "Zhipu Nano 1589", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-1590", .provider = "baichuan", .display = "Baichuan Pro 1590", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1591", .provider = "yi", .display = "Yi Ultra 1591", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1592", .provider = "siliconflow", .display = "Siliconflow Turbo 1592", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1593", .provider = "novita", .display = "Novita Instruct 1593", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1594", .provider = "lepton", .display = "Lepton Base 1594", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1595", .provider = "deepinfra", .display = "Deepinfra Preview 1595", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1596", .provider = "friendli", .display = "Friendli Experimental 1596", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1597", .provider = "hyperbolic", .display = "Hyperbolic Stable 1597", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1598", .provider = "lambda", .display = "Lambda Legacy 1598", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1599", .provider = "nebius", .display = "Nebius Edge 1599", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1500_id() []const u8 {
    return models[0].id;
}
pub fn model_1500_context() u32 {
    return models[0].context_window;
}
pub fn model_1500_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1500_family() []const u8 {
    return models[0].family;
}
pub fn model_1500_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1501_id() []const u8 {
    return models[1].id;
}
pub fn model_1501_context() u32 {
    return models[1].context_window;
}
pub fn model_1501_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1501_family() []const u8 {
    return models[1].family;
}
pub fn model_1501_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1502_id() []const u8 {
    return models[2].id;
}
pub fn model_1502_context() u32 {
    return models[2].context_window;
}
pub fn model_1502_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1502_family() []const u8 {
    return models[2].family;
}
pub fn model_1502_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1503_id() []const u8 {
    return models[3].id;
}
pub fn model_1503_context() u32 {
    return models[3].context_window;
}
pub fn model_1503_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1503_family() []const u8 {
    return models[3].family;
}
pub fn model_1503_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1504_id() []const u8 {
    return models[4].id;
}
pub fn model_1504_context() u32 {
    return models[4].context_window;
}
pub fn model_1504_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1504_family() []const u8 {
    return models[4].family;
}
pub fn model_1504_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1505_id() []const u8 {
    return models[5].id;
}
pub fn model_1505_context() u32 {
    return models[5].context_window;
}
pub fn model_1505_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1505_family() []const u8 {
    return models[5].family;
}
pub fn model_1505_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1506_id() []const u8 {
    return models[6].id;
}
pub fn model_1506_context() u32 {
    return models[6].context_window;
}
pub fn model_1506_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1506_family() []const u8 {
    return models[6].family;
}
pub fn model_1506_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1507_id() []const u8 {
    return models[7].id;
}
pub fn model_1507_context() u32 {
    return models[7].context_window;
}
pub fn model_1507_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1507_family() []const u8 {
    return models[7].family;
}
pub fn model_1507_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1508_id() []const u8 {
    return models[8].id;
}
pub fn model_1508_context() u32 {
    return models[8].context_window;
}
pub fn model_1508_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1508_family() []const u8 {
    return models[8].family;
}
pub fn model_1508_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1509_id() []const u8 {
    return models[9].id;
}
pub fn model_1509_context() u32 {
    return models[9].context_window;
}
pub fn model_1509_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1509_family() []const u8 {
    return models[9].family;
}
pub fn model_1509_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1510_id() []const u8 {
    return models[10].id;
}
pub fn model_1510_context() u32 {
    return models[10].context_window;
}
pub fn model_1510_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1510_family() []const u8 {
    return models[10].family;
}
pub fn model_1510_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1511_id() []const u8 {
    return models[11].id;
}
pub fn model_1511_context() u32 {
    return models[11].context_window;
}
pub fn model_1511_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1511_family() []const u8 {
    return models[11].family;
}
pub fn model_1511_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1512_id() []const u8 {
    return models[12].id;
}
pub fn model_1512_context() u32 {
    return models[12].context_window;
}
pub fn model_1512_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1512_family() []const u8 {
    return models[12].family;
}
pub fn model_1512_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1513_id() []const u8 {
    return models[13].id;
}
pub fn model_1513_context() u32 {
    return models[13].context_window;
}
pub fn model_1513_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1513_family() []const u8 {
    return models[13].family;
}
pub fn model_1513_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1514_id() []const u8 {
    return models[14].id;
}
pub fn model_1514_context() u32 {
    return models[14].context_window;
}
pub fn model_1514_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1514_family() []const u8 {
    return models[14].family;
}
pub fn model_1514_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1515_id() []const u8 {
    return models[15].id;
}
pub fn model_1515_context() u32 {
    return models[15].context_window;
}
pub fn model_1515_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1515_family() []const u8 {
    return models[15].family;
}
pub fn model_1515_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1516_id() []const u8 {
    return models[16].id;
}
pub fn model_1516_context() u32 {
    return models[16].context_window;
}
pub fn model_1516_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1516_family() []const u8 {
    return models[16].family;
}
pub fn model_1516_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1517_id() []const u8 {
    return models[17].id;
}
pub fn model_1517_context() u32 {
    return models[17].context_window;
}
pub fn model_1517_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1517_family() []const u8 {
    return models[17].family;
}
pub fn model_1517_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1518_id() []const u8 {
    return models[18].id;
}
pub fn model_1518_context() u32 {
    return models[18].context_window;
}
pub fn model_1518_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1518_family() []const u8 {
    return models[18].family;
}
pub fn model_1518_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1519_id() []const u8 {
    return models[19].id;
}
pub fn model_1519_context() u32 {
    return models[19].context_window;
}
pub fn model_1519_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1519_family() []const u8 {
    return models[19].family;
}
pub fn model_1519_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1520_id() []const u8 {
    return models[20].id;
}
pub fn model_1520_context() u32 {
    return models[20].context_window;
}
pub fn model_1520_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1520_family() []const u8 {
    return models[20].family;
}
pub fn model_1520_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1521_id() []const u8 {
    return models[21].id;
}
pub fn model_1521_context() u32 {
    return models[21].context_window;
}
pub fn model_1521_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1521_family() []const u8 {
    return models[21].family;
}
pub fn model_1521_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1522_id() []const u8 {
    return models[22].id;
}
pub fn model_1522_context() u32 {
    return models[22].context_window;
}
pub fn model_1522_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1522_family() []const u8 {
    return models[22].family;
}
pub fn model_1522_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1523_id() []const u8 {
    return models[23].id;
}
pub fn model_1523_context() u32 {
    return models[23].context_window;
}
pub fn model_1523_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1523_family() []const u8 {
    return models[23].family;
}
pub fn model_1523_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1524_id() []const u8 {
    return models[24].id;
}
pub fn model_1524_context() u32 {
    return models[24].context_window;
}
pub fn model_1524_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1524_family() []const u8 {
    return models[24].family;
}
pub fn model_1524_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1525_id() []const u8 {
    return models[25].id;
}
pub fn model_1525_context() u32 {
    return models[25].context_window;
}
pub fn model_1525_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1525_family() []const u8 {
    return models[25].family;
}
pub fn model_1525_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1526_id() []const u8 {
    return models[26].id;
}
pub fn model_1526_context() u32 {
    return models[26].context_window;
}
pub fn model_1526_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1526_family() []const u8 {
    return models[26].family;
}
pub fn model_1526_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1527_id() []const u8 {
    return models[27].id;
}
pub fn model_1527_context() u32 {
    return models[27].context_window;
}
pub fn model_1527_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1527_family() []const u8 {
    return models[27].family;
}
pub fn model_1527_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1528_id() []const u8 {
    return models[28].id;
}
pub fn model_1528_context() u32 {
    return models[28].context_window;
}
pub fn model_1528_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1528_family() []const u8 {
    return models[28].family;
}
pub fn model_1528_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1529_id() []const u8 {
    return models[29].id;
}
pub fn model_1529_context() u32 {
    return models[29].context_window;
}
pub fn model_1529_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1529_family() []const u8 {
    return models[29].family;
}
pub fn model_1529_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1530_id() []const u8 {
    return models[30].id;
}
pub fn model_1530_context() u32 {
    return models[30].context_window;
}
pub fn model_1530_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1530_family() []const u8 {
    return models[30].family;
}
pub fn model_1530_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1531_id() []const u8 {
    return models[31].id;
}
pub fn model_1531_context() u32 {
    return models[31].context_window;
}
pub fn model_1531_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1531_family() []const u8 {
    return models[31].family;
}
pub fn model_1531_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1532_id() []const u8 {
    return models[32].id;
}
pub fn model_1532_context() u32 {
    return models[32].context_window;
}
pub fn model_1532_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1532_family() []const u8 {
    return models[32].family;
}
pub fn model_1532_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1533_id() []const u8 {
    return models[33].id;
}
pub fn model_1533_context() u32 {
    return models[33].context_window;
}
pub fn model_1533_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1533_family() []const u8 {
    return models[33].family;
}
pub fn model_1533_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1534_id() []const u8 {
    return models[34].id;
}
pub fn model_1534_context() u32 {
    return models[34].context_window;
}
pub fn model_1534_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1534_family() []const u8 {
    return models[34].family;
}
pub fn model_1534_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1535_id() []const u8 {
    return models[35].id;
}
pub fn model_1535_context() u32 {
    return models[35].context_window;
}
pub fn model_1535_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1535_family() []const u8 {
    return models[35].family;
}
pub fn model_1535_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1536_id() []const u8 {
    return models[36].id;
}
pub fn model_1536_context() u32 {
    return models[36].context_window;
}
pub fn model_1536_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1536_family() []const u8 {
    return models[36].family;
}
pub fn model_1536_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1537_id() []const u8 {
    return models[37].id;
}
pub fn model_1537_context() u32 {
    return models[37].context_window;
}
pub fn model_1537_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1537_family() []const u8 {
    return models[37].family;
}
pub fn model_1537_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1538_id() []const u8 {
    return models[38].id;
}
pub fn model_1538_context() u32 {
    return models[38].context_window;
}
pub fn model_1538_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1538_family() []const u8 {
    return models[38].family;
}
pub fn model_1538_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1539_id() []const u8 {
    return models[39].id;
}
pub fn model_1539_context() u32 {
    return models[39].context_window;
}
pub fn model_1539_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1539_family() []const u8 {
    return models[39].family;
}
pub fn model_1539_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1540_id() []const u8 {
    return models[40].id;
}
pub fn model_1540_context() u32 {
    return models[40].context_window;
}
pub fn model_1540_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1540_family() []const u8 {
    return models[40].family;
}
pub fn model_1540_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1541_id() []const u8 {
    return models[41].id;
}
pub fn model_1541_context() u32 {
    return models[41].context_window;
}
pub fn model_1541_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1541_family() []const u8 {
    return models[41].family;
}
pub fn model_1541_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1542_id() []const u8 {
    return models[42].id;
}
pub fn model_1542_context() u32 {
    return models[42].context_window;
}
pub fn model_1542_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1542_family() []const u8 {
    return models[42].family;
}
pub fn model_1542_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1543_id() []const u8 {
    return models[43].id;
}
pub fn model_1543_context() u32 {
    return models[43].context_window;
}
pub fn model_1543_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1543_family() []const u8 {
    return models[43].family;
}
pub fn model_1543_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1544_id() []const u8 {
    return models[44].id;
}
pub fn model_1544_context() u32 {
    return models[44].context_window;
}
pub fn model_1544_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1544_family() []const u8 {
    return models[44].family;
}
pub fn model_1544_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1545_id() []const u8 {
    return models[45].id;
}
pub fn model_1545_context() u32 {
    return models[45].context_window;
}
pub fn model_1545_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1545_family() []const u8 {
    return models[45].family;
}
pub fn model_1545_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1546_id() []const u8 {
    return models[46].id;
}
pub fn model_1546_context() u32 {
    return models[46].context_window;
}
pub fn model_1546_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1546_family() []const u8 {
    return models[46].family;
}
pub fn model_1546_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1547_id() []const u8 {
    return models[47].id;
}
pub fn model_1547_context() u32 {
    return models[47].context_window;
}
pub fn model_1547_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1547_family() []const u8 {
    return models[47].family;
}
pub fn model_1547_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1548_id() []const u8 {
    return models[48].id;
}
pub fn model_1548_context() u32 {
    return models[48].context_window;
}
pub fn model_1548_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1548_family() []const u8 {
    return models[48].family;
}
pub fn model_1548_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1549_id() []const u8 {
    return models[49].id;
}
pub fn model_1549_context() u32 {
    return models[49].context_window;
}
pub fn model_1549_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1549_family() []const u8 {
    return models[49].family;
}
pub fn model_1549_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1550_id() []const u8 {
    return models[50].id;
}
pub fn model_1550_context() u32 {
    return models[50].context_window;
}
pub fn model_1550_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1550_family() []const u8 {
    return models[50].family;
}
pub fn model_1550_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1551_id() []const u8 {
    return models[51].id;
}
pub fn model_1551_context() u32 {
    return models[51].context_window;
}
pub fn model_1551_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1551_family() []const u8 {
    return models[51].family;
}
pub fn model_1551_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1552_id() []const u8 {
    return models[52].id;
}
pub fn model_1552_context() u32 {
    return models[52].context_window;
}
pub fn model_1552_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1552_family() []const u8 {
    return models[52].family;
}
pub fn model_1552_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1553_id() []const u8 {
    return models[53].id;
}
pub fn model_1553_context() u32 {
    return models[53].context_window;
}
pub fn model_1553_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1553_family() []const u8 {
    return models[53].family;
}
pub fn model_1553_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1554_id() []const u8 {
    return models[54].id;
}
pub fn model_1554_context() u32 {
    return models[54].context_window;
}
pub fn model_1554_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1554_family() []const u8 {
    return models[54].family;
}
pub fn model_1554_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1555_id() []const u8 {
    return models[55].id;
}
pub fn model_1555_context() u32 {
    return models[55].context_window;
}
pub fn model_1555_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1555_family() []const u8 {
    return models[55].family;
}
pub fn model_1555_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1556_id() []const u8 {
    return models[56].id;
}
pub fn model_1556_context() u32 {
    return models[56].context_window;
}
pub fn model_1556_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1556_family() []const u8 {
    return models[56].family;
}
pub fn model_1556_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1557_id() []const u8 {
    return models[57].id;
}
pub fn model_1557_context() u32 {
    return models[57].context_window;
}
pub fn model_1557_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1557_family() []const u8 {
    return models[57].family;
}
pub fn model_1557_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1558_id() []const u8 {
    return models[58].id;
}
pub fn model_1558_context() u32 {
    return models[58].context_window;
}
pub fn model_1558_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1558_family() []const u8 {
    return models[58].family;
}
pub fn model_1558_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1559_id() []const u8 {
    return models[59].id;
}
pub fn model_1559_context() u32 {
    return models[59].context_window;
}
pub fn model_1559_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1559_family() []const u8 {
    return models[59].family;
}
pub fn model_1559_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1560_id() []const u8 {
    return models[60].id;
}
pub fn model_1560_context() u32 {
    return models[60].context_window;
}
pub fn model_1560_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1560_family() []const u8 {
    return models[60].family;
}
pub fn model_1560_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1561_id() []const u8 {
    return models[61].id;
}
pub fn model_1561_context() u32 {
    return models[61].context_window;
}
pub fn model_1561_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1561_family() []const u8 {
    return models[61].family;
}
pub fn model_1561_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1562_id() []const u8 {
    return models[62].id;
}
pub fn model_1562_context() u32 {
    return models[62].context_window;
}
pub fn model_1562_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1562_family() []const u8 {
    return models[62].family;
}
pub fn model_1562_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1563_id() []const u8 {
    return models[63].id;
}
pub fn model_1563_context() u32 {
    return models[63].context_window;
}
pub fn model_1563_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1563_family() []const u8 {
    return models[63].family;
}
pub fn model_1563_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1564_id() []const u8 {
    return models[64].id;
}
pub fn model_1564_context() u32 {
    return models[64].context_window;
}
pub fn model_1564_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1564_family() []const u8 {
    return models[64].family;
}
pub fn model_1564_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1565_id() []const u8 {
    return models[65].id;
}
pub fn model_1565_context() u32 {
    return models[65].context_window;
}
pub fn model_1565_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1565_family() []const u8 {
    return models[65].family;
}
pub fn model_1565_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1566_id() []const u8 {
    return models[66].id;
}
pub fn model_1566_context() u32 {
    return models[66].context_window;
}
pub fn model_1566_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1566_family() []const u8 {
    return models[66].family;
}
pub fn model_1566_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1567_id() []const u8 {
    return models[67].id;
}
pub fn model_1567_context() u32 {
    return models[67].context_window;
}
pub fn model_1567_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1567_family() []const u8 {
    return models[67].family;
}
pub fn model_1567_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1568_id() []const u8 {
    return models[68].id;
}
pub fn model_1568_context() u32 {
    return models[68].context_window;
}
pub fn model_1568_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1568_family() []const u8 {
    return models[68].family;
}
pub fn model_1568_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1569_id() []const u8 {
    return models[69].id;
}
pub fn model_1569_context() u32 {
    return models[69].context_window;
}
pub fn model_1569_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1569_family() []const u8 {
    return models[69].family;
}
pub fn model_1569_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1570_id() []const u8 {
    return models[70].id;
}
pub fn model_1570_context() u32 {
    return models[70].context_window;
}
pub fn model_1570_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1570_family() []const u8 {
    return models[70].family;
}
pub fn model_1570_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1571_id() []const u8 {
    return models[71].id;
}
pub fn model_1571_context() u32 {
    return models[71].context_window;
}
pub fn model_1571_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1571_family() []const u8 {
    return models[71].family;
}
pub fn model_1571_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1572_id() []const u8 {
    return models[72].id;
}
pub fn model_1572_context() u32 {
    return models[72].context_window;
}
pub fn model_1572_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1572_family() []const u8 {
    return models[72].family;
}
pub fn model_1572_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1573_id() []const u8 {
    return models[73].id;
}
pub fn model_1573_context() u32 {
    return models[73].context_window;
}
pub fn model_1573_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1573_family() []const u8 {
    return models[73].family;
}
pub fn model_1573_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1574_id() []const u8 {
    return models[74].id;
}
pub fn model_1574_context() u32 {
    return models[74].context_window;
}
pub fn model_1574_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1574_family() []const u8 {
    return models[74].family;
}
pub fn model_1574_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1575_id() []const u8 {
    return models[75].id;
}
pub fn model_1575_context() u32 {
    return models[75].context_window;
}
pub fn model_1575_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1575_family() []const u8 {
    return models[75].family;
}
pub fn model_1575_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1576_id() []const u8 {
    return models[76].id;
}
pub fn model_1576_context() u32 {
    return models[76].context_window;
}
pub fn model_1576_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1576_family() []const u8 {
    return models[76].family;
}
pub fn model_1576_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1577_id() []const u8 {
    return models[77].id;
}
pub fn model_1577_context() u32 {
    return models[77].context_window;
}
pub fn model_1577_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1577_family() []const u8 {
    return models[77].family;
}
pub fn model_1577_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1578_id() []const u8 {
    return models[78].id;
}
pub fn model_1578_context() u32 {
    return models[78].context_window;
}
pub fn model_1578_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1578_family() []const u8 {
    return models[78].family;
}
pub fn model_1578_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1579_id() []const u8 {
    return models[79].id;
}
pub fn model_1579_context() u32 {
    return models[79].context_window;
}
pub fn model_1579_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1579_family() []const u8 {
    return models[79].family;
}
pub fn model_1579_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 15 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

