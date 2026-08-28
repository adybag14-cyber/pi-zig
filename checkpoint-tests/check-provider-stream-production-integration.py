from pathlib import Path
source = Path('src/extensions/js_bridge.mjs').read_text()
checks = {
    'real bounded assistant stream': 'class CompatAssistantMessageEventStream extends CompatEventStream',
    '64-event queue': 'PROVIDER_STREAM_MAX_QUEUED_EVENTS = 64',
    'queued byte cap': 'PROVIDER_STREAM_MAX_QUEUED_BYTES = 1024 * 1024',
    'event byte cap': 'PROVIDER_STREAM_MAX_EVENT_BYTES = 512 * 1024',
    'aggregate byte cap': 'PROVIDER_STREAM_MAX_TOTAL_BYTES = 16 * 1024 * 1024',
    'production invocation': 'async function invokeProviderStreamSimple',
    'native acknowledgement': "type: 'provider_stream_event'",
    'ack routing': "request.kind === 'provider_stream_ack'",
    'utf16 carry': 'pendingHighSurrogate',
    'content-index block state': 'state.blocks.set(index',
    'semantic tool JSON': 'canonicalJson(accumulated) !== canonicalJson(event.toolCall.arguments)',
    'terminal iterator completion': "if (!state.terminal) throw new Error('provider stream ended without a terminal done or error event')",
    'abort propagation': "signal?.throwIfAborted?.()",
    'abort races blocked iterators': 'awaitProviderStreamStep(iterator.next(), signal)',
    'bounded iterator retirement': 'retireProviderStreamIterator(iterator)',
    'assistant message validation': 'requireProviderAssistantMessage',
    'worker shutdown cleanup': 'pendingProviderStreamAcks.clear()',
    'shim export': 'createAssistantMessageEventStream = globalThis.__piCompat.createAssistantMessageEventStream',
}
missing = [name for name, needle in checks.items() if needle not in source]
if missing:
    raise SystemExit('missing stream integration checks: ' + ', '.join(missing))
print(f'provider streamSimple production integration: {len(checks)}/{len(checks)}')
