# Compaction methods

`MODEL.bend` defines one compaction operation and its current call. `PROGRAM.bend`
selects native compaction when the current account input fits, otherwise it reads
the retained public history in finite character chunks with a bounded summary.
Each `Next` requires a fresh committed invocation. A host interpreter performs one
call only; it cannot advance the cursor or publish a partial final replacement.

`Source` distinguishes native JSON history with retained raw rebuild material
from portable unread text. The native branch does not render the raw history.
`to_portable` derives that text when transport capacity, provider capacity or an
unsupported native capability first requires the portable method; later chunks
retain only the unread text.

The source text is quoted history data, not an instruction stream. Unicode
characters are split before target encoding. Every actual request is measured at
its provider before dispatch; an oversized chunk is reduced without dropping its
unread suffix. The model provider bounds output tokens. Transport faults use the
ordinary invocation failure mechanism.

An explicitly unsupported native route or model returns a capability observation.
The pending native method then switches to the existing portable method with all
retained source, unread material and note intact. A fresh committed call performs
that work. Authentication, rate limits, context limits and other service faults
keep their existing error behavior.

Before committing a call, the feature deducts the actual encoded effect metadata
from its kernel-frame allocation. The method measures the complete plan with an
empty chunk, including its note and prompt, and bounds the next chunk by the
remaining JSON bytes. The final encoded plan is checked again. A note that
occupies the allocation is retained as preceding unread material and rewritten
in bounded chunks. Preparation cannot publish a zero-length chunk while source
material remains. This byte constraint is independent of the model's token
window.

`PROOF.bend` binds cursor and replacement properties to the production methods.
Remote token counting, model summarization quality and network delivery remain
external boundaries.

The current Responses method admits windows of at least 4096 tokens and output
reserves of at least 256 tokens, with at most one quarter of the window reserved
for output. The preceding note was produced by the same model with
`max_output_tokens` equal to that reserve; it therefore has that model's bounded
output size, rather than a different tokenizer's estimated size. This leaves at
least half the window for the fixed prompt (under 1024 OpenAI tokens), framing
and a nonempty next fragment. Provider token counting checks the complete
serialized input before each actual call. A provider violating its own output
limit is an ordinary provider contract failure.

Official Responses requests use the provider's `input_tokens` endpoint. A
compatible endpoint that explicitly does not implement that route can instead
use the complete readable request's UTF-8 size as a conservative local bound;
the observation identifies that source. Authentication, rate limits and server
faults retain their ordinary failure behavior, and opaque input never receives
this estimate. The ChatGPT Web transport has a different stateful protocol and
is not declared as supporting this method.
