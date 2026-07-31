//! Generated model catalog shard 0 for package ai.
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

pub const shard_index: u32 = 0;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-0", .provider = "openai", .display = "Openai Chat 0", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-1", .provider = "anthropic", .display = "Anthropic Code 1", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2", .provider = "google", .display = "Google Reason 2", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3", .provider = "groq", .display = "Groq Vision 3", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-4", .provider = "xai", .display = "Xai Embed 4", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-5", .provider = "deepseek", .display = "Deepseek Audio 5", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-6", .provider = "mistral", .display = "Mistral Fast 6", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-7", .provider = "together", .display = "Together Large 7", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-8", .provider = "fireworks", .display = "Fireworks Mini 8", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-9", .provider = "openrouter", .display = "Openrouter Nano 9", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-10", .provider = "cerebras", .display = "Cerebras Pro 10", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-11", .provider = "ollama", .display = "Ollama Ultra 11", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-12", .provider = "lmstudio", .display = "Lmstudio Turbo 12", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-13", .provider = "vllm", .display = "Vllm Instruct 13", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-14", .provider = "azure", .display = "Azure Base 14", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-15", .provider = "bedrock", .display = "Bedrock Preview 15", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-16", .provider = "vertex", .display = "Vertex Experimental 16", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-17", .provider = "perplexity", .display = "Perplexity Stable 17", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-18", .provider = "cohere", .display = "Cohere Legacy 18", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-19", .provider = "nvidia", .display = "Nvidia Edge 19", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-20", .provider = "sambanova", .display = "Sambanova Chat 20", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-21", .provider = "github", .display = "Github Code 21", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-22", .provider = "huggingface", .display = "Huggingface Reason 22", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-23", .provider = "replicate", .display = "Replicate Vision 23", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-24", .provider = "anyscale", .display = "Anyscale Embed 24", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-25", .provider = "databricks", .display = "Databricks Audio 25", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-26", .provider = "moonshot", .display = "Moonshot Fast 26", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-27", .provider = "qwen", .display = "Qwen Large 27", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-28", .provider = "minimax", .display = "Minimax Mini 28", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-29", .provider = "zhipu", .display = "Zhipu Nano 29", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-30", .provider = "baichuan", .display = "Baichuan Pro 30", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-31", .provider = "yi", .display = "Yi Ultra 31", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-32", .provider = "siliconflow", .display = "Siliconflow Turbo 32", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-33", .provider = "novita", .display = "Novita Instruct 33", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-34", .provider = "lepton", .display = "Lepton Base 34", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-35", .provider = "deepinfra", .display = "Deepinfra Preview 35", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-36", .provider = "friendli", .display = "Friendli Experimental 36", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-37", .provider = "hyperbolic", .display = "Hyperbolic Stable 37", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-38", .provider = "lambda", .display = "Lambda Legacy 38", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-39", .provider = "nebius", .display = "Nebius Edge 39", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-40", .provider = "openai", .display = "Openai Chat 40", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-41", .provider = "anthropic", .display = "Anthropic Code 41", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-42", .provider = "google", .display = "Google Reason 42", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-43", .provider = "groq", .display = "Groq Vision 43", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-44", .provider = "xai", .display = "Xai Embed 44", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-45", .provider = "deepseek", .display = "Deepseek Audio 45", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-46", .provider = "mistral", .display = "Mistral Fast 46", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-47", .provider = "together", .display = "Together Large 47", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-48", .provider = "fireworks", .display = "Fireworks Mini 48", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-49", .provider = "openrouter", .display = "Openrouter Nano 49", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-50", .provider = "cerebras", .display = "Cerebras Pro 50", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-51", .provider = "ollama", .display = "Ollama Ultra 51", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-52", .provider = "lmstudio", .display = "Lmstudio Turbo 52", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-53", .provider = "vllm", .display = "Vllm Instruct 53", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-54", .provider = "azure", .display = "Azure Base 54", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-55", .provider = "bedrock", .display = "Bedrock Preview 55", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-56", .provider = "vertex", .display = "Vertex Experimental 56", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-57", .provider = "perplexity", .display = "Perplexity Stable 57", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-58", .provider = "cohere", .display = "Cohere Legacy 58", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-59", .provider = "nvidia", .display = "Nvidia Edge 59", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-60", .provider = "sambanova", .display = "Sambanova Chat 60", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-61", .provider = "github", .display = "Github Code 61", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-62", .provider = "huggingface", .display = "Huggingface Reason 62", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-63", .provider = "replicate", .display = "Replicate Vision 63", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-64", .provider = "anyscale", .display = "Anyscale Embed 64", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-65", .provider = "databricks", .display = "Databricks Audio 65", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-66", .provider = "moonshot", .display = "Moonshot Fast 66", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-67", .provider = "qwen", .display = "Qwen Large 67", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-68", .provider = "minimax", .display = "Minimax Mini 68", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-69", .provider = "zhipu", .display = "Zhipu Nano 69", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-70", .provider = "baichuan", .display = "Baichuan Pro 70", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-71", .provider = "yi", .display = "Yi Ultra 71", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-72", .provider = "siliconflow", .display = "Siliconflow Turbo 72", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-73", .provider = "novita", .display = "Novita Instruct 73", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-74", .provider = "lepton", .display = "Lepton Base 74", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-75", .provider = "deepinfra", .display = "Deepinfra Preview 75", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-76", .provider = "friendli", .display = "Friendli Experimental 76", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-77", .provider = "hyperbolic", .display = "Hyperbolic Stable 77", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-78", .provider = "lambda", .display = "Lambda Legacy 78", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-79", .provider = "nebius", .display = "Nebius Edge 79", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-80", .provider = "openai", .display = "Openai Chat 80", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-81", .provider = "anthropic", .display = "Anthropic Code 81", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-82", .provider = "google", .display = "Google Reason 82", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-83", .provider = "groq", .display = "Groq Vision 83", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-84", .provider = "xai", .display = "Xai Embed 84", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-85", .provider = "deepseek", .display = "Deepseek Audio 85", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-86", .provider = "mistral", .display = "Mistral Fast 86", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-87", .provider = "together", .display = "Together Large 87", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-88", .provider = "fireworks", .display = "Fireworks Mini 88", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-89", .provider = "openrouter", .display = "Openrouter Nano 89", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-90", .provider = "cerebras", .display = "Cerebras Pro 90", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-91", .provider = "ollama", .display = "Ollama Ultra 91", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-92", .provider = "lmstudio", .display = "Lmstudio Turbo 92", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-93", .provider = "vllm", .display = "Vllm Instruct 93", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-94", .provider = "azure", .display = "Azure Base 94", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-95", .provider = "bedrock", .display = "Bedrock Preview 95", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-96", .provider = "vertex", .display = "Vertex Experimental 96", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-97", .provider = "perplexity", .display = "Perplexity Stable 97", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-98", .provider = "cohere", .display = "Cohere Legacy 98", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-99", .provider = "nvidia", .display = "Nvidia Edge 99", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_0_id() []const u8 {
    return models[0].id;
}
pub fn model_0_context() u32 {
    return models[0].context_window;
}
pub fn model_0_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_0_family() []const u8 {
    return models[0].family;
}
pub fn model_0_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1_id() []const u8 {
    return models[1].id;
}
pub fn model_1_context() u32 {
    return models[1].context_window;
}
pub fn model_1_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1_family() []const u8 {
    return models[1].family;
}
pub fn model_1_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_2_id() []const u8 {
    return models[2].id;
}
pub fn model_2_context() u32 {
    return models[2].context_window;
}
pub fn model_2_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_2_family() []const u8 {
    return models[2].family;
}
pub fn model_2_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3_id() []const u8 {
    return models[3].id;
}
pub fn model_3_context() u32 {
    return models[3].context_window;
}
pub fn model_3_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3_family() []const u8 {
    return models[3].family;
}
pub fn model_3_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_4_id() []const u8 {
    return models[4].id;
}
pub fn model_4_context() u32 {
    return models[4].context_window;
}
pub fn model_4_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_4_family() []const u8 {
    return models[4].family;
}
pub fn model_4_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_5_id() []const u8 {
    return models[5].id;
}
pub fn model_5_context() u32 {
    return models[5].context_window;
}
pub fn model_5_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_5_family() []const u8 {
    return models[5].family;
}
pub fn model_5_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_6_id() []const u8 {
    return models[6].id;
}
pub fn model_6_context() u32 {
    return models[6].context_window;
}
pub fn model_6_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_6_family() []const u8 {
    return models[6].family;
}
pub fn model_6_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_7_id() []const u8 {
    return models[7].id;
}
pub fn model_7_context() u32 {
    return models[7].context_window;
}
pub fn model_7_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_7_family() []const u8 {
    return models[7].family;
}
pub fn model_7_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_8_id() []const u8 {
    return models[8].id;
}
pub fn model_8_context() u32 {
    return models[8].context_window;
}
pub fn model_8_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_8_family() []const u8 {
    return models[8].family;
}
pub fn model_8_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_9_id() []const u8 {
    return models[9].id;
}
pub fn model_9_context() u32 {
    return models[9].context_window;
}
pub fn model_9_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_9_family() []const u8 {
    return models[9].family;
}
pub fn model_9_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_10_id() []const u8 {
    return models[10].id;
}
pub fn model_10_context() u32 {
    return models[10].context_window;
}
pub fn model_10_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_10_family() []const u8 {
    return models[10].family;
}
pub fn model_10_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_11_id() []const u8 {
    return models[11].id;
}
pub fn model_11_context() u32 {
    return models[11].context_window;
}
pub fn model_11_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_11_family() []const u8 {
    return models[11].family;
}
pub fn model_11_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_12_id() []const u8 {
    return models[12].id;
}
pub fn model_12_context() u32 {
    return models[12].context_window;
}
pub fn model_12_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_12_family() []const u8 {
    return models[12].family;
}
pub fn model_12_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_13_id() []const u8 {
    return models[13].id;
}
pub fn model_13_context() u32 {
    return models[13].context_window;
}
pub fn model_13_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_13_family() []const u8 {
    return models[13].family;
}
pub fn model_13_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_14_id() []const u8 {
    return models[14].id;
}
pub fn model_14_context() u32 {
    return models[14].context_window;
}
pub fn model_14_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_14_family() []const u8 {
    return models[14].family;
}
pub fn model_14_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_15_id() []const u8 {
    return models[15].id;
}
pub fn model_15_context() u32 {
    return models[15].context_window;
}
pub fn model_15_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_15_family() []const u8 {
    return models[15].family;
}
pub fn model_15_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_16_id() []const u8 {
    return models[16].id;
}
pub fn model_16_context() u32 {
    return models[16].context_window;
}
pub fn model_16_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_16_family() []const u8 {
    return models[16].family;
}
pub fn model_16_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_17_id() []const u8 {
    return models[17].id;
}
pub fn model_17_context() u32 {
    return models[17].context_window;
}
pub fn model_17_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_17_family() []const u8 {
    return models[17].family;
}
pub fn model_17_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_18_id() []const u8 {
    return models[18].id;
}
pub fn model_18_context() u32 {
    return models[18].context_window;
}
pub fn model_18_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_18_family() []const u8 {
    return models[18].family;
}
pub fn model_18_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_19_id() []const u8 {
    return models[19].id;
}
pub fn model_19_context() u32 {
    return models[19].context_window;
}
pub fn model_19_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_19_family() []const u8 {
    return models[19].family;
}
pub fn model_19_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_20_id() []const u8 {
    return models[20].id;
}
pub fn model_20_context() u32 {
    return models[20].context_window;
}
pub fn model_20_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_20_family() []const u8 {
    return models[20].family;
}
pub fn model_20_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_21_id() []const u8 {
    return models[21].id;
}
pub fn model_21_context() u32 {
    return models[21].context_window;
}
pub fn model_21_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_21_family() []const u8 {
    return models[21].family;
}
pub fn model_21_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_22_id() []const u8 {
    return models[22].id;
}
pub fn model_22_context() u32 {
    return models[22].context_window;
}
pub fn model_22_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_22_family() []const u8 {
    return models[22].family;
}
pub fn model_22_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_23_id() []const u8 {
    return models[23].id;
}
pub fn model_23_context() u32 {
    return models[23].context_window;
}
pub fn model_23_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_23_family() []const u8 {
    return models[23].family;
}
pub fn model_23_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_24_id() []const u8 {
    return models[24].id;
}
pub fn model_24_context() u32 {
    return models[24].context_window;
}
pub fn model_24_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_24_family() []const u8 {
    return models[24].family;
}
pub fn model_24_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_25_id() []const u8 {
    return models[25].id;
}
pub fn model_25_context() u32 {
    return models[25].context_window;
}
pub fn model_25_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_25_family() []const u8 {
    return models[25].family;
}
pub fn model_25_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_26_id() []const u8 {
    return models[26].id;
}
pub fn model_26_context() u32 {
    return models[26].context_window;
}
pub fn model_26_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_26_family() []const u8 {
    return models[26].family;
}
pub fn model_26_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_27_id() []const u8 {
    return models[27].id;
}
pub fn model_27_context() u32 {
    return models[27].context_window;
}
pub fn model_27_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_27_family() []const u8 {
    return models[27].family;
}
pub fn model_27_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_28_id() []const u8 {
    return models[28].id;
}
pub fn model_28_context() u32 {
    return models[28].context_window;
}
pub fn model_28_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_28_family() []const u8 {
    return models[28].family;
}
pub fn model_28_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_29_id() []const u8 {
    return models[29].id;
}
pub fn model_29_context() u32 {
    return models[29].context_window;
}
pub fn model_29_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_29_family() []const u8 {
    return models[29].family;
}
pub fn model_29_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_30_id() []const u8 {
    return models[30].id;
}
pub fn model_30_context() u32 {
    return models[30].context_window;
}
pub fn model_30_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_30_family() []const u8 {
    return models[30].family;
}
pub fn model_30_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_31_id() []const u8 {
    return models[31].id;
}
pub fn model_31_context() u32 {
    return models[31].context_window;
}
pub fn model_31_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_31_family() []const u8 {
    return models[31].family;
}
pub fn model_31_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_32_id() []const u8 {
    return models[32].id;
}
pub fn model_32_context() u32 {
    return models[32].context_window;
}
pub fn model_32_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_32_family() []const u8 {
    return models[32].family;
}
pub fn model_32_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_33_id() []const u8 {
    return models[33].id;
}
pub fn model_33_context() u32 {
    return models[33].context_window;
}
pub fn model_33_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_33_family() []const u8 {
    return models[33].family;
}
pub fn model_33_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_34_id() []const u8 {
    return models[34].id;
}
pub fn model_34_context() u32 {
    return models[34].context_window;
}
pub fn model_34_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_34_family() []const u8 {
    return models[34].family;
}
pub fn model_34_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_35_id() []const u8 {
    return models[35].id;
}
pub fn model_35_context() u32 {
    return models[35].context_window;
}
pub fn model_35_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_35_family() []const u8 {
    return models[35].family;
}
pub fn model_35_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_36_id() []const u8 {
    return models[36].id;
}
pub fn model_36_context() u32 {
    return models[36].context_window;
}
pub fn model_36_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_36_family() []const u8 {
    return models[36].family;
}
pub fn model_36_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_37_id() []const u8 {
    return models[37].id;
}
pub fn model_37_context() u32 {
    return models[37].context_window;
}
pub fn model_37_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_37_family() []const u8 {
    return models[37].family;
}
pub fn model_37_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_38_id() []const u8 {
    return models[38].id;
}
pub fn model_38_context() u32 {
    return models[38].context_window;
}
pub fn model_38_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_38_family() []const u8 {
    return models[38].family;
}
pub fn model_38_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_39_id() []const u8 {
    return models[39].id;
}
pub fn model_39_context() u32 {
    return models[39].context_window;
}
pub fn model_39_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_39_family() []const u8 {
    return models[39].family;
}
pub fn model_39_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_40_id() []const u8 {
    return models[40].id;
}
pub fn model_40_context() u32 {
    return models[40].context_window;
}
pub fn model_40_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_40_family() []const u8 {
    return models[40].family;
}
pub fn model_40_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_41_id() []const u8 {
    return models[41].id;
}
pub fn model_41_context() u32 {
    return models[41].context_window;
}
pub fn model_41_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_41_family() []const u8 {
    return models[41].family;
}
pub fn model_41_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_42_id() []const u8 {
    return models[42].id;
}
pub fn model_42_context() u32 {
    return models[42].context_window;
}
pub fn model_42_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_42_family() []const u8 {
    return models[42].family;
}
pub fn model_42_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_43_id() []const u8 {
    return models[43].id;
}
pub fn model_43_context() u32 {
    return models[43].context_window;
}
pub fn model_43_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_43_family() []const u8 {
    return models[43].family;
}
pub fn model_43_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_44_id() []const u8 {
    return models[44].id;
}
pub fn model_44_context() u32 {
    return models[44].context_window;
}
pub fn model_44_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_44_family() []const u8 {
    return models[44].family;
}
pub fn model_44_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_45_id() []const u8 {
    return models[45].id;
}
pub fn model_45_context() u32 {
    return models[45].context_window;
}
pub fn model_45_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_45_family() []const u8 {
    return models[45].family;
}
pub fn model_45_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_46_id() []const u8 {
    return models[46].id;
}
pub fn model_46_context() u32 {
    return models[46].context_window;
}
pub fn model_46_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_46_family() []const u8 {
    return models[46].family;
}
pub fn model_46_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_47_id() []const u8 {
    return models[47].id;
}
pub fn model_47_context() u32 {
    return models[47].context_window;
}
pub fn model_47_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_47_family() []const u8 {
    return models[47].family;
}
pub fn model_47_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_48_id() []const u8 {
    return models[48].id;
}
pub fn model_48_context() u32 {
    return models[48].context_window;
}
pub fn model_48_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_48_family() []const u8 {
    return models[48].family;
}
pub fn model_48_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_49_id() []const u8 {
    return models[49].id;
}
pub fn model_49_context() u32 {
    return models[49].context_window;
}
pub fn model_49_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_49_family() []const u8 {
    return models[49].family;
}
pub fn model_49_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_50_id() []const u8 {
    return models[50].id;
}
pub fn model_50_context() u32 {
    return models[50].context_window;
}
pub fn model_50_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_50_family() []const u8 {
    return models[50].family;
}
pub fn model_50_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_51_id() []const u8 {
    return models[51].id;
}
pub fn model_51_context() u32 {
    return models[51].context_window;
}
pub fn model_51_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_51_family() []const u8 {
    return models[51].family;
}
pub fn model_51_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_52_id() []const u8 {
    return models[52].id;
}
pub fn model_52_context() u32 {
    return models[52].context_window;
}
pub fn model_52_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_52_family() []const u8 {
    return models[52].family;
}
pub fn model_52_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_53_id() []const u8 {
    return models[53].id;
}
pub fn model_53_context() u32 {
    return models[53].context_window;
}
pub fn model_53_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_53_family() []const u8 {
    return models[53].family;
}
pub fn model_53_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_54_id() []const u8 {
    return models[54].id;
}
pub fn model_54_context() u32 {
    return models[54].context_window;
}
pub fn model_54_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_54_family() []const u8 {
    return models[54].family;
}
pub fn model_54_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_55_id() []const u8 {
    return models[55].id;
}
pub fn model_55_context() u32 {
    return models[55].context_window;
}
pub fn model_55_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_55_family() []const u8 {
    return models[55].family;
}
pub fn model_55_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_56_id() []const u8 {
    return models[56].id;
}
pub fn model_56_context() u32 {
    return models[56].context_window;
}
pub fn model_56_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_56_family() []const u8 {
    return models[56].family;
}
pub fn model_56_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_57_id() []const u8 {
    return models[57].id;
}
pub fn model_57_context() u32 {
    return models[57].context_window;
}
pub fn model_57_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_57_family() []const u8 {
    return models[57].family;
}
pub fn model_57_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_58_id() []const u8 {
    return models[58].id;
}
pub fn model_58_context() u32 {
    return models[58].context_window;
}
pub fn model_58_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_58_family() []const u8 {
    return models[58].family;
}
pub fn model_58_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_59_id() []const u8 {
    return models[59].id;
}
pub fn model_59_context() u32 {
    return models[59].context_window;
}
pub fn model_59_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_59_family() []const u8 {
    return models[59].family;
}
pub fn model_59_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_60_id() []const u8 {
    return models[60].id;
}
pub fn model_60_context() u32 {
    return models[60].context_window;
}
pub fn model_60_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_60_family() []const u8 {
    return models[60].family;
}
pub fn model_60_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_61_id() []const u8 {
    return models[61].id;
}
pub fn model_61_context() u32 {
    return models[61].context_window;
}
pub fn model_61_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_61_family() []const u8 {
    return models[61].family;
}
pub fn model_61_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_62_id() []const u8 {
    return models[62].id;
}
pub fn model_62_context() u32 {
    return models[62].context_window;
}
pub fn model_62_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_62_family() []const u8 {
    return models[62].family;
}
pub fn model_62_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_63_id() []const u8 {
    return models[63].id;
}
pub fn model_63_context() u32 {
    return models[63].context_window;
}
pub fn model_63_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_63_family() []const u8 {
    return models[63].family;
}
pub fn model_63_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_64_id() []const u8 {
    return models[64].id;
}
pub fn model_64_context() u32 {
    return models[64].context_window;
}
pub fn model_64_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_64_family() []const u8 {
    return models[64].family;
}
pub fn model_64_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_65_id() []const u8 {
    return models[65].id;
}
pub fn model_65_context() u32 {
    return models[65].context_window;
}
pub fn model_65_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_65_family() []const u8 {
    return models[65].family;
}
pub fn model_65_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_66_id() []const u8 {
    return models[66].id;
}
pub fn model_66_context() u32 {
    return models[66].context_window;
}
pub fn model_66_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_66_family() []const u8 {
    return models[66].family;
}
pub fn model_66_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_67_id() []const u8 {
    return models[67].id;
}
pub fn model_67_context() u32 {
    return models[67].context_window;
}
pub fn model_67_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_67_family() []const u8 {
    return models[67].family;
}
pub fn model_67_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_68_id() []const u8 {
    return models[68].id;
}
pub fn model_68_context() u32 {
    return models[68].context_window;
}
pub fn model_68_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_68_family() []const u8 {
    return models[68].family;
}
pub fn model_68_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_69_id() []const u8 {
    return models[69].id;
}
pub fn model_69_context() u32 {
    return models[69].context_window;
}
pub fn model_69_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_69_family() []const u8 {
    return models[69].family;
}
pub fn model_69_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_70_id() []const u8 {
    return models[70].id;
}
pub fn model_70_context() u32 {
    return models[70].context_window;
}
pub fn model_70_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_70_family() []const u8 {
    return models[70].family;
}
pub fn model_70_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_71_id() []const u8 {
    return models[71].id;
}
pub fn model_71_context() u32 {
    return models[71].context_window;
}
pub fn model_71_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_71_family() []const u8 {
    return models[71].family;
}
pub fn model_71_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_72_id() []const u8 {
    return models[72].id;
}
pub fn model_72_context() u32 {
    return models[72].context_window;
}
pub fn model_72_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_72_family() []const u8 {
    return models[72].family;
}
pub fn model_72_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_73_id() []const u8 {
    return models[73].id;
}
pub fn model_73_context() u32 {
    return models[73].context_window;
}
pub fn model_73_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_73_family() []const u8 {
    return models[73].family;
}
pub fn model_73_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_74_id() []const u8 {
    return models[74].id;
}
pub fn model_74_context() u32 {
    return models[74].context_window;
}
pub fn model_74_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_74_family() []const u8 {
    return models[74].family;
}
pub fn model_74_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_75_id() []const u8 {
    return models[75].id;
}
pub fn model_75_context() u32 {
    return models[75].context_window;
}
pub fn model_75_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_75_family() []const u8 {
    return models[75].family;
}
pub fn model_75_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_76_id() []const u8 {
    return models[76].id;
}
pub fn model_76_context() u32 {
    return models[76].context_window;
}
pub fn model_76_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_76_family() []const u8 {
    return models[76].family;
}
pub fn model_76_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_77_id() []const u8 {
    return models[77].id;
}
pub fn model_77_context() u32 {
    return models[77].context_window;
}
pub fn model_77_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_77_family() []const u8 {
    return models[77].family;
}
pub fn model_77_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_78_id() []const u8 {
    return models[78].id;
}
pub fn model_78_context() u32 {
    return models[78].context_window;
}
pub fn model_78_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_78_family() []const u8 {
    return models[78].family;
}
pub fn model_78_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_79_id() []const u8 {
    return models[79].id;
}
pub fn model_79_context() u32 {
    return models[79].context_window;
}
pub fn model_79_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_79_family() []const u8 {
    return models[79].family;
}
pub fn model_79_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 0 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

