//! Generated model catalog shard 30 for package ai.
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

pub const shard_index: u32 = 30;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-3000", .provider = "openai", .display = "Openai Chat 3000", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3001", .provider = "anthropic", .display = "Anthropic Code 3001", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3002", .provider = "google", .display = "Google Reason 3002", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3003", .provider = "groq", .display = "Groq Vision 3003", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-3004", .provider = "xai", .display = "Xai Embed 3004", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3005", .provider = "deepseek", .display = "Deepseek Audio 3005", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3006", .provider = "mistral", .display = "Mistral Fast 3006", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3007", .provider = "together", .display = "Together Large 3007", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3008", .provider = "fireworks", .display = "Fireworks Mini 3008", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3009", .provider = "openrouter", .display = "Openrouter Nano 3009", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3010", .provider = "cerebras", .display = "Cerebras Pro 3010", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-3011", .provider = "ollama", .display = "Ollama Ultra 3011", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3012", .provider = "lmstudio", .display = "Lmstudio Turbo 3012", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3013", .provider = "vllm", .display = "Vllm Instruct 3013", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3014", .provider = "azure", .display = "Azure Base 3014", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3015", .provider = "bedrock", .display = "Bedrock Preview 3015", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3016", .provider = "vertex", .display = "Vertex Experimental 3016", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3017", .provider = "perplexity", .display = "Perplexity Stable 3017", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-3018", .provider = "cohere", .display = "Cohere Legacy 3018", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3019", .provider = "nvidia", .display = "Nvidia Edge 3019", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-3020", .provider = "sambanova", .display = "Sambanova Chat 3020", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3021", .provider = "github", .display = "Github Code 3021", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3022", .provider = "huggingface", .display = "Huggingface Reason 3022", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3023", .provider = "replicate", .display = "Replicate Vision 3023", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3024", .provider = "anyscale", .display = "Anyscale Embed 3024", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-3025", .provider = "databricks", .display = "Databricks Audio 3025", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3026", .provider = "moonshot", .display = "Moonshot Fast 3026", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-3027", .provider = "qwen", .display = "Qwen Large 3027", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3028", .provider = "minimax", .display = "Minimax Mini 3028", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3029", .provider = "zhipu", .display = "Zhipu Nano 3029", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3030", .provider = "baichuan", .display = "Baichuan Pro 3030", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3031", .provider = "yi", .display = "Yi Ultra 3031", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3032", .provider = "siliconflow", .display = "Siliconflow Turbo 3032", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3033", .provider = "novita", .display = "Novita Instruct 3033", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-3034", .provider = "lepton", .display = "Lepton Base 3034", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3035", .provider = "deepinfra", .display = "Deepinfra Preview 3035", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3036", .provider = "friendli", .display = "Friendli Experimental 3036", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3037", .provider = "hyperbolic", .display = "Hyperbolic Stable 3037", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3038", .provider = "lambda", .display = "Lambda Legacy 3038", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-3039", .provider = "nebius", .display = "Nebius Edge 3039", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3040", .provider = "openai", .display = "Openai Chat 3040", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-3041", .provider = "anthropic", .display = "Anthropic Code 3041", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3042", .provider = "google", .display = "Google Reason 3042", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3043", .provider = "groq", .display = "Groq Vision 3043", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3044", .provider = "xai", .display = "Xai Embed 3044", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3045", .provider = "deepseek", .display = "Deepseek Audio 3045", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-3046", .provider = "mistral", .display = "Mistral Fast 3046", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3047", .provider = "together", .display = "Together Large 3047", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-3048", .provider = "fireworks", .display = "Fireworks Mini 3048", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3049", .provider = "openrouter", .display = "Openrouter Nano 3049", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3050", .provider = "cerebras", .display = "Cerebras Pro 3050", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3051", .provider = "ollama", .display = "Ollama Ultra 3051", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3052", .provider = "lmstudio", .display = "Lmstudio Turbo 3052", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-3053", .provider = "vllm", .display = "Vllm Instruct 3053", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3054", .provider = "azure", .display = "Azure Base 3054", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-3055", .provider = "bedrock", .display = "Bedrock Preview 3055", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3056", .provider = "vertex", .display = "Vertex Experimental 3056", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3057", .provider = "perplexity", .display = "Perplexity Stable 3057", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3058", .provider = "cohere", .display = "Cohere Legacy 3058", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3059", .provider = "nvidia", .display = "Nvidia Edge 3059", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-3060", .provider = "sambanova", .display = "Sambanova Chat 3060", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-3061", .provider = "github", .display = "Github Code 3061", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-3062", .provider = "huggingface", .display = "Huggingface Reason 3062", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-3063", .provider = "replicate", .display = "Replicate Vision 3063", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-3064", .provider = "anyscale", .display = "Anyscale Embed 3064", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-3065", .provider = "databricks", .display = "Databricks Audio 3065", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-3066", .provider = "moonshot", .display = "Moonshot Fast 3066", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-3067", .provider = "qwen", .display = "Qwen Large 3067", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-3068", .provider = "minimax", .display = "Minimax Mini 3068", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-3069", .provider = "zhipu", .display = "Zhipu Nano 3069", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-3070", .provider = "baichuan", .display = "Baichuan Pro 3070", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-3071", .provider = "yi", .display = "Yi Ultra 3071", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-3072", .provider = "siliconflow", .display = "Siliconflow Turbo 3072", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-3073", .provider = "novita", .display = "Novita Instruct 3073", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-3074", .provider = "lepton", .display = "Lepton Base 3074", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-3075", .provider = "deepinfra", .display = "Deepinfra Preview 3075", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-3076", .provider = "friendli", .display = "Friendli Experimental 3076", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-3077", .provider = "hyperbolic", .display = "Hyperbolic Stable 3077", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-3078", .provider = "lambda", .display = "Lambda Legacy 3078", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-3079", .provider = "nebius", .display = "Nebius Edge 3079", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-3080", .provider = "openai", .display = "Openai Chat 3080", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-3081", .provider = "anthropic", .display = "Anthropic Code 3081", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-3082", .provider = "google", .display = "Google Reason 3082", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-3083", .provider = "groq", .display = "Groq Vision 3083", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-3084", .provider = "xai", .display = "Xai Embed 3084", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-3085", .provider = "deepseek", .display = "Deepseek Audio 3085", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-3086", .provider = "mistral", .display = "Mistral Fast 3086", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-3087", .provider = "together", .display = "Together Large 3087", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-3088", .provider = "fireworks", .display = "Fireworks Mini 3088", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-3089", .provider = "openrouter", .display = "Openrouter Nano 3089", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-3090", .provider = "cerebras", .display = "Cerebras Pro 3090", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-3091", .provider = "ollama", .display = "Ollama Ultra 3091", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-3092", .provider = "lmstudio", .display = "Lmstudio Turbo 3092", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-3093", .provider = "vllm", .display = "Vllm Instruct 3093", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-3094", .provider = "azure", .display = "Azure Base 3094", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-3095", .provider = "bedrock", .display = "Bedrock Preview 3095", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-3096", .provider = "vertex", .display = "Vertex Experimental 3096", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-3097", .provider = "perplexity", .display = "Perplexity Stable 3097", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-3098", .provider = "cohere", .display = "Cohere Legacy 3098", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-3099", .provider = "nvidia", .display = "Nvidia Edge 3099", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_3000_id() []const u8 {
    return models[0].id;
}
pub fn model_3000_context() u32 {
    return models[0].context_window;
}
pub fn model_3000_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_3000_family() []const u8 {
    return models[0].family;
}
pub fn model_3000_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_3001_id() []const u8 {
    return models[1].id;
}
pub fn model_3001_context() u32 {
    return models[1].context_window;
}
pub fn model_3001_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_3001_family() []const u8 {
    return models[1].family;
}
pub fn model_3001_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_3002_id() []const u8 {
    return models[2].id;
}
pub fn model_3002_context() u32 {
    return models[2].context_window;
}
pub fn model_3002_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_3002_family() []const u8 {
    return models[2].family;
}
pub fn model_3002_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_3003_id() []const u8 {
    return models[3].id;
}
pub fn model_3003_context() u32 {
    return models[3].context_window;
}
pub fn model_3003_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_3003_family() []const u8 {
    return models[3].family;
}
pub fn model_3003_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_3004_id() []const u8 {
    return models[4].id;
}
pub fn model_3004_context() u32 {
    return models[4].context_window;
}
pub fn model_3004_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_3004_family() []const u8 {
    return models[4].family;
}
pub fn model_3004_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_3005_id() []const u8 {
    return models[5].id;
}
pub fn model_3005_context() u32 {
    return models[5].context_window;
}
pub fn model_3005_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_3005_family() []const u8 {
    return models[5].family;
}
pub fn model_3005_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_3006_id() []const u8 {
    return models[6].id;
}
pub fn model_3006_context() u32 {
    return models[6].context_window;
}
pub fn model_3006_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_3006_family() []const u8 {
    return models[6].family;
}
pub fn model_3006_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_3007_id() []const u8 {
    return models[7].id;
}
pub fn model_3007_context() u32 {
    return models[7].context_window;
}
pub fn model_3007_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_3007_family() []const u8 {
    return models[7].family;
}
pub fn model_3007_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_3008_id() []const u8 {
    return models[8].id;
}
pub fn model_3008_context() u32 {
    return models[8].context_window;
}
pub fn model_3008_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_3008_family() []const u8 {
    return models[8].family;
}
pub fn model_3008_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_3009_id() []const u8 {
    return models[9].id;
}
pub fn model_3009_context() u32 {
    return models[9].context_window;
}
pub fn model_3009_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_3009_family() []const u8 {
    return models[9].family;
}
pub fn model_3009_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_3010_id() []const u8 {
    return models[10].id;
}
pub fn model_3010_context() u32 {
    return models[10].context_window;
}
pub fn model_3010_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_3010_family() []const u8 {
    return models[10].family;
}
pub fn model_3010_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_3011_id() []const u8 {
    return models[11].id;
}
pub fn model_3011_context() u32 {
    return models[11].context_window;
}
pub fn model_3011_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_3011_family() []const u8 {
    return models[11].family;
}
pub fn model_3011_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_3012_id() []const u8 {
    return models[12].id;
}
pub fn model_3012_context() u32 {
    return models[12].context_window;
}
pub fn model_3012_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_3012_family() []const u8 {
    return models[12].family;
}
pub fn model_3012_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_3013_id() []const u8 {
    return models[13].id;
}
pub fn model_3013_context() u32 {
    return models[13].context_window;
}
pub fn model_3013_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_3013_family() []const u8 {
    return models[13].family;
}
pub fn model_3013_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_3014_id() []const u8 {
    return models[14].id;
}
pub fn model_3014_context() u32 {
    return models[14].context_window;
}
pub fn model_3014_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_3014_family() []const u8 {
    return models[14].family;
}
pub fn model_3014_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_3015_id() []const u8 {
    return models[15].id;
}
pub fn model_3015_context() u32 {
    return models[15].context_window;
}
pub fn model_3015_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_3015_family() []const u8 {
    return models[15].family;
}
pub fn model_3015_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_3016_id() []const u8 {
    return models[16].id;
}
pub fn model_3016_context() u32 {
    return models[16].context_window;
}
pub fn model_3016_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_3016_family() []const u8 {
    return models[16].family;
}
pub fn model_3016_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_3017_id() []const u8 {
    return models[17].id;
}
pub fn model_3017_context() u32 {
    return models[17].context_window;
}
pub fn model_3017_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_3017_family() []const u8 {
    return models[17].family;
}
pub fn model_3017_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_3018_id() []const u8 {
    return models[18].id;
}
pub fn model_3018_context() u32 {
    return models[18].context_window;
}
pub fn model_3018_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_3018_family() []const u8 {
    return models[18].family;
}
pub fn model_3018_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_3019_id() []const u8 {
    return models[19].id;
}
pub fn model_3019_context() u32 {
    return models[19].context_window;
}
pub fn model_3019_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_3019_family() []const u8 {
    return models[19].family;
}
pub fn model_3019_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_3020_id() []const u8 {
    return models[20].id;
}
pub fn model_3020_context() u32 {
    return models[20].context_window;
}
pub fn model_3020_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_3020_family() []const u8 {
    return models[20].family;
}
pub fn model_3020_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_3021_id() []const u8 {
    return models[21].id;
}
pub fn model_3021_context() u32 {
    return models[21].context_window;
}
pub fn model_3021_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_3021_family() []const u8 {
    return models[21].family;
}
pub fn model_3021_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_3022_id() []const u8 {
    return models[22].id;
}
pub fn model_3022_context() u32 {
    return models[22].context_window;
}
pub fn model_3022_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_3022_family() []const u8 {
    return models[22].family;
}
pub fn model_3022_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_3023_id() []const u8 {
    return models[23].id;
}
pub fn model_3023_context() u32 {
    return models[23].context_window;
}
pub fn model_3023_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_3023_family() []const u8 {
    return models[23].family;
}
pub fn model_3023_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_3024_id() []const u8 {
    return models[24].id;
}
pub fn model_3024_context() u32 {
    return models[24].context_window;
}
pub fn model_3024_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_3024_family() []const u8 {
    return models[24].family;
}
pub fn model_3024_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_3025_id() []const u8 {
    return models[25].id;
}
pub fn model_3025_context() u32 {
    return models[25].context_window;
}
pub fn model_3025_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_3025_family() []const u8 {
    return models[25].family;
}
pub fn model_3025_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_3026_id() []const u8 {
    return models[26].id;
}
pub fn model_3026_context() u32 {
    return models[26].context_window;
}
pub fn model_3026_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_3026_family() []const u8 {
    return models[26].family;
}
pub fn model_3026_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_3027_id() []const u8 {
    return models[27].id;
}
pub fn model_3027_context() u32 {
    return models[27].context_window;
}
pub fn model_3027_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_3027_family() []const u8 {
    return models[27].family;
}
pub fn model_3027_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_3028_id() []const u8 {
    return models[28].id;
}
pub fn model_3028_context() u32 {
    return models[28].context_window;
}
pub fn model_3028_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_3028_family() []const u8 {
    return models[28].family;
}
pub fn model_3028_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_3029_id() []const u8 {
    return models[29].id;
}
pub fn model_3029_context() u32 {
    return models[29].context_window;
}
pub fn model_3029_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_3029_family() []const u8 {
    return models[29].family;
}
pub fn model_3029_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_3030_id() []const u8 {
    return models[30].id;
}
pub fn model_3030_context() u32 {
    return models[30].context_window;
}
pub fn model_3030_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_3030_family() []const u8 {
    return models[30].family;
}
pub fn model_3030_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_3031_id() []const u8 {
    return models[31].id;
}
pub fn model_3031_context() u32 {
    return models[31].context_window;
}
pub fn model_3031_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_3031_family() []const u8 {
    return models[31].family;
}
pub fn model_3031_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_3032_id() []const u8 {
    return models[32].id;
}
pub fn model_3032_context() u32 {
    return models[32].context_window;
}
pub fn model_3032_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_3032_family() []const u8 {
    return models[32].family;
}
pub fn model_3032_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_3033_id() []const u8 {
    return models[33].id;
}
pub fn model_3033_context() u32 {
    return models[33].context_window;
}
pub fn model_3033_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_3033_family() []const u8 {
    return models[33].family;
}
pub fn model_3033_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_3034_id() []const u8 {
    return models[34].id;
}
pub fn model_3034_context() u32 {
    return models[34].context_window;
}
pub fn model_3034_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_3034_family() []const u8 {
    return models[34].family;
}
pub fn model_3034_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_3035_id() []const u8 {
    return models[35].id;
}
pub fn model_3035_context() u32 {
    return models[35].context_window;
}
pub fn model_3035_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_3035_family() []const u8 {
    return models[35].family;
}
pub fn model_3035_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_3036_id() []const u8 {
    return models[36].id;
}
pub fn model_3036_context() u32 {
    return models[36].context_window;
}
pub fn model_3036_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_3036_family() []const u8 {
    return models[36].family;
}
pub fn model_3036_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_3037_id() []const u8 {
    return models[37].id;
}
pub fn model_3037_context() u32 {
    return models[37].context_window;
}
pub fn model_3037_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_3037_family() []const u8 {
    return models[37].family;
}
pub fn model_3037_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_3038_id() []const u8 {
    return models[38].id;
}
pub fn model_3038_context() u32 {
    return models[38].context_window;
}
pub fn model_3038_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_3038_family() []const u8 {
    return models[38].family;
}
pub fn model_3038_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_3039_id() []const u8 {
    return models[39].id;
}
pub fn model_3039_context() u32 {
    return models[39].context_window;
}
pub fn model_3039_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_3039_family() []const u8 {
    return models[39].family;
}
pub fn model_3039_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_3040_id() []const u8 {
    return models[40].id;
}
pub fn model_3040_context() u32 {
    return models[40].context_window;
}
pub fn model_3040_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_3040_family() []const u8 {
    return models[40].family;
}
pub fn model_3040_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_3041_id() []const u8 {
    return models[41].id;
}
pub fn model_3041_context() u32 {
    return models[41].context_window;
}
pub fn model_3041_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_3041_family() []const u8 {
    return models[41].family;
}
pub fn model_3041_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_3042_id() []const u8 {
    return models[42].id;
}
pub fn model_3042_context() u32 {
    return models[42].context_window;
}
pub fn model_3042_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_3042_family() []const u8 {
    return models[42].family;
}
pub fn model_3042_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_3043_id() []const u8 {
    return models[43].id;
}
pub fn model_3043_context() u32 {
    return models[43].context_window;
}
pub fn model_3043_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_3043_family() []const u8 {
    return models[43].family;
}
pub fn model_3043_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_3044_id() []const u8 {
    return models[44].id;
}
pub fn model_3044_context() u32 {
    return models[44].context_window;
}
pub fn model_3044_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_3044_family() []const u8 {
    return models[44].family;
}
pub fn model_3044_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_3045_id() []const u8 {
    return models[45].id;
}
pub fn model_3045_context() u32 {
    return models[45].context_window;
}
pub fn model_3045_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_3045_family() []const u8 {
    return models[45].family;
}
pub fn model_3045_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_3046_id() []const u8 {
    return models[46].id;
}
pub fn model_3046_context() u32 {
    return models[46].context_window;
}
pub fn model_3046_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_3046_family() []const u8 {
    return models[46].family;
}
pub fn model_3046_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_3047_id() []const u8 {
    return models[47].id;
}
pub fn model_3047_context() u32 {
    return models[47].context_window;
}
pub fn model_3047_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_3047_family() []const u8 {
    return models[47].family;
}
pub fn model_3047_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_3048_id() []const u8 {
    return models[48].id;
}
pub fn model_3048_context() u32 {
    return models[48].context_window;
}
pub fn model_3048_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_3048_family() []const u8 {
    return models[48].family;
}
pub fn model_3048_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_3049_id() []const u8 {
    return models[49].id;
}
pub fn model_3049_context() u32 {
    return models[49].context_window;
}
pub fn model_3049_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_3049_family() []const u8 {
    return models[49].family;
}
pub fn model_3049_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_3050_id() []const u8 {
    return models[50].id;
}
pub fn model_3050_context() u32 {
    return models[50].context_window;
}
pub fn model_3050_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_3050_family() []const u8 {
    return models[50].family;
}
pub fn model_3050_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_3051_id() []const u8 {
    return models[51].id;
}
pub fn model_3051_context() u32 {
    return models[51].context_window;
}
pub fn model_3051_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_3051_family() []const u8 {
    return models[51].family;
}
pub fn model_3051_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_3052_id() []const u8 {
    return models[52].id;
}
pub fn model_3052_context() u32 {
    return models[52].context_window;
}
pub fn model_3052_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_3052_family() []const u8 {
    return models[52].family;
}
pub fn model_3052_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_3053_id() []const u8 {
    return models[53].id;
}
pub fn model_3053_context() u32 {
    return models[53].context_window;
}
pub fn model_3053_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_3053_family() []const u8 {
    return models[53].family;
}
pub fn model_3053_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_3054_id() []const u8 {
    return models[54].id;
}
pub fn model_3054_context() u32 {
    return models[54].context_window;
}
pub fn model_3054_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_3054_family() []const u8 {
    return models[54].family;
}
pub fn model_3054_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_3055_id() []const u8 {
    return models[55].id;
}
pub fn model_3055_context() u32 {
    return models[55].context_window;
}
pub fn model_3055_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_3055_family() []const u8 {
    return models[55].family;
}
pub fn model_3055_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_3056_id() []const u8 {
    return models[56].id;
}
pub fn model_3056_context() u32 {
    return models[56].context_window;
}
pub fn model_3056_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_3056_family() []const u8 {
    return models[56].family;
}
pub fn model_3056_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_3057_id() []const u8 {
    return models[57].id;
}
pub fn model_3057_context() u32 {
    return models[57].context_window;
}
pub fn model_3057_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_3057_family() []const u8 {
    return models[57].family;
}
pub fn model_3057_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_3058_id() []const u8 {
    return models[58].id;
}
pub fn model_3058_context() u32 {
    return models[58].context_window;
}
pub fn model_3058_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_3058_family() []const u8 {
    return models[58].family;
}
pub fn model_3058_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_3059_id() []const u8 {
    return models[59].id;
}
pub fn model_3059_context() u32 {
    return models[59].context_window;
}
pub fn model_3059_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_3059_family() []const u8 {
    return models[59].family;
}
pub fn model_3059_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_3060_id() []const u8 {
    return models[60].id;
}
pub fn model_3060_context() u32 {
    return models[60].context_window;
}
pub fn model_3060_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_3060_family() []const u8 {
    return models[60].family;
}
pub fn model_3060_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_3061_id() []const u8 {
    return models[61].id;
}
pub fn model_3061_context() u32 {
    return models[61].context_window;
}
pub fn model_3061_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_3061_family() []const u8 {
    return models[61].family;
}
pub fn model_3061_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_3062_id() []const u8 {
    return models[62].id;
}
pub fn model_3062_context() u32 {
    return models[62].context_window;
}
pub fn model_3062_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_3062_family() []const u8 {
    return models[62].family;
}
pub fn model_3062_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_3063_id() []const u8 {
    return models[63].id;
}
pub fn model_3063_context() u32 {
    return models[63].context_window;
}
pub fn model_3063_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_3063_family() []const u8 {
    return models[63].family;
}
pub fn model_3063_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_3064_id() []const u8 {
    return models[64].id;
}
pub fn model_3064_context() u32 {
    return models[64].context_window;
}
pub fn model_3064_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_3064_family() []const u8 {
    return models[64].family;
}
pub fn model_3064_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_3065_id() []const u8 {
    return models[65].id;
}
pub fn model_3065_context() u32 {
    return models[65].context_window;
}
pub fn model_3065_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_3065_family() []const u8 {
    return models[65].family;
}
pub fn model_3065_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_3066_id() []const u8 {
    return models[66].id;
}
pub fn model_3066_context() u32 {
    return models[66].context_window;
}
pub fn model_3066_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_3066_family() []const u8 {
    return models[66].family;
}
pub fn model_3066_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_3067_id() []const u8 {
    return models[67].id;
}
pub fn model_3067_context() u32 {
    return models[67].context_window;
}
pub fn model_3067_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_3067_family() []const u8 {
    return models[67].family;
}
pub fn model_3067_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_3068_id() []const u8 {
    return models[68].id;
}
pub fn model_3068_context() u32 {
    return models[68].context_window;
}
pub fn model_3068_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_3068_family() []const u8 {
    return models[68].family;
}
pub fn model_3068_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_3069_id() []const u8 {
    return models[69].id;
}
pub fn model_3069_context() u32 {
    return models[69].context_window;
}
pub fn model_3069_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_3069_family() []const u8 {
    return models[69].family;
}
pub fn model_3069_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_3070_id() []const u8 {
    return models[70].id;
}
pub fn model_3070_context() u32 {
    return models[70].context_window;
}
pub fn model_3070_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_3070_family() []const u8 {
    return models[70].family;
}
pub fn model_3070_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_3071_id() []const u8 {
    return models[71].id;
}
pub fn model_3071_context() u32 {
    return models[71].context_window;
}
pub fn model_3071_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_3071_family() []const u8 {
    return models[71].family;
}
pub fn model_3071_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_3072_id() []const u8 {
    return models[72].id;
}
pub fn model_3072_context() u32 {
    return models[72].context_window;
}
pub fn model_3072_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_3072_family() []const u8 {
    return models[72].family;
}
pub fn model_3072_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_3073_id() []const u8 {
    return models[73].id;
}
pub fn model_3073_context() u32 {
    return models[73].context_window;
}
pub fn model_3073_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_3073_family() []const u8 {
    return models[73].family;
}
pub fn model_3073_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_3074_id() []const u8 {
    return models[74].id;
}
pub fn model_3074_context() u32 {
    return models[74].context_window;
}
pub fn model_3074_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_3074_family() []const u8 {
    return models[74].family;
}
pub fn model_3074_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_3075_id() []const u8 {
    return models[75].id;
}
pub fn model_3075_context() u32 {
    return models[75].context_window;
}
pub fn model_3075_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_3075_family() []const u8 {
    return models[75].family;
}
pub fn model_3075_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_3076_id() []const u8 {
    return models[76].id;
}
pub fn model_3076_context() u32 {
    return models[76].context_window;
}
pub fn model_3076_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_3076_family() []const u8 {
    return models[76].family;
}
pub fn model_3076_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_3077_id() []const u8 {
    return models[77].id;
}
pub fn model_3077_context() u32 {
    return models[77].context_window;
}
pub fn model_3077_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_3077_family() []const u8 {
    return models[77].family;
}
pub fn model_3077_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_3078_id() []const u8 {
    return models[78].id;
}
pub fn model_3078_context() u32 {
    return models[78].context_window;
}
pub fn model_3078_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_3078_family() []const u8 {
    return models[78].family;
}
pub fn model_3078_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_3079_id() []const u8 {
    return models[79].id;
}
pub fn model_3079_context() u32 {
    return models[79].context_window;
}
pub fn model_3079_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_3079_family() []const u8 {
    return models[79].family;
}
pub fn model_3079_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 30 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

