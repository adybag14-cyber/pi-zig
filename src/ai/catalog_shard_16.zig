//! Generated model catalog shard 16 for package ai.
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

pub const shard_index: u32 = 16;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-1600", .provider = "openai", .display = "Openai Chat 1600", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1601", .provider = "anthropic", .display = "Anthropic Code 1601", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1602", .provider = "google", .display = "Google Reason 1602", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1603", .provider = "groq", .display = "Groq Vision 1603", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-1604", .provider = "xai", .display = "Xai Embed 1604", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1605", .provider = "deepseek", .display = "Deepseek Audio 1605", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1606", .provider = "mistral", .display = "Mistral Fast 1606", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1607", .provider = "together", .display = "Together Large 1607", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1608", .provider = "fireworks", .display = "Fireworks Mini 1608", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1609", .provider = "openrouter", .display = "Openrouter Nano 1609", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1610", .provider = "cerebras", .display = "Cerebras Pro 1610", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-1611", .provider = "ollama", .display = "Ollama Ultra 1611", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1612", .provider = "lmstudio", .display = "Lmstudio Turbo 1612", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1613", .provider = "vllm", .display = "Vllm Instruct 1613", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1614", .provider = "azure", .display = "Azure Base 1614", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1615", .provider = "bedrock", .display = "Bedrock Preview 1615", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1616", .provider = "vertex", .display = "Vertex Experimental 1616", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1617", .provider = "perplexity", .display = "Perplexity Stable 1617", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-1618", .provider = "cohere", .display = "Cohere Legacy 1618", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1619", .provider = "nvidia", .display = "Nvidia Edge 1619", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1620", .provider = "sambanova", .display = "Sambanova Chat 1620", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1621", .provider = "github", .display = "Github Code 1621", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1622", .provider = "huggingface", .display = "Huggingface Reason 1622", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1623", .provider = "replicate", .display = "Replicate Vision 1623", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1624", .provider = "anyscale", .display = "Anyscale Embed 1624", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-1625", .provider = "databricks", .display = "Databricks Audio 1625", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1626", .provider = "moonshot", .display = "Moonshot Fast 1626", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1627", .provider = "qwen", .display = "Qwen Large 1627", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1628", .provider = "minimax", .display = "Minimax Mini 1628", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1629", .provider = "zhipu", .display = "Zhipu Nano 1629", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1630", .provider = "baichuan", .display = "Baichuan Pro 1630", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1631", .provider = "yi", .display = "Yi Ultra 1631", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1632", .provider = "siliconflow", .display = "Siliconflow Turbo 1632", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1633", .provider = "novita", .display = "Novita Instruct 1633", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1634", .provider = "lepton", .display = "Lepton Base 1634", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1635", .provider = "deepinfra", .display = "Deepinfra Preview 1635", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1636", .provider = "friendli", .display = "Friendli Experimental 1636", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1637", .provider = "hyperbolic", .display = "Hyperbolic Stable 1637", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1638", .provider = "lambda", .display = "Lambda Legacy 1638", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-1639", .provider = "nebius", .display = "Nebius Edge 1639", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1640", .provider = "openai", .display = "Openai Chat 1640", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1641", .provider = "anthropic", .display = "Anthropic Code 1641", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1642", .provider = "google", .display = "Google Reason 1642", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1643", .provider = "groq", .display = "Groq Vision 1643", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1644", .provider = "xai", .display = "Xai Embed 1644", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1645", .provider = "deepseek", .display = "Deepseek Audio 1645", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-1646", .provider = "mistral", .display = "Mistral Fast 1646", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1647", .provider = "together", .display = "Together Large 1647", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1648", .provider = "fireworks", .display = "Fireworks Mini 1648", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1649", .provider = "openrouter", .display = "Openrouter Nano 1649", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1650", .provider = "cerebras", .display = "Cerebras Pro 1650", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1651", .provider = "ollama", .display = "Ollama Ultra 1651", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1652", .provider = "lmstudio", .display = "Lmstudio Turbo 1652", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-1653", .provider = "vllm", .display = "Vllm Instruct 1653", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1654", .provider = "azure", .display = "Azure Base 1654", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1655", .provider = "bedrock", .display = "Bedrock Preview 1655", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1656", .provider = "vertex", .display = "Vertex Experimental 1656", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1657", .provider = "perplexity", .display = "Perplexity Stable 1657", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1658", .provider = "cohere", .display = "Cohere Legacy 1658", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1659", .provider = "nvidia", .display = "Nvidia Edge 1659", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-1660", .provider = "sambanova", .display = "Sambanova Chat 1660", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1661", .provider = "github", .display = "Github Code 1661", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1662", .provider = "huggingface", .display = "Huggingface Reason 1662", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1663", .provider = "replicate", .display = "Replicate Vision 1663", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1664", .provider = "anyscale", .display = "Anyscale Embed 1664", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1665", .provider = "databricks", .display = "Databricks Audio 1665", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1666", .provider = "moonshot", .display = "Moonshot Fast 1666", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-1667", .provider = "qwen", .display = "Qwen Large 1667", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1668", .provider = "minimax", .display = "Minimax Mini 1668", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1669", .provider = "zhipu", .display = "Zhipu Nano 1669", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1670", .provider = "baichuan", .display = "Baichuan Pro 1670", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1671", .provider = "yi", .display = "Yi Ultra 1671", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1672", .provider = "siliconflow", .display = "Siliconflow Turbo 1672", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1673", .provider = "novita", .display = "Novita Instruct 1673", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-1674", .provider = "lepton", .display = "Lepton Base 1674", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1675", .provider = "deepinfra", .display = "Deepinfra Preview 1675", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1676", .provider = "friendli", .display = "Friendli Experimental 1676", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1677", .provider = "hyperbolic", .display = "Hyperbolic Stable 1677", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1678", .provider = "lambda", .display = "Lambda Legacy 1678", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1679", .provider = "nebius", .display = "Nebius Edge 1679", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1680", .provider = "openai", .display = "Openai Chat 1680", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-1681", .provider = "anthropic", .display = "Anthropic Code 1681", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1682", .provider = "google", .display = "Google Reason 1682", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1683", .provider = "groq", .display = "Groq Vision 1683", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1684", .provider = "xai", .display = "Xai Embed 1684", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1685", .provider = "deepseek", .display = "Deepseek Audio 1685", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1686", .provider = "mistral", .display = "Mistral Fast 1686", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1687", .provider = "together", .display = "Together Large 1687", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-1688", .provider = "fireworks", .display = "Fireworks Mini 1688", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1689", .provider = "openrouter", .display = "Openrouter Nano 1689", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1690", .provider = "cerebras", .display = "Cerebras Pro 1690", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1691", .provider = "ollama", .display = "Ollama Ultra 1691", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1692", .provider = "lmstudio", .display = "Lmstudio Turbo 1692", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1693", .provider = "vllm", .display = "Vllm Instruct 1693", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1694", .provider = "azure", .display = "Azure Base 1694", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-1695", .provider = "bedrock", .display = "Bedrock Preview 1695", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1696", .provider = "vertex", .display = "Vertex Experimental 1696", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1697", .provider = "perplexity", .display = "Perplexity Stable 1697", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1698", .provider = "cohere", .display = "Cohere Legacy 1698", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1699", .provider = "nvidia", .display = "Nvidia Edge 1699", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1600_id() []const u8 {
    return models[0].id;
}
pub fn model_1600_context() u32 {
    return models[0].context_window;
}
pub fn model_1600_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1600_family() []const u8 {
    return models[0].family;
}
pub fn model_1600_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1601_id() []const u8 {
    return models[1].id;
}
pub fn model_1601_context() u32 {
    return models[1].context_window;
}
pub fn model_1601_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1601_family() []const u8 {
    return models[1].family;
}
pub fn model_1601_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1602_id() []const u8 {
    return models[2].id;
}
pub fn model_1602_context() u32 {
    return models[2].context_window;
}
pub fn model_1602_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1602_family() []const u8 {
    return models[2].family;
}
pub fn model_1602_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1603_id() []const u8 {
    return models[3].id;
}
pub fn model_1603_context() u32 {
    return models[3].context_window;
}
pub fn model_1603_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1603_family() []const u8 {
    return models[3].family;
}
pub fn model_1603_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1604_id() []const u8 {
    return models[4].id;
}
pub fn model_1604_context() u32 {
    return models[4].context_window;
}
pub fn model_1604_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1604_family() []const u8 {
    return models[4].family;
}
pub fn model_1604_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1605_id() []const u8 {
    return models[5].id;
}
pub fn model_1605_context() u32 {
    return models[5].context_window;
}
pub fn model_1605_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1605_family() []const u8 {
    return models[5].family;
}
pub fn model_1605_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1606_id() []const u8 {
    return models[6].id;
}
pub fn model_1606_context() u32 {
    return models[6].context_window;
}
pub fn model_1606_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1606_family() []const u8 {
    return models[6].family;
}
pub fn model_1606_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1607_id() []const u8 {
    return models[7].id;
}
pub fn model_1607_context() u32 {
    return models[7].context_window;
}
pub fn model_1607_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1607_family() []const u8 {
    return models[7].family;
}
pub fn model_1607_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1608_id() []const u8 {
    return models[8].id;
}
pub fn model_1608_context() u32 {
    return models[8].context_window;
}
pub fn model_1608_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1608_family() []const u8 {
    return models[8].family;
}
pub fn model_1608_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1609_id() []const u8 {
    return models[9].id;
}
pub fn model_1609_context() u32 {
    return models[9].context_window;
}
pub fn model_1609_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1609_family() []const u8 {
    return models[9].family;
}
pub fn model_1609_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1610_id() []const u8 {
    return models[10].id;
}
pub fn model_1610_context() u32 {
    return models[10].context_window;
}
pub fn model_1610_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1610_family() []const u8 {
    return models[10].family;
}
pub fn model_1610_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1611_id() []const u8 {
    return models[11].id;
}
pub fn model_1611_context() u32 {
    return models[11].context_window;
}
pub fn model_1611_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1611_family() []const u8 {
    return models[11].family;
}
pub fn model_1611_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1612_id() []const u8 {
    return models[12].id;
}
pub fn model_1612_context() u32 {
    return models[12].context_window;
}
pub fn model_1612_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1612_family() []const u8 {
    return models[12].family;
}
pub fn model_1612_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1613_id() []const u8 {
    return models[13].id;
}
pub fn model_1613_context() u32 {
    return models[13].context_window;
}
pub fn model_1613_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1613_family() []const u8 {
    return models[13].family;
}
pub fn model_1613_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1614_id() []const u8 {
    return models[14].id;
}
pub fn model_1614_context() u32 {
    return models[14].context_window;
}
pub fn model_1614_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1614_family() []const u8 {
    return models[14].family;
}
pub fn model_1614_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1615_id() []const u8 {
    return models[15].id;
}
pub fn model_1615_context() u32 {
    return models[15].context_window;
}
pub fn model_1615_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1615_family() []const u8 {
    return models[15].family;
}
pub fn model_1615_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1616_id() []const u8 {
    return models[16].id;
}
pub fn model_1616_context() u32 {
    return models[16].context_window;
}
pub fn model_1616_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1616_family() []const u8 {
    return models[16].family;
}
pub fn model_1616_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1617_id() []const u8 {
    return models[17].id;
}
pub fn model_1617_context() u32 {
    return models[17].context_window;
}
pub fn model_1617_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1617_family() []const u8 {
    return models[17].family;
}
pub fn model_1617_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1618_id() []const u8 {
    return models[18].id;
}
pub fn model_1618_context() u32 {
    return models[18].context_window;
}
pub fn model_1618_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1618_family() []const u8 {
    return models[18].family;
}
pub fn model_1618_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1619_id() []const u8 {
    return models[19].id;
}
pub fn model_1619_context() u32 {
    return models[19].context_window;
}
pub fn model_1619_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1619_family() []const u8 {
    return models[19].family;
}
pub fn model_1619_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1620_id() []const u8 {
    return models[20].id;
}
pub fn model_1620_context() u32 {
    return models[20].context_window;
}
pub fn model_1620_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1620_family() []const u8 {
    return models[20].family;
}
pub fn model_1620_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1621_id() []const u8 {
    return models[21].id;
}
pub fn model_1621_context() u32 {
    return models[21].context_window;
}
pub fn model_1621_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1621_family() []const u8 {
    return models[21].family;
}
pub fn model_1621_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1622_id() []const u8 {
    return models[22].id;
}
pub fn model_1622_context() u32 {
    return models[22].context_window;
}
pub fn model_1622_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1622_family() []const u8 {
    return models[22].family;
}
pub fn model_1622_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1623_id() []const u8 {
    return models[23].id;
}
pub fn model_1623_context() u32 {
    return models[23].context_window;
}
pub fn model_1623_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1623_family() []const u8 {
    return models[23].family;
}
pub fn model_1623_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1624_id() []const u8 {
    return models[24].id;
}
pub fn model_1624_context() u32 {
    return models[24].context_window;
}
pub fn model_1624_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1624_family() []const u8 {
    return models[24].family;
}
pub fn model_1624_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1625_id() []const u8 {
    return models[25].id;
}
pub fn model_1625_context() u32 {
    return models[25].context_window;
}
pub fn model_1625_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1625_family() []const u8 {
    return models[25].family;
}
pub fn model_1625_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1626_id() []const u8 {
    return models[26].id;
}
pub fn model_1626_context() u32 {
    return models[26].context_window;
}
pub fn model_1626_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1626_family() []const u8 {
    return models[26].family;
}
pub fn model_1626_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1627_id() []const u8 {
    return models[27].id;
}
pub fn model_1627_context() u32 {
    return models[27].context_window;
}
pub fn model_1627_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1627_family() []const u8 {
    return models[27].family;
}
pub fn model_1627_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1628_id() []const u8 {
    return models[28].id;
}
pub fn model_1628_context() u32 {
    return models[28].context_window;
}
pub fn model_1628_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1628_family() []const u8 {
    return models[28].family;
}
pub fn model_1628_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1629_id() []const u8 {
    return models[29].id;
}
pub fn model_1629_context() u32 {
    return models[29].context_window;
}
pub fn model_1629_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1629_family() []const u8 {
    return models[29].family;
}
pub fn model_1629_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1630_id() []const u8 {
    return models[30].id;
}
pub fn model_1630_context() u32 {
    return models[30].context_window;
}
pub fn model_1630_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1630_family() []const u8 {
    return models[30].family;
}
pub fn model_1630_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1631_id() []const u8 {
    return models[31].id;
}
pub fn model_1631_context() u32 {
    return models[31].context_window;
}
pub fn model_1631_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1631_family() []const u8 {
    return models[31].family;
}
pub fn model_1631_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1632_id() []const u8 {
    return models[32].id;
}
pub fn model_1632_context() u32 {
    return models[32].context_window;
}
pub fn model_1632_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1632_family() []const u8 {
    return models[32].family;
}
pub fn model_1632_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1633_id() []const u8 {
    return models[33].id;
}
pub fn model_1633_context() u32 {
    return models[33].context_window;
}
pub fn model_1633_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1633_family() []const u8 {
    return models[33].family;
}
pub fn model_1633_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1634_id() []const u8 {
    return models[34].id;
}
pub fn model_1634_context() u32 {
    return models[34].context_window;
}
pub fn model_1634_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1634_family() []const u8 {
    return models[34].family;
}
pub fn model_1634_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1635_id() []const u8 {
    return models[35].id;
}
pub fn model_1635_context() u32 {
    return models[35].context_window;
}
pub fn model_1635_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1635_family() []const u8 {
    return models[35].family;
}
pub fn model_1635_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1636_id() []const u8 {
    return models[36].id;
}
pub fn model_1636_context() u32 {
    return models[36].context_window;
}
pub fn model_1636_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1636_family() []const u8 {
    return models[36].family;
}
pub fn model_1636_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1637_id() []const u8 {
    return models[37].id;
}
pub fn model_1637_context() u32 {
    return models[37].context_window;
}
pub fn model_1637_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1637_family() []const u8 {
    return models[37].family;
}
pub fn model_1637_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1638_id() []const u8 {
    return models[38].id;
}
pub fn model_1638_context() u32 {
    return models[38].context_window;
}
pub fn model_1638_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1638_family() []const u8 {
    return models[38].family;
}
pub fn model_1638_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1639_id() []const u8 {
    return models[39].id;
}
pub fn model_1639_context() u32 {
    return models[39].context_window;
}
pub fn model_1639_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1639_family() []const u8 {
    return models[39].family;
}
pub fn model_1639_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1640_id() []const u8 {
    return models[40].id;
}
pub fn model_1640_context() u32 {
    return models[40].context_window;
}
pub fn model_1640_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1640_family() []const u8 {
    return models[40].family;
}
pub fn model_1640_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1641_id() []const u8 {
    return models[41].id;
}
pub fn model_1641_context() u32 {
    return models[41].context_window;
}
pub fn model_1641_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1641_family() []const u8 {
    return models[41].family;
}
pub fn model_1641_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1642_id() []const u8 {
    return models[42].id;
}
pub fn model_1642_context() u32 {
    return models[42].context_window;
}
pub fn model_1642_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1642_family() []const u8 {
    return models[42].family;
}
pub fn model_1642_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1643_id() []const u8 {
    return models[43].id;
}
pub fn model_1643_context() u32 {
    return models[43].context_window;
}
pub fn model_1643_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1643_family() []const u8 {
    return models[43].family;
}
pub fn model_1643_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1644_id() []const u8 {
    return models[44].id;
}
pub fn model_1644_context() u32 {
    return models[44].context_window;
}
pub fn model_1644_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1644_family() []const u8 {
    return models[44].family;
}
pub fn model_1644_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1645_id() []const u8 {
    return models[45].id;
}
pub fn model_1645_context() u32 {
    return models[45].context_window;
}
pub fn model_1645_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1645_family() []const u8 {
    return models[45].family;
}
pub fn model_1645_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1646_id() []const u8 {
    return models[46].id;
}
pub fn model_1646_context() u32 {
    return models[46].context_window;
}
pub fn model_1646_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1646_family() []const u8 {
    return models[46].family;
}
pub fn model_1646_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1647_id() []const u8 {
    return models[47].id;
}
pub fn model_1647_context() u32 {
    return models[47].context_window;
}
pub fn model_1647_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1647_family() []const u8 {
    return models[47].family;
}
pub fn model_1647_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1648_id() []const u8 {
    return models[48].id;
}
pub fn model_1648_context() u32 {
    return models[48].context_window;
}
pub fn model_1648_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1648_family() []const u8 {
    return models[48].family;
}
pub fn model_1648_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1649_id() []const u8 {
    return models[49].id;
}
pub fn model_1649_context() u32 {
    return models[49].context_window;
}
pub fn model_1649_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1649_family() []const u8 {
    return models[49].family;
}
pub fn model_1649_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1650_id() []const u8 {
    return models[50].id;
}
pub fn model_1650_context() u32 {
    return models[50].context_window;
}
pub fn model_1650_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1650_family() []const u8 {
    return models[50].family;
}
pub fn model_1650_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1651_id() []const u8 {
    return models[51].id;
}
pub fn model_1651_context() u32 {
    return models[51].context_window;
}
pub fn model_1651_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1651_family() []const u8 {
    return models[51].family;
}
pub fn model_1651_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1652_id() []const u8 {
    return models[52].id;
}
pub fn model_1652_context() u32 {
    return models[52].context_window;
}
pub fn model_1652_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1652_family() []const u8 {
    return models[52].family;
}
pub fn model_1652_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1653_id() []const u8 {
    return models[53].id;
}
pub fn model_1653_context() u32 {
    return models[53].context_window;
}
pub fn model_1653_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1653_family() []const u8 {
    return models[53].family;
}
pub fn model_1653_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1654_id() []const u8 {
    return models[54].id;
}
pub fn model_1654_context() u32 {
    return models[54].context_window;
}
pub fn model_1654_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1654_family() []const u8 {
    return models[54].family;
}
pub fn model_1654_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1655_id() []const u8 {
    return models[55].id;
}
pub fn model_1655_context() u32 {
    return models[55].context_window;
}
pub fn model_1655_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1655_family() []const u8 {
    return models[55].family;
}
pub fn model_1655_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1656_id() []const u8 {
    return models[56].id;
}
pub fn model_1656_context() u32 {
    return models[56].context_window;
}
pub fn model_1656_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1656_family() []const u8 {
    return models[56].family;
}
pub fn model_1656_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1657_id() []const u8 {
    return models[57].id;
}
pub fn model_1657_context() u32 {
    return models[57].context_window;
}
pub fn model_1657_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1657_family() []const u8 {
    return models[57].family;
}
pub fn model_1657_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1658_id() []const u8 {
    return models[58].id;
}
pub fn model_1658_context() u32 {
    return models[58].context_window;
}
pub fn model_1658_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1658_family() []const u8 {
    return models[58].family;
}
pub fn model_1658_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1659_id() []const u8 {
    return models[59].id;
}
pub fn model_1659_context() u32 {
    return models[59].context_window;
}
pub fn model_1659_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1659_family() []const u8 {
    return models[59].family;
}
pub fn model_1659_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1660_id() []const u8 {
    return models[60].id;
}
pub fn model_1660_context() u32 {
    return models[60].context_window;
}
pub fn model_1660_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1660_family() []const u8 {
    return models[60].family;
}
pub fn model_1660_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1661_id() []const u8 {
    return models[61].id;
}
pub fn model_1661_context() u32 {
    return models[61].context_window;
}
pub fn model_1661_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1661_family() []const u8 {
    return models[61].family;
}
pub fn model_1661_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1662_id() []const u8 {
    return models[62].id;
}
pub fn model_1662_context() u32 {
    return models[62].context_window;
}
pub fn model_1662_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1662_family() []const u8 {
    return models[62].family;
}
pub fn model_1662_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1663_id() []const u8 {
    return models[63].id;
}
pub fn model_1663_context() u32 {
    return models[63].context_window;
}
pub fn model_1663_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1663_family() []const u8 {
    return models[63].family;
}
pub fn model_1663_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1664_id() []const u8 {
    return models[64].id;
}
pub fn model_1664_context() u32 {
    return models[64].context_window;
}
pub fn model_1664_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1664_family() []const u8 {
    return models[64].family;
}
pub fn model_1664_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1665_id() []const u8 {
    return models[65].id;
}
pub fn model_1665_context() u32 {
    return models[65].context_window;
}
pub fn model_1665_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1665_family() []const u8 {
    return models[65].family;
}
pub fn model_1665_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1666_id() []const u8 {
    return models[66].id;
}
pub fn model_1666_context() u32 {
    return models[66].context_window;
}
pub fn model_1666_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1666_family() []const u8 {
    return models[66].family;
}
pub fn model_1666_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1667_id() []const u8 {
    return models[67].id;
}
pub fn model_1667_context() u32 {
    return models[67].context_window;
}
pub fn model_1667_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1667_family() []const u8 {
    return models[67].family;
}
pub fn model_1667_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1668_id() []const u8 {
    return models[68].id;
}
pub fn model_1668_context() u32 {
    return models[68].context_window;
}
pub fn model_1668_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1668_family() []const u8 {
    return models[68].family;
}
pub fn model_1668_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1669_id() []const u8 {
    return models[69].id;
}
pub fn model_1669_context() u32 {
    return models[69].context_window;
}
pub fn model_1669_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1669_family() []const u8 {
    return models[69].family;
}
pub fn model_1669_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1670_id() []const u8 {
    return models[70].id;
}
pub fn model_1670_context() u32 {
    return models[70].context_window;
}
pub fn model_1670_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1670_family() []const u8 {
    return models[70].family;
}
pub fn model_1670_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1671_id() []const u8 {
    return models[71].id;
}
pub fn model_1671_context() u32 {
    return models[71].context_window;
}
pub fn model_1671_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1671_family() []const u8 {
    return models[71].family;
}
pub fn model_1671_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1672_id() []const u8 {
    return models[72].id;
}
pub fn model_1672_context() u32 {
    return models[72].context_window;
}
pub fn model_1672_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1672_family() []const u8 {
    return models[72].family;
}
pub fn model_1672_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1673_id() []const u8 {
    return models[73].id;
}
pub fn model_1673_context() u32 {
    return models[73].context_window;
}
pub fn model_1673_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1673_family() []const u8 {
    return models[73].family;
}
pub fn model_1673_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1674_id() []const u8 {
    return models[74].id;
}
pub fn model_1674_context() u32 {
    return models[74].context_window;
}
pub fn model_1674_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1674_family() []const u8 {
    return models[74].family;
}
pub fn model_1674_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1675_id() []const u8 {
    return models[75].id;
}
pub fn model_1675_context() u32 {
    return models[75].context_window;
}
pub fn model_1675_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1675_family() []const u8 {
    return models[75].family;
}
pub fn model_1675_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1676_id() []const u8 {
    return models[76].id;
}
pub fn model_1676_context() u32 {
    return models[76].context_window;
}
pub fn model_1676_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1676_family() []const u8 {
    return models[76].family;
}
pub fn model_1676_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1677_id() []const u8 {
    return models[77].id;
}
pub fn model_1677_context() u32 {
    return models[77].context_window;
}
pub fn model_1677_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1677_family() []const u8 {
    return models[77].family;
}
pub fn model_1677_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1678_id() []const u8 {
    return models[78].id;
}
pub fn model_1678_context() u32 {
    return models[78].context_window;
}
pub fn model_1678_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1678_family() []const u8 {
    return models[78].family;
}
pub fn model_1678_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1679_id() []const u8 {
    return models[79].id;
}
pub fn model_1679_context() u32 {
    return models[79].context_window;
}
pub fn model_1679_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1679_family() []const u8 {
    return models[79].family;
}
pub fn model_1679_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 16 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

