import Base
import ./MODEL.bend as C
import ../../bendlib/json.bend as J

def kind() -> String:
  "interactive_markdown_v1"

def revision() -> String:
  "3"

def text_part_00() -> String:
  "Interactive Markdown v1 is available in ordinary assistant replies. Use normal Markdown freely. To create local interactive content, emit a fenced code block whose entire info string is exactly selvedge-ui. Do not call a tool just to print conversation UI. For the persistent shared UI belonging to a Work, use read_work_ui and apply_work_ui_patch instead: these infer the calling Task's Work and read or edit the same DSL as raw source, without Markdown fences. They are separate from emitting a streaming conversation interface. Do not emit JavaScript, HTML, CSS, event callbacks, or scripts. Other fences and Markdown retain their ordinary meaning.\nThe fence contains exactly one <ui id=\"name\"> root. IDs match [A-Za-z][A-Za-z0-9_-]{0,63}; every component requires a unique lexical id. Declaration IDs for state/derive/source/dataset and template variable names must additionally be expression identifiers [A-Za-z][A-Za-z0-9_]{0,63}, without hyphens; true, false and null are reserved literals and cannot be binding names. Attributes are JSON-quoted strings or {expressions}; no text nodes, comments, duplicate attributes, spread props, or arbitrary tags. Leaves self-close; containers close with the matching name. You may stream complete declarations/components progressively. Never change earlier declarat"

def text_part_01() -> String:
  "ions. Keep blocks small.\nBefore the first visual child declare root values: <state id=\"seats\" type=\"integer\" initial={8} min={1} max={50} />; supported types integer, number, boolean, string, enum. Enum uses literal options={[\"a\",\"b\"]}; string accepts max-length (default 4096, max 16384). Numeric step is positive, min/max optional except slider requires both. State initial/bounds/options are literals. <derive id=\"cost\" value={seats * 29} /> references only earlier bindings. <source id=\"workflow\" kind=\"task-graph\" graph-id={42} mode=\"live\" /> binds a real task graph ID returned by the graph creation/read tool; never invent IDs. <dataset id=\"sales\" columns={[\"id\",\"month\",\"amount\"]} /> declares append-only data. Declarations share one namespace and cannot be repeated or nested. <row dataset=\"sales\" key=\"jan\" value={{id:\"jan\",month:\"Jan\",amount:200}} /> is the only declaration allowed after visual children; each row is a literal record with exactly the dataset columns and unique key.\nExpressions support null, boo"

def text_part_02() -> String:
  "leans, bounded decimals, strings, lists, records, earlier identifiers, record.field, list[index], parentheses, !, unary -, + - * / %, < <= > >= == !=, lazy && || and condition ? yes : no. No assignment, loops, functions, methods, imports, globals, coercion, or executable predicates. Numbers have at most 6 decimal places and magnitude <=1000000000. Arithmetic overflow/division by zero is an error. + joins two strings or adds two numbers; use text(number) to convert explicitly. Builtins: len, min, max, abs, round(number,digits0to6), clamp, sum(list,field), count(list), filter(list,field,scalarEquals), sort(list,field,\"asc\"|\"desc\"), take(list,n), text(scalar), format(number,\"number\"|\"percent\"|\"currency:USD\"|\"currency:CNY\"), working(task), awaitingHuman(task).\nContainers: stack, row-layout, grid(columns1to4), card(optional label); gap is none|sm|md|lg. Leaves: text(label string), markdown(value string, ordinary Markdown only), metric(label,value,optional format), badge(label). Common visible/enabled are boolean e"

def text_part_03() -> String:
  "xpressions; tone neutral|accent|success|warning|danger|muted, motion none|pulse|spin, transition none|status. Never choose arbitrary CSS. Motion follows user preferences and stale sources stop continuous activity effects.\nInputs bind only root state by literal bind=\"stateId\": slider, number-input, text-input, textarea, checkbox, select. Every input has nonempty label. State survives stream appends and source updates. Invalid edits retain last valid value with validation. Buttons require label and action: set(target,value), reset, draft(message), submit(message), copy(value), openUrl(url). draft places text in the current task composer only if empty; submit explicitly sends a captured message through ordinary task admission and must have an explicit Send label. External model actions stay disabled until the whole reply completes successfully; inherited UI in another task remains locally interactive but cannot run model external actions. Rendering/source changes/restoration never trigger actions. All model-authored"

def text_part_04() -> String:
  " external actions require every declared live source to be ready and fresh.\nwhen(test bool) conditionally contains visual components. each(items list,item=\"node\",key=\"identity\") repeats a visual template with stable unique scalar record keys. Template variables cannot shadow declarations or other template variables; no declarations in templates. Root state is shared by repeated input bindings. table(rows list or dataset,row-key=\"id\",sortable={true}) has 1..16 column children(id,field,label,optional format). Tables paginate above 100 rows. line-chart/bar-chart(data,row-key,x,y,optional label/x-label/y-label) plot up to 512 records in collection order and show truncation; y must be numeric and missing data is an error. No implicit line sorting.\nA live source handle is {status,fresh,sequence,value}; status loading|ready|missing|forbidden|error and value is a graph or null. Use <resource-view id=\"resource\" source=\"workflow\" let=\"graph\"> to bind an available graph, including stale authorized data. The authored wrapper displays freshness an"

def text_part_05() -> String:
  "d errors. Graph={id,name,nodes,edges}; node={identity,key,taskId,task}; task is null or {id,title,control,phase,working,awaitingHuman,pendingMessages,operations,statusLabel}. Edge={identity,ruleKey,sourceIdentity,targetIdentity,actionKind}. Use <graph-view id=\"diagram\" nodes={graph.nodes} edges={graph.edges} node-key=\"identity\" layout=\"stable\" select=\"selected\"> with optional <node-template item=\"node\"><task-node id=\"task\" label={node.key} task={node.task} motion={workflow.fresh && working(node.task) ? \"pulse\" : \"none\"} /></node-template>. selected is an optional declared string state. Graph pan/zoom/selection are local. Task idle/Ready never means successful completion. Task phases and approvals may coexist. Graph edges describe forwarding rules, not proof of current transfer. Live snapshots show current state, not every intervening event. Live changes do not automatically enter model context.\nLimits: at most 16 UI fences per reply. Fence source has an independent 128 Ki Unicode-scalar cap. Semantic definiti"

def text_part_06() -> String:
  "on validation has a 100000-work-unit budget and precharges 2 units per source scalar, so a definition is limited to 49999 scalars (about 50k); complex definitions may exhaust work earlier and report a diagnostic. Parsing advances at most 256 syntax tokens per turn with 8192 parser work units per token. Other limits: nesting32, 128 declarations, 1024 syntax components, 4096 expanded nodes/collection rows, record64 fields, expression8192 scalars/depth32, graph128 nodes/512 edges. Keep definitions concise and comfortably below these limits; include explicit empty states. Malformed blocks preserve accepted controls and source; other Markdown continues.\nCalculator example:\n```selvedge-ui\n<ui id=\"team-cost\">\n  <state id=\"seats\" type=\"integer\" initial={8} min={1} max={50} />\n  <derive id=\"monthly\" value={seats * 29} />\n  <stack id=\"layout\" gap=\"md\">\n    <slider id=\"seat-input\" label=\"人数\" bind=\"seats\" />\n    <metric id=\"price\" label=\"每月费用\" value={monthly} format=\"currency:USD\" />\n    <button id=\"continue\" label=\"填入输入"

def text_part_07() -> String:
  "框\" action=\"draft\" message={\"按 \" + text(seats) + \" 个席位继续分析\"} />\n  </stack>\n</ui>\n```\nTable/chart example:\n```selvedge-ui\n<ui id=\"sales-report\">\n  <dataset id=\"sales\" columns={[\"id\",\"month\",\"amount\"]} />\n  <table id=\"details\" rows={sales} row-key=\"id\"><column id=\"month\" field=\"month\" label=\"月份\" /><column id=\"amount\" field=\"amount\" label=\"收入\" format=\"currency:CNY\" /></table>\n  <bar-chart id=\"trend\" data={sales} row-key=\"id\" x=\"month\" y=\"amount\" label=\"月收入\" />\n  <row dataset=\"sales\" key=\"jan\" value={{id:\"jan\",month:\"Jan\",amount:200}} />\n</ui>\n```\nTask graph example (replace42 with the real returned graph ID):\n```selvedge-ui\n<ui id=\"workflow-monitor\">\n  <state id=\"selected\" type=\"string\" initial=\"\" />\n  <source id=\"workflow\" kind=\"task-graph\" graph-id={42} mode=\"live\" />\n  <resource-view id=\"resource\" source=\"workflow\" let=\"graph\">\n    <graph-view id=\"diagram\" nodes={graph.nodes} edges={graph.edges} node-key=\"identity\" layout=\"stable\" select=\"selected\" />\n  </resource-view>\n</ui>\n```"

def text() -> String:
  text_part_00() ++ (text_part_01() ++ (text_part_02() ++ (text_part_03() ++ (text_part_04() ++ (text_part_05() ++ (text_part_06() ++ (text_part_07())))))))

def definition() -> C.Definition:
  C.text_context(kind(), "The runtime supports the following assistant output capability.", C.GlobalScope{},
    C.NativeText{revision(), text()}, [C.IdentityField{"capability", C.Constant{"interactive-markdown-v1"}, True{}}])

def key() -> C.Key:
  C.ContextKey{definition(), [C.FieldValue{"capability", "interactive-markdown-v1"}]}

def snapshot_matches(snapshot: Maybe<&2, C.Snapshot>) -> Bool:
  match snapshot:
    case None{}: False{}
    case Some{C.Snapshot{key, actual_revision, C.Record{actual_kind, fields}}}:
      String.eq(actual_revision, revision()) && String.eq(actual_kind, kind()) && String.eq(C.field_text(fields, "content"), text())

def available(bindings: +List<C.Snapshot>) -> Bool:
  snapshot_matches(C.find(bindings, key()))

def is_capability_message(+message: J.Json) -> Bool:
  String.eq(J.text(J.get(message, "role")), "task_context") &&
    (String.eq(J.text(J.get(J.get(J.get(message, "change"), "key"), "type")), kind()) ||
     String.eq(J.text(J.get(J.get(J.get(J.get(message, "change"), "snapshot"), "key"), "type")), kind()))

def keep_helper_message(capability: Bool, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match capability:
    case True{}: rest
    case False{}: message <> rest

def helper_history(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{+message, rest}: keep_helper_message(is_capability_message(message), message, helper_history(rest))
