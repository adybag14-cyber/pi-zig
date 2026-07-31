//! Generated model catalog shard 24 for package ai.
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

pub const shard_index: u32 = 24;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-2400", .provider = "openai", .display = "Openai Chat 2400", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2401", .provider = "anthropic", .display = "Anthropic Code 2401", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-2402", .provider = "google", .display = "Google Reason 2402", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2403", .provider = "groq", .display = "Groq Vision 2403", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2404", .provider = "xai", .display = "Xai Embed 2404", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2405", .provider = "deepseek", .display = "Deepseek Audio 2405", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2406", .provider = "mistral", .display = "Mistral Fast 2406", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2407", .provider = "together", .display = "Together Large 2407", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2408", .provider = "fireworks", .display = "Fireworks Mini 2408", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-2409", .provider = "openrouter", .display = "Openrouter Nano 2409", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2410", .provider = "cerebras", .display = "Cerebras Pro 2410", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2411", .provider = "ollama", .display = "Ollama Ultra 2411", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2412", .provider = "lmstudio", .display = "Lmstudio Turbo 2412", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2413", .provider = "vllm", .display = "Vllm Instruct 2413", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2414", .provider = "azure", .display = "Azure Base 2414", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2415", .provider = "bedrock", .display = "Bedrock Preview 2415", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-2416", .provider = "vertex", .display = "Vertex Experimental 2416", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2417", .provider = "perplexity", .display = "Perplexity Stable 2417", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2418", .provider = "cohere", .display = "Cohere Legacy 2418", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2419", .provider = "nvidia", .display = "Nvidia Edge 2419", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2420", .provider = "sambanova", .display = "Sambanova Chat 2420", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2421", .provider = "github", .display = "Github Code 2421", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2422", .provider = "huggingface", .display = "Huggingface Reason 2422", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-2423", .provider = "replicate", .display = "Replicate Vision 2423", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2424", .provider = "anyscale", .display = "Anyscale Embed 2424", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2425", .provider = "databricks", .display = "Databricks Audio 2425", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2426", .provider = "moonshot", .display = "Moonshot Fast 2426", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2427", .provider = "qwen", .display = "Qwen Large 2427", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2428", .provider = "minimax", .display = "Minimax Mini 2428", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2429", .provider = "zhipu", .display = "Zhipu Nano 2429", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-2430", .provider = "baichuan", .display = "Baichuan Pro 2430", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2431", .provider = "yi", .display = "Yi Ultra 2431", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2432", .provider = "siliconflow", .display = "Siliconflow Turbo 2432", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2433", .provider = "novita", .display = "Novita Instruct 2433", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2434", .provider = "lepton", .display = "Lepton Base 2434", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2435", .provider = "deepinfra", .display = "Deepinfra Preview 2435", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2436", .provider = "friendli", .display = "Friendli Experimental 2436", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2437", .provider = "hyperbolic", .display = "Hyperbolic Stable 2437", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2438", .provider = "lambda", .display = "Lambda Legacy 2438", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2439", .provider = "nebius", .display = "Nebius Edge 2439", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2440", .provider = "openai", .display = "Openai Chat 2440", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2441", .provider = "anthropic", .display = "Anthropic Code 2441", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2442", .provider = "google", .display = "Google Reason 2442", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2443", .provider = "groq", .display = "Groq Vision 2443", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-2444", .provider = "xai", .display = "Xai Embed 2444", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2445", .provider = "deepseek", .display = "Deepseek Audio 2445", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2446", .provider = "mistral", .display = "Mistral Fast 2446", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2447", .provider = "together", .display = "Together Large 2447", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2448", .provider = "fireworks", .display = "Fireworks Mini 2448", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2449", .provider = "openrouter", .display = "Openrouter Nano 2449", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2450", .provider = "cerebras", .display = "Cerebras Pro 2450", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-2451", .provider = "ollama", .display = "Ollama Ultra 2451", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2452", .provider = "lmstudio", .display = "Lmstudio Turbo 2452", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2453", .provider = "vllm", .display = "Vllm Instruct 2453", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2454", .provider = "azure", .display = "Azure Base 2454", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2455", .provider = "bedrock", .display = "Bedrock Preview 2455", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2456", .provider = "vertex", .display = "Vertex Experimental 2456", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2457", .provider = "perplexity", .display = "Perplexity Stable 2457", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-2458", .provider = "cohere", .display = "Cohere Legacy 2458", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2459", .provider = "nvidia", .display = "Nvidia Edge 2459", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2460", .provider = "sambanova", .display = "Sambanova Chat 2460", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2461", .provider = "github", .display = "Github Code 2461", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2462", .provider = "huggingface", .display = "Huggingface Reason 2462", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2463", .provider = "replicate", .display = "Replicate Vision 2463", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2464", .provider = "anyscale", .display = "Anyscale Embed 2464", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-2465", .provider = "databricks", .display = "Databricks Audio 2465", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2466", .provider = "moonshot", .display = "Moonshot Fast 2466", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2467", .provider = "qwen", .display = "Qwen Large 2467", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2468", .provider = "minimax", .display = "Minimax Mini 2468", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2469", .provider = "zhipu", .display = "Zhipu Nano 2469", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2470", .provider = "baichuan", .display = "Baichuan Pro 2470", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2471", .provider = "yi", .display = "Yi Ultra 2471", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2472", .provider = "siliconflow", .display = "Siliconflow Turbo 2472", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2473", .provider = "novita", .display = "Novita Instruct 2473", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2474", .provider = "lepton", .display = "Lepton Base 2474", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2475", .provider = "deepinfra", .display = "Deepinfra Preview 2475", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2476", .provider = "friendli", .display = "Friendli Experimental 2476", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2477", .provider = "hyperbolic", .display = "Hyperbolic Stable 2477", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2478", .provider = "lambda", .display = "Lambda Legacy 2478", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-2479", .provider = "nebius", .display = "Nebius Edge 2479", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2480", .provider = "openai", .display = "Openai Chat 2480", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2481", .provider = "anthropic", .display = "Anthropic Code 2481", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2482", .provider = "google", .display = "Google Reason 2482", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2483", .provider = "groq", .display = "Groq Vision 2483", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2484", .provider = "xai", .display = "Xai Embed 2484", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2485", .provider = "deepseek", .display = "Deepseek Audio 2485", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-2486", .provider = "mistral", .display = "Mistral Fast 2486", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2487", .provider = "together", .display = "Together Large 2487", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2488", .provider = "fireworks", .display = "Fireworks Mini 2488", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2489", .provider = "openrouter", .display = "Openrouter Nano 2489", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2490", .provider = "cerebras", .display = "Cerebras Pro 2490", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2491", .provider = "ollama", .display = "Ollama Ultra 2491", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2492", .provider = "lmstudio", .display = "Lmstudio Turbo 2492", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-2493", .provider = "vllm", .display = "Vllm Instruct 2493", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2494", .provider = "azure", .display = "Azure Base 2494", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2495", .provider = "bedrock", .display = "Bedrock Preview 2495", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2496", .provider = "vertex", .display = "Vertex Experimental 2496", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2497", .provider = "perplexity", .display = "Perplexity Stable 2497", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2498", .provider = "cohere", .display = "Cohere Legacy 2498", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2499", .provider = "nvidia", .display = "Nvidia Edge 2499", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
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

pub fn model_2400_id() []const u8 {
    return models[0].id;
}
pub fn model_2400_context() u32 {
    return models[0].context_window;
}
pub fn model_2400_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_2400_family() []const u8 {
    return models[0].family;
}
pub fn model_2400_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_2401_id() []const u8 {
    return models[1].id;
}
pub fn model_2401_context() u32 {
    return models[1].context_window;
}
pub fn model_2401_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_2401_family() []const u8 {
    return models[1].family;
}
pub fn model_2401_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_2402_id() []const u8 {
    return models[2].id;
}
pub fn model_2402_context() u32 {
    return models[2].context_window;
}
pub fn model_2402_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_2402_family() []const u8 {
    return models[2].family;
}
pub fn model_2402_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_2403_id() []const u8 {
    return models[3].id;
}
pub fn model_2403_context() u32 {
    return models[3].context_window;
}
pub fn model_2403_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_2403_family() []const u8 {
    return models[3].family;
}
pub fn model_2403_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_2404_id() []const u8 {
    return models[4].id;
}
pub fn model_2404_context() u32 {
    return models[4].context_window;
}
pub fn model_2404_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_2404_family() []const u8 {
    return models[4].family;
}
pub fn model_2404_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_2405_id() []const u8 {
    return models[5].id;
}
pub fn model_2405_context() u32 {
    return models[5].context_window;
}
pub fn model_2405_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_2405_family() []const u8 {
    return models[5].family;
}
pub fn model_2405_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_2406_id() []const u8 {
    return models[6].id;
}
pub fn model_2406_context() u32 {
    return models[6].context_window;
}
pub fn model_2406_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_2406_family() []const u8 {
    return models[6].family;
}
pub fn model_2406_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_2407_id() []const u8 {
    return models[7].id;
}
pub fn model_2407_context() u32 {
    return models[7].context_window;
}
pub fn model_2407_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_2407_family() []const u8 {
    return models[7].family;
}
pub fn model_2407_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_2408_id() []const u8 {
    return models[8].id;
}
pub fn model_2408_context() u32 {
    return models[8].context_window;
}
pub fn model_2408_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_2408_family() []const u8 {
    return models[8].family;
}
pub fn model_2408_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_2409_id() []const u8 {
    return models[9].id;
}
pub fn model_2409_context() u32 {
    return models[9].context_window;
}
pub fn model_2409_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_2409_family() []const u8 {
    return models[9].family;
}
pub fn model_2409_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_2410_id() []const u8 {
    return models[10].id;
}
pub fn model_2410_context() u32 {
    return models[10].context_window;
}
pub fn model_2410_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_2410_family() []const u8 {
    return models[10].family;
}
pub fn model_2410_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_2411_id() []const u8 {
    return models[11].id;
}
pub fn model_2411_context() u32 {
    return models[11].context_window;
}
pub fn model_2411_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_2411_family() []const u8 {
    return models[11].family;
}
pub fn model_2411_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_2412_id() []const u8 {
    return models[12].id;
}
pub fn model_2412_context() u32 {
    return models[12].context_window;
}
pub fn model_2412_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_2412_family() []const u8 {
    return models[12].family;
}
pub fn model_2412_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_2413_id() []const u8 {
    return models[13].id;
}
pub fn model_2413_context() u32 {
    return models[13].context_window;
}
pub fn model_2413_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_2413_family() []const u8 {
    return models[13].family;
}
pub fn model_2413_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_2414_id() []const u8 {
    return models[14].id;
}
pub fn model_2414_context() u32 {
    return models[14].context_window;
}
pub fn model_2414_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_2414_family() []const u8 {
    return models[14].family;
}
pub fn model_2414_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_2415_id() []const u8 {
    return models[15].id;
}
pub fn model_2415_context() u32 {
    return models[15].context_window;
}
pub fn model_2415_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_2415_family() []const u8 {
    return models[15].family;
}
pub fn model_2415_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_2416_id() []const u8 {
    return models[16].id;
}
pub fn model_2416_context() u32 {
    return models[16].context_window;
}
pub fn model_2416_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_2416_family() []const u8 {
    return models[16].family;
}
pub fn model_2416_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_2417_id() []const u8 {
    return models[17].id;
}
pub fn model_2417_context() u32 {
    return models[17].context_window;
}
pub fn model_2417_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_2417_family() []const u8 {
    return models[17].family;
}
pub fn model_2417_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_2418_id() []const u8 {
    return models[18].id;
}
pub fn model_2418_context() u32 {
    return models[18].context_window;
}
pub fn model_2418_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_2418_family() []const u8 {
    return models[18].family;
}
pub fn model_2418_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_2419_id() []const u8 {
    return models[19].id;
}
pub fn model_2419_context() u32 {
    return models[19].context_window;
}
pub fn model_2419_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_2419_family() []const u8 {
    return models[19].family;
}
pub fn model_2419_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_2420_id() []const u8 {
    return models[20].id;
}
pub fn model_2420_context() u32 {
    return models[20].context_window;
}
pub fn model_2420_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_2420_family() []const u8 {
    return models[20].family;
}
pub fn model_2420_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_2421_id() []const u8 {
    return models[21].id;
}
pub fn model_2421_context() u32 {
    return models[21].context_window;
}
pub fn model_2421_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_2421_family() []const u8 {
    return models[21].family;
}
pub fn model_2421_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_2422_id() []const u8 {
    return models[22].id;
}
pub fn model_2422_context() u32 {
    return models[22].context_window;
}
pub fn model_2422_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_2422_family() []const u8 {
    return models[22].family;
}
pub fn model_2422_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_2423_id() []const u8 {
    return models[23].id;
}
pub fn model_2423_context() u32 {
    return models[23].context_window;
}
pub fn model_2423_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_2423_family() []const u8 {
    return models[23].family;
}
pub fn model_2423_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_2424_id() []const u8 {
    return models[24].id;
}
pub fn model_2424_context() u32 {
    return models[24].context_window;
}
pub fn model_2424_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_2424_family() []const u8 {
    return models[24].family;
}
pub fn model_2424_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_2425_id() []const u8 {
    return models[25].id;
}
pub fn model_2425_context() u32 {
    return models[25].context_window;
}
pub fn model_2425_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_2425_family() []const u8 {
    return models[25].family;
}
pub fn model_2425_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_2426_id() []const u8 {
    return models[26].id;
}
pub fn model_2426_context() u32 {
    return models[26].context_window;
}
pub fn model_2426_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_2426_family() []const u8 {
    return models[26].family;
}
pub fn model_2426_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_2427_id() []const u8 {
    return models[27].id;
}
pub fn model_2427_context() u32 {
    return models[27].context_window;
}
pub fn model_2427_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_2427_family() []const u8 {
    return models[27].family;
}
pub fn model_2427_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_2428_id() []const u8 {
    return models[28].id;
}
pub fn model_2428_context() u32 {
    return models[28].context_window;
}
pub fn model_2428_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_2428_family() []const u8 {
    return models[28].family;
}
pub fn model_2428_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_2429_id() []const u8 {
    return models[29].id;
}
pub fn model_2429_context() u32 {
    return models[29].context_window;
}
pub fn model_2429_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_2429_family() []const u8 {
    return models[29].family;
}
pub fn model_2429_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_2430_id() []const u8 {
    return models[30].id;
}
pub fn model_2430_context() u32 {
    return models[30].context_window;
}
pub fn model_2430_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_2430_family() []const u8 {
    return models[30].family;
}
pub fn model_2430_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_2431_id() []const u8 {
    return models[31].id;
}
pub fn model_2431_context() u32 {
    return models[31].context_window;
}
pub fn model_2431_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_2431_family() []const u8 {
    return models[31].family;
}
pub fn model_2431_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_2432_id() []const u8 {
    return models[32].id;
}
pub fn model_2432_context() u32 {
    return models[32].context_window;
}
pub fn model_2432_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_2432_family() []const u8 {
    return models[32].family;
}
pub fn model_2432_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_2433_id() []const u8 {
    return models[33].id;
}
pub fn model_2433_context() u32 {
    return models[33].context_window;
}
pub fn model_2433_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_2433_family() []const u8 {
    return models[33].family;
}
pub fn model_2433_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_2434_id() []const u8 {
    return models[34].id;
}
pub fn model_2434_context() u32 {
    return models[34].context_window;
}
pub fn model_2434_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_2434_family() []const u8 {
    return models[34].family;
}
pub fn model_2434_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_2435_id() []const u8 {
    return models[35].id;
}
pub fn model_2435_context() u32 {
    return models[35].context_window;
}
pub fn model_2435_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_2435_family() []const u8 {
    return models[35].family;
}
pub fn model_2435_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_2436_id() []const u8 {
    return models[36].id;
}
pub fn model_2436_context() u32 {
    return models[36].context_window;
}
pub fn model_2436_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_2436_family() []const u8 {
    return models[36].family;
}
pub fn model_2436_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_2437_id() []const u8 {
    return models[37].id;
}
pub fn model_2437_context() u32 {
    return models[37].context_window;
}
pub fn model_2437_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_2437_family() []const u8 {
    return models[37].family;
}
pub fn model_2437_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_2438_id() []const u8 {
    return models[38].id;
}
pub fn model_2438_context() u32 {
    return models[38].context_window;
}
pub fn model_2438_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_2438_family() []const u8 {
    return models[38].family;
}
pub fn model_2438_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_2439_id() []const u8 {
    return models[39].id;
}
pub fn model_2439_context() u32 {
    return models[39].context_window;
}
pub fn model_2439_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_2439_family() []const u8 {
    return models[39].family;
}
pub fn model_2439_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_2440_id() []const u8 {
    return models[40].id;
}
pub fn model_2440_context() u32 {
    return models[40].context_window;
}
pub fn model_2440_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_2440_family() []const u8 {
    return models[40].family;
}
pub fn model_2440_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_2441_id() []const u8 {
    return models[41].id;
}
pub fn model_2441_context() u32 {
    return models[41].context_window;
}
pub fn model_2441_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_2441_family() []const u8 {
    return models[41].family;
}
pub fn model_2441_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_2442_id() []const u8 {
    return models[42].id;
}
pub fn model_2442_context() u32 {
    return models[42].context_window;
}
pub fn model_2442_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_2442_family() []const u8 {
    return models[42].family;
}
pub fn model_2442_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_2443_id() []const u8 {
    return models[43].id;
}
pub fn model_2443_context() u32 {
    return models[43].context_window;
}
pub fn model_2443_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_2443_family() []const u8 {
    return models[43].family;
}
pub fn model_2443_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_2444_id() []const u8 {
    return models[44].id;
}
pub fn model_2444_context() u32 {
    return models[44].context_window;
}
pub fn model_2444_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_2444_family() []const u8 {
    return models[44].family;
}
pub fn model_2444_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_2445_id() []const u8 {
    return models[45].id;
}
pub fn model_2445_context() u32 {
    return models[45].context_window;
}
pub fn model_2445_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_2445_family() []const u8 {
    return models[45].family;
}
pub fn model_2445_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_2446_id() []const u8 {
    return models[46].id;
}
pub fn model_2446_context() u32 {
    return models[46].context_window;
}
pub fn model_2446_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_2446_family() []const u8 {
    return models[46].family;
}
pub fn model_2446_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_2447_id() []const u8 {
    return models[47].id;
}
pub fn model_2447_context() u32 {
    return models[47].context_window;
}
pub fn model_2447_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_2447_family() []const u8 {
    return models[47].family;
}
pub fn model_2447_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_2448_id() []const u8 {
    return models[48].id;
}
pub fn model_2448_context() u32 {
    return models[48].context_window;
}
pub fn model_2448_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_2448_family() []const u8 {
    return models[48].family;
}
pub fn model_2448_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_2449_id() []const u8 {
    return models[49].id;
}
pub fn model_2449_context() u32 {
    return models[49].context_window;
}
pub fn model_2449_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_2449_family() []const u8 {
    return models[49].family;
}
pub fn model_2449_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_2450_id() []const u8 {
    return models[50].id;
}
pub fn model_2450_context() u32 {
    return models[50].context_window;
}
pub fn model_2450_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_2450_family() []const u8 {
    return models[50].family;
}
pub fn model_2450_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_2451_id() []const u8 {
    return models[51].id;
}
pub fn model_2451_context() u32 {
    return models[51].context_window;
}
pub fn model_2451_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_2451_family() []const u8 {
    return models[51].family;
}
pub fn model_2451_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_2452_id() []const u8 {
    return models[52].id;
}
pub fn model_2452_context() u32 {
    return models[52].context_window;
}
pub fn model_2452_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_2452_family() []const u8 {
    return models[52].family;
}
pub fn model_2452_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_2453_id() []const u8 {
    return models[53].id;
}
pub fn model_2453_context() u32 {
    return models[53].context_window;
}
pub fn model_2453_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_2453_family() []const u8 {
    return models[53].family;
}
pub fn model_2453_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_2454_id() []const u8 {
    return models[54].id;
}
pub fn model_2454_context() u32 {
    return models[54].context_window;
}
pub fn model_2454_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_2454_family() []const u8 {
    return models[54].family;
}
pub fn model_2454_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_2455_id() []const u8 {
    return models[55].id;
}
pub fn model_2455_context() u32 {
    return models[55].context_window;
}
pub fn model_2455_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_2455_family() []const u8 {
    return models[55].family;
}
pub fn model_2455_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_2456_id() []const u8 {
    return models[56].id;
}
pub fn model_2456_context() u32 {
    return models[56].context_window;
}
pub fn model_2456_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_2456_family() []const u8 {
    return models[56].family;
}
pub fn model_2456_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_2457_id() []const u8 {
    return models[57].id;
}
pub fn model_2457_context() u32 {
    return models[57].context_window;
}
pub fn model_2457_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_2457_family() []const u8 {
    return models[57].family;
}
pub fn model_2457_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_2458_id() []const u8 {
    return models[58].id;
}
pub fn model_2458_context() u32 {
    return models[58].context_window;
}
pub fn model_2458_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_2458_family() []const u8 {
    return models[58].family;
}
pub fn model_2458_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_2459_id() []const u8 {
    return models[59].id;
}
pub fn model_2459_context() u32 {
    return models[59].context_window;
}
pub fn model_2459_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_2459_family() []const u8 {
    return models[59].family;
}
pub fn model_2459_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_2460_id() []const u8 {
    return models[60].id;
}
pub fn model_2460_context() u32 {
    return models[60].context_window;
}
pub fn model_2460_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_2460_family() []const u8 {
    return models[60].family;
}
pub fn model_2460_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_2461_id() []const u8 {
    return models[61].id;
}
pub fn model_2461_context() u32 {
    return models[61].context_window;
}
pub fn model_2461_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_2461_family() []const u8 {
    return models[61].family;
}
pub fn model_2461_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_2462_id() []const u8 {
    return models[62].id;
}
pub fn model_2462_context() u32 {
    return models[62].context_window;
}
pub fn model_2462_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_2462_family() []const u8 {
    return models[62].family;
}
pub fn model_2462_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_2463_id() []const u8 {
    return models[63].id;
}
pub fn model_2463_context() u32 {
    return models[63].context_window;
}
pub fn model_2463_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_2463_family() []const u8 {
    return models[63].family;
}
pub fn model_2463_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_2464_id() []const u8 {
    return models[64].id;
}
pub fn model_2464_context() u32 {
    return models[64].context_window;
}
pub fn model_2464_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_2464_family() []const u8 {
    return models[64].family;
}
pub fn model_2464_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_2465_id() []const u8 {
    return models[65].id;
}
pub fn model_2465_context() u32 {
    return models[65].context_window;
}
pub fn model_2465_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_2465_family() []const u8 {
    return models[65].family;
}
pub fn model_2465_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_2466_id() []const u8 {
    return models[66].id;
}
pub fn model_2466_context() u32 {
    return models[66].context_window;
}
pub fn model_2466_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_2466_family() []const u8 {
    return models[66].family;
}
pub fn model_2466_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_2467_id() []const u8 {
    return models[67].id;
}
pub fn model_2467_context() u32 {
    return models[67].context_window;
}
pub fn model_2467_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_2467_family() []const u8 {
    return models[67].family;
}
pub fn model_2467_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_2468_id() []const u8 {
    return models[68].id;
}
pub fn model_2468_context() u32 {
    return models[68].context_window;
}
pub fn model_2468_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_2468_family() []const u8 {
    return models[68].family;
}
pub fn model_2468_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_2469_id() []const u8 {
    return models[69].id;
}
pub fn model_2469_context() u32 {
    return models[69].context_window;
}
pub fn model_2469_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_2469_family() []const u8 {
    return models[69].family;
}
pub fn model_2469_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_2470_id() []const u8 {
    return models[70].id;
}
pub fn model_2470_context() u32 {
    return models[70].context_window;
}
pub fn model_2470_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_2470_family() []const u8 {
    return models[70].family;
}
pub fn model_2470_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_2471_id() []const u8 {
    return models[71].id;
}
pub fn model_2471_context() u32 {
    return models[71].context_window;
}
pub fn model_2471_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_2471_family() []const u8 {
    return models[71].family;
}
pub fn model_2471_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_2472_id() []const u8 {
    return models[72].id;
}
pub fn model_2472_context() u32 {
    return models[72].context_window;
}
pub fn model_2472_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_2472_family() []const u8 {
    return models[72].family;
}
pub fn model_2472_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_2473_id() []const u8 {
    return models[73].id;
}
pub fn model_2473_context() u32 {
    return models[73].context_window;
}
pub fn model_2473_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_2473_family() []const u8 {
    return models[73].family;
}
pub fn model_2473_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_2474_id() []const u8 {
    return models[74].id;
}
pub fn model_2474_context() u32 {
    return models[74].context_window;
}
pub fn model_2474_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_2474_family() []const u8 {
    return models[74].family;
}
pub fn model_2474_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_2475_id() []const u8 {
    return models[75].id;
}
pub fn model_2475_context() u32 {
    return models[75].context_window;
}
pub fn model_2475_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_2475_family() []const u8 {
    return models[75].family;
}
pub fn model_2475_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_2476_id() []const u8 {
    return models[76].id;
}
pub fn model_2476_context() u32 {
    return models[76].context_window;
}
pub fn model_2476_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_2476_family() []const u8 {
    return models[76].family;
}
pub fn model_2476_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_2477_id() []const u8 {
    return models[77].id;
}
pub fn model_2477_context() u32 {
    return models[77].context_window;
}
pub fn model_2477_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_2477_family() []const u8 {
    return models[77].family;
}
pub fn model_2477_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_2478_id() []const u8 {
    return models[78].id;
}
pub fn model_2478_context() u32 {
    return models[78].context_window;
}
pub fn model_2478_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_2478_family() []const u8 {
    return models[78].family;
}
pub fn model_2478_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_2479_id() []const u8 {
    return models[79].id;
}
pub fn model_2479_context() u32 {
    return models[79].context_window;
}
pub fn model_2479_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_2479_family() []const u8 {
    return models[79].family;
}
pub fn model_2479_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 24 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

