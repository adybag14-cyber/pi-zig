//! Generated model catalog shard 37 for package ai.
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

pub const shard_index: u32 = 37;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-3700", .provider = "sambanova", .display = "Sambanova Chat 3700", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3701", .provider = "github", .display = "Github Code 3701", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3702", .provider = "huggingface", .display = "Huggingface Reason 3702", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3703", .provider = "replicate", .display = "Replicate Vision 3703", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-3704", .provider = "anyscale", .display = "Anyscale Embed 3704", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3705", .provider = "databricks", .display = "Databricks Audio 3705", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3706", .provider = "moonshot", .display = "Moonshot Fast 3706", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3707", .provider = "qwen", .display = "Qwen Large 3707", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3708", .provider = "minimax", .display = "Minimax Mini 3708", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3709", .provider = "zhipu", .display = "Zhipu Nano 3709", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3710", .provider = "baichuan", .display = "Baichuan Pro 3710", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-3711", .provider = "yi", .display = "Yi Ultra 3711", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3712", .provider = "siliconflow", .display = "Siliconflow Turbo 3712", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3713", .provider = "novita", .display = "Novita Instruct 3713", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3714", .provider = "lepton", .display = "Lepton Base 3714", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3715", .provider = "deepinfra", .display = "Deepinfra Preview 3715", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3716", .provider = "friendli", .display = "Friendli Experimental 3716", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3717", .provider = "hyperbolic", .display = "Hyperbolic Stable 3717", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-3718", .provider = "lambda", .display = "Lambda Legacy 3718", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3719", .provider = "nebius", .display = "Nebius Edge 3719", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3720", .provider = "openai", .display = "Openai Chat 3720", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3721", .provider = "anthropic", .display = "Anthropic Code 3721", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3722", .provider = "google", .display = "Google Reason 3722", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3723", .provider = "groq", .display = "Groq Vision 3723", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3724", .provider = "xai", .display = "Xai Embed 3724", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-3725", .provider = "deepseek", .display = "Deepseek Audio 3725", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3726", .provider = "mistral", .display = "Mistral Fast 3726", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3727", .provider = "together", .display = "Together Large 3727", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3728", .provider = "fireworks", .display = "Fireworks Mini 3728", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3729", .provider = "openrouter", .display = "Openrouter Nano 3729", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3730", .provider = "cerebras", .display = "Cerebras Pro 3730", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3731", .provider = "ollama", .display = "Ollama Ultra 3731", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3732", .provider = "lmstudio", .display = "Lmstudio Turbo 3732", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3733", .provider = "vllm", .display = "Vllm Instruct 3733", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3734", .provider = "azure", .display = "Azure Base 3734", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3735", .provider = "bedrock", .display = "Bedrock Preview 3735", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3736", .provider = "vertex", .display = "Vertex Experimental 3736", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3737", .provider = "perplexity", .display = "Perplexity Stable 3737", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3738", .provider = "cohere", .display = "Cohere Legacy 3738", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-3739", .provider = "nvidia", .display = "Nvidia Edge 3739", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3740", .provider = "sambanova", .display = "Sambanova Chat 3740", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3741", .provider = "github", .display = "Github Code 3741", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3742", .provider = "huggingface", .display = "Huggingface Reason 3742", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3743", .provider = "replicate", .display = "Replicate Vision 3743", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3744", .provider = "anyscale", .display = "Anyscale Embed 3744", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3745", .provider = "databricks", .display = "Databricks Audio 3745", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-3746", .provider = "moonshot", .display = "Moonshot Fast 3746", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3747", .provider = "qwen", .display = "Qwen Large 3747", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3748", .provider = "minimax", .display = "Minimax Mini 3748", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3749", .provider = "zhipu", .display = "Zhipu Nano 3749", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3750", .provider = "baichuan", .display = "Baichuan Pro 3750", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3751", .provider = "yi", .display = "Yi Ultra 3751", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3752", .provider = "siliconflow", .display = "Siliconflow Turbo 3752", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-3753", .provider = "novita", .display = "Novita Instruct 3753", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3754", .provider = "lepton", .display = "Lepton Base 3754", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3755", .provider = "deepinfra", .display = "Deepinfra Preview 3755", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3756", .provider = "friendli", .display = "Friendli Experimental 3756", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3757", .provider = "hyperbolic", .display = "Hyperbolic Stable 3757", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3758", .provider = "lambda", .display = "Lambda Legacy 3758", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3759", .provider = "nebius", .display = "Nebius Edge 3759", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-3760", .provider = "openai", .display = "Openai Chat 3760", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3761", .provider = "anthropic", .display = "Anthropic Code 3761", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3762", .provider = "google", .display = "Google Reason 3762", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3763", .provider = "groq", .display = "Groq Vision 3763", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3764", .provider = "xai", .display = "Xai Embed 3764", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3765", .provider = "deepseek", .display = "Deepseek Audio 3765", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3766", .provider = "mistral", .display = "Mistral Fast 3766", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-3767", .provider = "together", .display = "Together Large 3767", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3768", .provider = "fireworks", .display = "Fireworks Mini 3768", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3769", .provider = "openrouter", .display = "Openrouter Nano 3769", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3770", .provider = "cerebras", .display = "Cerebras Pro 3770", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3771", .provider = "ollama", .display = "Ollama Ultra 3771", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3772", .provider = "lmstudio", .display = "Lmstudio Turbo 3772", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3773", .provider = "vllm", .display = "Vllm Instruct 3773", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-3774", .provider = "azure", .display = "Azure Base 3774", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3775", .provider = "bedrock", .display = "Bedrock Preview 3775", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3776", .provider = "vertex", .display = "Vertex Experimental 3776", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3777", .provider = "perplexity", .display = "Perplexity Stable 3777", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3778", .provider = "cohere", .display = "Cohere Legacy 3778", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3779", .provider = "nvidia", .display = "Nvidia Edge 3779", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3780", .provider = "sambanova", .display = "Sambanova Chat 3780", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-3781", .provider = "github", .display = "Github Code 3781", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3782", .provider = "huggingface", .display = "Huggingface Reason 3782", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3783", .provider = "replicate", .display = "Replicate Vision 3783", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3784", .provider = "anyscale", .display = "Anyscale Embed 3784", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3785", .provider = "databricks", .display = "Databricks Audio 3785", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3786", .provider = "moonshot", .display = "Moonshot Fast 3786", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3787", .provider = "qwen", .display = "Qwen Large 3787", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-3788", .provider = "minimax", .display = "Minimax Mini 3788", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3789", .provider = "zhipu", .display = "Zhipu Nano 3789", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3790", .provider = "baichuan", .display = "Baichuan Pro 3790", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3791", .provider = "yi", .display = "Yi Ultra 3791", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3792", .provider = "siliconflow", .display = "Siliconflow Turbo 3792", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3793", .provider = "novita", .display = "Novita Instruct 3793", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3794", .provider = "lepton", .display = "Lepton Base 3794", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-3795", .provider = "deepinfra", .display = "Deepinfra Preview 3795", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3796", .provider = "friendli", .display = "Friendli Experimental 3796", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3797", .provider = "hyperbolic", .display = "Hyperbolic Stable 3797", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3798", .provider = "lambda", .display = "Lambda Legacy 3798", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3799", .provider = "nebius", .display = "Nebius Edge 3799", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3700_id() []const u8 {
    return models[0].id;
}
pub fn model_3700_context() u32 {
    return models[0].context_window;
}
pub fn model_3700_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3700_family() []const u8 {
    return models[0].family;
}
pub fn model_3700_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3701_id() []const u8 {
    return models[1].id;
}
pub fn model_3701_context() u32 {
    return models[1].context_window;
}
pub fn model_3701_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3701_family() []const u8 {
    return models[1].family;
}
pub fn model_3701_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3702_id() []const u8 {
    return models[2].id;
}
pub fn model_3702_context() u32 {
    return models[2].context_window;
}
pub fn model_3702_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3702_family() []const u8 {
    return models[2].family;
}
pub fn model_3702_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3703_id() []const u8 {
    return models[3].id;
}
pub fn model_3703_context() u32 {
    return models[3].context_window;
}
pub fn model_3703_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3703_family() []const u8 {
    return models[3].family;
}
pub fn model_3703_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3704_id() []const u8 {
    return models[4].id;
}
pub fn model_3704_context() u32 {
    return models[4].context_window;
}
pub fn model_3704_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3704_family() []const u8 {
    return models[4].family;
}
pub fn model_3704_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3705_id() []const u8 {
    return models[5].id;
}
pub fn model_3705_context() u32 {
    return models[5].context_window;
}
pub fn model_3705_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3705_family() []const u8 {
    return models[5].family;
}
pub fn model_3705_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3706_id() []const u8 {
    return models[6].id;
}
pub fn model_3706_context() u32 {
    return models[6].context_window;
}
pub fn model_3706_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3706_family() []const u8 {
    return models[6].family;
}
pub fn model_3706_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3707_id() []const u8 {
    return models[7].id;
}
pub fn model_3707_context() u32 {
    return models[7].context_window;
}
pub fn model_3707_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3707_family() []const u8 {
    return models[7].family;
}
pub fn model_3707_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3708_id() []const u8 {
    return models[8].id;
}
pub fn model_3708_context() u32 {
    return models[8].context_window;
}
pub fn model_3708_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3708_family() []const u8 {
    return models[8].family;
}
pub fn model_3708_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3709_id() []const u8 {
    return models[9].id;
}
pub fn model_3709_context() u32 {
    return models[9].context_window;
}
pub fn model_3709_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3709_family() []const u8 {
    return models[9].family;
}
pub fn model_3709_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3710_id() []const u8 {
    return models[10].id;
}
pub fn model_3710_context() u32 {
    return models[10].context_window;
}
pub fn model_3710_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3710_family() []const u8 {
    return models[10].family;
}
pub fn model_3710_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3711_id() []const u8 {
    return models[11].id;
}
pub fn model_3711_context() u32 {
    return models[11].context_window;
}
pub fn model_3711_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3711_family() []const u8 {
    return models[11].family;
}
pub fn model_3711_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3712_id() []const u8 {
    return models[12].id;
}
pub fn model_3712_context() u32 {
    return models[12].context_window;
}
pub fn model_3712_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3712_family() []const u8 {
    return models[12].family;
}
pub fn model_3712_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3713_id() []const u8 {
    return models[13].id;
}
pub fn model_3713_context() u32 {
    return models[13].context_window;
}
pub fn model_3713_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3713_family() []const u8 {
    return models[13].family;
}
pub fn model_3713_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3714_id() []const u8 {
    return models[14].id;
}
pub fn model_3714_context() u32 {
    return models[14].context_window;
}
pub fn model_3714_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3714_family() []const u8 {
    return models[14].family;
}
pub fn model_3714_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3715_id() []const u8 {
    return models[15].id;
}
pub fn model_3715_context() u32 {
    return models[15].context_window;
}
pub fn model_3715_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3715_family() []const u8 {
    return models[15].family;
}
pub fn model_3715_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3716_id() []const u8 {
    return models[16].id;
}
pub fn model_3716_context() u32 {
    return models[16].context_window;
}
pub fn model_3716_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3716_family() []const u8 {
    return models[16].family;
}
pub fn model_3716_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3717_id() []const u8 {
    return models[17].id;
}
pub fn model_3717_context() u32 {
    return models[17].context_window;
}
pub fn model_3717_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3717_family() []const u8 {
    return models[17].family;
}
pub fn model_3717_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3718_id() []const u8 {
    return models[18].id;
}
pub fn model_3718_context() u32 {
    return models[18].context_window;
}
pub fn model_3718_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3718_family() []const u8 {
    return models[18].family;
}
pub fn model_3718_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3719_id() []const u8 {
    return models[19].id;
}
pub fn model_3719_context() u32 {
    return models[19].context_window;
}
pub fn model_3719_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3719_family() []const u8 {
    return models[19].family;
}
pub fn model_3719_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3720_id() []const u8 {
    return models[20].id;
}
pub fn model_3720_context() u32 {
    return models[20].context_window;
}
pub fn model_3720_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3720_family() []const u8 {
    return models[20].family;
}
pub fn model_3720_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3721_id() []const u8 {
    return models[21].id;
}
pub fn model_3721_context() u32 {
    return models[21].context_window;
}
pub fn model_3721_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3721_family() []const u8 {
    return models[21].family;
}
pub fn model_3721_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3722_id() []const u8 {
    return models[22].id;
}
pub fn model_3722_context() u32 {
    return models[22].context_window;
}
pub fn model_3722_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3722_family() []const u8 {
    return models[22].family;
}
pub fn model_3722_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3723_id() []const u8 {
    return models[23].id;
}
pub fn model_3723_context() u32 {
    return models[23].context_window;
}
pub fn model_3723_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3723_family() []const u8 {
    return models[23].family;
}
pub fn model_3723_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3724_id() []const u8 {
    return models[24].id;
}
pub fn model_3724_context() u32 {
    return models[24].context_window;
}
pub fn model_3724_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3724_family() []const u8 {
    return models[24].family;
}
pub fn model_3724_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3725_id() []const u8 {
    return models[25].id;
}
pub fn model_3725_context() u32 {
    return models[25].context_window;
}
pub fn model_3725_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3725_family() []const u8 {
    return models[25].family;
}
pub fn model_3725_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3726_id() []const u8 {
    return models[26].id;
}
pub fn model_3726_context() u32 {
    return models[26].context_window;
}
pub fn model_3726_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3726_family() []const u8 {
    return models[26].family;
}
pub fn model_3726_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3727_id() []const u8 {
    return models[27].id;
}
pub fn model_3727_context() u32 {
    return models[27].context_window;
}
pub fn model_3727_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3727_family() []const u8 {
    return models[27].family;
}
pub fn model_3727_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3728_id() []const u8 {
    return models[28].id;
}
pub fn model_3728_context() u32 {
    return models[28].context_window;
}
pub fn model_3728_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3728_family() []const u8 {
    return models[28].family;
}
pub fn model_3728_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3729_id() []const u8 {
    return models[29].id;
}
pub fn model_3729_context() u32 {
    return models[29].context_window;
}
pub fn model_3729_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3729_family() []const u8 {
    return models[29].family;
}
pub fn model_3729_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3730_id() []const u8 {
    return models[30].id;
}
pub fn model_3730_context() u32 {
    return models[30].context_window;
}
pub fn model_3730_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3730_family() []const u8 {
    return models[30].family;
}
pub fn model_3730_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3731_id() []const u8 {
    return models[31].id;
}
pub fn model_3731_context() u32 {
    return models[31].context_window;
}
pub fn model_3731_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3731_family() []const u8 {
    return models[31].family;
}
pub fn model_3731_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3732_id() []const u8 {
    return models[32].id;
}
pub fn model_3732_context() u32 {
    return models[32].context_window;
}
pub fn model_3732_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3732_family() []const u8 {
    return models[32].family;
}
pub fn model_3732_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3733_id() []const u8 {
    return models[33].id;
}
pub fn model_3733_context() u32 {
    return models[33].context_window;
}
pub fn model_3733_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3733_family() []const u8 {
    return models[33].family;
}
pub fn model_3733_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3734_id() []const u8 {
    return models[34].id;
}
pub fn model_3734_context() u32 {
    return models[34].context_window;
}
pub fn model_3734_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3734_family() []const u8 {
    return models[34].family;
}
pub fn model_3734_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3735_id() []const u8 {
    return models[35].id;
}
pub fn model_3735_context() u32 {
    return models[35].context_window;
}
pub fn model_3735_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3735_family() []const u8 {
    return models[35].family;
}
pub fn model_3735_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3736_id() []const u8 {
    return models[36].id;
}
pub fn model_3736_context() u32 {
    return models[36].context_window;
}
pub fn model_3736_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3736_family() []const u8 {
    return models[36].family;
}
pub fn model_3736_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3737_id() []const u8 {
    return models[37].id;
}
pub fn model_3737_context() u32 {
    return models[37].context_window;
}
pub fn model_3737_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3737_family() []const u8 {
    return models[37].family;
}
pub fn model_3737_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3738_id() []const u8 {
    return models[38].id;
}
pub fn model_3738_context() u32 {
    return models[38].context_window;
}
pub fn model_3738_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3738_family() []const u8 {
    return models[38].family;
}
pub fn model_3738_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3739_id() []const u8 {
    return models[39].id;
}
pub fn model_3739_context() u32 {
    return models[39].context_window;
}
pub fn model_3739_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3739_family() []const u8 {
    return models[39].family;
}
pub fn model_3739_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3740_id() []const u8 {
    return models[40].id;
}
pub fn model_3740_context() u32 {
    return models[40].context_window;
}
pub fn model_3740_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3740_family() []const u8 {
    return models[40].family;
}
pub fn model_3740_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3741_id() []const u8 {
    return models[41].id;
}
pub fn model_3741_context() u32 {
    return models[41].context_window;
}
pub fn model_3741_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3741_family() []const u8 {
    return models[41].family;
}
pub fn model_3741_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3742_id() []const u8 {
    return models[42].id;
}
pub fn model_3742_context() u32 {
    return models[42].context_window;
}
pub fn model_3742_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3742_family() []const u8 {
    return models[42].family;
}
pub fn model_3742_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3743_id() []const u8 {
    return models[43].id;
}
pub fn model_3743_context() u32 {
    return models[43].context_window;
}
pub fn model_3743_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3743_family() []const u8 {
    return models[43].family;
}
pub fn model_3743_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3744_id() []const u8 {
    return models[44].id;
}
pub fn model_3744_context() u32 {
    return models[44].context_window;
}
pub fn model_3744_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3744_family() []const u8 {
    return models[44].family;
}
pub fn model_3744_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3745_id() []const u8 {
    return models[45].id;
}
pub fn model_3745_context() u32 {
    return models[45].context_window;
}
pub fn model_3745_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3745_family() []const u8 {
    return models[45].family;
}
pub fn model_3745_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3746_id() []const u8 {
    return models[46].id;
}
pub fn model_3746_context() u32 {
    return models[46].context_window;
}
pub fn model_3746_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3746_family() []const u8 {
    return models[46].family;
}
pub fn model_3746_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3747_id() []const u8 {
    return models[47].id;
}
pub fn model_3747_context() u32 {
    return models[47].context_window;
}
pub fn model_3747_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3747_family() []const u8 {
    return models[47].family;
}
pub fn model_3747_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3748_id() []const u8 {
    return models[48].id;
}
pub fn model_3748_context() u32 {
    return models[48].context_window;
}
pub fn model_3748_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3748_family() []const u8 {
    return models[48].family;
}
pub fn model_3748_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3749_id() []const u8 {
    return models[49].id;
}
pub fn model_3749_context() u32 {
    return models[49].context_window;
}
pub fn model_3749_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3749_family() []const u8 {
    return models[49].family;
}
pub fn model_3749_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3750_id() []const u8 {
    return models[50].id;
}
pub fn model_3750_context() u32 {
    return models[50].context_window;
}
pub fn model_3750_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3750_family() []const u8 {
    return models[50].family;
}
pub fn model_3750_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3751_id() []const u8 {
    return models[51].id;
}
pub fn model_3751_context() u32 {
    return models[51].context_window;
}
pub fn model_3751_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3751_family() []const u8 {
    return models[51].family;
}
pub fn model_3751_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3752_id() []const u8 {
    return models[52].id;
}
pub fn model_3752_context() u32 {
    return models[52].context_window;
}
pub fn model_3752_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3752_family() []const u8 {
    return models[52].family;
}
pub fn model_3752_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3753_id() []const u8 {
    return models[53].id;
}
pub fn model_3753_context() u32 {
    return models[53].context_window;
}
pub fn model_3753_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3753_family() []const u8 {
    return models[53].family;
}
pub fn model_3753_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3754_id() []const u8 {
    return models[54].id;
}
pub fn model_3754_context() u32 {
    return models[54].context_window;
}
pub fn model_3754_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3754_family() []const u8 {
    return models[54].family;
}
pub fn model_3754_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3755_id() []const u8 {
    return models[55].id;
}
pub fn model_3755_context() u32 {
    return models[55].context_window;
}
pub fn model_3755_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3755_family() []const u8 {
    return models[55].family;
}
pub fn model_3755_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3756_id() []const u8 {
    return models[56].id;
}
pub fn model_3756_context() u32 {
    return models[56].context_window;
}
pub fn model_3756_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3756_family() []const u8 {
    return models[56].family;
}
pub fn model_3756_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3757_id() []const u8 {
    return models[57].id;
}
pub fn model_3757_context() u32 {
    return models[57].context_window;
}
pub fn model_3757_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3757_family() []const u8 {
    return models[57].family;
}
pub fn model_3757_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3758_id() []const u8 {
    return models[58].id;
}
pub fn model_3758_context() u32 {
    return models[58].context_window;
}
pub fn model_3758_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3758_family() []const u8 {
    return models[58].family;
}
pub fn model_3758_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3759_id() []const u8 {
    return models[59].id;
}
pub fn model_3759_context() u32 {
    return models[59].context_window;
}
pub fn model_3759_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3759_family() []const u8 {
    return models[59].family;
}
pub fn model_3759_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3760_id() []const u8 {
    return models[60].id;
}
pub fn model_3760_context() u32 {
    return models[60].context_window;
}
pub fn model_3760_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3760_family() []const u8 {
    return models[60].family;
}
pub fn model_3760_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3761_id() []const u8 {
    return models[61].id;
}
pub fn model_3761_context() u32 {
    return models[61].context_window;
}
pub fn model_3761_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3761_family() []const u8 {
    return models[61].family;
}
pub fn model_3761_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3762_id() []const u8 {
    return models[62].id;
}
pub fn model_3762_context() u32 {
    return models[62].context_window;
}
pub fn model_3762_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3762_family() []const u8 {
    return models[62].family;
}
pub fn model_3762_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3763_id() []const u8 {
    return models[63].id;
}
pub fn model_3763_context() u32 {
    return models[63].context_window;
}
pub fn model_3763_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3763_family() []const u8 {
    return models[63].family;
}
pub fn model_3763_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3764_id() []const u8 {
    return models[64].id;
}
pub fn model_3764_context() u32 {
    return models[64].context_window;
}
pub fn model_3764_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3764_family() []const u8 {
    return models[64].family;
}
pub fn model_3764_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3765_id() []const u8 {
    return models[65].id;
}
pub fn model_3765_context() u32 {
    return models[65].context_window;
}
pub fn model_3765_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3765_family() []const u8 {
    return models[65].family;
}
pub fn model_3765_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3766_id() []const u8 {
    return models[66].id;
}
pub fn model_3766_context() u32 {
    return models[66].context_window;
}
pub fn model_3766_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3766_family() []const u8 {
    return models[66].family;
}
pub fn model_3766_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3767_id() []const u8 {
    return models[67].id;
}
pub fn model_3767_context() u32 {
    return models[67].context_window;
}
pub fn model_3767_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3767_family() []const u8 {
    return models[67].family;
}
pub fn model_3767_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3768_id() []const u8 {
    return models[68].id;
}
pub fn model_3768_context() u32 {
    return models[68].context_window;
}
pub fn model_3768_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3768_family() []const u8 {
    return models[68].family;
}
pub fn model_3768_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3769_id() []const u8 {
    return models[69].id;
}
pub fn model_3769_context() u32 {
    return models[69].context_window;
}
pub fn model_3769_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3769_family() []const u8 {
    return models[69].family;
}
pub fn model_3769_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3770_id() []const u8 {
    return models[70].id;
}
pub fn model_3770_context() u32 {
    return models[70].context_window;
}
pub fn model_3770_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3770_family() []const u8 {
    return models[70].family;
}
pub fn model_3770_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3771_id() []const u8 {
    return models[71].id;
}
pub fn model_3771_context() u32 {
    return models[71].context_window;
}
pub fn model_3771_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3771_family() []const u8 {
    return models[71].family;
}
pub fn model_3771_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3772_id() []const u8 {
    return models[72].id;
}
pub fn model_3772_context() u32 {
    return models[72].context_window;
}
pub fn model_3772_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3772_family() []const u8 {
    return models[72].family;
}
pub fn model_3772_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3773_id() []const u8 {
    return models[73].id;
}
pub fn model_3773_context() u32 {
    return models[73].context_window;
}
pub fn model_3773_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3773_family() []const u8 {
    return models[73].family;
}
pub fn model_3773_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3774_id() []const u8 {
    return models[74].id;
}
pub fn model_3774_context() u32 {
    return models[74].context_window;
}
pub fn model_3774_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3774_family() []const u8 {
    return models[74].family;
}
pub fn model_3774_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3775_id() []const u8 {
    return models[75].id;
}
pub fn model_3775_context() u32 {
    return models[75].context_window;
}
pub fn model_3775_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3775_family() []const u8 {
    return models[75].family;
}
pub fn model_3775_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3776_id() []const u8 {
    return models[76].id;
}
pub fn model_3776_context() u32 {
    return models[76].context_window;
}
pub fn model_3776_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3776_family() []const u8 {
    return models[76].family;
}
pub fn model_3776_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3777_id() []const u8 {
    return models[77].id;
}
pub fn model_3777_context() u32 {
    return models[77].context_window;
}
pub fn model_3777_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3777_family() []const u8 {
    return models[77].family;
}
pub fn model_3777_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3778_id() []const u8 {
    return models[78].id;
}
pub fn model_3778_context() u32 {
    return models[78].context_window;
}
pub fn model_3778_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3778_family() []const u8 {
    return models[78].family;
}
pub fn model_3778_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3779_id() []const u8 {
    return models[79].id;
}
pub fn model_3779_context() u32 {
    return models[79].context_window;
}
pub fn model_3779_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3779_family() []const u8 {
    return models[79].family;
}
pub fn model_3779_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 37 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

