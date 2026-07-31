//! Generated model catalog shard 1 for package ai.
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

pub const shard_index: u32 = 1;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-100", .provider = "sambanova", .display = "Sambanova Chat 100", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-101", .provider = "github", .display = "Github Code 101", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-102", .provider = "huggingface", .display = "Huggingface Reason 102", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-103", .provider = "replicate", .display = "Replicate Vision 103", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-104", .provider = "anyscale", .display = "Anyscale Embed 104", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-105", .provider = "databricks", .display = "Databricks Audio 105", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "moonshot/fast-106", .provider = "moonshot", .display = "Moonshot Fast 106", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-107", .provider = "qwen", .display = "Qwen Large 107", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-108", .provider = "minimax", .display = "Minimax Mini 108", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-109", .provider = "zhipu", .display = "Zhipu Nano 109", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-110", .provider = "baichuan", .display = "Baichuan Pro 110", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-111", .provider = "yi", .display = "Yi Ultra 111", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-112", .provider = "siliconflow", .display = "Siliconflow Turbo 112", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "novita/instruct-113", .provider = "novita", .display = "Novita Instruct 113", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-114", .provider = "lepton", .display = "Lepton Base 114", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-115", .provider = "deepinfra", .display = "Deepinfra Preview 115", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-116", .provider = "friendli", .display = "Friendli Experimental 116", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-117", .provider = "hyperbolic", .display = "Hyperbolic Stable 117", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-118", .provider = "lambda", .display = "Lambda Legacy 118", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-119", .provider = "nebius", .display = "Nebius Edge 119", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "openai/chat-120", .provider = "openai", .display = "Openai Chat 120", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-121", .provider = "anthropic", .display = "Anthropic Code 121", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-122", .provider = "google", .display = "Google Reason 122", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-123", .provider = "groq", .display = "Groq Vision 123", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-124", .provider = "xai", .display = "Xai Embed 124", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-125", .provider = "deepseek", .display = "Deepseek Audio 125", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-126", .provider = "mistral", .display = "Mistral Fast 126", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-127", .provider = "together", .display = "Together Large 127", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-128", .provider = "fireworks", .display = "Fireworks Mini 128", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-129", .provider = "openrouter", .display = "Openrouter Nano 129", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-130", .provider = "cerebras", .display = "Cerebras Pro 130", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-131", .provider = "ollama", .display = "Ollama Ultra 131", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-132", .provider = "lmstudio", .display = "Lmstudio Turbo 132", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-133", .provider = "vllm", .display = "Vllm Instruct 133", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-134", .provider = "azure", .display = "Azure Base 134", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-135", .provider = "bedrock", .display = "Bedrock Preview 135", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-136", .provider = "vertex", .display = "Vertex Experimental 136", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-137", .provider = "perplexity", .display = "Perplexity Stable 137", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-138", .provider = "cohere", .display = "Cohere Legacy 138", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-139", .provider = "nvidia", .display = "Nvidia Edge 139", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-140", .provider = "sambanova", .display = "Sambanova Chat 140", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-141", .provider = "github", .display = "Github Code 141", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-142", .provider = "huggingface", .display = "Huggingface Reason 142", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-143", .provider = "replicate", .display = "Replicate Vision 143", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-144", .provider = "anyscale", .display = "Anyscale Embed 144", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-145", .provider = "databricks", .display = "Databricks Audio 145", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-146", .provider = "moonshot", .display = "Moonshot Fast 146", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-147", .provider = "qwen", .display = "Qwen Large 147", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-148", .provider = "minimax", .display = "Minimax Mini 148", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-149", .provider = "zhipu", .display = "Zhipu Nano 149", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-150", .provider = "baichuan", .display = "Baichuan Pro 150", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-151", .provider = "yi", .display = "Yi Ultra 151", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-152", .provider = "siliconflow", .display = "Siliconflow Turbo 152", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-153", .provider = "novita", .display = "Novita Instruct 153", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-154", .provider = "lepton", .display = "Lepton Base 154", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-155", .provider = "deepinfra", .display = "Deepinfra Preview 155", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-156", .provider = "friendli", .display = "Friendli Experimental 156", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-157", .provider = "hyperbolic", .display = "Hyperbolic Stable 157", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-158", .provider = "lambda", .display = "Lambda Legacy 158", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-159", .provider = "nebius", .display = "Nebius Edge 159", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-160", .provider = "openai", .display = "Openai Chat 160", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-161", .provider = "anthropic", .display = "Anthropic Code 161", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-162", .provider = "google", .display = "Google Reason 162", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-163", .provider = "groq", .display = "Groq Vision 163", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-164", .provider = "xai", .display = "Xai Embed 164", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-165", .provider = "deepseek", .display = "Deepseek Audio 165", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-166", .provider = "mistral", .display = "Mistral Fast 166", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-167", .provider = "together", .display = "Together Large 167", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-168", .provider = "fireworks", .display = "Fireworks Mini 168", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-169", .provider = "openrouter", .display = "Openrouter Nano 169", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-170", .provider = "cerebras", .display = "Cerebras Pro 170", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-171", .provider = "ollama", .display = "Ollama Ultra 171", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-172", .provider = "lmstudio", .display = "Lmstudio Turbo 172", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-173", .provider = "vllm", .display = "Vllm Instruct 173", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-174", .provider = "azure", .display = "Azure Base 174", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-175", .provider = "bedrock", .display = "Bedrock Preview 175", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-176", .provider = "vertex", .display = "Vertex Experimental 176", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-177", .provider = "perplexity", .display = "Perplexity Stable 177", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-178", .provider = "cohere", .display = "Cohere Legacy 178", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-179", .provider = "nvidia", .display = "Nvidia Edge 179", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-180", .provider = "sambanova", .display = "Sambanova Chat 180", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-181", .provider = "github", .display = "Github Code 181", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-182", .provider = "huggingface", .display = "Huggingface Reason 182", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-183", .provider = "replicate", .display = "Replicate Vision 183", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-184", .provider = "anyscale", .display = "Anyscale Embed 184", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-185", .provider = "databricks", .display = "Databricks Audio 185", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-186", .provider = "moonshot", .display = "Moonshot Fast 186", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-187", .provider = "qwen", .display = "Qwen Large 187", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-188", .provider = "minimax", .display = "Minimax Mini 188", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-189", .provider = "zhipu", .display = "Zhipu Nano 189", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-190", .provider = "baichuan", .display = "Baichuan Pro 190", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-191", .provider = "yi", .display = "Yi Ultra 191", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-192", .provider = "siliconflow", .display = "Siliconflow Turbo 192", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-193", .provider = "novita", .display = "Novita Instruct 193", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-194", .provider = "lepton", .display = "Lepton Base 194", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-195", .provider = "deepinfra", .display = "Deepinfra Preview 195", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-196", .provider = "friendli", .display = "Friendli Experimental 196", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-197", .provider = "hyperbolic", .display = "Hyperbolic Stable 197", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-198", .provider = "lambda", .display = "Lambda Legacy 198", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-199", .provider = "nebius", .display = "Nebius Edge 199", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_100_id() []const u8 {
    return models[0].id;
}
pub fn model_100_context() u32 {
    return models[0].context_window;
}
pub fn model_100_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_100_family() []const u8 {
    return models[0].family;
}
pub fn model_100_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_101_id() []const u8 {
    return models[1].id;
}
pub fn model_101_context() u32 {
    return models[1].context_window;
}
pub fn model_101_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_101_family() []const u8 {
    return models[1].family;
}
pub fn model_101_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_102_id() []const u8 {
    return models[2].id;
}
pub fn model_102_context() u32 {
    return models[2].context_window;
}
pub fn model_102_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_102_family() []const u8 {
    return models[2].family;
}
pub fn model_102_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_103_id() []const u8 {
    return models[3].id;
}
pub fn model_103_context() u32 {
    return models[3].context_window;
}
pub fn model_103_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_103_family() []const u8 {
    return models[3].family;
}
pub fn model_103_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_104_id() []const u8 {
    return models[4].id;
}
pub fn model_104_context() u32 {
    return models[4].context_window;
}
pub fn model_104_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_104_family() []const u8 {
    return models[4].family;
}
pub fn model_104_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_105_id() []const u8 {
    return models[5].id;
}
pub fn model_105_context() u32 {
    return models[5].context_window;
}
pub fn model_105_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_105_family() []const u8 {
    return models[5].family;
}
pub fn model_105_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_106_id() []const u8 {
    return models[6].id;
}
pub fn model_106_context() u32 {
    return models[6].context_window;
}
pub fn model_106_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_106_family() []const u8 {
    return models[6].family;
}
pub fn model_106_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_107_id() []const u8 {
    return models[7].id;
}
pub fn model_107_context() u32 {
    return models[7].context_window;
}
pub fn model_107_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_107_family() []const u8 {
    return models[7].family;
}
pub fn model_107_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_108_id() []const u8 {
    return models[8].id;
}
pub fn model_108_context() u32 {
    return models[8].context_window;
}
pub fn model_108_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_108_family() []const u8 {
    return models[8].family;
}
pub fn model_108_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_109_id() []const u8 {
    return models[9].id;
}
pub fn model_109_context() u32 {
    return models[9].context_window;
}
pub fn model_109_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_109_family() []const u8 {
    return models[9].family;
}
pub fn model_109_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_110_id() []const u8 {
    return models[10].id;
}
pub fn model_110_context() u32 {
    return models[10].context_window;
}
pub fn model_110_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_110_family() []const u8 {
    return models[10].family;
}
pub fn model_110_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_111_id() []const u8 {
    return models[11].id;
}
pub fn model_111_context() u32 {
    return models[11].context_window;
}
pub fn model_111_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_111_family() []const u8 {
    return models[11].family;
}
pub fn model_111_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_112_id() []const u8 {
    return models[12].id;
}
pub fn model_112_context() u32 {
    return models[12].context_window;
}
pub fn model_112_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_112_family() []const u8 {
    return models[12].family;
}
pub fn model_112_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_113_id() []const u8 {
    return models[13].id;
}
pub fn model_113_context() u32 {
    return models[13].context_window;
}
pub fn model_113_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_113_family() []const u8 {
    return models[13].family;
}
pub fn model_113_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_114_id() []const u8 {
    return models[14].id;
}
pub fn model_114_context() u32 {
    return models[14].context_window;
}
pub fn model_114_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_114_family() []const u8 {
    return models[14].family;
}
pub fn model_114_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_115_id() []const u8 {
    return models[15].id;
}
pub fn model_115_context() u32 {
    return models[15].context_window;
}
pub fn model_115_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_115_family() []const u8 {
    return models[15].family;
}
pub fn model_115_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_116_id() []const u8 {
    return models[16].id;
}
pub fn model_116_context() u32 {
    return models[16].context_window;
}
pub fn model_116_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_116_family() []const u8 {
    return models[16].family;
}
pub fn model_116_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_117_id() []const u8 {
    return models[17].id;
}
pub fn model_117_context() u32 {
    return models[17].context_window;
}
pub fn model_117_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_117_family() []const u8 {
    return models[17].family;
}
pub fn model_117_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_118_id() []const u8 {
    return models[18].id;
}
pub fn model_118_context() u32 {
    return models[18].context_window;
}
pub fn model_118_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_118_family() []const u8 {
    return models[18].family;
}
pub fn model_118_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_119_id() []const u8 {
    return models[19].id;
}
pub fn model_119_context() u32 {
    return models[19].context_window;
}
pub fn model_119_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_119_family() []const u8 {
    return models[19].family;
}
pub fn model_119_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_120_id() []const u8 {
    return models[20].id;
}
pub fn model_120_context() u32 {
    return models[20].context_window;
}
pub fn model_120_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_120_family() []const u8 {
    return models[20].family;
}
pub fn model_120_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_121_id() []const u8 {
    return models[21].id;
}
pub fn model_121_context() u32 {
    return models[21].context_window;
}
pub fn model_121_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_121_family() []const u8 {
    return models[21].family;
}
pub fn model_121_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_122_id() []const u8 {
    return models[22].id;
}
pub fn model_122_context() u32 {
    return models[22].context_window;
}
pub fn model_122_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_122_family() []const u8 {
    return models[22].family;
}
pub fn model_122_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_123_id() []const u8 {
    return models[23].id;
}
pub fn model_123_context() u32 {
    return models[23].context_window;
}
pub fn model_123_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_123_family() []const u8 {
    return models[23].family;
}
pub fn model_123_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_124_id() []const u8 {
    return models[24].id;
}
pub fn model_124_context() u32 {
    return models[24].context_window;
}
pub fn model_124_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_124_family() []const u8 {
    return models[24].family;
}
pub fn model_124_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_125_id() []const u8 {
    return models[25].id;
}
pub fn model_125_context() u32 {
    return models[25].context_window;
}
pub fn model_125_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_125_family() []const u8 {
    return models[25].family;
}
pub fn model_125_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_126_id() []const u8 {
    return models[26].id;
}
pub fn model_126_context() u32 {
    return models[26].context_window;
}
pub fn model_126_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_126_family() []const u8 {
    return models[26].family;
}
pub fn model_126_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_127_id() []const u8 {
    return models[27].id;
}
pub fn model_127_context() u32 {
    return models[27].context_window;
}
pub fn model_127_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_127_family() []const u8 {
    return models[27].family;
}
pub fn model_127_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_128_id() []const u8 {
    return models[28].id;
}
pub fn model_128_context() u32 {
    return models[28].context_window;
}
pub fn model_128_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_128_family() []const u8 {
    return models[28].family;
}
pub fn model_128_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_129_id() []const u8 {
    return models[29].id;
}
pub fn model_129_context() u32 {
    return models[29].context_window;
}
pub fn model_129_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_129_family() []const u8 {
    return models[29].family;
}
pub fn model_129_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_130_id() []const u8 {
    return models[30].id;
}
pub fn model_130_context() u32 {
    return models[30].context_window;
}
pub fn model_130_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_130_family() []const u8 {
    return models[30].family;
}
pub fn model_130_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_131_id() []const u8 {
    return models[31].id;
}
pub fn model_131_context() u32 {
    return models[31].context_window;
}
pub fn model_131_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_131_family() []const u8 {
    return models[31].family;
}
pub fn model_131_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_132_id() []const u8 {
    return models[32].id;
}
pub fn model_132_context() u32 {
    return models[32].context_window;
}
pub fn model_132_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_132_family() []const u8 {
    return models[32].family;
}
pub fn model_132_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_133_id() []const u8 {
    return models[33].id;
}
pub fn model_133_context() u32 {
    return models[33].context_window;
}
pub fn model_133_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_133_family() []const u8 {
    return models[33].family;
}
pub fn model_133_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_134_id() []const u8 {
    return models[34].id;
}
pub fn model_134_context() u32 {
    return models[34].context_window;
}
pub fn model_134_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_134_family() []const u8 {
    return models[34].family;
}
pub fn model_134_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_135_id() []const u8 {
    return models[35].id;
}
pub fn model_135_context() u32 {
    return models[35].context_window;
}
pub fn model_135_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_135_family() []const u8 {
    return models[35].family;
}
pub fn model_135_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_136_id() []const u8 {
    return models[36].id;
}
pub fn model_136_context() u32 {
    return models[36].context_window;
}
pub fn model_136_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_136_family() []const u8 {
    return models[36].family;
}
pub fn model_136_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_137_id() []const u8 {
    return models[37].id;
}
pub fn model_137_context() u32 {
    return models[37].context_window;
}
pub fn model_137_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_137_family() []const u8 {
    return models[37].family;
}
pub fn model_137_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_138_id() []const u8 {
    return models[38].id;
}
pub fn model_138_context() u32 {
    return models[38].context_window;
}
pub fn model_138_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_138_family() []const u8 {
    return models[38].family;
}
pub fn model_138_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_139_id() []const u8 {
    return models[39].id;
}
pub fn model_139_context() u32 {
    return models[39].context_window;
}
pub fn model_139_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_139_family() []const u8 {
    return models[39].family;
}
pub fn model_139_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_140_id() []const u8 {
    return models[40].id;
}
pub fn model_140_context() u32 {
    return models[40].context_window;
}
pub fn model_140_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_140_family() []const u8 {
    return models[40].family;
}
pub fn model_140_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_141_id() []const u8 {
    return models[41].id;
}
pub fn model_141_context() u32 {
    return models[41].context_window;
}
pub fn model_141_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_141_family() []const u8 {
    return models[41].family;
}
pub fn model_141_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_142_id() []const u8 {
    return models[42].id;
}
pub fn model_142_context() u32 {
    return models[42].context_window;
}
pub fn model_142_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_142_family() []const u8 {
    return models[42].family;
}
pub fn model_142_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_143_id() []const u8 {
    return models[43].id;
}
pub fn model_143_context() u32 {
    return models[43].context_window;
}
pub fn model_143_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_143_family() []const u8 {
    return models[43].family;
}
pub fn model_143_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_144_id() []const u8 {
    return models[44].id;
}
pub fn model_144_context() u32 {
    return models[44].context_window;
}
pub fn model_144_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_144_family() []const u8 {
    return models[44].family;
}
pub fn model_144_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_145_id() []const u8 {
    return models[45].id;
}
pub fn model_145_context() u32 {
    return models[45].context_window;
}
pub fn model_145_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_145_family() []const u8 {
    return models[45].family;
}
pub fn model_145_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_146_id() []const u8 {
    return models[46].id;
}
pub fn model_146_context() u32 {
    return models[46].context_window;
}
pub fn model_146_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_146_family() []const u8 {
    return models[46].family;
}
pub fn model_146_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_147_id() []const u8 {
    return models[47].id;
}
pub fn model_147_context() u32 {
    return models[47].context_window;
}
pub fn model_147_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_147_family() []const u8 {
    return models[47].family;
}
pub fn model_147_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_148_id() []const u8 {
    return models[48].id;
}
pub fn model_148_context() u32 {
    return models[48].context_window;
}
pub fn model_148_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_148_family() []const u8 {
    return models[48].family;
}
pub fn model_148_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_149_id() []const u8 {
    return models[49].id;
}
pub fn model_149_context() u32 {
    return models[49].context_window;
}
pub fn model_149_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_149_family() []const u8 {
    return models[49].family;
}
pub fn model_149_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_150_id() []const u8 {
    return models[50].id;
}
pub fn model_150_context() u32 {
    return models[50].context_window;
}
pub fn model_150_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_150_family() []const u8 {
    return models[50].family;
}
pub fn model_150_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_151_id() []const u8 {
    return models[51].id;
}
pub fn model_151_context() u32 {
    return models[51].context_window;
}
pub fn model_151_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_151_family() []const u8 {
    return models[51].family;
}
pub fn model_151_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_152_id() []const u8 {
    return models[52].id;
}
pub fn model_152_context() u32 {
    return models[52].context_window;
}
pub fn model_152_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_152_family() []const u8 {
    return models[52].family;
}
pub fn model_152_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_153_id() []const u8 {
    return models[53].id;
}
pub fn model_153_context() u32 {
    return models[53].context_window;
}
pub fn model_153_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_153_family() []const u8 {
    return models[53].family;
}
pub fn model_153_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_154_id() []const u8 {
    return models[54].id;
}
pub fn model_154_context() u32 {
    return models[54].context_window;
}
pub fn model_154_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_154_family() []const u8 {
    return models[54].family;
}
pub fn model_154_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_155_id() []const u8 {
    return models[55].id;
}
pub fn model_155_context() u32 {
    return models[55].context_window;
}
pub fn model_155_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_155_family() []const u8 {
    return models[55].family;
}
pub fn model_155_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_156_id() []const u8 {
    return models[56].id;
}
pub fn model_156_context() u32 {
    return models[56].context_window;
}
pub fn model_156_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_156_family() []const u8 {
    return models[56].family;
}
pub fn model_156_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_157_id() []const u8 {
    return models[57].id;
}
pub fn model_157_context() u32 {
    return models[57].context_window;
}
pub fn model_157_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_157_family() []const u8 {
    return models[57].family;
}
pub fn model_157_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_158_id() []const u8 {
    return models[58].id;
}
pub fn model_158_context() u32 {
    return models[58].context_window;
}
pub fn model_158_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_158_family() []const u8 {
    return models[58].family;
}
pub fn model_158_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_159_id() []const u8 {
    return models[59].id;
}
pub fn model_159_context() u32 {
    return models[59].context_window;
}
pub fn model_159_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_159_family() []const u8 {
    return models[59].family;
}
pub fn model_159_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_160_id() []const u8 {
    return models[60].id;
}
pub fn model_160_context() u32 {
    return models[60].context_window;
}
pub fn model_160_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_160_family() []const u8 {
    return models[60].family;
}
pub fn model_160_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_161_id() []const u8 {
    return models[61].id;
}
pub fn model_161_context() u32 {
    return models[61].context_window;
}
pub fn model_161_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_161_family() []const u8 {
    return models[61].family;
}
pub fn model_161_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_162_id() []const u8 {
    return models[62].id;
}
pub fn model_162_context() u32 {
    return models[62].context_window;
}
pub fn model_162_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_162_family() []const u8 {
    return models[62].family;
}
pub fn model_162_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_163_id() []const u8 {
    return models[63].id;
}
pub fn model_163_context() u32 {
    return models[63].context_window;
}
pub fn model_163_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_163_family() []const u8 {
    return models[63].family;
}
pub fn model_163_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_164_id() []const u8 {
    return models[64].id;
}
pub fn model_164_context() u32 {
    return models[64].context_window;
}
pub fn model_164_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_164_family() []const u8 {
    return models[64].family;
}
pub fn model_164_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_165_id() []const u8 {
    return models[65].id;
}
pub fn model_165_context() u32 {
    return models[65].context_window;
}
pub fn model_165_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_165_family() []const u8 {
    return models[65].family;
}
pub fn model_165_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_166_id() []const u8 {
    return models[66].id;
}
pub fn model_166_context() u32 {
    return models[66].context_window;
}
pub fn model_166_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_166_family() []const u8 {
    return models[66].family;
}
pub fn model_166_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_167_id() []const u8 {
    return models[67].id;
}
pub fn model_167_context() u32 {
    return models[67].context_window;
}
pub fn model_167_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_167_family() []const u8 {
    return models[67].family;
}
pub fn model_167_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_168_id() []const u8 {
    return models[68].id;
}
pub fn model_168_context() u32 {
    return models[68].context_window;
}
pub fn model_168_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_168_family() []const u8 {
    return models[68].family;
}
pub fn model_168_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_169_id() []const u8 {
    return models[69].id;
}
pub fn model_169_context() u32 {
    return models[69].context_window;
}
pub fn model_169_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_169_family() []const u8 {
    return models[69].family;
}
pub fn model_169_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_170_id() []const u8 {
    return models[70].id;
}
pub fn model_170_context() u32 {
    return models[70].context_window;
}
pub fn model_170_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_170_family() []const u8 {
    return models[70].family;
}
pub fn model_170_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_171_id() []const u8 {
    return models[71].id;
}
pub fn model_171_context() u32 {
    return models[71].context_window;
}
pub fn model_171_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_171_family() []const u8 {
    return models[71].family;
}
pub fn model_171_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_172_id() []const u8 {
    return models[72].id;
}
pub fn model_172_context() u32 {
    return models[72].context_window;
}
pub fn model_172_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_172_family() []const u8 {
    return models[72].family;
}
pub fn model_172_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_173_id() []const u8 {
    return models[73].id;
}
pub fn model_173_context() u32 {
    return models[73].context_window;
}
pub fn model_173_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_173_family() []const u8 {
    return models[73].family;
}
pub fn model_173_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_174_id() []const u8 {
    return models[74].id;
}
pub fn model_174_context() u32 {
    return models[74].context_window;
}
pub fn model_174_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_174_family() []const u8 {
    return models[74].family;
}
pub fn model_174_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_175_id() []const u8 {
    return models[75].id;
}
pub fn model_175_context() u32 {
    return models[75].context_window;
}
pub fn model_175_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_175_family() []const u8 {
    return models[75].family;
}
pub fn model_175_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_176_id() []const u8 {
    return models[76].id;
}
pub fn model_176_context() u32 {
    return models[76].context_window;
}
pub fn model_176_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_176_family() []const u8 {
    return models[76].family;
}
pub fn model_176_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_177_id() []const u8 {
    return models[77].id;
}
pub fn model_177_context() u32 {
    return models[77].context_window;
}
pub fn model_177_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_177_family() []const u8 {
    return models[77].family;
}
pub fn model_177_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_178_id() []const u8 {
    return models[78].id;
}
pub fn model_178_context() u32 {
    return models[78].context_window;
}
pub fn model_178_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_178_family() []const u8 {
    return models[78].family;
}
pub fn model_178_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_179_id() []const u8 {
    return models[79].id;
}
pub fn model_179_context() u32 {
    return models[79].context_window;
}
pub fn model_179_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_179_family() []const u8 {
    return models[79].family;
}
pub fn model_179_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 1 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

