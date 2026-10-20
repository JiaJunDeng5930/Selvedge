# Host semantic adapters

[MODEL.bend](MODEL.bend) packages host semantic calculations as operations with
pointwise correspondence to their executable meaning. `adapter` creates the
package, `construct` captures the complete input and actual result, `consume`
extracts a constructed result, and `execute` composes those last two operations.
The construction reuses [Categories](../../bendlib/categories.bend) so clients
receive evidence indexed by their actual input and output without another
construction representation.

Domain modules own their meanings, admission requirements, and diagnostic text.
They use `success`, `failure`, and `failure_code` for the outer result envelope.
`failure_code` can carry the existing exception constructor metadata
`TypeError`, `RangeError`, `SyntaxError`, or `Error`. The shared
[boundary](../public/model-boundary.mjs) reconstructs that constructor; other
business error codes remain on the resulting error's `code` property. Domain
admission stays in the native operation rather than another host guard.
External observations remain explicit inputs to these calculations. Existing
[JSON operations](../../bendlib/json.bend) supply wire values and accessors.

`PLUGINS.bend` classifies complete declared tool definitions through the published
ChatGPT CODEC entry kinds. Annotation membership binds the native route and
matching hints; query preservation follows the harness observation laws, and
cancellation stabilization follows the owning ChatGPT component evidence.
Its MCP input schemas project those same native command and execution-argument
declarations, removing authenticated coordinates and flattening execution fields.
Only the local connection's optional argument defaults belong to this projection.

`plugin.http_response` owns HTTP-reply parsing and the single reply admission.
Its consumer requires both wire-syntax and payload memberships of the same
reply and constructs the MCP output directly. The host strictly decodes external
UTF-8 bytes before supplying that observation.

Credential strings, lengths, hashes, and Bearer bytes remain outside Bend.
For API-key model consumers, the host hashes the complete target and resolved
credential together; only that final consumer-scope digest crosses the boundary.
This lets the same target reuse its opaque receipts while a credential change
invalidates them, without exposing a separate credential fingerprint.
`plugin.credential_plan` emits requirements interpreted by
[opaque-credentials.mjs](../opaque-credentials.mjs), which is also copied verbatim
into the standalone plugin's generated assets. This opaque-string interpreter
and `timingSafeEqual` are external secret boundaries; native correspondence
proves production plan construction, not the contents of secret bytes. URL
parsing, nofollow file IO, and file metadata observation likewise remain external;
nonsecret configuration, endpoint observations, and file admission use the native
plugin operations.

`CONFIGURATION.bend` owns the `config.` operations used by `loadConfig` for the
current JSON configuration. Environment values remain opaque references retained
by the host interpreter. No obsolete configuration format is accepted or converted.
`config.compaction` admits independent threshold and target-budget settings;
`config.compaction_runtime` resolves explicit budgets and advertised account model
windows after discovery. The summary method owns the shared legal-budget predicate
in `harness/compaction/MODEL.bend`; configuration does not duplicate its limits.

`EVALUATOR.bend` owns the `evaluator.` reasoning operations that produce committed
native effects. Tokenizer, clock and URL parsing results are explicit observations;
the host reconstructs opaque objects from the native result coordinates.

`HTTP.bend` owns the `http.` stage plans consumed by the server. Opaque comparisons
and network/file IO remain host observations and interpretation effects. The
shared dispatcher exposes each domain's actual factory consumer and complete
result correspondence to its executable meaning on the entire original source.

`effect.workspace_command` constructs the directory-observation plan for public
commands, including root births, graph-node settings and worktree preparation.
`effect.workspace_settings` admits client-selected settings and chooses whether
to resolve a Project or observe an explicit Workspace. The plan uses the
public command catalog's actual command kinds and the graph codec's node
classification. The host reports only directory and guidance observations;
`effect.workspace_command_observed` consumes them at the plan's native coordinates
and preserves the remaining command fields by construction.

Model requests retain stable native definitions and lightweight external function
declarations. Complete MCP and plugin schemas arrive through `discover_tools`
results at their committed history position. `discovery.bend` owns that
presentation for Responses and ChatGPT Web; it leaves the original task catalog
and callable projection intact. See [ADR 0053](../../docs/adr/0053-deferred-tool-definitions.md)
for the provider constraint and cache decision.
