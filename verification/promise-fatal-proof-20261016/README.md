# Executed native Promise and module failure controls

Exact candidate `a3ea0d060c782848cf9cc43169d80bd5bb1623ec` executed all
34 selected entries: 29 named target controls and five imported anonymous
storage entries. The first packet passed START8, resumed7 and resolving5 before
a later fresh-memory admission refusal. The continuation passed inactive2 and
shared12. The first packet remains a partial negative; it was not rewritten as
a completely passing batch.

The tested C SHA256 is
`2FA2E26E35B7D5C45D1FFD3F6F10EE3A5DE9A984738486128399A20BD8E4D88D`;
the header remains
`341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB`.
The tests cover START/resumed module fatal delivery, native async resolving
callbacks, retired Await callbacks across GC, and active shared thenable,
hook and settlement failures. Ordinary/historical/lookalike reasons and hook
replacement remain covered by the selected controls.

Every actual protocol result had zero flags: no failure, skip, error log or
leak. Complete 10,510-file source and 19,546-file compiler seals matched across
the packets. Bounded process owners exited zero and were independently absent.
The independent acceptance receipt is included in both passing-result archives;
its SHA256 is
`6057819C94F745EFB5F9F837353A1E9C1305F5B95993B082FD83BF9701538055`.

- `first20/proof.zip`: first three executable artifacts and original partial
  batch evidence, SHA256
  `EC7938455E17DB100C0A17007BA16812E251D8BC3F9BE76F716AC0BD4213A446`.
- `remaining14/proof.zip`: remaining two executable artifacts and passing
  continuation, SHA256
  `2802DE0F8B00B6CC3EC74615871FCFB97322F3A1873E4EA32453DDBF4DF1A053`.
- `resource-negative/proof.zip`: preserved unsuccessful first continuation,
  which compiled/read inactive metadata but did not execute it, SHA256
  `29CAC1EF025F86A5029203CE9759481877156D1DE60936BB88FED335A19DC8E2`.

Each packet index records all member hashes and sizes. Archive members were
decompressed and rehashed after creation. This is focused native qualification;
it does not certify the default SDK graph, all extensions or the whole Pi app.
