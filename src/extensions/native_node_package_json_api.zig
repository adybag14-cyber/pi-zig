//! Shared native package parser C namespace. The cache and serializer exchange
//! opaque Config pointers from this one import, preserving their actual type.
pub const c = @cImport(@cInclude("native_node_package_json_parser.h"));
