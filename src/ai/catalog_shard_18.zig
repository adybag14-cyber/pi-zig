//! Generated model catalog shard 18 for package ai.
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

pub const shard_index: u32 = 18;
pub const shard_count: u32 = 100;

pub const models = [_]ModelMeta{
    .{ .id = "openai/chat-1800", .provider = "openai", .display = "Openai Chat 1800", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.05, .output_cost_per_mtok = 0.15, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1801", .provider = "anthropic", .display = "Anthropic Code 1801", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.06, .output_cost_per_mtok = 0.17, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1802", .provider = "google", .display = "Google Reason 1802", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.07, .output_cost_per_mtok = 0.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1803", .provider = "groq", .display = "Groq Vision 1803", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.08, .output_cost_per_mtok = 0.21, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1804", .provider = "xai", .display = "Xai Embed 1804", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.09, .output_cost_per_mtok = 0.23, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1805", .provider = "deepseek", .display = "Deepseek Audio 1805", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.10, .output_cost_per_mtok = 0.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1806", .provider = "mistral", .display = "Mistral Fast 1806", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.11, .output_cost_per_mtok = 0.27, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "fast" },
    .{ .id = "together/large-1807", .provider = "together", .display = "Together Large 1807", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.12, .output_cost_per_mtok = 0.29, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1808", .provider = "fireworks", .display = "Fireworks Mini 1808", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.13, .output_cost_per_mtok = 0.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1809", .provider = "openrouter", .display = "Openrouter Nano 1809", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.14, .output_cost_per_mtok = 0.33, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1810", .provider = "cerebras", .display = "Cerebras Pro 1810", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.15, .output_cost_per_mtok = 0.35, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1811", .provider = "ollama", .display = "Ollama Ultra 1811", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.16, .output_cost_per_mtok = 0.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1812", .provider = "lmstudio", .display = "Lmstudio Turbo 1812", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.17, .output_cost_per_mtok = 0.39, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1813", .provider = "vllm", .display = "Vllm Instruct 1813", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.18, .output_cost_per_mtok = 0.41, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "instruct" },
    .{ .id = "azure/base-1814", .provider = "azure", .display = "Azure Base 1814", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.19, .output_cost_per_mtok = 0.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1815", .provider = "bedrock", .display = "Bedrock Preview 1815", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.20, .output_cost_per_mtok = 0.45, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1816", .provider = "vertex", .display = "Vertex Experimental 1816", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.21, .output_cost_per_mtok = 0.47, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1817", .provider = "perplexity", .display = "Perplexity Stable 1817", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.22, .output_cost_per_mtok = 0.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1818", .provider = "cohere", .display = "Cohere Legacy 1818", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.23, .output_cost_per_mtok = 0.51, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1819", .provider = "nvidia", .display = "Nvidia Edge 1819", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.24, .output_cost_per_mtok = 0.53, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1820", .provider = "sambanova", .display = "Sambanova Chat 1820", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.25, .output_cost_per_mtok = 0.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "chat" },
    .{ .id = "github/code-1821", .provider = "github", .display = "Github Code 1821", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.26, .output_cost_per_mtok = 0.57, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1822", .provider = "huggingface", .display = "Huggingface Reason 1822", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.27, .output_cost_per_mtok = 0.59, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "replicate/vision-1823", .provider = "replicate", .display = "Replicate Vision 1823", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.28, .output_cost_per_mtok = 0.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1824", .provider = "anyscale", .display = "Anyscale Embed 1824", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.29, .output_cost_per_mtok = 0.63, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1825", .provider = "databricks", .display = "Databricks Audio 1825", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.30, .output_cost_per_mtok = 0.65, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1826", .provider = "moonshot", .display = "Moonshot Fast 1826", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.31, .output_cost_per_mtok = 0.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1827", .provider = "qwen", .display = "Qwen Large 1827", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.32, .output_cost_per_mtok = 0.69, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "large" },
    .{ .id = "minimax/mini-1828", .provider = "minimax", .display = "Minimax Mini 1828", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.33, .output_cost_per_mtok = 0.71, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1829", .provider = "zhipu", .display = "Zhipu Nano 1829", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.34, .output_cost_per_mtok = 0.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "baichuan/pro-1830", .provider = "baichuan", .display = "Baichuan Pro 1830", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.35, .output_cost_per_mtok = 0.75, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1831", .provider = "yi", .display = "Yi Ultra 1831", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.36, .output_cost_per_mtok = 0.77, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1832", .provider = "siliconflow", .display = "Siliconflow Turbo 1832", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.37, .output_cost_per_mtok = 0.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1833", .provider = "novita", .display = "Novita Instruct 1833", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.38, .output_cost_per_mtok = 0.81, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1834", .provider = "lepton", .display = "Lepton Base 1834", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.39, .output_cost_per_mtok = 0.83, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "base" },
    .{ .id = "deepinfra/preview-1835", .provider = "deepinfra", .display = "Deepinfra Preview 1835", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.40, .output_cost_per_mtok = 0.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1836", .provider = "friendli", .display = "Friendli Experimental 1836", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.41, .output_cost_per_mtok = 0.87, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1837", .provider = "hyperbolic", .display = "Hyperbolic Stable 1837", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.42, .output_cost_per_mtok = 0.89, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1838", .provider = "lambda", .display = "Lambda Legacy 1838", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.43, .output_cost_per_mtok = 0.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1839", .provider = "nebius", .display = "Nebius Edge 1839", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.44, .output_cost_per_mtok = 0.93, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1840", .provider = "openai", .display = "Openai Chat 1840", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.45, .output_cost_per_mtok = 0.95, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1841", .provider = "anthropic", .display = "Anthropic Code 1841", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.46, .output_cost_per_mtok = 0.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "code" },
    .{ .id = "google/reason-1842", .provider = "google", .display = "Google Reason 1842", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.47, .output_cost_per_mtok = 0.99, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1843", .provider = "groq", .display = "Groq Vision 1843", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.48, .output_cost_per_mtok = 1.01, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "xai/embed-1844", .provider = "xai", .display = "Xai Embed 1844", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.49, .output_cost_per_mtok = 1.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1845", .provider = "deepseek", .display = "Deepseek Audio 1845", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.50, .output_cost_per_mtok = 1.05, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1846", .provider = "mistral", .display = "Mistral Fast 1846", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.51, .output_cost_per_mtok = 1.07, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1847", .provider = "together", .display = "Together Large 1847", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.52, .output_cost_per_mtok = 1.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1848", .provider = "fireworks", .display = "Fireworks Mini 1848", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.53, .output_cost_per_mtok = 1.11, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "mini" },
    .{ .id = "openrouter/nano-1849", .provider = "openrouter", .display = "Openrouter Nano 1849", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.54, .output_cost_per_mtok = 1.13, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1850", .provider = "cerebras", .display = "Cerebras Pro 1850", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.55, .output_cost_per_mtok = 1.15, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "ollama/ultra-1851", .provider = "ollama", .display = "Ollama Ultra 1851", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.56, .output_cost_per_mtok = 1.17, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1852", .provider = "lmstudio", .display = "Lmstudio Turbo 1852", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.57, .output_cost_per_mtok = 1.19, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1853", .provider = "vllm", .display = "Vllm Instruct 1853", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.58, .output_cost_per_mtok = 1.21, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1854", .provider = "azure", .display = "Azure Base 1854", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.59, .output_cost_per_mtok = 1.23, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1855", .provider = "bedrock", .display = "Bedrock Preview 1855", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.60, .output_cost_per_mtok = 1.25, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "preview" },
    .{ .id = "vertex/experimental-1856", .provider = "vertex", .display = "Vertex Experimental 1856", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.61, .output_cost_per_mtok = 1.27, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1857", .provider = "perplexity", .display = "Perplexity Stable 1857", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.62, .output_cost_per_mtok = 1.29, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "cohere/legacy-1858", .provider = "cohere", .display = "Cohere Legacy 1858", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.63, .output_cost_per_mtok = 1.31, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1859", .provider = "nvidia", .display = "Nvidia Edge 1859", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.64, .output_cost_per_mtok = 1.33, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "sambanova/chat-1860", .provider = "sambanova", .display = "Sambanova Chat 1860", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.65, .output_cost_per_mtok = 1.35, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "github/code-1861", .provider = "github", .display = "Github Code 1861", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.66, .output_cost_per_mtok = 1.37, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "huggingface/reason-1862", .provider = "huggingface", .display = "Huggingface Reason 1862", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.67, .output_cost_per_mtok = 1.39, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "reason" },
    .{ .id = "replicate/vision-1863", .provider = "replicate", .display = "Replicate Vision 1863", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 0.68, .output_cost_per_mtok = 1.41, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "vision" },
    .{ .id = "anyscale/embed-1864", .provider = "anyscale", .display = "Anyscale Embed 1864", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 0.69, .output_cost_per_mtok = 1.43, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "databricks/audio-1865", .provider = "databricks", .display = "Databricks Audio 1865", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 0.70, .output_cost_per_mtok = 1.45, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "moonshot/fast-1866", .provider = "moonshot", .display = "Moonshot Fast 1866", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 0.71, .output_cost_per_mtok = 1.47, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "qwen/large-1867", .provider = "qwen", .display = "Qwen Large 1867", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 0.72, .output_cost_per_mtok = 1.49, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "minimax/mini-1868", .provider = "minimax", .display = "Minimax Mini 1868", .context_window = 53248, .max_output = 13312, .input_cost_per_mtok = 0.73, .output_cost_per_mtok = 1.51, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "zhipu/nano-1869", .provider = "zhipu", .display = "Zhipu Nano 1869", .context_window = 57344, .max_output = 14336, .input_cost_per_mtok = 0.74, .output_cost_per_mtok = 1.53, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "nano" },
    .{ .id = "baichuan/pro-1870", .provider = "baichuan", .display = "Baichuan Pro 1870", .context_window = 61440, .max_output = 15360, .input_cost_per_mtok = 0.75, .output_cost_per_mtok = 1.55, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "pro" },
    .{ .id = "yi/ultra-1871", .provider = "yi", .display = "Yi Ultra 1871", .context_window = 65536, .max_output = 16384, .input_cost_per_mtok = 0.76, .output_cost_per_mtok = 1.57, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "siliconflow/turbo-1872", .provider = "siliconflow", .display = "Siliconflow Turbo 1872", .context_window = 69632, .max_output = 1024, .input_cost_per_mtok = 0.77, .output_cost_per_mtok = 1.59, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "novita/instruct-1873", .provider = "novita", .display = "Novita Instruct 1873", .context_window = 73728, .max_output = 2048, .input_cost_per_mtok = 0.78, .output_cost_per_mtok = 1.61, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "lepton/base-1874", .provider = "lepton", .display = "Lepton Base 1874", .context_window = 77824, .max_output = 3072, .input_cost_per_mtok = 0.79, .output_cost_per_mtok = 1.63, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "deepinfra/preview-1875", .provider = "deepinfra", .display = "Deepinfra Preview 1875", .context_window = 81920, .max_output = 4096, .input_cost_per_mtok = 0.80, .output_cost_per_mtok = 1.65, .supports_tools = false, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "friendli/experimental-1876", .provider = "friendli", .display = "Friendli Experimental 1876", .context_window = 86016, .max_output = 5120, .input_cost_per_mtok = 0.81, .output_cost_per_mtok = 1.67, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = true, .family = "experimental" },
    .{ .id = "hyperbolic/stable-1877", .provider = "hyperbolic", .display = "Hyperbolic Stable 1877", .context_window = 90112, .max_output = 6144, .input_cost_per_mtok = 0.82, .output_cost_per_mtok = 1.69, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "stable" },
    .{ .id = "lambda/legacy-1878", .provider = "lambda", .display = "Lambda Legacy 1878", .context_window = 94208, .max_output = 7168, .input_cost_per_mtok = 0.83, .output_cost_per_mtok = 1.71, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nebius/edge-1879", .provider = "nebius", .display = "Nebius Edge 1879", .context_window = 98304, .max_output = 8192, .input_cost_per_mtok = 0.84, .output_cost_per_mtok = 1.73, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
    .{ .id = "openai/chat-1880", .provider = "openai", .display = "Openai Chat 1880", .context_window = 102400, .max_output = 9216, .input_cost_per_mtok = 0.85, .output_cost_per_mtok = 1.75, .supports_tools = true, .supports_vision = true, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "chat" },
    .{ .id = "anthropic/code-1881", .provider = "anthropic", .display = "Anthropic Code 1881", .context_window = 106496, .max_output = 10240, .input_cost_per_mtok = 0.86, .output_cost_per_mtok = 1.77, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "code" },
    .{ .id = "google/reason-1882", .provider = "google", .display = "Google Reason 1882", .context_window = 110592, .max_output = 11264, .input_cost_per_mtok = 0.87, .output_cost_per_mtok = 1.79, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "reason" },
    .{ .id = "groq/vision-1883", .provider = "groq", .display = "Groq Vision 1883", .context_window = 114688, .max_output = 12288, .input_cost_per_mtok = 0.88, .output_cost_per_mtok = 1.81, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "vision" },
    .{ .id = "xai/embed-1884", .provider = "xai", .display = "Xai Embed 1884", .context_window = 118784, .max_output = 13312, .input_cost_per_mtok = 0.89, .output_cost_per_mtok = 1.83, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "embed" },
    .{ .id = "deepseek/audio-1885", .provider = "deepseek", .display = "Deepseek Audio 1885", .context_window = 122880, .max_output = 14336, .input_cost_per_mtok = 0.90, .output_cost_per_mtok = 1.85, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "audio" },
    .{ .id = "mistral/fast-1886", .provider = "mistral", .display = "Mistral Fast 1886", .context_window = 126976, .max_output = 15360, .input_cost_per_mtok = 0.91, .output_cost_per_mtok = 1.87, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "fast" },
    .{ .id = "together/large-1887", .provider = "together", .display = "Together Large 1887", .context_window = 131072, .max_output = 16384, .input_cost_per_mtok = 0.92, .output_cost_per_mtok = 1.89, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "large" },
    .{ .id = "fireworks/mini-1888", .provider = "fireworks", .display = "Fireworks Mini 1888", .context_window = 4096, .max_output = 1024, .input_cost_per_mtok = 0.93, .output_cost_per_mtok = 1.91, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "mini" },
    .{ .id = "openrouter/nano-1889", .provider = "openrouter", .display = "Openrouter Nano 1889", .context_window = 8192, .max_output = 2048, .input_cost_per_mtok = 0.94, .output_cost_per_mtok = 1.93, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "nano" },
    .{ .id = "cerebras/pro-1890", .provider = "cerebras", .display = "Cerebras Pro 1890", .context_window = 12288, .max_output = 3072, .input_cost_per_mtok = 0.95, .output_cost_per_mtok = 1.95, .supports_tools = false, .supports_vision = true, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = true, .family = "pro" },
    .{ .id = "ollama/ultra-1891", .provider = "ollama", .display = "Ollama Ultra 1891", .context_window = 16384, .max_output = 4096, .input_cost_per_mtok = 0.96, .output_cost_per_mtok = 1.97, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "ultra" },
    .{ .id = "lmstudio/turbo-1892", .provider = "lmstudio", .display = "Lmstudio Turbo 1892", .context_window = 20480, .max_output = 5120, .input_cost_per_mtok = 0.97, .output_cost_per_mtok = 1.99, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "turbo" },
    .{ .id = "vllm/instruct-1893", .provider = "vllm", .display = "Vllm Instruct 1893", .context_window = 24576, .max_output = 6144, .input_cost_per_mtok = 0.98, .output_cost_per_mtok = 2.01, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "instruct" },
    .{ .id = "azure/base-1894", .provider = "azure", .display = "Azure Base 1894", .context_window = 28672, .max_output = 7168, .input_cost_per_mtok = 0.99, .output_cost_per_mtok = 2.03, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "base" },
    .{ .id = "bedrock/preview-1895", .provider = "bedrock", .display = "Bedrock Preview 1895", .context_window = 32768, .max_output = 8192, .input_cost_per_mtok = 1.00, .output_cost_per_mtok = 2.05, .supports_tools = true, .supports_vision = true, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "preview" },
    .{ .id = "vertex/experimental-1896", .provider = "vertex", .display = "Vertex Experimental 1896", .context_window = 36864, .max_output = 9216, .input_cost_per_mtok = 1.01, .output_cost_per_mtok = 2.07, .supports_tools = false, .supports_vision = false, .supports_streaming = true, .supports_json_mode = false, .supports_reasoning = false, .family = "experimental" },
    .{ .id = "perplexity/stable-1897", .provider = "perplexity", .display = "Perplexity Stable 1897", .context_window = 40960, .max_output = 10240, .input_cost_per_mtok = 1.02, .output_cost_per_mtok = 2.09, .supports_tools = true, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = true, .family = "stable" },
    .{ .id = "cohere/legacy-1898", .provider = "cohere", .display = "Cohere Legacy 1898", .context_window = 45056, .max_output = 11264, .input_cost_per_mtok = 1.03, .output_cost_per_mtok = 2.11, .supports_tools = true, .supports_vision = false, .supports_streaming = true, .supports_json_mode = true, .supports_reasoning = false, .family = "legacy" },
    .{ .id = "nvidia/edge-1899", .provider = "nvidia", .display = "Nvidia Edge 1899", .context_window = 49152, .max_output = 12288, .input_cost_per_mtok = 1.04, .output_cost_per_mtok = 2.13, .supports_tools = false, .supports_vision = false, .supports_streaming = false, .supports_json_mode = true, .supports_reasoning = false, .family = "edge" },
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

pub fn model_1800_id() []const u8 {
    return models[0].id;
}
pub fn model_1800_context() u32 {
    return models[0].context_window;
}
pub fn model_1800_supports_tools() bool {
    return models[0].supports_tools;
}
pub fn model_1800_family() []const u8 {
    return models[0].family;
}
pub fn model_1800_is_vision() bool {
    return models[0].supports_vision;
}

pub fn model_1801_id() []const u8 {
    return models[1].id;
}
pub fn model_1801_context() u32 {
    return models[1].context_window;
}
pub fn model_1801_supports_tools() bool {
    return models[1].supports_tools;
}
pub fn model_1801_family() []const u8 {
    return models[1].family;
}
pub fn model_1801_is_vision() bool {
    return models[1].supports_vision;
}

pub fn model_1802_id() []const u8 {
    return models[2].id;
}
pub fn model_1802_context() u32 {
    return models[2].context_window;
}
pub fn model_1802_supports_tools() bool {
    return models[2].supports_tools;
}
pub fn model_1802_family() []const u8 {
    return models[2].family;
}
pub fn model_1802_is_vision() bool {
    return models[2].supports_vision;
}

pub fn model_1803_id() []const u8 {
    return models[3].id;
}
pub fn model_1803_context() u32 {
    return models[3].context_window;
}
pub fn model_1803_supports_tools() bool {
    return models[3].supports_tools;
}
pub fn model_1803_family() []const u8 {
    return models[3].family;
}
pub fn model_1803_is_vision() bool {
    return models[3].supports_vision;
}

pub fn model_1804_id() []const u8 {
    return models[4].id;
}
pub fn model_1804_context() u32 {
    return models[4].context_window;
}
pub fn model_1804_supports_tools() bool {
    return models[4].supports_tools;
}
pub fn model_1804_family() []const u8 {
    return models[4].family;
}
pub fn model_1804_is_vision() bool {
    return models[4].supports_vision;
}

pub fn model_1805_id() []const u8 {
    return models[5].id;
}
pub fn model_1805_context() u32 {
    return models[5].context_window;
}
pub fn model_1805_supports_tools() bool {
    return models[5].supports_tools;
}
pub fn model_1805_family() []const u8 {
    return models[5].family;
}
pub fn model_1805_is_vision() bool {
    return models[5].supports_vision;
}

pub fn model_1806_id() []const u8 {
    return models[6].id;
}
pub fn model_1806_context() u32 {
    return models[6].context_window;
}
pub fn model_1806_supports_tools() bool {
    return models[6].supports_tools;
}
pub fn model_1806_family() []const u8 {
    return models[6].family;
}
pub fn model_1806_is_vision() bool {
    return models[6].supports_vision;
}

pub fn model_1807_id() []const u8 {
    return models[7].id;
}
pub fn model_1807_context() u32 {
    return models[7].context_window;
}
pub fn model_1807_supports_tools() bool {
    return models[7].supports_tools;
}
pub fn model_1807_family() []const u8 {
    return models[7].family;
}
pub fn model_1807_is_vision() bool {
    return models[7].supports_vision;
}

pub fn model_1808_id() []const u8 {
    return models[8].id;
}
pub fn model_1808_context() u32 {
    return models[8].context_window;
}
pub fn model_1808_supports_tools() bool {
    return models[8].supports_tools;
}
pub fn model_1808_family() []const u8 {
    return models[8].family;
}
pub fn model_1808_is_vision() bool {
    return models[8].supports_vision;
}

pub fn model_1809_id() []const u8 {
    return models[9].id;
}
pub fn model_1809_context() u32 {
    return models[9].context_window;
}
pub fn model_1809_supports_tools() bool {
    return models[9].supports_tools;
}
pub fn model_1809_family() []const u8 {
    return models[9].family;
}
pub fn model_1809_is_vision() bool {
    return models[9].supports_vision;
}

pub fn model_1810_id() []const u8 {
    return models[10].id;
}
pub fn model_1810_context() u32 {
    return models[10].context_window;
}
pub fn model_1810_supports_tools() bool {
    return models[10].supports_tools;
}
pub fn model_1810_family() []const u8 {
    return models[10].family;
}
pub fn model_1810_is_vision() bool {
    return models[10].supports_vision;
}

pub fn model_1811_id() []const u8 {
    return models[11].id;
}
pub fn model_1811_context() u32 {
    return models[11].context_window;
}
pub fn model_1811_supports_tools() bool {
    return models[11].supports_tools;
}
pub fn model_1811_family() []const u8 {
    return models[11].family;
}
pub fn model_1811_is_vision() bool {
    return models[11].supports_vision;
}

pub fn model_1812_id() []const u8 {
    return models[12].id;
}
pub fn model_1812_context() u32 {
    return models[12].context_window;
}
pub fn model_1812_supports_tools() bool {
    return models[12].supports_tools;
}
pub fn model_1812_family() []const u8 {
    return models[12].family;
}
pub fn model_1812_is_vision() bool {
    return models[12].supports_vision;
}

pub fn model_1813_id() []const u8 {
    return models[13].id;
}
pub fn model_1813_context() u32 {
    return models[13].context_window;
}
pub fn model_1813_supports_tools() bool {
    return models[13].supports_tools;
}
pub fn model_1813_family() []const u8 {
    return models[13].family;
}
pub fn model_1813_is_vision() bool {
    return models[13].supports_vision;
}

pub fn model_1814_id() []const u8 {
    return models[14].id;
}
pub fn model_1814_context() u32 {
    return models[14].context_window;
}
pub fn model_1814_supports_tools() bool {
    return models[14].supports_tools;
}
pub fn model_1814_family() []const u8 {
    return models[14].family;
}
pub fn model_1814_is_vision() bool {
    return models[14].supports_vision;
}

pub fn model_1815_id() []const u8 {
    return models[15].id;
}
pub fn model_1815_context() u32 {
    return models[15].context_window;
}
pub fn model_1815_supports_tools() bool {
    return models[15].supports_tools;
}
pub fn model_1815_family() []const u8 {
    return models[15].family;
}
pub fn model_1815_is_vision() bool {
    return models[15].supports_vision;
}

pub fn model_1816_id() []const u8 {
    return models[16].id;
}
pub fn model_1816_context() u32 {
    return models[16].context_window;
}
pub fn model_1816_supports_tools() bool {
    return models[16].supports_tools;
}
pub fn model_1816_family() []const u8 {
    return models[16].family;
}
pub fn model_1816_is_vision() bool {
    return models[16].supports_vision;
}

pub fn model_1817_id() []const u8 {
    return models[17].id;
}
pub fn model_1817_context() u32 {
    return models[17].context_window;
}
pub fn model_1817_supports_tools() bool {
    return models[17].supports_tools;
}
pub fn model_1817_family() []const u8 {
    return models[17].family;
}
pub fn model_1817_is_vision() bool {
    return models[17].supports_vision;
}

pub fn model_1818_id() []const u8 {
    return models[18].id;
}
pub fn model_1818_context() u32 {
    return models[18].context_window;
}
pub fn model_1818_supports_tools() bool {
    return models[18].supports_tools;
}
pub fn model_1818_family() []const u8 {
    return models[18].family;
}
pub fn model_1818_is_vision() bool {
    return models[18].supports_vision;
}

pub fn model_1819_id() []const u8 {
    return models[19].id;
}
pub fn model_1819_context() u32 {
    return models[19].context_window;
}
pub fn model_1819_supports_tools() bool {
    return models[19].supports_tools;
}
pub fn model_1819_family() []const u8 {
    return models[19].family;
}
pub fn model_1819_is_vision() bool {
    return models[19].supports_vision;
}

pub fn model_1820_id() []const u8 {
    return models[20].id;
}
pub fn model_1820_context() u32 {
    return models[20].context_window;
}
pub fn model_1820_supports_tools() bool {
    return models[20].supports_tools;
}
pub fn model_1820_family() []const u8 {
    return models[20].family;
}
pub fn model_1820_is_vision() bool {
    return models[20].supports_vision;
}

pub fn model_1821_id() []const u8 {
    return models[21].id;
}
pub fn model_1821_context() u32 {
    return models[21].context_window;
}
pub fn model_1821_supports_tools() bool {
    return models[21].supports_tools;
}
pub fn model_1821_family() []const u8 {
    return models[21].family;
}
pub fn model_1821_is_vision() bool {
    return models[21].supports_vision;
}

pub fn model_1822_id() []const u8 {
    return models[22].id;
}
pub fn model_1822_context() u32 {
    return models[22].context_window;
}
pub fn model_1822_supports_tools() bool {
    return models[22].supports_tools;
}
pub fn model_1822_family() []const u8 {
    return models[22].family;
}
pub fn model_1822_is_vision() bool {
    return models[22].supports_vision;
}

pub fn model_1823_id() []const u8 {
    return models[23].id;
}
pub fn model_1823_context() u32 {
    return models[23].context_window;
}
pub fn model_1823_supports_tools() bool {
    return models[23].supports_tools;
}
pub fn model_1823_family() []const u8 {
    return models[23].family;
}
pub fn model_1823_is_vision() bool {
    return models[23].supports_vision;
}

pub fn model_1824_id() []const u8 {
    return models[24].id;
}
pub fn model_1824_context() u32 {
    return models[24].context_window;
}
pub fn model_1824_supports_tools() bool {
    return models[24].supports_tools;
}
pub fn model_1824_family() []const u8 {
    return models[24].family;
}
pub fn model_1824_is_vision() bool {
    return models[24].supports_vision;
}

pub fn model_1825_id() []const u8 {
    return models[25].id;
}
pub fn model_1825_context() u32 {
    return models[25].context_window;
}
pub fn model_1825_supports_tools() bool {
    return models[25].supports_tools;
}
pub fn model_1825_family() []const u8 {
    return models[25].family;
}
pub fn model_1825_is_vision() bool {
    return models[25].supports_vision;
}

pub fn model_1826_id() []const u8 {
    return models[26].id;
}
pub fn model_1826_context() u32 {
    return models[26].context_window;
}
pub fn model_1826_supports_tools() bool {
    return models[26].supports_tools;
}
pub fn model_1826_family() []const u8 {
    return models[26].family;
}
pub fn model_1826_is_vision() bool {
    return models[26].supports_vision;
}

pub fn model_1827_id() []const u8 {
    return models[27].id;
}
pub fn model_1827_context() u32 {
    return models[27].context_window;
}
pub fn model_1827_supports_tools() bool {
    return models[27].supports_tools;
}
pub fn model_1827_family() []const u8 {
    return models[27].family;
}
pub fn model_1827_is_vision() bool {
    return models[27].supports_vision;
}

pub fn model_1828_id() []const u8 {
    return models[28].id;
}
pub fn model_1828_context() u32 {
    return models[28].context_window;
}
pub fn model_1828_supports_tools() bool {
    return models[28].supports_tools;
}
pub fn model_1828_family() []const u8 {
    return models[28].family;
}
pub fn model_1828_is_vision() bool {
    return models[28].supports_vision;
}

pub fn model_1829_id() []const u8 {
    return models[29].id;
}
pub fn model_1829_context() u32 {
    return models[29].context_window;
}
pub fn model_1829_supports_tools() bool {
    return models[29].supports_tools;
}
pub fn model_1829_family() []const u8 {
    return models[29].family;
}
pub fn model_1829_is_vision() bool {
    return models[29].supports_vision;
}

pub fn model_1830_id() []const u8 {
    return models[30].id;
}
pub fn model_1830_context() u32 {
    return models[30].context_window;
}
pub fn model_1830_supports_tools() bool {
    return models[30].supports_tools;
}
pub fn model_1830_family() []const u8 {
    return models[30].family;
}
pub fn model_1830_is_vision() bool {
    return models[30].supports_vision;
}

pub fn model_1831_id() []const u8 {
    return models[31].id;
}
pub fn model_1831_context() u32 {
    return models[31].context_window;
}
pub fn model_1831_supports_tools() bool {
    return models[31].supports_tools;
}
pub fn model_1831_family() []const u8 {
    return models[31].family;
}
pub fn model_1831_is_vision() bool {
    return models[31].supports_vision;
}

pub fn model_1832_id() []const u8 {
    return models[32].id;
}
pub fn model_1832_context() u32 {
    return models[32].context_window;
}
pub fn model_1832_supports_tools() bool {
    return models[32].supports_tools;
}
pub fn model_1832_family() []const u8 {
    return models[32].family;
}
pub fn model_1832_is_vision() bool {
    return models[32].supports_vision;
}

pub fn model_1833_id() []const u8 {
    return models[33].id;
}
pub fn model_1833_context() u32 {
    return models[33].context_window;
}
pub fn model_1833_supports_tools() bool {
    return models[33].supports_tools;
}
pub fn model_1833_family() []const u8 {
    return models[33].family;
}
pub fn model_1833_is_vision() bool {
    return models[33].supports_vision;
}

pub fn model_1834_id() []const u8 {
    return models[34].id;
}
pub fn model_1834_context() u32 {
    return models[34].context_window;
}
pub fn model_1834_supports_tools() bool {
    return models[34].supports_tools;
}
pub fn model_1834_family() []const u8 {
    return models[34].family;
}
pub fn model_1834_is_vision() bool {
    return models[34].supports_vision;
}

pub fn model_1835_id() []const u8 {
    return models[35].id;
}
pub fn model_1835_context() u32 {
    return models[35].context_window;
}
pub fn model_1835_supports_tools() bool {
    return models[35].supports_tools;
}
pub fn model_1835_family() []const u8 {
    return models[35].family;
}
pub fn model_1835_is_vision() bool {
    return models[35].supports_vision;
}

pub fn model_1836_id() []const u8 {
    return models[36].id;
}
pub fn model_1836_context() u32 {
    return models[36].context_window;
}
pub fn model_1836_supports_tools() bool {
    return models[36].supports_tools;
}
pub fn model_1836_family() []const u8 {
    return models[36].family;
}
pub fn model_1836_is_vision() bool {
    return models[36].supports_vision;
}

pub fn model_1837_id() []const u8 {
    return models[37].id;
}
pub fn model_1837_context() u32 {
    return models[37].context_window;
}
pub fn model_1837_supports_tools() bool {
    return models[37].supports_tools;
}
pub fn model_1837_family() []const u8 {
    return models[37].family;
}
pub fn model_1837_is_vision() bool {
    return models[37].supports_vision;
}

pub fn model_1838_id() []const u8 {
    return models[38].id;
}
pub fn model_1838_context() u32 {
    return models[38].context_window;
}
pub fn model_1838_supports_tools() bool {
    return models[38].supports_tools;
}
pub fn model_1838_family() []const u8 {
    return models[38].family;
}
pub fn model_1838_is_vision() bool {
    return models[38].supports_vision;
}

pub fn model_1839_id() []const u8 {
    return models[39].id;
}
pub fn model_1839_context() u32 {
    return models[39].context_window;
}
pub fn model_1839_supports_tools() bool {
    return models[39].supports_tools;
}
pub fn model_1839_family() []const u8 {
    return models[39].family;
}
pub fn model_1839_is_vision() bool {
    return models[39].supports_vision;
}

pub fn model_1840_id() []const u8 {
    return models[40].id;
}
pub fn model_1840_context() u32 {
    return models[40].context_window;
}
pub fn model_1840_supports_tools() bool {
    return models[40].supports_tools;
}
pub fn model_1840_family() []const u8 {
    return models[40].family;
}
pub fn model_1840_is_vision() bool {
    return models[40].supports_vision;
}

pub fn model_1841_id() []const u8 {
    return models[41].id;
}
pub fn model_1841_context() u32 {
    return models[41].context_window;
}
pub fn model_1841_supports_tools() bool {
    return models[41].supports_tools;
}
pub fn model_1841_family() []const u8 {
    return models[41].family;
}
pub fn model_1841_is_vision() bool {
    return models[41].supports_vision;
}

pub fn model_1842_id() []const u8 {
    return models[42].id;
}
pub fn model_1842_context() u32 {
    return models[42].context_window;
}
pub fn model_1842_supports_tools() bool {
    return models[42].supports_tools;
}
pub fn model_1842_family() []const u8 {
    return models[42].family;
}
pub fn model_1842_is_vision() bool {
    return models[42].supports_vision;
}

pub fn model_1843_id() []const u8 {
    return models[43].id;
}
pub fn model_1843_context() u32 {
    return models[43].context_window;
}
pub fn model_1843_supports_tools() bool {
    return models[43].supports_tools;
}
pub fn model_1843_family() []const u8 {
    return models[43].family;
}
pub fn model_1843_is_vision() bool {
    return models[43].supports_vision;
}

pub fn model_1844_id() []const u8 {
    return models[44].id;
}
pub fn model_1844_context() u32 {
    return models[44].context_window;
}
pub fn model_1844_supports_tools() bool {
    return models[44].supports_tools;
}
pub fn model_1844_family() []const u8 {
    return models[44].family;
}
pub fn model_1844_is_vision() bool {
    return models[44].supports_vision;
}

pub fn model_1845_id() []const u8 {
    return models[45].id;
}
pub fn model_1845_context() u32 {
    return models[45].context_window;
}
pub fn model_1845_supports_tools() bool {
    return models[45].supports_tools;
}
pub fn model_1845_family() []const u8 {
    return models[45].family;
}
pub fn model_1845_is_vision() bool {
    return models[45].supports_vision;
}

pub fn model_1846_id() []const u8 {
    return models[46].id;
}
pub fn model_1846_context() u32 {
    return models[46].context_window;
}
pub fn model_1846_supports_tools() bool {
    return models[46].supports_tools;
}
pub fn model_1846_family() []const u8 {
    return models[46].family;
}
pub fn model_1846_is_vision() bool {
    return models[46].supports_vision;
}

pub fn model_1847_id() []const u8 {
    return models[47].id;
}
pub fn model_1847_context() u32 {
    return models[47].context_window;
}
pub fn model_1847_supports_tools() bool {
    return models[47].supports_tools;
}
pub fn model_1847_family() []const u8 {
    return models[47].family;
}
pub fn model_1847_is_vision() bool {
    return models[47].supports_vision;
}

pub fn model_1848_id() []const u8 {
    return models[48].id;
}
pub fn model_1848_context() u32 {
    return models[48].context_window;
}
pub fn model_1848_supports_tools() bool {
    return models[48].supports_tools;
}
pub fn model_1848_family() []const u8 {
    return models[48].family;
}
pub fn model_1848_is_vision() bool {
    return models[48].supports_vision;
}

pub fn model_1849_id() []const u8 {
    return models[49].id;
}
pub fn model_1849_context() u32 {
    return models[49].context_window;
}
pub fn model_1849_supports_tools() bool {
    return models[49].supports_tools;
}
pub fn model_1849_family() []const u8 {
    return models[49].family;
}
pub fn model_1849_is_vision() bool {
    return models[49].supports_vision;
}

pub fn model_1850_id() []const u8 {
    return models[50].id;
}
pub fn model_1850_context() u32 {
    return models[50].context_window;
}
pub fn model_1850_supports_tools() bool {
    return models[50].supports_tools;
}
pub fn model_1850_family() []const u8 {
    return models[50].family;
}
pub fn model_1850_is_vision() bool {
    return models[50].supports_vision;
}

pub fn model_1851_id() []const u8 {
    return models[51].id;
}
pub fn model_1851_context() u32 {
    return models[51].context_window;
}
pub fn model_1851_supports_tools() bool {
    return models[51].supports_tools;
}
pub fn model_1851_family() []const u8 {
    return models[51].family;
}
pub fn model_1851_is_vision() bool {
    return models[51].supports_vision;
}

pub fn model_1852_id() []const u8 {
    return models[52].id;
}
pub fn model_1852_context() u32 {
    return models[52].context_window;
}
pub fn model_1852_supports_tools() bool {
    return models[52].supports_tools;
}
pub fn model_1852_family() []const u8 {
    return models[52].family;
}
pub fn model_1852_is_vision() bool {
    return models[52].supports_vision;
}

pub fn model_1853_id() []const u8 {
    return models[53].id;
}
pub fn model_1853_context() u32 {
    return models[53].context_window;
}
pub fn model_1853_supports_tools() bool {
    return models[53].supports_tools;
}
pub fn model_1853_family() []const u8 {
    return models[53].family;
}
pub fn model_1853_is_vision() bool {
    return models[53].supports_vision;
}

pub fn model_1854_id() []const u8 {
    return models[54].id;
}
pub fn model_1854_context() u32 {
    return models[54].context_window;
}
pub fn model_1854_supports_tools() bool {
    return models[54].supports_tools;
}
pub fn model_1854_family() []const u8 {
    return models[54].family;
}
pub fn model_1854_is_vision() bool {
    return models[54].supports_vision;
}

pub fn model_1855_id() []const u8 {
    return models[55].id;
}
pub fn model_1855_context() u32 {
    return models[55].context_window;
}
pub fn model_1855_supports_tools() bool {
    return models[55].supports_tools;
}
pub fn model_1855_family() []const u8 {
    return models[55].family;
}
pub fn model_1855_is_vision() bool {
    return models[55].supports_vision;
}

pub fn model_1856_id() []const u8 {
    return models[56].id;
}
pub fn model_1856_context() u32 {
    return models[56].context_window;
}
pub fn model_1856_supports_tools() bool {
    return models[56].supports_tools;
}
pub fn model_1856_family() []const u8 {
    return models[56].family;
}
pub fn model_1856_is_vision() bool {
    return models[56].supports_vision;
}

pub fn model_1857_id() []const u8 {
    return models[57].id;
}
pub fn model_1857_context() u32 {
    return models[57].context_window;
}
pub fn model_1857_supports_tools() bool {
    return models[57].supports_tools;
}
pub fn model_1857_family() []const u8 {
    return models[57].family;
}
pub fn model_1857_is_vision() bool {
    return models[57].supports_vision;
}

pub fn model_1858_id() []const u8 {
    return models[58].id;
}
pub fn model_1858_context() u32 {
    return models[58].context_window;
}
pub fn model_1858_supports_tools() bool {
    return models[58].supports_tools;
}
pub fn model_1858_family() []const u8 {
    return models[58].family;
}
pub fn model_1858_is_vision() bool {
    return models[58].supports_vision;
}

pub fn model_1859_id() []const u8 {
    return models[59].id;
}
pub fn model_1859_context() u32 {
    return models[59].context_window;
}
pub fn model_1859_supports_tools() bool {
    return models[59].supports_tools;
}
pub fn model_1859_family() []const u8 {
    return models[59].family;
}
pub fn model_1859_is_vision() bool {
    return models[59].supports_vision;
}

pub fn model_1860_id() []const u8 {
    return models[60].id;
}
pub fn model_1860_context() u32 {
    return models[60].context_window;
}
pub fn model_1860_supports_tools() bool {
    return models[60].supports_tools;
}
pub fn model_1860_family() []const u8 {
    return models[60].family;
}
pub fn model_1860_is_vision() bool {
    return models[60].supports_vision;
}

pub fn model_1861_id() []const u8 {
    return models[61].id;
}
pub fn model_1861_context() u32 {
    return models[61].context_window;
}
pub fn model_1861_supports_tools() bool {
    return models[61].supports_tools;
}
pub fn model_1861_family() []const u8 {
    return models[61].family;
}
pub fn model_1861_is_vision() bool {
    return models[61].supports_vision;
}

pub fn model_1862_id() []const u8 {
    return models[62].id;
}
pub fn model_1862_context() u32 {
    return models[62].context_window;
}
pub fn model_1862_supports_tools() bool {
    return models[62].supports_tools;
}
pub fn model_1862_family() []const u8 {
    return models[62].family;
}
pub fn model_1862_is_vision() bool {
    return models[62].supports_vision;
}

pub fn model_1863_id() []const u8 {
    return models[63].id;
}
pub fn model_1863_context() u32 {
    return models[63].context_window;
}
pub fn model_1863_supports_tools() bool {
    return models[63].supports_tools;
}
pub fn model_1863_family() []const u8 {
    return models[63].family;
}
pub fn model_1863_is_vision() bool {
    return models[63].supports_vision;
}

pub fn model_1864_id() []const u8 {
    return models[64].id;
}
pub fn model_1864_context() u32 {
    return models[64].context_window;
}
pub fn model_1864_supports_tools() bool {
    return models[64].supports_tools;
}
pub fn model_1864_family() []const u8 {
    return models[64].family;
}
pub fn model_1864_is_vision() bool {
    return models[64].supports_vision;
}

pub fn model_1865_id() []const u8 {
    return models[65].id;
}
pub fn model_1865_context() u32 {
    return models[65].context_window;
}
pub fn model_1865_supports_tools() bool {
    return models[65].supports_tools;
}
pub fn model_1865_family() []const u8 {
    return models[65].family;
}
pub fn model_1865_is_vision() bool {
    return models[65].supports_vision;
}

pub fn model_1866_id() []const u8 {
    return models[66].id;
}
pub fn model_1866_context() u32 {
    return models[66].context_window;
}
pub fn model_1866_supports_tools() bool {
    return models[66].supports_tools;
}
pub fn model_1866_family() []const u8 {
    return models[66].family;
}
pub fn model_1866_is_vision() bool {
    return models[66].supports_vision;
}

pub fn model_1867_id() []const u8 {
    return models[67].id;
}
pub fn model_1867_context() u32 {
    return models[67].context_window;
}
pub fn model_1867_supports_tools() bool {
    return models[67].supports_tools;
}
pub fn model_1867_family() []const u8 {
    return models[67].family;
}
pub fn model_1867_is_vision() bool {
    return models[67].supports_vision;
}

pub fn model_1868_id() []const u8 {
    return models[68].id;
}
pub fn model_1868_context() u32 {
    return models[68].context_window;
}
pub fn model_1868_supports_tools() bool {
    return models[68].supports_tools;
}
pub fn model_1868_family() []const u8 {
    return models[68].family;
}
pub fn model_1868_is_vision() bool {
    return models[68].supports_vision;
}

pub fn model_1869_id() []const u8 {
    return models[69].id;
}
pub fn model_1869_context() u32 {
    return models[69].context_window;
}
pub fn model_1869_supports_tools() bool {
    return models[69].supports_tools;
}
pub fn model_1869_family() []const u8 {
    return models[69].family;
}
pub fn model_1869_is_vision() bool {
    return models[69].supports_vision;
}

pub fn model_1870_id() []const u8 {
    return models[70].id;
}
pub fn model_1870_context() u32 {
    return models[70].context_window;
}
pub fn model_1870_supports_tools() bool {
    return models[70].supports_tools;
}
pub fn model_1870_family() []const u8 {
    return models[70].family;
}
pub fn model_1870_is_vision() bool {
    return models[70].supports_vision;
}

pub fn model_1871_id() []const u8 {
    return models[71].id;
}
pub fn model_1871_context() u32 {
    return models[71].context_window;
}
pub fn model_1871_supports_tools() bool {
    return models[71].supports_tools;
}
pub fn model_1871_family() []const u8 {
    return models[71].family;
}
pub fn model_1871_is_vision() bool {
    return models[71].supports_vision;
}

pub fn model_1872_id() []const u8 {
    return models[72].id;
}
pub fn model_1872_context() u32 {
    return models[72].context_window;
}
pub fn model_1872_supports_tools() bool {
    return models[72].supports_tools;
}
pub fn model_1872_family() []const u8 {
    return models[72].family;
}
pub fn model_1872_is_vision() bool {
    return models[72].supports_vision;
}

pub fn model_1873_id() []const u8 {
    return models[73].id;
}
pub fn model_1873_context() u32 {
    return models[73].context_window;
}
pub fn model_1873_supports_tools() bool {
    return models[73].supports_tools;
}
pub fn model_1873_family() []const u8 {
    return models[73].family;
}
pub fn model_1873_is_vision() bool {
    return models[73].supports_vision;
}

pub fn model_1874_id() []const u8 {
    return models[74].id;
}
pub fn model_1874_context() u32 {
    return models[74].context_window;
}
pub fn model_1874_supports_tools() bool {
    return models[74].supports_tools;
}
pub fn model_1874_family() []const u8 {
    return models[74].family;
}
pub fn model_1874_is_vision() bool {
    return models[74].supports_vision;
}

pub fn model_1875_id() []const u8 {
    return models[75].id;
}
pub fn model_1875_context() u32 {
    return models[75].context_window;
}
pub fn model_1875_supports_tools() bool {
    return models[75].supports_tools;
}
pub fn model_1875_family() []const u8 {
    return models[75].family;
}
pub fn model_1875_is_vision() bool {
    return models[75].supports_vision;
}

pub fn model_1876_id() []const u8 {
    return models[76].id;
}
pub fn model_1876_context() u32 {
    return models[76].context_window;
}
pub fn model_1876_supports_tools() bool {
    return models[76].supports_tools;
}
pub fn model_1876_family() []const u8 {
    return models[76].family;
}
pub fn model_1876_is_vision() bool {
    return models[76].supports_vision;
}

pub fn model_1877_id() []const u8 {
    return models[77].id;
}
pub fn model_1877_context() u32 {
    return models[77].context_window;
}
pub fn model_1877_supports_tools() bool {
    return models[77].supports_tools;
}
pub fn model_1877_family() []const u8 {
    return models[77].family;
}
pub fn model_1877_is_vision() bool {
    return models[77].supports_vision;
}

pub fn model_1878_id() []const u8 {
    return models[78].id;
}
pub fn model_1878_context() u32 {
    return models[78].context_window;
}
pub fn model_1878_supports_tools() bool {
    return models[78].supports_tools;
}
pub fn model_1878_family() []const u8 {
    return models[78].family;
}
pub fn model_1878_is_vision() bool {
    return models[78].supports_vision;
}

pub fn model_1879_id() []const u8 {
    return models[79].id;
}
pub fn model_1879_context() u32 {
    return models[79].context_window;
}
pub fn model_1879_supports_tools() bool {
    return models[79].supports_tools;
}
pub fn model_1879_family() []const u8 {
    return models[79].family;
}
pub fn model_1879_is_vision() bool {
    return models[79].supports_vision;
}

test "shard 18 count and lookup" {
    try std.testing.expect(count() == 100);
    const first = get(0).?;
    try std.testing.expect(findById(first.id) != null);
    try std.testing.expect(maxContextInShard() >= first.context_window);
    var buf: [64]ModelMeta = undefined;
    const n = filterToolsCapable(&buf);
    try std.testing.expect(n <= 64);
    _ = estimateCostUsd(first.id, 1000, 500);
}

