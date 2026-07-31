//! Generated model catalog shard 35 for package ai.
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

pub const shard_index: u32 = 35;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-3500", .provider = "sambanova", .display = "Sambanova Chat 3500", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-3501", .provider = "github", .display = "Github Code 3501", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3502", .provider = "huggingface", .display = "Huggingface Reason 3502", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3503", .provider = "replicate", .display = "Replicate Vision 3503", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3504", .provider = "anyscale", .display = "Anyscale Embed 3504", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3505", .provider = "databricks", .display = "Databricks Audio 3505", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3506", .provider = "moonshot", .display = "Moonshot Fast 3506", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3507", .provider = "qwen", .display = "Qwen Large 3507", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-3508", .provider = "minimax", .display = "Minimax Mini 3508", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3509", .provider = "zhipu", .display = "Zhipu Nano 3509", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3510", .provider = "baichuan", .display = "Baichuan Pro 3510", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3511", .provider = "yi", .display = "Yi Ultra 3511", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3512", .provider = "siliconflow", .display = "Siliconflow Turbo 3512", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3513", .provider = "novita", .display = "Novita Instruct 3513", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3514", .provider = "lepton", .display = "Lepton Base 3514", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-3515", .provider = "deepinfra", .display = "Deepinfra Preview 3515", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3516", .provider = "friendli", .display = "Friendli Experimental 3516", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3517", .provider = "hyperbolic", .display = "Hyperbolic Stable 3517", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3518", .provider = "lambda", .display = "Lambda Legacy 3518", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3519", .provider = "nebius", .display = "Nebius Edge 3519", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3520", .provider = "openai", .display = "Openai Chat 3520", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3521", .provider = "anthropic", .display = "Anthropic Code 3521", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-3522", .provider = "google", .display = "Google Reason 3522", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3523", .provider = "groq", .display = "Groq Vision 3523", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3524", .provider = "xai", .display = "Xai Embed 3524", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3525", .provider = "deepseek", .display = "Deepseek Audio 3525", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3526", .provider = "mistral", .display = "Mistral Fast 3526", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3527", .provider = "together", .display = "Together Large 3527", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3528", .provider = "fireworks", .display = "Fireworks Mini 3528", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-3529", .provider = "openrouter", .display = "Openrouter Nano 3529", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3530", .provider = "cerebras", .display = "Cerebras Pro 3530", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3531", .provider = "ollama", .display = "Ollama Ultra 3531", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3532", .provider = "lmstudio", .display = "Lmstudio Turbo 3532", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3533", .provider = "vllm", .display = "Vllm Instruct 3533", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3534", .provider = "azure", .display = "Azure Base 3534", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3535", .provider = "bedrock", .display = "Bedrock Preview 3535", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-3536", .provider = "vertex", .display = "Vertex Experimental 3536", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3537", .provider = "perplexity", .display = "Perplexity Stable 3537", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3538", .provider = "cohere", .display = "Cohere Legacy 3538", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3539", .provider = "nvidia", .display = "Nvidia Edge 3539", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3540", .provider = "sambanova", .display = "Sambanova Chat 3540", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3541", .provider = "github", .display = "Github Code 3541", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3542", .provider = "huggingface", .display = "Huggingface Reason 3542", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-3543", .provider = "replicate", .display = "Replicate Vision 3543", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3544", .provider = "anyscale", .display = "Anyscale Embed 3544", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3545", .provider = "databricks", .display = "Databricks Audio 3545", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3546", .provider = "moonshot", .display = "Moonshot Fast 3546", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3547", .provider = "qwen", .display = "Qwen Large 3547", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3548", .provider = "minimax", .display = "Minimax Mini 3548", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3549", .provider = "zhipu", .display = "Zhipu Nano 3549", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-3550", .provider = "baichuan", .display = "Baichuan Pro 3550", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3551", .provider = "yi", .display = "Yi Ultra 3551", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3552", .provider = "siliconflow", .display = "Siliconflow Turbo 3552", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3553", .provider = "novita", .display = "Novita Instruct 3553", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3554", .provider = "lepton", .display = "Lepton Base 3554", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3555", .provider = "deepinfra", .display = "Deepinfra Preview 3555", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3556", .provider = "friendli", .display = "Friendli Experimental 3556", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3557", .provider = "hyperbolic", .display = "Hyperbolic Stable 3557", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3558", .provider = "lambda", .display = "Lambda Legacy 3558", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3559", .provider = "nebius", .display = "Nebius Edge 3559", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3560", .provider = "openai", .display = "Openai Chat 3560", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3561", .provider = "anthropic", .display = "Anthropic Code 3561", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3562", .provider = "google", .display = "Google Reason 3562", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3563", .provider = "groq", .display = "Groq Vision 3563", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-3564", .provider = "xai", .display = "Xai Embed 3564", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3565", .provider = "deepseek", .display = "Deepseek Audio 3565", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3566", .provider = "mistral", .display = "Mistral Fast 3566", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3567", .provider = "together", .display = "Together Large 3567", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3568", .provider = "fireworks", .display = "Fireworks Mini 3568", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3569", .provider = "openrouter", .display = "Openrouter Nano 3569", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3570", .provider = "cerebras", .display = "Cerebras Pro 3570", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-3571", .provider = "ollama", .display = "Ollama Ultra 3571", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3572", .provider = "lmstudio", .display = "Lmstudio Turbo 3572", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3573", .provider = "vllm", .display = "Vllm Instruct 3573", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3574", .provider = "azure", .display = "Azure Base 3574", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3575", .provider = "bedrock", .display = "Bedrock Preview 3575", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3576", .provider = "vertex", .display = "Vertex Experimental 3576", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3577", .provider = "perplexity", .display = "Perplexity Stable 3577", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-3578", .provider = "cohere", .display = "Cohere Legacy 3578", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3579", .provider = "nvidia", .display = "Nvidia Edge 3579", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3580", .provider = "sambanova", .display = "Sambanova Chat 3580", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3581", .provider = "github", .display = "Github Code 3581", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3582", .provider = "huggingface", .display = "Huggingface Reason 3582", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3583", .provider = "replicate", .display = "Replicate Vision 3583", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3584", .provider = "anyscale", .display = "Anyscale Embed 3584", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-3585", .provider = "databricks", .display = "Databricks Audio 3585", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3586", .provider = "moonshot", .display = "Moonshot Fast 3586", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3587", .provider = "qwen", .display = "Qwen Large 3587", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3588", .provider = "minimax", .display = "Minimax Mini 3588", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3589", .provider = "zhipu", .display = "Zhipu Nano 3589", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3590", .provider = "baichuan", .display = "Baichuan Pro 3590", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3591", .provider = "yi", .display = "Yi Ultra 3591", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3592", .provider = "siliconflow", .display = "Siliconflow Turbo 3592", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3593", .provider = "novita", .display = "Novita Instruct 3593", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3594", .provider = "lepton", .display = "Lepton Base 3594", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3595", .provider = "deepinfra", .display = "Deepinfra Preview 3595", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3596", .provider = "friendli", .display = "Friendli Experimental 3596", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3597", .provider = "hyperbolic", .display = "Hyperbolic Stable 3597", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3598", .provider = "lambda", .display = "Lambda Legacy 3598", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-3599", .provider = "nebius", .display = "Nebius Edge 3599", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3500_id() []const u8 {
    return models[0].id;
}
pub fn model_3500_context() u32 {
    return models[0].context_window;
}
pub fn model_3500_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3500_family() []const u8 {
    return models[0].family;
}
pub fn model_3500_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3501_id() []const u8 {
    return models[1].id;
}
pub fn model_3501_context() u32 {
    return models[1].context_window;
}
pub fn model_3501_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3501_family() []const u8 {
    return models[1].family;
}
pub fn model_3501_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3502_id() []const u8 {
    return models[2].id;
}
pub fn model_3502_context() u32 {
    return models[2].context_window;
}
pub fn model_3502_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3502_family() []const u8 {
    return models[2].family;
}
pub fn model_3502_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3503_id() []const u8 {
    return models[3].id;
}
pub fn model_3503_context() u32 {
    return models[3].context_window;
}
pub fn model_3503_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3503_family() []const u8 {
    return models[3].family;
}
pub fn model_3503_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3504_id() []const u8 {
    return models[4].id;
}
pub fn model_3504_context() u32 {
    return models[4].context_window;
}
pub fn model_3504_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3504_family() []const u8 {
    return models[4].family;
}
pub fn model_3504_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3505_id() []const u8 {
    return models[5].id;
}
pub fn model_3505_context() u32 {
    return models[5].context_window;
}
pub fn model_3505_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3505_family() []const u8 {
    return models[5].family;
}
pub fn model_3505_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3506_id() []const u8 {
    return models[6].id;
}
pub fn model_3506_context() u32 {
    return models[6].context_window;
}
pub fn model_3506_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3506_family() []const u8 {
    return models[6].family;
}
pub fn model_3506_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3507_id() []const u8 {
    return models[7].id;
}
pub fn model_3507_context() u32 {
    return models[7].context_window;
}
pub fn model_3507_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3507_family() []const u8 {
    return models[7].family;
}
pub fn model_3507_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3508_id() []const u8 {
    return models[8].id;
}
pub fn model_3508_context() u32 {
    return models[8].context_window;
}
pub fn model_3508_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3508_family() []const u8 {
    return models[8].family;
}
pub fn model_3508_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3509_id() []const u8 {
    return models[9].id;
}
pub fn model_3509_context() u32 {
    return models[9].context_window;
}
pub fn model_3509_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3509_family() []const u8 {
    return models[9].family;
}
pub fn model_3509_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3510_id() []const u8 {
    return models[10].id;
}
pub fn model_3510_context() u32 {
    return models[10].context_window;
}
pub fn model_3510_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3510_family() []const u8 {
    return models[10].family;
}
pub fn model_3510_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3511_id() []const u8 {
    return models[11].id;
}
pub fn model_3511_context() u32 {
    return models[11].context_window;
}
pub fn model_3511_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3511_family() []const u8 {
    return models[11].family;
}
pub fn model_3511_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3512_id() []const u8 {
    return models[12].id;
}
pub fn model_3512_context() u32 {
    return models[12].context_window;
}
pub fn model_3512_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3512_family() []const u8 {
    return models[12].family;
}
pub fn model_3512_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3513_id() []const u8 {
    return models[13].id;
}
pub fn model_3513_context() u32 {
    return models[13].context_window;
}
pub fn model_3513_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3513_family() []const u8 {
    return models[13].family;
}
pub fn model_3513_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3514_id() []const u8 {
    return models[14].id;
}
pub fn model_3514_context() u32 {
    return models[14].context_window;
}
pub fn model_3514_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3514_family() []const u8 {
    return models[14].family;
}
pub fn model_3514_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3515_id() []const u8 {
    return models[15].id;
}
pub fn model_3515_context() u32 {
    return models[15].context_window;
}
pub fn model_3515_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3515_family() []const u8 {
    return models[15].family;
}
pub fn model_3515_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3516_id() []const u8 {
    return models[16].id;
}
pub fn model_3516_context() u32 {
    return models[16].context_window;
}
pub fn model_3516_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3516_family() []const u8 {
    return models[16].family;
}
pub fn model_3516_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3517_id() []const u8 {
    return models[17].id;
}
pub fn model_3517_context() u32 {
    return models[17].context_window;
}
pub fn model_3517_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3517_family() []const u8 {
    return models[17].family;
}
pub fn model_3517_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3518_id() []const u8 {
    return models[18].id;
}
pub fn model_3518_context() u32 {
    return models[18].context_window;
}
pub fn model_3518_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3518_family() []const u8 {
    return models[18].family;
}
pub fn model_3518_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3519_id() []const u8 {
    return models[19].id;
}
pub fn model_3519_context() u32 {
    return models[19].context_window;
}
pub fn model_3519_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3519_family() []const u8 {
    return models[19].family;
}
pub fn model_3519_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3520_id() []const u8 {
    return models[20].id;
}
pub fn model_3520_context() u32 {
    return models[20].context_window;
}
pub fn model_3520_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3520_family() []const u8 {
    return models[20].family;
}
pub fn model_3520_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3521_id() []const u8 {
    return models[21].id;
}
pub fn model_3521_context() u32 {
    return models[21].context_window;
}
pub fn model_3521_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3521_family() []const u8 {
    return models[21].family;
}
pub fn model_3521_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3522_id() []const u8 {
    return models[22].id;
}
pub fn model_3522_context() u32 {
    return models[22].context_window;
}
pub fn model_3522_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3522_family() []const u8 {
    return models[22].family;
}
pub fn model_3522_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3523_id() []const u8 {
    return models[23].id;
}
pub fn model_3523_context() u32 {
    return models[23].context_window;
}
pub fn model_3523_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3523_family() []const u8 {
    return models[23].family;
}
pub fn model_3523_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3524_id() []const u8 {
    return models[24].id;
}
pub fn model_3524_context() u32 {
    return models[24].context_window;
}
pub fn model_3524_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3524_family() []const u8 {
    return models[24].family;
}
pub fn model_3524_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3525_id() []const u8 {
    return models[25].id;
}
pub fn model_3525_context() u32 {
    return models[25].context_window;
}
pub fn model_3525_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3525_family() []const u8 {
    return models[25].family;
}
pub fn model_3525_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3526_id() []const u8 {
    return models[26].id;
}
pub fn model_3526_context() u32 {
    return models[26].context_window;
}
pub fn model_3526_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3526_family() []const u8 {
    return models[26].family;
}
pub fn model_3526_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3527_id() []const u8 {
    return models[27].id;
}
pub fn model_3527_context() u32 {
    return models[27].context_window;
}
pub fn model_3527_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3527_family() []const u8 {
    return models[27].family;
}
pub fn model_3527_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3528_id() []const u8 {
    return models[28].id;
}
pub fn model_3528_context() u32 {
    return models[28].context_window;
}
pub fn model_3528_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3528_family() []const u8 {
    return models[28].family;
}
pub fn model_3528_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3529_id() []const u8 {
    return models[29].id;
}
pub fn model_3529_context() u32 {
    return models[29].context_window;
}
pub fn model_3529_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3529_family() []const u8 {
    return models[29].family;
}
pub fn model_3529_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3530_id() []const u8 {
    return models[30].id;
}
pub fn model_3530_context() u32 {
    return models[30].context_window;
}
pub fn model_3530_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3530_family() []const u8 {
    return models[30].family;
}
pub fn model_3530_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3531_id() []const u8 {
    return models[31].id;
}
pub fn model_3531_context() u32 {
    return models[31].context_window;
}
pub fn model_3531_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3531_family() []const u8 {
    return models[31].family;
}
pub fn model_3531_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3532_id() []const u8 {
    return models[32].id;
}
pub fn model_3532_context() u32 {
    return models[32].context_window;
}
pub fn model_3532_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3532_family() []const u8 {
    return models[32].family;
}
pub fn model_3532_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3533_id() []const u8 {
    return models[33].id;
}
pub fn model_3533_context() u32 {
    return models[33].context_window;
}
pub fn model_3533_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3533_family() []const u8 {
    return models[33].family;
}
pub fn model_3533_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3534_id() []const u8 {
    return models[34].id;
}
pub fn model_3534_context() u32 {
    return models[34].context_window;
}
pub fn model_3534_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3534_family() []const u8 {
    return models[34].family;
}
pub fn model_3534_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3535_id() []const u8 {
    return models[35].id;
}
pub fn model_3535_context() u32 {
    return models[35].context_window;
}
pub fn model_3535_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3535_family() []const u8 {
    return models[35].family;
}
pub fn model_3535_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3536_id() []const u8 {
    return models[36].id;
}
pub fn model_3536_context() u32 {
    return models[36].context_window;
}
pub fn model_3536_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3536_family() []const u8 {
    return models[36].family;
}
pub fn model_3536_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3537_id() []const u8 {
    return models[37].id;
}
pub fn model_3537_context() u32 {
    return models[37].context_window;
}
pub fn model_3537_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3537_family() []const u8 {
    return models[37].family;
}
pub fn model_3537_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3538_id() []const u8 {
    return models[38].id;
}
pub fn model_3538_context() u32 {
    return models[38].context_window;
}
pub fn model_3538_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3538_family() []const u8 {
    return models[38].family;
}
pub fn model_3538_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3539_id() []const u8 {
    return models[39].id;
}
pub fn model_3539_context() u32 {
    return models[39].context_window;
}
pub fn model_3539_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3539_family() []const u8 {
    return models[39].family;
}
pub fn model_3539_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3540_id() []const u8 {
    return models[40].id;
}
pub fn model_3540_context() u32 {
    return models[40].context_window;
}
pub fn model_3540_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3540_family() []const u8 {
    return models[40].family;
}
pub fn model_3540_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3541_id() []const u8 {
    return models[41].id;
}
pub fn model_3541_context() u32 {
    return models[41].context_window;
}
pub fn model_3541_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3541_family() []const u8 {
    return models[41].family;
}
pub fn model_3541_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3542_id() []const u8 {
    return models[42].id;
}
pub fn model_3542_context() u32 {
    return models[42].context_window;
}
pub fn model_3542_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3542_family() []const u8 {
    return models[42].family;
}
pub fn model_3542_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3543_id() []const u8 {
    return models[43].id;
}
pub fn model_3543_context() u32 {
    return models[43].context_window;
}
pub fn model_3543_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3543_family() []const u8 {
    return models[43].family;
}
pub fn model_3543_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3544_id() []const u8 {
    return models[44].id;
}
pub fn model_3544_context() u32 {
    return models[44].context_window;
}
pub fn model_3544_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3544_family() []const u8 {
    return models[44].family;
}
pub fn model_3544_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3545_id() []const u8 {
    return models[45].id;
}
pub fn model_3545_context() u32 {
    return models[45].context_window;
}
pub fn model_3545_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3545_family() []const u8 {
    return models[45].family;
}
pub fn model_3545_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3546_id() []const u8 {
    return models[46].id;
}
pub fn model_3546_context() u32 {
    return models[46].context_window;
}
pub fn model_3546_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3546_family() []const u8 {
    return models[46].family;
}
pub fn model_3546_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3547_id() []const u8 {
    return models[47].id;
}
pub fn model_3547_context() u32 {
    return models[47].context_window;
}
pub fn model_3547_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3547_family() []const u8 {
    return models[47].family;
}
pub fn model_3547_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3548_id() []const u8 {
    return models[48].id;
}
pub fn model_3548_context() u32 {
    return models[48].context_window;
}
pub fn model_3548_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3548_family() []const u8 {
    return models[48].family;
}
pub fn model_3548_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3549_id() []const u8 {
    return models[49].id;
}
pub fn model_3549_context() u32 {
    return models[49].context_window;
}
pub fn model_3549_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3549_family() []const u8 {
    return models[49].family;
}
pub fn model_3549_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3550_id() []const u8 {
    return models[50].id;
}
pub fn model_3550_context() u32 {
    return models[50].context_window;
}
pub fn model_3550_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3550_family() []const u8 {
    return models[50].family;
}
pub fn model_3550_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3551_id() []const u8 {
    return models[51].id;
}
pub fn model_3551_context() u32 {
    return models[51].context_window;
}
pub fn model_3551_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3551_family() []const u8 {
    return models[51].family;
}
pub fn model_3551_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3552_id() []const u8 {
    return models[52].id;
}
pub fn model_3552_context() u32 {
    return models[52].context_window;
}
pub fn model_3552_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3552_family() []const u8 {
    return models[52].family;
}
pub fn model_3552_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3553_id() []const u8 {
    return models[53].id;
}
pub fn model_3553_context() u32 {
    return models[53].context_window;
}
pub fn model_3553_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3553_family() []const u8 {
    return models[53].family;
}
pub fn model_3553_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3554_id() []const u8 {
    return models[54].id;
}
pub fn model_3554_context() u32 {
    return models[54].context_window;
}
pub fn model_3554_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3554_family() []const u8 {
    return models[54].family;
}
pub fn model_3554_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3555_id() []const u8 {
    return models[55].id;
}
pub fn model_3555_context() u32 {
    return models[55].context_window;
}
pub fn model_3555_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3555_family() []const u8 {
    return models[55].family;
}
pub fn model_3555_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3556_id() []const u8 {
    return models[56].id;
}
pub fn model_3556_context() u32 {
    return models[56].context_window;
}
pub fn model_3556_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3556_family() []const u8 {
    return models[56].family;
}
pub fn model_3556_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3557_id() []const u8 {
    return models[57].id;
}
pub fn model_3557_context() u32 {
    return models[57].context_window;
}
pub fn model_3557_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3557_family() []const u8 {
    return models[57].family;
}
pub fn model_3557_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3558_id() []const u8 {
    return models[58].id;
}
pub fn model_3558_context() u32 {
    return models[58].context_window;
}
pub fn model_3558_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3558_family() []const u8 {
    return models[58].family;
}
pub fn model_3558_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3559_id() []const u8 {
    return models[59].id;
}
pub fn model_3559_context() u32 {
    return models[59].context_window;
}
pub fn model_3559_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3559_family() []const u8 {
    return models[59].family;
}
pub fn model_3559_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3560_id() []const u8 {
    return models[60].id;
}
pub fn model_3560_context() u32 {
    return models[60].context_window;
}
pub fn model_3560_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3560_family() []const u8 {
    return models[60].family;
}
pub fn model_3560_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3561_id() []const u8 {
    return models[61].id;
}
pub fn model_3561_context() u32 {
    return models[61].context_window;
}
pub fn model_3561_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3561_family() []const u8 {
    return models[61].family;
}
pub fn model_3561_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3562_id() []const u8 {
    return models[62].id;
}
pub fn model_3562_context() u32 {
    return models[62].context_window;
}
pub fn model_3562_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3562_family() []const u8 {
    return models[62].family;
}
pub fn model_3562_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3563_id() []const u8 {
    return models[63].id;
}
pub fn model_3563_context() u32 {
    return models[63].context_window;
}
pub fn model_3563_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3563_family() []const u8 {
    return models[63].family;
}
pub fn model_3563_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3564_id() []const u8 {
    return models[64].id;
}
pub fn model_3564_context() u32 {
    return models[64].context_window;
}
pub fn model_3564_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3564_family() []const u8 {
    return models[64].family;
}
pub fn model_3564_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3565_id() []const u8 {
    return models[65].id;
}
pub fn model_3565_context() u32 {
    return models[65].context_window;
}
pub fn model_3565_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3565_family() []const u8 {
    return models[65].family;
}
pub fn model_3565_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3566_id() []const u8 {
    return models[66].id;
}
pub fn model_3566_context() u32 {
    return models[66].context_window;
}
pub fn model_3566_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3566_family() []const u8 {
    return models[66].family;
}
pub fn model_3566_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3567_id() []const u8 {
    return models[67].id;
}
pub fn model_3567_context() u32 {
    return models[67].context_window;
}
pub fn model_3567_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3567_family() []const u8 {
    return models[67].family;
}
pub fn model_3567_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3568_id() []const u8 {
    return models[68].id;
}
pub fn model_3568_context() u32 {
    return models[68].context_window;
}
pub fn model_3568_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3568_family() []const u8 {
    return models[68].family;
}
pub fn model_3568_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3569_id() []const u8 {
    return models[69].id;
}
pub fn model_3569_context() u32 {
    return models[69].context_window;
}
pub fn model_3569_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3569_family() []const u8 {
    return models[69].family;
}
pub fn model_3569_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3570_id() []const u8 {
    return models[70].id;
}
pub fn model_3570_context() u32 {
    return models[70].context_window;
}
pub fn model_3570_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3570_family() []const u8 {
    return models[70].family;
}
pub fn model_3570_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3571_id() []const u8 {
    return models[71].id;
}
pub fn model_3571_context() u32 {
    return models[71].context_window;
}
pub fn model_3571_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3571_family() []const u8 {
    return models[71].family;
}
pub fn model_3571_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3572_id() []const u8 {
    return models[72].id;
}
pub fn model_3572_context() u32 {
    return models[72].context_window;
}
pub fn model_3572_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3572_family() []const u8 {
    return models[72].family;
}
pub fn model_3572_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3573_id() []const u8 {
    return models[73].id;
}
pub fn model_3573_context() u32 {
    return models[73].context_window;
}
pub fn model_3573_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3573_family() []const u8 {
    return models[73].family;
}
pub fn model_3573_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3574_id() []const u8 {
    return models[74].id;
}
pub fn model_3574_context() u32 {
    return models[74].context_window;
}
pub fn model_3574_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3574_family() []const u8 {
    return models[74].family;
}
pub fn model_3574_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3575_id() []const u8 {
    return models[75].id;
}
pub fn model_3575_context() u32 {
    return models[75].context_window;
}
pub fn model_3575_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3575_family() []const u8 {
    return models[75].family;
}
pub fn model_3575_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3576_id() []const u8 {
    return models[76].id;
}
pub fn model_3576_context() u32 {
    return models[76].context_window;
}
pub fn model_3576_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3576_family() []const u8 {
    return models[76].family;
}
pub fn model_3576_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3577_id() []const u8 {
    return models[77].id;
}
pub fn model_3577_context() u32 {
    return models[77].context_window;
}
pub fn model_3577_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3577_family() []const u8 {
    return models[77].family;
}
pub fn model_3577_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3578_id() []const u8 {
    return models[78].id;
}
pub fn model_3578_context() u32 {
    return models[78].context_window;
}
pub fn model_3578_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3578_family() []const u8 {
    return models[78].family;
}
pub fn model_3578_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3579_id() []const u8 {
    return models[79].id;
}
pub fn model_3579_context() u32 {
    return models[79].context_window;
}
pub fn model_3579_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3579_family() []const u8 {
    return models[79].family;
}
pub fn model_3579_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 35 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

