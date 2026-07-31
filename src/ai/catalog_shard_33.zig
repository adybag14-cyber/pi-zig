//! Generated model catalog shard 33 for package ai.
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

pub const shard_index: u32 = 33;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-3300", .provider = "sambanova", .display = "Sambanova Chat 3300", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3301", .provider = "github", .display = "Github Code 3301", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3302", .provider = "huggingface", .display = "Huggingface Reason 3302", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3303", .provider = "replicate", .display = "Replicate Vision 3303", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3304", .provider = "anyscale", .display = "Anyscale Embed 3304", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-3305", .provider = "databricks", .display = "Databricks Audio 3305", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3306", .provider = "moonshot", .display = "Moonshot Fast 3306", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3307", .provider = "qwen", .display = "Qwen Large 3307", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3308", .provider = "minimax", .display = "Minimax Mini 3308", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3309", .provider = "zhipu", .display = "Zhipu Nano 3309", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3310", .provider = "baichuan", .display = "Baichuan Pro 3310", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3311", .provider = "yi", .display = "Yi Ultra 3311", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3312", .provider = "siliconflow", .display = "Siliconflow Turbo 3312", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3313", .provider = "novita", .display = "Novita Instruct 3313", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3314", .provider = "lepton", .display = "Lepton Base 3314", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3315", .provider = "deepinfra", .display = "Deepinfra Preview 3315", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3316", .provider = "friendli", .display = "Friendli Experimental 3316", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3317", .provider = "hyperbolic", .display = "Hyperbolic Stable 3317", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3318", .provider = "lambda", .display = "Lambda Legacy 3318", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-3319", .provider = "nebius", .display = "Nebius Edge 3319", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3320", .provider = "openai", .display = "Openai Chat 3320", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3321", .provider = "anthropic", .display = "Anthropic Code 3321", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3322", .provider = "google", .display = "Google Reason 3322", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3323", .provider = "groq", .display = "Groq Vision 3323", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3324", .provider = "xai", .display = "Xai Embed 3324", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3325", .provider = "deepseek", .display = "Deepseek Audio 3325", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-3326", .provider = "mistral", .display = "Mistral Fast 3326", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3327", .provider = "together", .display = "Together Large 3327", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3328", .provider = "fireworks", .display = "Fireworks Mini 3328", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3329", .provider = "openrouter", .display = "Openrouter Nano 3329", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3330", .provider = "cerebras", .display = "Cerebras Pro 3330", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3331", .provider = "ollama", .display = "Ollama Ultra 3331", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3332", .provider = "lmstudio", .display = "Lmstudio Turbo 3332", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-3333", .provider = "vllm", .display = "Vllm Instruct 3333", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3334", .provider = "azure", .display = "Azure Base 3334", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3335", .provider = "bedrock", .display = "Bedrock Preview 3335", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3336", .provider = "vertex", .display = "Vertex Experimental 3336", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3337", .provider = "perplexity", .display = "Perplexity Stable 3337", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3338", .provider = "cohere", .display = "Cohere Legacy 3338", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3339", .provider = "nvidia", .display = "Nvidia Edge 3339", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-3340", .provider = "sambanova", .display = "Sambanova Chat 3340", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3341", .provider = "github", .display = "Github Code 3341", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3342", .provider = "huggingface", .display = "Huggingface Reason 3342", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3343", .provider = "replicate", .display = "Replicate Vision 3343", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3344", .provider = "anyscale", .display = "Anyscale Embed 3344", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3345", .provider = "databricks", .display = "Databricks Audio 3345", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3346", .provider = "moonshot", .display = "Moonshot Fast 3346", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-3347", .provider = "qwen", .display = "Qwen Large 3347", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3348", .provider = "minimax", .display = "Minimax Mini 3348", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3349", .provider = "zhipu", .display = "Zhipu Nano 3349", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3350", .provider = "baichuan", .display = "Baichuan Pro 3350", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3351", .provider = "yi", .display = "Yi Ultra 3351", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3352", .provider = "siliconflow", .display = "Siliconflow Turbo 3352", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3353", .provider = "novita", .display = "Novita Instruct 3353", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-3354", .provider = "lepton", .display = "Lepton Base 3354", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3355", .provider = "deepinfra", .display = "Deepinfra Preview 3355", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3356", .provider = "friendli", .display = "Friendli Experimental 3356", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3357", .provider = "hyperbolic", .display = "Hyperbolic Stable 3357", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3358", .provider = "lambda", .display = "Lambda Legacy 3358", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3359", .provider = "nebius", .display = "Nebius Edge 3359", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3360", .provider = "openai", .display = "Openai Chat 3360", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-3361", .provider = "anthropic", .display = "Anthropic Code 3361", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3362", .provider = "google", .display = "Google Reason 3362", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3363", .provider = "groq", .display = "Groq Vision 3363", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3364", .provider = "xai", .display = "Xai Embed 3364", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3365", .provider = "deepseek", .display = "Deepseek Audio 3365", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3366", .provider = "mistral", .display = "Mistral Fast 3366", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3367", .provider = "together", .display = "Together Large 3367", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-3368", .provider = "fireworks", .display = "Fireworks Mini 3368", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3369", .provider = "openrouter", .display = "Openrouter Nano 3369", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3370", .provider = "cerebras", .display = "Cerebras Pro 3370", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3371", .provider = "ollama", .display = "Ollama Ultra 3371", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3372", .provider = "lmstudio", .display = "Lmstudio Turbo 3372", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3373", .provider = "vllm", .display = "Vllm Instruct 3373", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3374", .provider = "azure", .display = "Azure Base 3374", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-3375", .provider = "bedrock", .display = "Bedrock Preview 3375", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3376", .provider = "vertex", .display = "Vertex Experimental 3376", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3377", .provider = "perplexity", .display = "Perplexity Stable 3377", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3378", .provider = "cohere", .display = "Cohere Legacy 3378", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3379", .provider = "nvidia", .display = "Nvidia Edge 3379", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3380", .provider = "sambanova", .display = "Sambanova Chat 3380", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3381", .provider = "github", .display = "Github Code 3381", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-3382", .provider = "huggingface", .display = "Huggingface Reason 3382", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3383", .provider = "replicate", .display = "Replicate Vision 3383", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3384", .provider = "anyscale", .display = "Anyscale Embed 3384", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3385", .provider = "databricks", .display = "Databricks Audio 3385", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3386", .provider = "moonshot", .display = "Moonshot Fast 3386", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3387", .provider = "qwen", .display = "Qwen Large 3387", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3388", .provider = "minimax", .display = "Minimax Mini 3388", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-3389", .provider = "zhipu", .display = "Zhipu Nano 3389", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3390", .provider = "baichuan", .display = "Baichuan Pro 3390", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3391", .provider = "yi", .display = "Yi Ultra 3391", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3392", .provider = "siliconflow", .display = "Siliconflow Turbo 3392", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3393", .provider = "novita", .display = "Novita Instruct 3393", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3394", .provider = "lepton", .display = "Lepton Base 3394", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3395", .provider = "deepinfra", .display = "Deepinfra Preview 3395", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-3396", .provider = "friendli", .display = "Friendli Experimental 3396", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3397", .provider = "hyperbolic", .display = "Hyperbolic Stable 3397", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3398", .provider = "lambda", .display = "Lambda Legacy 3398", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3399", .provider = "nebius", .display = "Nebius Edge 3399", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3300_id() []const u8 {
    return models[0].id;
}
pub fn model_3300_context() u32 {
    return models[0].context_window;
}
pub fn model_3300_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3300_family() []const u8 {
    return models[0].family;
}
pub fn model_3300_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3301_id() []const u8 {
    return models[1].id;
}
pub fn model_3301_context() u32 {
    return models[1].context_window;
}
pub fn model_3301_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3301_family() []const u8 {
    return models[1].family;
}
pub fn model_3301_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3302_id() []const u8 {
    return models[2].id;
}
pub fn model_3302_context() u32 {
    return models[2].context_window;
}
pub fn model_3302_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3302_family() []const u8 {
    return models[2].family;
}
pub fn model_3302_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3303_id() []const u8 {
    return models[3].id;
}
pub fn model_3303_context() u32 {
    return models[3].context_window;
}
pub fn model_3303_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3303_family() []const u8 {
    return models[3].family;
}
pub fn model_3303_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3304_id() []const u8 {
    return models[4].id;
}
pub fn model_3304_context() u32 {
    return models[4].context_window;
}
pub fn model_3304_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3304_family() []const u8 {
    return models[4].family;
}
pub fn model_3304_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3305_id() []const u8 {
    return models[5].id;
}
pub fn model_3305_context() u32 {
    return models[5].context_window;
}
pub fn model_3305_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3305_family() []const u8 {
    return models[5].family;
}
pub fn model_3305_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3306_id() []const u8 {
    return models[6].id;
}
pub fn model_3306_context() u32 {
    return models[6].context_window;
}
pub fn model_3306_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3306_family() []const u8 {
    return models[6].family;
}
pub fn model_3306_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3307_id() []const u8 {
    return models[7].id;
}
pub fn model_3307_context() u32 {
    return models[7].context_window;
}
pub fn model_3307_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3307_family() []const u8 {
    return models[7].family;
}
pub fn model_3307_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3308_id() []const u8 {
    return models[8].id;
}
pub fn model_3308_context() u32 {
    return models[8].context_window;
}
pub fn model_3308_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3308_family() []const u8 {
    return models[8].family;
}
pub fn model_3308_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3309_id() []const u8 {
    return models[9].id;
}
pub fn model_3309_context() u32 {
    return models[9].context_window;
}
pub fn model_3309_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3309_family() []const u8 {
    return models[9].family;
}
pub fn model_3309_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3310_id() []const u8 {
    return models[10].id;
}
pub fn model_3310_context() u32 {
    return models[10].context_window;
}
pub fn model_3310_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3310_family() []const u8 {
    return models[10].family;
}
pub fn model_3310_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3311_id() []const u8 {
    return models[11].id;
}
pub fn model_3311_context() u32 {
    return models[11].context_window;
}
pub fn model_3311_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3311_family() []const u8 {
    return models[11].family;
}
pub fn model_3311_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3312_id() []const u8 {
    return models[12].id;
}
pub fn model_3312_context() u32 {
    return models[12].context_window;
}
pub fn model_3312_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3312_family() []const u8 {
    return models[12].family;
}
pub fn model_3312_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3313_id() []const u8 {
    return models[13].id;
}
pub fn model_3313_context() u32 {
    return models[13].context_window;
}
pub fn model_3313_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3313_family() []const u8 {
    return models[13].family;
}
pub fn model_3313_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3314_id() []const u8 {
    return models[14].id;
}
pub fn model_3314_context() u32 {
    return models[14].context_window;
}
pub fn model_3314_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3314_family() []const u8 {
    return models[14].family;
}
pub fn model_3314_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3315_id() []const u8 {
    return models[15].id;
}
pub fn model_3315_context() u32 {
    return models[15].context_window;
}
pub fn model_3315_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3315_family() []const u8 {
    return models[15].family;
}
pub fn model_3315_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3316_id() []const u8 {
    return models[16].id;
}
pub fn model_3316_context() u32 {
    return models[16].context_window;
}
pub fn model_3316_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3316_family() []const u8 {
    return models[16].family;
}
pub fn model_3316_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3317_id() []const u8 {
    return models[17].id;
}
pub fn model_3317_context() u32 {
    return models[17].context_window;
}
pub fn model_3317_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3317_family() []const u8 {
    return models[17].family;
}
pub fn model_3317_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3318_id() []const u8 {
    return models[18].id;
}
pub fn model_3318_context() u32 {
    return models[18].context_window;
}
pub fn model_3318_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3318_family() []const u8 {
    return models[18].family;
}
pub fn model_3318_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3319_id() []const u8 {
    return models[19].id;
}
pub fn model_3319_context() u32 {
    return models[19].context_window;
}
pub fn model_3319_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3319_family() []const u8 {
    return models[19].family;
}
pub fn model_3319_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3320_id() []const u8 {
    return models[20].id;
}
pub fn model_3320_context() u32 {
    return models[20].context_window;
}
pub fn model_3320_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3320_family() []const u8 {
    return models[20].family;
}
pub fn model_3320_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3321_id() []const u8 {
    return models[21].id;
}
pub fn model_3321_context() u32 {
    return models[21].context_window;
}
pub fn model_3321_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3321_family() []const u8 {
    return models[21].family;
}
pub fn model_3321_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3322_id() []const u8 {
    return models[22].id;
}
pub fn model_3322_context() u32 {
    return models[22].context_window;
}
pub fn model_3322_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3322_family() []const u8 {
    return models[22].family;
}
pub fn model_3322_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3323_id() []const u8 {
    return models[23].id;
}
pub fn model_3323_context() u32 {
    return models[23].context_window;
}
pub fn model_3323_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3323_family() []const u8 {
    return models[23].family;
}
pub fn model_3323_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3324_id() []const u8 {
    return models[24].id;
}
pub fn model_3324_context() u32 {
    return models[24].context_window;
}
pub fn model_3324_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3324_family() []const u8 {
    return models[24].family;
}
pub fn model_3324_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3325_id() []const u8 {
    return models[25].id;
}
pub fn model_3325_context() u32 {
    return models[25].context_window;
}
pub fn model_3325_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3325_family() []const u8 {
    return models[25].family;
}
pub fn model_3325_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3326_id() []const u8 {
    return models[26].id;
}
pub fn model_3326_context() u32 {
    return models[26].context_window;
}
pub fn model_3326_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3326_family() []const u8 {
    return models[26].family;
}
pub fn model_3326_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3327_id() []const u8 {
    return models[27].id;
}
pub fn model_3327_context() u32 {
    return models[27].context_window;
}
pub fn model_3327_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3327_family() []const u8 {
    return models[27].family;
}
pub fn model_3327_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3328_id() []const u8 {
    return models[28].id;
}
pub fn model_3328_context() u32 {
    return models[28].context_window;
}
pub fn model_3328_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3328_family() []const u8 {
    return models[28].family;
}
pub fn model_3328_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3329_id() []const u8 {
    return models[29].id;
}
pub fn model_3329_context() u32 {
    return models[29].context_window;
}
pub fn model_3329_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3329_family() []const u8 {
    return models[29].family;
}
pub fn model_3329_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3330_id() []const u8 {
    return models[30].id;
}
pub fn model_3330_context() u32 {
    return models[30].context_window;
}
pub fn model_3330_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3330_family() []const u8 {
    return models[30].family;
}
pub fn model_3330_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3331_id() []const u8 {
    return models[31].id;
}
pub fn model_3331_context() u32 {
    return models[31].context_window;
}
pub fn model_3331_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3331_family() []const u8 {
    return models[31].family;
}
pub fn model_3331_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3332_id() []const u8 {
    return models[32].id;
}
pub fn model_3332_context() u32 {
    return models[32].context_window;
}
pub fn model_3332_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3332_family() []const u8 {
    return models[32].family;
}
pub fn model_3332_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3333_id() []const u8 {
    return models[33].id;
}
pub fn model_3333_context() u32 {
    return models[33].context_window;
}
pub fn model_3333_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3333_family() []const u8 {
    return models[33].family;
}
pub fn model_3333_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3334_id() []const u8 {
    return models[34].id;
}
pub fn model_3334_context() u32 {
    return models[34].context_window;
}
pub fn model_3334_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3334_family() []const u8 {
    return models[34].family;
}
pub fn model_3334_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3335_id() []const u8 {
    return models[35].id;
}
pub fn model_3335_context() u32 {
    return models[35].context_window;
}
pub fn model_3335_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3335_family() []const u8 {
    return models[35].family;
}
pub fn model_3335_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3336_id() []const u8 {
    return models[36].id;
}
pub fn model_3336_context() u32 {
    return models[36].context_window;
}
pub fn model_3336_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3336_family() []const u8 {
    return models[36].family;
}
pub fn model_3336_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3337_id() []const u8 {
    return models[37].id;
}
pub fn model_3337_context() u32 {
    return models[37].context_window;
}
pub fn model_3337_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3337_family() []const u8 {
    return models[37].family;
}
pub fn model_3337_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3338_id() []const u8 {
    return models[38].id;
}
pub fn model_3338_context() u32 {
    return models[38].context_window;
}
pub fn model_3338_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3338_family() []const u8 {
    return models[38].family;
}
pub fn model_3338_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3339_id() []const u8 {
    return models[39].id;
}
pub fn model_3339_context() u32 {
    return models[39].context_window;
}
pub fn model_3339_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3339_family() []const u8 {
    return models[39].family;
}
pub fn model_3339_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3340_id() []const u8 {
    return models[40].id;
}
pub fn model_3340_context() u32 {
    return models[40].context_window;
}
pub fn model_3340_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3340_family() []const u8 {
    return models[40].family;
}
pub fn model_3340_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3341_id() []const u8 {
    return models[41].id;
}
pub fn model_3341_context() u32 {
    return models[41].context_window;
}
pub fn model_3341_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3341_family() []const u8 {
    return models[41].family;
}
pub fn model_3341_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3342_id() []const u8 {
    return models[42].id;
}
pub fn model_3342_context() u32 {
    return models[42].context_window;
}
pub fn model_3342_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3342_family() []const u8 {
    return models[42].family;
}
pub fn model_3342_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3343_id() []const u8 {
    return models[43].id;
}
pub fn model_3343_context() u32 {
    return models[43].context_window;
}
pub fn model_3343_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3343_family() []const u8 {
    return models[43].family;
}
pub fn model_3343_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3344_id() []const u8 {
    return models[44].id;
}
pub fn model_3344_context() u32 {
    return models[44].context_window;
}
pub fn model_3344_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3344_family() []const u8 {
    return models[44].family;
}
pub fn model_3344_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3345_id() []const u8 {
    return models[45].id;
}
pub fn model_3345_context() u32 {
    return models[45].context_window;
}
pub fn model_3345_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3345_family() []const u8 {
    return models[45].family;
}
pub fn model_3345_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3346_id() []const u8 {
    return models[46].id;
}
pub fn model_3346_context() u32 {
    return models[46].context_window;
}
pub fn model_3346_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3346_family() []const u8 {
    return models[46].family;
}
pub fn model_3346_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3347_id() []const u8 {
    return models[47].id;
}
pub fn model_3347_context() u32 {
    return models[47].context_window;
}
pub fn model_3347_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3347_family() []const u8 {
    return models[47].family;
}
pub fn model_3347_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3348_id() []const u8 {
    return models[48].id;
}
pub fn model_3348_context() u32 {
    return models[48].context_window;
}
pub fn model_3348_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3348_family() []const u8 {
    return models[48].family;
}
pub fn model_3348_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3349_id() []const u8 {
    return models[49].id;
}
pub fn model_3349_context() u32 {
    return models[49].context_window;
}
pub fn model_3349_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3349_family() []const u8 {
    return models[49].family;
}
pub fn model_3349_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3350_id() []const u8 {
    return models[50].id;
}
pub fn model_3350_context() u32 {
    return models[50].context_window;
}
pub fn model_3350_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3350_family() []const u8 {
    return models[50].family;
}
pub fn model_3350_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3351_id() []const u8 {
    return models[51].id;
}
pub fn model_3351_context() u32 {
    return models[51].context_window;
}
pub fn model_3351_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3351_family() []const u8 {
    return models[51].family;
}
pub fn model_3351_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3352_id() []const u8 {
    return models[52].id;
}
pub fn model_3352_context() u32 {
    return models[52].context_window;
}
pub fn model_3352_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3352_family() []const u8 {
    return models[52].family;
}
pub fn model_3352_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3353_id() []const u8 {
    return models[53].id;
}
pub fn model_3353_context() u32 {
    return models[53].context_window;
}
pub fn model_3353_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3353_family() []const u8 {
    return models[53].family;
}
pub fn model_3353_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3354_id() []const u8 {
    return models[54].id;
}
pub fn model_3354_context() u32 {
    return models[54].context_window;
}
pub fn model_3354_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3354_family() []const u8 {
    return models[54].family;
}
pub fn model_3354_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3355_id() []const u8 {
    return models[55].id;
}
pub fn model_3355_context() u32 {
    return models[55].context_window;
}
pub fn model_3355_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3355_family() []const u8 {
    return models[55].family;
}
pub fn model_3355_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3356_id() []const u8 {
    return models[56].id;
}
pub fn model_3356_context() u32 {
    return models[56].context_window;
}
pub fn model_3356_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3356_family() []const u8 {
    return models[56].family;
}
pub fn model_3356_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3357_id() []const u8 {
    return models[57].id;
}
pub fn model_3357_context() u32 {
    return models[57].context_window;
}
pub fn model_3357_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3357_family() []const u8 {
    return models[57].family;
}
pub fn model_3357_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3358_id() []const u8 {
    return models[58].id;
}
pub fn model_3358_context() u32 {
    return models[58].context_window;
}
pub fn model_3358_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3358_family() []const u8 {
    return models[58].family;
}
pub fn model_3358_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3359_id() []const u8 {
    return models[59].id;
}
pub fn model_3359_context() u32 {
    return models[59].context_window;
}
pub fn model_3359_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3359_family() []const u8 {
    return models[59].family;
}
pub fn model_3359_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3360_id() []const u8 {
    return models[60].id;
}
pub fn model_3360_context() u32 {
    return models[60].context_window;
}
pub fn model_3360_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3360_family() []const u8 {
    return models[60].family;
}
pub fn model_3360_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3361_id() []const u8 {
    return models[61].id;
}
pub fn model_3361_context() u32 {
    return models[61].context_window;
}
pub fn model_3361_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3361_family() []const u8 {
    return models[61].family;
}
pub fn model_3361_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3362_id() []const u8 {
    return models[62].id;
}
pub fn model_3362_context() u32 {
    return models[62].context_window;
}
pub fn model_3362_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3362_family() []const u8 {
    return models[62].family;
}
pub fn model_3362_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3363_id() []const u8 {
    return models[63].id;
}
pub fn model_3363_context() u32 {
    return models[63].context_window;
}
pub fn model_3363_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3363_family() []const u8 {
    return models[63].family;
}
pub fn model_3363_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3364_id() []const u8 {
    return models[64].id;
}
pub fn model_3364_context() u32 {
    return models[64].context_window;
}
pub fn model_3364_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3364_family() []const u8 {
    return models[64].family;
}
pub fn model_3364_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3365_id() []const u8 {
    return models[65].id;
}
pub fn model_3365_context() u32 {
    return models[65].context_window;
}
pub fn model_3365_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3365_family() []const u8 {
    return models[65].family;
}
pub fn model_3365_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3366_id() []const u8 {
    return models[66].id;
}
pub fn model_3366_context() u32 {
    return models[66].context_window;
}
pub fn model_3366_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3366_family() []const u8 {
    return models[66].family;
}
pub fn model_3366_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3367_id() []const u8 {
    return models[67].id;
}
pub fn model_3367_context() u32 {
    return models[67].context_window;
}
pub fn model_3367_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3367_family() []const u8 {
    return models[67].family;
}
pub fn model_3367_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3368_id() []const u8 {
    return models[68].id;
}
pub fn model_3368_context() u32 {
    return models[68].context_window;
}
pub fn model_3368_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3368_family() []const u8 {
    return models[68].family;
}
pub fn model_3368_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3369_id() []const u8 {
    return models[69].id;
}
pub fn model_3369_context() u32 {
    return models[69].context_window;
}
pub fn model_3369_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3369_family() []const u8 {
    return models[69].family;
}
pub fn model_3369_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3370_id() []const u8 {
    return models[70].id;
}
pub fn model_3370_context() u32 {
    return models[70].context_window;
}
pub fn model_3370_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3370_family() []const u8 {
    return models[70].family;
}
pub fn model_3370_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3371_id() []const u8 {
    return models[71].id;
}
pub fn model_3371_context() u32 {
    return models[71].context_window;
}
pub fn model_3371_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3371_family() []const u8 {
    return models[71].family;
}
pub fn model_3371_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3372_id() []const u8 {
    return models[72].id;
}
pub fn model_3372_context() u32 {
    return models[72].context_window;
}
pub fn model_3372_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3372_family() []const u8 {
    return models[72].family;
}
pub fn model_3372_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3373_id() []const u8 {
    return models[73].id;
}
pub fn model_3373_context() u32 {
    return models[73].context_window;
}
pub fn model_3373_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3373_family() []const u8 {
    return models[73].family;
}
pub fn model_3373_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3374_id() []const u8 {
    return models[74].id;
}
pub fn model_3374_context() u32 {
    return models[74].context_window;
}
pub fn model_3374_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3374_family() []const u8 {
    return models[74].family;
}
pub fn model_3374_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3375_id() []const u8 {
    return models[75].id;
}
pub fn model_3375_context() u32 {
    return models[75].context_window;
}
pub fn model_3375_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3375_family() []const u8 {
    return models[75].family;
}
pub fn model_3375_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3376_id() []const u8 {
    return models[76].id;
}
pub fn model_3376_context() u32 {
    return models[76].context_window;
}
pub fn model_3376_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3376_family() []const u8 {
    return models[76].family;
}
pub fn model_3376_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3377_id() []const u8 {
    return models[77].id;
}
pub fn model_3377_context() u32 {
    return models[77].context_window;
}
pub fn model_3377_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3377_family() []const u8 {
    return models[77].family;
}
pub fn model_3377_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3378_id() []const u8 {
    return models[78].id;
}
pub fn model_3378_context() u32 {
    return models[78].context_window;
}
pub fn model_3378_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3378_family() []const u8 {
    return models[78].family;
}
pub fn model_3378_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3379_id() []const u8 {
    return models[79].id;
}
pub fn model_3379_context() u32 {
    return models[79].context_window;
}
pub fn model_3379_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3379_family() []const u8 {
    return models[79].family;
}
pub fn model_3379_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 33 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

