// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original Node24.13 async provider order from src/async_wrap.h. Compile feature
//! selection is explicit; no subset of the table is fabricated for one user.
pub const non_crypto = [_][]const u8{
    "NONE", "DIRHANDLE", "DNSCHANNEL", "ELDHISTOGRAM", "FILEHANDLE",
    "FILEHANDLECLOSEREQ", "BLOBREADER", "FSEVENTWRAP", "FSREQCALLBACK",
    "FSREQPROMISE", "GETADDRINFOREQWRAP", "GETNAMEINFOREQWRAP", "HEAPSNAPSHOT",
    "HTTP2SESSION", "HTTP2STREAM", "HTTP2PING", "HTTP2SETTINGS",
    "HTTPINCOMINGMESSAGE", "HTTPCLIENTREQUEST", "LOCKS", "JSSTREAM", "JSUDPWRAP",
    "MESSAGEPORT", "PIPECONNECTWRAP", "PIPESERVERWRAP", "PIPEWRAP", "PROCESSWRAP",
    "PROMISE", "QUERYWRAP", "QUIC_ENDPOINT", "QUIC_LOGSTREAM", "QUIC_PACKET",
    "QUIC_SESSION", "QUIC_STREAM", "QUIC_UDP", "SHUTDOWNWRAP", "SIGNALWRAP",
    "STATWATCHER", "STREAMPIPE", "TCPCONNECTWRAP", "TCPSERVERWRAP", "TCPWRAP",
    "TTYWRAP", "UDPSENDWRAP", "UDPWRAP", "SIGINTWATCHDOG", "WORKER",
    "WORKERCPUPROFILE", "WORKERCPUUSAGE", "WORKERHEAPPROFILE",
    "WORKERHEAPSNAPSHOT", "WORKERHEAPSTATISTICS", "WRITEWRAP", "ZLIB",
};
pub const crypto = [_][]const u8{
    "CHECKPRIMEREQUEST", "PBKDF2REQUEST", "KEYPAIRGENREQUEST", "KEYGENREQUEST",
    "KEYEXPORTREQUEST", "ARGON2REQUEST", "CIPHERREQUEST", "DERIVEBITSREQUEST",
    "HASHREQUEST", "RANDOMBYTESREQUEST", "RANDOMPRIMEREQUEST", "SCRYPTREQUEST",
    "SIGNREQUEST", "TLSWRAP", "VERIFYREQUEST",
};
const all = non_crypto ++ crypto;
pub fn names(have_openssl: bool) []const []const u8 {
    return if (have_openssl) &all else &non_crypto;
}
pub const none: u32 = 0;
pub const file_handle: u32 = 4;
pub const file_handle_close_request: u32 = 5;
pub const fs_request_promise: u32 = 9;
