//! Generated model catalog shard 38 for package ai.
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

pub const shard_index: u32 = 38;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-3800", .provider = "openai", .display = "Openai Chat 3800", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3801", .provider = "anthropic", .display = "Anthropic Code 3801", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-3802", .provider = "google", .display = "Google Reason 3802", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3803", .provider = "groq", .display = "Groq Vision 3803", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3804", .provider = "xai", .display = "Xai Embed 3804", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3805", .provider = "deepseek", .display = "Deepseek Audio 3805", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3806", .provider = "mistral", .display = "Mistral Fast 3806", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3807", .provider = "together", .display = "Together Large 3807", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3808", .provider = "fireworks", .display = "Fireworks Mini 3808", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-3809", .provider = "openrouter", .display = "Openrouter Nano 3809", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3810", .provider = "cerebras", .display = "Cerebras Pro 3810", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3811", .provider = "ollama", .display = "Ollama Ultra 3811", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3812", .provider = "lmstudio", .display = "Lmstudio Turbo 3812", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3813", .provider = "vllm", .display = "Vllm Instruct 3813", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3814", .provider = "azure", .display = "Azure Base 3814", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3815", .provider = "bedrock", .display = "Bedrock Preview 3815", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-3816", .provider = "vertex", .display = "Vertex Experimental 3816", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3817", .provider = "perplexity", .display = "Perplexity Stable 3817", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3818", .provider = "cohere", .display = "Cohere Legacy 3818", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3819", .provider = "nvidia", .display = "Nvidia Edge 3819", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3820", .provider = "sambanova", .display = "Sambanova Chat 3820", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3821", .provider = "github", .display = "Github Code 3821", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3822", .provider = "huggingface", .display = "Huggingface Reason 3822", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-3823", .provider = "replicate", .display = "Replicate Vision 3823", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3824", .provider = "anyscale", .display = "Anyscale Embed 3824", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3825", .provider = "databricks", .display = "Databricks Audio 3825", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3826", .provider = "moonshot", .display = "Moonshot Fast 3826", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3827", .provider = "qwen", .display = "Qwen Large 3827", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3828", .provider = "minimax", .display = "Minimax Mini 3828", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3829", .provider = "zhipu", .display = "Zhipu Nano 3829", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-3830", .provider = "baichuan", .display = "Baichuan Pro 3830", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3831", .provider = "yi", .display = "Yi Ultra 3831", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3832", .provider = "siliconflow", .display = "Siliconflow Turbo 3832", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3833", .provider = "novita", .display = "Novita Instruct 3833", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3834", .provider = "lepton", .display = "Lepton Base 3834", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3835", .provider = "deepinfra", .display = "Deepinfra Preview 3835", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3836", .provider = "friendli", .display = "Friendli Experimental 3836", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3837", .provider = "hyperbolic", .display = "Hyperbolic Stable 3837", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3838", .provider = "lambda", .display = "Lambda Legacy 3838", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3839", .provider = "nebius", .display = "Nebius Edge 3839", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3840", .provider = "openai", .display = "Openai Chat 3840", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3841", .provider = "anthropic", .display = "Anthropic Code 3841", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3842", .provider = "google", .display = "Google Reason 3842", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3843", .provider = "groq", .display = "Groq Vision 3843", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-3844", .provider = "xai", .display = "Xai Embed 3844", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3845", .provider = "deepseek", .display = "Deepseek Audio 3845", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3846", .provider = "mistral", .display = "Mistral Fast 3846", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3847", .provider = "together", .display = "Together Large 3847", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3848", .provider = "fireworks", .display = "Fireworks Mini 3848", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3849", .provider = "openrouter", .display = "Openrouter Nano 3849", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3850", .provider = "cerebras", .display = "Cerebras Pro 3850", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-3851", .provider = "ollama", .display = "Ollama Ultra 3851", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3852", .provider = "lmstudio", .display = "Lmstudio Turbo 3852", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3853", .provider = "vllm", .display = "Vllm Instruct 3853", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3854", .provider = "azure", .display = "Azure Base 3854", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3855", .provider = "bedrock", .display = "Bedrock Preview 3855", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3856", .provider = "vertex", .display = "Vertex Experimental 3856", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3857", .provider = "perplexity", .display = "Perplexity Stable 3857", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-3858", .provider = "cohere", .display = "Cohere Legacy 3858", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3859", .provider = "nvidia", .display = "Nvidia Edge 3859", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3860", .provider = "sambanova", .display = "Sambanova Chat 3860", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3861", .provider = "github", .display = "Github Code 3861", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3862", .provider = "huggingface", .display = "Huggingface Reason 3862", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3863", .provider = "replicate", .display = "Replicate Vision 3863", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3864", .provider = "anyscale", .display = "Anyscale Embed 3864", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-3865", .provider = "databricks", .display = "Databricks Audio 3865", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3866", .provider = "moonshot", .display = "Moonshot Fast 3866", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3867", .provider = "qwen", .display = "Qwen Large 3867", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3868", .provider = "minimax", .display = "Minimax Mini 3868", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3869", .provider = "zhipu", .display = "Zhipu Nano 3869", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3870", .provider = "baichuan", .display = "Baichuan Pro 3870", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3871", .provider = "yi", .display = "Yi Ultra 3871", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3872", .provider = "siliconflow", .display = "Siliconflow Turbo 3872", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3873", .provider = "novita", .display = "Novita Instruct 3873", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3874", .provider = "lepton", .display = "Lepton Base 3874", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3875", .provider = "deepinfra", .display = "Deepinfra Preview 3875", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3876", .provider = "friendli", .display = "Friendli Experimental 3876", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3877", .provider = "hyperbolic", .display = "Hyperbolic Stable 3877", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3878", .provider = "lambda", .display = "Lambda Legacy 3878", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-3879", .provider = "nebius", .display = "Nebius Edge 3879", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3880", .provider = "openai", .display = "Openai Chat 3880", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3881", .provider = "anthropic", .display = "Anthropic Code 3881", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3882", .provider = "google", .display = "Google Reason 3882", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3883", .provider = "groq", .display = "Groq Vision 3883", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3884", .provider = "xai", .display = "Xai Embed 3884", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3885", .provider = "deepseek", .display = "Deepseek Audio 3885", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-3886", .provider = "mistral", .display = "Mistral Fast 3886", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3887", .provider = "together", .display = "Together Large 3887", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3888", .provider = "fireworks", .display = "Fireworks Mini 3888", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3889", .provider = "openrouter", .display = "Openrouter Nano 3889", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3890", .provider = "cerebras", .display = "Cerebras Pro 3890", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3891", .provider = "ollama", .display = "Ollama Ultra 3891", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3892", .provider = "lmstudio", .display = "Lmstudio Turbo 3892", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-3893", .provider = "vllm", .display = "Vllm Instruct 3893", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3894", .provider = "azure", .display = "Azure Base 3894", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3895", .provider = "bedrock", .display = "Bedrock Preview 3895", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3896", .provider = "vertex", .display = "Vertex Experimental 3896", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3897", .provider = "perplexity", .display = "Perplexity Stable 3897", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3898", .provider = "cohere", .display = "Cohere Legacy 3898", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3899", .provider = "nvidia", .display = "Nvidia Edge 3899", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
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

pub fn model_3800_id() []const u8 {
    return models[0].id;
}
pub fn model_3800_context() u32 {
    return models[0].context_window;
}
pub fn model_3800_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3800_family() []const u8 {
    return models[0].family;
}
pub fn model_3800_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3801_id() []const u8 {
    return models[1].id;
}
pub fn model_3801_context() u32 {
    return models[1].context_window;
}
pub fn model_3801_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3801_family() []const u8 {
    return models[1].family;
}
pub fn model_3801_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3802_id() []const u8 {
    return models[2].id;
}
pub fn model_3802_context() u32 {
    return models[2].context_window;
}
pub fn model_3802_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3802_family() []const u8 {
    return models[2].family;
}
pub fn model_3802_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3803_id() []const u8 {
    return models[3].id;
}
pub fn model_3803_context() u32 {
    return models[3].context_window;
}
pub fn model_3803_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3803_family() []const u8 {
    return models[3].family;
}
pub fn model_3803_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3804_id() []const u8 {
    return models[4].id;
}
pub fn model_3804_context() u32 {
    return models[4].context_window;
}
pub fn model_3804_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3804_family() []const u8 {
    return models[4].family;
}
pub fn model_3804_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3805_id() []const u8 {
    return models[5].id;
}
pub fn model_3805_context() u32 {
    return models[5].context_window;
}
pub fn model_3805_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3805_family() []const u8 {
    return models[5].family;
}
pub fn model_3805_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3806_id() []const u8 {
    return models[6].id;
}
pub fn model_3806_context() u32 {
    return models[6].context_window;
}
pub fn model_3806_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3806_family() []const u8 {
    return models[6].family;
}
pub fn model_3806_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3807_id() []const u8 {
    return models[7].id;
}
pub fn model_3807_context() u32 {
    return models[7].context_window;
}
pub fn model_3807_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3807_family() []const u8 {
    return models[7].family;
}
pub fn model_3807_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3808_id() []const u8 {
    return models[8].id;
}
pub fn model_3808_context() u32 {
    return models[8].context_window;
}
pub fn model_3808_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3808_family() []const u8 {
    return models[8].family;
}
pub fn model_3808_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3809_id() []const u8 {
    return models[9].id;
}
pub fn model_3809_context() u32 {
    return models[9].context_window;
}
pub fn model_3809_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3809_family() []const u8 {
    return models[9].family;
}
pub fn model_3809_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3810_id() []const u8 {
    return models[10].id;
}
pub fn model_3810_context() u32 {
    return models[10].context_window;
}
pub fn model_3810_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3810_family() []const u8 {
    return models[10].family;
}
pub fn model_3810_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3811_id() []const u8 {
    return models[11].id;
}
pub fn model_3811_context() u32 {
    return models[11].context_window;
}
pub fn model_3811_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3811_family() []const u8 {
    return models[11].family;
}
pub fn model_3811_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3812_id() []const u8 {
    return models[12].id;
}
pub fn model_3812_context() u32 {
    return models[12].context_window;
}
pub fn model_3812_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3812_family() []const u8 {
    return models[12].family;
}
pub fn model_3812_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3813_id() []const u8 {
    return models[13].id;
}
pub fn model_3813_context() u32 {
    return models[13].context_window;
}
pub fn model_3813_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3813_family() []const u8 {
    return models[13].family;
}
pub fn model_3813_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3814_id() []const u8 {
    return models[14].id;
}
pub fn model_3814_context() u32 {
    return models[14].context_window;
}
pub fn model_3814_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3814_family() []const u8 {
    return models[14].family;
}
pub fn model_3814_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3815_id() []const u8 {
    return models[15].id;
}
pub fn model_3815_context() u32 {
    return models[15].context_window;
}
pub fn model_3815_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3815_family() []const u8 {
    return models[15].family;
}
pub fn model_3815_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3816_id() []const u8 {
    return models[16].id;
}
pub fn model_3816_context() u32 {
    return models[16].context_window;
}
pub fn model_3816_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3816_family() []const u8 {
    return models[16].family;
}
pub fn model_3816_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3817_id() []const u8 {
    return models[17].id;
}
pub fn model_3817_context() u32 {
    return models[17].context_window;
}
pub fn model_3817_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3817_family() []const u8 {
    return models[17].family;
}
pub fn model_3817_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3818_id() []const u8 {
    return models[18].id;
}
pub fn model_3818_context() u32 {
    return models[18].context_window;
}
pub fn model_3818_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3818_family() []const u8 {
    return models[18].family;
}
pub fn model_3818_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3819_id() []const u8 {
    return models[19].id;
}
pub fn model_3819_context() u32 {
    return models[19].context_window;
}
pub fn model_3819_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3819_family() []const u8 {
    return models[19].family;
}
pub fn model_3819_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3820_id() []const u8 {
    return models[20].id;
}
pub fn model_3820_context() u32 {
    return models[20].context_window;
}
pub fn model_3820_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3820_family() []const u8 {
    return models[20].family;
}
pub fn model_3820_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3821_id() []const u8 {
    return models[21].id;
}
pub fn model_3821_context() u32 {
    return models[21].context_window;
}
pub fn model_3821_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3821_family() []const u8 {
    return models[21].family;
}
pub fn model_3821_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3822_id() []const u8 {
    return models[22].id;
}
pub fn model_3822_context() u32 {
    return models[22].context_window;
}
pub fn model_3822_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3822_family() []const u8 {
    return models[22].family;
}
pub fn model_3822_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3823_id() []const u8 {
    return models[23].id;
}
pub fn model_3823_context() u32 {
    return models[23].context_window;
}
pub fn model_3823_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3823_family() []const u8 {
    return models[23].family;
}
pub fn model_3823_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3824_id() []const u8 {
    return models[24].id;
}
pub fn model_3824_context() u32 {
    return models[24].context_window;
}
pub fn model_3824_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3824_family() []const u8 {
    return models[24].family;
}
pub fn model_3824_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3825_id() []const u8 {
    return models[25].id;
}
pub fn model_3825_context() u32 {
    return models[25].context_window;
}
pub fn model_3825_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3825_family() []const u8 {
    return models[25].family;
}
pub fn model_3825_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3826_id() []const u8 {
    return models[26].id;
}
pub fn model_3826_context() u32 {
    return models[26].context_window;
}
pub fn model_3826_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3826_family() []const u8 {
    return models[26].family;
}
pub fn model_3826_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3827_id() []const u8 {
    return models[27].id;
}
pub fn model_3827_context() u32 {
    return models[27].context_window;
}
pub fn model_3827_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3827_family() []const u8 {
    return models[27].family;
}
pub fn model_3827_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3828_id() []const u8 {
    return models[28].id;
}
pub fn model_3828_context() u32 {
    return models[28].context_window;
}
pub fn model_3828_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3828_family() []const u8 {
    return models[28].family;
}
pub fn model_3828_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3829_id() []const u8 {
    return models[29].id;
}
pub fn model_3829_context() u32 {
    return models[29].context_window;
}
pub fn model_3829_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3829_family() []const u8 {
    return models[29].family;
}
pub fn model_3829_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3830_id() []const u8 {
    return models[30].id;
}
pub fn model_3830_context() u32 {
    return models[30].context_window;
}
pub fn model_3830_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3830_family() []const u8 {
    return models[30].family;
}
pub fn model_3830_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3831_id() []const u8 {
    return models[31].id;
}
pub fn model_3831_context() u32 {
    return models[31].context_window;
}
pub fn model_3831_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3831_family() []const u8 {
    return models[31].family;
}
pub fn model_3831_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3832_id() []const u8 {
    return models[32].id;
}
pub fn model_3832_context() u32 {
    return models[32].context_window;
}
pub fn model_3832_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3832_family() []const u8 {
    return models[32].family;
}
pub fn model_3832_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3833_id() []const u8 {
    return models[33].id;
}
pub fn model_3833_context() u32 {
    return models[33].context_window;
}
pub fn model_3833_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3833_family() []const u8 {
    return models[33].family;
}
pub fn model_3833_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3834_id() []const u8 {
    return models[34].id;
}
pub fn model_3834_context() u32 {
    return models[34].context_window;
}
pub fn model_3834_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3834_family() []const u8 {
    return models[34].family;
}
pub fn model_3834_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3835_id() []const u8 {
    return models[35].id;
}
pub fn model_3835_context() u32 {
    return models[35].context_window;
}
pub fn model_3835_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3835_family() []const u8 {
    return models[35].family;
}
pub fn model_3835_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3836_id() []const u8 {
    return models[36].id;
}
pub fn model_3836_context() u32 {
    return models[36].context_window;
}
pub fn model_3836_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3836_family() []const u8 {
    return models[36].family;
}
pub fn model_3836_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3837_id() []const u8 {
    return models[37].id;
}
pub fn model_3837_context() u32 {
    return models[37].context_window;
}
pub fn model_3837_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3837_family() []const u8 {
    return models[37].family;
}
pub fn model_3837_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3838_id() []const u8 {
    return models[38].id;
}
pub fn model_3838_context() u32 {
    return models[38].context_window;
}
pub fn model_3838_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3838_family() []const u8 {
    return models[38].family;
}
pub fn model_3838_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3839_id() []const u8 {
    return models[39].id;
}
pub fn model_3839_context() u32 {
    return models[39].context_window;
}
pub fn model_3839_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3839_family() []const u8 {
    return models[39].family;
}
pub fn model_3839_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3840_id() []const u8 {
    return models[40].id;
}
pub fn model_3840_context() u32 {
    return models[40].context_window;
}
pub fn model_3840_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3840_family() []const u8 {
    return models[40].family;
}
pub fn model_3840_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3841_id() []const u8 {
    return models[41].id;
}
pub fn model_3841_context() u32 {
    return models[41].context_window;
}
pub fn model_3841_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3841_family() []const u8 {
    return models[41].family;
}
pub fn model_3841_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3842_id() []const u8 {
    return models[42].id;
}
pub fn model_3842_context() u32 {
    return models[42].context_window;
}
pub fn model_3842_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3842_family() []const u8 {
    return models[42].family;
}
pub fn model_3842_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3843_id() []const u8 {
    return models[43].id;
}
pub fn model_3843_context() u32 {
    return models[43].context_window;
}
pub fn model_3843_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3843_family() []const u8 {
    return models[43].family;
}
pub fn model_3843_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3844_id() []const u8 {
    return models[44].id;
}
pub fn model_3844_context() u32 {
    return models[44].context_window;
}
pub fn model_3844_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3844_family() []const u8 {
    return models[44].family;
}
pub fn model_3844_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3845_id() []const u8 {
    return models[45].id;
}
pub fn model_3845_context() u32 {
    return models[45].context_window;
}
pub fn model_3845_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3845_family() []const u8 {
    return models[45].family;
}
pub fn model_3845_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3846_id() []const u8 {
    return models[46].id;
}
pub fn model_3846_context() u32 {
    return models[46].context_window;
}
pub fn model_3846_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3846_family() []const u8 {
    return models[46].family;
}
pub fn model_3846_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3847_id() []const u8 {
    return models[47].id;
}
pub fn model_3847_context() u32 {
    return models[47].context_window;
}
pub fn model_3847_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3847_family() []const u8 {
    return models[47].family;
}
pub fn model_3847_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3848_id() []const u8 {
    return models[48].id;
}
pub fn model_3848_context() u32 {
    return models[48].context_window;
}
pub fn model_3848_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3848_family() []const u8 {
    return models[48].family;
}
pub fn model_3848_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3849_id() []const u8 {
    return models[49].id;
}
pub fn model_3849_context() u32 {
    return models[49].context_window;
}
pub fn model_3849_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3849_family() []const u8 {
    return models[49].family;
}
pub fn model_3849_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3850_id() []const u8 {
    return models[50].id;
}
pub fn model_3850_context() u32 {
    return models[50].context_window;
}
pub fn model_3850_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3850_family() []const u8 {
    return models[50].family;
}
pub fn model_3850_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3851_id() []const u8 {
    return models[51].id;
}
pub fn model_3851_context() u32 {
    return models[51].context_window;
}
pub fn model_3851_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3851_family() []const u8 {
    return models[51].family;
}
pub fn model_3851_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3852_id() []const u8 {
    return models[52].id;
}
pub fn model_3852_context() u32 {
    return models[52].context_window;
}
pub fn model_3852_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3852_family() []const u8 {
    return models[52].family;
}
pub fn model_3852_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3853_id() []const u8 {
    return models[53].id;
}
pub fn model_3853_context() u32 {
    return models[53].context_window;
}
pub fn model_3853_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3853_family() []const u8 {
    return models[53].family;
}
pub fn model_3853_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3854_id() []const u8 {
    return models[54].id;
}
pub fn model_3854_context() u32 {
    return models[54].context_window;
}
pub fn model_3854_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3854_family() []const u8 {
    return models[54].family;
}
pub fn model_3854_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3855_id() []const u8 {
    return models[55].id;
}
pub fn model_3855_context() u32 {
    return models[55].context_window;
}
pub fn model_3855_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3855_family() []const u8 {
    return models[55].family;
}
pub fn model_3855_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3856_id() []const u8 {
    return models[56].id;
}
pub fn model_3856_context() u32 {
    return models[56].context_window;
}
pub fn model_3856_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3856_family() []const u8 {
    return models[56].family;
}
pub fn model_3856_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3857_id() []const u8 {
    return models[57].id;
}
pub fn model_3857_context() u32 {
    return models[57].context_window;
}
pub fn model_3857_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3857_family() []const u8 {
    return models[57].family;
}
pub fn model_3857_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3858_id() []const u8 {
    return models[58].id;
}
pub fn model_3858_context() u32 {
    return models[58].context_window;
}
pub fn model_3858_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3858_family() []const u8 {
    return models[58].family;
}
pub fn model_3858_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3859_id() []const u8 {
    return models[59].id;
}
pub fn model_3859_context() u32 {
    return models[59].context_window;
}
pub fn model_3859_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3859_family() []const u8 {
    return models[59].family;
}
pub fn model_3859_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3860_id() []const u8 {
    return models[60].id;
}
pub fn model_3860_context() u32 {
    return models[60].context_window;
}
pub fn model_3860_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3860_family() []const u8 {
    return models[60].family;
}
pub fn model_3860_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3861_id() []const u8 {
    return models[61].id;
}
pub fn model_3861_context() u32 {
    return models[61].context_window;
}
pub fn model_3861_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3861_family() []const u8 {
    return models[61].family;
}
pub fn model_3861_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3862_id() []const u8 {
    return models[62].id;
}
pub fn model_3862_context() u32 {
    return models[62].context_window;
}
pub fn model_3862_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3862_family() []const u8 {
    return models[62].family;
}
pub fn model_3862_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3863_id() []const u8 {
    return models[63].id;
}
pub fn model_3863_context() u32 {
    return models[63].context_window;
}
pub fn model_3863_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3863_family() []const u8 {
    return models[63].family;
}
pub fn model_3863_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3864_id() []const u8 {
    return models[64].id;
}
pub fn model_3864_context() u32 {
    return models[64].context_window;
}
pub fn model_3864_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3864_family() []const u8 {
    return models[64].family;
}
pub fn model_3864_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3865_id() []const u8 {
    return models[65].id;
}
pub fn model_3865_context() u32 {
    return models[65].context_window;
}
pub fn model_3865_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3865_family() []const u8 {
    return models[65].family;
}
pub fn model_3865_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3866_id() []const u8 {
    return models[66].id;
}
pub fn model_3866_context() u32 {
    return models[66].context_window;
}
pub fn model_3866_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3866_family() []const u8 {
    return models[66].family;
}
pub fn model_3866_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3867_id() []const u8 {
    return models[67].id;
}
pub fn model_3867_context() u32 {
    return models[67].context_window;
}
pub fn model_3867_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3867_family() []const u8 {
    return models[67].family;
}
pub fn model_3867_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3868_id() []const u8 {
    return models[68].id;
}
pub fn model_3868_context() u32 {
    return models[68].context_window;
}
pub fn model_3868_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3868_family() []const u8 {
    return models[68].family;
}
pub fn model_3868_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3869_id() []const u8 {
    return models[69].id;
}
pub fn model_3869_context() u32 {
    return models[69].context_window;
}
pub fn model_3869_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3869_family() []const u8 {
    return models[69].family;
}
pub fn model_3869_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3870_id() []const u8 {
    return models[70].id;
}
pub fn model_3870_context() u32 {
    return models[70].context_window;
}
pub fn model_3870_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3870_family() []const u8 {
    return models[70].family;
}
pub fn model_3870_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3871_id() []const u8 {
    return models[71].id;
}
pub fn model_3871_context() u32 {
    return models[71].context_window;
}
pub fn model_3871_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3871_family() []const u8 {
    return models[71].family;
}
pub fn model_3871_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3872_id() []const u8 {
    return models[72].id;
}
pub fn model_3872_context() u32 {
    return models[72].context_window;
}
pub fn model_3872_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3872_family() []const u8 {
    return models[72].family;
}
pub fn model_3872_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3873_id() []const u8 {
    return models[73].id;
}
pub fn model_3873_context() u32 {
    return models[73].context_window;
}
pub fn model_3873_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3873_family() []const u8 {
    return models[73].family;
}
pub fn model_3873_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3874_id() []const u8 {
    return models[74].id;
}
pub fn model_3874_context() u32 {
    return models[74].context_window;
}
pub fn model_3874_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3874_family() []const u8 {
    return models[74].family;
}
pub fn model_3874_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3875_id() []const u8 {
    return models[75].id;
}
pub fn model_3875_context() u32 {
    return models[75].context_window;
}
pub fn model_3875_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3875_family() []const u8 {
    return models[75].family;
}
pub fn model_3875_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3876_id() []const u8 {
    return models[76].id;
}
pub fn model_3876_context() u32 {
    return models[76].context_window;
}
pub fn model_3876_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3876_family() []const u8 {
    return models[76].family;
}
pub fn model_3876_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3877_id() []const u8 {
    return models[77].id;
}
pub fn model_3877_context() u32 {
    return models[77].context_window;
}
pub fn model_3877_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3877_family() []const u8 {
    return models[77].family;
}
pub fn model_3877_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3878_id() []const u8 {
    return models[78].id;
}
pub fn model_3878_context() u32 {
    return models[78].context_window;
}
pub fn model_3878_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3878_family() []const u8 {
    return models[78].family;
}
pub fn model_3878_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3879_id() []const u8 {
    return models[79].id;
}
pub fn model_3879_context() u32 {
    return models[79].context_window;
}
pub fn model_3879_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3879_family() []const u8 {
    return models[79].family;
}
pub fn model_3879_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 38 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

