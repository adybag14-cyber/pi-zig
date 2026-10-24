# Stream write error-result correction

The original new14 BuildQuery on 7947d3a0 failed at native_node_stream_write.zig:222 because Zig rejects discarding an anyerror value with "_ =".

The correction explicitly consumes the ordinary JavaScriptException completion while keeping its actual thrown reason in the existing owned Boundary. invalidBuffer then returns normally, so writeBuffer preserves the original native zero before the enclosing Scope publishes the exception. Any different native completion propagates. A direct "return a.raise" would skip that native zero and fail the existing exact control.

Original stream_base.cc:302-304 throws ERR_INVALID_ARG_TYPE and returns 0. Existing native_node_stream_write_test.zig:350-369 requires the JavaScriptException, records last_status == 0, checks the intrinsic TypeError/code/message and unchanged shared result slots. Those controls and all other production bytes remain unchanged.

This is an isolated source correction. Main is still frozen pending independent closure of the original failed BuildQuery. No compiler, runtime or qualification result is asserted.
