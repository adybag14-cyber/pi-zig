// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Selected original native Permission and FS radix algorithms. Native standard
// allocation failures retain the shared real new-handler policy.
// Two explicit native cleanup corrections are recorded separately from the
// unchanged selected policy algorithm; they are not original-body equivalence.
#include "native_node_permission_internal.hpp"
#include "uv.h"
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <algorithm>
#include <new>
#include <optional>
#if !defined(_WIN32) && !defined(__linux__)
#error "the selected native Permission owner is admitted on Windows/Linux"
#endif
using pi_node::EnvironmentString;
using pi_node::PermissionEnvironment;
using pi_node::PermissionStrings;
namespace {

EnvironmentString WildcardIfDir(const EnvironmentString& res) noexcept {
  uv_fs_t req;
  int rc = uv_fs_stat(nullptr, &req, res.c_str(), nullptr);
  if (rc == 0) {
    const uv_stat_t* const s = static_cast<const uv_stat_t*>(req.ptr);
    if ((s->st_mode & S_IFMT) == S_IFDIR) {
      // add wildcard when directory
      if (res.back() == pi_node::kPathSeparator) {
        EnvironmentString result = res + "*";
        uv_fs_req_cleanup(&req);
        return result;
      }
      EnvironmentString result = res + pi_node::kPathSeparator + "*";
      uv_fs_req_cleanup(&req);
      return result;
    }
  }
  uv_fs_req_cleanup(&req);
  return res;
}

void FreeRecursivelyNode(
    pi_node::permission::FSPermission::RadixTree::Node* node) {
  if (node == nullptr) {
    return;
  }

  if (node->children.size()) {
    for (auto& c : node->children) {
      FreeRecursivelyNode(c.second);
    }
  }

  FreeRecursivelyNode(node->wildcard_child);
  delete node;
}

bool is_tree_granted(
    pi_node::PermissionEnvironment* env,
    const pi_node::permission::FSPermission::RadixTree* granted_tree,
    const std::string_view& param) {
  EnvironmentString resolved_param = pi_node::PathResolve(&env->path, {param});
#ifdef _WIN32
  // Remove leading "\\?\" from UNC path
  if (resolved_param.starts_with("\\\\?\\")) {
    resolved_param.erase(0, 4);
  }

  // Remove leading "UNC\" from UNC path
  if (resolved_param.starts_with("UNC\\")) {
    resolved_param.erase(0, 4);
  }
  // Remove leading "//" from UNC path
  if (resolved_param.starts_with("//")) {
    resolved_param.erase(0, 2);
  }
#endif
  return granted_tree->Lookup(resolved_param, true);
}

static const char* kBoxDrawingsLightUpAndRight = "└─ ";
static const char* kBoxDrawingsLightVerticalAndRight = "├─ ";

void DebugTreeLine(const PiNodePermissionDebug* debug,
                   const char* indent, const char* prefix) {
  if (debug->enabled(debug->user))
    debug->format_tree_line(debug->user, indent, prefix);
}

void PrintTree(const pi_node::permission::FSPermission::RadixTree::Node* node,
               size_t depth = 0,
               const EnvironmentString& branch_prefix = "",
               bool is_last = true,
               const PiNodePermissionDebug* debug = nullptr) {
  if (node == nullptr) {
    return;
  }

  if (depth > 0 || (node->prefix.length() > 0)) {
    EnvironmentString indent;

    if (depth > 0) {
      indent = branch_prefix;
      if (is_last) {
        indent += kBoxDrawingsLightUpAndRight;
      } else {
        indent += kBoxDrawingsLightVerticalAndRight;
      }
    }

    DebugTreeLine(debug, indent.c_str(), node->prefix.c_str());
  }

  if (node->children.size() > 0) {
    size_t count = 0;
    size_t total = node->children.size();

    EnvironmentString next_branch_prefix;
    if (depth > 0) {
      next_branch_prefix = branch_prefix;
      if (is_last) {
        next_branch_prefix += "   ";
      } else {
        next_branch_prefix += "│  ";
      }
    }

    for (const auto& pair : node->children) {
      count++;
      bool child_is_last = (count == total);
      PrintTree(pair.second, depth + 1, next_branch_prefix, child_is_last,
                debug);
    }
  }
}

}  // namespace

namespace pi_node {

namespace permission {

// allow = '*'
// allow = '/tmp/,/home/example.js'
void FSPermission::Apply(PermissionEnvironment* env,
                         const PermissionStrings& allow,
                         PermissionScope scope) {
  for (const EnvironmentString& res : allow) {
    if (res == "*") {
      if (scope == PermissionScope::kFileSystemRead) {
        deny_all_in_ = false;
        allow_all_in_ = true;
      } else {
        deny_all_out_ = false;
        allow_all_out_ = true;
      }
      return;
    }
    GrantAccess(env, scope, PathResolve(&env->path, {res}));
  }
}

void FSPermission::GrantAccess(PermissionEnvironment* env,
                               PermissionScope perm, const EnvironmentString& res) {
  const EnvironmentString path = WildcardIfDir(res);
  if (perm == PermissionScope::kFileSystemRead &&
      !granted_in_fs_.Lookup(path)) {
    granted_in_fs_.Insert(path, env);
    deny_all_in_ = false;
  } else if (perm == PermissionScope::kFileSystemWrite &&
             !granted_out_fs_.Lookup(path)) {
    granted_out_fs_.Insert(path, env);
    deny_all_out_ = false;
  }
}

bool FSPermission::is_granted(PermissionEnvironment* env,
                              PermissionScope perm,
                              const std::string_view& param = "") const {
  switch (perm) {
    case PermissionScope::kFileSystem:
      return allow_all_in_ && allow_all_out_;
    case PermissionScope::kFileSystemRead:
      return !deny_all_in_ &&
             ((param.empty() && allow_all_in_) || allow_all_in_ ||
              is_tree_granted(env, &granted_in_fs_, param));
    case PermissionScope::kFileSystemWrite:
      return !deny_all_out_ &&
             ((param.empty() && allow_all_out_) || allow_all_out_ ||
              is_tree_granted(env, &granted_out_fs_, param));
    default:
      return false;
  }
}

FSPermission::RadixTree::RadixTree() : root_node_(new Node("")) {}

FSPermission::RadixTree::~RadixTree() {
  FreeRecursivelyNode(root_node_);
}

bool FSPermission::RadixTree::Lookup(const std::string_view& s,
                                     bool when_empty_return) const {
  FSPermission::RadixTree::Node* current_node = root_node_;
  if (current_node->children.empty()) {
    return when_empty_return;
  }
  size_t parent_node_prefix_len = current_node->prefix.length();
  const EnvironmentString path(s);
  auto path_len = path.length();

  while (true) {
    if (parent_node_prefix_len == path_len && current_node->IsEndNode()) {
      return true;
    }

    auto node = current_node->NextNode(path, parent_node_prefix_len);
    if (node == nullptr) {
      return false;
    }

    current_node = node;
    parent_node_prefix_len += current_node->prefix.length();
    if (current_node->wildcard_child != nullptr &&
        path_len >= (parent_node_prefix_len - 2 /* slash* */)) {
      return true;
    }
  }
}

void FSPermission::RadixTree::Insert(const EnvironmentString& path,
                                    PermissionEnvironment* env) {
  FSPermission::RadixTree::Node* current_node = root_node_;

  size_t parent_node_prefix_len = current_node->prefix.length();
  size_t path_len = path.length();

  for (size_t i = 1; i <= path_len; ++i) {
    bool is_wildcard_node = path[i - 1] == '*';
    bool is_last_char = i == path_len;

    if (is_wildcard_node || is_last_char) {
      EnvironmentString node_path = path.substr(parent_node_prefix_len, i);
      current_node = current_node->CreateChild(node_path, env->path.context);
    }

    if (is_wildcard_node) {
      current_node = current_node->CreateWildcardChild();
      parent_node_prefix_len = i;
    }
  }

  const PiNodePermissionDebug* debug = env->debug;
  if (debug->enabled(debug->user)) [[unlikely]] {
    if (debug->enabled(debug->user))
      debug->format_insert(debug->user, path.data(), path.size());
    PrintTree(root_node_, 0, "", true, debug);
  }
}

}  // namespace permission
}  // namespace pi_node

namespace pi_node::permission {
void AddonPermission::Apply(PermissionEnvironment* env,
                            const PermissionStrings& allow,
                            PermissionScope scope) {
  deny_all_ = true;
}

bool AddonPermission::is_granted(PermissionEnvironment* env,
                                 PermissionScope perm,
                                 const std::string_view& param) const {
  return deny_all_ == false;
}


void ChildProcessPermission::Apply(PermissionEnvironment* env,
                                   const PermissionStrings& allow,
                                   PermissionScope scope) {
  deny_all_ = true;
}

bool ChildProcessPermission::is_granted(PermissionEnvironment* env,
                                        PermissionScope perm,
                                        const std::string_view& param) const {
  return deny_all_ == false;
}


void InspectorPermission::Apply(PermissionEnvironment* env,
                                const PermissionStrings& allow,
                                PermissionScope scope) {
  deny_all_ = true;
}

bool InspectorPermission::is_granted(PermissionEnvironment* env,
                                     PermissionScope perm,
                                     const std::string_view& param) const {
  return deny_all_ == false;
}


void WASIPermission::Apply(PermissionEnvironment* env,
                           const PermissionStrings& allow,
                           PermissionScope scope) {
  deny_all_ = true;
}

bool WASIPermission::is_granted(PermissionEnvironment* env,
                                PermissionScope perm,
                                const std::string_view& param) const {
  return deny_all_ == false;
}


void WorkerPermission::Apply(PermissionEnvironment* env,
                             const PermissionStrings& allow,
                             PermissionScope scope) {
  deny_all_ = true;
}

bool WorkerPermission::is_granted(PermissionEnvironment* env,
                                  PermissionScope perm,
                                  const std::string_view& param) const {
  return deny_all_ == false;
}


#define V(Name, label, _, __)                                                  \
  if (perm == PermissionScope::k##Name) return #Name;
const char* Permission::PermissionToString(const PermissionScope perm) {
  PERMISSIONS(V)
  return nullptr;
}
#undef V

#define V(Name, label, _, __)                                                  \
  if (perm == label) return PermissionScope::k##Name;
PermissionScope Permission::StringToPermission(const EnvironmentString& perm) {
  PERMISSIONS(V)
  return PermissionScope::kPermissionsRoot;
}
#undef V

Permission::Permission() : enabled_(false) {
  std::shared_ptr<PermissionBase> fs = std::allocate_shared<FSPermission>(Allocator<FSPermission>{});
  std::shared_ptr<PermissionBase> child_p =
      std::allocate_shared<ChildProcessPermission>(Allocator<ChildProcessPermission>{});
  std::shared_ptr<PermissionBase> worker_t =
      std::allocate_shared<WorkerPermission>(Allocator<WorkerPermission>{});
  std::shared_ptr<PermissionBase> inspector =
      std::allocate_shared<InspectorPermission>(Allocator<InspectorPermission>{});
  std::shared_ptr<PermissionBase> wasi = std::allocate_shared<WASIPermission>(Allocator<WASIPermission>{});
  std::shared_ptr<PermissionBase> addon = std::allocate_shared<AddonPermission>(Allocator<AddonPermission>{});
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, fs));
  FILESYSTEM_PERMISSIONS(V)
#undef V
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, child_p));
  CHILD_PROCESS_PERMISSIONS(V)
#undef V
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, worker_t));
  WORKER_THREADS_PERMISSIONS(V)
#undef V
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, inspector));
  INSPECTOR_PERMISSIONS(V)
#undef V
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, wasi));
  WASI_PERMISSIONS(V)
#undef V
#define V(Name, _, __, ___)                                                    \
  nodes_.insert(std::make_pair(PermissionScope::k##Name, addon));
  ADDON_PERMISSIONS(V)
#undef V
}

void Permission::EnablePermissions() {
  if (!enabled_) {
    enabled_ = true;
  }
}

void Permission::Apply(PermissionEnvironment* env,
                       const PermissionStrings& allow,
                       PermissionScope scope) {
  auto permission = nodes_.find(scope);
  if (permission != nodes_.end()) {
    permission->second->Apply(env, allow, scope);
  }
}

}  // namespace pi_node::permission

struct PiNodePermission {
  pi_node::permission::Permission value;
};
namespace {
std::optional<pi_node::PermissionEnvironment> BorrowEnvironment(
    const PiNodePermissionEnvironment* environment) {
  if (environment == nullptr) return std::nullopt;
  return pi_node::PermissionEnvironment{
      {environment->paths, environment->map, environment->context,
       environment->trace}, environment->process_debug};
}
}  // namespace
extern "C" size_t pi_node_permission_storage_size(void) noexcept {
  return sizeof(PiNodePermission);
}
extern "C" size_t pi_node_permission_storage_alignment(void) noexcept {
  return alignof(PiNodePermission);
}
extern "C" PiNodePermission* pi_node_permission_construct(
    void* storage, void* memory_owner) noexcept {
  pi_node::AllocationScope scope(memory_owner);
  return ::new (storage) PiNodePermission();
}
extern "C" void pi_node_permission_destroy(
    PiNodePermission* permission) noexcept {
  permission->~PiNodePermission();
}
extern "C" int pi_node_permission_enabled(
    const PiNodePermission* permission) noexcept {
  return permission->value.enabled();
}
extern "C" void pi_node_permission_enable(
    PiNodePermission* permission) noexcept {
  permission->value.EnablePermissions();
}
extern "C" void pi_node_permission_apply(
    PiNodePermission* permission, void* memory_owner,
    const PiNodePermissionEnvironment* environment,
    const PiNodeEnvironmentPathSpan* allow, size_t count, int scope) noexcept {
  pi_node::AllocationScope allocation_scope(memory_owner);
  auto env = BorrowEnvironment(environment);
  PermissionStrings entries;
  entries.reserve(count);
  for (size_t i = 0; i < count; ++i)
    entries.emplace_back(allow[i].data, allow[i].length);
  permission->value.Apply(env ? &*env : nullptr, entries,
      static_cast<pi_node::permission::PermissionScope>(scope));
}
extern "C" int pi_node_permission_is_granted(
    const PiNodePermission* permission, void* memory_owner,
    const PiNodePermissionEnvironment* environment, int scope,
    const char* resource, size_t resource_length) noexcept {
  pi_node::AllocationScope allocation_scope(memory_owner);
  auto env = BorrowEnvironment(environment);
  return permission->value.is_granted(env ? &*env : nullptr,
      static_cast<pi_node::permission::PermissionScope>(scope),
      std::string_view(resource, resource_length));
}
