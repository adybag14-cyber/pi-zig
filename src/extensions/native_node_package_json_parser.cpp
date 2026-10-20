// Selected native GetPackageJSON parse loop from Node v24.13.0 node_modules.cc.
// Exact original: 26C1741820F992983DE87A5EDBE8274B9FFDFF348F988E4D44586B8809EAA414.
// Physical reads, path/cache ownership, native error construction and the JS
// modules-binding publication are separate owners. This file owns no JS roots.
#include "native_node_package_json_parser.h"
#include "native_simdjson_memory.hpp"
#include "../../vendor/node-v24.13.0/simdjson-owned/simdjson.h"
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string_view>

namespace {
struct Bytes final {
  char* data = nullptr;
  std::size_t length = 0;
  std::size_t capacity = 0;
  bool present = false;

  Bytes() noexcept = default;
  Bytes(const Bytes&) = delete;
  Bytes& operator=(const Bytes&) = delete;
  ~Bytes() noexcept { pi_simd::release(data); }

  bool reserve(std::size_t requested) noexcept {
    if (requested <= capacity) return true;
    if (requested == std::numeric_limits<std::size_t>::max()) {
      pi_simd::allocationFailure();
      return false;
    }
    auto* next = static_cast<char*>(pi_simd::allocate(requested + 1));
    if (!next) return false;
    // Every successful growth owns its real old/new overlap until this release.
    pi_simd::release(data);
    data = next;
    capacity = requested;
    return true;
  }
  bool assign(std::string_view value) noexcept {
    if (!reserve(value.size())) return false;
    if (!value.empty()) std::memcpy(data, value.data(), value.size());
    if (data) data[value.size()] = '\0';
    length = value.size();
    present = true;
    return true;
  }
  PiNodePackageJsonSpan view() const noexcept {
    return {present ? (data ? data : "") : nullptr, length, present ? 1 : 0};
  }
};

// This is the actual simdjson::pad algorithm over the owned native byte buffer:
// only ASCII JSON whitespace at the end supplies existing padding. Appended
// spaces remain in the retained raw bytes, but the parser sees original length.
bool paddedInput(Bytes& raw, const uint8_t* input, std::size_t length) noexcept {
  std::size_t existing_padding = 0;
  for (std::size_t i = length; i > 0; --i) {
    const uint8_t c = input[i - 1];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') ++existing_padding;
    else break;
  }
  const std::size_t needed_padding = existing_padding < simdjson::SIMDJSON_PADDING
      ? simdjson::SIMDJSON_PADDING - existing_padding : 0;
  if (length > std::numeric_limits<std::size_t>::max() - needed_padding) {
    pi_simd::allocationFailure();
    return false;
  }
  const std::size_t total = length + needed_padding;
  if (!raw.reserve(total)) return false;
  if (length) std::memcpy(raw.data, input, length);
  if (needed_padding) std::memset(raw.data + length, ' ', needed_padding);
  raw.data[total] = '\0';
  raw.length = total;
  raw.present = true;
  return true;
}

enum class Kind { none, commonjs, module };
PiNodePackageJsonSpan kindView(Kind kind) noexcept {
  switch (kind) {
    case Kind::commonjs: return {"commonjs", 8, 1};
    case Kind::module: return {"module", 6, 1};
    case Kind::none: return {"none", 4, 1};
  }
  std::abort();
}
}  // namespace

struct PiNodePackageJsonParser final {
  // Borrowed from this object's independent charged Allocation prefix.
  void* memory_owner;
  simdjson::ondemand::parser parser;
  bool storage_ready = false;
  bool allocation_failed = false;
  explicit PiNodePackageJsonParser(void* owner) noexcept : memory_owner(owner) {}
};
struct PiNodePackageJsonConfig final {
  Bytes name;
  Bytes main;
  Kind type = Kind::none;
  Bytes exports;
  Bytes imports;
  Bytes scripts;
  Bytes raw_json;
};
static_assert(alignof(PiNodePackageJsonParser) <= alignof(std::max_align_t),
              "parser owner exceeds native allocation alignment");
static_assert(alignof(PiNodePackageJsonConfig) <= alignof(std::max_align_t),
              "config owner exceeds native allocation alignment");

namespace {
struct ConfigDelete {
  void operator()(PiNodePackageJsonConfig* config) const noexcept {
    pi_node_package_json_config_destroy(config);
  }
};

int parseBody(PiNodePackageJsonParser* owner, pi_simd::Scope& allocations,
              const uint8_t* input, std::size_t length,
              PiNodePackageJsonConfig** output, bool retain_invalid) noexcept {
  void* memory = pi_simd::allocate(sizeof(PiNodePackageJsonConfig));
  if (!memory) return PI_NODE_PACKAGE_JSON_MEMORY;
  std::unique_ptr<PiNodePackageJsonConfig, ConfigDelete> config(
      ::new (memory) PiNodePackageJsonConfig());
  // Node raises ERR_INVALID_PACKAGE_CONFIG before its stack PackageConfig is
  // destroyed. Only the binding entry transfers that actual partial owner;
  // the raw parser entry keeps its original null-on-failure contract.
  const auto invalid = [&]() noexcept {
    if (retain_invalid) *output = config.release();
    return PI_NODE_PACKAGE_JSON_INVALID;
  };
  if (!paddedInput(config->raw_json, input, length))
    return PI_NODE_PACKAGE_JSON_MEMORY;

  simdjson::padded_string_view json(config->raw_json.data, length,
                                   config->raw_json.length);
  // The original iterate removes exactly one BOM before deciding capacity.
  // Inspect a copy only for allocation size, then pass the original view to
  // iterate so a second leading BOM is not silently removed.
  auto allocation_view = json;
  allocation_view.remove_utf8_bom();
  if (!owner->storage_ready || owner->parser.capacity() < allocation_view.length()) {
    const auto error = owner->parser.allocate(allocation_view.length(),
                                              owner->parser.max_depth());
    // Original allocate can report SUCCESS after a missing string/development
    // buffer. Observe the real allocation producer before iterate can use it.
    if (allocations.failed()) {
      owner->storage_ready = false;
      return PI_NODE_PACKAGE_JSON_MEMORY;
    }
    if (error) {
      if (error != simdjson::CAPACITY) owner->storage_ready = false;
      return invalid();
    }
    owner->storage_ready = true;
  }

  simdjson::ondemand::document document;
  simdjson::ondemand::object main_object;
  const auto error = owner->parser.iterate(json).get(document);
  if (allocations.failed()) return PI_NODE_PACKAGE_JSON_MEMORY;
  if (error || document.get_object().get(main_object))
    return invalid();

  simdjson::ondemand::raw_json_string key;
  simdjson::ondemand::value value;
  std::string_view field_value;
  simdjson::ondemand::json_type field_type;
  for (auto field : main_object) {
    if (field.key().get(key) || field.value().get(value))
      return invalid();
    if (key.raw() == nullptr) continue;

    if (key == "name") {
      // The selected get_string(receiver) is get_string().get(view), then
      // receiver = view. Preserve that sequence with an explicit checked copy.
      if (value.get_string().get(field_value))
        return invalid();
      if (!config->name.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
    } else if (key == "main") {
      // Original USE ignores the parser error and preserves an earlier main.
      if (!value.get_string().get(field_value)) {
        if (!config->main.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
      }
    } else if (key == "exports") {
      if (value.type().get(field_type)) return invalid();
      switch (field_type) {
        case simdjson::ondemand::json_type::object:
        case simdjson::ondemand::json_type::array:
          if (value.raw_json().get(field_value)) return invalid();
          if (!config->exports.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
          break;
        case simdjson::ondemand::json_type::string:
          if (value.get_string().get(field_value)) return invalid();
          if (!config->exports.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
          break;
        default: break;
      }
    } else if (key == "imports") {
      if (value.type().get(field_type)) return invalid();
      switch (field_type) {
        case simdjson::ondemand::json_type::array:
        case simdjson::ondemand::json_type::object:
          if (value.raw_json().get(field_value)) return invalid();
          if (!config->imports.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
          break;
        case simdjson::ondemand::json_type::string:
          if (value.get_string().get(field_value)) return invalid();
          if (!config->imports.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
          break;
        default: break;
      }
    } else if (key == "type") {
      if (value.get_string().get(field_value)) return invalid();
      if (field_value == "commonjs") config->type = Kind::commonjs;
      else if (field_value == "module") config->type = Kind::module;
    } else if (key == "scripts") {
      if (value.type().get(field_type)) return invalid();
      switch (field_type) {
        case simdjson::ondemand::json_type::object:
          if (value.raw_json().get(field_value)) return invalid();
          if (!config->scripts.assign(field_value)) return PI_NODE_PACKAGE_JSON_MEMORY;
          break;
        default: break;
      }
    }
  }
  *output = config.release();
  return PI_NODE_PACKAGE_JSON_OK;
}
}  // namespace

extern "C" PiNodePackageJsonParser* pi_node_package_json_parser_create(void* memory_owner) {
  pi_simd::Scope allocations(memory_owner);
  void* memory = pi_simd::allocate(sizeof(PiNodePackageJsonParser));
  if (!memory) return nullptr;
  return ::new (memory) PiNodePackageJsonParser(memory_owner);
}
extern "C" void pi_node_package_json_parser_destroy(PiNodePackageJsonParser* parser) {
  if (!parser) return;
  parser->~PiNodePackageJsonParser();
  pi_simd::release(parser);
}
namespace {
int parseResult(PiNodePackageJsonParser* parser,
                const uint8_t* input, size_t length,
                PiNodePackageJsonConfig** output, bool retain_invalid) noexcept {
  *output = nullptr;
  if (parser->allocation_failed) return PI_NODE_PACKAGE_JSON_MEMORY;
  pi_simd::Scope allocations(parser->memory_owner);
  const int result = parseBody(parser, allocations, input, length, output, retain_invalid);
  if (allocations.failed()) {
    parser->allocation_failed = true;
    pi_node_package_json_config_destroy(*output);
    *output = nullptr;
    return PI_NODE_PACKAGE_JSON_MEMORY;
  }
  return result;
}
}  // namespace

extern "C" int pi_node_package_json_parse(PiNodePackageJsonParser* parser,
                                         const uint8_t* input, size_t length,
                                         PiNodePackageJsonConfig** output) {
  return parseResult(parser, input, length, output, false);
}
extern "C" int pi_node_package_json_parse_retained(PiNodePackageJsonParser* parser,
                                                  const uint8_t* input, size_t length,
                                                  PiNodePackageJsonConfig** output) {
  return parseResult(parser, input, length, output, true);
}
extern "C" void pi_node_package_json_config_views(const PiNodePackageJsonConfig* config,
                                                  PiNodePackageJsonViews* output) {
  *output = {config->name.view(), config->main.view(), kindView(config->type),
             config->imports.view(), config->exports.view(), config->scripts.view(),
             config->raw_json.view()};
}
extern "C" void pi_node_package_json_config_destroy(PiNodePackageJsonConfig* config) {
  if (!config) return;
  config->~PiNodePackageJsonConfig();
  pi_simd::release(config);
}
