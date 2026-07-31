//! Generated model catalog shard 7 for package ai.
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

pub const shard_index: u32 = 7;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-700", .provider = "sambanova", .display = "Sambanova Chat 700", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-701", .provider = "github", .display = "Github Code 701", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-702", .provider = "huggingface", .display = "Huggingface Reason 702", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-703", .provider = "replicate", .display = "Replicate Vision 703", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-704", .provider = "anyscale", .display = "Anyscale Embed 704", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-705", .provider = "databricks", .display = "Databricks Audio 705", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-706", .provider = "moonshot", .display = "Moonshot Fast 706", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-707", .provider = "qwen", .display = "Qwen Large 707", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-708", .provider = "minimax", .display = "Minimax Mini 708", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-709", .provider = "zhipu", .display = "Zhipu Nano 709", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-710", .provider = "baichuan", .display = "Baichuan Pro 710", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-711", .provider = "yi", .display = "Yi Ultra 711", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-712", .provider = "siliconflow", .display = "Siliconflow Turbo 712", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-713", .provider = "novita", .display = "Novita Instruct 713", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-714", .provider = "lepton", .display = "Lepton Base 714", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-715", .provider = "deepinfra", .display = "Deepinfra Preview 715", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-716", .provider = "friendli", .display = "Friendli Experimental 716", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-717", .provider = "hyperbolic", .display = "Hyperbolic Stable 717", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-718", .provider = "lambda", .display = "Lambda Legacy 718", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-719", .provider = "nebius", .display = "Nebius Edge 719", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-720", .provider = "openai", .display = "Openai Chat 720", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-721", .provider = "anthropic", .display = "Anthropic Code 721", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-722", .provider = "google", .display = "Google Reason 722", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-723", .provider = "groq", .display = "Groq Vision 723", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-724", .provider = "xai", .display = "Xai Embed 724", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-725", .provider = "deepseek", .display = "Deepseek Audio 725", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-726", .provider = "mistral", .display = "Mistral Fast 726", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-727", .provider = "together", .display = "Together Large 727", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-728", .provider = "fireworks", .display = "Fireworks Mini 728", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-729", .provider = "openrouter", .display = "Openrouter Nano 729", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-730", .provider = "cerebras", .display = "Cerebras Pro 730", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-731", .provider = "ollama", .display = "Ollama Ultra 731", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-732", .provider = "lmstudio", .display = "Lmstudio Turbo 732", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-733", .provider = "vllm", .display = "Vllm Instruct 733", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-734", .provider = "azure", .display = "Azure Base 734", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-735", .provider = "bedrock", .display = "Bedrock Preview 735", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-736", .provider = "vertex", .display = "Vertex Experimental 736", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-737", .provider = "perplexity", .display = "Perplexity Stable 737", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-738", .provider = "cohere", .display = "Cohere Legacy 738", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-739", .provider = "nvidia", .display = "Nvidia Edge 739", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-740", .provider = "sambanova", .display = "Sambanova Chat 740", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-741", .provider = "github", .display = "Github Code 741", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-742", .provider = "huggingface", .display = "Huggingface Reason 742", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-743", .provider = "replicate", .display = "Replicate Vision 743", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-744", .provider = "anyscale", .display = "Anyscale Embed 744", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-745", .provider = "databricks", .display = "Databricks Audio 745", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-746", .provider = "moonshot", .display = "Moonshot Fast 746", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-747", .provider = "qwen", .display = "Qwen Large 747", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-748", .provider = "minimax", .display = "Minimax Mini 748", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-749", .provider = "zhipu", .display = "Zhipu Nano 749", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-750", .provider = "baichuan", .display = "Baichuan Pro 750", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-751", .provider = "yi", .display = "Yi Ultra 751", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-752", .provider = "siliconflow", .display = "Siliconflow Turbo 752", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-753", .provider = "novita", .display = "Novita Instruct 753", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-754", .provider = "lepton", .display = "Lepton Base 754", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-755", .provider = "deepinfra", .display = "Deepinfra Preview 755", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-756", .provider = "friendli", .display = "Friendli Experimental 756", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-757", .provider = "hyperbolic", .display = "Hyperbolic Stable 757", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-758", .provider = "lambda", .display = "Lambda Legacy 758", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-759", .provider = "nebius", .display = "Nebius Edge 759", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-760", .provider = "openai", .display = "Openai Chat 760", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-761", .provider = "anthropic", .display = "Anthropic Code 761", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-762", .provider = "google", .display = "Google Reason 762", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-763", .provider = "groq", .display = "Groq Vision 763", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-764", .provider = "xai", .display = "Xai Embed 764", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-765", .provider = "deepseek", .display = "Deepseek Audio 765", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-766", .provider = "mistral", .display = "Mistral Fast 766", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-767", .provider = "together", .display = "Together Large 767", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-768", .provider = "fireworks", .display = "Fireworks Mini 768", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-769", .provider = "openrouter", .display = "Openrouter Nano 769", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-770", .provider = "cerebras", .display = "Cerebras Pro 770", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-771", .provider = "ollama", .display = "Ollama Ultra 771", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-772", .provider = "lmstudio", .display = "Lmstudio Turbo 772", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-773", .provider = "vllm", .display = "Vllm Instruct 773", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-774", .provider = "azure", .display = "Azure Base 774", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-775", .provider = "bedrock", .display = "Bedrock Preview 775", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-776", .provider = "vertex", .display = "Vertex Experimental 776", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-777", .provider = "perplexity", .display = "Perplexity Stable 777", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-778", .provider = "cohere", .display = "Cohere Legacy 778", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-779", .provider = "nvidia", .display = "Nvidia Edge 779", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-780", .provider = "sambanova", .display = "Sambanova Chat 780", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-781", .provider = "github", .display = "Github Code 781", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-782", .provider = "huggingface", .display = "Huggingface Reason 782", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-783", .provider = "replicate", .display = "Replicate Vision 783", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-784", .provider = "anyscale", .display = "Anyscale Embed 784", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-785", .provider = "databricks", .display = "Databricks Audio 785", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-786", .provider = "moonshot", .display = "Moonshot Fast 786", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-787", .provider = "qwen", .display = "Qwen Large 787", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-788", .provider = "minimax", .display = "Minimax Mini 788", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-789", .provider = "zhipu", .display = "Zhipu Nano 789", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-790", .provider = "baichuan", .display = "Baichuan Pro 790", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-791", .provider = "yi", .display = "Yi Ultra 791", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-792", .provider = "siliconflow", .display = "Siliconflow Turbo 792", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-793", .provider = "novita", .display = "Novita Instruct 793", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-794", .provider = "lepton", .display = "Lepton Base 794", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-795", .provider = "deepinfra", .display = "Deepinfra Preview 795", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-796", .provider = "friendli", .display = "Friendli Experimental 796", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-797", .provider = "hyperbolic", .display = "Hyperbolic Stable 797", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-798", .provider = "lambda", .display = "Lambda Legacy 798", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-799", .provider = "nebius", .display = "Nebius Edge 799", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_700_id() []const u8 {
    return models[0].id;
}
pub fn model_700_context() u32 {
    return models[0].context_window;
}
pub fn model_700_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_700_family() []const u8 {
    return models[0].family;
}
pub fn model_700_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_701_id() []const u8 {
    return models[1].id;
}
pub fn model_701_context() u32 {
    return models[1].context_window;
}
pub fn model_701_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_701_family() []const u8 {
    return models[1].family;
}
pub fn model_701_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_702_id() []const u8 {
    return models[2].id;
}
pub fn model_702_context() u32 {
    return models[2].context_window;
}
pub fn model_702_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_702_family() []const u8 {
    return models[2].family;
}
pub fn model_702_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_703_id() []const u8 {
    return models[3].id;
}
pub fn model_703_context() u32 {
    return models[3].context_window;
}
pub fn model_703_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_703_family() []const u8 {
    return models[3].family;
}
pub fn model_703_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_704_id() []const u8 {
    return models[4].id;
}
pub fn model_704_context() u32 {
    return models[4].context_window;
}
pub fn model_704_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_704_family() []const u8 {
    return models[4].family;
}
pub fn model_704_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_705_id() []const u8 {
    return models[5].id;
}
pub fn model_705_context() u32 {
    return models[5].context_window;
}
pub fn model_705_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_705_family() []const u8 {
    return models[5].family;
}
pub fn model_705_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_706_id() []const u8 {
    return models[6].id;
}
pub fn model_706_context() u32 {
    return models[6].context_window;
}
pub fn model_706_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_706_family() []const u8 {
    return models[6].family;
}
pub fn model_706_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_707_id() []const u8 {
    return models[7].id;
}
pub fn model_707_context() u32 {
    return models[7].context_window;
}
pub fn model_707_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_707_family() []const u8 {
    return models[7].family;
}
pub fn model_707_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_708_id() []const u8 {
    return models[8].id;
}
pub fn model_708_context() u32 {
    return models[8].context_window;
}
pub fn model_708_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_708_family() []const u8 {
    return models[8].family;
}
pub fn model_708_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_709_id() []const u8 {
    return models[9].id;
}
pub fn model_709_context() u32 {
    return models[9].context_window;
}
pub fn model_709_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_709_family() []const u8 {
    return models[9].family;
}
pub fn model_709_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_710_id() []const u8 {
    return models[10].id;
}
pub fn model_710_context() u32 {
    return models[10].context_window;
}
pub fn model_710_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_710_family() []const u8 {
    return models[10].family;
}
pub fn model_710_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_711_id() []const u8 {
    return models[11].id;
}
pub fn model_711_context() u32 {
    return models[11].context_window;
}
pub fn model_711_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_711_family() []const u8 {
    return models[11].family;
}
pub fn model_711_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_712_id() []const u8 {
    return models[12].id;
}
pub fn model_712_context() u32 {
    return models[12].context_window;
}
pub fn model_712_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_712_family() []const u8 {
    return models[12].family;
}
pub fn model_712_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_713_id() []const u8 {
    return models[13].id;
}
pub fn model_713_context() u32 {
    return models[13].context_window;
}
pub fn model_713_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_713_family() []const u8 {
    return models[13].family;
}
pub fn model_713_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_714_id() []const u8 {
    return models[14].id;
}
pub fn model_714_context() u32 {
    return models[14].context_window;
}
pub fn model_714_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_714_family() []const u8 {
    return models[14].family;
}
pub fn model_714_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_715_id() []const u8 {
    return models[15].id;
}
pub fn model_715_context() u32 {
    return models[15].context_window;
}
pub fn model_715_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_715_family() []const u8 {
    return models[15].family;
}
pub fn model_715_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_716_id() []const u8 {
    return models[16].id;
}
pub fn model_716_context() u32 {
    return models[16].context_window;
}
pub fn model_716_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_716_family() []const u8 {
    return models[16].family;
}
pub fn model_716_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_717_id() []const u8 {
    return models[17].id;
}
pub fn model_717_context() u32 {
    return models[17].context_window;
}
pub fn model_717_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_717_family() []const u8 {
    return models[17].family;
}
pub fn model_717_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_718_id() []const u8 {
    return models[18].id;
}
pub fn model_718_context() u32 {
    return models[18].context_window;
}
pub fn model_718_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_718_family() []const u8 {
    return models[18].family;
}
pub fn model_718_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_719_id() []const u8 {
    return models[19].id;
}
pub fn model_719_context() u32 {
    return models[19].context_window;
}
pub fn model_719_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_719_family() []const u8 {
    return models[19].family;
}
pub fn model_719_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_720_id() []const u8 {
    return models[20].id;
}
pub fn model_720_context() u32 {
    return models[20].context_window;
}
pub fn model_720_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_720_family() []const u8 {
    return models[20].family;
}
pub fn model_720_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_721_id() []const u8 {
    return models[21].id;
}
pub fn model_721_context() u32 {
    return models[21].context_window;
}
pub fn model_721_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_721_family() []const u8 {
    return models[21].family;
}
pub fn model_721_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_722_id() []const u8 {
    return models[22].id;
}
pub fn model_722_context() u32 {
    return models[22].context_window;
}
pub fn model_722_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_722_family() []const u8 {
    return models[22].family;
}
pub fn model_722_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_723_id() []const u8 {
    return models[23].id;
}
pub fn model_723_context() u32 {
    return models[23].context_window;
}
pub fn model_723_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_723_family() []const u8 {
    return models[23].family;
}
pub fn model_723_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_724_id() []const u8 {
    return models[24].id;
}
pub fn model_724_context() u32 {
    return models[24].context_window;
}
pub fn model_724_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_724_family() []const u8 {
    return models[24].family;
}
pub fn model_724_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_725_id() []const u8 {
    return models[25].id;
}
pub fn model_725_context() u32 {
    return models[25].context_window;
}
pub fn model_725_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_725_family() []const u8 {
    return models[25].family;
}
pub fn model_725_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_726_id() []const u8 {
    return models[26].id;
}
pub fn model_726_context() u32 {
    return models[26].context_window;
}
pub fn model_726_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_726_family() []const u8 {
    return models[26].family;
}
pub fn model_726_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_727_id() []const u8 {
    return models[27].id;
}
pub fn model_727_context() u32 {
    return models[27].context_window;
}
pub fn model_727_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_727_family() []const u8 {
    return models[27].family;
}
pub fn model_727_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_728_id() []const u8 {
    return models[28].id;
}
pub fn model_728_context() u32 {
    return models[28].context_window;
}
pub fn model_728_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_728_family() []const u8 {
    return models[28].family;
}
pub fn model_728_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_729_id() []const u8 {
    return models[29].id;
}
pub fn model_729_context() u32 {
    return models[29].context_window;
}
pub fn model_729_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_729_family() []const u8 {
    return models[29].family;
}
pub fn model_729_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_730_id() []const u8 {
    return models[30].id;
}
pub fn model_730_context() u32 {
    return models[30].context_window;
}
pub fn model_730_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_730_family() []const u8 {
    return models[30].family;
}
pub fn model_730_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_731_id() []const u8 {
    return models[31].id;
}
pub fn model_731_context() u32 {
    return models[31].context_window;
}
pub fn model_731_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_731_family() []const u8 {
    return models[31].family;
}
pub fn model_731_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_732_id() []const u8 {
    return models[32].id;
}
pub fn model_732_context() u32 {
    return models[32].context_window;
}
pub fn model_732_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_732_family() []const u8 {
    return models[32].family;
}
pub fn model_732_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_733_id() []const u8 {
    return models[33].id;
}
pub fn model_733_context() u32 {
    return models[33].context_window;
}
pub fn model_733_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_733_family() []const u8 {
    return models[33].family;
}
pub fn model_733_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_734_id() []const u8 {
    return models[34].id;
}
pub fn model_734_context() u32 {
    return models[34].context_window;
}
pub fn model_734_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_734_family() []const u8 {
    return models[34].family;
}
pub fn model_734_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_735_id() []const u8 {
    return models[35].id;
}
pub fn model_735_context() u32 {
    return models[35].context_window;
}
pub fn model_735_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_735_family() []const u8 {
    return models[35].family;
}
pub fn model_735_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_736_id() []const u8 {
    return models[36].id;
}
pub fn model_736_context() u32 {
    return models[36].context_window;
}
pub fn model_736_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_736_family() []const u8 {
    return models[36].family;
}
pub fn model_736_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_737_id() []const u8 {
    return models[37].id;
}
pub fn model_737_context() u32 {
    return models[37].context_window;
}
pub fn model_737_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_737_family() []const u8 {
    return models[37].family;
}
pub fn model_737_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_738_id() []const u8 {
    return models[38].id;
}
pub fn model_738_context() u32 {
    return models[38].context_window;
}
pub fn model_738_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_738_family() []const u8 {
    return models[38].family;
}
pub fn model_738_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_739_id() []const u8 {
    return models[39].id;
}
pub fn model_739_context() u32 {
    return models[39].context_window;
}
pub fn model_739_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_739_family() []const u8 {
    return models[39].family;
}
pub fn model_739_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_740_id() []const u8 {
    return models[40].id;
}
pub fn model_740_context() u32 {
    return models[40].context_window;
}
pub fn model_740_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_740_family() []const u8 {
    return models[40].family;
}
pub fn model_740_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_741_id() []const u8 {
    return models[41].id;
}
pub fn model_741_context() u32 {
    return models[41].context_window;
}
pub fn model_741_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_741_family() []const u8 {
    return models[41].family;
}
pub fn model_741_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_742_id() []const u8 {
    return models[42].id;
}
pub fn model_742_context() u32 {
    return models[42].context_window;
}
pub fn model_742_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_742_family() []const u8 {
    return models[42].family;
}
pub fn model_742_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_743_id() []const u8 {
    return models[43].id;
}
pub fn model_743_context() u32 {
    return models[43].context_window;
}
pub fn model_743_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_743_family() []const u8 {
    return models[43].family;
}
pub fn model_743_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_744_id() []const u8 {
    return models[44].id;
}
pub fn model_744_context() u32 {
    return models[44].context_window;
}
pub fn model_744_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_744_family() []const u8 {
    return models[44].family;
}
pub fn model_744_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_745_id() []const u8 {
    return models[45].id;
}
pub fn model_745_context() u32 {
    return models[45].context_window;
}
pub fn model_745_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_745_family() []const u8 {
    return models[45].family;
}
pub fn model_745_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_746_id() []const u8 {
    return models[46].id;
}
pub fn model_746_context() u32 {
    return models[46].context_window;
}
pub fn model_746_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_746_family() []const u8 {
    return models[46].family;
}
pub fn model_746_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_747_id() []const u8 {
    return models[47].id;
}
pub fn model_747_context() u32 {
    return models[47].context_window;
}
pub fn model_747_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_747_family() []const u8 {
    return models[47].family;
}
pub fn model_747_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_748_id() []const u8 {
    return models[48].id;
}
pub fn model_748_context() u32 {
    return models[48].context_window;
}
pub fn model_748_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_748_family() []const u8 {
    return models[48].family;
}
pub fn model_748_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_749_id() []const u8 {
    return models[49].id;
}
pub fn model_749_context() u32 {
    return models[49].context_window;
}
pub fn model_749_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_749_family() []const u8 {
    return models[49].family;
}
pub fn model_749_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_750_id() []const u8 {
    return models[50].id;
}
pub fn model_750_context() u32 {
    return models[50].context_window;
}
pub fn model_750_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_750_family() []const u8 {
    return models[50].family;
}
pub fn model_750_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_751_id() []const u8 {
    return models[51].id;
}
pub fn model_751_context() u32 {
    return models[51].context_window;
}
pub fn model_751_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_751_family() []const u8 {
    return models[51].family;
}
pub fn model_751_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_752_id() []const u8 {
    return models[52].id;
}
pub fn model_752_context() u32 {
    return models[52].context_window;
}
pub fn model_752_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_752_family() []const u8 {
    return models[52].family;
}
pub fn model_752_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_753_id() []const u8 {
    return models[53].id;
}
pub fn model_753_context() u32 {
    return models[53].context_window;
}
pub fn model_753_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_753_family() []const u8 {
    return models[53].family;
}
pub fn model_753_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_754_id() []const u8 {
    return models[54].id;
}
pub fn model_754_context() u32 {
    return models[54].context_window;
}
pub fn model_754_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_754_family() []const u8 {
    return models[54].family;
}
pub fn model_754_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_755_id() []const u8 {
    return models[55].id;
}
pub fn model_755_context() u32 {
    return models[55].context_window;
}
pub fn model_755_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_755_family() []const u8 {
    return models[55].family;
}
pub fn model_755_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_756_id() []const u8 {
    return models[56].id;
}
pub fn model_756_context() u32 {
    return models[56].context_window;
}
pub fn model_756_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_756_family() []const u8 {
    return models[56].family;
}
pub fn model_756_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_757_id() []const u8 {
    return models[57].id;
}
pub fn model_757_context() u32 {
    return models[57].context_window;
}
pub fn model_757_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_757_family() []const u8 {
    return models[57].family;
}
pub fn model_757_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_758_id() []const u8 {
    return models[58].id;
}
pub fn model_758_context() u32 {
    return models[58].context_window;
}
pub fn model_758_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_758_family() []const u8 {
    return models[58].family;
}
pub fn model_758_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_759_id() []const u8 {
    return models[59].id;
}
pub fn model_759_context() u32 {
    return models[59].context_window;
}
pub fn model_759_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_759_family() []const u8 {
    return models[59].family;
}
pub fn model_759_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_760_id() []const u8 {
    return models[60].id;
}
pub fn model_760_context() u32 {
    return models[60].context_window;
}
pub fn model_760_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_760_family() []const u8 {
    return models[60].family;
}
pub fn model_760_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_761_id() []const u8 {
    return models[61].id;
}
pub fn model_761_context() u32 {
    return models[61].context_window;
}
pub fn model_761_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_761_family() []const u8 {
    return models[61].family;
}
pub fn model_761_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_762_id() []const u8 {
    return models[62].id;
}
pub fn model_762_context() u32 {
    return models[62].context_window;
}
pub fn model_762_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_762_family() []const u8 {
    return models[62].family;
}
pub fn model_762_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_763_id() []const u8 {
    return models[63].id;
}
pub fn model_763_context() u32 {
    return models[63].context_window;
}
pub fn model_763_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_763_family() []const u8 {
    return models[63].family;
}
pub fn model_763_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_764_id() []const u8 {
    return models[64].id;
}
pub fn model_764_context() u32 {
    return models[64].context_window;
}
pub fn model_764_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_764_family() []const u8 {
    return models[64].family;
}
pub fn model_764_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_765_id() []const u8 {
    return models[65].id;
}
pub fn model_765_context() u32 {
    return models[65].context_window;
}
pub fn model_765_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_765_family() []const u8 {
    return models[65].family;
}
pub fn model_765_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_766_id() []const u8 {
    return models[66].id;
}
pub fn model_766_context() u32 {
    return models[66].context_window;
}
pub fn model_766_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_766_family() []const u8 {
    return models[66].family;
}
pub fn model_766_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_767_id() []const u8 {
    return models[67].id;
}
pub fn model_767_context() u32 {
    return models[67].context_window;
}
pub fn model_767_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_767_family() []const u8 {
    return models[67].family;
}
pub fn model_767_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_768_id() []const u8 {
    return models[68].id;
}
pub fn model_768_context() u32 {
    return models[68].context_window;
}
pub fn model_768_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_768_family() []const u8 {
    return models[68].family;
}
pub fn model_768_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_769_id() []const u8 {
    return models[69].id;
}
pub fn model_769_context() u32 {
    return models[69].context_window;
}
pub fn model_769_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_769_family() []const u8 {
    return models[69].family;
}
pub fn model_769_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_770_id() []const u8 {
    return models[70].id;
}
pub fn model_770_context() u32 {
    return models[70].context_window;
}
pub fn model_770_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_770_family() []const u8 {
    return models[70].family;
}
pub fn model_770_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_771_id() []const u8 {
    return models[71].id;
}
pub fn model_771_context() u32 {
    return models[71].context_window;
}
pub fn model_771_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_771_family() []const u8 {
    return models[71].family;
}
pub fn model_771_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_772_id() []const u8 {
    return models[72].id;
}
pub fn model_772_context() u32 {
    return models[72].context_window;
}
pub fn model_772_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_772_family() []const u8 {
    return models[72].family;
}
pub fn model_772_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_773_id() []const u8 {
    return models[73].id;
}
pub fn model_773_context() u32 {
    return models[73].context_window;
}
pub fn model_773_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_773_family() []const u8 {
    return models[73].family;
}
pub fn model_773_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_774_id() []const u8 {
    return models[74].id;
}
pub fn model_774_context() u32 {
    return models[74].context_window;
}
pub fn model_774_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_774_family() []const u8 {
    return models[74].family;
}
pub fn model_774_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_775_id() []const u8 {
    return models[75].id;
}
pub fn model_775_context() u32 {
    return models[75].context_window;
}
pub fn model_775_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_775_family() []const u8 {
    return models[75].family;
}
pub fn model_775_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_776_id() []const u8 {
    return models[76].id;
}
pub fn model_776_context() u32 {
    return models[76].context_window;
}
pub fn model_776_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_776_family() []const u8 {
    return models[76].family;
}
pub fn model_776_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_777_id() []const u8 {
    return models[77].id;
}
pub fn model_777_context() u32 {
    return models[77].context_window;
}
pub fn model_777_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_777_family() []const u8 {
    return models[77].family;
}
pub fn model_777_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_778_id() []const u8 {
    return models[78].id;
}
pub fn model_778_context() u32 {
    return models[78].context_window;
}
pub fn model_778_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_778_family() []const u8 {
    return models[78].family;
}
pub fn model_778_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_779_id() []const u8 {
    return models[79].id;
}
pub fn model_779_context() u32 {
    return models[79].context_window;
}
pub fn model_779_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_779_family() []const u8 {
    return models[79].family;
}
pub fn model_779_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 7 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

