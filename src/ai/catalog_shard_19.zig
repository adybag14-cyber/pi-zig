//! Generated model catalog shard 19 for package ai.
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

pub const shard_index: u32 = 19;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "sambanova/chat-1900", .provider = "sambanova", .display = "Sambanova Chat 1900", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1901", .provider = "github", .display = "Github Code 1901", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1902", .provider = "huggingface", .display = "Huggingface Reason 1902", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1903", .provider = "replicate", .display = "Replicate Vision 1903", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1904", .provider = "anyscale", .display = "Anyscale Embed 1904", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "embed" },
    .{ .id = "databricks/audio-1905", .provider = "databricks", .display = "Databricks Audio 1905", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1906", .provider = "moonshot", .display = "Moonshot Fast 1906", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1907", .provider = "qwen", .display = "Qwen Large 1907", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1908", .provider = "minimax", .display = "Minimax Mini 1908", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1909", .provider = "zhipu", .display = "Zhipu Nano 1909", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1910", .provider = "baichuan", .display = "Baichuan Pro 1910", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1911", .provider = "yi", .display = "Yi Ultra 1911", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1912", .provider = "siliconflow", .display = "Siliconflow Turbo 1912", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1913", .provider = "novita", .display = "Novita Instruct 1913", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1914", .provider = "lepton", .display = "Lepton Base 1914", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1915", .provider = "deepinfra", .display = "Deepinfra Preview 1915", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1916", .provider = "friendli", .display = "Friendli Experimental 1916", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1917", .provider = "hyperbolic", .display = "Hyperbolic Stable 1917", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1918", .provider = "lambda", .display = "Lambda Legacy 1918", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "legacy" },
    .{ .id = "nebius/edge-1919", .provider = "nebius", .display = "Nebius Edge 1919", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1920", .provider = "openai", .display = "Openai Chat 1920", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1921", .provider = "anthropic", .display = "Anthropic Code 1921", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1922", .provider = "google", .display = "Google Reason 1922", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1923", .provider = "groq", .display = "Groq Vision 1923", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1924", .provider = "xai", .display = "Xai Embed 1924", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1925", .provider = "deepseek", .display = "Deepseek Audio 1925", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "audio" },
    .{ .id = "mistral/fast-1926", .provider = "mistral", .display = "Mistral Fast 1926", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1927", .provider = "together", .display = "Together Large 1927", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1928", .provider = "fireworks", .display = "Fireworks Mini 1928", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1929", .provider = "openrouter", .display = "Openrouter Nano 1929", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1930", .provider = "cerebras", .display = "Cerebras Pro 1930", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1931", .provider = "ollama", .display = "Ollama Ultra 1931", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1932", .provider = "lmstudio", .display = "Lmstudio Turbo 1932", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "turbo" },
    .{ .id = "vllm/instruct-1933", .provider = "vllm", .display = "Vllm Instruct 1933", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1934", .provider = "azure", .display = "Azure Base 1934", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1935", .provider = "bedrock", .display = "Bedrock Preview 1935", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1936", .provider = "vertex", .display = "Vertex Experimental 1936", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1937", .provider = "perplexity", .display = "Perplexity Stable 1937", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1938", .provider = "cohere", .display = "Cohere Legacy 1938", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1939", .provider = "nvidia", .display = "Nvidia Edge 1939", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "edge" },
    .{ .id = "sambanova/chat-1940", .provider = "sambanova", .display = "Sambanova Chat 1940", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1941", .provider = "github", .display = "Github Code 1941", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1942", .provider = "huggingface", .display = "Huggingface Reason 1942", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1943", .provider = "replicate", .display = "Replicate Vision 1943", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1944", .provider = "anyscale", .display = "Anyscale Embed 1944", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1945", .provider = "databricks", .display = "Databricks Audio 1945", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1946", .provider = "moonshot", .display = "Moonshot Fast 1946", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "qwen/large-1947", .provider = "qwen", .display = "Qwen Large 1947", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1948", .provider = "minimax", .display = "Minimax Mini 1948", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1949", .provider = "zhipu", .display = "Zhipu Nano 1949", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1950", .provider = "baichuan", .display = "Baichuan Pro 1950", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1951", .provider = "yi", .display = "Yi Ultra 1951", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1952", .provider = "siliconflow", .display = "Siliconflow Turbo 1952", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1953", .provider = "novita", .display = "Novita Instruct 1953", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "lepton/base-1954", .provider = "lepton", .display = "Lepton Base 1954", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1955", .provider = "deepinfra", .display = "Deepinfra Preview 1955", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1956", .provider = "friendli", .display = "Friendli Experimental 1956", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1957", .provider = "hyperbolic", .display = "Hyperbolic Stable 1957", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1958", .provider = "lambda", .display = "Lambda Legacy 1958", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1959", .provider = "nebius", .display = "Nebius Edge 1959", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1960", .provider = "openai", .display = "Openai Chat 1960", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "anthropic/code-1961", .provider = "anthropic", .display = "Anthropic Code 1961", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1962", .provider = "google", .display = "Google Reason 1962", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1963", .provider = "groq", .display = "Groq Vision 1963", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1964", .provider = "xai", .display = "Xai Embed 1964", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1965", .provider = "deepseek", .display = "Deepseek Audio 1965", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1966", .provider = "mistral", .display = "Mistral Fast 1966", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1967", .provider = "together", .display = "Together Large 1967", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "fireworks/mini-1968", .provider = "fireworks", .display = "Fireworks Mini 1968", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1969", .provider = "openrouter", .display = "Openrouter Nano 1969", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1970", .provider = "cerebras", .display = "Cerebras Pro 1970", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1971", .provider = "ollama", .display = "Ollama Ultra 1971", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1972", .provider = "lmstudio", .display = "Lmstudio Turbo 1972", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1973", .provider = "vllm", .display = "Vllm Instruct 1973", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1974", .provider = "azure", .display = "Azure Base 1974", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "bedrock/preview-1975", .provider = "bedrock", .display = "Bedrock Preview 1975", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1976", .provider = "vertex", .display = "Vertex Experimental 1976", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1977", .provider = "perplexity", .display = "Perplexity Stable 1977", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1978", .provider = "cohere", .display = "Cohere Legacy 1978", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1979", .provider = "nvidia", .display = "Nvidia Edge 1979", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1980", .provider = "sambanova", .display = "Sambanova Chat 1980", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1981", .provider = "github", .display = "Github Code 1981", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "huggingface/reason-1982", .provider = "huggingface", .display = "Huggingface Reason 1982", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1983", .provider = "replicate", .display = "Replicate Vision 1983", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1984", .provider = "anyscale", .display = "Anyscale Embed 1984", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1985", .provider = "databricks", .display = "Databricks Audio 1985", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1986", .provider = "moonshot", .display = "Moonshot Fast 1986", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1987", .provider = "qwen", .display = "Qwen Large 1987", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1988", .provider = "minimax", .display = "Minimax Mini 1988", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "zhipu/nano-1989", .provider = "zhipu", .display = "Zhipu Nano 1989", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1990", .provider = "baichuan", .display = "Baichuan Pro 1990", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1991", .provider = "yi", .display = "Yi Ultra 1991", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1992", .provider = "siliconflow", .display = "Siliconflow Turbo 1992", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1993", .provider = "novita", .display = "Novita Instruct 1993", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1994", .provider = "lepton", .display = "Lepton Base 1994", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1995", .provider = "deepinfra", .display = "Deepinfra Preview 1995", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "friendli/experimental-1996", .provider = "friendli", .display = "Friendli Experimental 1996", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1997", .provider = "hyperbolic", .display = "Hyperbolic Stable 1997", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1998", .provider = "lambda", .display = "Lambda Legacy 1998", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1999", .provider = "nebius", .display = "Nebius Edge 1999", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1900_id() []const u8 {
    return models[0].id;
}
pub fn model_1900_context() u32 {
    return models[0].context_window;
}
pub fn model_1900_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1900_family() []const u8 {
    return models[0].family;
}
pub fn model_1900_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1901_id() []const u8 {
    return models[1].id;
}
pub fn model_1901_context() u32 {
    return models[1].context_window;
}
pub fn model_1901_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1901_family() []const u8 {
    return models[1].family;
}
pub fn model_1901_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1902_id() []const u8 {
    return models[2].id;
}
pub fn model_1902_context() u32 {
    return models[2].context_window;
}
pub fn model_1902_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1902_family() []const u8 {
    return models[2].family;
}
pub fn model_1902_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1903_id() []const u8 {
    return models[3].id;
}
pub fn model_1903_context() u32 {
    return models[3].context_window;
}
pub fn model_1903_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1903_family() []const u8 {
    return models[3].family;
}
pub fn model_1903_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1904_id() []const u8 {
    return models[4].id;
}
pub fn model_1904_context() u32 {
    return models[4].context_window;
}
pub fn model_1904_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1904_family() []const u8 {
    return models[4].family;
}
pub fn model_1904_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1905_id() []const u8 {
    return models[5].id;
}
pub fn model_1905_context() u32 {
    return models[5].context_window;
}
pub fn model_1905_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1905_family() []const u8 {
    return models[5].family;
}
pub fn model_1905_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1906_id() []const u8 {
    return models[6].id;
}
pub fn model_1906_context() u32 {
    return models[6].context_window;
}
pub fn model_1906_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1906_family() []const u8 {
    return models[6].family;
}
pub fn model_1906_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1907_id() []const u8 {
    return models[7].id;
}
pub fn model_1907_context() u32 {
    return models[7].context_window;
}
pub fn model_1907_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1907_family() []const u8 {
    return models[7].family;
}
pub fn model_1907_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1908_id() []const u8 {
    return models[8].id;
}
pub fn model_1908_context() u32 {
    return models[8].context_window;
}
pub fn model_1908_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1908_family() []const u8 {
    return models[8].family;
}
pub fn model_1908_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1909_id() []const u8 {
    return models[9].id;
}
pub fn model_1909_context() u32 {
    return models[9].context_window;
}
pub fn model_1909_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1909_family() []const u8 {
    return models[9].family;
}
pub fn model_1909_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1910_id() []const u8 {
    return models[10].id;
}
pub fn model_1910_context() u32 {
    return models[10].context_window;
}
pub fn model_1910_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1910_family() []const u8 {
    return models[10].family;
}
pub fn model_1910_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1911_id() []const u8 {
    return models[11].id;
}
pub fn model_1911_context() u32 {
    return models[11].context_window;
}
pub fn model_1911_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1911_family() []const u8 {
    return models[11].family;
}
pub fn model_1911_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1912_id() []const u8 {
    return models[12].id;
}
pub fn model_1912_context() u32 {
    return models[12].context_window;
}
pub fn model_1912_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1912_family() []const u8 {
    return models[12].family;
}
pub fn model_1912_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1913_id() []const u8 {
    return models[13].id;
}
pub fn model_1913_context() u32 {
    return models[13].context_window;
}
pub fn model_1913_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1913_family() []const u8 {
    return models[13].family;
}
pub fn model_1913_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1914_id() []const u8 {
    return models[14].id;
}
pub fn model_1914_context() u32 {
    return models[14].context_window;
}
pub fn model_1914_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1914_family() []const u8 {
    return models[14].family;
}
pub fn model_1914_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1915_id() []const u8 {
    return models[15].id;
}
pub fn model_1915_context() u32 {
    return models[15].context_window;
}
pub fn model_1915_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1915_family() []const u8 {
    return models[15].family;
}
pub fn model_1915_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1916_id() []const u8 {
    return models[16].id;
}
pub fn model_1916_context() u32 {
    return models[16].context_window;
}
pub fn model_1916_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1916_family() []const u8 {
    return models[16].family;
}
pub fn model_1916_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1917_id() []const u8 {
    return models[17].id;
}
pub fn model_1917_context() u32 {
    return models[17].context_window;
}
pub fn model_1917_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1917_family() []const u8 {
    return models[17].family;
}
pub fn model_1917_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1918_id() []const u8 {
    return models[18].id;
}
pub fn model_1918_context() u32 {
    return models[18].context_window;
}
pub fn model_1918_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1918_family() []const u8 {
    return models[18].family;
}
pub fn model_1918_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1919_id() []const u8 {
    return models[19].id;
}
pub fn model_1919_context() u32 {
    return models[19].context_window;
}
pub fn model_1919_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1919_family() []const u8 {
    return models[19].family;
}
pub fn model_1919_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1920_id() []const u8 {
    return models[20].id;
}
pub fn model_1920_context() u32 {
    return models[20].context_window;
}
pub fn model_1920_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1920_family() []const u8 {
    return models[20].family;
}
pub fn model_1920_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1921_id() []const u8 {
    return models[21].id;
}
pub fn model_1921_context() u32 {
    return models[21].context_window;
}
pub fn model_1921_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1921_family() []const u8 {
    return models[21].family;
}
pub fn model_1921_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1922_id() []const u8 {
    return models[22].id;
}
pub fn model_1922_context() u32 {
    return models[22].context_window;
}
pub fn model_1922_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1922_family() []const u8 {
    return models[22].family;
}
pub fn model_1922_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1923_id() []const u8 {
    return models[23].id;
}
pub fn model_1923_context() u32 {
    return models[23].context_window;
}
pub fn model_1923_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1923_family() []const u8 {
    return models[23].family;
}
pub fn model_1923_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1924_id() []const u8 {
    return models[24].id;
}
pub fn model_1924_context() u32 {
    return models[24].context_window;
}
pub fn model_1924_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1924_family() []const u8 {
    return models[24].family;
}
pub fn model_1924_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1925_id() []const u8 {
    return models[25].id;
}
pub fn model_1925_context() u32 {
    return models[25].context_window;
}
pub fn model_1925_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1925_family() []const u8 {
    return models[25].family;
}
pub fn model_1925_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1926_id() []const u8 {
    return models[26].id;
}
pub fn model_1926_context() u32 {
    return models[26].context_window;
}
pub fn model_1926_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1926_family() []const u8 {
    return models[26].family;
}
pub fn model_1926_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1927_id() []const u8 {
    return models[27].id;
}
pub fn model_1927_context() u32 {
    return models[27].context_window;
}
pub fn model_1927_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1927_family() []const u8 {
    return models[27].family;
}
pub fn model_1927_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1928_id() []const u8 {
    return models[28].id;
}
pub fn model_1928_context() u32 {
    return models[28].context_window;
}
pub fn model_1928_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1928_family() []const u8 {
    return models[28].family;
}
pub fn model_1928_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1929_id() []const u8 {
    return models[29].id;
}
pub fn model_1929_context() u32 {
    return models[29].context_window;
}
pub fn model_1929_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1929_family() []const u8 {
    return models[29].family;
}
pub fn model_1929_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1930_id() []const u8 {
    return models[30].id;
}
pub fn model_1930_context() u32 {
    return models[30].context_window;
}
pub fn model_1930_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1930_family() []const u8 {
    return models[30].family;
}
pub fn model_1930_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1931_id() []const u8 {
    return models[31].id;
}
pub fn model_1931_context() u32 {
    return models[31].context_window;
}
pub fn model_1931_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1931_family() []const u8 {
    return models[31].family;
}
pub fn model_1931_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1932_id() []const u8 {
    return models[32].id;
}
pub fn model_1932_context() u32 {
    return models[32].context_window;
}
pub fn model_1932_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1932_family() []const u8 {
    return models[32].family;
}
pub fn model_1932_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1933_id() []const u8 {
    return models[33].id;
}
pub fn model_1933_context() u32 {
    return models[33].context_window;
}
pub fn model_1933_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1933_family() []const u8 {
    return models[33].family;
}
pub fn model_1933_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1934_id() []const u8 {
    return models[34].id;
}
pub fn model_1934_context() u32 {
    return models[34].context_window;
}
pub fn model_1934_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1934_family() []const u8 {
    return models[34].family;
}
pub fn model_1934_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1935_id() []const u8 {
    return models[35].id;
}
pub fn model_1935_context() u32 {
    return models[35].context_window;
}
pub fn model_1935_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1935_family() []const u8 {
    return models[35].family;
}
pub fn model_1935_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1936_id() []const u8 {
    return models[36].id;
}
pub fn model_1936_context() u32 {
    return models[36].context_window;
}
pub fn model_1936_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1936_family() []const u8 {
    return models[36].family;
}
pub fn model_1936_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1937_id() []const u8 {
    return models[37].id;
}
pub fn model_1937_context() u32 {
    return models[37].context_window;
}
pub fn model_1937_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1937_family() []const u8 {
    return models[37].family;
}
pub fn model_1937_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1938_id() []const u8 {
    return models[38].id;
}
pub fn model_1938_context() u32 {
    return models[38].context_window;
}
pub fn model_1938_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1938_family() []const u8 {
    return models[38].family;
}
pub fn model_1938_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1939_id() []const u8 {
    return models[39].id;
}
pub fn model_1939_context() u32 {
    return models[39].context_window;
}
pub fn model_1939_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1939_family() []const u8 {
    return models[39].family;
}
pub fn model_1939_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1940_id() []const u8 {
    return models[40].id;
}
pub fn model_1940_context() u32 {
    return models[40].context_window;
}
pub fn model_1940_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1940_family() []const u8 {
    return models[40].family;
}
pub fn model_1940_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1941_id() []const u8 {
    return models[41].id;
}
pub fn model_1941_context() u32 {
    return models[41].context_window;
}
pub fn model_1941_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1941_family() []const u8 {
    return models[41].family;
}
pub fn model_1941_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1942_id() []const u8 {
    return models[42].id;
}
pub fn model_1942_context() u32 {
    return models[42].context_window;
}
pub fn model_1942_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1942_family() []const u8 {
    return models[42].family;
}
pub fn model_1942_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1943_id() []const u8 {
    return models[43].id;
}
pub fn model_1943_context() u32 {
    return models[43].context_window;
}
pub fn model_1943_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1943_family() []const u8 {
    return models[43].family;
}
pub fn model_1943_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1944_id() []const u8 {
    return models[44].id;
}
pub fn model_1944_context() u32 {
    return models[44].context_window;
}
pub fn model_1944_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1944_family() []const u8 {
    return models[44].family;
}
pub fn model_1944_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1945_id() []const u8 {
    return models[45].id;
}
pub fn model_1945_context() u32 {
    return models[45].context_window;
}
pub fn model_1945_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1945_family() []const u8 {
    return models[45].family;
}
pub fn model_1945_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1946_id() []const u8 {
    return models[46].id;
}
pub fn model_1946_context() u32 {
    return models[46].context_window;
}
pub fn model_1946_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1946_family() []const u8 {
    return models[46].family;
}
pub fn model_1946_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1947_id() []const u8 {
    return models[47].id;
}
pub fn model_1947_context() u32 {
    return models[47].context_window;
}
pub fn model_1947_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1947_family() []const u8 {
    return models[47].family;
}
pub fn model_1947_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1948_id() []const u8 {
    return models[48].id;
}
pub fn model_1948_context() u32 {
    return models[48].context_window;
}
pub fn model_1948_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1948_family() []const u8 {
    return models[48].family;
}
pub fn model_1948_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1949_id() []const u8 {
    return models[49].id;
}
pub fn model_1949_context() u32 {
    return models[49].context_window;
}
pub fn model_1949_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1949_family() []const u8 {
    return models[49].family;
}
pub fn model_1949_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1950_id() []const u8 {
    return models[50].id;
}
pub fn model_1950_context() u32 {
    return models[50].context_window;
}
pub fn model_1950_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1950_family() []const u8 {
    return models[50].family;
}
pub fn model_1950_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1951_id() []const u8 {
    return models[51].id;
}
pub fn model_1951_context() u32 {
    return models[51].context_window;
}
pub fn model_1951_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1951_family() []const u8 {
    return models[51].family;
}
pub fn model_1951_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1952_id() []const u8 {
    return models[52].id;
}
pub fn model_1952_context() u32 {
    return models[52].context_window;
}
pub fn model_1952_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1952_family() []const u8 {
    return models[52].family;
}
pub fn model_1952_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1953_id() []const u8 {
    return models[53].id;
}
pub fn model_1953_context() u32 {
    return models[53].context_window;
}
pub fn model_1953_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1953_family() []const u8 {
    return models[53].family;
}
pub fn model_1953_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1954_id() []const u8 {
    return models[54].id;
}
pub fn model_1954_context() u32 {
    return models[54].context_window;
}
pub fn model_1954_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1954_family() []const u8 {
    return models[54].family;
}
pub fn model_1954_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1955_id() []const u8 {
    return models[55].id;
}
pub fn model_1955_context() u32 {
    return models[55].context_window;
}
pub fn model_1955_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1955_family() []const u8 {
    return models[55].family;
}
pub fn model_1955_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1956_id() []const u8 {
    return models[56].id;
}
pub fn model_1956_context() u32 {
    return models[56].context_window;
}
pub fn model_1956_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1956_family() []const u8 {
    return models[56].family;
}
pub fn model_1956_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1957_id() []const u8 {
    return models[57].id;
}
pub fn model_1957_context() u32 {
    return models[57].context_window;
}
pub fn model_1957_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1957_family() []const u8 {
    return models[57].family;
}
pub fn model_1957_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1958_id() []const u8 {
    return models[58].id;
}
pub fn model_1958_context() u32 {
    return models[58].context_window;
}
pub fn model_1958_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1958_family() []const u8 {
    return models[58].family;
}
pub fn model_1958_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1959_id() []const u8 {
    return models[59].id;
}
pub fn model_1959_context() u32 {
    return models[59].context_window;
}
pub fn model_1959_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1959_family() []const u8 {
    return models[59].family;
}
pub fn model_1959_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1960_id() []const u8 {
    return models[60].id;
}
pub fn model_1960_context() u32 {
    return models[60].context_window;
}
pub fn model_1960_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1960_family() []const u8 {
    return models[60].family;
}
pub fn model_1960_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1961_id() []const u8 {
    return models[61].id;
}
pub fn model_1961_context() u32 {
    return models[61].context_window;
}
pub fn model_1961_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1961_family() []const u8 {
    return models[61].family;
}
pub fn model_1961_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1962_id() []const u8 {
    return models[62].id;
}
pub fn model_1962_context() u32 {
    return models[62].context_window;
}
pub fn model_1962_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1962_family() []const u8 {
    return models[62].family;
}
pub fn model_1962_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1963_id() []const u8 {
    return models[63].id;
}
pub fn model_1963_context() u32 {
    return models[63].context_window;
}
pub fn model_1963_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1963_family() []const u8 {
    return models[63].family;
}
pub fn model_1963_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1964_id() []const u8 {
    return models[64].id;
}
pub fn model_1964_context() u32 {
    return models[64].context_window;
}
pub fn model_1964_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1964_family() []const u8 {
    return models[64].family;
}
pub fn model_1964_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1965_id() []const u8 {
    return models[65].id;
}
pub fn model_1965_context() u32 {
    return models[65].context_window;
}
pub fn model_1965_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1965_family() []const u8 {
    return models[65].family;
}
pub fn model_1965_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1966_id() []const u8 {
    return models[66].id;
}
pub fn model_1966_context() u32 {
    return models[66].context_window;
}
pub fn model_1966_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1966_family() []const u8 {
    return models[66].family;
}
pub fn model_1966_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1967_id() []const u8 {
    return models[67].id;
}
pub fn model_1967_context() u32 {
    return models[67].context_window;
}
pub fn model_1967_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1967_family() []const u8 {
    return models[67].family;
}
pub fn model_1967_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1968_id() []const u8 {
    return models[68].id;
}
pub fn model_1968_context() u32 {
    return models[68].context_window;
}
pub fn model_1968_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1968_family() []const u8 {
    return models[68].family;
}
pub fn model_1968_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1969_id() []const u8 {
    return models[69].id;
}
pub fn model_1969_context() u32 {
    return models[69].context_window;
}
pub fn model_1969_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1969_family() []const u8 {
    return models[69].family;
}
pub fn model_1969_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1970_id() []const u8 {
    return models[70].id;
}
pub fn model_1970_context() u32 {
    return models[70].context_window;
}
pub fn model_1970_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1970_family() []const u8 {
    return models[70].family;
}
pub fn model_1970_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1971_id() []const u8 {
    return models[71].id;
}
pub fn model_1971_context() u32 {
    return models[71].context_window;
}
pub fn model_1971_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1971_family() []const u8 {
    return models[71].family;
}
pub fn model_1971_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1972_id() []const u8 {
    return models[72].id;
}
pub fn model_1972_context() u32 {
    return models[72].context_window;
}
pub fn model_1972_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1972_family() []const u8 {
    return models[72].family;
}
pub fn model_1972_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1973_id() []const u8 {
    return models[73].id;
}
pub fn model_1973_context() u32 {
    return models[73].context_window;
}
pub fn model_1973_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1973_family() []const u8 {
    return models[73].family;
}
pub fn model_1973_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1974_id() []const u8 {
    return models[74].id;
}
pub fn model_1974_context() u32 {
    return models[74].context_window;
}
pub fn model_1974_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1974_family() []const u8 {
    return models[74].family;
}
pub fn model_1974_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1975_id() []const u8 {
    return models[75].id;
}
pub fn model_1975_context() u32 {
    return models[75].context_window;
}
pub fn model_1975_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1975_family() []const u8 {
    return models[75].family;
}
pub fn model_1975_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1976_id() []const u8 {
    return models[76].id;
}
pub fn model_1976_context() u32 {
    return models[76].context_window;
}
pub fn model_1976_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1976_family() []const u8 {
    return models[76].family;
}
pub fn model_1976_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1977_id() []const u8 {
    return models[77].id;
}
pub fn model_1977_context() u32 {
    return models[77].context_window;
}
pub fn model_1977_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1977_family() []const u8 {
    return models[77].family;
}
pub fn model_1977_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1978_id() []const u8 {
    return models[78].id;
}
pub fn model_1978_context() u32 {
    return models[78].context_window;
}
pub fn model_1978_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1978_family() []const u8 {
    return models[78].family;
}
pub fn model_1978_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1979_id() []const u8 {
    return models[79].id;
}
pub fn model_1979_context() u32 {
    return models[79].context_window;
}
pub fn model_1979_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1979_family() []const u8 {
    return models[79].family;
}
pub fn model_1979_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 19 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

