import Base
import ../MODEL.bend as M
import ../UI.bend as Product
import ../BOARD.bend as Board
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-experience.bend as E
import ../core/user-input.bend as U
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services
import ../core/user-context.bend as Context
import ../core/code-block.bend as Code
import ../core/live-output.bend as Live
import ./focus.bend as Focus
import ./editor.bend as Editor
import ./reading.bend as Reading
import ../WORKSPACE.bend as Workspace
import ../bendlib/json.bend as J
import ../bendlib/domain.bend as D
import ../bendlib/command-codec.bend as Codec
import ./MODEL.bend as Web
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./document.bend as Document
import ./renderer.bend as Renderer

type RequestStatus is Data:
  AwaitingReceipt{}
  OutcomeUnknown{reason: String}

type Pending is Data:
  Pending{ticket: Nat, completion: E.Completion, command: J.Json, origin: String, status: RequestStatus}
type State is Data:
  State{web: Web.State, sequence: Nat, next_ticket: Nat, pending: +List<Pending>}
type Input is Data:
  Native{input: Web.Input}
  Snapshot{sequence: Nat, program: M.World()}
  Completed{ticket: Nat, sequence: Nat, program: M.World(), reply: J.Json}
  Failed{ticket: Nat, error: String}
type Effect is Data:
  BrowserEffect{effect: Web.Effect}
  Command{ticket: Nat, command: J.Json}
  Service{effect: Services.Effect}
  Directories{ticket: Nat, workspace: D.Workspace}
  RenderingFailed{generation: Nat, violations: +List<Rendered.Violation>}
type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

type KeyResult is Data:
  KeyResult{handled: Bool, decision: Decision}

def initial(program: M.World(), sequence: Nat) -> State:
  State{Web.initial(program), sequence, 0n, Nil{}}
def program(state: State) -> M.World():
  State{Web.State{Platform.State{Core.State{E.Application{program, session}, services}, platform}, generation, realization, environment}, sequence, next, pending} = state
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

def mask_meaning(blocked: Bool, meaning: UI.Meaning) -> UI.Meaning:
  match blocked meaning:
    case True{} UI.Activate{input, availability}: UI.Activate{input, View.Unavailable{"Request pending"}}
    case _ other: other
def mask_nodes(nodes: +List<UI.Node>, +pending: +List<Pending>) -> +List<UI.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{UI.Node{+key, semantic, label, role, meaning, children}, rest}:
      UI.Node{key, semantic, label, role, mask_meaning(busy(pending, key), meaning), mask_nodes(children, pending)} <> mask_nodes(rest, pending)
def mask_surface(surface: UI.Surface, +pending: +List<Pending>) -> UI.Surface:
  UI.Surface{content, base, overlays, scope} = surface
  UI.Surface{content, mask_nodes(base, pending), mask_nodes(overlays, pending), scope}
def mark_attrs(blocked: Bool, attrs: +List<Document.Property>) -> +List<Document.Property>:
  match blocked:
    case False{}: attrs
    case True{}: Document.Property{"aria-busy", "true"} <> attrs
def mark_nodes(nodes: +List<Document.Node>, +pending: +List<Pending>) -> +List<Document.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Document.Element{+key, tag, attrs, styles, events, children}, rest}:
      Document.Element{key, tag, mark_attrs(busy(pending, key), attrs), styles, events, mark_nodes(children, pending)} <> mark_nodes(rest, pending)
    case Con{Document.Portal{key, target, children}, rest}:
      Document.Portal{key, target, mark_nodes(children, pending)} <> mark_nodes(rest, pending)
    case Con{Document.TargetProperties{+key, target, attrs, styles}, rest}:
      Document.TargetProperties{key, target, mark_attrs(busy(pending, key), attrs), styles} <> mark_nodes(rest, pending)
    case Con{Document.Text{value}, rest}:
      Document.Text{value} <> mark_nodes(rest, pending)
    case Con{Document.Markdown{key, source, value}, rest}:
      Document.Markdown{key, source, value} <> mark_nodes(rest, pending)
def mark_node(node: Document.Node, +pending: +List<Pending>) -> Document.Node:
  match node:
    case Document.Element{+key, tag, attrs, styles, events, children}:
      Document.Element{key, tag, mark_attrs(busy(pending, key), attrs), styles, events, mark_nodes(children, pending)}
    case Document.Portal{key, target, children}: Document.Portal{key, target, mark_nodes(children, pending)}
    case Document.TargetProperties{+key, target, attrs, styles}: Document.TargetProperties{key, target, mark_attrs(busy(pending, key), attrs), styles}
    case other: other
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
def rendering_faults(realization: Rendered.State) -> +List<Effect>:
  match realization:
    case Rendered.Unmet{generation, frame, violations}: [RenderingFailed{generation, violations}]
    case _: Nil{}
def empty() -> M.World():
  M.initial()
def code_key(source: Code.Source, ordinal: Nat) -> String:
  Code.key(Code.Identity{source, ordinal})
def prefer_key(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback
def credential_key(nodes: +List<UI.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{UI.Node{key, semantic, label, role, UI.EnterCredential{entered}, children}, rest}: Some{key}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}: prefer_key(credential_key(children), credential_key(rest))
def connect_key(nodes: +List<UI.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{UI.Node{key, semantic, label, role, UI.Activate{Core.ServiceInput{Services.Connect{}}, availability}, children}, rest}: Some{key}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}: prefer_key(connect_key(children), connect_key(rest))
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
      State{web, sequence, +next, pending} = state
      Decision{State{web, sequence, (next + 1n : Nat), List.append(&2, Pending, pending, [Pending{next, completion, command, origin, AwaitingReceipt{}}])}, [Command{next, command}]}
def count_gesture(value: Maybe<&2, Nat>) -> Maybe<&2, UI.Gesture>:
  match value:
    case None{}: None{}
    case Some{count}: Some{UI.Change{Forms.Count{count}}}
def entry_text(entry: Forms.Entry, text: String) -> Maybe<&2, UI.Gesture>:
  match entry:
    case Forms.PositiveInteger{}:
      count_gesture(Nat.read(text))
    case Forms.DisplayOnly{}: None{}
    case Forms.FileCollection{}: None{}
    case Forms.DirectoryCollection{}: Some{UI.Directory{text}}
    case _: Some{UI.Change{Forms.Text{text}}}
def mask_scene(scene: Web.Scene, pending: +List<Pending>) -> Web.Scene:
  Web.Scene{surface, platform, generation, realization, presentation} = scene
  Web.Scene{mask_surface(surface, pending), platform, generation, realization, presentation}
def scene(state: State) -> Web.Scene:
  State{web, sequence, next, +pending} = state
  mask_scene(Web.observe(web), pending)
# Unknown receipt status is local browser feedback; it never enters task history.
def unknown_notice(ticket: Nat, reason: String) -> Document.Node:
  Document.Element{"@browser/unknown/" ++ Nat.show(ticket), "p",
    [Document.Property{"role", "status"}],
    [Document.Property{"margin", "0"}, Document.Property{"padding", "8px 16px"}], Nil{},
    [Document.Text{"Connection interrupted. Submission status is unknown. " ++ reason}]}

def pending_notice(entry: Pending, rest: +List<Document.Node>) -> +List<Document.Node>:
  Pending{ticket, completion, command, origin, status} = entry
  match status:
    case AwaitingReceipt{}: rest
    case OutcomeUnknown{reason}: unknown_notice(ticket, reason) <> rest

def unknown_notices(pending: +List<Pending>) -> +List<Document.Node>:
  match pending:
    case Nil{}: Nil{}
    case Con{entry, rest}: pending_notice(entry, unknown_notices(rest))

def inset_document(root: Document.Node) -> Document.Node:
  match root:
    case Document.Element{key, tag, attrs, styles, events, children}:
      Document.Element{key, tag, attrs, List.append(&2, Document.Property, styles,
        [Document.Property{"top", "4rem"}, Document.Property{"height", "calc(100dvh - 4rem)"}, Document.Property{"min-height", "0"}]), events, children}
    case other: other

def with_notices(notices: +List<Document.Node>, root: Document.Node, title: String) -> Document.Document:
  match notices:
    case Nil{}: Document.Document{root, title}
    case Con{notice, rest}:
      Document.Document{Document.Element{"@browser/interaction", "div", Nil{},
        [Document.Property{"height", "100dvh"}, Document.Property{"overflow", "hidden"}], Nil{},
        [Document.Element{"@browser/unknown-status", "aside", Nil{},
          [Document.Property{"height", "4rem"}, Document.Property{"overflow", "auto"},
           Document.Property{"background", "var(--color-surface)"}, Document.Property{"color", "var(--color-text)"}], Nil{}, notice <> rest}, inset_document(root)]}, title}

def uncertainty_document(document: Document.Document, pending: +List<Pending>) -> Document.Document:
  Document.Document{root, title} = document
  with_notices(unknown_notices(pending), root, title)

def mark_document(document: Document.Document, +pending: +List<Pending>) -> Document.Document:
  Document.Document{root, title} = document
  uncertainty_document(Document.Document{mark_node(root, pending), title}, pending)
def render_document(+state: State) -> Document.Document:
  State{web, sequence, next, pending} = state
  mark_document(Renderer.render(scene(state)), pending)
def observe(+state: State) -> Document.Document:
  State{Web.State{application, generation, realization, environment}, sequence, next, pending} = state
  match realization:
    case Rendered.Unmet{received, frame, violations}:
      Document.Document{Document.Element{"@browser/failure", "section",
        [Document.Property{"role", "alert"}, Document.Property{"data-frame-observation", "off"}], Nil{}, Nil{},
        [Document.Element{"@browser/failure/message", "p", Nil{}, Nil{}, Nil{}, [Document.Text{"The interface could not complete its display. Retry to measure and render it again."}]},
          Document.Element{"@browser/retry", "button", [Document.Property{"type", "button"}], Nil{}, [Document.Activate{"@browser/retry"}], [Document.Text{"Retry"}]}]}, "Display failed"}
    case _: render_document(state)

def prepend_effect(effect: Effect, decision: Decision) -> Decision:
  Decision{state, effects} = decision
  Decision{state, effect <> effects}
def collected_finish(decision: Decision, web: +List<Web.Effect>, services: +List<Services.Effect>) -> Decision:
  Decision{state, requests} = decision
  Decision{state, List.append(&2, Effect, wrap_web(web), List.append(&2, Effect, requests, wrap_services(services)))}
def scene_nodes(scene: Web.Scene) -> +List<UI.Node>:
  Web.Scene{surface, platform, generation, realization, presentation} = scene
  UI.active_nodes(surface)
def nodes(state: State) -> +List<UI.Node>:
  scene_nodes(scene(state))
def found_node(+key: String, state: State) -> Maybe<&2, UI.Node>:
  UI.find_node(nodes(state), key)
def stream_parts(parts: +List<J.Json>) -> +List<Live.Part>:
  match parts:
    case Nil{}: Nil{}
    case Con{+part, rest}: Live.Part{J.natural_or(J.natural(J.get(part, "output_index")), 0n), J.text(J.get(part, "text"))} <> stream_parts(rest)
def stream_output(+value: J.Json) -> Live.Output:
  Live.Output{J.natural_or(J.natural(J.get(value, "task_id")), 0n), J.natural_or(J.natural(J.get(value, "ticket")), 0n), stream_parts(J.items(J.get(value, "parts")))}
def native_frame(received: Nat, frame: Rendered.Frame, web: Web.State, sequence: Nat, next: Nat, +pending: +List<Pending>) -> Decision:
  Web.State{+application, +generation, previous, +environment} = web
  +realization = Rendered.observe(generation, received, mask_surface(Web.frame_surface(environment, Web.surface(application)), pending), frame, previous)
  Decision{State{Web.State{application, generation, realization, environment}, sequence, next, pending}, rendering_faults(realization)}

def filter_text(filter: Board.Filter, text: String) -> Board.Filter:
  Board.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  Board.Filter{text, search, status, priority, date, assignee, creator, project, label}
def project_origin(value: Maybe<&2, Nat>) -> Maybe<&2, UI.Gesture>:
  match value:
    case Some{id}: Some{UI.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ProjectDefaults{id}}}}}
    case None{}: None{}
def parent_origin(value: Maybe<&2, Nat>) -> Maybe<&2, UI.Gesture>:
  match value:
    case Some{id}: Some{UI.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ParentTask{id}}}}}
    case None{}: None{}
def project_parent_origin(task: Maybe<&2, Nat>, project: Maybe<&2, Nat>) -> Maybe<&2, UI.Gesture>:
  match task project:
    case Some{task} Some{project}: Some{UI.Change{Forms.ContextChange{Context.ChooseOrigin{Context.ProjectForParent{task, project}}}}}
    case _ _: None{}
def origin_gesture(parts: +List<String>) -> Maybe<&2, UI.Gesture>:
  match parts:
    case Con{"environment", Nil{}}: Some{UI.Change{Forms.ContextChange{Context.ChooseOrigin{Context.EnvironmentDefaults{}}}}}
    case Con{"project", Con{id, Nil{}}}: project_origin(Nat.read(id))
    case Con{"parent", Con{id, Nil{}}}: parent_origin(Nat.read(id))
    case Con{"project-for-parent", Con{task, Con{project, Nil{}}}}: project_parent_origin(Nat.read(task), Nat.read(project))
    case _: None{}
def sandbox_value(value: Context.SandboxValue) -> D.Sandbox:
  match value:
    case Context.InheritedSandbox{sandbox}: sandbox
    case Context.ChosenSandbox{sandbox}: sandbox
def sandbox_mode(sandbox: D.Sandbox, text: String) -> Maybe<&2, UI.Gesture>:
  D.Sandbox{mode, network} = sandbox
  match text:
    case "workspace-write": Some{UI.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{D.WorkspaceWrite{}, network}}}}}
    case "read-only": Some{UI.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{D.ReadOnly{}, network}}}}}
    case _: None{}
def sandbox_gesture(value: Forms.Observed, text: String) -> Maybe<&2, UI.Gesture>:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: sandbox_mode(sandbox_value(sandbox), text)
    case _: None{}
def model_field(profile: String, reasoning: String, text: String, effort: Bool) -> Maybe<&2, UI.Gesture>:
  match effort:
    case False{}: Some{UI.Change{Forms.Model{text, reasoning}}}
    case True{}: Some{UI.Change{Forms.Model{profile, text}}}
def model_gesture(value: Forms.Observed, text: String, effort: Bool) -> Maybe<&2, UI.Gesture>:
  match value:
    case Forms.ModelValue{profile, reasoning}: model_field(profile, reasoning, text, effort)
    case _: None{}
def delivery_gesture(text: String) -> Maybe<&2, UI.Gesture>:
  match text:
    case "send": Some{UI.Change{Forms.Delivery{U.Send{}}}}
    case "steer": Some{UI.Change{Forms.Delivery{U.Steer{}}}}
    case _: None{}
def assistance_gesture(value: Forms.Observed, text: String) -> Maybe<&2, UI.Gesture>:
  match value:
    case Forms.AssistanceValue{enabled, profile}: Some{UI.Change{Forms.Assistance{enabled, text}}}
    case _: None{}
def optional_text(text: String) -> Maybe<&2, String>:
  match text:
    case "": None{}
    case text: Some{text}
def current_draft(state: State, editor: U.Editor) -> Maybe<&2, U.Draft>:
  State{Web.State{Platform.State{Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services}, platform}, generation, realization, environment}, sequence, ticket, requests} = state
  E.find_draft(drafts, editor)
def retained_messages(messages: Maybe<&2, +List<String>>, fallback: +List<String>) -> +List<String>:
  match messages:
    case None{}: fallback
    case Some{values}: values
def fork_gesture(draft: Maybe<&2, U.Draft>, count: Maybe<&2, Nat>, messages: Maybe<&2, +List<String>>) -> Maybe<&2, UI.Gesture>:
  match draft:
    case Some{U.Draft{revision, U.Fork{task, old_count, old_messages, config}, feedback}}:
      Some{UI.Change{Forms.Fork{J.natural_or(count, old_count), retained_messages(messages, old_messages)}}}
    case _: None{}
def network_gesture(sandbox: D.Sandbox, enabled: Bool) -> Maybe<&2, UI.Gesture>:
  D.Sandbox{mode, network} = sandbox
  Some{UI.Change{Forms.ContextChange{Context.SetSandbox{D.Sandbox{mode, enabled}}}}}

def toggle_gesture(found: Maybe<&2, UI.Node>, enabled: Bool) -> Maybe<&2, UI.Gesture>:
  match found:
    case Some{UI.Node{key, semantic, label, role, UI.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{previous, profile}}, children}}: Some{UI.Change{Forms.Assistance{enabled, profile}}}
    case Some{UI.Node{key, semantic, label, role, UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}}, children}}: network_gesture(sandbox_value(sandbox), enabled)
    case Some{UI.Node{key, semantic, label, role, UI.Edit{editor, field, entry, Forms.ToggleValue{previous}}, children}}: Some{UI.Change{Forms.Toggle{enabled}}}
    case _: None{}
def pending_of(state: State) -> +List<Pending>:
  State{web, sequence, next, pending} = state
  pending

def collect_one(effect: E.Effect, origin: String, +state: State) -> Decision:
  match effect:
    case E.RequestCommand{command, completion}:
      +wire = Codec.command_json(command)
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
def finish(decision: Web.Decision, sequence: Nat, next: Nat, pending: +List<Pending>, origin: String) -> Decision:
  Web.Decision{+web, Core.Decision{core, reply, runtime, interaction, services, durable}, effects} = decision
  collected_finish(collect(interaction, origin, State{web, sequence, next, pending}), effects, services)

def native_element(blocked: Bool, +key: String, gesture: UI.Gesture, state: State) -> Decision:
  match blocked:
    case True{}: Decision{state, Nil{}}
    case False{}:
      State{web, sequence, next, pending} = state
      finish(Web.step(Web.ElementInput{key, gesture}, web), sequence, next, pending, key)
def native_state(state: State, event: Web.Input) -> Decision:
  State{+web, sequence, next, +pending} = state
  match event:
    case Web.FrameObserved{received, frame}:
      native_frame(received, frame, web, sequence, next, pending)
    case Web.ElementInput{+key, gesture}:
      native_element(busy(pending, key), key, gesture, State{web, sequence, next, pending})
    case +other: finish(Web.step(other, web), sequence, next, pending, origin(other))
def native(event: Web.Input, +state: State) -> Decision:
  native_state(state, event)
def product_input(input: Product.Input, state: State) -> Decision:
  native(Web.PlatformInput{Platform.ProductInput{input}}, state)
def activate(key: String, state: State) -> Decision:
  match key:
    case "@browser/retry": native(Web.Mount{}, state)
    case other: native(Web.ElementInput{other, UI.Press{}}, state)
def apply_gesture(gesture: Maybe<&2, UI.Gesture>, key: String, state: State) -> Decision:
  match gesture:
    case None{}: Decision{state, Nil{}}
    case Some{gesture}: native(Web.ElementInput{key, gesture}, state)
def edit_toggle(+key: String, enabled: Bool, +state: State) -> Decision:
  apply_gesture(toggle_gesture(found_node(key, state), enabled), key, state)
def attach(key: String, file: Services.File, state: State) -> Decision:
  native(Web.ElementInput{key, UI.Attach{file}}, state)
def place(key: String, target: String, state: State) -> Decision:
  native(Web.ElementInput{key, UI.Place{target}}, state)


def code_source(source: Code.Source, ordinal: Nat, text: String, state: State) -> Decision:
  product_input(Product.CodeSource{Code.Identity{source, ordinal}, text}, state)
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
      State{web, current, next, pending} = state
      product_input(Product.ProgramObserved{world}, State{web, sequence, next, pending})
def snapshot(+sequence: Nat, program: M.World(), +state: State) -> Decision:
  State{web, current, next, pending} = state
  snapshot_new(Nat.is_lt(current, sequence), sequence, program, state)
def settle_new(+ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{web, current, next, pending} = state
  product_input(Product.CommandCompleted{supplied, reply, completion}, State{web, received, next, remove(pending, ticket)})
def settle_old(+ticket: Nat, reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{+web, +current, +next, +pending} = state
  product_input(Product.CommandCompleted{program(State{web, current, next, pending}), reply, completion}, State{web, current, next, remove(pending, ticket)})
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

def editor_found(found: Maybe<&2, UI.Node>, event: Editor.Event, state: State) -> Decision:
  match found:
    case Some{UI.Node{key, semantic, label, role, UI.Edit{editor, Forms.MessageText{}, entry, value}, children}}:
      native(Web.PlatformInput{Platform.EditorInput{editor, event}}, state)
    case _: Decision{state, Nil{}}
def editor_event(+key: String, event: Editor.Event, +state: State) -> Decision:
  editor_found(found_node(key, state), event, state)
def reading(task: Nat, generation: Nat, event: Reading.Event, state: State) -> Decision:
  native(Web.PlatformInput{Platform.ReadingInput{task, generation, event}}, state)
def streams_fold(values: +List<J.Json>, decision: Decision) -> Decision:
  match values decision:
    case Nil{} Decision{state, effects}: Decision{state, effects}
    case Con{value, rest} Decision{state, effects}:
      streams_fold(rest, append_decision(effects, product_input(Product.LiveOutput{Live.PartialOutput{stream_output(value)}}, state)))
def streams(body: J.Json, state: State) -> Decision:
  streams_fold(J.items(J.get(body, "streams")), product_input(Product.LiveOutput{Live.ConnectionEnded{}}, state))

def complete_ticket(ticket: Nat, +received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion, state: State) -> Decision:
  State{web, +current, next, pending} = state
  complete_new(Nat.is_lt(current, received), ticket, received, supplied, reply, completion, State{web, current, next, pending})

def completed(found: Maybe<&2, Pending>, received: Nat, supplied: M.World(), reply: J.Json, +state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{Pending{+ticket, completion, text, origin, status}}:
      complete_ticket(ticket, received, supplied, reply, completion, state)
def received_completion(+ticket: Nat, received: Nat, world: M.World(), reply: J.Json, state: State) -> Decision:
  State{web, sequence, next, +pending} = state
  completed(find(pending, ticket), received, world, reply, State{web, sequence, next, pending})
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
  State{web, sequence, next, pending} = state
  Decision{State{web, sequence, next, uncertain_pending(pending, ticket, error)}, Nil{}}

def step(event: Input, state: State) -> Decision:
  match event:
    case Native{input}: native(input, state)
    case Snapshot{received, world}: snapshot(received, world, state)
    case Completed{ticket, received, world, reply}: received_completion(ticket, received, world, reply, state)
    case Failed{ticket, error}: failed_completion(ticket, error, state)
def owned_choice(same: Bool, rest: Bool) -> Bool:
  match same:
    case True{}: True{}
    case False{}: rest

def owns_ticket(pending: +List<Pending>, +ticket: Nat) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{entry, rest}: owned_choice(Nat.is_eq(ticket_of(entry), ticket), owns_ticket(rest, ticket))
def automatic_profile(valid: Bool, profile: String) -> Maybe<&2, UI.Gesture>:
  match valid:
    case False{}: None{}
    case True{}: Some{UI.Change{Forms.ContextChange{Context.SetApproval{Context.AutomaticReview{profile}}}}}
def automatic_gesture(prefixed: Bool, +profile: String) -> Maybe<&2, UI.Gesture>:
  match prefixed:
    case False{}: None{}
    case True{}: automatic_profile(D.nonempty(profile), profile)
def approval_gesture(text: String) -> Maybe<&2, UI.Gesture>:
  match text:
    case "ask": Some{UI.Change{Forms.ContextChange{Context.SetApproval{Context.Ask{}}}}}
    case "full-access": Some{UI.Change{Forms.ContextChange{Context.SetApproval{Context.Unrestricted{}}}}}
    case +other: automatic_gesture(String.starts_with(other, "automatic/"), String.drop(other, 10n))
def field_text(editor: U.Editor, field: Forms.Field, entry: Forms.Entry, value: Forms.Observed, text: String, state: State) -> Maybe<&2, UI.Gesture>:
  match field:
    case Forms.ContextOrigin{}: origin_gesture(String.split(text, Chr{47}))
    case Forms.WorkspacePrimary{}: Some{UI.Change{Forms.WorkspaceChange{Context.ChoosePrimary{text}}}}
    case Forms.SandboxMode{}: sandbox_gesture(value, text)
    case Forms.ApprovalPolicy{}: approval_gesture(text)
    case Forms.ModelProfile{}: model_gesture(value, text, False{})
    case Forms.ReasoningEffort{}: model_gesture(value, text, True{})
    case Forms.DeliveryIntent{}: delivery_gesture(text)
    case Forms.AssistanceProfile{}: assistance_gesture(value, text)
    case Forms.CardLabels{}: Some{UI.Change{Forms.Strings{String.split(text, Chr{10})}}}
    case Forms.ForkCount{}: fork_gesture(current_draft(state, editor), Nat.read(text), None{})
    case Forms.ForkMessages{}: fork_gesture(current_draft(state, editor), None{}, Some{String.split(text, Chr{10})})
    case Forms.CompactionSummary{}: Some{UI.Change{Forms.Summary{optional_text(text)}}}
    case Forms.CardStage{}: Some{UI.Change{Forms.Stage{Board.stage(text)}}}
    case Forms.CardPriority{}: Some{UI.Change{Forms.Priority{Board.priority(text)}}}
    case Forms.CardOwner{}: Some{UI.Change{Forms.Owner{Board.owner(text)}}}
    case Forms.CardProject{}: Some{UI.Change{Forms.Project{Nat.read(text)}}}
    case _: entry_text(entry, text)
def gesture_text(meaning: UI.Meaning, text: String, state: State) -> Maybe<&2, UI.Gesture>:
  match meaning:
    case UI.SearchChoices{query}: Some{UI.Search{text}}
    case UI.EnterCredential{entered}: Some{UI.Credential{text}}
    case UI.EnterDirectory{editor}: Some{UI.Directory{text}}
    case UI.BoardProfile{automatic, selected, choices, enabled}: Some{UI.SelectBoardProfile{text}}
    case UI.BoardFilter{value}: Some{UI.Filter{filter_text(value, text)}}
    case UI.Edit{editor, field, entry, value}: field_text(editor, field, entry, value, text, state)
    case _: None{}
def edit_gesture(found: Maybe<&2, UI.Node>, text: String, state: State) -> Maybe<&2, UI.Gesture>:
  match found:
    case None{}: None{}
    case Some{UI.Node{key, semantic, label, role, meaning, children}}: gesture_text(meaning, text, state)
def edit_text(+key: String, text: String, +state: State) -> Decision:
  apply_gesture(edit_gesture(found_node(key, state), text, state), key, state)
def connect_credential(found: Maybe<&2, String>, credential: String, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{key}:
      entered_connect(edit_text(key, credential, state))
def connect(credential: String, +state: State) -> Decision:
  connect_credential(credential_key(nodes(state)), credential, state)


def dismiss_input(input: Core.Input) -> Bool:
  match input:
    case Core.ServiceInput{Services.ClosePreview{}}: True{}
    case Core.ServiceInput{Services.CloseSettings{}}: True{}
    case Core.ApplicationInput{E.UserInput{U.Activate{U.ClosePanel{}}}}: True{}
    case Core.ApplicationInput{E.UserInput{U.SetNavigation{False{}}}}: True{}
    case _: False{}

def dismiss_selected(eligible: Bool, key: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match eligible:
    case True{}: Some{key}
    case False{}: fallback

def dismiss_key(values: +List<UI.Node>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Con{UI.Node{+key, semantic, label, role, UI.Activate{input, availability}, +children}, rest}:
      dismiss_selected(UI.available(availability) && dismiss_input(input), key, prefer_key(dismiss_key(children), dismiss_key(rest)))
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      prefer_key(dismiss_key(children), dismiss_key(rest))

def dismiss_found(found: Maybe<&2, String>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{key}: activate(key, state)

def cycle_found(found: Maybe<&2, String>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{target}:
      State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, +ticket, reduced, capacity, scope}}, generation, realization, environment}, sequence, next, pending} = state
      Decision{State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, (ticket + 1n : Nat), reduced, capacity, scope}}, generation, realization, environment}, sequence, next, pending},
        [BrowserEffect{Web.PlatformEffect{Platform.Focus{(ticket + 1n : Nat), target}}}]}

def frame_cycle(realization: Rendered.State, scope: Focus.Scope, reverse: Bool) -> Maybe<&2, String>:
  match realization:
    case Rendered.Realized{generation, Rendered.Frame{viewport, elements, focused, order}}:
      Focus.cycle(scope, order, focused, reverse)
    case _: None{}

def temporary_action(scope: Focus.Scope, tab: Bool, escape: Bool, reverse: Bool, realization: Rendered.State, +state: State) -> Decision:
  match tab escape:
    case True{} _: cycle_found(frame_cycle(realization, scope, reverse), state)
    case False{} True{}: dismiss_found(dismiss_key(nodes(state)), state)
    case False{} False{}: Decision{state, Nil{}}

def key_scoped(scope: Focus.Scope, tab: Bool, escape: Bool, reverse: Bool, realization: Rendered.State, state: State) -> Decision:
  match scope:
    case Focus.Document{}: Decision{state, Nil{}}
    case Focus.Temporary{identity, initial, restore}:
      temporary_action(Focus.Temporary{identity, initial, restore}, tab, escape, reverse, realization, state)

def temporary_key(tab: Bool, escape: Bool, reverse: Bool, +state: State) -> Decision:
  State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment}, sequence, next, pending} = state
  key_scoped(scope, tab, escape, reverse, realization, state)

def key_input(+key: String, shift: Bool, state: State) -> Decision:
  temporary_key(String.eq(key, "Tab"), String.eq(key, "Escape"), shift, state)


def key_handled(scope: Focus.Scope, +key: String) -> Bool:
  match scope:
    case Focus.Document{}: False{}
    case Focus.Temporary{identity, initial, restore}: String.eq(key, "Tab") || String.eq(key, "Escape")

def key_event(+key: String, shift: Bool, +state: State) -> KeyResult:
  State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment}, sequence, next, pending} = state
  KeyResult{key_handled(scope, key), key_input(key, shift, state)}
