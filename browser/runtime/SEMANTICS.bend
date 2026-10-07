import ../document/presentation-order.bend as Order
import ../../interaction/submission/MODEL.bend as Receipt
import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../harness/MODEL.bend as M
import ../../interaction/MODEL.bend as Product
import ../../features/board/MODEL.bend as Board
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/services/CONTEXT.bend as Context
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/conversation/OUTPUT.bend as Live
import ../focus/MODEL.bend as Focus
import ../editor/MODEL.bend as Editor
import ../reading/MODEL.bend as Reading
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../bendlib/json.bend as J
import ../../harness/DOMAIN.bend as D
import ../../harness/transport/command-codec.bend as Codec
import ../MODEL.bend as Web
import ./PLATFORM.bend as Platform
import ../document/RENDERED.bend as Rendered
import ../appearance/FONT.bend as F
import ./request.bend as Request
type RequestStatus is Data:
  AwaitingReceipt{}
  OutcomeUnknown{reason: String}
type Pending is Data:
  Pending{ticket: Nat, completion: E.Completion, command: J.Json, origin: String, status: RequestStatus}
type State is Data:
  State{web: Web.State, sequence: Nat, next_ticket: Nat, pending: +List<Pending>, receipt: Maybe<&2, Receipt.Receipt>}
def web(state: State) -> Web.State:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  value_web

def sequence(state: State) -> Nat:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  value_sequence

def next_ticket(state: State) -> Nat:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  value_next_ticket

def pending(state: State) -> +List<Pending>:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  value_pending

def receipt(state: State) -> Maybe<&2, Receipt.Receipt>:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  value_receipt

def with_web(value: Web.State, state: State) -> State:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  State{value, value_sequence, value_next_ticket, value_pending, value_receipt}

type Input is Data:
  Native{input: Web.Input}
  Snapshot{sequence: Nat, program: M.World()}
  Completed{ticket: Nat, sequence: Nat, program: M.World(), reply: J.Json}
  Failed{ticket: Nat, error: String}
  Rejected{ticket: Nat, error: String}
type Effect is Data:
  BrowserEffect{effect: Web.Effect}
  Command{ticket: Nat, command: J.Json}
  Service{effect: Services.Effect}
  Directories{ticket: Nat, workspace: D.Workspace}
  RenderingFailed{generation: Nat, violations: +List<Rendered.Violation>}
type Decision is Data:
  Decision{state: State, effects: +List<Effect>}
type OutsideDecision is Data:
  OutsideDecision{handled: Bool, decision: Decision}
type KeyResult is Data:
  KeyResult{handled: Bool, decision: Decision}
def with_receipt(value: Maybe<&2, Receipt.Receipt>, state: State) -> State:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  State{value_web, value_sequence, value_next_ticket, value_pending, value}

def with_pending(value: +List<Pending>, state: State) -> State:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  State{value_web, value_sequence, value_next_ticket, value, value_receipt}

def with_next_ticket(value: Nat, state: State) -> State:
  State{value_web, value_sequence, value_next_ticket, value_pending, value_receipt} = state
  State{value_web, value_sequence, value, value_pending, value_receipt}

def initial(program: M.World(), sequence: Nat) -> State:
  State{Web.initial(program), sequence, 0n, Nil{}, None{}}

def program(+state: State) -> M.World():
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_core_3 = Platform.core(observed_application_2)
  +observed_application_4 = Core.application(observed_core_3)
  +program = E.program(observed_application_4)
  program

def choose_found(same: Bool, entry: Pending, rest: Maybe<&2, Pending>) -> Maybe<&2, Pending>:
  match same:
    case True{}: Some{entry}
    case False{}: rest

def find(pending: +List<Pending>, +ticket: Nat) -> Maybe<&2, Pending>:
  match pending:
    case Nil{}: None{}
    case Con{+entry, rest}:
      Pending{current, completion, text, origin, status} = entry
      choose_found(Nat.is_eq(current, ticket), entry, find(rest, ticket))

def contains_command(pending: +List<Pending>, +command: J.Json) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{Pending{ticket, completion, current, origin, status}, rest}: J.same(current, command) || contains_command(rest, command)

def busy(pending: +List<Pending>, +key: String) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{Pending{ticket, completion, text, origin, status}, rest}: String.eq(origin, key) || busy(rest, key)

def mask_meaning(blocked: Bool, meaning: InterfaceView.Meaning) -> InterfaceView.Meaning:
  match blocked meaning:
    case True{} InterfaceView.ComposerAction{subject, input, availability}: InterfaceView.ComposerAction{subject, input, View.Unavailable{"Request pending"}}
    case True{} InterfaceView.Activate{input, availability}: InterfaceView.Activate{input, View.Unavailable{"Request pending"}}
    case True{} InterfaceView.Choice{kind, icon, selected, description, input, availability}: InterfaceView.Choice{kind, icon, selected, description, input, View.Unavailable{"Request pending"}}
    case _ other: other

def mask_nodes(nodes: +List<InterfaceView.Node>, +pending: +List<Pending>) -> +List<InterfaceView.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{InterfaceView.Node{+key, semantic, label, role, meaning, children}, rest}:
      InterfaceView.Node{key, semantic, label, role, mask_meaning(busy(pending, UIIdentity.encode(key)), meaning), mask_nodes(children, pending)} <> mask_nodes(rest, pending)

def mask_surface(surface: InterfaceView.Surface, +pending: +List<Pending>) -> InterfaceView.Surface:
  InterfaceView.Surface{content, base, overlays, scope} = surface
  InterfaceView.Surface{content, mask_nodes(base, pending), mask_nodes(overlays, pending), scope}

def wrap_web(effects: +List<Web.Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: BrowserEffect{effect} <> wrap_web(rest)

def wrap_services(effects: +List<Services.Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: Service{effect} <> wrap_services(rest)

def append_decision(first: +List<Effect>, decision: Decision) -> Decision:
  Decision{state, later} = decision
  Decision{state, List.append(&2, Effect, first, later)}

def origin(input: Web.Input) -> String:
  match input:
    case Web.ElementInput{key, gesture}: key
    case _: ""

def empty() -> M.World():
  M.initial()

def code_key(source: Code.Source, ordinal: Nat) -> String:
  Code.dom_key(Code.Identity{source, ordinal})

def prefer_key(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback

def credential_key(nodes: +List<InterfaceView.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{InterfaceView.Node{key, semantic, label, role, InterfaceView.EnterCredential{entered}, children}, rest}: Some{UIIdentity.encode(key)}
    case Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}: prefer_key(credential_key(children), credential_key(rest))

def connect_key(nodes: +List<InterfaceView.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{InterfaceView.Node{key, semantic, label, role, InterfaceView.ComposerAction{subject, Core.ServiceInput{Services.Connect{}}, availability}, children}, rest}: Some{UIIdentity.encode(key)}
    case Con{InterfaceView.Node{key, semantic, label, role, InterfaceView.Activate{Core.ServiceInput{Services.Connect{}}, availability}, children}, rest}: Some{UIIdentity.encode(key)}
    case Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}: prefer_key(connect_key(children), connect_key(rest))

def choose_removed(same: Bool, entry: Pending, rest: +List<Pending>) -> +List<Pending>:
  match same:
    case True{}: rest
    case False{}: entry <> rest

def remove(pending: +List<Pending>, +ticket: Nat) -> +List<Pending>:
  match pending:
    case Nil{}: Nil{}
    case Con{+entry, rest}:
      Pending{current, completion, text, origin, status} = entry
      choose_removed(Nat.is_eq(current, ticket), entry, remove(rest, ticket))

def request_ready(duplicate: Bool, +command: J.Json, completion: E.Completion, origin: String, state: State) -> Decision:
  match duplicate:
    case True{}: Decision{state, Nil{}}
    case False{}:
      State{web, sequence, +next, pending, receipt} = state
      Decision{State{web, sequence, (next + 1n : Nat), List.append(&2, Pending, pending, [Pending{next, completion, command, origin, AwaitingReceipt{}}]), None{}}, [Command{next, command}]}

def count_gesture(value: Maybe<&2, Nat>) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case None{}: None{}
    case Some{count}: Some{InterfaceView.Change{Forms.Count{count}}}

def entry_text(entry: Forms.Entry, text: String) -> Maybe<&2, InterfaceView.Gesture>:
  match entry:
    case Forms.PositiveInteger{}:
      count_gesture(Nat.read(text))
    case Forms.DisplayOnly{}: None{}
    case Forms.FileCollection{}: None{}
    case Forms.DirectoryCollection{}: Some{InterfaceView.Directory{text}}
    case _: Some{InterfaceView.Change{Forms.Text{text}}}

def collected_finish(decision: Decision, web: +List<Web.Effect>, services: +List<Services.Effect>) -> Decision:
  Decision{state, requests} = decision
  Decision{state, List.append(&2, Effect, wrap_web(web), List.append(&2, Effect, requests, wrap_services(services)))}

def semantic_surface(+capacity: View.Capacity, +state: State) -> InterfaceView.Surface:
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +core = Platform.core(observed_application_2)
  Order.ordered_surface(mask_surface(InterfaceView.with_receipt(InterfaceView.observe(capacity, core), receipt), pending))

def nodes(+state: State) -> +List<InterfaceView.Node>:
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +capacity = Platform.capacity(observed_platform_3)
  InterfaceView.active_nodes(semantic_surface(capacity, state))

def found_node(+key: String, state: State) -> Maybe<&2, InterfaceView.Node>:
  InterfaceView.find_node(nodes(state), key)

def stream_parts(parts: +List<J.Json>) -> +List<Live.Part>:
  match parts:
    case Nil{}: Nil{}
    case Con{+part, rest}: Live.Part{J.natural_or(J.natural(J.get(part, "output_index")), 0n), J.text(J.get(part, "text"))} <> stream_parts(rest)

def stream_output(+value: J.Json) -> Live.Output:
  Live.Output{J.natural_or(J.natural(J.get(value, "task_id")), 0n), J.natural_or(J.natural(J.get(value, "ticket")), 0n), stream_parts(J.items(J.get(value, "parts")))}

def search_filter(filter: Board.Filter, text: String) -> Board.Filter:
  Board.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  Board.Filter{view, text, status, priority, date, assignee, creator, project, label}

def project_origin(value: Maybe<&2, Nat>) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case Some{id}: Some{InterfaceView.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ProjectDefaults{id}}}}}
    case None{}: None{}

def parent_origin(value: Maybe<&2, Nat>) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case Some{id}: Some{InterfaceView.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ParentTask{id}}}}}
    case None{}: None{}

def project_parent_origin(task: Maybe<&2, Nat>, project: Maybe<&2, Nat>) -> Maybe<&2, InterfaceView.Gesture>:
  match task project:
    case Some{task} Some{project}: Some{InterfaceView.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ProjectForParent{task, project}}}}}
    case _ _: None{}

def origin_gesture(parts: +List<String>) -> Maybe<&2, InterfaceView.Gesture>:
  match parts:
    case Con{"environment", Nil{}}: Some{InterfaceView.Change{Forms.ContextChange{Context.ChooseOrigin{Context.EnvironmentDefaults{}}}}}
    case Con{"project", Con{id, Nil{}}}: project_origin(Nat.read(id))
    case Con{"parent", Con{id, Nil{}}}: parent_origin(Nat.read(id))
    case Con{"project-for-parent", Con{task, Con{project, Nil{}}}}: project_parent_origin(Nat.read(task), Nat.read(project))
    case _: None{}

def sandbox_mode(sandbox: D.Sandbox, text: String) -> Maybe<&2, InterfaceView.Gesture>:
  D.Sandbox{mode, network} = sandbox
  match text:
    case "workspace-write": Some{InterfaceView.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{D.WorkspaceWrite{}, network}}}}}
    case "read-only": Some{InterfaceView.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{D.ReadOnly{}, network}}}}}
    case _: None{}

def sandbox_gesture(value: Forms.Observed, text: String) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: sandbox_mode(Context.unwrap_sandbox(sandbox), text)
    case _: None{}

def model_field(profile: String, reasoning: String, text: String, effort: Bool) -> Maybe<&2, InterfaceView.Gesture>:
  match effort:
    case False{}: Some{InterfaceView.Change{Forms.Model{text, reasoning}}}
    case True{}: Some{InterfaceView.Change{Forms.Model{profile, text}}}

def model_gesture(value: Forms.Observed, text: String, effort: Bool) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case Forms.ModelValue{profile, reasoning}: model_field(profile, reasoning, text, effort)
    case _: None{}

def delivery_gesture(text: String) -> Maybe<&2, InterfaceView.Gesture>:
  match text:
    case "send": Some{InterfaceView.Change{Forms.Delivery{U.Send{}}}}
    case "steer": Some{InterfaceView.Change{Forms.Delivery{U.Steer{}}}}
    case _: None{}

def assistance_gesture(value: Forms.Observed, text: String) -> Maybe<&2, InterfaceView.Gesture>:
  match value:
    case Forms.AssistanceValue{enabled, profile}: Some{InterfaceView.Change{Forms.Assistance{enabled, text}}}
    case _: None{}

def optional_text(text: String) -> Maybe<&2, String>:
  match text:
    case "": None{}
    case text: Some{text}

def current_draft(+state: State, editor: U.Editor) -> Maybe<&2, U.Draft>:
  State{+observed_state_1, sequence, ticket, requests, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_core_3 = Platform.core(observed_application_2)
  +observed_application_4 = Core.application(observed_core_3)
  +observed_session_5 = E.session(observed_application_4)
  +drafts = E.drafts(observed_session_5)
  E.find_draft(drafts, editor)

def retained_messages(messages: Maybe<&2, +List<String>>, fallback: +List<String>) -> +List<String>:
  match messages:
    case None{}: fallback
    case Some{values}: values

def fork_gesture(draft: Maybe<&2, U.Draft>, count: Maybe<&2, Nat>, messages: Maybe<&2, +List<String>>) -> Maybe<&2, InterfaceView.Gesture>:
  match draft:
    case Some{U.Draft{revision, U.Fork{task, old_count, old_messages, config}, feedback, directory_entry}}:
      Some{InterfaceView.Change{Forms.Fork{J.natural_or(count, old_count), retained_messages(messages, old_messages)}}}
    case _: None{}

def network_gesture(sandbox: D.Sandbox, enabled: Bool) -> Maybe<&2, InterfaceView.Gesture>:
  D.Sandbox{mode, network} = sandbox
  Some{InterfaceView.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{mode, enabled}}}}}

def toggle_gesture(found: Maybe<&2, InterfaceView.Node>, enabled: Bool) -> Maybe<&2, InterfaceView.Gesture>:
  match found:
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{previous, profile}, choices}, children}}: Some{InterfaceView.Change{Forms.Assistance{enabled, profile}}}
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, choices}, children}}: network_gesture(Context.unwrap_sandbox(sandbox), enabled)
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.Edit{editor, field, entry, Forms.ToggleValue{previous}, choices}, children}}: Some{InterfaceView.Change{Forms.Toggle{enabled}}}
    case _: None{}

def pending_of(state: State) -> +List<Pending>:
  State{web, sequence, next, pending, receipt} = state
  pending

def request_payload(command: M.Command) -> J.Json:
  Request.client(Codec.command_json(command))

def collect_one(effect: E.Effect, origin: String, +state: State) -> Decision:
  match effect:
    case E.RequestCommand{command, completion}:
      +wire = request_payload(command)
      request_ready(contains_command(pending_of(state), wire), wire, completion, origin, state)
    case E.ObserveDirectories{ticket, entered}: Decision{state, [Directories{ticket, entered}]}
    case _: Decision{state, Nil{}}

def collect_loop(interaction: +List<E.Effect>, +origin: String, accumulator: Decision) -> Decision:
  match interaction accumulator:
    case Nil{} Decision{state, effects}: Decision{state, effects}
    case Con{effect, rest} Decision{state, effects}:
      collect_loop(rest, origin, append_decision(effects, collect_one(effect, origin, state)))

def collect(interaction: +List<E.Effect>, origin: String, state: State) -> Decision:
  collect_loop(interaction, origin, Decision{state, Nil{}})

def finish(decision: Web.Decision, sequence: Nat, next: Nat, pending: +List<Pending>, origin: String, receipt: Maybe<&2, Receipt.Receipt>) -> Decision:
  Web.Decision{+web, Core.Decision{core, reply, runtime, interaction, services, durable}, effects} = decision
  collected_finish(collect(interaction, origin, State{web, sequence, next, pending, receipt}), effects, services)

def observe_frame(received: Nat, surface: InterfaceView.Surface, frame: Rendered.Frame, state: State) -> Decision:
  State{web, sequence, next, pending, receipt} = state
  finish(Web.observe_frame(received, surface, frame, web), sequence, next, pending, "", receipt)

def native_element(blocked: Bool, +key: String, gesture: InterfaceView.Gesture, state: State) -> Decision:
  match blocked:
    case True{}: Decision{state, Nil{}}
    case False{}:
      State{web, sequence, next, pending, receipt} = state
      finish(Web.step(Web.ElementInput{key, gesture}, web), sequence, next, pending, key, receipt)

def native_state(state: State, event: Web.Input) -> Decision:
  State{+web, sequence, next, +pending, receipt} = state
  match event:
    case Web.ElementInput{+key, gesture}:
      native_element(busy(pending, key), key, gesture, State{web, sequence, next, pending, receipt})
    case +other: finish(Web.step(other, web), sequence, next, pending, origin(other), receipt)

def native(event: Web.Input, +state: State) -> Decision:
  native_state(state, event)

def product_input(input: Product.Input, state: State) -> Decision:
  native(Web.PlatformInput{Platform.ProductInput{input}}, state)

def activate(key: String, state: State) -> Decision:
  match key:
    case "@browser/retry": native(Web.Mount{}, state)
    case other: native(Web.ElementInput{other, InterfaceView.Press{}}, state)

def apply_gesture(gesture: Maybe<&2, InterfaceView.Gesture>, key: String, state: State) -> Decision:
  match gesture:
    case None{}: Decision{state, Nil{}}
    case Some{gesture}: native(Web.ElementInput{key, gesture}, state)

def edit_toggle(+key: String, enabled: Bool, +state: State) -> Decision:
  apply_gesture(toggle_gesture(found_node(key, state), enabled), key, state)

def attach(key: String, file: Services.SelectedFile, state: State) -> Decision:
  native(Web.ElementInput{key, InterfaceView.Attach{file}}, state)

def place(key: String, target: String, state: State) -> Decision:
  native(Web.ElementInput{key, InterfaceView.Place{target}}, state)

def code_source(source: Code.Source, ordinal: Nat, text: String, state: State) -> Decision:
  product_input(Product.CodeSource{Code.Identity{source, ordinal}, text}, state)

def directory_count_same(same: Bool, rest: Nat) -> Nat:
  match same:
    case True{}: (rest + 1n : Nat)
    case False{}: rest

def directory_field_count(fields: +List<J.Field>, +name: String) -> Nat:
  match fields:
    case Nil{}: 0n
    case Con{J.Field{key, value}, rest}: directory_count_same(String.eq(key, name), directory_field_count(rest, name))

def directory_fields_present(+fields: +List<J.Field>, names: +List<String>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{name, rest}: Nat.is_eq(directory_field_count(fields, name), 1n) && directory_fields_present(fields, rest)

def directory_shape(value: J.Json, +names: +List<String>) -> Bool:
  match value:
    case J.Object{+fields}: Nat.is_eq(List.length(&2, J.Field, fields), List.length(&2, String, names)) && directory_fields_present(fields, names)
    case _: False{}

def directory_entry_valid(valid: Bool, name: String, path: String) -> Result<&2, &2, String, Services.DirectoryEntry>:
  match valid:
    case True{}: Done{Services.DirectoryEntry{name, path}}
    case False{}: Fail{"Invalid folder entry"}

def directory_entry_fields(shape: Bool, name: J.Json, path: J.Json) -> Result<&2, &2, String, Services.DirectoryEntry>:
  match shape name path:
    case True{} J.Text{+name} J.Text{+path}:
      directory_entry_valid(Bool.not(String.is_empty(name)) && String.starts_with(path, "/"), name, path)
    case _ _ _: Fail{"Invalid folder entry"}

def directory_entry(+value: J.Json) -> Result<&2, &2, String, Services.DirectoryEntry>:
  directory_entry_fields(directory_shape(value, ["name", "path"]), J.get(value, "name"), J.get(value, "path"))

def directory_entry_cons(entry: Result<&2, &2, String, Services.DirectoryEntry>,
  rest: Result<&2, &2, String, +List<Services.DirectoryEntry>>) -> Result<&2, &2, String, +List<Services.DirectoryEntry>>:
  match entry rest:
    case Done{value} Done{values}: Done{value <> values}
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}

def directory_entries(values: +List<J.Json>) -> Result<&2, &2, String, +List<Services.DirectoryEntry>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Con{value, rest}: directory_entry_cons(directory_entry(value), directory_entries(rest))

def directory_parent_valid(valid: Bool, path: String, up: String, entries: +List<Services.DirectoryEntry>, truncated: Bool) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  match valid:
    case True{}: Done{Services.DirectoryCatalog{path, Some{up}, entries, truncated}}
    case False{}: Fail{"Invalid parent folder"}

def directory_catalog_valid(valid: Bool, path: String, parent: J.Json, values: Result<&2, &2, String, +List<Services.DirectoryEntry>>,
  truncated: Bool) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  match valid parent values:
    case True{} J.Null{} Done{entries}: Done{Services.DirectoryCatalog{path, None{}, entries, truncated}}
    case True{} J.Text{+up} Done{entries}: directory_parent_valid(String.starts_with(up, "/"), path, up, entries, truncated)
    case _ _ Fail{reason}: Fail{reason}
    case _ _ _: Fail{"Invalid folder catalog"}

def directory_catalog(+path: String, parent: J.Json, values: Result<&2, &2, String, +List<Services.DirectoryEntry>>,
  truncated: Bool) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  directory_catalog_valid(String.starts_with(path, "/"), path, parent, values, truncated)

def directory_response_failure(shape: Bool, error: J.Json) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  match shape error:
    case True{} J.Text{reason}: Fail{reason}
    case _ _: Fail{"Invalid folder listing failure"}

def directory_response_success(shape: Bool, path: J.Json, entries: J.Json, truncated: J.Json, parent: J.Json) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  match shape path entries truncated:
    case True{} J.Text{path} J.Array{entries} J.Boolean{truncated}: directory_catalog(path, parent, directory_entries(entries), truncated)
    case _ _ _ _: Fail{"Invalid folder listing"}

def directory_response_ok(ok: J.Json, +body: J.Json) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  match ok:
    case J.Boolean{False{}}: directory_response_failure(directory_shape(body, ["ok", "error"]), J.get(body, "error"))
    case J.Boolean{True{}}: directory_response_success(directory_shape(body, ["ok", "path", "parent", "entries", "truncated"]), J.get(body, "path"), J.get(body, "entries"), J.get(body, "truncated"), J.get(body, "parent"))
    case _: Fail{"Invalid folder listing"}

def directory_response(+body: J.Json) -> Result<&2, &2, String, Services.DirectoryCatalog>:
  directory_response_ok(J.get(body, "ok"), body)

def directory_listed(ticket: Nat, ok: Bool, +body: J.Json, state: State) -> Decision:
  match ok:
    case False{}: product_input(Product.DirectoryListed{ticket, Fail{J.text(J.get(body, "error"))}}, state)
    case True{}: product_input(Product.DirectoryListed{ticket, directory_response(body)}, state)

def directories_completed(ticket: Nat, ok: Bool, +body: J.Json, state: State) -> Decision:
  match ok:
    case False{}: product_input(Product.Directories{ticket, Fail{J.text(J.get(body, "error"))}}, state)
    case True{}:
      +workspace = Workspace.read_workspace(J.get(body, "workspace"), D.Workspace{Nil{}, None{}})
      guidance = Workspace.read_guidance(J.get(body, "guidance"), workspace, D.NoProject{})
      product_input(Product.Directories{ticket, Done{Context.DirectoryObservation{workspace, guidance}}}, state)

# Credentials and connection controls are found by their current authority,
# so DOM identifiers never become another source of settings semantics.

def snapshot_new(newer: Bool, sequence: Nat, world: M.World(), state: State) -> Decision:
  match newer:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{web, current, next, pending, receipt} = state
      product_input(Product.ProgramObserved{world}, State{web, sequence, next, pending, receipt})

def snapshot(+sequence: Nat, program: M.World(), +state: State) -> Decision:
  State{web, current, next, pending, receipt} = state
  snapshot_new(Nat.is_lt(current, sequence), sequence, program, state)

def settle_new(+ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{web, current, next, pending, receipt} = state
  product_input(Product.CommandCompleted{supplied, reply, completion}, State{web, received, next, remove(pending, ticket), receipt})

def settle_old(+ticket: Nat, reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{+web, +current, +next, +pending, +receipt} = state
  product_input(Product.CommandCompleted{program(State{web, current, next, pending, receipt}), reply, completion}, State{web, current, next, remove(pending, ticket), receipt})

def complete_new(newer: Bool, ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion, state: State) -> Decision:
  match newer:
    case True{}: settle_new(ticket, received, supplied, reply, completion, state)
    case False{}: settle_old(ticket, reply, completion, state)

def connect_entered(found: Maybe<&2, String>, entered: State, first: +List<Effect>) -> Decision:
  match found:
    case None{}: Decision{entered, first}
    case Some{key}:
      append_decision(first, activate(key, entered))

def entered_connect(decision: Decision) -> Decision:
  Decision{+entered, first} = decision
  connect_entered(connect_key(nodes(entered)), entered, first)

def editor_found(found: Maybe<&2, InterfaceView.Node>, event: Editor.EditorEvent, state: State) -> Decision:
  match found:
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.Edit{editor, Forms.MessageText{}, entry, value, choices}, children}}:
      native(Web.PlatformInput{Platform.EditorInput{editor, event}}, state)
    case _: Decision{state, Nil{}}

def editor_event(+key: String, event: Editor.EditorEvent, +state: State) -> Decision:
  editor_found(found_node(key, state), event, state)

def reading(task: Nat, generation: Nat, event: Reading.ReadingEvent, state: State) -> Decision:
  native(Web.PlatformInput{Platform.ReadingInput{task, generation, event}}, state)

def streams_fold(values: +List<J.Json>, decision: Decision) -> Decision:
  match values decision:
    case Nil{} Decision{state, effects}: Decision{state, effects}
    case Con{value, rest} Decision{state, effects}:
      streams_fold(rest, append_decision(effects, product_input(Product.LiveOutput{Live.PartialOutput{stream_output(value)}}, state)))

def streams(body: J.Json, state: State) -> Decision:
  streams_fold(J.items(J.get(body, "streams")), product_input(Product.LiveOutput{Live.ConnectionEnded{}}, state))

def complete_ticket(ticket: Nat, +received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{web, +current, next, pending, receipt} = state
  complete_new(Nat.is_lt(current, received), ticket, received, supplied, reply, completion, State{web, current, next, pending, receipt})

def receipt_decision(receipt: Maybe<&2, Receipt.Receipt>, decision: Decision) -> Decision:
  Decision{State{web, sequence, next, pending, previous}, effects} = decision
  Decision{State{web, sequence, next, pending, receipt}, effects}

def completion_receipt(completion: E.Completion, receipt: Maybe<&2, Receipt.Receipt>, decision: Decision) -> Decision:
  match completion:
    case E.DraftCompletion{draft}: decision
    case _: receipt_decision(receipt, decision)

def completed(found: Maybe<&2, Pending>, received: Nat, supplied: M.World(), +reply: J.Json, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{Pending{+ticket, +completion, text, +origin, status}}:
      completion_receipt(completion, Receipt.from_reply(ticket, origin, reply), complete_ticket(ticket, received, supplied, reply, completion, state))

def received_completion(+ticket: Nat, received: Nat, world: M.World(), reply: J.Json, state: State) -> Decision:
  State{web, sequence, next, +pending, receipt} = state
  completed(find(pending, ticket), received, world, reply, State{web, sequence, next, pending, receipt})

def ticket_of(pending: Pending) -> Nat:
  Pending{ticket, completion, command, origin, status} = pending
  ticket

def mark_uncertain(hit: Bool, entry: Pending, reason: String) -> Pending:
  match hit:
    case False{}: entry
    case True{}:
      Pending{ticket, completion, command, origin, status} = entry
      Pending{ticket, completion, command, origin, OutcomeUnknown{reason}}

def uncertain_pending(pending: +List<Pending>, +ticket: Nat, +reason: String) -> +List<Pending>:
  match pending:
    case Nil{}: Nil{}
    case Con{+entry, rest}:
      mark_uncertain(Nat.is_eq(ticket_of(entry), ticket), entry, reason) <> uncertain_pending(rest, ticket, reason)

def failed_completion(ticket: Nat, error: String, state: State) -> Decision:
  State{web, sequence, next, pending, receipt} = state
  Decision{State{web, sequence, next, uncertain_pending(pending, ticket, error), receipt}, Nil{}}

def rejected_pending(found: Maybe<&2, Pending>, +reason: String, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{Pending{+ticket, +completion, command, +origin, status}}:
      completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), settle_old(ticket, D.failure("command_not_submitted", reason), completion, state))

def command_rejected(+ticket: Nat, reason: String, state: State) -> Decision:
  State{web, sequence, next, +pending, receipt} = state
  rejected_pending(find(pending, ticket), reason, State{web, sequence, next, pending, receipt})

def step(event: Input, state: State) -> Decision:
  match event:
    case Native{input}: native(input, state)
    case Snapshot{received, world}: snapshot(received, world, state)
    case Completed{ticket, received, world, reply}: received_completion(ticket, received, world, reply, state)
    case Failed{ticket, error}: failed_completion(ticket, error, state)
    case Rejected{ticket, error}: command_rejected(ticket, error, state)

def owned_choice(same: Bool, rest: Bool) -> Bool:
  match same:
    case True{}: True{}
    case False{}: rest

def owns_ticket(pending: +List<Pending>, +ticket: Nat) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{entry, rest}: owned_choice(Nat.is_eq(ticket_of(entry), ticket), owns_ticket(rest, ticket))

def automatic_profile(valid: Bool, profile: String) -> Maybe<&2, InterfaceView.Gesture>:
  match valid:
    case False{}: None{}
    case True{}: Some{InterfaceView.Change{Forms.ContextChange{Context.SetApproval{Context.AutomaticReview{profile}}}}}

def automatic_gesture(prefixed: Bool, +profile: String) -> Maybe<&2, InterfaceView.Gesture>:
  match prefixed:
    case False{}: None{}
    case True{}: automatic_profile(D.nonempty(profile), profile)

def approval_gesture(text: String) -> Maybe<&2, InterfaceView.Gesture>:
  match text:
    case "ask": Some{InterfaceView.Change{Forms.ContextChange{Context.SetApproval{Context.Ask{}}}}}
    case "full-access": Some{InterfaceView.Change{Forms.ContextChange{Context.SetApproval{Context.Unrestricted{}}}}}
    case +other: automatic_gesture(String.starts_with(other, "automatic/"), String.drop(other, 10n))

def field_text(editor: U.Editor, field: Forms.Field, entry: Forms.Entry, value: Forms.Observed, text: String, state: State) -> Maybe<&2, InterfaceView.Gesture>:
  match field:
    case Forms.ContextOrigin{}: origin_gesture(String.split(text, Chr{47}))
    case Forms.WorkspacePrimary{}: Some{InterfaceView.Change{Forms.WorkspaceChange{Context.ChoosePrimary{text}}}}
    case Forms.SandboxMode{}: sandbox_gesture(value, text)
    case Forms.ApprovalPolicy{}: approval_gesture(text)
    case Forms.ModelProfile{}: model_gesture(value, text, False{})
    case Forms.ReasoningEffort{}: model_gesture(value, text, True{})
    case Forms.DeliveryIntent{}: delivery_gesture(text)
    case Forms.AssistanceProfile{}: assistance_gesture(value, text)
    case Forms.CardLabels{}: Some{InterfaceView.Change{Forms.Strings{String.split(text, Chr{10})}}}
    case Forms.ForkCount{}: fork_gesture(current_draft(state, editor), Nat.read(text), None{})
    case Forms.ForkMessages{}: fork_gesture(current_draft(state, editor), None{}, Some{String.split(text, Chr{10})})
    case Forms.CompactionSummary{}: Some{InterfaceView.Change{Forms.Summary{optional_text(text)}}}
    case Forms.CardStage{}: Some{InterfaceView.Change{Forms.Stage{Board.stage(text)}}}
    case Forms.CardPriority{}: Some{InterfaceView.Change{Forms.Priority{Board.priority(text)}}}
    case Forms.CardOwner{}: Some{InterfaceView.Change{Forms.Owner{Board.owner(text)}}}
    case Forms.CardProject{}: Some{InterfaceView.Change{Forms.Project{Nat.read(text)}}}
    case _: entry_text(entry, text)

def gesture_text(meaning: InterfaceView.Meaning, text: String, state: State) -> Maybe<&2, InterfaceView.Gesture>:
  match meaning:
    case InterfaceView.SearchChoices{query}: Some{InterfaceView.Search{text}}
    case InterfaceView.EnterCredential{entered}: Some{InterfaceView.Credential{text}}
    case InterfaceView.EnterDirectory{editor, current}: Some{InterfaceView.Directory{text}}
    case InterfaceView.DirectoryBrowserLocation{value}: Some{InterfaceView.Directory{text}}
    case InterfaceView.BoardProfile{automatic, selected, choices, enabled}: Some{InterfaceView.SelectBoardProfile{text}}
    case InterfaceView.BoardSearch{filter}: Some{InterfaceView.Filter{search_filter(filter, text)}}
    case InterfaceView.Edit{editor, field, entry, value, choices}: field_text(editor, field, entry, value, text, state)
    case _: None{}

def edit_gesture(found: Maybe<&2, InterfaceView.Node>, text: String, state: State) -> Maybe<&2, InterfaceView.Gesture>:
  match found:
    case None{}: None{}
    case Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}: gesture_text(meaning, text, state)

def edit_text(+key: String, text: String, +state: State) -> Decision:
  apply_gesture(edit_gesture(found_node(key, state), text, state), key, state)

def confirmation_key(keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool) -> Bool:
  String.eq(keyboard, "Enter") && Bool.not(composing) && Bool.not(control) && Bool.not(alt) && Bool.not(shift) && Bool.not(meta)

def confirm_source(found: Maybe<&2, InterfaceView.Node>) -> Maybe<&2, InterfaceView.Gesture>:
  match found:
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.DirectoryBrowserLocation{value}, children}}: Some{InterfaceView.ConfirmDirectory{}}
    case Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.EnterDirectory{editor, text}, children}}: Some{InterfaceView.ConfirmDirectory{}}
    case _: None{}

def confirm_gesture(found: Maybe<&2, InterfaceView.Node>, admitted: Bool) -> Maybe<&2, InterfaceView.Gesture>:
  match admitted:
    case True{}: confirm_source(found)
    case False{}: None{}

def confirm_text(+key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, +state: State) -> Decision:
  apply_gesture(confirm_gesture(found_node(key, state), confirmation_key(keyboard, composing, control, alt, shift, meta)), key, state)

def connect_credential(found: Maybe<&2, String>, credential: String, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{key}:
      entered_connect(edit_text(key, credential, state))

def connect(credential: String, +state: State) -> Decision:
  connect_credential(credential_key(nodes(state)), credential, state)

type DismissTarget is Data:
  DismissTarget{identity: String, input: Core.Input, outside: Bool, escape: Bool}
def first_dismiss_target(found: Maybe<&2, DismissTarget>, fallback: Maybe<&2, DismissTarget>) -> Maybe<&2, DismissTarget>:
  match found:
    case Some{target}: Some{target}
    case None{}: fallback

def dismiss_target(values: +List<InterfaceView.Node>) -> Maybe<&2, DismissTarget>:
  match values:
    case Nil{}: None{}
    case Con{InterfaceView.Node{key, semantic, label, role, InterfaceView.LayerRegion{input, outside, escape}, children}, rest}:
      Some{DismissTarget{UIIdentity.encode(key), input, outside, escape}}
    case Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}:
      first_dismiss_target(dismiss_target(children), dismiss_target(rest))

def dismiss_permitted(allowed: Bool, input: Core.Input, state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}: product_input(Product.InterfaceInput{input}, state)

def active_focus_scope(+state: State) -> Focus.Scope:
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +scope = Platform.scope(observed_platform_3)
  scope

def outside_layer_owned(+identity: String, key: Maybe<&2, String>) -> Bool:
  match key:
    case None{}: False{}
    case Some{current}: String.eq(identity, current)

# NOTE: A refused dismissal must discard the candidate and its effects so
# the browser can retain the original pointer action without committing work.

def outside_completed(closed: Bool, candidate: Decision, state: State) -> OutsideDecision:
  match closed:
    case True{}: OutsideDecision{True{}, candidate}
    case False{}: OutsideDecision{False{}, Decision{state, Nil{}}}

def semantic_layer_key(surface: InterfaceView.Surface) -> Maybe<&2, String>:
  InterfaceView.Surface{content, base, overlays, scope} = surface
  scope

def outside_closed(identity: String, candidate: Decision) -> Bool:
  Decision{next, effects} = candidate
  State{web, sequence, ticket, pending, receipt} = next
  Bool.not(outside_layer_owned(identity, semantic_layer_key(Web.observed_surface(web))))

def outside_transition(+identity: String, +candidate: Decision, state: State) -> OutsideDecision:
  outside_completed(outside_closed(identity, candidate), candidate, state)

def outside_scoped(scope: Focus.Scope, input: Core.Input, +state: State) -> OutsideDecision:
  match scope:
    case Focus.Document{}: OutsideDecision{False{}, Decision{state, Nil{}}}
    case Focus.Temporary{identity, initial, restore, occurrence}:
      outside_transition(identity, product_input(Product.InterfaceInput{input}, state), state)

def outside_permitted(allowed: Bool, input: Core.Input, +state: State) -> OutsideDecision:
  match allowed:
    case False{}: OutsideDecision{False{}, Decision{state, Nil{}}}
    case True{}: outside_scoped(active_focus_scope(state), input, state)

def outside_target(+identity: String, found: Maybe<&2, DismissTarget>, current_layer: Maybe<&2, String>, +state: State) -> OutsideDecision:
  match found:
    case None{}: OutsideDecision{False{}, Decision{state, Nil{}}}
    case Some{DismissTarget{key, input, outside, escape}}:
      outside_permitted((String.eq(identity, key) && outside) && outside_layer_owned(identity, current_layer), input, state)

def current_layer_key(+state: State) -> Maybe<&2, String>:
  State{web, sequence, next, pending, receipt} = state
  semantic_layer_key(Web.observed_surface(web))

def outside_event(+identity: String, +state: State) -> OutsideDecision:
  outside_target(identity, dismiss_target(nodes(state)), current_layer_key(state), state)

def escape_target(found: Maybe<&2, DismissTarget>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{DismissTarget{key, input, outside, escape}}: dismiss_permitted(escape, input, state)

def accepts_escape(found: Maybe<&2, DismissTarget>) -> Bool:
  match found:
    case None{}: False{}
    case Some{DismissTarget{key, input, outside, escape}}: escape

def cycle_target_found(found: Maybe<&2, Focus.Target>, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{target}:
      State{+observed_state_1, sequence, next, pending, receipt} = state
      +observed_application_2 = Web.application(observed_state_1)
      +observed_platform_3 = Platform.platform(observed_application_2)
      editors = Platform.editors(observed_platform_3)
      +ticket = Platform.focus_ticket(observed_platform_3)
      Decision{State{Web.with_application(Platform.with_platform(Platform.with_focus_ticket((ticket + 1n : Nat), observed_platform_3), observed_application_2), observed_state_1), sequence, next, pending, receipt},
        [BrowserEffect{Web.PlatformEffect{Platform.Focus{(ticket + 1n : Nat), target}}}]}

def cycle_found(found: Maybe<&2, String>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{identity}: cycle_target_found(Some{Focus.Product{identity}}, state)

def frame_cycle(realization: Rendered.State, scope: Focus.Scope, reverse: Bool) -> Maybe<&2, String>:
  match realization:
    case Rendered.Realized{generation, Rendered.Frame{viewport, elements, focused, order, +native_focus}}:
      Focus.cycle(scope, order, focused, reverse)
    case _: None{}

def temporary_action(scope: Focus.Scope, tab: Bool, escape: Bool, reverse: Bool, realization: Rendered.State, +state: State) -> Decision:
  match tab escape:
    case True{} _: cycle_found(frame_cycle(realization, scope, reverse), state)
    case False{} True{}: escape_target(dismiss_target(nodes(state)), state)
    case False{} False{}: Decision{state, Nil{}}

def key_scoped(scope: Focus.Scope, tab: Bool, escape: Bool, reverse: Bool, realization: Rendered.State, state: State) -> Decision:
  match scope:
    case Focus.Document{}: Decision{state, Nil{}}
    case Focus.Temporary{identity, initial, restore, occurrence}:
      temporary_action(Focus.Temporary{identity, initial, restore, occurrence}, tab, escape, reverse, realization, state)

def temporary_key(tab: Bool, escape: Bool, reverse: Bool, +state: State) -> Decision:
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +scope = Platform.scope(observed_platform_3)
  +realization = Web.realization(observed_state_1)
  key_scoped(scope, tab, escape, reverse, realization, state)

def key_handled(scope: Focus.Scope, +key: String, escape: Bool) -> Bool:
  match scope:
    case Focus.Document{}: False{}
    case Focus.Temporary{identity, initial, restore, occurrence}: String.eq(key, "Tab") || (String.eq(key, "Escape") && escape)

def ready_key_event(+key: String, shift: Bool, +state: State) -> KeyResult:
  State{+observed_state_1, sequence, next, pending, receipt} = state
  +observed_application_2 = Web.application(observed_state_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +scope = Platform.scope(observed_platform_3)
  KeyResult{key_handled(scope, key, accepts_escape(dismiss_target(nodes(state)))), temporary_key(String.eq(key, "Tab"), String.eq(key, "Escape"), shift, state)}

def key_result_decision(result: KeyResult) -> Decision:
  KeyResult{handled, decision} = result
  decision

def key_input(+key: String, shift: Bool, +state: State) -> Decision:
  key_result_decision(ready_key_event(key, shift, state))

def measurements(observation: F.Observation, state: State) -> Decision:
  native(Web.TypographyObserved{observation}, state)

def key_event(key: String, shift: Bool, +state: State) -> KeyResult:
  ready_key_event(key, shift, state)

def operation_receipt(state: State) -> Maybe<&2, Receipt.Receipt>:
  State{web, sequence, next, pending, receipt} = state
  receipt

def decision_receipt(decision: Decision) -> Maybe<&2, Receipt.Receipt>:
  Decision{state, effects} = decision
  operation_receipt(state)
