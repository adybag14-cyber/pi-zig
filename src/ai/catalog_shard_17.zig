//! Generated model catalog shard 17 for package ai.
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

pub const shard_index: u32 = 17;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-1700", .provider = "sambanova", .display = "Sambanova Chat 1700", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1701", .provider = "github", .display = "Github Code 1701", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-1702", .provider = "huggingface", .display = "Huggingface Reason 1702", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1703", .provider = "replicate", .display = "Replicate Vision 1703", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1704", .provider = "anyscale", .display = "Anyscale Embed 1704", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1705", .provider = "databricks", .display = "Databricks Audio 1705", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1706", .provider = "moonshot", .display = "Moonshot Fast 1706", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1707", .provider = "qwen", .display = "Qwen Large 1707", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1708", .provider = "minimax", .display = "Minimax Mini 1708", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-1709", .provider = "zhipu", .display = "Zhipu Nano 1709", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1710", .provider = "baichuan", .display = "Baichuan Pro 1710", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1711", .provider = "yi", .display = "Yi Ultra 1711", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1712", .provider = "siliconflow", .display = "Siliconflow Turbo 1712", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1713", .provider = "novita", .display = "Novita Instruct 1713", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1714", .provider = "lepton", .display = "Lepton Base 1714", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1715", .provider = "deepinfra", .display = "Deepinfra Preview 1715", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-1716", .provider = "friendli", .display = "Friendli Experimental 1716", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1717", .provider = "hyperbolic", .display = "Hyperbolic Stable 1717", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1718", .provider = "lambda", .display = "Lambda Legacy 1718", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1719", .provider = "nebius", .display = "Nebius Edge 1719", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1720", .provider = "openai", .display = "Openai Chat 1720", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1721", .provider = "anthropic", .display = "Anthropic Code 1721", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1722", .provider = "google", .display = "Google Reason 1722", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-1723", .provider = "groq", .display = "Groq Vision 1723", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1724", .provider = "xai", .display = "Xai Embed 1724", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1725", .provider = "deepseek", .display = "Deepseek Audio 1725", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1726", .provider = "mistral", .display = "Mistral Fast 1726", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1727", .provider = "together", .display = "Together Large 1727", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1728", .provider = "fireworks", .display = "Fireworks Mini 1728", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1729", .provider = "openrouter", .display = "Openrouter Nano 1729", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-1730", .provider = "cerebras", .display = "Cerebras Pro 1730", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1731", .provider = "ollama", .display = "Ollama Ultra 1731", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1732", .provider = "lmstudio", .display = "Lmstudio Turbo 1732", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1733", .provider = "vllm", .display = "Vllm Instruct 1733", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1734", .provider = "azure", .display = "Azure Base 1734", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1735", .provider = "bedrock", .display = "Bedrock Preview 1735", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1736", .provider = "vertex", .display = "Vertex Experimental 1736", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-1737", .provider = "perplexity", .display = "Perplexity Stable 1737", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1738", .provider = "cohere", .display = "Cohere Legacy 1738", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1739", .provider = "nvidia", .display = "Nvidia Edge 1739", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1740", .provider = "sambanova", .display = "Sambanova Chat 1740", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1741", .provider = "github", .display = "Github Code 1741", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1742", .provider = "huggingface", .display = "Huggingface Reason 1742", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1743", .provider = "replicate", .display = "Replicate Vision 1743", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-1744", .provider = "anyscale", .display = "Anyscale Embed 1744", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1745", .provider = "databricks", .display = "Databricks Audio 1745", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1746", .provider = "moonshot", .display = "Moonshot Fast 1746", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1747", .provider = "qwen", .display = "Qwen Large 1747", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1748", .provider = "minimax", .display = "Minimax Mini 1748", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1749", .provider = "zhipu", .display = "Zhipu Nano 1749", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1750", .provider = "baichuan", .display = "Baichuan Pro 1750", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-1751", .provider = "yi", .display = "Yi Ultra 1751", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1752", .provider = "siliconflow", .display = "Siliconflow Turbo 1752", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1753", .provider = "novita", .display = "Novita Instruct 1753", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1754", .provider = "lepton", .display = "Lepton Base 1754", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1755", .provider = "deepinfra", .display = "Deepinfra Preview 1755", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1756", .provider = "friendli", .display = "Friendli Experimental 1756", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1757", .provider = "hyperbolic", .display = "Hyperbolic Stable 1757", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-1758", .provider = "lambda", .display = "Lambda Legacy 1758", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1759", .provider = "nebius", .display = "Nebius Edge 1759", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1760", .provider = "openai", .display = "Openai Chat 1760", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1761", .provider = "anthropic", .display = "Anthropic Code 1761", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1762", .provider = "google", .display = "Google Reason 1762", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1763", .provider = "groq", .display = "Groq Vision 1763", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1764", .provider = "xai", .display = "Xai Embed 1764", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-1765", .provider = "deepseek", .display = "Deepseek Audio 1765", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1766", .provider = "mistral", .display = "Mistral Fast 1766", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1767", .provider = "together", .display = "Together Large 1767", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1768", .provider = "fireworks", .display = "Fireworks Mini 1768", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1769", .provider = "openrouter", .display = "Openrouter Nano 1769", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1770", .provider = "cerebras", .display = "Cerebras Pro 1770", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1771", .provider = "ollama", .display = "Ollama Ultra 1771", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1772", .provider = "lmstudio", .display = "Lmstudio Turbo 1772", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1773", .provider = "vllm", .display = "Vllm Instruct 1773", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1774", .provider = "azure", .display = "Azure Base 1774", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1775", .provider = "bedrock", .display = "Bedrock Preview 1775", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1776", .provider = "vertex", .display = "Vertex Experimental 1776", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1777", .provider = "perplexity", .display = "Perplexity Stable 1777", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1778", .provider = "cohere", .display = "Cohere Legacy 1778", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-1779", .provider = "nvidia", .display = "Nvidia Edge 1779", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1780", .provider = "sambanova", .display = "Sambanova Chat 1780", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1781", .provider = "github", .display = "Github Code 1781", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1782", .provider = "huggingface", .display = "Huggingface Reason 1782", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1783", .provider = "replicate", .display = "Replicate Vision 1783", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1784", .provider = "anyscale", .display = "Anyscale Embed 1784", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1785", .provider = "databricks", .display = "Databricks Audio 1785", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-1786", .provider = "moonshot", .display = "Moonshot Fast 1786", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1787", .provider = "qwen", .display = "Qwen Large 1787", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1788", .provider = "minimax", .display = "Minimax Mini 1788", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1789", .provider = "zhipu", .display = "Zhipu Nano 1789", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1790", .provider = "baichuan", .display = "Baichuan Pro 1790", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1791", .provider = "yi", .display = "Yi Ultra 1791", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1792", .provider = "siliconflow", .display = "Siliconflow Turbo 1792", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-1793", .provider = "novita", .display = "Novita Instruct 1793", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1794", .provider = "lepton", .display = "Lepton Base 1794", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1795", .provider = "deepinfra", .display = "Deepinfra Preview 1795", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1796", .provider = "friendli", .display = "Friendli Experimental 1796", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1797", .provider = "hyperbolic", .display = "Hyperbolic Stable 1797", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1798", .provider = "lambda", .display = "Lambda Legacy 1798", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1799", .provider = "nebius", .display = "Nebius Edge 1799", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
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

pub fn model_1700_id() []const u8 {
    return models[0].id;
}
pub fn model_1700_context() u32 {
    return models[0].context_window;
}
pub fn model_1700_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1700_family() []const u8 {
    return models[0].family;
}
pub fn model_1700_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1701_id() []const u8 {
    return models[1].id;
}
pub fn model_1701_context() u32 {
    return models[1].context_window;
}
pub fn model_1701_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1701_family() []const u8 {
    return models[1].family;
}
pub fn model_1701_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1702_id() []const u8 {
    return models[2].id;
}
pub fn model_1702_context() u32 {
    return models[2].context_window;
}
pub fn model_1702_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1702_family() []const u8 {
    return models[2].family;
}
pub fn model_1702_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1703_id() []const u8 {
    return models[3].id;
}
pub fn model_1703_context() u32 {
    return models[3].context_window;
}
pub fn model_1703_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1703_family() []const u8 {
    return models[3].family;
}
pub fn model_1703_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1704_id() []const u8 {
    return models[4].id;
}
pub fn model_1704_context() u32 {
    return models[4].context_window;
}
pub fn model_1704_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1704_family() []const u8 {
    return models[4].family;
}
pub fn model_1704_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1705_id() []const u8 {
    return models[5].id;
}
pub fn model_1705_context() u32 {
    return models[5].context_window;
}
pub fn model_1705_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1705_family() []const u8 {
    return models[5].family;
}
pub fn model_1705_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1706_id() []const u8 {
    return models[6].id;
}
pub fn model_1706_context() u32 {
    return models[6].context_window;
}
pub fn model_1706_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1706_family() []const u8 {
    return models[6].family;
}
pub fn model_1706_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1707_id() []const u8 {
    return models[7].id;
}
pub fn model_1707_context() u32 {
    return models[7].context_window;
}
pub fn model_1707_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1707_family() []const u8 {
    return models[7].family;
}
pub fn model_1707_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1708_id() []const u8 {
    return models[8].id;
}
pub fn model_1708_context() u32 {
    return models[8].context_window;
}
pub fn model_1708_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1708_family() []const u8 {
    return models[8].family;
}
pub fn model_1708_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1709_id() []const u8 {
    return models[9].id;
}
pub fn model_1709_context() u32 {
    return models[9].context_window;
}
pub fn model_1709_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1709_family() []const u8 {
    return models[9].family;
}
pub fn model_1709_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1710_id() []const u8 {
    return models[10].id;
}
pub fn model_1710_context() u32 {
    return models[10].context_window;
}
pub fn model_1710_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1710_family() []const u8 {
    return models[10].family;
}
pub fn model_1710_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1711_id() []const u8 {
    return models[11].id;
}
pub fn model_1711_context() u32 {
    return models[11].context_window;
}
pub fn model_1711_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1711_family() []const u8 {
    return models[11].family;
}
pub fn model_1711_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1712_id() []const u8 {
    return models[12].id;
}
pub fn model_1712_context() u32 {
    return models[12].context_window;
}
pub fn model_1712_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1712_family() []const u8 {
    return models[12].family;
}
pub fn model_1712_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1713_id() []const u8 {
    return models[13].id;
}
pub fn model_1713_context() u32 {
    return models[13].context_window;
}
pub fn model_1713_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1713_family() []const u8 {
    return models[13].family;
}
pub fn model_1713_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1714_id() []const u8 {
    return models[14].id;
}
pub fn model_1714_context() u32 {
    return models[14].context_window;
}
pub fn model_1714_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1714_family() []const u8 {
    return models[14].family;
}
pub fn model_1714_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1715_id() []const u8 {
    return models[15].id;
}
pub fn model_1715_context() u32 {
    return models[15].context_window;
}
pub fn model_1715_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1715_family() []const u8 {
    return models[15].family;
}
pub fn model_1715_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1716_id() []const u8 {
    return models[16].id;
}
pub fn model_1716_context() u32 {
    return models[16].context_window;
}
pub fn model_1716_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1716_family() []const u8 {
    return models[16].family;
}
pub fn model_1716_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1717_id() []const u8 {
    return models[17].id;
}
pub fn model_1717_context() u32 {
    return models[17].context_window;
}
pub fn model_1717_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1717_family() []const u8 {
    return models[17].family;
}
pub fn model_1717_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1718_id() []const u8 {
    return models[18].id;
}
pub fn model_1718_context() u32 {
    return models[18].context_window;
}
pub fn model_1718_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1718_family() []const u8 {
    return models[18].family;
}
pub fn model_1718_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1719_id() []const u8 {
    return models[19].id;
}
pub fn model_1719_context() u32 {
    return models[19].context_window;
}
pub fn model_1719_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1719_family() []const u8 {
    return models[19].family;
}
pub fn model_1719_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1720_id() []const u8 {
    return models[20].id;
}
pub fn model_1720_context() u32 {
    return models[20].context_window;
}
pub fn model_1720_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1720_family() []const u8 {
    return models[20].family;
}
pub fn model_1720_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1721_id() []const u8 {
    return models[21].id;
}
pub fn model_1721_context() u32 {
    return models[21].context_window;
}
pub fn model_1721_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1721_family() []const u8 {
    return models[21].family;
}
pub fn model_1721_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1722_id() []const u8 {
    return models[22].id;
}
pub fn model_1722_context() u32 {
    return models[22].context_window;
}
pub fn model_1722_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1722_family() []const u8 {
    return models[22].family;
}
pub fn model_1722_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1723_id() []const u8 {
    return models[23].id;
}
pub fn model_1723_context() u32 {
    return models[23].context_window;
}
pub fn model_1723_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1723_family() []const u8 {
    return models[23].family;
}
pub fn model_1723_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1724_id() []const u8 {
    return models[24].id;
}
pub fn model_1724_context() u32 {
    return models[24].context_window;
}
pub fn model_1724_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1724_family() []const u8 {
    return models[24].family;
}
pub fn model_1724_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1725_id() []const u8 {
    return models[25].id;
}
pub fn model_1725_context() u32 {
    return models[25].context_window;
}
pub fn model_1725_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1725_family() []const u8 {
    return models[25].family;
}
pub fn model_1725_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1726_id() []const u8 {
    return models[26].id;
}
pub fn model_1726_context() u32 {
    return models[26].context_window;
}
pub fn model_1726_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1726_family() []const u8 {
    return models[26].family;
}
pub fn model_1726_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1727_id() []const u8 {
    return models[27].id;
}
pub fn model_1727_context() u32 {
    return models[27].context_window;
}
pub fn model_1727_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1727_family() []const u8 {
    return models[27].family;
}
pub fn model_1727_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1728_id() []const u8 {
    return models[28].id;
}
pub fn model_1728_context() u32 {
    return models[28].context_window;
}
pub fn model_1728_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1728_family() []const u8 {
    return models[28].family;
}
pub fn model_1728_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1729_id() []const u8 {
    return models[29].id;
}
pub fn model_1729_context() u32 {
    return models[29].context_window;
}
pub fn model_1729_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1729_family() []const u8 {
    return models[29].family;
}
pub fn model_1729_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1730_id() []const u8 {
    return models[30].id;
}
pub fn model_1730_context() u32 {
    return models[30].context_window;
}
pub fn model_1730_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1730_family() []const u8 {
    return models[30].family;
}
pub fn model_1730_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1731_id() []const u8 {
    return models[31].id;
}
pub fn model_1731_context() u32 {
    return models[31].context_window;
}
pub fn model_1731_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1731_family() []const u8 {
    return models[31].family;
}
pub fn model_1731_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1732_id() []const u8 {
    return models[32].id;
}
pub fn model_1732_context() u32 {
    return models[32].context_window;
}
pub fn model_1732_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1732_family() []const u8 {
    return models[32].family;
}
pub fn model_1732_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1733_id() []const u8 {
    return models[33].id;
}
pub fn model_1733_context() u32 {
    return models[33].context_window;
}
pub fn model_1733_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1733_family() []const u8 {
    return models[33].family;
}
pub fn model_1733_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1734_id() []const u8 {
    return models[34].id;
}
pub fn model_1734_context() u32 {
    return models[34].context_window;
}
pub fn model_1734_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1734_family() []const u8 {
    return models[34].family;
}
pub fn model_1734_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1735_id() []const u8 {
    return models[35].id;
}
pub fn model_1735_context() u32 {
    return models[35].context_window;
}
pub fn model_1735_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1735_family() []const u8 {
    return models[35].family;
}
pub fn model_1735_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1736_id() []const u8 {
    return models[36].id;
}
pub fn model_1736_context() u32 {
    return models[36].context_window;
}
pub fn model_1736_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1736_family() []const u8 {
    return models[36].family;
}
pub fn model_1736_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1737_id() []const u8 {
    return models[37].id;
}
pub fn model_1737_context() u32 {
    return models[37].context_window;
}
pub fn model_1737_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1737_family() []const u8 {
    return models[37].family;
}
pub fn model_1737_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1738_id() []const u8 {
    return models[38].id;
}
pub fn model_1738_context() u32 {
    return models[38].context_window;
}
pub fn model_1738_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1738_family() []const u8 {
    return models[38].family;
}
pub fn model_1738_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1739_id() []const u8 {
    return models[39].id;
}
pub fn model_1739_context() u32 {
    return models[39].context_window;
}
pub fn model_1739_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1739_family() []const u8 {
    return models[39].family;
}
pub fn model_1739_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1740_id() []const u8 {
    return models[40].id;
}
pub fn model_1740_context() u32 {
    return models[40].context_window;
}
pub fn model_1740_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1740_family() []const u8 {
    return models[40].family;
}
pub fn model_1740_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1741_id() []const u8 {
    return models[41].id;
}
pub fn model_1741_context() u32 {
    return models[41].context_window;
}
pub fn model_1741_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1741_family() []const u8 {
    return models[41].family;
}
pub fn model_1741_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1742_id() []const u8 {
    return models[42].id;
}
pub fn model_1742_context() u32 {
    return models[42].context_window;
}
pub fn model_1742_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1742_family() []const u8 {
    return models[42].family;
}
pub fn model_1742_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1743_id() []const u8 {
    return models[43].id;
}
pub fn model_1743_context() u32 {
    return models[43].context_window;
}
pub fn model_1743_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1743_family() []const u8 {
    return models[43].family;
}
pub fn model_1743_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1744_id() []const u8 {
    return models[44].id;
}
pub fn model_1744_context() u32 {
    return models[44].context_window;
}
pub fn model_1744_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1744_family() []const u8 {
    return models[44].family;
}
pub fn model_1744_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1745_id() []const u8 {
    return models[45].id;
}
pub fn model_1745_context() u32 {
    return models[45].context_window;
}
pub fn model_1745_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1745_family() []const u8 {
    return models[45].family;
}
pub fn model_1745_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1746_id() []const u8 {
    return models[46].id;
}
pub fn model_1746_context() u32 {
    return models[46].context_window;
}
pub fn model_1746_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1746_family() []const u8 {
    return models[46].family;
}
pub fn model_1746_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1747_id() []const u8 {
    return models[47].id;
}
pub fn model_1747_context() u32 {
    return models[47].context_window;
}
pub fn model_1747_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1747_family() []const u8 {
    return models[47].family;
}
pub fn model_1747_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1748_id() []const u8 {
    return models[48].id;
}
pub fn model_1748_context() u32 {
    return models[48].context_window;
}
pub fn model_1748_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1748_family() []const u8 {
    return models[48].family;
}
pub fn model_1748_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1749_id() []const u8 {
    return models[49].id;
}
pub fn model_1749_context() u32 {
    return models[49].context_window;
}
pub fn model_1749_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1749_family() []const u8 {
    return models[49].family;
}
pub fn model_1749_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1750_id() []const u8 {
    return models[50].id;
}
pub fn model_1750_context() u32 {
    return models[50].context_window;
}
pub fn model_1750_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1750_family() []const u8 {
    return models[50].family;
}
pub fn model_1750_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1751_id() []const u8 {
    return models[51].id;
}
pub fn model_1751_context() u32 {
    return models[51].context_window;
}
pub fn model_1751_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1751_family() []const u8 {
    return models[51].family;
}
pub fn model_1751_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1752_id() []const u8 {
    return models[52].id;
}
pub fn model_1752_context() u32 {
    return models[52].context_window;
}
pub fn model_1752_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1752_family() []const u8 {
    return models[52].family;
}
pub fn model_1752_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1753_id() []const u8 {
    return models[53].id;
}
pub fn model_1753_context() u32 {
    return models[53].context_window;
}
pub fn model_1753_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1753_family() []const u8 {
    return models[53].family;
}
pub fn model_1753_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1754_id() []const u8 {
    return models[54].id;
}
pub fn model_1754_context() u32 {
    return models[54].context_window;
}
pub fn model_1754_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1754_family() []const u8 {
    return models[54].family;
}
pub fn model_1754_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1755_id() []const u8 {
    return models[55].id;
}
pub fn model_1755_context() u32 {
    return models[55].context_window;
}
pub fn model_1755_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1755_family() []const u8 {
    return models[55].family;
}
pub fn model_1755_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1756_id() []const u8 {
    return models[56].id;
}
pub fn model_1756_context() u32 {
    return models[56].context_window;
}
pub fn model_1756_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1756_family() []const u8 {
    return models[56].family;
}
pub fn model_1756_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1757_id() []const u8 {
    return models[57].id;
}
pub fn model_1757_context() u32 {
    return models[57].context_window;
}
pub fn model_1757_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1757_family() []const u8 {
    return models[57].family;
}
pub fn model_1757_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1758_id() []const u8 {
    return models[58].id;
}
pub fn model_1758_context() u32 {
    return models[58].context_window;
}
pub fn model_1758_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1758_family() []const u8 {
    return models[58].family;
}
pub fn model_1758_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1759_id() []const u8 {
    return models[59].id;
}
pub fn model_1759_context() u32 {
    return models[59].context_window;
}
pub fn model_1759_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1759_family() []const u8 {
    return models[59].family;
}
pub fn model_1759_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1760_id() []const u8 {
    return models[60].id;
}
pub fn model_1760_context() u32 {
    return models[60].context_window;
}
pub fn model_1760_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1760_family() []const u8 {
    return models[60].family;
}
pub fn model_1760_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1761_id() []const u8 {
    return models[61].id;
}
pub fn model_1761_context() u32 {
    return models[61].context_window;
}
pub fn model_1761_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1761_family() []const u8 {
    return models[61].family;
}
pub fn model_1761_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1762_id() []const u8 {
    return models[62].id;
}
pub fn model_1762_context() u32 {
    return models[62].context_window;
}
pub fn model_1762_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1762_family() []const u8 {
    return models[62].family;
}
pub fn model_1762_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1763_id() []const u8 {
    return models[63].id;
}
pub fn model_1763_context() u32 {
    return models[63].context_window;
}
pub fn model_1763_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1763_family() []const u8 {
    return models[63].family;
}
pub fn model_1763_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1764_id() []const u8 {
    return models[64].id;
}
pub fn model_1764_context() u32 {
    return models[64].context_window;
}
pub fn model_1764_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1764_family() []const u8 {
    return models[64].family;
}
pub fn model_1764_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1765_id() []const u8 {
    return models[65].id;
}
pub fn model_1765_context() u32 {
    return models[65].context_window;
}
pub fn model_1765_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1765_family() []const u8 {
    return models[65].family;
}
pub fn model_1765_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1766_id() []const u8 {
    return models[66].id;
}
pub fn model_1766_context() u32 {
    return models[66].context_window;
}
pub fn model_1766_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1766_family() []const u8 {
    return models[66].family;
}
pub fn model_1766_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1767_id() []const u8 {
    return models[67].id;
}
pub fn model_1767_context() u32 {
    return models[67].context_window;
}
pub fn model_1767_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1767_family() []const u8 {
    return models[67].family;
}
pub fn model_1767_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1768_id() []const u8 {
    return models[68].id;
}
pub fn model_1768_context() u32 {
    return models[68].context_window;
}
pub fn model_1768_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1768_family() []const u8 {
    return models[68].family;
}
pub fn model_1768_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1769_id() []const u8 {
    return models[69].id;
}
pub fn model_1769_context() u32 {
    return models[69].context_window;
}
pub fn model_1769_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1769_family() []const u8 {
    return models[69].family;
}
pub fn model_1769_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1770_id() []const u8 {
    return models[70].id;
}
pub fn model_1770_context() u32 {
    return models[70].context_window;
}
pub fn model_1770_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1770_family() []const u8 {
    return models[70].family;
}
pub fn model_1770_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1771_id() []const u8 {
    return models[71].id;
}
pub fn model_1771_context() u32 {
    return models[71].context_window;
}
pub fn model_1771_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1771_family() []const u8 {
    return models[71].family;
}
pub fn model_1771_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1772_id() []const u8 {
    return models[72].id;
}
pub fn model_1772_context() u32 {
    return models[72].context_window;
}
pub fn model_1772_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1772_family() []const u8 {
    return models[72].family;
}
pub fn model_1772_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1773_id() []const u8 {
    return models[73].id;
}
pub fn model_1773_context() u32 {
    return models[73].context_window;
}
pub fn model_1773_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1773_family() []const u8 {
    return models[73].family;
}
pub fn model_1773_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1774_id() []const u8 {
    return models[74].id;
}
pub fn model_1774_context() u32 {
    return models[74].context_window;
}
pub fn model_1774_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1774_family() []const u8 {
    return models[74].family;
}
pub fn model_1774_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1775_id() []const u8 {
    return models[75].id;
}
pub fn model_1775_context() u32 {
    return models[75].context_window;
}
pub fn model_1775_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1775_family() []const u8 {
    return models[75].family;
}
pub fn model_1775_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1776_id() []const u8 {
    return models[76].id;
}
pub fn model_1776_context() u32 {
    return models[76].context_window;
}
pub fn model_1776_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1776_family() []const u8 {
    return models[76].family;
}
pub fn model_1776_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1777_id() []const u8 {
    return models[77].id;
}
pub fn model_1777_context() u32 {
    return models[77].context_window;
}
pub fn model_1777_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1777_family() []const u8 {
    return models[77].family;
}
pub fn model_1777_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1778_id() []const u8 {
    return models[78].id;
}
pub fn model_1778_context() u32 {
    return models[78].context_window;
}
pub fn model_1778_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1778_family() []const u8 {
    return models[78].family;
}
pub fn model_1778_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1779_id() []const u8 {
    return models[79].id;
}
pub fn model_1779_context() u32 {
    return models[79].context_window;
}
pub fn model_1779_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1779_family() []const u8 {
    return models[79].family;
}
pub fn model_1779_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 17 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

