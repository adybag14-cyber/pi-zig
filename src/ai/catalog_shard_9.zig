//! Generated model catalog shard 9 for package ai.
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

pub const shard_index: u32 = 9;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-900", .provider = "sambanova", .display = "Sambanova Chat 900", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-901", .provider = "github", .display = "Github Code 901", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-902", .provider = "huggingface", .display = "Huggingface Reason 902", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-903", .provider = "replicate", .display = "Replicate Vision 903", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-904", .provider = "anyscale", .display = "Anyscale Embed 904", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-905", .provider = "databricks", .display = "Databricks Audio 905", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-906", .provider = "moonshot", .display = "Moonshot Fast 906", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-907", .provider = "qwen", .display = "Qwen Large 907", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-908", .provider = "minimax", .display = "Minimax Mini 908", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-909", .provider = "zhipu", .display = "Zhipu Nano 909", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-910", .provider = "baichuan", .display = "Baichuan Pro 910", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-911", .provider = "yi", .display = "Yi Ultra 911", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-912", .provider = "siliconflow", .display = "Siliconflow Turbo 912", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-913", .provider = "novita", .display = "Novita Instruct 913", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-914", .provider = "lepton", .display = "Lepton Base 914", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-915", .provider = "deepinfra", .display = "Deepinfra Preview 915", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-916", .provider = "friendli", .display = "Friendli Experimental 916", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-917", .provider = "hyperbolic", .display = "Hyperbolic Stable 917", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-918", .provider = "lambda", .display = "Lambda Legacy 918", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-919", .provider = "nebius", .display = "Nebius Edge 919", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-920", .provider = "openai", .display = "Openai Chat 920", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-921", .provider = "anthropic", .display = "Anthropic Code 921", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-922", .provider = "google", .display = "Google Reason 922", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-923", .provider = "groq", .display = "Groq Vision 923", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-924", .provider = "xai", .display = "Xai Embed 924", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-925", .provider = "deepseek", .display = "Deepseek Audio 925", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-926", .provider = "mistral", .display = "Mistral Fast 926", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-927", .provider = "together", .display = "Together Large 927", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-928", .provider = "fireworks", .display = "Fireworks Mini 928", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-929", .provider = "openrouter", .display = "Openrouter Nano 929", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-930", .provider = "cerebras", .display = "Cerebras Pro 930", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-931", .provider = "ollama", .display = "Ollama Ultra 931", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-932", .provider = "lmstudio", .display = "Lmstudio Turbo 932", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-933", .provider = "vllm", .display = "Vllm Instruct 933", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-934", .provider = "azure", .display = "Azure Base 934", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-935", .provider = "bedrock", .display = "Bedrock Preview 935", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-936", .provider = "vertex", .display = "Vertex Experimental 936", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-937", .provider = "perplexity", .display = "Perplexity Stable 937", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-938", .provider = "cohere", .display = "Cohere Legacy 938", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-939", .provider = "nvidia", .display = "Nvidia Edge 939", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-940", .provider = "sambanova", .display = "Sambanova Chat 940", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-941", .provider = "github", .display = "Github Code 941", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-942", .provider = "huggingface", .display = "Huggingface Reason 942", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-943", .provider = "replicate", .display = "Replicate Vision 943", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-944", .provider = "anyscale", .display = "Anyscale Embed 944", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-945", .provider = "databricks", .display = "Databricks Audio 945", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-946", .provider = "moonshot", .display = "Moonshot Fast 946", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-947", .provider = "qwen", .display = "Qwen Large 947", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-948", .provider = "minimax", .display = "Minimax Mini 948", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-949", .provider = "zhipu", .display = "Zhipu Nano 949", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-950", .provider = "baichuan", .display = "Baichuan Pro 950", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-951", .provider = "yi", .display = "Yi Ultra 951", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-952", .provider = "siliconflow", .display = "Siliconflow Turbo 952", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-953", .provider = "novita", .display = "Novita Instruct 953", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-954", .provider = "lepton", .display = "Lepton Base 954", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-955", .provider = "deepinfra", .display = "Deepinfra Preview 955", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-956", .provider = "friendli", .display = "Friendli Experimental 956", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-957", .provider = "hyperbolic", .display = "Hyperbolic Stable 957", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-958", .provider = "lambda", .display = "Lambda Legacy 958", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-959", .provider = "nebius", .display = "Nebius Edge 959", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-960", .provider = "openai", .display = "Openai Chat 960", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-961", .provider = "anthropic", .display = "Anthropic Code 961", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-962", .provider = "google", .display = "Google Reason 962", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-963", .provider = "groq", .display = "Groq Vision 963", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-964", .provider = "xai", .display = "Xai Embed 964", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-965", .provider = "deepseek", .display = "Deepseek Audio 965", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-966", .provider = "mistral", .display = "Mistral Fast 966", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-967", .provider = "together", .display = "Together Large 967", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-968", .provider = "fireworks", .display = "Fireworks Mini 968", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-969", .provider = "openrouter", .display = "Openrouter Nano 969", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-970", .provider = "cerebras", .display = "Cerebras Pro 970", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-971", .provider = "ollama", .display = "Ollama Ultra 971", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-972", .provider = "lmstudio", .display = "Lmstudio Turbo 972", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-973", .provider = "vllm", .display = "Vllm Instruct 973", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-974", .provider = "azure", .display = "Azure Base 974", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-975", .provider = "bedrock", .display = "Bedrock Preview 975", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-976", .provider = "vertex", .display = "Vertex Experimental 976", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-977", .provider = "perplexity", .display = "Perplexity Stable 977", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-978", .provider = "cohere", .display = "Cohere Legacy 978", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-979", .provider = "nvidia", .display = "Nvidia Edge 979", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-980", .provider = "sambanova", .display = "Sambanova Chat 980", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-981", .provider = "github", .display = "Github Code 981", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-982", .provider = "huggingface", .display = "Huggingface Reason 982", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-983", .provider = "replicate", .display = "Replicate Vision 983", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-984", .provider = "anyscale", .display = "Anyscale Embed 984", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-985", .provider = "databricks", .display = "Databricks Audio 985", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-986", .provider = "moonshot", .display = "Moonshot Fast 986", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-987", .provider = "qwen", .display = "Qwen Large 987", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-988", .provider = "minimax", .display = "Minimax Mini 988", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-989", .provider = "zhipu", .display = "Zhipu Nano 989", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-990", .provider = "baichuan", .display = "Baichuan Pro 990", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-991", .provider = "yi", .display = "Yi Ultra 991", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-992", .provider = "siliconflow", .display = "Siliconflow Turbo 992", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-993", .provider = "novita", .display = "Novita Instruct 993", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-994", .provider = "lepton", .display = "Lepton Base 994", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-995", .provider = "deepinfra", .display = "Deepinfra Preview 995", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-996", .provider = "friendli", .display = "Friendli Experimental 996", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-997", .provider = "hyperbolic", .display = "Hyperbolic Stable 997", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-998", .provider = "lambda", .display = "Lambda Legacy 998", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-999", .provider = "nebius", .display = "Nebius Edge 999", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_900_id() []const u8 {
    return models[0].id;
}
pub fn model_900_context() u32 {
    return models[0].context_window;
}
pub fn model_900_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_900_family() []const u8 {
    return models[0].family;
}
pub fn model_900_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_901_id() []const u8 {
    return models[1].id;
}
pub fn model_901_context() u32 {
    return models[1].context_window;
}
pub fn model_901_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_901_family() []const u8 {
    return models[1].family;
}
pub fn model_901_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_902_id() []const u8 {
    return models[2].id;
}
pub fn model_902_context() u32 {
    return models[2].context_window;
}
pub fn model_902_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_902_family() []const u8 {
    return models[2].family;
}
pub fn model_902_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_903_id() []const u8 {
    return models[3].id;
}
pub fn model_903_context() u32 {
    return models[3].context_window;
}
pub fn model_903_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_903_family() []const u8 {
    return models[3].family;
}
pub fn model_903_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_904_id() []const u8 {
    return models[4].id;
}
pub fn model_904_context() u32 {
    return models[4].context_window;
}
pub fn model_904_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_904_family() []const u8 {
    return models[4].family;
}
pub fn model_904_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_905_id() []const u8 {
    return models[5].id;
}
pub fn model_905_context() u32 {
    return models[5].context_window;
}
pub fn model_905_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_905_family() []const u8 {
    return models[5].family;
}
pub fn model_905_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_906_id() []const u8 {
    return models[6].id;
}
pub fn model_906_context() u32 {
    return models[6].context_window;
}
pub fn model_906_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_906_family() []const u8 {
    return models[6].family;
}
pub fn model_906_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_907_id() []const u8 {
    return models[7].id;
}
pub fn model_907_context() u32 {
    return models[7].context_window;
}
pub fn model_907_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_907_family() []const u8 {
    return models[7].family;
}
pub fn model_907_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_908_id() []const u8 {
    return models[8].id;
}
pub fn model_908_context() u32 {
    return models[8].context_window;
}
pub fn model_908_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_908_family() []const u8 {
    return models[8].family;
}
pub fn model_908_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_909_id() []const u8 {
    return models[9].id;
}
pub fn model_909_context() u32 {
    return models[9].context_window;
}
pub fn model_909_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_909_family() []const u8 {
    return models[9].family;
}
pub fn model_909_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_910_id() []const u8 {
    return models[10].id;
}
pub fn model_910_context() u32 {
    return models[10].context_window;
}
pub fn model_910_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_910_family() []const u8 {
    return models[10].family;
}
pub fn model_910_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_911_id() []const u8 {
    return models[11].id;
}
pub fn model_911_context() u32 {
    return models[11].context_window;
}
pub fn model_911_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_911_family() []const u8 {
    return models[11].family;
}
pub fn model_911_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_912_id() []const u8 {
    return models[12].id;
}
pub fn model_912_context() u32 {
    return models[12].context_window;
}
pub fn model_912_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_912_family() []const u8 {
    return models[12].family;
}
pub fn model_912_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_913_id() []const u8 {
    return models[13].id;
}
pub fn model_913_context() u32 {
    return models[13].context_window;
}
pub fn model_913_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_913_family() []const u8 {
    return models[13].family;
}
pub fn model_913_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_914_id() []const u8 {
    return models[14].id;
}
pub fn model_914_context() u32 {
    return models[14].context_window;
}
pub fn model_914_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_914_family() []const u8 {
    return models[14].family;
}
pub fn model_914_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_915_id() []const u8 {
    return models[15].id;
}
pub fn model_915_context() u32 {
    return models[15].context_window;
}
pub fn model_915_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_915_family() []const u8 {
    return models[15].family;
}
pub fn model_915_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_916_id() []const u8 {
    return models[16].id;
}
pub fn model_916_context() u32 {
    return models[16].context_window;
}
pub fn model_916_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_916_family() []const u8 {
    return models[16].family;
}
pub fn model_916_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_917_id() []const u8 {
    return models[17].id;
}
pub fn model_917_context() u32 {
    return models[17].context_window;
}
pub fn model_917_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_917_family() []const u8 {
    return models[17].family;
}
pub fn model_917_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_918_id() []const u8 {
    return models[18].id;
}
pub fn model_918_context() u32 {
    return models[18].context_window;
}
pub fn model_918_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_918_family() []const u8 {
    return models[18].family;
}
pub fn model_918_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_919_id() []const u8 {
    return models[19].id;
}
pub fn model_919_context() u32 {
    return models[19].context_window;
}
pub fn model_919_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_919_family() []const u8 {
    return models[19].family;
}
pub fn model_919_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_920_id() []const u8 {
    return models[20].id;
}
pub fn model_920_context() u32 {
    return models[20].context_window;
}
pub fn model_920_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_920_family() []const u8 {
    return models[20].family;
}
pub fn model_920_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_921_id() []const u8 {
    return models[21].id;
}
pub fn model_921_context() u32 {
    return models[21].context_window;
}
pub fn model_921_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_921_family() []const u8 {
    return models[21].family;
}
pub fn model_921_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_922_id() []const u8 {
    return models[22].id;
}
pub fn model_922_context() u32 {
    return models[22].context_window;
}
pub fn model_922_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_922_family() []const u8 {
    return models[22].family;
}
pub fn model_922_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_923_id() []const u8 {
    return models[23].id;
}
pub fn model_923_context() u32 {
    return models[23].context_window;
}
pub fn model_923_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_923_family() []const u8 {
    return models[23].family;
}
pub fn model_923_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_924_id() []const u8 {
    return models[24].id;
}
pub fn model_924_context() u32 {
    return models[24].context_window;
}
pub fn model_924_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_924_family() []const u8 {
    return models[24].family;
}
pub fn model_924_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_925_id() []const u8 {
    return models[25].id;
}
pub fn model_925_context() u32 {
    return models[25].context_window;
}
pub fn model_925_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_925_family() []const u8 {
    return models[25].family;
}
pub fn model_925_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_926_id() []const u8 {
    return models[26].id;
}
pub fn model_926_context() u32 {
    return models[26].context_window;
}
pub fn model_926_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_926_family() []const u8 {
    return models[26].family;
}
pub fn model_926_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_927_id() []const u8 {
    return models[27].id;
}
pub fn model_927_context() u32 {
    return models[27].context_window;
}
pub fn model_927_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_927_family() []const u8 {
    return models[27].family;
}
pub fn model_927_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_928_id() []const u8 {
    return models[28].id;
}
pub fn model_928_context() u32 {
    return models[28].context_window;
}
pub fn model_928_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_928_family() []const u8 {
    return models[28].family;
}
pub fn model_928_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_929_id() []const u8 {
    return models[29].id;
}
pub fn model_929_context() u32 {
    return models[29].context_window;
}
pub fn model_929_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_929_family() []const u8 {
    return models[29].family;
}
pub fn model_929_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_930_id() []const u8 {
    return models[30].id;
}
pub fn model_930_context() u32 {
    return models[30].context_window;
}
pub fn model_930_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_930_family() []const u8 {
    return models[30].family;
}
pub fn model_930_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_931_id() []const u8 {
    return models[31].id;
}
pub fn model_931_context() u32 {
    return models[31].context_window;
}
pub fn model_931_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_931_family() []const u8 {
    return models[31].family;
}
pub fn model_931_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_932_id() []const u8 {
    return models[32].id;
}
pub fn model_932_context() u32 {
    return models[32].context_window;
}
pub fn model_932_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_932_family() []const u8 {
    return models[32].family;
}
pub fn model_932_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_933_id() []const u8 {
    return models[33].id;
}
pub fn model_933_context() u32 {
    return models[33].context_window;
}
pub fn model_933_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_933_family() []const u8 {
    return models[33].family;
}
pub fn model_933_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_934_id() []const u8 {
    return models[34].id;
}
pub fn model_934_context() u32 {
    return models[34].context_window;
}
pub fn model_934_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_934_family() []const u8 {
    return models[34].family;
}
pub fn model_934_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_935_id() []const u8 {
    return models[35].id;
}
pub fn model_935_context() u32 {
    return models[35].context_window;
}
pub fn model_935_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_935_family() []const u8 {
    return models[35].family;
}
pub fn model_935_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_936_id() []const u8 {
    return models[36].id;
}
pub fn model_936_context() u32 {
    return models[36].context_window;
}
pub fn model_936_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_936_family() []const u8 {
    return models[36].family;
}
pub fn model_936_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_937_id() []const u8 {
    return models[37].id;
}
pub fn model_937_context() u32 {
    return models[37].context_window;
}
pub fn model_937_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_937_family() []const u8 {
    return models[37].family;
}
pub fn model_937_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_938_id() []const u8 {
    return models[38].id;
}
pub fn model_938_context() u32 {
    return models[38].context_window;
}
pub fn model_938_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_938_family() []const u8 {
    return models[38].family;
}
pub fn model_938_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_939_id() []const u8 {
    return models[39].id;
}
pub fn model_939_context() u32 {
    return models[39].context_window;
}
pub fn model_939_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_939_family() []const u8 {
    return models[39].family;
}
pub fn model_939_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_940_id() []const u8 {
    return models[40].id;
}
pub fn model_940_context() u32 {
    return models[40].context_window;
}
pub fn model_940_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_940_family() []const u8 {
    return models[40].family;
}
pub fn model_940_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_941_id() []const u8 {
    return models[41].id;
}
pub fn model_941_context() u32 {
    return models[41].context_window;
}
pub fn model_941_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_941_family() []const u8 {
    return models[41].family;
}
pub fn model_941_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_942_id() []const u8 {
    return models[42].id;
}
pub fn model_942_context() u32 {
    return models[42].context_window;
}
pub fn model_942_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_942_family() []const u8 {
    return models[42].family;
}
pub fn model_942_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_943_id() []const u8 {
    return models[43].id;
}
pub fn model_943_context() u32 {
    return models[43].context_window;
}
pub fn model_943_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_943_family() []const u8 {
    return models[43].family;
}
pub fn model_943_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_944_id() []const u8 {
    return models[44].id;
}
pub fn model_944_context() u32 {
    return models[44].context_window;
}
pub fn model_944_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_944_family() []const u8 {
    return models[44].family;
}
pub fn model_944_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_945_id() []const u8 {
    return models[45].id;
}
pub fn model_945_context() u32 {
    return models[45].context_window;
}
pub fn model_945_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_945_family() []const u8 {
    return models[45].family;
}
pub fn model_945_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_946_id() []const u8 {
    return models[46].id;
}
pub fn model_946_context() u32 {
    return models[46].context_window;
}
pub fn model_946_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_946_family() []const u8 {
    return models[46].family;
}
pub fn model_946_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_947_id() []const u8 {
    return models[47].id;
}
pub fn model_947_context() u32 {
    return models[47].context_window;
}
pub fn model_947_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_947_family() []const u8 {
    return models[47].family;
}
pub fn model_947_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_948_id() []const u8 {
    return models[48].id;
}
pub fn model_948_context() u32 {
    return models[48].context_window;
}
pub fn model_948_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_948_family() []const u8 {
    return models[48].family;
}
pub fn model_948_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_949_id() []const u8 {
    return models[49].id;
}
pub fn model_949_context() u32 {
    return models[49].context_window;
}
pub fn model_949_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_949_family() []const u8 {
    return models[49].family;
}
pub fn model_949_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_950_id() []const u8 {
    return models[50].id;
}
pub fn model_950_context() u32 {
    return models[50].context_window;
}
pub fn model_950_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_950_family() []const u8 {
    return models[50].family;
}
pub fn model_950_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_951_id() []const u8 {
    return models[51].id;
}
pub fn model_951_context() u32 {
    return models[51].context_window;
}
pub fn model_951_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_951_family() []const u8 {
    return models[51].family;
}
pub fn model_951_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_952_id() []const u8 {
    return models[52].id;
}
pub fn model_952_context() u32 {
    return models[52].context_window;
}
pub fn model_952_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_952_family() []const u8 {
    return models[52].family;
}
pub fn model_952_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_953_id() []const u8 {
    return models[53].id;
}
pub fn model_953_context() u32 {
    return models[53].context_window;
}
pub fn model_953_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_953_family() []const u8 {
    return models[53].family;
}
pub fn model_953_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_954_id() []const u8 {
    return models[54].id;
}
pub fn model_954_context() u32 {
    return models[54].context_window;
}
pub fn model_954_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_954_family() []const u8 {
    return models[54].family;
}
pub fn model_954_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_955_id() []const u8 {
    return models[55].id;
}
pub fn model_955_context() u32 {
    return models[55].context_window;
}
pub fn model_955_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_955_family() []const u8 {
    return models[55].family;
}
pub fn model_955_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_956_id() []const u8 {
    return models[56].id;
}
pub fn model_956_context() u32 {
    return models[56].context_window;
}
pub fn model_956_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_956_family() []const u8 {
    return models[56].family;
}
pub fn model_956_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_957_id() []const u8 {
    return models[57].id;
}
pub fn model_957_context() u32 {
    return models[57].context_window;
}
pub fn model_957_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_957_family() []const u8 {
    return models[57].family;
}
pub fn model_957_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_958_id() []const u8 {
    return models[58].id;
}
pub fn model_958_context() u32 {
    return models[58].context_window;
}
pub fn model_958_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_958_family() []const u8 {
    return models[58].family;
}
pub fn model_958_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_959_id() []const u8 {
    return models[59].id;
}
pub fn model_959_context() u32 {
    return models[59].context_window;
}
pub fn model_959_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_959_family() []const u8 {
    return models[59].family;
}
pub fn model_959_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_960_id() []const u8 {
    return models[60].id;
}
pub fn model_960_context() u32 {
    return models[60].context_window;
}
pub fn model_960_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_960_family() []const u8 {
    return models[60].family;
}
pub fn model_960_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_961_id() []const u8 {
    return models[61].id;
}
pub fn model_961_context() u32 {
    return models[61].context_window;
}
pub fn model_961_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_961_family() []const u8 {
    return models[61].family;
}
pub fn model_961_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_962_id() []const u8 {
    return models[62].id;
}
pub fn model_962_context() u32 {
    return models[62].context_window;
}
pub fn model_962_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_962_family() []const u8 {
    return models[62].family;
}
pub fn model_962_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_963_id() []const u8 {
    return models[63].id;
}
pub fn model_963_context() u32 {
    return models[63].context_window;
}
pub fn model_963_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_963_family() []const u8 {
    return models[63].family;
}
pub fn model_963_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_964_id() []const u8 {
    return models[64].id;
}
pub fn model_964_context() u32 {
    return models[64].context_window;
}
pub fn model_964_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_964_family() []const u8 {
    return models[64].family;
}
pub fn model_964_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_965_id() []const u8 {
    return models[65].id;
}
pub fn model_965_context() u32 {
    return models[65].context_window;
}
pub fn model_965_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_965_family() []const u8 {
    return models[65].family;
}
pub fn model_965_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_966_id() []const u8 {
    return models[66].id;
}
pub fn model_966_context() u32 {
    return models[66].context_window;
}
pub fn model_966_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_966_family() []const u8 {
    return models[66].family;
}
pub fn model_966_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_967_id() []const u8 {
    return models[67].id;
}
pub fn model_967_context() u32 {
    return models[67].context_window;
}
pub fn model_967_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_967_family() []const u8 {
    return models[67].family;
}
pub fn model_967_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_968_id() []const u8 {
    return models[68].id;
}
pub fn model_968_context() u32 {
    return models[68].context_window;
}
pub fn model_968_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_968_family() []const u8 {
    return models[68].family;
}
pub fn model_968_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_969_id() []const u8 {
    return models[69].id;
}
pub fn model_969_context() u32 {
    return models[69].context_window;
}
pub fn model_969_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_969_family() []const u8 {
    return models[69].family;
}
pub fn model_969_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_970_id() []const u8 {
    return models[70].id;
}
pub fn model_970_context() u32 {
    return models[70].context_window;
}
pub fn model_970_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_970_family() []const u8 {
    return models[70].family;
}
pub fn model_970_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_971_id() []const u8 {
    return models[71].id;
}
pub fn model_971_context() u32 {
    return models[71].context_window;
}
pub fn model_971_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_971_family() []const u8 {
    return models[71].family;
}
pub fn model_971_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_972_id() []const u8 {
    return models[72].id;
}
pub fn model_972_context() u32 {
    return models[72].context_window;
}
pub fn model_972_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_972_family() []const u8 {
    return models[72].family;
}
pub fn model_972_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_973_id() []const u8 {
    return models[73].id;
}
pub fn model_973_context() u32 {
    return models[73].context_window;
}
pub fn model_973_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_973_family() []const u8 {
    return models[73].family;
}
pub fn model_973_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_974_id() []const u8 {
    return models[74].id;
}
pub fn model_974_context() u32 {
    return models[74].context_window;
}
pub fn model_974_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_974_family() []const u8 {
    return models[74].family;
}
pub fn model_974_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_975_id() []const u8 {
    return models[75].id;
}
pub fn model_975_context() u32 {
    return models[75].context_window;
}
pub fn model_975_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_975_family() []const u8 {
    return models[75].family;
}
pub fn model_975_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_976_id() []const u8 {
    return models[76].id;
}
pub fn model_976_context() u32 {
    return models[76].context_window;
}
pub fn model_976_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_976_family() []const u8 {
    return models[76].family;
}
pub fn model_976_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_977_id() []const u8 {
    return models[77].id;
}
pub fn model_977_context() u32 {
    return models[77].context_window;
}
pub fn model_977_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_977_family() []const u8 {
    return models[77].family;
}
pub fn model_977_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_978_id() []const u8 {
    return models[78].id;
}
pub fn model_978_context() u32 {
    return models[78].context_window;
}
pub fn model_978_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_978_family() []const u8 {
    return models[78].family;
}
pub fn model_978_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_979_id() []const u8 {
    return models[79].id;
}
pub fn model_979_context() u32 {
    return models[79].context_window;
}
pub fn model_979_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_979_family() []const u8 {
    return models[79].family;
}
pub fn model_979_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 9 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

