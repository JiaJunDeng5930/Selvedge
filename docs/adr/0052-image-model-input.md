# 0052: Content-addressed image inputs

## Context

Board attachments could be uploaded and previewed, but starting a Task put only
their filesystem paths in a textual prompt. A visible screenshot did not supply
image input to the model. Local image-reading tools had the same missing boundary.

The provider protocols share ordered text and image content, while their transport
identities differ. [OpenAI Responses](https://developers.openai.com/api/docs/guides/images-vision)
accepts image URLs, data URLs and provider file identifiers; Chat Completions uses
a different image envelope. [Anthropic](https://platform.claude.com/docs/en/build-with-claude/vision)
uses image source objects, and [Gemini](https://ai.google.dev/gemini-api/docs/image-understanding)
supports inline bytes and uploaded file references. Provider file identifiers and
remote URLs therefore cannot identify a portable image in Task history.

The wider comparison supports this separation:

| Provider family | Documented image input | Implication for the shared representation |
| --- | --- | --- |
| OpenAI Responses / Chat Completions | Different image envelopes; URL, data URL, or provider file identity where supported | Preserve content order; let the adapter own the wire envelope. |
| Anthropic | Image source objects with media type and provider-specific sources | Preserve media type without making its source object a domain type. |
| Gemini | Inline data and uploaded-file references | Keep provider uploads outside durable Task identity. |
| [Mistral](https://docs.mistral.ai/studio/conversations/vision) | Ordered text and `image_url` content, including Base64 image input | Reuse the same content model despite a different image envelope. |
| [Qwen / Model Studio](https://www.alibabacloud.com/help/en/model-studio/vision) | OpenAI-compatible text and `image_url` content | Protocol compatibility does not establish identical model limits. |
| [Grok](https://docs.x.ai/developers/model-capabilities/images/understanding) | Responses image/text inputs; documented JPEG/PNG inputs | Format support remains an adapter capability, separate from image identity. |

[Codex's image tool](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/view_image.rs)
also returns an image content item rather than a filename or a textual success
message. That distinction applies equally to user input and tool output here.

## Decision

Use the existing content-addressed attachment vault for both browser uploads and
local image snapshots. Its content hash supplies stable image identity separately
from a filename, card or mutable workspace path. Message content preserves the
order of text and image parts. This permits subsequent requests and replay to
refer to the same bytes without copying Base64 strings into Bend state, journal
decisions and browser world snapshots.

Keep byte loading and encoding at the host's physical boundary. The native
backend construction chooses the image input positions; the host verifies the
referenced vault content and fills those positions for transport. A missing or
invalid snapshot fails the request rather than turning the picture into text.

Implement the ChatGPT account Responses backend first. Other backends reject
image input until their protocol mapping is implemented. A common representation
does not imply common provider limits, supported models or image-detail policies.
Use the existing Task sandbox for local image reads, then preserve the read bytes
as a vault snapshot so later requests do not observe a changed source file.

Use the existing summary compaction path when the history contains images.
[Native compaction](https://developers.openai.com/api/docs/guides/compaction)
returns a canonical window that may retain original input items. Passing image
data URLs through that response would put large byte strings back into Bend and
duplicate images retained by portable history selection. Summary compaction can
retain the original image references without that reverse conversion.

Account image inputs use the same kind of reference-based input estimate as
[Codex history](https://github.com/openai/codex/blob/main/codex-rs/core/src/context_manager/history.rs).
The account transport does not promise the public API's token-counting endpoint;
requiring that endpoint would prevent otherwise valid image requests. The estimate
supports scheduling, while actual context-limit responses keep their existing
compression behavior.

## Consequences

Browser, board and tool images share storage and request materialization. Their
history does not depend on a provider's upload service or the continued existence
of the original local file. The vault remains part of the service's durable data;
copying only the journal is insufficient to move image-bearing conversations.

Production proofs cover the native content and request constructions. Public
HTTP-to-provider acceptance checks cover the external byte loading, serialization
and transport boundary; browser checks cover actual pasted files and decoded
images. Provider response quality remains an external model behavior.
