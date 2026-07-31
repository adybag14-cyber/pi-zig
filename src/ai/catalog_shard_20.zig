//! Generated model catalog shard 20 for package ai.
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

pub const shard_index: u32 = 20;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-2000", .provider = "openai", .display = "Openai Chat 2000", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2001", .provider = "anthropic", .display = "Anthropic Code 2001", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2002", .provider = "google", .display = "Google Reason 2002", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-2003", .provider = "groq", .display = "Groq Vision 2003", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2004", .provider = "xai", .display = "Xai Embed 2004", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2005", .provider = "deepseek", .display = "Deepseek Audio 2005", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2006", .provider = "mistral", .display = "Mistral Fast 2006", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2007", .provider = "together", .display = "Together Large 2007", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2008", .provider = "fireworks", .display = "Fireworks Mini 2008", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2009", .provider = "openrouter", .display = "Openrouter Nano 2009", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-2010", .provider = "cerebras", .display = "Cerebras Pro 2010", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2011", .provider = "ollama", .display = "Ollama Ultra 2011", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2012", .provider = "lmstudio", .display = "Lmstudio Turbo 2012", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2013", .provider = "vllm", .display = "Vllm Instruct 2013", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2014", .provider = "azure", .display = "Azure Base 2014", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2015", .provider = "bedrock", .display = "Bedrock Preview 2015", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2016", .provider = "vertex", .display = "Vertex Experimental 2016", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-2017", .provider = "perplexity", .display = "Perplexity Stable 2017", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2018", .provider = "cohere", .display = "Cohere Legacy 2018", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2019", .provider = "nvidia", .display = "Nvidia Edge 2019", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2020", .provider = "sambanova", .display = "Sambanova Chat 2020", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2021", .provider = "github", .display = "Github Code 2021", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2022", .provider = "huggingface", .display = "Huggingface Reason 2022", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2023", .provider = "replicate", .display = "Replicate Vision 2023", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-2024", .provider = "anyscale", .display = "Anyscale Embed 2024", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2025", .provider = "databricks", .display = "Databricks Audio 2025", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2026", .provider = "moonshot", .display = "Moonshot Fast 2026", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2027", .provider = "qwen", .display = "Qwen Large 2027", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2028", .provider = "minimax", .display = "Minimax Mini 2028", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2029", .provider = "zhipu", .display = "Zhipu Nano 2029", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2030", .provider = "baichuan", .display = "Baichuan Pro 2030", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-2031", .provider = "yi", .display = "Yi Ultra 2031", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2032", .provider = "siliconflow", .display = "Siliconflow Turbo 2032", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2033", .provider = "novita", .display = "Novita Instruct 2033", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2034", .provider = "lepton", .display = "Lepton Base 2034", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2035", .provider = "deepinfra", .display = "Deepinfra Preview 2035", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2036", .provider = "friendli", .display = "Friendli Experimental 2036", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2037", .provider = "hyperbolic", .display = "Hyperbolic Stable 2037", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-2038", .provider = "lambda", .display = "Lambda Legacy 2038", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2039", .provider = "nebius", .display = "Nebius Edge 2039", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2040", .provider = "openai", .display = "Openai Chat 2040", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2041", .provider = "anthropic", .display = "Anthropic Code 2041", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2042", .provider = "google", .display = "Google Reason 2042", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2043", .provider = "groq", .display = "Groq Vision 2043", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2044", .provider = "xai", .display = "Xai Embed 2044", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-2045", .provider = "deepseek", .display = "Deepseek Audio 2045", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2046", .provider = "mistral", .display = "Mistral Fast 2046", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2047", .provider = "together", .display = "Together Large 2047", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2048", .provider = "fireworks", .display = "Fireworks Mini 2048", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2049", .provider = "openrouter", .display = "Openrouter Nano 2049", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2050", .provider = "cerebras", .display = "Cerebras Pro 2050", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2051", .provider = "ollama", .display = "Ollama Ultra 2051", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2052", .provider = "lmstudio", .display = "Lmstudio Turbo 2052", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2053", .provider = "vllm", .display = "Vllm Instruct 2053", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2054", .provider = "azure", .display = "Azure Base 2054", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2055", .provider = "bedrock", .display = "Bedrock Preview 2055", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2056", .provider = "vertex", .display = "Vertex Experimental 2056", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2057", .provider = "perplexity", .display = "Perplexity Stable 2057", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2058", .provider = "cohere", .display = "Cohere Legacy 2058", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-2059", .provider = "nvidia", .display = "Nvidia Edge 2059", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2060", .provider = "sambanova", .display = "Sambanova Chat 2060", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2061", .provider = "github", .display = "Github Code 2061", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2062", .provider = "huggingface", .display = "Huggingface Reason 2062", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2063", .provider = "replicate", .display = "Replicate Vision 2063", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2064", .provider = "anyscale", .display = "Anyscale Embed 2064", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2065", .provider = "databricks", .display = "Databricks Audio 2065", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-2066", .provider = "moonshot", .display = "Moonshot Fast 2066", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2067", .provider = "qwen", .display = "Qwen Large 2067", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2068", .provider = "minimax", .display = "Minimax Mini 2068", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2069", .provider = "zhipu", .display = "Zhipu Nano 2069", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2070", .provider = "baichuan", .display = "Baichuan Pro 2070", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2071", .provider = "yi", .display = "Yi Ultra 2071", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2072", .provider = "siliconflow", .display = "Siliconflow Turbo 2072", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-2073", .provider = "novita", .display = "Novita Instruct 2073", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2074", .provider = "lepton", .display = "Lepton Base 2074", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2075", .provider = "deepinfra", .display = "Deepinfra Preview 2075", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2076", .provider = "friendli", .display = "Friendli Experimental 2076", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2077", .provider = "hyperbolic", .display = "Hyperbolic Stable 2077", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2078", .provider = "lambda", .display = "Lambda Legacy 2078", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2079", .provider = "nebius", .display = "Nebius Edge 2079", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-2080", .provider = "openai", .display = "Openai Chat 2080", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2081", .provider = "anthropic", .display = "Anthropic Code 2081", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2082", .provider = "google", .display = "Google Reason 2082", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2083", .provider = "groq", .display = "Groq Vision 2083", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2084", .provider = "xai", .display = "Xai Embed 2084", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2085", .provider = "deepseek", .display = "Deepseek Audio 2085", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2086", .provider = "mistral", .display = "Mistral Fast 2086", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-2087", .provider = "together", .display = "Together Large 2087", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2088", .provider = "fireworks", .display = "Fireworks Mini 2088", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2089", .provider = "openrouter", .display = "Openrouter Nano 2089", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2090", .provider = "cerebras", .display = "Cerebras Pro 2090", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2091", .provider = "ollama", .display = "Ollama Ultra 2091", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2092", .provider = "lmstudio", .display = "Lmstudio Turbo 2092", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2093", .provider = "vllm", .display = "Vllm Instruct 2093", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-2094", .provider = "azure", .display = "Azure Base 2094", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2095", .provider = "bedrock", .display = "Bedrock Preview 2095", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2096", .provider = "vertex", .display = "Vertex Experimental 2096", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2097", .provider = "perplexity", .display = "Perplexity Stable 2097", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2098", .provider = "cohere", .display = "Cohere Legacy 2098", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2099", .provider = "nvidia", .display = "Nvidia Edge 2099", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_2000_id() []const u8 {
    return models[0].id;
}
pub fn model_2000_context() u32 {
    return models[0].context_window;
}
pub fn model_2000_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_2000_family() []const u8 {
    return models[0].family;
}
pub fn model_2000_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_2001_id() []const u8 {
    return models[1].id;
}
pub fn model_2001_context() u32 {
    return models[1].context_window;
}
pub fn model_2001_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_2001_family() []const u8 {
    return models[1].family;
}
pub fn model_2001_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_2002_id() []const u8 {
    return models[2].id;
}
pub fn model_2002_context() u32 {
    return models[2].context_window;
}
pub fn model_2002_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_2002_family() []const u8 {
    return models[2].family;
}
pub fn model_2002_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_2003_id() []const u8 {
    return models[3].id;
}
pub fn model_2003_context() u32 {
    return models[3].context_window;
}
pub fn model_2003_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_2003_family() []const u8 {
    return models[3].family;
}
pub fn model_2003_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_2004_id() []const u8 {
    return models[4].id;
}
pub fn model_2004_context() u32 {
    return models[4].context_window;
}
pub fn model_2004_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_2004_family() []const u8 {
    return models[4].family;
}
pub fn model_2004_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_2005_id() []const u8 {
    return models[5].id;
}
pub fn model_2005_context() u32 {
    return models[5].context_window;
}
pub fn model_2005_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_2005_family() []const u8 {
    return models[5].family;
}
pub fn model_2005_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_2006_id() []const u8 {
    return models[6].id;
}
pub fn model_2006_context() u32 {
    return models[6].context_window;
}
pub fn model_2006_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_2006_family() []const u8 {
    return models[6].family;
}
pub fn model_2006_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_2007_id() []const u8 {
    return models[7].id;
}
pub fn model_2007_context() u32 {
    return models[7].context_window;
}
pub fn model_2007_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_2007_family() []const u8 {
    return models[7].family;
}
pub fn model_2007_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_2008_id() []const u8 {
    return models[8].id;
}
pub fn model_2008_context() u32 {
    return models[8].context_window;
}
pub fn model_2008_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_2008_family() []const u8 {
    return models[8].family;
}
pub fn model_2008_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_2009_id() []const u8 {
    return models[9].id;
}
pub fn model_2009_context() u32 {
    return models[9].context_window;
}
pub fn model_2009_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_2009_family() []const u8 {
    return models[9].family;
}
pub fn model_2009_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_2010_id() []const u8 {
    return models[10].id;
}
pub fn model_2010_context() u32 {
    return models[10].context_window;
}
pub fn model_2010_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_2010_family() []const u8 {
    return models[10].family;
}
pub fn model_2010_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_2011_id() []const u8 {
    return models[11].id;
}
pub fn model_2011_context() u32 {
    return models[11].context_window;
}
pub fn model_2011_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_2011_family() []const u8 {
    return models[11].family;
}
pub fn model_2011_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_2012_id() []const u8 {
    return models[12].id;
}
pub fn model_2012_context() u32 {
    return models[12].context_window;
}
pub fn model_2012_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_2012_family() []const u8 {
    return models[12].family;
}
pub fn model_2012_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_2013_id() []const u8 {
    return models[13].id;
}
pub fn model_2013_context() u32 {
    return models[13].context_window;
}
pub fn model_2013_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_2013_family() []const u8 {
    return models[13].family;
}
pub fn model_2013_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_2014_id() []const u8 {
    return models[14].id;
}
pub fn model_2014_context() u32 {
    return models[14].context_window;
}
pub fn model_2014_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_2014_family() []const u8 {
    return models[14].family;
}
pub fn model_2014_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_2015_id() []const u8 {
    return models[15].id;
}
pub fn model_2015_context() u32 {
    return models[15].context_window;
}
pub fn model_2015_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_2015_family() []const u8 {
    return models[15].family;
}
pub fn model_2015_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_2016_id() []const u8 {
    return models[16].id;
}
pub fn model_2016_context() u32 {
    return models[16].context_window;
}
pub fn model_2016_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_2016_family() []const u8 {
    return models[16].family;
}
pub fn model_2016_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_2017_id() []const u8 {
    return models[17].id;
}
pub fn model_2017_context() u32 {
    return models[17].context_window;
}
pub fn model_2017_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_2017_family() []const u8 {
    return models[17].family;
}
pub fn model_2017_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_2018_id() []const u8 {
    return models[18].id;
}
pub fn model_2018_context() u32 {
    return models[18].context_window;
}
pub fn model_2018_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_2018_family() []const u8 {
    return models[18].family;
}
pub fn model_2018_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_2019_id() []const u8 {
    return models[19].id;
}
pub fn model_2019_context() u32 {
    return models[19].context_window;
}
pub fn model_2019_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_2019_family() []const u8 {
    return models[19].family;
}
pub fn model_2019_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_2020_id() []const u8 {
    return models[20].id;
}
pub fn model_2020_context() u32 {
    return models[20].context_window;
}
pub fn model_2020_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_2020_family() []const u8 {
    return models[20].family;
}
pub fn model_2020_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_2021_id() []const u8 {
    return models[21].id;
}
pub fn model_2021_context() u32 {
    return models[21].context_window;
}
pub fn model_2021_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_2021_family() []const u8 {
    return models[21].family;
}
pub fn model_2021_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_2022_id() []const u8 {
    return models[22].id;
}
pub fn model_2022_context() u32 {
    return models[22].context_window;
}
pub fn model_2022_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_2022_family() []const u8 {
    return models[22].family;
}
pub fn model_2022_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_2023_id() []const u8 {
    return models[23].id;
}
pub fn model_2023_context() u32 {
    return models[23].context_window;
}
pub fn model_2023_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_2023_family() []const u8 {
    return models[23].family;
}
pub fn model_2023_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_2024_id() []const u8 {
    return models[24].id;
}
pub fn model_2024_context() u32 {
    return models[24].context_window;
}
pub fn model_2024_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_2024_family() []const u8 {
    return models[24].family;
}
pub fn model_2024_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_2025_id() []const u8 {
    return models[25].id;
}
pub fn model_2025_context() u32 {
    return models[25].context_window;
}
pub fn model_2025_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_2025_family() []const u8 {
    return models[25].family;
}
pub fn model_2025_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_2026_id() []const u8 {
    return models[26].id;
}
pub fn model_2026_context() u32 {
    return models[26].context_window;
}
pub fn model_2026_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_2026_family() []const u8 {
    return models[26].family;
}
pub fn model_2026_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_2027_id() []const u8 {
    return models[27].id;
}
pub fn model_2027_context() u32 {
    return models[27].context_window;
}
pub fn model_2027_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_2027_family() []const u8 {
    return models[27].family;
}
pub fn model_2027_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_2028_id() []const u8 {
    return models[28].id;
}
pub fn model_2028_context() u32 {
    return models[28].context_window;
}
pub fn model_2028_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_2028_family() []const u8 {
    return models[28].family;
}
pub fn model_2028_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_2029_id() []const u8 {
    return models[29].id;
}
pub fn model_2029_context() u32 {
    return models[29].context_window;
}
pub fn model_2029_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_2029_family() []const u8 {
    return models[29].family;
}
pub fn model_2029_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_2030_id() []const u8 {
    return models[30].id;
}
pub fn model_2030_context() u32 {
    return models[30].context_window;
}
pub fn model_2030_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_2030_family() []const u8 {
    return models[30].family;
}
pub fn model_2030_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_2031_id() []const u8 {
    return models[31].id;
}
pub fn model_2031_context() u32 {
    return models[31].context_window;
}
pub fn model_2031_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_2031_family() []const u8 {
    return models[31].family;
}
pub fn model_2031_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_2032_id() []const u8 {
    return models[32].id;
}
pub fn model_2032_context() u32 {
    return models[32].context_window;
}
pub fn model_2032_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_2032_family() []const u8 {
    return models[32].family;
}
pub fn model_2032_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_2033_id() []const u8 {
    return models[33].id;
}
pub fn model_2033_context() u32 {
    return models[33].context_window;
}
pub fn model_2033_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_2033_family() []const u8 {
    return models[33].family;
}
pub fn model_2033_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_2034_id() []const u8 {
    return models[34].id;
}
pub fn model_2034_context() u32 {
    return models[34].context_window;
}
pub fn model_2034_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_2034_family() []const u8 {
    return models[34].family;
}
pub fn model_2034_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_2035_id() []const u8 {
    return models[35].id;
}
pub fn model_2035_context() u32 {
    return models[35].context_window;
}
pub fn model_2035_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_2035_family() []const u8 {
    return models[35].family;
}
pub fn model_2035_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_2036_id() []const u8 {
    return models[36].id;
}
pub fn model_2036_context() u32 {
    return models[36].context_window;
}
pub fn model_2036_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_2036_family() []const u8 {
    return models[36].family;
}
pub fn model_2036_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_2037_id() []const u8 {
    return models[37].id;
}
pub fn model_2037_context() u32 {
    return models[37].context_window;
}
pub fn model_2037_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_2037_family() []const u8 {
    return models[37].family;
}
pub fn model_2037_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_2038_id() []const u8 {
    return models[38].id;
}
pub fn model_2038_context() u32 {
    return models[38].context_window;
}
pub fn model_2038_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_2038_family() []const u8 {
    return models[38].family;
}
pub fn model_2038_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_2039_id() []const u8 {
    return models[39].id;
}
pub fn model_2039_context() u32 {
    return models[39].context_window;
}
pub fn model_2039_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_2039_family() []const u8 {
    return models[39].family;
}
pub fn model_2039_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_2040_id() []const u8 {
    return models[40].id;
}
pub fn model_2040_context() u32 {
    return models[40].context_window;
}
pub fn model_2040_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_2040_family() []const u8 {
    return models[40].family;
}
pub fn model_2040_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_2041_id() []const u8 {
    return models[41].id;
}
pub fn model_2041_context() u32 {
    return models[41].context_window;
}
pub fn model_2041_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_2041_family() []const u8 {
    return models[41].family;
}
pub fn model_2041_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_2042_id() []const u8 {
    return models[42].id;
}
pub fn model_2042_context() u32 {
    return models[42].context_window;
}
pub fn model_2042_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_2042_family() []const u8 {
    return models[42].family;
}
pub fn model_2042_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_2043_id() []const u8 {
    return models[43].id;
}
pub fn model_2043_context() u32 {
    return models[43].context_window;
}
pub fn model_2043_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_2043_family() []const u8 {
    return models[43].family;
}
pub fn model_2043_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_2044_id() []const u8 {
    return models[44].id;
}
pub fn model_2044_context() u32 {
    return models[44].context_window;
}
pub fn model_2044_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_2044_family() []const u8 {
    return models[44].family;
}
pub fn model_2044_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_2045_id() []const u8 {
    return models[45].id;
}
pub fn model_2045_context() u32 {
    return models[45].context_window;
}
pub fn model_2045_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_2045_family() []const u8 {
    return models[45].family;
}
pub fn model_2045_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_2046_id() []const u8 {
    return models[46].id;
}
pub fn model_2046_context() u32 {
    return models[46].context_window;
}
pub fn model_2046_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_2046_family() []const u8 {
    return models[46].family;
}
pub fn model_2046_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_2047_id() []const u8 {
    return models[47].id;
}
pub fn model_2047_context() u32 {
    return models[47].context_window;
}
pub fn model_2047_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_2047_family() []const u8 {
    return models[47].family;
}
pub fn model_2047_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_2048_id() []const u8 {
    return models[48].id;
}
pub fn model_2048_context() u32 {
    return models[48].context_window;
}
pub fn model_2048_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_2048_family() []const u8 {
    return models[48].family;
}
pub fn model_2048_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_2049_id() []const u8 {
    return models[49].id;
}
pub fn model_2049_context() u32 {
    return models[49].context_window;
}
pub fn model_2049_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_2049_family() []const u8 {
    return models[49].family;
}
pub fn model_2049_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_2050_id() []const u8 {
    return models[50].id;
}
pub fn model_2050_context() u32 {
    return models[50].context_window;
}
pub fn model_2050_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_2050_family() []const u8 {
    return models[50].family;
}
pub fn model_2050_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_2051_id() []const u8 {
    return models[51].id;
}
pub fn model_2051_context() u32 {
    return models[51].context_window;
}
pub fn model_2051_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_2051_family() []const u8 {
    return models[51].family;
}
pub fn model_2051_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_2052_id() []const u8 {
    return models[52].id;
}
pub fn model_2052_context() u32 {
    return models[52].context_window;
}
pub fn model_2052_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_2052_family() []const u8 {
    return models[52].family;
}
pub fn model_2052_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_2053_id() []const u8 {
    return models[53].id;
}
pub fn model_2053_context() u32 {
    return models[53].context_window;
}
pub fn model_2053_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_2053_family() []const u8 {
    return models[53].family;
}
pub fn model_2053_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_2054_id() []const u8 {
    return models[54].id;
}
pub fn model_2054_context() u32 {
    return models[54].context_window;
}
pub fn model_2054_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_2054_family() []const u8 {
    return models[54].family;
}
pub fn model_2054_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_2055_id() []const u8 {
    return models[55].id;
}
pub fn model_2055_context() u32 {
    return models[55].context_window;
}
pub fn model_2055_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_2055_family() []const u8 {
    return models[55].family;
}
pub fn model_2055_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_2056_id() []const u8 {
    return models[56].id;
}
pub fn model_2056_context() u32 {
    return models[56].context_window;
}
pub fn model_2056_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_2056_family() []const u8 {
    return models[56].family;
}
pub fn model_2056_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_2057_id() []const u8 {
    return models[57].id;
}
pub fn model_2057_context() u32 {
    return models[57].context_window;
}
pub fn model_2057_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_2057_family() []const u8 {
    return models[57].family;
}
pub fn model_2057_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_2058_id() []const u8 {
    return models[58].id;
}
pub fn model_2058_context() u32 {
    return models[58].context_window;
}
pub fn model_2058_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_2058_family() []const u8 {
    return models[58].family;
}
pub fn model_2058_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_2059_id() []const u8 {
    return models[59].id;
}
pub fn model_2059_context() u32 {
    return models[59].context_window;
}
pub fn model_2059_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_2059_family() []const u8 {
    return models[59].family;
}
pub fn model_2059_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_2060_id() []const u8 {
    return models[60].id;
}
pub fn model_2060_context() u32 {
    return models[60].context_window;
}
pub fn model_2060_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_2060_family() []const u8 {
    return models[60].family;
}
pub fn model_2060_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_2061_id() []const u8 {
    return models[61].id;
}
pub fn model_2061_context() u32 {
    return models[61].context_window;
}
pub fn model_2061_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_2061_family() []const u8 {
    return models[61].family;
}
pub fn model_2061_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_2062_id() []const u8 {
    return models[62].id;
}
pub fn model_2062_context() u32 {
    return models[62].context_window;
}
pub fn model_2062_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_2062_family() []const u8 {
    return models[62].family;
}
pub fn model_2062_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_2063_id() []const u8 {
    return models[63].id;
}
pub fn model_2063_context() u32 {
    return models[63].context_window;
}
pub fn model_2063_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_2063_family() []const u8 {
    return models[63].family;
}
pub fn model_2063_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_2064_id() []const u8 {
    return models[64].id;
}
pub fn model_2064_context() u32 {
    return models[64].context_window;
}
pub fn model_2064_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_2064_family() []const u8 {
    return models[64].family;
}
pub fn model_2064_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_2065_id() []const u8 {
    return models[65].id;
}
pub fn model_2065_context() u32 {
    return models[65].context_window;
}
pub fn model_2065_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_2065_family() []const u8 {
    return models[65].family;
}
pub fn model_2065_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_2066_id() []const u8 {
    return models[66].id;
}
pub fn model_2066_context() u32 {
    return models[66].context_window;
}
pub fn model_2066_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_2066_family() []const u8 {
    return models[66].family;
}
pub fn model_2066_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_2067_id() []const u8 {
    return models[67].id;
}
pub fn model_2067_context() u32 {
    return models[67].context_window;
}
pub fn model_2067_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_2067_family() []const u8 {
    return models[67].family;
}
pub fn model_2067_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_2068_id() []const u8 {
    return models[68].id;
}
pub fn model_2068_context() u32 {
    return models[68].context_window;
}
pub fn model_2068_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_2068_family() []const u8 {
    return models[68].family;
}
pub fn model_2068_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_2069_id() []const u8 {
    return models[69].id;
}
pub fn model_2069_context() u32 {
    return models[69].context_window;
}
pub fn model_2069_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_2069_family() []const u8 {
    return models[69].family;
}
pub fn model_2069_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_2070_id() []const u8 {
    return models[70].id;
}
pub fn model_2070_context() u32 {
    return models[70].context_window;
}
pub fn model_2070_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_2070_family() []const u8 {
    return models[70].family;
}
pub fn model_2070_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_2071_id() []const u8 {
    return models[71].id;
}
pub fn model_2071_context() u32 {
    return models[71].context_window;
}
pub fn model_2071_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_2071_family() []const u8 {
    return models[71].family;
}
pub fn model_2071_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_2072_id() []const u8 {
    return models[72].id;
}
pub fn model_2072_context() u32 {
    return models[72].context_window;
}
pub fn model_2072_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_2072_family() []const u8 {
    return models[72].family;
}
pub fn model_2072_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_2073_id() []const u8 {
    return models[73].id;
}
pub fn model_2073_context() u32 {
    return models[73].context_window;
}
pub fn model_2073_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_2073_family() []const u8 {
    return models[73].family;
}
pub fn model_2073_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_2074_id() []const u8 {
    return models[74].id;
}
pub fn model_2074_context() u32 {
    return models[74].context_window;
}
pub fn model_2074_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_2074_family() []const u8 {
    return models[74].family;
}
pub fn model_2074_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_2075_id() []const u8 {
    return models[75].id;
}
pub fn model_2075_context() u32 {
    return models[75].context_window;
}
pub fn model_2075_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_2075_family() []const u8 {
    return models[75].family;
}
pub fn model_2075_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_2076_id() []const u8 {
    return models[76].id;
}
pub fn model_2076_context() u32 {
    return models[76].context_window;
}
pub fn model_2076_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_2076_family() []const u8 {
    return models[76].family;
}
pub fn model_2076_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_2077_id() []const u8 {
    return models[77].id;
}
pub fn model_2077_context() u32 {
    return models[77].context_window;
}
pub fn model_2077_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_2077_family() []const u8 {
    return models[77].family;
}
pub fn model_2077_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_2078_id() []const u8 {
    return models[78].id;
}
pub fn model_2078_context() u32 {
    return models[78].context_window;
}
pub fn model_2078_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_2078_family() []const u8 {
    return models[78].family;
}
pub fn model_2078_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_2079_id() []const u8 {
    return models[79].id;
}
pub fn model_2079_context() u32 {
    return models[79].context_window;
}
pub fn model_2079_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_2079_family() []const u8 {
    return models[79].family;
}
pub fn model_2079_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 20 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

