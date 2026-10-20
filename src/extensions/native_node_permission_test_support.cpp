#include "native_node_permission_test_support.h"
#include "native_node_native_debug_internal.hpp"
#include "uv.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#if defined(_WIN32)
#include <io.h>
#include <fcntl.h>
#else
#include <unistd.h>
#endif
namespace {
struct File {
  FILE* value;
  explicit File(FILE* input) : value(input) {}
  ~File() { if (value) fclose(value); }
};
int ReadOutput(FILE* file, PiNativeOutputObservation* output) {
  if (fflush(file) != 0 || fseek(file, 0, SEEK_SET) != 0) {
    output->io_error = 1; return -1;
  }
  output->length = fread(output->bytes, 1, sizeof(output->bytes), file);
  if (ferror(file)) { output->io_error = 1; return -1; }
  if (output->length == sizeof(output->bytes)) {
    const int tail = fgetc(file);
    output->overflow = tail != EOF;
    if (ferror(file)) { output->io_error = 1; return -1; }
  }
  return 0;
}
#if defined(_WIN32)
int NativeFileno(FILE* file) { return _fileno(file); }
int NativeDup(int fd) { return _dup(fd); }
int NativeDup2(int from, int to) { return _dup2(from, to); }
void NativeClose(int fd) { _close(fd); }
#else
int NativeFileno(FILE* file) { return fileno(file); }
int NativeDup(int fd) { return dup(fd); }
int NativeDup2(int from, int to) { return dup2(from, to); }
void NativeClose(int fd) { close(fd); }
#endif
struct UvTracker {
  struct Block { void* pointer; size_t bytes; };
  Block blocks[256]{};
  size_t count = 0;
  PiPermissionUvAllocationObservation* observation;
  static UvTracker* current;
  explicit UvTracker(PiPermissionUvAllocationObservation* value)
      : observation(value) {}
  void add(void* pointer, size_t bytes) {
    if (!pointer) return;
    if (count == 256) std::abort();  // bounded synchronous stat invariant
    blocks[count++] = {pointer, bytes};
    ++observation->allocations;
    if (count > observation->peak_blocks) observation->peak_blocks = count;
  }
  size_t find(void* pointer) const {
    for (size_t i = 0; i < count; ++i)
      if (blocks[i].pointer == pointer) return i;
    return count;
  }
  void removed(void* pointer) {
    if (!pointer) return;
    const size_t at = find(pointer);
    if (at == count) { ++observation->untracked_frees; return; }
    blocks[at] = blocks[--count];
    ++observation->frees;
  }
  static void* allocate(size_t bytes) {
    if (current->count == 256) {
      current->observation->overflow = 1; return nullptr;
    }
    void* pointer = std::malloc(bytes);
    current->add(pointer, bytes);
    return pointer;
  }
  static void* allocateZero(size_t count, size_t bytes) {
    if (current->count == 256 ||
        (bytes != 0 && count > std::numeric_limits<size_t>::max() / bytes)) {
      current->observation->overflow = 1; return nullptr;
    }
    void* pointer = std::calloc(count, bytes);
    current->add(pointer, count * bytes);
    return pointer;
  }
  static void* resize(void* pointer, size_t bytes) {
    if (!pointer) return allocate(bytes);
    if (bytes == 0) { release(pointer); return nullptr; }
    const size_t at = current->find(pointer);
    if (at == current->count && current->count == 256) {
      current->observation->overflow = 1; return nullptr;
    }
    void* replacement = std::realloc(pointer, bytes);
    if (replacement) {
      if (at < current->count)
        current->blocks[at] = {replacement, bytes};
      else
        current->add(replacement, bytes);
    }
    return replacement;
  }
  static void release(void* pointer) {
    current->removed(pointer);
    std::free(pointer);
  }
  void snapshotAndRetire() {
    observation->live_blocks_before_observer_cleanup = count;
    for (size_t i = 0; i < count; ++i)
      observation->live_bytes_before_observer_cleanup += blocks[i].bytes;
    // The sole synchronous native call has returned and its stack request is
    // gone. These otherwise leaked path blocks have no surviving UV owner.
    for (size_t i = 0; i < count; ++i) std::free(blocks[i].pointer);
    count = 0;
  }
};
UvTracker* UvTracker::current = nullptr;
}  // namespace
extern "C" void pi_native_debug_test_format(
    void* memory_owner, JSContext* context, int tree_line,
    const char* first, size_t first_length, const char* second,
    PiNodeEnvironmentValueVisitor visitor, void* user) {
  pi_node::AllocationScope scope(memory_owner);
  if (tree_line) {
    auto output = pi_node::debug::SPrintF(context, "%s%s\n", first, second);
    visitor(user, output.data(), output.size());
  } else {
    auto output = pi_node::debug::SPrintF(
        context, "Inserting %s\n",
        pi_node::debug::SizedString{first, first_length});
    visitor(user, output.data(), output.size());
  }
}
extern "C" int pi_native_debug_test_file_write(void* memory_owner,
    const char* bytes, size_t length, PiNativeOutputObservation* output) {
  *output = {};
  File file(tmpfile());
  if (!file.value) { output->io_error = 1; return -1; }
  pi_node::AllocationScope scope(memory_owner);
  const pi_node::EnvironmentString input(bytes, length);
  pi_node::debug::FWrite(file.value, input);
  return ReadOutput(file.value, output);
}
extern "C" int pi_native_debug_test_capture_stderr(
    PiNativePermissionTestAction action, void* user,
    PiNativeOutputObservation* output) {
  *output = {};
  File file(tmpfile());
  if (!file.value || fflush(stderr) != 0) {
    output->io_error = 1; return -1;
  }
  const int destination = NativeFileno(stderr);
  const int saved = NativeDup(destination);
  if (saved < 0) { output->io_error = 1; return -1; }
#if defined(_WIN32)
  const int former_mode = _setmode(destination, _O_BINARY);
  if (former_mode < 0) {
    NativeClose(saved); output->io_error = 1; return -1;
  }
#endif
  if (NativeDup2(NativeFileno(file.value), destination) < 0) {
#if defined(_WIN32)
    _setmode(destination, former_mode);
#endif
    NativeClose(saved); output->io_error = 1; return -1;
  }
#if defined(_WIN32)
  if (_setmode(destination, _O_BINARY) < 0) {
    NativeDup2(saved, destination); _setmode(destination, former_mode);
    NativeClose(saved); output->io_error = 1; return -1;
  }
#endif
  action(user);
  const int flush_result = fflush(stderr);
  const int restore_result = NativeDup2(saved, destination);
#if defined(_WIN32)
  const int mode_result = _setmode(destination, former_mode);
#else
  const int mode_result = 0;
#endif
  NativeClose(saved);
  if (flush_result != 0 || restore_result < 0 || mode_result < 0) {
    output->io_error = 1; return -1;
  }
  return ReadOutput(file.value, output);
}
extern "C" int pi_native_permission_test_directory_apply(
    PiNodePermission* permission, void* memory_owner,
    const PiNodePermissionEnvironment* environment,
    const char* absolute_directory, size_t length, int permission_scope,
    PiPermissionUvAllocationObservation* observation) {
  *observation = {};
  uv_fs_t warm;
  observation->warm_status =
      uv_fs_stat(nullptr, &warm, absolute_directory, nullptr);
  uv_fs_req_cleanup(&warm);
  if (observation->warm_status != 0 || UvTracker::current != nullptr) return -1;
  UvTracker tracker(observation);
  UvTracker::current = &tracker;
  if (uv_replace_allocator(UvTracker::allocate, UvTracker::resize,
                           UvTracker::allocateZero, UvTracker::release) != 0) {
    UvTracker::current = nullptr; return -1;
  }
  const PiNodeEnvironmentPathSpan path{absolute_directory, length};
  pi_node_permission_apply(permission, memory_owner, environment,
                           &path, 1, permission_scope);
  const int restored = uv_replace_allocator(
      std::malloc, std::realloc, std::calloc, std::free);
  UvTracker::current = nullptr;
  tracker.snapshotAndRetire();
  return restored;
}
