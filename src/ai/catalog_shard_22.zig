//! Generated model catalog shard 22 for package ai.
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

pub const shard_index: u32 = 22;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-2200", .provider = "openai", .display = "Openai Chat 2200", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2201", .provider = "anthropic", .display = "Anthropic Code 2201", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2202", .provider = "google", .display = "Google Reason 2202", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2203", .provider = "groq", .display = "Groq Vision 2203", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2204", .provider = "xai", .display = "Xai Embed 2204", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2205", .provider = "deepseek", .display = "Deepseek Audio 2205", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-2206", .provider = "mistral", .display = "Mistral Fast 2206", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2207", .provider = "together", .display = "Together Large 2207", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2208", .provider = "fireworks", .display = "Fireworks Mini 2208", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2209", .provider = "openrouter", .display = "Openrouter Nano 2209", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2210", .provider = "cerebras", .display = "Cerebras Pro 2210", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2211", .provider = "ollama", .display = "Ollama Ultra 2211", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2212", .provider = "lmstudio", .display = "Lmstudio Turbo 2212", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-2213", .provider = "vllm", .display = "Vllm Instruct 2213", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2214", .provider = "azure", .display = "Azure Base 2214", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2215", .provider = "bedrock", .display = "Bedrock Preview 2215", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2216", .provider = "vertex", .display = "Vertex Experimental 2216", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2217", .provider = "perplexity", .display = "Perplexity Stable 2217", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2218", .provider = "cohere", .display = "Cohere Legacy 2218", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2219", .provider = "nvidia", .display = "Nvidia Edge 2219", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-2220", .provider = "sambanova", .display = "Sambanova Chat 2220", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2221", .provider = "github", .display = "Github Code 2221", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2222", .provider = "huggingface", .display = "Huggingface Reason 2222", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2223", .provider = "replicate", .display = "Replicate Vision 2223", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2224", .provider = "anyscale", .display = "Anyscale Embed 2224", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2225", .provider = "databricks", .display = "Databricks Audio 2225", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2226", .provider = "moonshot", .display = "Moonshot Fast 2226", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-2227", .provider = "qwen", .display = "Qwen Large 2227", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2228", .provider = "minimax", .display = "Minimax Mini 2228", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2229", .provider = "zhipu", .display = "Zhipu Nano 2229", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2230", .provider = "baichuan", .display = "Baichuan Pro 2230", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2231", .provider = "yi", .display = "Yi Ultra 2231", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2232", .provider = "siliconflow", .display = "Siliconflow Turbo 2232", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2233", .provider = "novita", .display = "Novita Instruct 2233", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-2234", .provider = "lepton", .display = "Lepton Base 2234", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2235", .provider = "deepinfra", .display = "Deepinfra Preview 2235", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2236", .provider = "friendli", .display = "Friendli Experimental 2236", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2237", .provider = "hyperbolic", .display = "Hyperbolic Stable 2237", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2238", .provider = "lambda", .display = "Lambda Legacy 2238", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2239", .provider = "nebius", .display = "Nebius Edge 2239", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2240", .provider = "openai", .display = "Openai Chat 2240", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-2241", .provider = "anthropic", .display = "Anthropic Code 2241", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2242", .provider = "google", .display = "Google Reason 2242", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2243", .provider = "groq", .display = "Groq Vision 2243", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2244", .provider = "xai", .display = "Xai Embed 2244", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2245", .provider = "deepseek", .display = "Deepseek Audio 2245", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2246", .provider = "mistral", .display = "Mistral Fast 2246", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2247", .provider = "together", .display = "Together Large 2247", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-2248", .provider = "fireworks", .display = "Fireworks Mini 2248", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2249", .provider = "openrouter", .display = "Openrouter Nano 2249", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2250", .provider = "cerebras", .display = "Cerebras Pro 2250", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2251", .provider = "ollama", .display = "Ollama Ultra 2251", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2252", .provider = "lmstudio", .display = "Lmstudio Turbo 2252", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2253", .provider = "vllm", .display = "Vllm Instruct 2253", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2254", .provider = "azure", .display = "Azure Base 2254", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-2255", .provider = "bedrock", .display = "Bedrock Preview 2255", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2256", .provider = "vertex", .display = "Vertex Experimental 2256", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2257", .provider = "perplexity", .display = "Perplexity Stable 2257", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2258", .provider = "cohere", .display = "Cohere Legacy 2258", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2259", .provider = "nvidia", .display = "Nvidia Edge 2259", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2260", .provider = "sambanova", .display = "Sambanova Chat 2260", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2261", .provider = "github", .display = "Github Code 2261", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-2262", .provider = "huggingface", .display = "Huggingface Reason 2262", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2263", .provider = "replicate", .display = "Replicate Vision 2263", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2264", .provider = "anyscale", .display = "Anyscale Embed 2264", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2265", .provider = "databricks", .display = "Databricks Audio 2265", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2266", .provider = "moonshot", .display = "Moonshot Fast 2266", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2267", .provider = "qwen", .display = "Qwen Large 2267", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2268", .provider = "minimax", .display = "Minimax Mini 2268", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-2269", .provider = "zhipu", .display = "Zhipu Nano 2269", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2270", .provider = "baichuan", .display = "Baichuan Pro 2270", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2271", .provider = "yi", .display = "Yi Ultra 2271", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2272", .provider = "siliconflow", .display = "Siliconflow Turbo 2272", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2273", .provider = "novita", .display = "Novita Instruct 2273", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2274", .provider = "lepton", .display = "Lepton Base 2274", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2275", .provider = "deepinfra", .display = "Deepinfra Preview 2275", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-2276", .provider = "friendli", .display = "Friendli Experimental 2276", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2277", .provider = "hyperbolic", .display = "Hyperbolic Stable 2277", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2278", .provider = "lambda", .display = "Lambda Legacy 2278", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2279", .provider = "nebius", .display = "Nebius Edge 2279", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2280", .provider = "openai", .display = "Openai Chat 2280", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2281", .provider = "anthropic", .display = "Anthropic Code 2281", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2282", .provider = "google", .display = "Google Reason 2282", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-2283", .provider = "groq", .display = "Groq Vision 2283", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2284", .provider = "xai", .display = "Xai Embed 2284", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2285", .provider = "deepseek", .display = "Deepseek Audio 2285", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2286", .provider = "mistral", .display = "Mistral Fast 2286", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2287", .provider = "together", .display = "Together Large 2287", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2288", .provider = "fireworks", .display = "Fireworks Mini 2288", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2289", .provider = "openrouter", .display = "Openrouter Nano 2289", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-2290", .provider = "cerebras", .display = "Cerebras Pro 2290", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2291", .provider = "ollama", .display = "Ollama Ultra 2291", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2292", .provider = "lmstudio", .display = "Lmstudio Turbo 2292", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2293", .provider = "vllm", .display = "Vllm Instruct 2293", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2294", .provider = "azure", .display = "Azure Base 2294", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2295", .provider = "bedrock", .display = "Bedrock Preview 2295", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2296", .provider = "vertex", .display = "Vertex Experimental 2296", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-2297", .provider = "perplexity", .display = "Perplexity Stable 2297", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2298", .provider = "cohere", .display = "Cohere Legacy 2298", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2299", .provider = "nvidia", .display = "Nvidia Edge 2299", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_2200_id() []const u8 {
    return models[0].id;
}
pub fn model_2200_context() u32 {
    return models[0].context_window;
}
pub fn model_2200_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_2200_family() []const u8 {
    return models[0].family;
}
pub fn model_2200_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_2201_id() []const u8 {
    return models[1].id;
}
pub fn model_2201_context() u32 {
    return models[1].context_window;
}
pub fn model_2201_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_2201_family() []const u8 {
    return models[1].family;
}
pub fn model_2201_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_2202_id() []const u8 {
    return models[2].id;
}
pub fn model_2202_context() u32 {
    return models[2].context_window;
}
pub fn model_2202_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_2202_family() []const u8 {
    return models[2].family;
}
pub fn model_2202_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_2203_id() []const u8 {
    return models[3].id;
}
pub fn model_2203_context() u32 {
    return models[3].context_window;
}
pub fn model_2203_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_2203_family() []const u8 {
    return models[3].family;
}
pub fn model_2203_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_2204_id() []const u8 {
    return models[4].id;
}
pub fn model_2204_context() u32 {
    return models[4].context_window;
}
pub fn model_2204_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_2204_family() []const u8 {
    return models[4].family;
}
pub fn model_2204_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_2205_id() []const u8 {
    return models[5].id;
}
pub fn model_2205_context() u32 {
    return models[5].context_window;
}
pub fn model_2205_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_2205_family() []const u8 {
    return models[5].family;
}
pub fn model_2205_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_2206_id() []const u8 {
    return models[6].id;
}
pub fn model_2206_context() u32 {
    return models[6].context_window;
}
pub fn model_2206_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_2206_family() []const u8 {
    return models[6].family;
}
pub fn model_2206_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_2207_id() []const u8 {
    return models[7].id;
}
pub fn model_2207_context() u32 {
    return models[7].context_window;
}
pub fn model_2207_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_2207_family() []const u8 {
    return models[7].family;
}
pub fn model_2207_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_2208_id() []const u8 {
    return models[8].id;
}
pub fn model_2208_context() u32 {
    return models[8].context_window;
}
pub fn model_2208_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_2208_family() []const u8 {
    return models[8].family;
}
pub fn model_2208_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_2209_id() []const u8 {
    return models[9].id;
}
pub fn model_2209_context() u32 {
    return models[9].context_window;
}
pub fn model_2209_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_2209_family() []const u8 {
    return models[9].family;
}
pub fn model_2209_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_2210_id() []const u8 {
    return models[10].id;
}
pub fn model_2210_context() u32 {
    return models[10].context_window;
}
pub fn model_2210_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_2210_family() []const u8 {
    return models[10].family;
}
pub fn model_2210_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_2211_id() []const u8 {
    return models[11].id;
}
pub fn model_2211_context() u32 {
    return models[11].context_window;
}
pub fn model_2211_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_2211_family() []const u8 {
    return models[11].family;
}
pub fn model_2211_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_2212_id() []const u8 {
    return models[12].id;
}
pub fn model_2212_context() u32 {
    return models[12].context_window;
}
pub fn model_2212_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_2212_family() []const u8 {
    return models[12].family;
}
pub fn model_2212_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_2213_id() []const u8 {
    return models[13].id;
}
pub fn model_2213_context() u32 {
    return models[13].context_window;
}
pub fn model_2213_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_2213_family() []const u8 {
    return models[13].family;
}
pub fn model_2213_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_2214_id() []const u8 {
    return models[14].id;
}
pub fn model_2214_context() u32 {
    return models[14].context_window;
}
pub fn model_2214_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_2214_family() []const u8 {
    return models[14].family;
}
pub fn model_2214_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_2215_id() []const u8 {
    return models[15].id;
}
pub fn model_2215_context() u32 {
    return models[15].context_window;
}
pub fn model_2215_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_2215_family() []const u8 {
    return models[15].family;
}
pub fn model_2215_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_2216_id() []const u8 {
    return models[16].id;
}
pub fn model_2216_context() u32 {
    return models[16].context_window;
}
pub fn model_2216_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_2216_family() []const u8 {
    return models[16].family;
}
pub fn model_2216_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_2217_id() []const u8 {
    return models[17].id;
}
pub fn model_2217_context() u32 {
    return models[17].context_window;
}
pub fn model_2217_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_2217_family() []const u8 {
    return models[17].family;
}
pub fn model_2217_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_2218_id() []const u8 {
    return models[18].id;
}
pub fn model_2218_context() u32 {
    return models[18].context_window;
}
pub fn model_2218_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_2218_family() []const u8 {
    return models[18].family;
}
pub fn model_2218_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_2219_id() []const u8 {
    return models[19].id;
}
pub fn model_2219_context() u32 {
    return models[19].context_window;
}
pub fn model_2219_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_2219_family() []const u8 {
    return models[19].family;
}
pub fn model_2219_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_2220_id() []const u8 {
    return models[20].id;
}
pub fn model_2220_context() u32 {
    return models[20].context_window;
}
pub fn model_2220_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_2220_family() []const u8 {
    return models[20].family;
}
pub fn model_2220_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_2221_id() []const u8 {
    return models[21].id;
}
pub fn model_2221_context() u32 {
    return models[21].context_window;
}
pub fn model_2221_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_2221_family() []const u8 {
    return models[21].family;
}
pub fn model_2221_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_2222_id() []const u8 {
    return models[22].id;
}
pub fn model_2222_context() u32 {
    return models[22].context_window;
}
pub fn model_2222_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_2222_family() []const u8 {
    return models[22].family;
}
pub fn model_2222_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_2223_id() []const u8 {
    return models[23].id;
}
pub fn model_2223_context() u32 {
    return models[23].context_window;
}
pub fn model_2223_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_2223_family() []const u8 {
    return models[23].family;
}
pub fn model_2223_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_2224_id() []const u8 {
    return models[24].id;
}
pub fn model_2224_context() u32 {
    return models[24].context_window;
}
pub fn model_2224_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_2224_family() []const u8 {
    return models[24].family;
}
pub fn model_2224_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_2225_id() []const u8 {
    return models[25].id;
}
pub fn model_2225_context() u32 {
    return models[25].context_window;
}
pub fn model_2225_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_2225_family() []const u8 {
    return models[25].family;
}
pub fn model_2225_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_2226_id() []const u8 {
    return models[26].id;
}
pub fn model_2226_context() u32 {
    return models[26].context_window;
}
pub fn model_2226_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_2226_family() []const u8 {
    return models[26].family;
}
pub fn model_2226_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_2227_id() []const u8 {
    return models[27].id;
}
pub fn model_2227_context() u32 {
    return models[27].context_window;
}
pub fn model_2227_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_2227_family() []const u8 {
    return models[27].family;
}
pub fn model_2227_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_2228_id() []const u8 {
    return models[28].id;
}
pub fn model_2228_context() u32 {
    return models[28].context_window;
}
pub fn model_2228_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_2228_family() []const u8 {
    return models[28].family;
}
pub fn model_2228_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_2229_id() []const u8 {
    return models[29].id;
}
pub fn model_2229_context() u32 {
    return models[29].context_window;
}
pub fn model_2229_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_2229_family() []const u8 {
    return models[29].family;
}
pub fn model_2229_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_2230_id() []const u8 {
    return models[30].id;
}
pub fn model_2230_context() u32 {
    return models[30].context_window;
}
pub fn model_2230_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_2230_family() []const u8 {
    return models[30].family;
}
pub fn model_2230_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_2231_id() []const u8 {
    return models[31].id;
}
pub fn model_2231_context() u32 {
    return models[31].context_window;
}
pub fn model_2231_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_2231_family() []const u8 {
    return models[31].family;
}
pub fn model_2231_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_2232_id() []const u8 {
    return models[32].id;
}
pub fn model_2232_context() u32 {
    return models[32].context_window;
}
pub fn model_2232_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_2232_family() []const u8 {
    return models[32].family;
}
pub fn model_2232_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_2233_id() []const u8 {
    return models[33].id;
}
pub fn model_2233_context() u32 {
    return models[33].context_window;
}
pub fn model_2233_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_2233_family() []const u8 {
    return models[33].family;
}
pub fn model_2233_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_2234_id() []const u8 {
    return models[34].id;
}
pub fn model_2234_context() u32 {
    return models[34].context_window;
}
pub fn model_2234_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_2234_family() []const u8 {
    return models[34].family;
}
pub fn model_2234_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_2235_id() []const u8 {
    return models[35].id;
}
pub fn model_2235_context() u32 {
    return models[35].context_window;
}
pub fn model_2235_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_2235_family() []const u8 {
    return models[35].family;
}
pub fn model_2235_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_2236_id() []const u8 {
    return models[36].id;
}
pub fn model_2236_context() u32 {
    return models[36].context_window;
}
pub fn model_2236_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_2236_family() []const u8 {
    return models[36].family;
}
pub fn model_2236_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_2237_id() []const u8 {
    return models[37].id;
}
pub fn model_2237_context() u32 {
    return models[37].context_window;
}
pub fn model_2237_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_2237_family() []const u8 {
    return models[37].family;
}
pub fn model_2237_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_2238_id() []const u8 {
    return models[38].id;
}
pub fn model_2238_context() u32 {
    return models[38].context_window;
}
pub fn model_2238_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_2238_family() []const u8 {
    return models[38].family;
}
pub fn model_2238_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_2239_id() []const u8 {
    return models[39].id;
}
pub fn model_2239_context() u32 {
    return models[39].context_window;
}
pub fn model_2239_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_2239_family() []const u8 {
    return models[39].family;
}
pub fn model_2239_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_2240_id() []const u8 {
    return models[40].id;
}
pub fn model_2240_context() u32 {
    return models[40].context_window;
}
pub fn model_2240_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_2240_family() []const u8 {
    return models[40].family;
}
pub fn model_2240_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_2241_id() []const u8 {
    return models[41].id;
}
pub fn model_2241_context() u32 {
    return models[41].context_window;
}
pub fn model_2241_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_2241_family() []const u8 {
    return models[41].family;
}
pub fn model_2241_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_2242_id() []const u8 {
    return models[42].id;
}
pub fn model_2242_context() u32 {
    return models[42].context_window;
}
pub fn model_2242_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_2242_family() []const u8 {
    return models[42].family;
}
pub fn model_2242_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_2243_id() []const u8 {
    return models[43].id;
}
pub fn model_2243_context() u32 {
    return models[43].context_window;
}
pub fn model_2243_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_2243_family() []const u8 {
    return models[43].family;
}
pub fn model_2243_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_2244_id() []const u8 {
    return models[44].id;
}
pub fn model_2244_context() u32 {
    return models[44].context_window;
}
pub fn model_2244_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_2244_family() []const u8 {
    return models[44].family;
}
pub fn model_2244_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_2245_id() []const u8 {
    return models[45].id;
}
pub fn model_2245_context() u32 {
    return models[45].context_window;
}
pub fn model_2245_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_2245_family() []const u8 {
    return models[45].family;
}
pub fn model_2245_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_2246_id() []const u8 {
    return models[46].id;
}
pub fn model_2246_context() u32 {
    return models[46].context_window;
}
pub fn model_2246_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_2246_family() []const u8 {
    return models[46].family;
}
pub fn model_2246_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_2247_id() []const u8 {
    return models[47].id;
}
pub fn model_2247_context() u32 {
    return models[47].context_window;
}
pub fn model_2247_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_2247_family() []const u8 {
    return models[47].family;
}
pub fn model_2247_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_2248_id() []const u8 {
    return models[48].id;
}
pub fn model_2248_context() u32 {
    return models[48].context_window;
}
pub fn model_2248_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_2248_family() []const u8 {
    return models[48].family;
}
pub fn model_2248_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_2249_id() []const u8 {
    return models[49].id;
}
pub fn model_2249_context() u32 {
    return models[49].context_window;
}
pub fn model_2249_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_2249_family() []const u8 {
    return models[49].family;
}
pub fn model_2249_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_2250_id() []const u8 {
    return models[50].id;
}
pub fn model_2250_context() u32 {
    return models[50].context_window;
}
pub fn model_2250_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_2250_family() []const u8 {
    return models[50].family;
}
pub fn model_2250_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_2251_id() []const u8 {
    return models[51].id;
}
pub fn model_2251_context() u32 {
    return models[51].context_window;
}
pub fn model_2251_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_2251_family() []const u8 {
    return models[51].family;
}
pub fn model_2251_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_2252_id() []const u8 {
    return models[52].id;
}
pub fn model_2252_context() u32 {
    return models[52].context_window;
}
pub fn model_2252_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_2252_family() []const u8 {
    return models[52].family;
}
pub fn model_2252_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_2253_id() []const u8 {
    return models[53].id;
}
pub fn model_2253_context() u32 {
    return models[53].context_window;
}
pub fn model_2253_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_2253_family() []const u8 {
    return models[53].family;
}
pub fn model_2253_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_2254_id() []const u8 {
    return models[54].id;
}
pub fn model_2254_context() u32 {
    return models[54].context_window;
}
pub fn model_2254_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_2254_family() []const u8 {
    return models[54].family;
}
pub fn model_2254_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_2255_id() []const u8 {
    return models[55].id;
}
pub fn model_2255_context() u32 {
    return models[55].context_window;
}
pub fn model_2255_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_2255_family() []const u8 {
    return models[55].family;
}
pub fn model_2255_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_2256_id() []const u8 {
    return models[56].id;
}
pub fn model_2256_context() u32 {
    return models[56].context_window;
}
pub fn model_2256_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_2256_family() []const u8 {
    return models[56].family;
}
pub fn model_2256_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_2257_id() []const u8 {
    return models[57].id;
}
pub fn model_2257_context() u32 {
    return models[57].context_window;
}
pub fn model_2257_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_2257_family() []const u8 {
    return models[57].family;
}
pub fn model_2257_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_2258_id() []const u8 {
    return models[58].id;
}
pub fn model_2258_context() u32 {
    return models[58].context_window;
}
pub fn model_2258_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_2258_family() []const u8 {
    return models[58].family;
}
pub fn model_2258_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_2259_id() []const u8 {
    return models[59].id;
}
pub fn model_2259_context() u32 {
    return models[59].context_window;
}
pub fn model_2259_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_2259_family() []const u8 {
    return models[59].family;
}
pub fn model_2259_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_2260_id() []const u8 {
    return models[60].id;
}
pub fn model_2260_context() u32 {
    return models[60].context_window;
}
pub fn model_2260_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_2260_family() []const u8 {
    return models[60].family;
}
pub fn model_2260_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_2261_id() []const u8 {
    return models[61].id;
}
pub fn model_2261_context() u32 {
    return models[61].context_window;
}
pub fn model_2261_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_2261_family() []const u8 {
    return models[61].family;
}
pub fn model_2261_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_2262_id() []const u8 {
    return models[62].id;
}
pub fn model_2262_context() u32 {
    return models[62].context_window;
}
pub fn model_2262_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_2262_family() []const u8 {
    return models[62].family;
}
pub fn model_2262_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_2263_id() []const u8 {
    return models[63].id;
}
pub fn model_2263_context() u32 {
    return models[63].context_window;
}
pub fn model_2263_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_2263_family() []const u8 {
    return models[63].family;
}
pub fn model_2263_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_2264_id() []const u8 {
    return models[64].id;
}
pub fn model_2264_context() u32 {
    return models[64].context_window;
}
pub fn model_2264_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_2264_family() []const u8 {
    return models[64].family;
}
pub fn model_2264_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_2265_id() []const u8 {
    return models[65].id;
}
pub fn model_2265_context() u32 {
    return models[65].context_window;
}
pub fn model_2265_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_2265_family() []const u8 {
    return models[65].family;
}
pub fn model_2265_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_2266_id() []const u8 {
    return models[66].id;
}
pub fn model_2266_context() u32 {
    return models[66].context_window;
}
pub fn model_2266_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_2266_family() []const u8 {
    return models[66].family;
}
pub fn model_2266_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_2267_id() []const u8 {
    return models[67].id;
}
pub fn model_2267_context() u32 {
    return models[67].context_window;
}
pub fn model_2267_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_2267_family() []const u8 {
    return models[67].family;
}
pub fn model_2267_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_2268_id() []const u8 {
    return models[68].id;
}
pub fn model_2268_context() u32 {
    return models[68].context_window;
}
pub fn model_2268_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_2268_family() []const u8 {
    return models[68].family;
}
pub fn model_2268_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_2269_id() []const u8 {
    return models[69].id;
}
pub fn model_2269_context() u32 {
    return models[69].context_window;
}
pub fn model_2269_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_2269_family() []const u8 {
    return models[69].family;
}
pub fn model_2269_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_2270_id() []const u8 {
    return models[70].id;
}
pub fn model_2270_context() u32 {
    return models[70].context_window;
}
pub fn model_2270_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_2270_family() []const u8 {
    return models[70].family;
}
pub fn model_2270_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_2271_id() []const u8 {
    return models[71].id;
}
pub fn model_2271_context() u32 {
    return models[71].context_window;
}
pub fn model_2271_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_2271_family() []const u8 {
    return models[71].family;
}
pub fn model_2271_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_2272_id() []const u8 {
    return models[72].id;
}
pub fn model_2272_context() u32 {
    return models[72].context_window;
}
pub fn model_2272_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_2272_family() []const u8 {
    return models[72].family;
}
pub fn model_2272_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_2273_id() []const u8 {
    return models[73].id;
}
pub fn model_2273_context() u32 {
    return models[73].context_window;
}
pub fn model_2273_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_2273_family() []const u8 {
    return models[73].family;
}
pub fn model_2273_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_2274_id() []const u8 {
    return models[74].id;
}
pub fn model_2274_context() u32 {
    return models[74].context_window;
}
pub fn model_2274_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_2274_family() []const u8 {
    return models[74].family;
}
pub fn model_2274_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_2275_id() []const u8 {
    return models[75].id;
}
pub fn model_2275_context() u32 {
    return models[75].context_window;
}
pub fn model_2275_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_2275_family() []const u8 {
    return models[75].family;
}
pub fn model_2275_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_2276_id() []const u8 {
    return models[76].id;
}
pub fn model_2276_context() u32 {
    return models[76].context_window;
}
pub fn model_2276_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_2276_family() []const u8 {
    return models[76].family;
}
pub fn model_2276_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_2277_id() []const u8 {
    return models[77].id;
}
pub fn model_2277_context() u32 {
    return models[77].context_window;
}
pub fn model_2277_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_2277_family() []const u8 {
    return models[77].family;
}
pub fn model_2277_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_2278_id() []const u8 {
    return models[78].id;
}
pub fn model_2278_context() u32 {
    return models[78].context_window;
}
pub fn model_2278_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_2278_family() []const u8 {
    return models[78].family;
}
pub fn model_2278_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_2279_id() []const u8 {
    return models[79].id;
}
pub fn model_2279_context() u32 {
    return models[79].context_window;
}
pub fn model_2279_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_2279_family() []const u8 {
    return models[79].family;
}
pub fn model_2279_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 22 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

