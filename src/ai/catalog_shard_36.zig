//! Generated model catalog shard 36 for package ai.
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

pub const shard_index: u32 = 36;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-3600", .provider = "openai", .display = "Openai Chat 3600", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3601", .provider = "anthropic", .display = "Anthropic Code 3601", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3602", .provider = "google", .display = "Google Reason 3602", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3603", .provider = "groq", .display = "Groq Vision 3603", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3604", .provider = "xai", .display = "Xai Embed 3604", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3605", .provider = "deepseek", .display = "Deepseek Audio 3605", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-3606", .provider = "mistral", .display = "Mistral Fast 3606", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3607", .provider = "together", .display = "Together Large 3607", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3608", .provider = "fireworks", .display = "Fireworks Mini 3608", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3609", .provider = "openrouter", .display = "Openrouter Nano 3609", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3610", .provider = "cerebras", .display = "Cerebras Pro 3610", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3611", .provider = "ollama", .display = "Ollama Ultra 3611", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3612", .provider = "lmstudio", .display = "Lmstudio Turbo 3612", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-3613", .provider = "vllm", .display = "Vllm Instruct 3613", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3614", .provider = "azure", .display = "Azure Base 3614", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3615", .provider = "bedrock", .display = "Bedrock Preview 3615", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3616", .provider = "vertex", .display = "Vertex Experimental 3616", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3617", .provider = "perplexity", .display = "Perplexity Stable 3617", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3618", .provider = "cohere", .display = "Cohere Legacy 3618", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3619", .provider = "nvidia", .display = "Nvidia Edge 3619", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-3620", .provider = "sambanova", .display = "Sambanova Chat 3620", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3621", .provider = "github", .display = "Github Code 3621", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3622", .provider = "huggingface", .display = "Huggingface Reason 3622", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3623", .provider = "replicate", .display = "Replicate Vision 3623", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3624", .provider = "anyscale", .display = "Anyscale Embed 3624", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3625", .provider = "databricks", .display = "Databricks Audio 3625", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3626", .provider = "moonshot", .display = "Moonshot Fast 3626", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-3627", .provider = "qwen", .display = "Qwen Large 3627", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3628", .provider = "minimax", .display = "Minimax Mini 3628", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3629", .provider = "zhipu", .display = "Zhipu Nano 3629", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3630", .provider = "baichuan", .display = "Baichuan Pro 3630", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3631", .provider = "yi", .display = "Yi Ultra 3631", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3632", .provider = "siliconflow", .display = "Siliconflow Turbo 3632", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3633", .provider = "novita", .display = "Novita Instruct 3633", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-3634", .provider = "lepton", .display = "Lepton Base 3634", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3635", .provider = "deepinfra", .display = "Deepinfra Preview 3635", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3636", .provider = "friendli", .display = "Friendli Experimental 3636", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3637", .provider = "hyperbolic", .display = "Hyperbolic Stable 3637", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3638", .provider = "lambda", .display = "Lambda Legacy 3638", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3639", .provider = "nebius", .display = "Nebius Edge 3639", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3640", .provider = "openai", .display = "Openai Chat 3640", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-3641", .provider = "anthropic", .display = "Anthropic Code 3641", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3642", .provider = "google", .display = "Google Reason 3642", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3643", .provider = "groq", .display = "Groq Vision 3643", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3644", .provider = "xai", .display = "Xai Embed 3644", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3645", .provider = "deepseek", .display = "Deepseek Audio 3645", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3646", .provider = "mistral", .display = "Mistral Fast 3646", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3647", .provider = "together", .display = "Together Large 3647", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-3648", .provider = "fireworks", .display = "Fireworks Mini 3648", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3649", .provider = "openrouter", .display = "Openrouter Nano 3649", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3650", .provider = "cerebras", .display = "Cerebras Pro 3650", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3651", .provider = "ollama", .display = "Ollama Ultra 3651", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3652", .provider = "lmstudio", .display = "Lmstudio Turbo 3652", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3653", .provider = "vllm", .display = "Vllm Instruct 3653", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3654", .provider = "azure", .display = "Azure Base 3654", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-3655", .provider = "bedrock", .display = "Bedrock Preview 3655", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3656", .provider = "vertex", .display = "Vertex Experimental 3656", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3657", .provider = "perplexity", .display = "Perplexity Stable 3657", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3658", .provider = "cohere", .display = "Cohere Legacy 3658", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3659", .provider = "nvidia", .display = "Nvidia Edge 3659", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3660", .provider = "sambanova", .display = "Sambanova Chat 3660", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3661", .provider = "github", .display = "Github Code 3661", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-3662", .provider = "huggingface", .display = "Huggingface Reason 3662", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3663", .provider = "replicate", .display = "Replicate Vision 3663", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3664", .provider = "anyscale", .display = "Anyscale Embed 3664", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3665", .provider = "databricks", .display = "Databricks Audio 3665", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3666", .provider = "moonshot", .display = "Moonshot Fast 3666", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3667", .provider = "qwen", .display = "Qwen Large 3667", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3668", .provider = "minimax", .display = "Minimax Mini 3668", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-3669", .provider = "zhipu", .display = "Zhipu Nano 3669", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3670", .provider = "baichuan", .display = "Baichuan Pro 3670", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3671", .provider = "yi", .display = "Yi Ultra 3671", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3672", .provider = "siliconflow", .display = "Siliconflow Turbo 3672", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3673", .provider = "novita", .display = "Novita Instruct 3673", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3674", .provider = "lepton", .display = "Lepton Base 3674", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3675", .provider = "deepinfra", .display = "Deepinfra Preview 3675", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-3676", .provider = "friendli", .display = "Friendli Experimental 3676", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3677", .provider = "hyperbolic", .display = "Hyperbolic Stable 3677", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3678", .provider = "lambda", .display = "Lambda Legacy 3678", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3679", .provider = "nebius", .display = "Nebius Edge 3679", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3680", .provider = "openai", .display = "Openai Chat 3680", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3681", .provider = "anthropic", .display = "Anthropic Code 3681", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3682", .provider = "google", .display = "Google Reason 3682", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "groq/vision-3683", .provider = "groq", .display = "Groq Vision 3683", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3684", .provider = "xai", .display = "Xai Embed 3684", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3685", .provider = "deepseek", .display = "Deepseek Audio 3685", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3686", .provider = "mistral", .display = "Mistral Fast 3686", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3687", .provider = "together", .display = "Together Large 3687", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3688", .provider = "fireworks", .display = "Fireworks Mini 3688", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3689", .provider = "openrouter", .display = "Openrouter Nano 3689", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "cerebras/pro-3690", .provider = "cerebras", .display = "Cerebras Pro 3690", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3691", .provider = "ollama", .display = "Ollama Ultra 3691", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3692", .provider = "lmstudio", .display = "Lmstudio Turbo 3692", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3693", .provider = "vllm", .display = "Vllm Instruct 3693", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3694", .provider = "azure", .display = "Azure Base 3694", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3695", .provider = "bedrock", .display = "Bedrock Preview 3695", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3696", .provider = "vertex", .display = "Vertex Experimental 3696", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "perplexity/stable-3697", .provider = "perplexity", .display = "Perplexity Stable 3697", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3698", .provider = "cohere", .display = "Cohere Legacy 3698", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3699", .provider = "nvidia", .display = "Nvidia Edge 3699", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3600_id() []const u8 {
    return models[0].id;
}
pub fn model_3600_context() u32 {
    return models[0].context_window;
}
pub fn model_3600_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3600_family() []const u8 {
    return models[0].family;
}
pub fn model_3600_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3601_id() []const u8 {
    return models[1].id;
}
pub fn model_3601_context() u32 {
    return models[1].context_window;
}
pub fn model_3601_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3601_family() []const u8 {
    return models[1].family;
}
pub fn model_3601_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3602_id() []const u8 {
    return models[2].id;
}
pub fn model_3602_context() u32 {
    return models[2].context_window;
}
pub fn model_3602_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3602_family() []const u8 {
    return models[2].family;
}
pub fn model_3602_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3603_id() []const u8 {
    return models[3].id;
}
pub fn model_3603_context() u32 {
    return models[3].context_window;
}
pub fn model_3603_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3603_family() []const u8 {
    return models[3].family;
}
pub fn model_3603_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3604_id() []const u8 {
    return models[4].id;
}
pub fn model_3604_context() u32 {
    return models[4].context_window;
}
pub fn model_3604_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3604_family() []const u8 {
    return models[4].family;
}
pub fn model_3604_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3605_id() []const u8 {
    return models[5].id;
}
pub fn model_3605_context() u32 {
    return models[5].context_window;
}
pub fn model_3605_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3605_family() []const u8 {
    return models[5].family;
}
pub fn model_3605_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3606_id() []const u8 {
    return models[6].id;
}
pub fn model_3606_context() u32 {
    return models[6].context_window;
}
pub fn model_3606_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3606_family() []const u8 {
    return models[6].family;
}
pub fn model_3606_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3607_id() []const u8 {
    return models[7].id;
}
pub fn model_3607_context() u32 {
    return models[7].context_window;
}
pub fn model_3607_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3607_family() []const u8 {
    return models[7].family;
}
pub fn model_3607_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3608_id() []const u8 {
    return models[8].id;
}
pub fn model_3608_context() u32 {
    return models[8].context_window;
}
pub fn model_3608_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3608_family() []const u8 {
    return models[8].family;
}
pub fn model_3608_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3609_id() []const u8 {
    return models[9].id;
}
pub fn model_3609_context() u32 {
    return models[9].context_window;
}
pub fn model_3609_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3609_family() []const u8 {
    return models[9].family;
}
pub fn model_3609_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3610_id() []const u8 {
    return models[10].id;
}
pub fn model_3610_context() u32 {
    return models[10].context_window;
}
pub fn model_3610_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3610_family() []const u8 {
    return models[10].family;
}
pub fn model_3610_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3611_id() []const u8 {
    return models[11].id;
}
pub fn model_3611_context() u32 {
    return models[11].context_window;
}
pub fn model_3611_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3611_family() []const u8 {
    return models[11].family;
}
pub fn model_3611_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3612_id() []const u8 {
    return models[12].id;
}
pub fn model_3612_context() u32 {
    return models[12].context_window;
}
pub fn model_3612_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3612_family() []const u8 {
    return models[12].family;
}
pub fn model_3612_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3613_id() []const u8 {
    return models[13].id;
}
pub fn model_3613_context() u32 {
    return models[13].context_window;
}
pub fn model_3613_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3613_family() []const u8 {
    return models[13].family;
}
pub fn model_3613_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3614_id() []const u8 {
    return models[14].id;
}
pub fn model_3614_context() u32 {
    return models[14].context_window;
}
pub fn model_3614_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3614_family() []const u8 {
    return models[14].family;
}
pub fn model_3614_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3615_id() []const u8 {
    return models[15].id;
}
pub fn model_3615_context() u32 {
    return models[15].context_window;
}
pub fn model_3615_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3615_family() []const u8 {
    return models[15].family;
}
pub fn model_3615_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3616_id() []const u8 {
    return models[16].id;
}
pub fn model_3616_context() u32 {
    return models[16].context_window;
}
pub fn model_3616_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3616_family() []const u8 {
    return models[16].family;
}
pub fn model_3616_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3617_id() []const u8 {
    return models[17].id;
}
pub fn model_3617_context() u32 {
    return models[17].context_window;
}
pub fn model_3617_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3617_family() []const u8 {
    return models[17].family;
}
pub fn model_3617_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3618_id() []const u8 {
    return models[18].id;
}
pub fn model_3618_context() u32 {
    return models[18].context_window;
}
pub fn model_3618_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3618_family() []const u8 {
    return models[18].family;
}
pub fn model_3618_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3619_id() []const u8 {
    return models[19].id;
}
pub fn model_3619_context() u32 {
    return models[19].context_window;
}
pub fn model_3619_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3619_family() []const u8 {
    return models[19].family;
}
pub fn model_3619_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3620_id() []const u8 {
    return models[20].id;
}
pub fn model_3620_context() u32 {
    return models[20].context_window;
}
pub fn model_3620_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3620_family() []const u8 {
    return models[20].family;
}
pub fn model_3620_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3621_id() []const u8 {
    return models[21].id;
}
pub fn model_3621_context() u32 {
    return models[21].context_window;
}
pub fn model_3621_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3621_family() []const u8 {
    return models[21].family;
}
pub fn model_3621_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3622_id() []const u8 {
    return models[22].id;
}
pub fn model_3622_context() u32 {
    return models[22].context_window;
}
pub fn model_3622_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3622_family() []const u8 {
    return models[22].family;
}
pub fn model_3622_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3623_id() []const u8 {
    return models[23].id;
}
pub fn model_3623_context() u32 {
    return models[23].context_window;
}
pub fn model_3623_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3623_family() []const u8 {
    return models[23].family;
}
pub fn model_3623_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3624_id() []const u8 {
    return models[24].id;
}
pub fn model_3624_context() u32 {
    return models[24].context_window;
}
pub fn model_3624_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3624_family() []const u8 {
    return models[24].family;
}
pub fn model_3624_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3625_id() []const u8 {
    return models[25].id;
}
pub fn model_3625_context() u32 {
    return models[25].context_window;
}
pub fn model_3625_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3625_family() []const u8 {
    return models[25].family;
}
pub fn model_3625_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3626_id() []const u8 {
    return models[26].id;
}
pub fn model_3626_context() u32 {
    return models[26].context_window;
}
pub fn model_3626_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3626_family() []const u8 {
    return models[26].family;
}
pub fn model_3626_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3627_id() []const u8 {
    return models[27].id;
}
pub fn model_3627_context() u32 {
    return models[27].context_window;
}
pub fn model_3627_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3627_family() []const u8 {
    return models[27].family;
}
pub fn model_3627_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3628_id() []const u8 {
    return models[28].id;
}
pub fn model_3628_context() u32 {
    return models[28].context_window;
}
pub fn model_3628_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3628_family() []const u8 {
    return models[28].family;
}
pub fn model_3628_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3629_id() []const u8 {
    return models[29].id;
}
pub fn model_3629_context() u32 {
    return models[29].context_window;
}
pub fn model_3629_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3629_family() []const u8 {
    return models[29].family;
}
pub fn model_3629_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3630_id() []const u8 {
    return models[30].id;
}
pub fn model_3630_context() u32 {
    return models[30].context_window;
}
pub fn model_3630_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3630_family() []const u8 {
    return models[30].family;
}
pub fn model_3630_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3631_id() []const u8 {
    return models[31].id;
}
pub fn model_3631_context() u32 {
    return models[31].context_window;
}
pub fn model_3631_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3631_family() []const u8 {
    return models[31].family;
}
pub fn model_3631_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3632_id() []const u8 {
    return models[32].id;
}
pub fn model_3632_context() u32 {
    return models[32].context_window;
}
pub fn model_3632_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3632_family() []const u8 {
    return models[32].family;
}
pub fn model_3632_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3633_id() []const u8 {
    return models[33].id;
}
pub fn model_3633_context() u32 {
    return models[33].context_window;
}
pub fn model_3633_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3633_family() []const u8 {
    return models[33].family;
}
pub fn model_3633_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3634_id() []const u8 {
    return models[34].id;
}
pub fn model_3634_context() u32 {
    return models[34].context_window;
}
pub fn model_3634_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3634_family() []const u8 {
    return models[34].family;
}
pub fn model_3634_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3635_id() []const u8 {
    return models[35].id;
}
pub fn model_3635_context() u32 {
    return models[35].context_window;
}
pub fn model_3635_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3635_family() []const u8 {
    return models[35].family;
}
pub fn model_3635_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3636_id() []const u8 {
    return models[36].id;
}
pub fn model_3636_context() u32 {
    return models[36].context_window;
}
pub fn model_3636_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3636_family() []const u8 {
    return models[36].family;
}
pub fn model_3636_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3637_id() []const u8 {
    return models[37].id;
}
pub fn model_3637_context() u32 {
    return models[37].context_window;
}
pub fn model_3637_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3637_family() []const u8 {
    return models[37].family;
}
pub fn model_3637_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3638_id() []const u8 {
    return models[38].id;
}
pub fn model_3638_context() u32 {
    return models[38].context_window;
}
pub fn model_3638_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3638_family() []const u8 {
    return models[38].family;
}
pub fn model_3638_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3639_id() []const u8 {
    return models[39].id;
}
pub fn model_3639_context() u32 {
    return models[39].context_window;
}
pub fn model_3639_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3639_family() []const u8 {
    return models[39].family;
}
pub fn model_3639_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3640_id() []const u8 {
    return models[40].id;
}
pub fn model_3640_context() u32 {
    return models[40].context_window;
}
pub fn model_3640_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3640_family() []const u8 {
    return models[40].family;
}
pub fn model_3640_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3641_id() []const u8 {
    return models[41].id;
}
pub fn model_3641_context() u32 {
    return models[41].context_window;
}
pub fn model_3641_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3641_family() []const u8 {
    return models[41].family;
}
pub fn model_3641_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3642_id() []const u8 {
    return models[42].id;
}
pub fn model_3642_context() u32 {
    return models[42].context_window;
}
pub fn model_3642_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3642_family() []const u8 {
    return models[42].family;
}
pub fn model_3642_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3643_id() []const u8 {
    return models[43].id;
}
pub fn model_3643_context() u32 {
    return models[43].context_window;
}
pub fn model_3643_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3643_family() []const u8 {
    return models[43].family;
}
pub fn model_3643_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3644_id() []const u8 {
    return models[44].id;
}
pub fn model_3644_context() u32 {
    return models[44].context_window;
}
pub fn model_3644_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3644_family() []const u8 {
    return models[44].family;
}
pub fn model_3644_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3645_id() []const u8 {
    return models[45].id;
}
pub fn model_3645_context() u32 {
    return models[45].context_window;
}
pub fn model_3645_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3645_family() []const u8 {
    return models[45].family;
}
pub fn model_3645_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3646_id() []const u8 {
    return models[46].id;
}
pub fn model_3646_context() u32 {
    return models[46].context_window;
}
pub fn model_3646_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3646_family() []const u8 {
    return models[46].family;
}
pub fn model_3646_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3647_id() []const u8 {
    return models[47].id;
}
pub fn model_3647_context() u32 {
    return models[47].context_window;
}
pub fn model_3647_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3647_family() []const u8 {
    return models[47].family;
}
pub fn model_3647_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3648_id() []const u8 {
    return models[48].id;
}
pub fn model_3648_context() u32 {
    return models[48].context_window;
}
pub fn model_3648_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3648_family() []const u8 {
    return models[48].family;
}
pub fn model_3648_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3649_id() []const u8 {
    return models[49].id;
}
pub fn model_3649_context() u32 {
    return models[49].context_window;
}
pub fn model_3649_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3649_family() []const u8 {
    return models[49].family;
}
pub fn model_3649_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3650_id() []const u8 {
    return models[50].id;
}
pub fn model_3650_context() u32 {
    return models[50].context_window;
}
pub fn model_3650_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3650_family() []const u8 {
    return models[50].family;
}
pub fn model_3650_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3651_id() []const u8 {
    return models[51].id;
}
pub fn model_3651_context() u32 {
    return models[51].context_window;
}
pub fn model_3651_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3651_family() []const u8 {
    return models[51].family;
}
pub fn model_3651_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3652_id() []const u8 {
    return models[52].id;
}
pub fn model_3652_context() u32 {
    return models[52].context_window;
}
pub fn model_3652_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3652_family() []const u8 {
    return models[52].family;
}
pub fn model_3652_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3653_id() []const u8 {
    return models[53].id;
}
pub fn model_3653_context() u32 {
    return models[53].context_window;
}
pub fn model_3653_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3653_family() []const u8 {
    return models[53].family;
}
pub fn model_3653_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3654_id() []const u8 {
    return models[54].id;
}
pub fn model_3654_context() u32 {
    return models[54].context_window;
}
pub fn model_3654_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3654_family() []const u8 {
    return models[54].family;
}
pub fn model_3654_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3655_id() []const u8 {
    return models[55].id;
}
pub fn model_3655_context() u32 {
    return models[55].context_window;
}
pub fn model_3655_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3655_family() []const u8 {
    return models[55].family;
}
pub fn model_3655_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3656_id() []const u8 {
    return models[56].id;
}
pub fn model_3656_context() u32 {
    return models[56].context_window;
}
pub fn model_3656_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3656_family() []const u8 {
    return models[56].family;
}
pub fn model_3656_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3657_id() []const u8 {
    return models[57].id;
}
pub fn model_3657_context() u32 {
    return models[57].context_window;
}
pub fn model_3657_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3657_family() []const u8 {
    return models[57].family;
}
pub fn model_3657_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3658_id() []const u8 {
    return models[58].id;
}
pub fn model_3658_context() u32 {
    return models[58].context_window;
}
pub fn model_3658_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3658_family() []const u8 {
    return models[58].family;
}
pub fn model_3658_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3659_id() []const u8 {
    return models[59].id;
}
pub fn model_3659_context() u32 {
    return models[59].context_window;
}
pub fn model_3659_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3659_family() []const u8 {
    return models[59].family;
}
pub fn model_3659_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3660_id() []const u8 {
    return models[60].id;
}
pub fn model_3660_context() u32 {
    return models[60].context_window;
}
pub fn model_3660_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3660_family() []const u8 {
    return models[60].family;
}
pub fn model_3660_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3661_id() []const u8 {
    return models[61].id;
}
pub fn model_3661_context() u32 {
    return models[61].context_window;
}
pub fn model_3661_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3661_family() []const u8 {
    return models[61].family;
}
pub fn model_3661_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3662_id() []const u8 {
    return models[62].id;
}
pub fn model_3662_context() u32 {
    return models[62].context_window;
}
pub fn model_3662_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3662_family() []const u8 {
    return models[62].family;
}
pub fn model_3662_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3663_id() []const u8 {
    return models[63].id;
}
pub fn model_3663_context() u32 {
    return models[63].context_window;
}
pub fn model_3663_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3663_family() []const u8 {
    return models[63].family;
}
pub fn model_3663_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3664_id() []const u8 {
    return models[64].id;
}
pub fn model_3664_context() u32 {
    return models[64].context_window;
}
pub fn model_3664_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3664_family() []const u8 {
    return models[64].family;
}
pub fn model_3664_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3665_id() []const u8 {
    return models[65].id;
}
pub fn model_3665_context() u32 {
    return models[65].context_window;
}
pub fn model_3665_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3665_family() []const u8 {
    return models[65].family;
}
pub fn model_3665_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3666_id() []const u8 {
    return models[66].id;
}
pub fn model_3666_context() u32 {
    return models[66].context_window;
}
pub fn model_3666_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3666_family() []const u8 {
    return models[66].family;
}
pub fn model_3666_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3667_id() []const u8 {
    return models[67].id;
}
pub fn model_3667_context() u32 {
    return models[67].context_window;
}
pub fn model_3667_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3667_family() []const u8 {
    return models[67].family;
}
pub fn model_3667_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3668_id() []const u8 {
    return models[68].id;
}
pub fn model_3668_context() u32 {
    return models[68].context_window;
}
pub fn model_3668_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3668_family() []const u8 {
    return models[68].family;
}
pub fn model_3668_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3669_id() []const u8 {
    return models[69].id;
}
pub fn model_3669_context() u32 {
    return models[69].context_window;
}
pub fn model_3669_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3669_family() []const u8 {
    return models[69].family;
}
pub fn model_3669_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3670_id() []const u8 {
    return models[70].id;
}
pub fn model_3670_context() u32 {
    return models[70].context_window;
}
pub fn model_3670_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3670_family() []const u8 {
    return models[70].family;
}
pub fn model_3670_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3671_id() []const u8 {
    return models[71].id;
}
pub fn model_3671_context() u32 {
    return models[71].context_window;
}
pub fn model_3671_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3671_family() []const u8 {
    return models[71].family;
}
pub fn model_3671_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3672_id() []const u8 {
    return models[72].id;
}
pub fn model_3672_context() u32 {
    return models[72].context_window;
}
pub fn model_3672_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3672_family() []const u8 {
    return models[72].family;
}
pub fn model_3672_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3673_id() []const u8 {
    return models[73].id;
}
pub fn model_3673_context() u32 {
    return models[73].context_window;
}
pub fn model_3673_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3673_family() []const u8 {
    return models[73].family;
}
pub fn model_3673_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3674_id() []const u8 {
    return models[74].id;
}
pub fn model_3674_context() u32 {
    return models[74].context_window;
}
pub fn model_3674_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3674_family() []const u8 {
    return models[74].family;
}
pub fn model_3674_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3675_id() []const u8 {
    return models[75].id;
}
pub fn model_3675_context() u32 {
    return models[75].context_window;
}
pub fn model_3675_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3675_family() []const u8 {
    return models[75].family;
}
pub fn model_3675_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3676_id() []const u8 {
    return models[76].id;
}
pub fn model_3676_context() u32 {
    return models[76].context_window;
}
pub fn model_3676_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3676_family() []const u8 {
    return models[76].family;
}
pub fn model_3676_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3677_id() []const u8 {
    return models[77].id;
}
pub fn model_3677_context() u32 {
    return models[77].context_window;
}
pub fn model_3677_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3677_family() []const u8 {
    return models[77].family;
}
pub fn model_3677_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3678_id() []const u8 {
    return models[78].id;
}
pub fn model_3678_context() u32 {
    return models[78].context_window;
}
pub fn model_3678_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3678_family() []const u8 {
    return models[78].family;
}
pub fn model_3678_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3679_id() []const u8 {
    return models[79].id;
}
pub fn model_3679_context() u32 {
    return models[79].context_window;
}
pub fn model_3679_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3679_family() []const u8 {
    return models[79].family;
}
pub fn model_3679_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 36 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

