// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Native selected Permission policies. The actual process debug operations are
// a required borrowed dependency; no disabled substitute is provided.
// Native cleanup differences are explicit in the separate source packet.
#ifndef PI_NATIVE_NODE_PERMISSION_INTERNAL_HPP
#define PI_NATIVE_NODE_PERMISSION_INTERNAL_HPP
#include "native_node_permission.h"
#include "native_node_environment_paths_internal.hpp"
#include "native_node_check_failure.h"
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>
namespace pi_node {
inline constexpr char kPathSeparator =
    std::filesystem::path::preferred_separator;
using PermissionStrings =
    std::vector<EnvironmentString, Allocator<EnvironmentString>>;
struct PermissionEnvironment {
  EnvironmentPathAccess path;
  const PiNodePermissionDebug* debug;
};
namespace permission {
#define FILESYSTEM_PERMISSIONS(V)                                              \
  V(FileSystem, "fs", PermissionsRoot, "")                                     \
  V(FileSystemRead, "fs.read", FileSystem, "--allow-fs-read")                  \
  V(FileSystemWrite, "fs.write", FileSystem, "--allow-fs-write")

#define CHILD_PROCESS_PERMISSIONS(V)                                           \
  V(ChildProcess, "child", PermissionsRoot, "--allow-child-process")

#define WASI_PERMISSIONS(V) V(WASI, "wasi", PermissionsRoot, "--allow-wasi")

#define WORKER_THREADS_PERMISSIONS(V)                                          \
  V(WorkerThreads, "worker", PermissionsRoot, "--allow-worker")

#define INSPECTOR_PERMISSIONS(V)                                               \
  V(Inspector, "inspector", PermissionsRoot, "--allow-inspector")

#define ADDON_PERMISSIONS(V)                                                   \
  V(Addon, "addon", PermissionsRoot, "--allow-addons")

#define PERMISSIONS(V)                                                         \
  FILESYSTEM_PERMISSIONS(V)                                                    \
  CHILD_PROCESS_PERMISSIONS(V)                                                 \
  WASI_PERMISSIONS(V)                                                          \
  WORKER_THREADS_PERMISSIONS(V)                                                \
  INSPECTOR_PERMISSIONS(V)                                                     \
  ADDON_PERMISSIONS(V)

#define V(name, _, __, ___) k##name,
enum class PermissionScope {
  kPermissionsRoot = -1,
  PERMISSIONS(V) kPermissionsCount
};
#undef V

class PermissionBase {
 public:
  virtual void Apply(PermissionEnvironment* env,
                     const PermissionStrings& allow,
                     PermissionScope scope) = 0;
  virtual bool is_granted(PermissionEnvironment* env,
                          PermissionScope perm,
                          const std::string_view& param = "") const = 0;
};

class FSPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param) const override;

  struct RadixTree {
    struct Node {
      EnvironmentString prefix;
      using ChildEntry = std::pair<const char, Node*>;
      std::unordered_map<char, Node*, std::hash<char>, std::equal_to<char>,
                         Allocator<ChildEntry>> children;
      Node* wildcard_child;
      bool is_leaf;

      static void* operator new(std::size_t bytes) {
        return allocateStandard(bytes);
      }
      static void operator delete(void* value) noexcept {
        pi_simd::release(value);
      }

      explicit Node(const EnvironmentString& pre)
          : prefix(pre), wildcard_child(nullptr), is_leaf(false) {}

      Node() : wildcard_child(nullptr), is_leaf(false) {}

      Node* CreateChild(const EnvironmentString& path_prefix, JSContext* context) {
        if (path_prefix.empty() && !is_leaf) {
          is_leaf = true;
          return this;
        }

        if (path_prefix.empty()) {
          const PiNodeAssertionInfo info = {
              "../src/permission/fs_permission.h:43", "!path_prefix.empty()",
              "node::permission::FSPermission::RadixTree::Node::CreateChild"};
          pi_node_assert_failure(context, &info);
          std::abort();
        }
        char label = path_prefix[0];

        Node* child = children[label];
        if (child == nullptr) {
          children[label] = new Node(path_prefix);
          return children[label];
        }

        // swap prefix
        size_t i = 0;
        size_t prefix_len = path_prefix.length();
        for (; i < child->prefix.length(); ++i) {
          if (i > prefix_len || path_prefix[i] != child->prefix[i]) {
            EnvironmentString parent_prefix = child->prefix.substr(0, i);
            EnvironmentString child_prefix = child->prefix.substr(i);

            child->prefix = child_prefix;
            Node* split_child = new Node(parent_prefix);
            split_child->children[child_prefix[0]] = child;
            children[parent_prefix[0]] = split_child;

            return split_child->CreateChild(path_prefix.substr(i), context);
          }
        }
        child->is_leaf = true;
        return child->CreateChild(path_prefix.substr(i), context);
      }

      Node* CreateWildcardChild() {
        if (wildcard_child != nullptr) {
          return wildcard_child;
        }
        wildcard_child = new Node();
        return wildcard_child;
      }

      Node* NextNode(const EnvironmentString& path, size_t idx) const {
        if (idx >= path.length()) {
          return nullptr;
        }

        // wildcard node takes precedence
        if (children.size() > 1) {
          auto it = children.find('*');
          if (it != children.end()) {
            return it->second;
          }
        }

        auto it = children.find(path[idx]);
        if (it == children.end()) {
          return nullptr;
        }
        auto child = it->second;
        // match prefix
        size_t prefix_len = child->prefix.length();
        for (size_t i = 0; i < path.length(); ++i) {
          if (i >= prefix_len || child->prefix[i] == '*') {
            return child;
          }

          // Handle optional trailing
          // path = /home/subdirectory
          // child = subdirectory/*
          if (idx >= path.length() &&
              child->prefix[i] == pi_node::kPathSeparator) {
            continue;
          }

          if (path[idx++] != child->prefix[i]) {
            return nullptr;
          }
        }
        return child;
      }

      // A node can be a *end* node and have children
      // E.g: */slower*, */slown* are inserted:
      // /slow
      // ---> er
      // ---> n
      // If */slow* is inserted right after, it will create an
      // empty node
      // /slow
      // ---> '\000' ASCII (0) || \0
      // ---> er
      // ---> n
      bool IsEndNode() const {
        if (children.empty()) {
          return true;
        }
        return is_leaf;
      }
    };

    RadixTree();
    ~RadixTree();
    void Insert(const EnvironmentString& s, PermissionEnvironment* env);
    bool Lookup(const std::string_view& s) const { return Lookup(s, false); }
    bool Lookup(const std::string_view& s, bool when_empty_return) const;

   private:
    Node* root_node_;
  };

 private:
  void GrantAccess(PermissionEnvironment* env, PermissionScope scope,
                   const EnvironmentString& param);
  // fs granted on startup
  RadixTree granted_in_fs_;
  RadixTree granted_out_fs_;

  bool deny_all_in_ = true;
  bool deny_all_out_ = true;

  bool allow_all_in_ = false;
  bool allow_all_out_ = false;
};

class AddonPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param = "") const override;

 private:
  bool deny_all_;
};


class ChildProcessPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param = "") const override;

 private:
  bool deny_all_;
};


class InspectorPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param = "") const override;

 private:
  bool deny_all_;
};


class WASIPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param = "") const override;

 private:
  bool deny_all_;
};


class WorkerPermission final : public PermissionBase {
 public:
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope) override;
  bool is_granted(PermissionEnvironment* env,
                  PermissionScope perm,
                  const std::string_view& param = "") const override;

 private:
  bool deny_all_;
};



class Permission {
 public:
  Permission();

  bool is_granted(PermissionEnvironment* env,
                               const PermissionScope permission,
                               const std::string_view& res = "") const {
    if (!enabled_) [[likely]] {
      return true;
    }
    return is_scope_granted(env, permission, res);
  }

  bool enabled() const { return enabled_; }

  static PermissionScope StringToPermission(const EnvironmentString& perm);
  static const char* PermissionToString(PermissionScope perm);
  // CLI Call
  void Apply(PermissionEnvironment* env,
             const PermissionStrings& allow,
             PermissionScope scope);
  void EnablePermissions();

 private:
  bool is_scope_granted(PermissionEnvironment* env,
                                      const PermissionScope permission,
                                      const std::string_view& res = "") const {
    auto perm_node = nodes_.find(permission);
    if (perm_node != nodes_.end()) {
      return perm_node->second->is_granted(env, permission, res);
    }
    return false;
  }

  using PolicyEntry =
      std::pair<const PermissionScope, std::shared_ptr<PermissionBase>>;
  std::unordered_map<PermissionScope, std::shared_ptr<PermissionBase>,
                     std::hash<PermissionScope>, std::equal_to<PermissionScope>,
                     Allocator<PolicyEntry>> nodes_;
  bool enabled_;
};

}  // namespace permission
}  // namespace pi_node
#endif
