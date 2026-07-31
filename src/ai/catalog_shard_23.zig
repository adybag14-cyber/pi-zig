//! Generated model catalog shard 23 for package ai.
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

pub const shard_index: u32 = 23;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-2300", .provider = "sambanova", .display = "Sambanova Chat 2300", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2301", .provider = "github", .display = "Github Code 2301", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2302", .provider = "huggingface", .display = "Huggingface Reason 2302", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2303", .provider = "replicate", .display = "Replicate Vision 2303", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "anyscale/embed-2304", .provider = "anyscale", .display = "Anyscale Embed 2304", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2305", .provider = "databricks", .display = "Databricks Audio 2305", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2306", .provider = "moonshot", .display = "Moonshot Fast 2306", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2307", .provider = "qwen", .display = "Qwen Large 2307", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2308", .provider = "minimax", .display = "Minimax Mini 2308", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2309", .provider = "zhipu", .display = "Zhipu Nano 2309", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2310", .provider = "baichuan", .display = "Baichuan Pro 2310", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "yi/ultra-2311", .provider = "yi", .display = "Yi Ultra 2311", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2312", .provider = "siliconflow", .display = "Siliconflow Turbo 2312", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2313", .provider = "novita", .display = "Novita Instruct 2313", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2314", .provider = "lepton", .display = "Lepton Base 2314", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2315", .provider = "deepinfra", .display = "Deepinfra Preview 2315", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2316", .provider = "friendli", .display = "Friendli Experimental 2316", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2317", .provider = "hyperbolic", .display = "Hyperbolic Stable 2317", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "lambda/legacy-2318", .provider = "lambda", .display = "Lambda Legacy 2318", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2319", .provider = "nebius", .display = "Nebius Edge 2319", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-2320", .provider = "openai", .display = "Openai Chat 2320", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2321", .provider = "anthropic", .display = "Anthropic Code 2321", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2322", .provider = "google", .display = "Google Reason 2322", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2323", .provider = "groq", .display = "Groq Vision 2323", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2324", .provider = "xai", .display = "Xai Embed 2324", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "deepseek/audio-2325", .provider = "deepseek", .display = "Deepseek Audio 2325", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2326", .provider = "mistral", .display = "Mistral Fast 2326", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-2327", .provider = "together", .display = "Together Large 2327", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2328", .provider = "fireworks", .display = "Fireworks Mini 2328", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2329", .provider = "openrouter", .display = "Openrouter Nano 2329", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2330", .provider = "cerebras", .display = "Cerebras Pro 2330", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2331", .provider = "ollama", .display = "Ollama Ultra 2331", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2332", .provider = "lmstudio", .display = "Lmstudio Turbo 2332", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2333", .provider = "vllm", .display = "Vllm Instruct 2333", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-2334", .provider = "azure", .display = "Azure Base 2334", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2335", .provider = "bedrock", .display = "Bedrock Preview 2335", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2336", .provider = "vertex", .display = "Vertex Experimental 2336", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2337", .provider = "perplexity", .display = "Perplexity Stable 2337", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2338", .provider = "cohere", .display = "Cohere Legacy 2338", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nvidia/edge-2339", .provider = "nvidia", .display = "Nvidia Edge 2339", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2340", .provider = "sambanova", .display = "Sambanova Chat 2340", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-2341", .provider = "github", .display = "Github Code 2341", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2342", .provider = "huggingface", .display = "Huggingface Reason 2342", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2343", .provider = "replicate", .display = "Replicate Vision 2343", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2344", .provider = "anyscale", .display = "Anyscale Embed 2344", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2345", .provider = "databricks", .display = "Databricks Audio 2345", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-2346", .provider = "moonshot", .display = "Moonshot Fast 2346", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2347", .provider = "qwen", .display = "Qwen Large 2347", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-2348", .provider = "minimax", .display = "Minimax Mini 2348", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2349", .provider = "zhipu", .display = "Zhipu Nano 2349", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2350", .provider = "baichuan", .display = "Baichuan Pro 2350", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2351", .provider = "yi", .display = "Yi Ultra 2351", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2352", .provider = "siliconflow", .display = "Siliconflow Turbo 2352", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-2353", .provider = "novita", .display = "Novita Instruct 2353", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2354", .provider = "lepton", .display = "Lepton Base 2354", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-2355", .provider = "deepinfra", .display = "Deepinfra Preview 2355", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2356", .provider = "friendli", .display = "Friendli Experimental 2356", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2357", .provider = "hyperbolic", .display = "Hyperbolic Stable 2357", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2358", .provider = "lambda", .display = "Lambda Legacy 2358", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2359", .provider = "nebius", .display = "Nebius Edge 2359", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-2360", .provider = "openai", .display = "Openai Chat 2360", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-2361", .provider = "anthropic", .display = "Anthropic Code 2361", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-2362", .provider = "google", .display = "Google Reason 2362", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-2363", .provider = "groq", .display = "Groq Vision 2363", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-2364", .provider = "xai", .display = "Xai Embed 2364", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-2365", .provider = "deepseek", .display = "Deepseek Audio 2365", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-2366", .provider = "mistral", .display = "Mistral Fast 2366", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-2367", .provider = "together", .display = "Together Large 2367", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-2368", .provider = "fireworks", .display = "Fireworks Mini 2368", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-2369", .provider = "openrouter", .display = "Openrouter Nano 2369", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-2370", .provider = "cerebras", .display = "Cerebras Pro 2370", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-2371", .provider = "ollama", .display = "Ollama Ultra 2371", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-2372", .provider = "lmstudio", .display = "Lmstudio Turbo 2372", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-2373", .provider = "vllm", .display = "Vllm Instruct 2373", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-2374", .provider = "azure", .display = "Azure Base 2374", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-2375", .provider = "bedrock", .display = "Bedrock Preview 2375", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-2376", .provider = "vertex", .display = "Vertex Experimental 2376", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-2377", .provider = "perplexity", .display = "Perplexity Stable 2377", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-2378", .provider = "cohere", .display = "Cohere Legacy 2378", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-2379", .provider = "nvidia", .display = "Nvidia Edge 2379", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-2380", .provider = "sambanova", .display = "Sambanova Chat 2380", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-2381", .provider = "github", .display = "Github Code 2381", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-2382", .provider = "huggingface", .display = "Huggingface Reason 2382", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-2383", .provider = "replicate", .display = "Replicate Vision 2383", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-2384", .provider = "anyscale", .display = "Anyscale Embed 2384", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-2385", .provider = "databricks", .display = "Databricks Audio 2385", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-2386", .provider = "moonshot", .display = "Moonshot Fast 2386", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-2387", .provider = "qwen", .display = "Qwen Large 2387", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-2388", .provider = "minimax", .display = "Minimax Mini 2388", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-2389", .provider = "zhipu", .display = "Zhipu Nano 2389", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-2390", .provider = "baichuan", .display = "Baichuan Pro 2390", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-2391", .provider = "yi", .display = "Yi Ultra 2391", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-2392", .provider = "siliconflow", .display = "Siliconflow Turbo 2392", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-2393", .provider = "novita", .display = "Novita Instruct 2393", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-2394", .provider = "lepton", .display = "Lepton Base 2394", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-2395", .provider = "deepinfra", .display = "Deepinfra Preview 2395", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-2396", .provider = "friendli", .display = "Friendli Experimental 2396", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-2397", .provider = "hyperbolic", .display = "Hyperbolic Stable 2397", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-2398", .provider = "lambda", .display = "Lambda Legacy 2398", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-2399", .provider = "nebius", .display = "Nebius Edge 2399", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_2300_id() []const u8 {
    return models[0].id;
}
pub fn model_2300_context() u32 {
    return models[0].context_window;
}
pub fn model_2300_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_2300_family() []const u8 {
    return models[0].family;
}
pub fn model_2300_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_2301_id() []const u8 {
    return models[1].id;
}
pub fn model_2301_context() u32 {
    return models[1].context_window;
}
pub fn model_2301_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_2301_family() []const u8 {
    return models[1].family;
}
pub fn model_2301_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_2302_id() []const u8 {
    return models[2].id;
}
pub fn model_2302_context() u32 {
    return models[2].context_window;
}
pub fn model_2302_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_2302_family() []const u8 {
    return models[2].family;
}
pub fn model_2302_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_2303_id() []const u8 {
    return models[3].id;
}
pub fn model_2303_context() u32 {
    return models[3].context_window;
}
pub fn model_2303_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_2303_family() []const u8 {
    return models[3].family;
}
pub fn model_2303_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_2304_id() []const u8 {
    return models[4].id;
}
pub fn model_2304_context() u32 {
    return models[4].context_window;
}
pub fn model_2304_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_2304_family() []const u8 {
    return models[4].family;
}
pub fn model_2304_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_2305_id() []const u8 {
    return models[5].id;
}
pub fn model_2305_context() u32 {
    return models[5].context_window;
}
pub fn model_2305_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_2305_family() []const u8 {
    return models[5].family;
}
pub fn model_2305_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_2306_id() []const u8 {
    return models[6].id;
}
pub fn model_2306_context() u32 {
    return models[6].context_window;
}
pub fn model_2306_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_2306_family() []const u8 {
    return models[6].family;
}
pub fn model_2306_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_2307_id() []const u8 {
    return models[7].id;
}
pub fn model_2307_context() u32 {
    return models[7].context_window;
}
pub fn model_2307_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_2307_family() []const u8 {
    return models[7].family;
}
pub fn model_2307_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_2308_id() []const u8 {
    return models[8].id;
}
pub fn model_2308_context() u32 {
    return models[8].context_window;
}
pub fn model_2308_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_2308_family() []const u8 {
    return models[8].family;
}
pub fn model_2308_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_2309_id() []const u8 {
    return models[9].id;
}
pub fn model_2309_context() u32 {
    return models[9].context_window;
}
pub fn model_2309_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_2309_family() []const u8 {
    return models[9].family;
}
pub fn model_2309_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_2310_id() []const u8 {
    return models[10].id;
}
pub fn model_2310_context() u32 {
    return models[10].context_window;
}
pub fn model_2310_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_2310_family() []const u8 {
    return models[10].family;
}
pub fn model_2310_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_2311_id() []const u8 {
    return models[11].id;
}
pub fn model_2311_context() u32 {
    return models[11].context_window;
}
pub fn model_2311_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_2311_family() []const u8 {
    return models[11].family;
}
pub fn model_2311_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_2312_id() []const u8 {
    return models[12].id;
}
pub fn model_2312_context() u32 {
    return models[12].context_window;
}
pub fn model_2312_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_2312_family() []const u8 {
    return models[12].family;
}
pub fn model_2312_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_2313_id() []const u8 {
    return models[13].id;
}
pub fn model_2313_context() u32 {
    return models[13].context_window;
}
pub fn model_2313_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_2313_family() []const u8 {
    return models[13].family;
}
pub fn model_2313_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_2314_id() []const u8 {
    return models[14].id;
}
pub fn model_2314_context() u32 {
    return models[14].context_window;
}
pub fn model_2314_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_2314_family() []const u8 {
    return models[14].family;
}
pub fn model_2314_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_2315_id() []const u8 {
    return models[15].id;
}
pub fn model_2315_context() u32 {
    return models[15].context_window;
}
pub fn model_2315_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_2315_family() []const u8 {
    return models[15].family;
}
pub fn model_2315_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_2316_id() []const u8 {
    return models[16].id;
}
pub fn model_2316_context() u32 {
    return models[16].context_window;
}
pub fn model_2316_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_2316_family() []const u8 {
    return models[16].family;
}
pub fn model_2316_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_2317_id() []const u8 {
    return models[17].id;
}
pub fn model_2317_context() u32 {
    return models[17].context_window;
}
pub fn model_2317_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_2317_family() []const u8 {
    return models[17].family;
}
pub fn model_2317_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_2318_id() []const u8 {
    return models[18].id;
}
pub fn model_2318_context() u32 {
    return models[18].context_window;
}
pub fn model_2318_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_2318_family() []const u8 {
    return models[18].family;
}
pub fn model_2318_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_2319_id() []const u8 {
    return models[19].id;
}
pub fn model_2319_context() u32 {
    return models[19].context_window;
}
pub fn model_2319_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_2319_family() []const u8 {
    return models[19].family;
}
pub fn model_2319_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_2320_id() []const u8 {
    return models[20].id;
}
pub fn model_2320_context() u32 {
    return models[20].context_window;
}
pub fn model_2320_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_2320_family() []const u8 {
    return models[20].family;
}
pub fn model_2320_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_2321_id() []const u8 {
    return models[21].id;
}
pub fn model_2321_context() u32 {
    return models[21].context_window;
}
pub fn model_2321_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_2321_family() []const u8 {
    return models[21].family;
}
pub fn model_2321_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_2322_id() []const u8 {
    return models[22].id;
}
pub fn model_2322_context() u32 {
    return models[22].context_window;
}
pub fn model_2322_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_2322_family() []const u8 {
    return models[22].family;
}
pub fn model_2322_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_2323_id() []const u8 {
    return models[23].id;
}
pub fn model_2323_context() u32 {
    return models[23].context_window;
}
pub fn model_2323_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_2323_family() []const u8 {
    return models[23].family;
}
pub fn model_2323_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_2324_id() []const u8 {
    return models[24].id;
}
pub fn model_2324_context() u32 {
    return models[24].context_window;
}
pub fn model_2324_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_2324_family() []const u8 {
    return models[24].family;
}
pub fn model_2324_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_2325_id() []const u8 {
    return models[25].id;
}
pub fn model_2325_context() u32 {
    return models[25].context_window;
}
pub fn model_2325_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_2325_family() []const u8 {
    return models[25].family;
}
pub fn model_2325_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_2326_id() []const u8 {
    return models[26].id;
}
pub fn model_2326_context() u32 {
    return models[26].context_window;
}
pub fn model_2326_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_2326_family() []const u8 {
    return models[26].family;
}
pub fn model_2326_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_2327_id() []const u8 {
    return models[27].id;
}
pub fn model_2327_context() u32 {
    return models[27].context_window;
}
pub fn model_2327_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_2327_family() []const u8 {
    return models[27].family;
}
pub fn model_2327_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_2328_id() []const u8 {
    return models[28].id;
}
pub fn model_2328_context() u32 {
    return models[28].context_window;
}
pub fn model_2328_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_2328_family() []const u8 {
    return models[28].family;
}
pub fn model_2328_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_2329_id() []const u8 {
    return models[29].id;
}
pub fn model_2329_context() u32 {
    return models[29].context_window;
}
pub fn model_2329_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_2329_family() []const u8 {
    return models[29].family;
}
pub fn model_2329_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_2330_id() []const u8 {
    return models[30].id;
}
pub fn model_2330_context() u32 {
    return models[30].context_window;
}
pub fn model_2330_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_2330_family() []const u8 {
    return models[30].family;
}
pub fn model_2330_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_2331_id() []const u8 {
    return models[31].id;
}
pub fn model_2331_context() u32 {
    return models[31].context_window;
}
pub fn model_2331_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_2331_family() []const u8 {
    return models[31].family;
}
pub fn model_2331_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_2332_id() []const u8 {
    return models[32].id;
}
pub fn model_2332_context() u32 {
    return models[32].context_window;
}
pub fn model_2332_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_2332_family() []const u8 {
    return models[32].family;
}
pub fn model_2332_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_2333_id() []const u8 {
    return models[33].id;
}
pub fn model_2333_context() u32 {
    return models[33].context_window;
}
pub fn model_2333_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_2333_family() []const u8 {
    return models[33].family;
}
pub fn model_2333_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_2334_id() []const u8 {
    return models[34].id;
}
pub fn model_2334_context() u32 {
    return models[34].context_window;
}
pub fn model_2334_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_2334_family() []const u8 {
    return models[34].family;
}
pub fn model_2334_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_2335_id() []const u8 {
    return models[35].id;
}
pub fn model_2335_context() u32 {
    return models[35].context_window;
}
pub fn model_2335_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_2335_family() []const u8 {
    return models[35].family;
}
pub fn model_2335_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_2336_id() []const u8 {
    return models[36].id;
}
pub fn model_2336_context() u32 {
    return models[36].context_window;
}
pub fn model_2336_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_2336_family() []const u8 {
    return models[36].family;
}
pub fn model_2336_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_2337_id() []const u8 {
    return models[37].id;
}
pub fn model_2337_context() u32 {
    return models[37].context_window;
}
pub fn model_2337_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_2337_family() []const u8 {
    return models[37].family;
}
pub fn model_2337_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_2338_id() []const u8 {
    return models[38].id;
}
pub fn model_2338_context() u32 {
    return models[38].context_window;
}
pub fn model_2338_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_2338_family() []const u8 {
    return models[38].family;
}
pub fn model_2338_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_2339_id() []const u8 {
    return models[39].id;
}
pub fn model_2339_context() u32 {
    return models[39].context_window;
}
pub fn model_2339_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_2339_family() []const u8 {
    return models[39].family;
}
pub fn model_2339_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_2340_id() []const u8 {
    return models[40].id;
}
pub fn model_2340_context() u32 {
    return models[40].context_window;
}
pub fn model_2340_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_2340_family() []const u8 {
    return models[40].family;
}
pub fn model_2340_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_2341_id() []const u8 {
    return models[41].id;
}
pub fn model_2341_context() u32 {
    return models[41].context_window;
}
pub fn model_2341_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_2341_family() []const u8 {
    return models[41].family;
}
pub fn model_2341_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_2342_id() []const u8 {
    return models[42].id;
}
pub fn model_2342_context() u32 {
    return models[42].context_window;
}
pub fn model_2342_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_2342_family() []const u8 {
    return models[42].family;
}
pub fn model_2342_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_2343_id() []const u8 {
    return models[43].id;
}
pub fn model_2343_context() u32 {
    return models[43].context_window;
}
pub fn model_2343_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_2343_family() []const u8 {
    return models[43].family;
}
pub fn model_2343_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_2344_id() []const u8 {
    return models[44].id;
}
pub fn model_2344_context() u32 {
    return models[44].context_window;
}
pub fn model_2344_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_2344_family() []const u8 {
    return models[44].family;
}
pub fn model_2344_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_2345_id() []const u8 {
    return models[45].id;
}
pub fn model_2345_context() u32 {
    return models[45].context_window;
}
pub fn model_2345_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_2345_family() []const u8 {
    return models[45].family;
}
pub fn model_2345_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_2346_id() []const u8 {
    return models[46].id;
}
pub fn model_2346_context() u32 {
    return models[46].context_window;
}
pub fn model_2346_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_2346_family() []const u8 {
    return models[46].family;
}
pub fn model_2346_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_2347_id() []const u8 {
    return models[47].id;
}
pub fn model_2347_context() u32 {
    return models[47].context_window;
}
pub fn model_2347_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_2347_family() []const u8 {
    return models[47].family;
}
pub fn model_2347_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_2348_id() []const u8 {
    return models[48].id;
}
pub fn model_2348_context() u32 {
    return models[48].context_window;
}
pub fn model_2348_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_2348_family() []const u8 {
    return models[48].family;
}
pub fn model_2348_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_2349_id() []const u8 {
    return models[49].id;
}
pub fn model_2349_context() u32 {
    return models[49].context_window;
}
pub fn model_2349_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_2349_family() []const u8 {
    return models[49].family;
}
pub fn model_2349_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_2350_id() []const u8 {
    return models[50].id;
}
pub fn model_2350_context() u32 {
    return models[50].context_window;
}
pub fn model_2350_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_2350_family() []const u8 {
    return models[50].family;
}
pub fn model_2350_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_2351_id() []const u8 {
    return models[51].id;
}
pub fn model_2351_context() u32 {
    return models[51].context_window;
}
pub fn model_2351_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_2351_family() []const u8 {
    return models[51].family;
}
pub fn model_2351_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_2352_id() []const u8 {
    return models[52].id;
}
pub fn model_2352_context() u32 {
    return models[52].context_window;
}
pub fn model_2352_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_2352_family() []const u8 {
    return models[52].family;
}
pub fn model_2352_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_2353_id() []const u8 {
    return models[53].id;
}
pub fn model_2353_context() u32 {
    return models[53].context_window;
}
pub fn model_2353_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_2353_family() []const u8 {
    return models[53].family;
}
pub fn model_2353_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_2354_id() []const u8 {
    return models[54].id;
}
pub fn model_2354_context() u32 {
    return models[54].context_window;
}
pub fn model_2354_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_2354_family() []const u8 {
    return models[54].family;
}
pub fn model_2354_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_2355_id() []const u8 {
    return models[55].id;
}
pub fn model_2355_context() u32 {
    return models[55].context_window;
}
pub fn model_2355_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_2355_family() []const u8 {
    return models[55].family;
}
pub fn model_2355_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_2356_id() []const u8 {
    return models[56].id;
}
pub fn model_2356_context() u32 {
    return models[56].context_window;
}
pub fn model_2356_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_2356_family() []const u8 {
    return models[56].family;
}
pub fn model_2356_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_2357_id() []const u8 {
    return models[57].id;
}
pub fn model_2357_context() u32 {
    return models[57].context_window;
}
pub fn model_2357_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_2357_family() []const u8 {
    return models[57].family;
}
pub fn model_2357_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_2358_id() []const u8 {
    return models[58].id;
}
pub fn model_2358_context() u32 {
    return models[58].context_window;
}
pub fn model_2358_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_2358_family() []const u8 {
    return models[58].family;
}
pub fn model_2358_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_2359_id() []const u8 {
    return models[59].id;
}
pub fn model_2359_context() u32 {
    return models[59].context_window;
}
pub fn model_2359_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_2359_family() []const u8 {
    return models[59].family;
}
pub fn model_2359_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_2360_id() []const u8 {
    return models[60].id;
}
pub fn model_2360_context() u32 {
    return models[60].context_window;
}
pub fn model_2360_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_2360_family() []const u8 {
    return models[60].family;
}
pub fn model_2360_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_2361_id() []const u8 {
    return models[61].id;
}
pub fn model_2361_context() u32 {
    return models[61].context_window;
}
pub fn model_2361_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_2361_family() []const u8 {
    return models[61].family;
}
pub fn model_2361_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_2362_id() []const u8 {
    return models[62].id;
}
pub fn model_2362_context() u32 {
    return models[62].context_window;
}
pub fn model_2362_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_2362_family() []const u8 {
    return models[62].family;
}
pub fn model_2362_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_2363_id() []const u8 {
    return models[63].id;
}
pub fn model_2363_context() u32 {
    return models[63].context_window;
}
pub fn model_2363_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_2363_family() []const u8 {
    return models[63].family;
}
pub fn model_2363_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_2364_id() []const u8 {
    return models[64].id;
}
pub fn model_2364_context() u32 {
    return models[64].context_window;
}
pub fn model_2364_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_2364_family() []const u8 {
    return models[64].family;
}
pub fn model_2364_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_2365_id() []const u8 {
    return models[65].id;
}
pub fn model_2365_context() u32 {
    return models[65].context_window;
}
pub fn model_2365_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_2365_family() []const u8 {
    return models[65].family;
}
pub fn model_2365_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_2366_id() []const u8 {
    return models[66].id;
}
pub fn model_2366_context() u32 {
    return models[66].context_window;
}
pub fn model_2366_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_2366_family() []const u8 {
    return models[66].family;
}
pub fn model_2366_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_2367_id() []const u8 {
    return models[67].id;
}
pub fn model_2367_context() u32 {
    return models[67].context_window;
}
pub fn model_2367_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_2367_family() []const u8 {
    return models[67].family;
}
pub fn model_2367_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_2368_id() []const u8 {
    return models[68].id;
}
pub fn model_2368_context() u32 {
    return models[68].context_window;
}
pub fn model_2368_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_2368_family() []const u8 {
    return models[68].family;
}
pub fn model_2368_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_2369_id() []const u8 {
    return models[69].id;
}
pub fn model_2369_context() u32 {
    return models[69].context_window;
}
pub fn model_2369_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_2369_family() []const u8 {
    return models[69].family;
}
pub fn model_2369_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_2370_id() []const u8 {
    return models[70].id;
}
pub fn model_2370_context() u32 {
    return models[70].context_window;
}
pub fn model_2370_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_2370_family() []const u8 {
    return models[70].family;
}
pub fn model_2370_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_2371_id() []const u8 {
    return models[71].id;
}
pub fn model_2371_context() u32 {
    return models[71].context_window;
}
pub fn model_2371_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_2371_family() []const u8 {
    return models[71].family;
}
pub fn model_2371_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_2372_id() []const u8 {
    return models[72].id;
}
pub fn model_2372_context() u32 {
    return models[72].context_window;
}
pub fn model_2372_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_2372_family() []const u8 {
    return models[72].family;
}
pub fn model_2372_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_2373_id() []const u8 {
    return models[73].id;
}
pub fn model_2373_context() u32 {
    return models[73].context_window;
}
pub fn model_2373_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_2373_family() []const u8 {
    return models[73].family;
}
pub fn model_2373_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_2374_id() []const u8 {
    return models[74].id;
}
pub fn model_2374_context() u32 {
    return models[74].context_window;
}
pub fn model_2374_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_2374_family() []const u8 {
    return models[74].family;
}
pub fn model_2374_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_2375_id() []const u8 {
    return models[75].id;
}
pub fn model_2375_context() u32 {
    return models[75].context_window;
}
pub fn model_2375_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_2375_family() []const u8 {
    return models[75].family;
}
pub fn model_2375_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_2376_id() []const u8 {
    return models[76].id;
}
pub fn model_2376_context() u32 {
    return models[76].context_window;
}
pub fn model_2376_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_2376_family() []const u8 {
    return models[76].family;
}
pub fn model_2376_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_2377_id() []const u8 {
    return models[77].id;
}
pub fn model_2377_context() u32 {
    return models[77].context_window;
}
pub fn model_2377_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_2377_family() []const u8 {
    return models[77].family;
}
pub fn model_2377_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_2378_id() []const u8 {
    return models[78].id;
}
pub fn model_2378_context() u32 {
    return models[78].context_window;
}
pub fn model_2378_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_2378_family() []const u8 {
    return models[78].family;
}
pub fn model_2378_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_2379_id() []const u8 {
    return models[79].id;
}
pub fn model_2379_context() u32 {
    return models[79].context_window;
}
pub fn model_2379_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_2379_family() []const u8 {
    return models[79].family;
}
pub fn model_2379_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 23 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

