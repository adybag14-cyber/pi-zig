//! Generated model catalog shard 34 for package ai.
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

pub const shard_index: u32 = 34;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-3400", .provider = "openai", .display = "Openai Chat 3400", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3401", .provider = "anthropic", .display = "Anthropic Code 3401", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3402", .provider = "google", .display = "Google Reason 3402", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-3403", .provider = "groq", .display = "Groq Vision 3403", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3404", .provider = "xai", .display = "Xai Embed 3404", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3405", .provider = "deepseek", .display = "Deepseek Audio 3405", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3406", .provider = "mistral", .display = "Mistral Fast 3406", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3407", .provider = "together", .display = "Together Large 3407", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3408", .provider = "fireworks", .display = "Fireworks Mini 3408", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3409", .provider = "openrouter", .display = "Openrouter Nano 3409", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-3410", .provider = "cerebras", .display = "Cerebras Pro 3410", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3411", .provider = "ollama", .display = "Ollama Ultra 3411", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3412", .provider = "lmstudio", .display = "Lmstudio Turbo 3412", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3413", .provider = "vllm", .display = "Vllm Instruct 3413", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3414", .provider = "azure", .display = "Azure Base 3414", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3415", .provider = "bedrock", .display = "Bedrock Preview 3415", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3416", .provider = "vertex", .display = "Vertex Experimental 3416", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-3417", .provider = "perplexity", .display = "Perplexity Stable 3417", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3418", .provider = "cohere", .display = "Cohere Legacy 3418", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3419", .provider = "nvidia", .display = "Nvidia Edge 3419", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3420", .provider = "sambanova", .display = "Sambanova Chat 3420", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3421", .provider = "github", .display = "Github Code 3421", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3422", .provider = "huggingface", .display = "Huggingface Reason 3422", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3423", .provider = "replicate", .display = "Replicate Vision 3423", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-3424", .provider = "anyscale", .display = "Anyscale Embed 3424", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3425", .provider = "databricks", .display = "Databricks Audio 3425", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3426", .provider = "moonshot", .display = "Moonshot Fast 3426", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3427", .provider = "qwen", .display = "Qwen Large 3427", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3428", .provider = "minimax", .display = "Minimax Mini 3428", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3429", .provider = "zhipu", .display = "Zhipu Nano 3429", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3430", .provider = "baichuan", .display = "Baichuan Pro 3430", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-3431", .provider = "yi", .display = "Yi Ultra 3431", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3432", .provider = "siliconflow", .display = "Siliconflow Turbo 3432", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3433", .provider = "novita", .display = "Novita Instruct 3433", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3434", .provider = "lepton", .display = "Lepton Base 3434", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3435", .provider = "deepinfra", .display = "Deepinfra Preview 3435", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3436", .provider = "friendli", .display = "Friendli Experimental 3436", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3437", .provider = "hyperbolic", .display = "Hyperbolic Stable 3437", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-3438", .provider = "lambda", .display = "Lambda Legacy 3438", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3439", .provider = "nebius", .display = "Nebius Edge 3439", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3440", .provider = "openai", .display = "Openai Chat 3440", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3441", .provider = "anthropic", .display = "Anthropic Code 3441", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3442", .provider = "google", .display = "Google Reason 3442", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3443", .provider = "groq", .display = "Groq Vision 3443", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3444", .provider = "xai", .display = "Xai Embed 3444", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-3445", .provider = "deepseek", .display = "Deepseek Audio 3445", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3446", .provider = "mistral", .display = "Mistral Fast 3446", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3447", .provider = "together", .display = "Together Large 3447", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3448", .provider = "fireworks", .display = "Fireworks Mini 3448", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3449", .provider = "openrouter", .display = "Openrouter Nano 3449", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3450", .provider = "cerebras", .display = "Cerebras Pro 3450", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3451", .provider = "ollama", .display = "Ollama Ultra 3451", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3452", .provider = "lmstudio", .display = "Lmstudio Turbo 3452", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3453", .provider = "vllm", .display = "Vllm Instruct 3453", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3454", .provider = "azure", .display = "Azure Base 3454", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3455", .provider = "bedrock", .display = "Bedrock Preview 3455", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3456", .provider = "vertex", .display = "Vertex Experimental 3456", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3457", .provider = "perplexity", .display = "Perplexity Stable 3457", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3458", .provider = "cohere", .display = "Cohere Legacy 3458", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-3459", .provider = "nvidia", .display = "Nvidia Edge 3459", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3460", .provider = "sambanova", .display = "Sambanova Chat 3460", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3461", .provider = "github", .display = "Github Code 3461", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3462", .provider = "huggingface", .display = "Huggingface Reason 3462", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3463", .provider = "replicate", .display = "Replicate Vision 3463", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3464", .provider = "anyscale", .display = "Anyscale Embed 3464", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3465", .provider = "databricks", .display = "Databricks Audio 3465", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-3466", .provider = "moonshot", .display = "Moonshot Fast 3466", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3467", .provider = "qwen", .display = "Qwen Large 3467", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3468", .provider = "minimax", .display = "Minimax Mini 3468", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3469", .provider = "zhipu", .display = "Zhipu Nano 3469", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3470", .provider = "baichuan", .display = "Baichuan Pro 3470", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3471", .provider = "yi", .display = "Yi Ultra 3471", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3472", .provider = "siliconflow", .display = "Siliconflow Turbo 3472", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-3473", .provider = "novita", .display = "Novita Instruct 3473", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3474", .provider = "lepton", .display = "Lepton Base 3474", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3475", .provider = "deepinfra", .display = "Deepinfra Preview 3475", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3476", .provider = "friendli", .display = "Friendli Experimental 3476", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3477", .provider = "hyperbolic", .display = "Hyperbolic Stable 3477", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3478", .provider = "lambda", .display = "Lambda Legacy 3478", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3479", .provider = "nebius", .display = "Nebius Edge 3479", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-3480", .provider = "openai", .display = "Openai Chat 3480", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3481", .provider = "anthropic", .display = "Anthropic Code 3481", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3482", .provider = "google", .display = "Google Reason 3482", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3483", .provider = "groq", .display = "Groq Vision 3483", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3484", .provider = "xai", .display = "Xai Embed 3484", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3485", .provider = "deepseek", .display = "Deepseek Audio 3485", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3486", .provider = "mistral", .display = "Mistral Fast 3486", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-3487", .provider = "together", .display = "Together Large 3487", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3488", .provider = "fireworks", .display = "Fireworks Mini 3488", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3489", .provider = "openrouter", .display = "Openrouter Nano 3489", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3490", .provider = "cerebras", .display = "Cerebras Pro 3490", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3491", .provider = "ollama", .display = "Ollama Ultra 3491", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3492", .provider = "lmstudio", .display = "Lmstudio Turbo 3492", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3493", .provider = "vllm", .display = "Vllm Instruct 3493", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-3494", .provider = "azure", .display = "Azure Base 3494", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3495", .provider = "bedrock", .display = "Bedrock Preview 3495", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3496", .provider = "vertex", .display = "Vertex Experimental 3496", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3497", .provider = "perplexity", .display = "Perplexity Stable 3497", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3498", .provider = "cohere", .display = "Cohere Legacy 3498", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3499", .provider = "nvidia", .display = "Nvidia Edge 3499", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3400_id() []const u8 {
    return models[0].id;
}
pub fn model_3400_context() u32 {
    return models[0].context_window;
}
pub fn model_3400_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3400_family() []const u8 {
    return models[0].family;
}
pub fn model_3400_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3401_id() []const u8 {
    return models[1].id;
}
pub fn model_3401_context() u32 {
    return models[1].context_window;
}
pub fn model_3401_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3401_family() []const u8 {
    return models[1].family;
}
pub fn model_3401_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3402_id() []const u8 {
    return models[2].id;
}
pub fn model_3402_context() u32 {
    return models[2].context_window;
}
pub fn model_3402_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3402_family() []const u8 {
    return models[2].family;
}
pub fn model_3402_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3403_id() []const u8 {
    return models[3].id;
}
pub fn model_3403_context() u32 {
    return models[3].context_window;
}
pub fn model_3403_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3403_family() []const u8 {
    return models[3].family;
}
pub fn model_3403_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3404_id() []const u8 {
    return models[4].id;
}
pub fn model_3404_context() u32 {
    return models[4].context_window;
}
pub fn model_3404_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3404_family() []const u8 {
    return models[4].family;
}
pub fn model_3404_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3405_id() []const u8 {
    return models[5].id;
}
pub fn model_3405_context() u32 {
    return models[5].context_window;
}
pub fn model_3405_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3405_family() []const u8 {
    return models[5].family;
}
pub fn model_3405_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3406_id() []const u8 {
    return models[6].id;
}
pub fn model_3406_context() u32 {
    return models[6].context_window;
}
pub fn model_3406_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3406_family() []const u8 {
    return models[6].family;
}
pub fn model_3406_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3407_id() []const u8 {
    return models[7].id;
}
pub fn model_3407_context() u32 {
    return models[7].context_window;
}
pub fn model_3407_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3407_family() []const u8 {
    return models[7].family;
}
pub fn model_3407_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3408_id() []const u8 {
    return models[8].id;
}
pub fn model_3408_context() u32 {
    return models[8].context_window;
}
pub fn model_3408_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3408_family() []const u8 {
    return models[8].family;
}
pub fn model_3408_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3409_id() []const u8 {
    return models[9].id;
}
pub fn model_3409_context() u32 {
    return models[9].context_window;
}
pub fn model_3409_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3409_family() []const u8 {
    return models[9].family;
}
pub fn model_3409_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3410_id() []const u8 {
    return models[10].id;
}
pub fn model_3410_context() u32 {
    return models[10].context_window;
}
pub fn model_3410_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3410_family() []const u8 {
    return models[10].family;
}
pub fn model_3410_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3411_id() []const u8 {
    return models[11].id;
}
pub fn model_3411_context() u32 {
    return models[11].context_window;
}
pub fn model_3411_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3411_family() []const u8 {
    return models[11].family;
}
pub fn model_3411_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3412_id() []const u8 {
    return models[12].id;
}
pub fn model_3412_context() u32 {
    return models[12].context_window;
}
pub fn model_3412_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3412_family() []const u8 {
    return models[12].family;
}
pub fn model_3412_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3413_id() []const u8 {
    return models[13].id;
}
pub fn model_3413_context() u32 {
    return models[13].context_window;
}
pub fn model_3413_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3413_family() []const u8 {
    return models[13].family;
}
pub fn model_3413_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3414_id() []const u8 {
    return models[14].id;
}
pub fn model_3414_context() u32 {
    return models[14].context_window;
}
pub fn model_3414_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3414_family() []const u8 {
    return models[14].family;
}
pub fn model_3414_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3415_id() []const u8 {
    return models[15].id;
}
pub fn model_3415_context() u32 {
    return models[15].context_window;
}
pub fn model_3415_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3415_family() []const u8 {
    return models[15].family;
}
pub fn model_3415_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3416_id() []const u8 {
    return models[16].id;
}
pub fn model_3416_context() u32 {
    return models[16].context_window;
}
pub fn model_3416_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3416_family() []const u8 {
    return models[16].family;
}
pub fn model_3416_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3417_id() []const u8 {
    return models[17].id;
}
pub fn model_3417_context() u32 {
    return models[17].context_window;
}
pub fn model_3417_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3417_family() []const u8 {
    return models[17].family;
}
pub fn model_3417_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3418_id() []const u8 {
    return models[18].id;
}
pub fn model_3418_context() u32 {
    return models[18].context_window;
}
pub fn model_3418_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3418_family() []const u8 {
    return models[18].family;
}
pub fn model_3418_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3419_id() []const u8 {
    return models[19].id;
}
pub fn model_3419_context() u32 {
    return models[19].context_window;
}
pub fn model_3419_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3419_family() []const u8 {
    return models[19].family;
}
pub fn model_3419_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3420_id() []const u8 {
    return models[20].id;
}
pub fn model_3420_context() u32 {
    return models[20].context_window;
}
pub fn model_3420_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3420_family() []const u8 {
    return models[20].family;
}
pub fn model_3420_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3421_id() []const u8 {
    return models[21].id;
}
pub fn model_3421_context() u32 {
    return models[21].context_window;
}
pub fn model_3421_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3421_family() []const u8 {
    return models[21].family;
}
pub fn model_3421_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3422_id() []const u8 {
    return models[22].id;
}
pub fn model_3422_context() u32 {
    return models[22].context_window;
}
pub fn model_3422_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3422_family() []const u8 {
    return models[22].family;
}
pub fn model_3422_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3423_id() []const u8 {
    return models[23].id;
}
pub fn model_3423_context() u32 {
    return models[23].context_window;
}
pub fn model_3423_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3423_family() []const u8 {
    return models[23].family;
}
pub fn model_3423_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3424_id() []const u8 {
    return models[24].id;
}
pub fn model_3424_context() u32 {
    return models[24].context_window;
}
pub fn model_3424_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3424_family() []const u8 {
    return models[24].family;
}
pub fn model_3424_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3425_id() []const u8 {
    return models[25].id;
}
pub fn model_3425_context() u32 {
    return models[25].context_window;
}
pub fn model_3425_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3425_family() []const u8 {
    return models[25].family;
}
pub fn model_3425_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3426_id() []const u8 {
    return models[26].id;
}
pub fn model_3426_context() u32 {
    return models[26].context_window;
}
pub fn model_3426_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3426_family() []const u8 {
    return models[26].family;
}
pub fn model_3426_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3427_id() []const u8 {
    return models[27].id;
}
pub fn model_3427_context() u32 {
    return models[27].context_window;
}
pub fn model_3427_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3427_family() []const u8 {
    return models[27].family;
}
pub fn model_3427_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3428_id() []const u8 {
    return models[28].id;
}
pub fn model_3428_context() u32 {
    return models[28].context_window;
}
pub fn model_3428_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3428_family() []const u8 {
    return models[28].family;
}
pub fn model_3428_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3429_id() []const u8 {
    return models[29].id;
}
pub fn model_3429_context() u32 {
    return models[29].context_window;
}
pub fn model_3429_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3429_family() []const u8 {
    return models[29].family;
}
pub fn model_3429_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3430_id() []const u8 {
    return models[30].id;
}
pub fn model_3430_context() u32 {
    return models[30].context_window;
}
pub fn model_3430_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3430_family() []const u8 {
    return models[30].family;
}
pub fn model_3430_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3431_id() []const u8 {
    return models[31].id;
}
pub fn model_3431_context() u32 {
    return models[31].context_window;
}
pub fn model_3431_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3431_family() []const u8 {
    return models[31].family;
}
pub fn model_3431_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3432_id() []const u8 {
    return models[32].id;
}
pub fn model_3432_context() u32 {
    return models[32].context_window;
}
pub fn model_3432_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3432_family() []const u8 {
    return models[32].family;
}
pub fn model_3432_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3433_id() []const u8 {
    return models[33].id;
}
pub fn model_3433_context() u32 {
    return models[33].context_window;
}
pub fn model_3433_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3433_family() []const u8 {
    return models[33].family;
}
pub fn model_3433_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3434_id() []const u8 {
    return models[34].id;
}
pub fn model_3434_context() u32 {
    return models[34].context_window;
}
pub fn model_3434_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3434_family() []const u8 {
    return models[34].family;
}
pub fn model_3434_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3435_id() []const u8 {
    return models[35].id;
}
pub fn model_3435_context() u32 {
    return models[35].context_window;
}
pub fn model_3435_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3435_family() []const u8 {
    return models[35].family;
}
pub fn model_3435_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3436_id() []const u8 {
    return models[36].id;
}
pub fn model_3436_context() u32 {
    return models[36].context_window;
}
pub fn model_3436_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3436_family() []const u8 {
    return models[36].family;
}
pub fn model_3436_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3437_id() []const u8 {
    return models[37].id;
}
pub fn model_3437_context() u32 {
    return models[37].context_window;
}
pub fn model_3437_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3437_family() []const u8 {
    return models[37].family;
}
pub fn model_3437_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3438_id() []const u8 {
    return models[38].id;
}
pub fn model_3438_context() u32 {
    return models[38].context_window;
}
pub fn model_3438_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3438_family() []const u8 {
    return models[38].family;
}
pub fn model_3438_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3439_id() []const u8 {
    return models[39].id;
}
pub fn model_3439_context() u32 {
    return models[39].context_window;
}
pub fn model_3439_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3439_family() []const u8 {
    return models[39].family;
}
pub fn model_3439_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3440_id() []const u8 {
    return models[40].id;
}
pub fn model_3440_context() u32 {
    return models[40].context_window;
}
pub fn model_3440_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3440_family() []const u8 {
    return models[40].family;
}
pub fn model_3440_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3441_id() []const u8 {
    return models[41].id;
}
pub fn model_3441_context() u32 {
    return models[41].context_window;
}
pub fn model_3441_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3441_family() []const u8 {
    return models[41].family;
}
pub fn model_3441_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3442_id() []const u8 {
    return models[42].id;
}
pub fn model_3442_context() u32 {
    return models[42].context_window;
}
pub fn model_3442_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3442_family() []const u8 {
    return models[42].family;
}
pub fn model_3442_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3443_id() []const u8 {
    return models[43].id;
}
pub fn model_3443_context() u32 {
    return models[43].context_window;
}
pub fn model_3443_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3443_family() []const u8 {
    return models[43].family;
}
pub fn model_3443_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3444_id() []const u8 {
    return models[44].id;
}
pub fn model_3444_context() u32 {
    return models[44].context_window;
}
pub fn model_3444_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3444_family() []const u8 {
    return models[44].family;
}
pub fn model_3444_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3445_id() []const u8 {
    return models[45].id;
}
pub fn model_3445_context() u32 {
    return models[45].context_window;
}
pub fn model_3445_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3445_family() []const u8 {
    return models[45].family;
}
pub fn model_3445_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3446_id() []const u8 {
    return models[46].id;
}
pub fn model_3446_context() u32 {
    return models[46].context_window;
}
pub fn model_3446_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3446_family() []const u8 {
    return models[46].family;
}
pub fn model_3446_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3447_id() []const u8 {
    return models[47].id;
}
pub fn model_3447_context() u32 {
    return models[47].context_window;
}
pub fn model_3447_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3447_family() []const u8 {
    return models[47].family;
}
pub fn model_3447_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3448_id() []const u8 {
    return models[48].id;
}
pub fn model_3448_context() u32 {
    return models[48].context_window;
}
pub fn model_3448_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3448_family() []const u8 {
    return models[48].family;
}
pub fn model_3448_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3449_id() []const u8 {
    return models[49].id;
}
pub fn model_3449_context() u32 {
    return models[49].context_window;
}
pub fn model_3449_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3449_family() []const u8 {
    return models[49].family;
}
pub fn model_3449_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3450_id() []const u8 {
    return models[50].id;
}
pub fn model_3450_context() u32 {
    return models[50].context_window;
}
pub fn model_3450_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3450_family() []const u8 {
    return models[50].family;
}
pub fn model_3450_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3451_id() []const u8 {
    return models[51].id;
}
pub fn model_3451_context() u32 {
    return models[51].context_window;
}
pub fn model_3451_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3451_family() []const u8 {
    return models[51].family;
}
pub fn model_3451_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3452_id() []const u8 {
    return models[52].id;
}
pub fn model_3452_context() u32 {
    return models[52].context_window;
}
pub fn model_3452_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3452_family() []const u8 {
    return models[52].family;
}
pub fn model_3452_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3453_id() []const u8 {
    return models[53].id;
}
pub fn model_3453_context() u32 {
    return models[53].context_window;
}
pub fn model_3453_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3453_family() []const u8 {
    return models[53].family;
}
pub fn model_3453_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3454_id() []const u8 {
    return models[54].id;
}
pub fn model_3454_context() u32 {
    return models[54].context_window;
}
pub fn model_3454_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3454_family() []const u8 {
    return models[54].family;
}
pub fn model_3454_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3455_id() []const u8 {
    return models[55].id;
}
pub fn model_3455_context() u32 {
    return models[55].context_window;
}
pub fn model_3455_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3455_family() []const u8 {
    return models[55].family;
}
pub fn model_3455_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3456_id() []const u8 {
    return models[56].id;
}
pub fn model_3456_context() u32 {
    return models[56].context_window;
}
pub fn model_3456_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3456_family() []const u8 {
    return models[56].family;
}
pub fn model_3456_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3457_id() []const u8 {
    return models[57].id;
}
pub fn model_3457_context() u32 {
    return models[57].context_window;
}
pub fn model_3457_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3457_family() []const u8 {
    return models[57].family;
}
pub fn model_3457_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3458_id() []const u8 {
    return models[58].id;
}
pub fn model_3458_context() u32 {
    return models[58].context_window;
}
pub fn model_3458_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3458_family() []const u8 {
    return models[58].family;
}
pub fn model_3458_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3459_id() []const u8 {
    return models[59].id;
}
pub fn model_3459_context() u32 {
    return models[59].context_window;
}
pub fn model_3459_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3459_family() []const u8 {
    return models[59].family;
}
pub fn model_3459_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3460_id() []const u8 {
    return models[60].id;
}
pub fn model_3460_context() u32 {
    return models[60].context_window;
}
pub fn model_3460_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3460_family() []const u8 {
    return models[60].family;
}
pub fn model_3460_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3461_id() []const u8 {
    return models[61].id;
}
pub fn model_3461_context() u32 {
    return models[61].context_window;
}
pub fn model_3461_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3461_family() []const u8 {
    return models[61].family;
}
pub fn model_3461_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3462_id() []const u8 {
    return models[62].id;
}
pub fn model_3462_context() u32 {
    return models[62].context_window;
}
pub fn model_3462_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3462_family() []const u8 {
    return models[62].family;
}
pub fn model_3462_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3463_id() []const u8 {
    return models[63].id;
}
pub fn model_3463_context() u32 {
    return models[63].context_window;
}
pub fn model_3463_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3463_family() []const u8 {
    return models[63].family;
}
pub fn model_3463_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3464_id() []const u8 {
    return models[64].id;
}
pub fn model_3464_context() u32 {
    return models[64].context_window;
}
pub fn model_3464_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3464_family() []const u8 {
    return models[64].family;
}
pub fn model_3464_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3465_id() []const u8 {
    return models[65].id;
}
pub fn model_3465_context() u32 {
    return models[65].context_window;
}
pub fn model_3465_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3465_family() []const u8 {
    return models[65].family;
}
pub fn model_3465_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3466_id() []const u8 {
    return models[66].id;
}
pub fn model_3466_context() u32 {
    return models[66].context_window;
}
pub fn model_3466_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3466_family() []const u8 {
    return models[66].family;
}
pub fn model_3466_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3467_id() []const u8 {
    return models[67].id;
}
pub fn model_3467_context() u32 {
    return models[67].context_window;
}
pub fn model_3467_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3467_family() []const u8 {
    return models[67].family;
}
pub fn model_3467_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3468_id() []const u8 {
    return models[68].id;
}
pub fn model_3468_context() u32 {
    return models[68].context_window;
}
pub fn model_3468_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3468_family() []const u8 {
    return models[68].family;
}
pub fn model_3468_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3469_id() []const u8 {
    return models[69].id;
}
pub fn model_3469_context() u32 {
    return models[69].context_window;
}
pub fn model_3469_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3469_family() []const u8 {
    return models[69].family;
}
pub fn model_3469_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3470_id() []const u8 {
    return models[70].id;
}
pub fn model_3470_context() u32 {
    return models[70].context_window;
}
pub fn model_3470_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3470_family() []const u8 {
    return models[70].family;
}
pub fn model_3470_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3471_id() []const u8 {
    return models[71].id;
}
pub fn model_3471_context() u32 {
    return models[71].context_window;
}
pub fn model_3471_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3471_family() []const u8 {
    return models[71].family;
}
pub fn model_3471_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3472_id() []const u8 {
    return models[72].id;
}
pub fn model_3472_context() u32 {
    return models[72].context_window;
}
pub fn model_3472_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3472_family() []const u8 {
    return models[72].family;
}
pub fn model_3472_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3473_id() []const u8 {
    return models[73].id;
}
pub fn model_3473_context() u32 {
    return models[73].context_window;
}
pub fn model_3473_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3473_family() []const u8 {
    return models[73].family;
}
pub fn model_3473_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3474_id() []const u8 {
    return models[74].id;
}
pub fn model_3474_context() u32 {
    return models[74].context_window;
}
pub fn model_3474_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3474_family() []const u8 {
    return models[74].family;
}
pub fn model_3474_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3475_id() []const u8 {
    return models[75].id;
}
pub fn model_3475_context() u32 {
    return models[75].context_window;
}
pub fn model_3475_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3475_family() []const u8 {
    return models[75].family;
}
pub fn model_3475_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3476_id() []const u8 {
    return models[76].id;
}
pub fn model_3476_context() u32 {
    return models[76].context_window;
}
pub fn model_3476_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3476_family() []const u8 {
    return models[76].family;
}
pub fn model_3476_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3477_id() []const u8 {
    return models[77].id;
}
pub fn model_3477_context() u32 {
    return models[77].context_window;
}
pub fn model_3477_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3477_family() []const u8 {
    return models[77].family;
}
pub fn model_3477_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3478_id() []const u8 {
    return models[78].id;
}
pub fn model_3478_context() u32 {
    return models[78].context_window;
}
pub fn model_3478_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3478_family() []const u8 {
    return models[78].family;
}
pub fn model_3478_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3479_id() []const u8 {
    return models[79].id;
}
pub fn model_3479_context() u32 {
    return models[79].context_window;
}
pub fn model_3479_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3479_family() []const u8 {
    return models[79].family;
}
pub fn model_3479_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 34 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

