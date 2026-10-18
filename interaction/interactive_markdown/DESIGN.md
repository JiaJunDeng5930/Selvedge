# Interactive Markdown design

The goal is to make model replies progressively interactive and responsive to local input and current application state while retaining ordinary Markdown. This document explains the language and shared boundaries. Executable contracts bind the engineering requirements to the operations used in production.

## 1. Outcome and existing constraints

Implement a local, declarative, reactive document language inside explicit `selvedge-ui` Markdown fences. A model emits one definition, progressively; accepted portions become usable while later text arrives. User input, read-only application snapshots, and registered display motion update the interface without another model call. Ordinary Markdown stays on the existing streaming parser path.

Production semantics (syntax acceptance, bindings, values, state transitions, resource projections, identity, action admission, persistence admission) belong to Bend. JavaScript interprets the compiled document and physical effects, observes the existing Markdown parser's fences, schedules bounded rendering, handles DOM/native input/animation/storage, and transports observations. No `eval`, `Function`, model JavaScript, model CSS, arbitrary property access into application world, or hidden watcher commands.

Existing mechanisms to reuse: `interaction/conversation/CODE.bend` identity + code state; the single `streaming-markdown` parser and Portal/TargetProperties targets; authored controls + native-fields IME and canonical value protocol; `interaction/session` application world snapshots; `features/task_graph` resolved task references; existing Task status observations; browser runtime candidate/measurement validation. Changes must retain root operational abstraction and production proof assembly, not place product policy in the host.

In scope: complete basic layouts, text/metric, inputs and bounded actions, table and line/bar chart, conditional/repeated views, live task graph with templates and stable layout, state restoration, capability instructions, stream-to-history continuity, errors and bounds, real browser verification. Event-by-event delivery replay, arbitrary HTML applications, and a general programmable timeline are future capabilities, not prerequisites or claims of this implementation.

## 2. Shared vocabulary and ownership

The new independent `interaction/interactive_markdown` concept owns vocabulary/parser/evaluator/state/contract/proof. Public types do not import assembled harness or browser types. General OutputOrigin belongs to existing harness DOMAIN or independent harness/conversation vocabulary; harness core must not import the UI language to attach provenance. Task-graph projection may live in `interaction/conversation` or presentation, consuming the public values and one real world. No concept directory deeper than two levels.

Shared carriers (names may follow local convention; fields/meanings fixed):

```
OutputOrigin = {producerTask: Nat, operation: Nat, part: Nat, mode: Plain | InteractiveV1}
ContentOrigin = {namespace: String, output: OutputOrigin}
DocumentInput = {origin, text, ending: Open | Complete | Interrupted}
BlockIdentity = {origin, fenceOrdinal: Nat}
InstanceIdentity = {block, viewingTask: Nat, epoch: Nat, uiId: String}
ComponentIdentity = {instance, templateKeyPath: List<String>, componentId: String}
EventIdentity = {component, mountOccurrence: Nat}
FenceObservation = {block, epoch, inputRevision, rawInfo, codePrefix, closed}
SourceReference = {namespace, kind: TaskGraph, id: Nat}
SourceObservation = {reference, worldSequence, availability, freshness, value}
LocalSnapshot = {instance origin, fullDefinition, stateSchema, values, viewValues}
```

`fenceOrdinal` counts all code fences in a document, including ordinary ones. It is a parser observation, not a hash of text. Root `uiId` must be nonempty but does not replace fence identity; duplicate root IDs in separate fences do not merge state. Identical documents from separate tasks/operations never share state. Source updates and worldSequence do not change document/component identity.

Application interaction state owns document sessions, accepted definitions, local typed values, invalid input buffers, graph pan/zoom/selection, event mount occurrence, source observations, and action feedback. Parser tail is bounded. Render trees and derived values are disposable observations. The host storage contains only acknowledged local snapshot effects, never an alternative state reducer. DOM `value` is the native display of canonical state and must use native-fields identity/composition handling.

## 3. Provenance, mode and final message continuity

This is a prerequisite, not an optional optimization. The accepted model reply boundary records production provenance for each model output item. Both `Say` -> AssistantMessage and provider `Context` -> ModelContext (including Responses assistant message items) must retain `OutputOrigin`. Reasoning/context-only records do not enable UI. Model text cannot select its own `mode` or operation.

The current Responses adapter emits preview `output_index`; final output conversion must preserve the same explicit item index, including positions occupied by reasoning and tool calls. Normalize adapters to an explicit logical part coordinate in their model-item envelope: Say{part,text}, Context{part,value}; Invoke retains Call. Wire accepts part, never producerTask/operation/mode (those are application authority), and rejects duplicate Say/Context parts. Extend committed AssistantMessage/ModelContext with OutputOrigin and retain their existing body meaning. Do not infer mapping from the ordinal of Say, last message, equal text, model timestamp, provider message ID alone, or history length. The actual accepted model ticket supplies operation and task identity supplies producerTask. Responses parts equal real output_index. ChatGPT Web currently has at most two stages, index 0/1, each completed stage yields exactly one Say; use stage index as its part, and reserve part 2 for its final provider receipt (Plain, non-speech). Requires-action stages create Invoke only. A third Web stage must reject under this protocol rather than collide with receipt; any future expansion changes the declared protocol. Echo final Say uses part 0. Providers that only expose final text still get an explicit part coordinate at their adapter. Every adapter must either provide a checked matching preview coordinate or emit no preview for that item; it must never guess.

Normal user-facing model requests advertise InteractiveV1 and stamp their output mode accordingly. The actual request's capability/mode is frozen in its admitted ModelPending operation before the external model call; preview and final provenance both read that frozen mode, never a mutable preference or the wording of the reply. Approval, compaction, board text helper requests, user content, tool results, quoted/audit data and raw provider reasoning are Plain. Existing historical model messages in the current schema have explicit mode; no obsolete-format fallback. Conversation extraction must retain this origin for provider assistant Context as well as direct Say. Preserve the native provider Context body and its normal continuation re-serialization; provenance does not turn all native messages into Say/AssistantMessage.

Preview and final message use the same `ContentOrigin` and Markdown node key. Accepted final text that extends preview consumes only its suffix. Exact equal text updates ending only. A final non-prefix correction creates a fresh parser epoch and deliberately resets that document's UI values; it does not pretend to preserve structurally different controls. The final history owns the message, but does not allocate another UI instance. Inherited messages in a fork retain original content provenance and remain locally interactive; `viewingTask` in instance/state/storage identity makes their user input independent from the parent and other branches. Model external actions are disabled for inherited content when viewingTask differs from owningTask; new branch-local outputs operate normally. Host-authored source copy remains available.

Interrupted output retention: a session that has observed a valid preview retains its text/definition/local input when a fresh authoritative snapshot no longer contains the operation and no accepted final item for that origin exists. Mark it Interrupted and show “生成未完成”; keep local interaction and source disclosure, disable model external actions. This is a session presentation artifact, not a fabricated committed assistant message or durable model history. Its owner is the conversation session's retained-output map keyed by ContentOrigin+viewingTask, independent from transport's active preview list. Present terminal partials in an explicitly titled session-only unfinished-reply section after committed history (including any failure audit record) and before active preview/composer, ordered by operation ticket then part; promotion removes exactly that artifact and leaves final history in its normal location. User may dismiss it explicitly. Transport disconnect alone marks freshness unknown and retains preview; it does not imply terminal interruption. On reconnect, reconcile authoritative world plus the existing host stream snapshot: matched final origin promotes; active operation resumes available matching prefix; terminal absent operation interrupts. If a resumed/final source is not a prefix, normal epoch replacement applies. Never silently remove partial controls merely because `Live.active` becomes false or ConnectionEnded fires. Interrupted artifacts survive route switches during browser session but not refresh/restart; label that retention limit. Bound live retained interrupted artifacts to 16 per task and 64 per session, newest first; when exceeded replace oldest with a visible source-only “未完成显示已收起” disclosure. Bound source-only archives to 4 MiB session text; any removal leaves a visible count of discarded unfinished outputs, clearable by the user.

Service data namespace: create a random 128-bit identifier once, persist it as an exact current journal meta field, return it in authenticated browser snapshots/bootstrap observations, and retain across service restart. It identifies data, not the HTTP URL or browser auth cookie. Create one new current journal format/schema; no migration/dual parser. Old formats fail normally. Namespace validation and HTTP shape are boundary tests. Resource and local-storage identities require this namespace; missing/invalid namespace disables interactive binding and restoration with a visible diagnostic.

## 4. Markdown extension boundary

The same existing Markdown parser recognizes code fences and all their nesting/escape rules. Extend its sink to report complete raw fence info (currently `LANG` truncates/splits it); Bend decides activation. A fence activates iff mode is InteractiveV1, token is fenced code (not indented code), and raw info trimmed only of ASCII surrounding spaces/tabs is exactly `selvedge-ui`. Matching is case sensitive; extra options or words make ordinary code. The fence opener must be complete before activation. Tilde/backtick/nested/list/blockquote behavior follows that parser, not a second regex scanner. Raw HTML and brace text outside fences have unchanged semantics.

The Markdown sink creates an empty stable UI target plus an ordinary literal source target under the same fence wrapper. It does not parse DSL, mount product controls, or remove ordinary surrounding Markdown. Bend emits a Portal into UI target and properties that select source/preview exposure. Until activation is known the fence remains literal. Activated blocks have an explicit source disclosure/copy affordance implemented by Bend; errors retain selectable source. A four-backtick outer example containing triple-backtick syntax stays an ordinary outer code fence.

Avoid a source/measurement cycle: each active document has one canonical fence-observation parser session started as an input observation capability, before any physical measurement or visible publication is required. It runs the same pinned Markdown parser with a non-DOM sink, reporting raw fence info, code prefix and closure. It is the only producer of semantic FenceObservation. Physical visible/probe Markdown parsers use that same implementation and ordinal rules only to reproduce text and targets, never send a second semantic observation or own a second DSL state. This is reuse of one parser implementation, not a regex split or multiple independent Markdown dialects. An ordinary model input can schedule a bounded parsing observation effect, whose callback is epoch/prefix-correlated; this is not a business action. The canonical session can parse without document fonts, layout, controls or Portal availability, so first UI definition acceptance never waits for its own measured view to be published.

Renderer must preserve one Markdown session per origin/epoch. Equal input: no parsing. Strict extension: append suffix. Non-prefix change/mode/origin replacement: dispose old parser/targets, increment epoch, reconstruct. `finish()` only on Complete or Interrupted. Ordinary Markdown must also benefit from append handling and no longer be disposed on every snapshot. Unclosed fence consumes its actual Markdown extent, never guesses recovery from a heading. Outside-block compatibility is relative to current parser, not a new CommonMark claim.

`whenCaughtUp(revision)` means parser/formatters have consumed that requested prefix and Portal targets are available; it does not require document EOF. Snapshot measurement waits for this prefix barrier. `whenSettled` can continue to mean true EOF for finished documents. Code/fence callbacks carry origin+epoch+actual prefix revision; accept an older callback only when that exact observed prefix remains an unchanged prefix of current input. Publication generation alone must not reject all observations during sustained streaming. Stale non-prefix epochs are rejected.

## 5. Language grammar and validation

Inside a fence the language is UTF-8 text with XML/JSX-like tags. Whitespace between tags is ignored. Exactly one `<ui id="...">` root. No text nodes, comments, processing instructions, spread attributes, namespaces, arbitrary HTML, escaped tag names or JavaScript blocks. Leaf components/declarations are self-closing; containers close with their exact tag name. Attributes are unique, quoted JSON string literals or brace-delimited expressions. Strings use JSON escapes including valid Unicode; braces inside strings do not terminate expression. No raw interpolation in labels; use expression-valued `label`/`value`/`message`. All IDs use `[A-Za-z][A-Za-z0-9_-]{0,63}`.

Top-level declarations before the first visual child:

```
<state id="seats" type="integer" initial={8} min={1} max={50} />
<state id="choice" type="enum" initial="standard" options={["standard","large"]} />
<state id="note" type="string" initial="" max-length={1000} />
<derive id="monthly" value={seats * 29} />
<source id="workflow" kind="task-graph" graph-id={42} mode="live" />
<dataset id="sales" columns={["id","month","amount"]} />
```

`state` types: integer, number, boolean, string, enum. Initial/type/bounds/options must be complete literals and validate at declaration time. Numeric min/max optional; integer step defaults 1; number step defaults 0.01; explicit step positive and representable. String max-length defaults 4096, maximum 16384 Unicode scalar values; enum options unique nonempty string list. IDs of state, derive, source and dataset share one namespace, no redefinition; derived expressions reference only earlier declarations, so no forward references/cycles. Template variables are lexical and cannot shadow these IDs or each other. State/source/derive declarations after a visual child are block definition errors. No declarations inside conditional/templates.

Append data is the sole post-layout data-declaration exception:

```
<row dataset="sales" key="jan" value={{id:"jan",month:"Jan",amount:200}} />
```

`row` is only a direct child of ui and may appear before/between/after visual children. Its value is a literal record matching declared dataset columns; key unique within dataset and scalar string. A duplicate/invalid complete row is locally diagnosed and skipped; prior rows remain. Dataset is append-only; no row overwrite or hidden state mutation. Table/chart referencing it can mount before any rows and update as rows arrive.

Unknown tag/attribute or wrong component property type is a local component error when lexical structure remains readable; render a named diagnostic occupying that component, and skip its subtree while checking structural closure. Invalid state/source/dataset declaration shape, duplicate declaration ID, root error, misplaced declaration, mismatched closing tag or broken lexical structure are fatal to that block's subsequent semantic acceptance. A syntactically complete uniquely named derive with unknown references or invalid expression type instead reserves a permanently erroneous derive binding, allowing its dependents to show dependency errors and unrelated components to continue. Malformed/incomplete derive syntax follows lexical/truncation rules; it is not silently skipped. Keep accepted tree/values, show diagnostic; never reinterpret committed ancestors or silently invent a closing tag. Runtime value failures are local, recover after valid input/source update, and disable affected actions.

## 6. Expression semantics

Values: null, Bool, bounded decimal Number, String, List<Value>, Record<String,Value>. Strings are data, never parsed as code/HTML. Records have unique static identifier/string keys. Lists and records may be literal or registered resource values. Expressions allow literals, identifier, `a.b` on record fields, `a[index]` on lists (integer nonnegative) or record string key, parenthesis, unary `!`/`-`, arithmetic `* / % + -`, numeric order, strict `== !=`, Boolean `&& ||`, conditional `? :`, and named registered pure function calls. Standard precedence, left associativity except conditional, lazy Boolean/conditional branches. No assignment, lambda, `new`, method calls, prototype, loops, recursion, import, global objects, optional JS coercion or arbitrary function values. Missing field/index returns null; using null with arithmetic yields a local type error. Record keys such as `__proto__` remain data and must never become JS object prototypes.

Numbers have deterministic signed fixed-decimal semantics: at most 6 fractional digits, magnitude <= 1,000,000,000; no exponent syntax. `integer` is the integral subset. Addition/subtraction exact within bound; multiply/divide round to 6 places, ties away from zero; divide/modulo zero and overflow are errors. `%` requires integers and follows signed remainder. `+` accepts Number+Number or String+String only. No implicit string conversion or NaN/Infinity. Equality is structural over same types and bounded values. Browser attributes/storage use canonical decimal strings, not lossy BigInt/Number conversion as semantic authority.

Registered functions for v1 (exact arity; wrong arity/type is local evaluation error):

| signature | result |
|---|---|
| len(String or List), count(List) | Number of Unicode scalars / list items |
| min(Number,Number), max(Number,Number), abs(Number) | Number |
| round(Number, integral Number 0..6) | Number, decimal ties away from zero |
| clamp(Number,Number,Number) | Number, error when lower > upper |
| sum(List<Record>,String fieldPath) | Number, empty list -> 0 |
| filter(List<Record>,String fieldPath, scalar) | stable List<Record> matching structural equality |
| sort(List<Record>,String fieldPath,String direction) | stable List<Record>, direction asc/desc |
| take(List,integral Number 0..4096) | first n items |
| text(null/Bool/Number/String) | String, null -> empty and Bool -> true/false |
| format(Number,String style) | String, style number/percent/currency:USD/currency:CNY |
| working(TaskObservation or null), awaitingHuman(TaskObservation or null) | Bool, null -> false |

Collection fieldPath is a nonempty dot-separated sequence of record field names; there is no executable predicate. Field absent/wrong type in numeric aggregate is an error; filter compares structurally (missing path is null); sort requires homogeneous non-null Number or String keys and preserves equal-item order. Format uses deterministic grouping and registered currency precision, not implementation-dependent locale. No object stringification. `working`/`awaitingHuman` read registered TaskObservation facts (a pure record with Bool working/awaitingHuman fields); malformed records error rather than invent task meaning. The exact public built-in registry is shared with model instructions.

Definition validation checks declared types and component obligations; source/record/list field lookups that cannot be established statically are checked during evaluation. Each accepted local or source update must produce derived and displayed values from that update's canonical inputs, preserve unrelated local state, and share one bounded evaluation budget. The implementation may recompute the declaration tree or use a dependency index; either strategy must satisfy these value, state-preservation and resource requirements.

## 7. Components and action contract

Common component properties: required unique lexical `id`, `visible={Bool}` default true, `enabled={Bool}` default true for interactive controls, `tone="neutral|accent|success|warning|danger|muted"`, `motion="none|pulse|spin"`, `transition="none|status"`. Tone/motion/transition may be expressions returning these enums. Hidden components do not own live DOM events and do not initialize/reset state on reappearance. Their declarations/values remain. Enabled=false disables only interaction, preserving display. Unknown enum is local error, not raw CSS.

Containers: `stack` (vertical), `row-layout` (horizontal wrapping), `grid` (columns 1..4, collapse to one when allocated width requires), `card` (optional label). `gap="none|sm|md|lg"`, normal spacing from existing design parameters. No user CSS/pixel placement. The data `row` tag and `row-layout` are intentionally distinct. Width bounded to containing allocation, overflow handled by component policy.

Leaves: `text label={String}`; `markdown value={String}` (Plain policy only, no recursive UI); `metric label={String} value={scalar} format="number|percent|currency:USD|currency:CNY"` optional formatting; `badge label={String}`. Text wraps; table/graph/chart have bounded scrollable viewport. Every empty collection has an explicit empty state.

Inputs: `slider bind="stateId" label="..."` for numeric state (min/max required on state); `number-input` for numeric; `text-input` / `textarea` for string; `checkbox` for boolean; `select` for enum. Bindings are literal IDs, state type validated. Inputs may not bind derive/source/dataset. Native field ownership carries instance+component+mount occurrence and schema identity. Invalid numeric edits retain raw entry with visible validation while last valid canonical value continues driving calculations; blur/Enter commits only if valid, never silently clamps. Slider values must match the declared step grid; off-grid edits retain the previous canonical value. Reset restores all root state defaults and graph view values, not source/dataset definitions. Labels are nonempty, native keyboard behavior and IME retained; slider native range semantics must be introduced into Source.NativeFieldKind/controls/native-fields rather than plain ad hoc `<input>`.

`button` requires nonempty label and action:

| action | properties and admitted effect |
|---|---|
| set | `target="stateId" value={expression}`; validate target schema, one local update |
| reset | no target/value; reset entire ui local/view values |
| draft | `message={String}`; place in owning task composer through existing draft-edit path; refuse if composer nonempty unless user explicitly clears it first |
| submit | `message={String}`; visible Send affordance; use owning task's ordinary Send through existing assessment/service/pending admission, capture text once |
| copy | `value={String}`; existing correlated clipboard capability, feedback only to requesting occurrence |
| openUrl | `url={String}`; existing Bend link policy and physical navigation, accepted user activation only |

Buttons cannot target arbitrary task IDs. Submit does not overwrite the user's composer and does not change task policy/settings. A block may submit only after its fence closes and document ending is Complete; streaming/Interrupted/fatal blocks keep local inputs usable but all external actions (draft/submit/copy/openUrl) disabled until complete. Reset/set remain available. All model-authored external actions in a block require every declared live source to be ready and fresh, including sources a particular button does not reference; local inputs/set/reset and host-authored fence copy/source disclosure remain available. Render/evaluation/restoration/animation never run actions. Pending submit has one owning ticket, disables that button until settlement, and follows existing committed effects rules; no retry from storage replay.

If another button submits the same in-flight command, it receives explicit duplicate feedback and leaves its pending state. The original request and its completion owner remain intact; no second command is sent.

`table rows={datasetOrList} row-key="field"` accepts `column id="..." field="..." label="..." format="..."` children, 1..16 columns. Stable unique scalar row key required; duplicate collection keys produce a collection diagnostic, do not alias DOM. Sorting is local via explicit user header action when `sortable={true}`; stable ordering, no mutation of source. Tables scroll horizontally and virtualize or paginate above 100 visible rows, show total/truncation explicitly.

`line-chart` / `bar-chart` use `data={datasetOrList}`, `row-key`, `x="field"`, `y="field"`, optional label/x-label/y-label. x is numeric or string category, y finite Number. Line preserves collection order; no implicit sorting. Missing/non-numeric values produce a clear local data error, not fake zeros. At most 512 plotted rows; if more, show count + bounded first 512 with explicit truncation. Authored SVG and accessible text/table summary; chart coordinates are computed in Bend using allocated logical geometry, browser only paints SVG. Native source data and values remain inspectable. No arbitrary SVG path source from model.

`when test={Bool}` conditional container; `each items={List} item="node" key="identity"` repeated container. `key` is a static record field path ending in nonempty String/integer; duplicates error the collection. Child IDs must be unique within lexical template, and expanded identities include stable item keys. Removing/reordering one item preserves unrelated nodes. No new state declarations in repetitions; input bindings refer existing root state. Limit expansion independently of source length.

## 8. Live sources and task graphs

v1 source registry contains only `task-graph`; fields `graph-id` (nonnegative Nat literal, including the actual first graph ID 0), `mode="live"` (required). It accepts either an integral Number literal within DSL bounds, or a canonical decimal digit String literal up to 64 digits for larger native Nat IDs. No arbitrary queries, world paths, network URLs, model tool calls or per-component polling. Source reference is bound once to declaring document's namespace and immutable ID. Shared resource observation cache is permitted; local UI state is never shared.

Projection is one pure Bend function of one accepted world snapshot/sequence. Graph topology, resolved node task IDs and tasks' observations come from this same world. Expose:

```
graph = {id, name, nodes, edges}
node = {identity, key, taskId, task}
task = null | {id, title, control, phase, working, awaitingHuman,
              pendingMessages, operations, statusLabel}
edge = {identity, ruleKey, sourceIdentity, targetIdentity, actionKind}
```

Node identity includes graph ID/node key/actual task ID. Edge identity includes rule key/action ordinal/source/target; support multiple edges, cycles and self-loops. Native IDs and source/world sequences are exposed as canonical decimal Strings, never clipped/rounded to DSL Number range. `control` preserves Active/Frozen/Stopped/Archived; `phase` preserves actual model/execution phase; operations summarize actual accepted stages, including approvals and execution/result processing. `working` and `statusLabel` reuse/extract existing application meaning, not a new competing inference. `awaitingHuman` is actual outstanding approval fact and may coexist with working. Null task means retained graph node whose task is absent; do not fabricate completion. Idle/Ready are never success. No whole-graph completion or DAG scheduling claim.

Source handle expression value = `{status, fresh, sequence, value}` where status is `loading|ready|missing|forbidden|error`, fresh Bool, value graph or null. At transport disconnection retain last authorized ready value, set fresh=false; no synthesized task transition. Missing from an accepted authoritative snapshot means missing and removes value. Explicit authorization failure/logout/permission revocation removes value and enters forbidden (do not retain restricted data). Mere network failure is not revocation. Invalid declaration means error; unavailable namespace means binding error. A successful accepted snapshot refreshes value; unrelated world changes preserve equal projection and do not restart motion. Connection freshness observations enter Bend through existing service boundary. Display “实时视图 / 上次同步” and stale state independently of model labels.

`resource-view source="workflow" let="graph"` binds only when source value is present, including stale authorized value. Other states use authored loading/missing/forbidden/error placeholders; stale adds banner and stops continuous activity motion. Its subtree cannot cause an application command by binding/unbinding.

`graph-view nodes={graph.nodes} edges={graph.edges} node-key="identity" layout="stable" select="selectedState"` has one optional `node-template item="node"` child. Default template is task-node. `task-node task={node.task} label={node.key}` shows current real state even if custom tone/motion expressions exist. Template supports ordinary containers/leaves/controls but no declarations. Graph built-in selection updates a root string state if `select` present; selected identity disappearing shows “原节点已移除” until user selects/clears; it never auto-selects another node. Built-in pan, zoom, fit controls and accessible node list are local view state. Graph topology-only changes recompute deterministic positions; task status changes preserve coordinates, zoom/pan and selected identity. Simple deterministic layered or grid placement with explicit cycle handling is valid; no force simulation required. At most 128 nodes/512 edges, otherwise source remains inspectable but graph shows limit diagnostic. All visual labels and real state accessible via list equivalent.

Live snapshots answer current state, not every intervening event. Do not animate transfer along an edge merely because a source task works. Exact receipt animation would need new stable event IDs and event-stream retention, excluded here.

## 9. Streaming acceptance, errors and resource bounds

Parser is incremental and commits complete tokens. A complete valid container start may mount; complete self-closing controls may mount immediately. Half tags/quoted strings/expressions remain buffered. For `<slider value={1` do not speculate that the value is 1. Later parse may add children but may not reinterpret already accepted properties/parentage. UI root closure plus actual fence closure seals definition. Only full document Complete enables external model actions.

Exhaustive update decision ordering: wrong origin/old epoch -> no-op; same text+ending -> no-op; non-prefix text/mode change -> new epoch and reset; strict suffix -> bounded incremental parse; after terminal ending any changed text -> new epoch; Complete/Interrupted with same prefix -> drain prefix and close parser, retain valid prefix, report incomplete tail. Duplicate ending idempotent. A closed fence with complete root succeeds; closing fence with unfinished root reports truncated block and retains accepted prefix. No fence closer is guessed by DSL parser. Structural fatal stops DSL acceptance to that fence's real end; subsequent Markdown and subsequent independent fences continue normally.

Resource budgets (central Bend constants, with the physical parser enforcing the text cap too): message 4 Mi UTF-16 units (existing); active UI fences 16 per message; each DSL fence 128 Ki Unicode scalars; depth 32; token/expression 8192 scalars; 128 declarations; 1024 accepted syntax components; 4096 expanded nodes; string max 16384; collection max 4096; record fields 64; dataset 4096 rows; expression depth 32; 100000 evaluator steps per block update; per parsing turn consume at most 256 bounded tokens then schedule continuation; graph/chart/table visible limits above. Budget failures are named local diagnostic when recoverable, fatal block stop when parser/definition budget, and never delete accepted state. Global message limit uses existing display failure behavior. Rendering all 16 blocks must share bounded scheduling rather than each claiming a frame.

Every user event validates current instance epoch, component lexical identity, current mount occurrence, actual current exposure+enabled, action kind/schema, and bounded payload. A stale removed/hidden/recreated component event is no-op with no effects. Value events contain state target but lookup authoritative current binding before applying (client target not authority). Current conditions/resources are re-evaluated at click time, not trusted from captured label. Template reordering does not change mount occurrence; unmount/remount does. Nonempty source dependencies must be fresh for external actions; local operations remain available. Pending result settlement updates only its owning ticket/occurrence; accepted real commands remain accepted if view later disappears.

## 10. Publication, measurement and motion

Local state is updated synchronously in semantic reducer; output parser and display work can be paced. Runtime separates `Latest{application,semanticRevision}` from `Measuring{frozenApplication,frozenScene,frozenSources,frozenFonts,frozenPrefix,generation}` and `Displayed{allocatedWorld,semantic,basis,revision}`. These are ownership carriers, not aliases of one mutable application. Completing a receipt changes Measuring/Displayed, never assigns frozenApplication back into Latest. It coalesces exactly one latest pending candidate and starts it immediately after current bounded measurement finishes. New token/source/input changes do not cancel the currently measuring candidate. Environment changes that invalidate physical meaning (viewport/font metrics) cancel/restart; ordinary app changes do not. Receipts remain generation-bound and pass current physical contracts.

Publication deliberately supports explicit presentation lag. A published candidate's entire evaluated tree (metrics, conditional regions, graph facts and source timestamps) belongs to its one frozen semantic revision. If that revision is older than Latest, a preallocated, already-measured status slot displays “正在更新显示”; source-bearing blocks retain their displayed snapshot sequence/time. Do not present old derived results as if computed from newer values. All model external actions are disabled while display lags. The marker is a presentation-only property update inside reserved geometry and does not wait for another measurement. After current publication, measure coalesced Latest; a caught-up display clears marker.

The sole native-input exception is the user's newer editing buffer: it remains visible as pending input and cannot be overwritten by publishing an older candidate. That buffer may show slider=12 while displayed snapshot metrics still represent 8, but reserved “正在更新显示” status makes the distinction explicit; no inconsistent unmarked scene is claimed. Native-field identity/value synchronization must compare delivered input revision with published revision, rather than blindly overlaying latest canonical fields and calling the result coherent. Pending raw text stays inside the previously allocated native field box (textarea scrolls); its larger natural height is measured only in a subsequent candidate, never grows page geometry outside admission. Checkbox/range/select retain fixed native geometry. Focus/selection/IME and newer canonical local state survive each old publication. Events/commands always revalidate Latest state, and lagged model external actions refuse. A 50 ms foreground response target for a small calculator is a measured quality goal, not a scheduler fairness proof.

Explicit authorization loss, namespace switch, current viewing-task removal or source access revocation is an immediate invalidation boundary: cancel/disallow any frozen candidate containing affected data, remove restricted source content and disable its events in a reserved recovery region without waiting for stale publication. Ordinary transport loss marks stale immediately and suppresses activity motion via reserved presentation properties; it may retain authorized last data. These physical invalidation effects are selected by Bend, not inferred from DOM. Later valid fresh observations rebuild normal candidates.

Measurement clones receive already accepted definition + canonical values + frozen resource observation + frozen prefix; build same authored scene and Portals. They never emit fence/code observations, create subscriptions, initialize state, save storage, dispatch controls, animate, or send commands. They use prefix caught-up barrier, not EOF. Prefix measurements remain generation-bound and validated; never accept an old receipt as belonging to a new generation. A bounded candidate must terminate in Ready or existing explicit recovery; do not claim global fairness proof from coalescing alone.

Motion vocabulary compiled by Bend into whitelisted physical presentation: pulse (opacity), spin (glyph transform), status (short tone/opacity transition <=200 ms). No geometry-changing CSS animation in v1. Same component identity+semantic motion value does not restart on every snapshot. Reduced-motion, document hidden, offscreen, stale source and isolated measurement disable continuous motion and show static informative state. Browser animation completion is not a semantic event. If node position transition is added, hit regions/focus/measurement must match animated position; v1 graph relocates topology deterministically without position animation. Layout and values continue updating with reduced motion.

## 11. Persistence and recovery

Use browser local storage through Bend-owned encode/decode/effects, scoped by current namespace + producerTask + viewingTask + operation + part + fenceOrdinal + uiId + schema version 1. In-memory state persists across route switch/render unmount; snapshot store saves only completed accepted final documents after user local/view changes, debounced physically but payload/revision selected by Bend. Preview values remain in memory and become eligible once final continuity succeeds. No restoration of previews after connection loss/process restart.

Snapshot stores exact complete DSL definition string (bounded) + typed state schema/defaults + values + graph view values, not only digest; restore requires exact definition and schema equality before any value installation, current source membership, same namespace/task origin. Comparison is canonical bounded literal equality, no hash-only authority. Restore once per instance before fresh user edit; an asynchronous restore arriving after user edit must not overwrite input. Validate each stored typed value/range and all total limits; bad entry rejected wholly and removed. Storage unavailable/quota failure leaves usable in-memory state with nonblocking notice, no fake saved state. One current schema, no migration; corrupt/unknown records rejected. Bend selects admissible snapshot payloads. The physical store retains at most 100 documents/5 MiB and evicts the oldest persisted entries to stay within those limits, without resetting active in-memory instances. Multi-tab last successful save wins for later restore, never live-merges into an open document. Reset persists defaults. Task deletion/namespace mismatch removes or renders entries unreachable; explicit authorization revocation removes sensitive live source values from DOM, not user inputs. Plain transport loss retains authorized stale source values.

Do not persist derived values, source data, parse tails, callbacks, pending copy/submit actions, tickets, motion time or DOM state. Recovering storage can only restore local values, no external effects. Sources are reacquired from fresh authorized application snapshots.

## 12. Model-facing capability and examples

Add one authoritative Bend capability instruction using existing model context/instruction construction. It gives exact fence grammar, ID/type rules, component/action/builtin registry, limits, no-JS/no-CSS rule, literal source binding, examples for calculator/table/chart/task graph, and state semantics. Native graph create/read tool returns real graph ID; instruction tells model to use returned IDs, not invent them. User request need not mention a new tool: model emits UI in assistant body. Source updates are not automatically model context; explicit user submit can format selected live values into message. The instruction never says every transition/event is captured or idle means completed.

Capability text is injected only into normal user-facing model requests, not approvals/compaction/internal helper text. It is a tracked constructed instruction with stable identity/content revision so request reuse and context reconstruction remain consistent. Add a NativeText{revision,content} observation source in the existing context definition construction, register the capability in KINDS, and interpret its descriptor as immutable provided text at the host boundary. Helper request input projections omit this kind. Capability mode on output derives from the actual request contract frozen in ModelPending. Do not make a fake tool whose only job is printing UI.

Calculator example:

```selvedge-ui
<ui id="team-cost">
  <state id="seats" type="integer" initial={8} min={1} max={50} />
  <derive id="monthly" value={seats * 29} />
  <stack id="layout" gap="md">
    <slider id="seat-input" label="人数" bind="seats" />
    <metric id="price" label="每月费用" value={monthly} format="currency:USD" />
    <button id="continue" label="填入输入框" action="draft" message={"按 " + text(seats) + " 个席位继续分析"} />
  </stack>
</ui>
```

Graph example:

```selvedge-ui
<ui id="workflow-monitor">
  <state id="selected" type="string" initial="" />
  <source id="workflow" kind="task-graph" graph-id={42} mode="live" />
  <resource-view id="resource" source="workflow" let="graph">
    <graph-view id="diagram" nodes={graph.nodes} edges={graph.edges} node-key="identity" layout="stable" select="selected">
      <node-template item="node">
        <task-node id="task" label={node.key} task={node.task} tone={awaitingHuman(node.task) ? "warning" : "neutral"} motion={workflow.fresh && working(node.task) ? "pulse" : "none"} transition="status" />
      </node-template>
    </graph-view>
  </resource-view>
</ui>
```

## 13. Verification of engineering behavior

Production contracts must independently state full decisions and intended writes: rejected stale/invalid events preserve complete state and emit no effects; accepted input updates exact owned field and preserves unrelated blocks; declarations initialize only once; prefix append retains user values; final origin correspondence; observe/evaluate/restore has no business effects; source projection from same snapshot; runtime candidate retention + native field update correspondence. Bind all to production functions through local provider and root proof assembly. Use imported list/iterator/map results where they match actual carriers; no second generic graph/state algebra, no axioms/holes/proof weakening. Parser/evaluator pure structural properties should be proved against independent syntax/meaning observations; native compiler/JSON/DOM remain tested boundaries.

Select tests by actual usage, observed faults, change risk, existing safeguards and maintenance/runtime cost. A requirement alone does not justify another test. The retained external-boundary and browser checks are described in [tests-bend/README.md](../../tests-bend/README.md); this design does not impose an additional test checklist. Browser checks use the real server and compiled production browser in Chromium. Record actual executed commands and failures; claim live provider acceptance only when it was exercised.

## 14. Display and input policies

- A chart uses a 480 by 240 logical canvas inside a viewport that follows its allocated width and scrolls horizontally. Axes, plotted values and the accessible summary describe the same ordered data. Nested field paths have the same meaning in all three.
- A current-namespace watch commit already covered by the accepted durable sequence needs no snapshot refresh while data is fresh, authorized and connected. Newer or malformed notices and recovery still request authoritative data.
- The pending marker covers all display revisions. External actions require publication to have reached the latest semantic change. Navigation attention alone does not invalidate an otherwise current action; it cannot clear an earlier semantic change. Event identity, mount occurrence and source/service permission still apply at activation.
- Numeric initial values, edits, assignments and restored values use an exact step grid anchored at `min`, or zero if absent. The default step is 1 for integers and 0.01 for numbers. Off-grid input retains the prior canonical value and reports validation; it is never silently clamped.
- Numeric spellings longer than 18 Unicode scalars are rejected before digit parsing. The separate 16384-scalar raw editor limit still applies. Component IDs may include hyphens; declaration and template identifiers used in expressions may not, because hyphen denotes subtraction.
- Code ordinals include fenced and indented code emitted by the pinned Markdown parser. Only eligible fenced code activates UI. The pinned parser recognizes backtick fences; other syntax retains its ordinary Markdown behavior.
- Restored graph/table views require an accepted declaration and exact typed instance path. A valid conditional view may remain dormant while its instance is absent; unknown paths or invalid fields reject the entry atomically. Saves omit disappeared dynamic instances without deleting their in-memory values.
- Authentication results belong to the current request namespace and pending ticket. A current authentication may settle after a newer world revision without installing its older snapshot. Obsolete tickets cannot restore access. Only an owned successful authentication starts the physical watch.
- Watch notices are handled in order. Replacing a watch aborts its reader and requests. A failed request carries its request-start namespace and sequence; it cannot revoke a newer accepted scope. Recovery never replays a command with an unknown outcome or a failed upload.
- Parsing uses bounded scheduled turns; field edits preserve bounded raw buffers. Continuous output and source updates must still allow publication and user interaction. These are browser acceptance requirements, not consequences of a token-count limit.
- Namespace replacement, explicit revocation and removal of the viewed task immediately invalidate hidden measurement probes as well as visible restricted content. Ordinary stream updates preserve a valid active measurement.
- A physical receipt must belong to its generation, owner, key and purpose. Width-specific heights also match width, and zero is a present measurement when that node permits it. An unusable first matching element cannot borrow valid properties from a later duplicate.
- Attachments follow the Markdown parser's shared code ordinal. Code tools precede UI at the same ordinal; equal-category payloads retain order and multiplicity, including UI whose code observation has not arrived. Source, viewing task and component identity remain part of ownership.
- Native fields resolve the complete current owner and mounted event before applying canonical values, raw editor text, enabled state or checkbox state. Fields may remain editable outside a temporary action scope; actions belong to the current foreground scope. Measurement and publication cannot overwrite newer native drafts or composition.
