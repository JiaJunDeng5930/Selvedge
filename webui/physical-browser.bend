import ./physical-space.bend as Space
import ./rendered.bend as Rendered
import Base
import ./browser.bend as Legacy
import ./MODEL.bend as Web
import ./platform.bend as Platform
import ./document.bend as Doc
import ./physical-world.bend as World
import ./physical-plan.bend as Plan
import ./physical-content.bend as Content
import ./physical-renderer.bend as Renderer
import ./physical-probe.bend as Probe
import ./authored-shell.bend as Shell
import ./source.bend as Source
import ./spatial.bend as Spatial
import ./design.bend as Design
import ./font-observation.bend as F
import ./typography.bend as T
import ./paint.bend as Paint
import ./presentation-order.bend as Order
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../core/SYSTEM.bend as Core
import ./focus.bend as Focus
import ../MODEL.bend as M
import ./editor.bend as Editor
import ./reading.bend as Reading
import ../core/client-services.bend as Services
import ../core/code-block.bend as Code
import ../bendlib/json.bend as J

type Lifecycle is Data:
  WaitingEnvironment{}
  WaitingFont{}
  Measuring{candidate_index: Nat, capacity: View.Capacity, engine: World.Engine}
  Displaying{capacity: View.Capacity, engine: World.Engine}
  Blocked{problem: String}



type State is Data:
  State{legacy: Legacy.State, generation: Nat, anchors: +List<Shell.Anchor>, lifecycle: Lifecycle,
    displayed: Maybe<&2, Content.AllocatedWorld>}


type Publication is Data:
  KeepPublished{}
  Publish{generation: Nat, document: Doc.Document}


type Decision is Data:
  Decision{state: State, effects: +List<Legacy.Effect>}


type KeyResult is Data:
  KeyResult{handled: Bool, decision: Decision}


type Search is Data:
  Searching{index: Nat, state: State}
  Stopped{decision: Decision}


type OutsideDecision is Data:
  OutsideDecision{handled: Bool, decision: Decision}



def initial(+program: M.World(), +sequence: Nat) -> State:
  State{Legacy.initial(program, sequence), 0n, Nil{}, WaitingEnvironment{}, None{}}
def legacy(+state: State) -> Legacy.State:
  State{value, generation, anchors, lifecycle, displayed} = state
  value
def candidate(+index: Nat) -> View.Capacity:
  match index:
    case 0n: View.Capacity{True{}, True{}}
    case 1n: View.Capacity{True{}, False{}}
    case 2n: View.Capacity{False{}, True{}}
    case _: View.Capacity{False{}, False{}}
def admitted(+decision: Legacy.Decision, +world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +serial: Nat, +anchors: +List<Shell.Anchor>) -> Decision:
  Legacy.Decision{accepted, collected} = decision
  Decision{State{accepted, serial, anchors, Displaying{capacity, engine}, Some{world}}, collected}
def admit(+world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +state: State) -> Decision:
  State{Legacy.State{Web.State{Platform.State{+core, platform}, generation, realization, environment, font}, sequence, ticket, pending}, serial, anchors, lifecycle, displayed} = state
  +decision = Platform.reflow_capacity(Platform.Decision{Platform.unchanged(core), platform, Nil{}}, capacity)
  admitted(Legacy.finish(Web.production_commit(decision, generation, environment, font), sequence, ticket, pending, ""), world, capacity, engine, serial, anchors)
def display_ready(+state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Displaying{capacity, engine}: True{}
    case _: False{}
def displayed_generation(+state: State) -> Nat:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: 0n
    case Some{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}}: generation
def render_status(+state: State) -> String:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Displaying{capacity, engine}: "ready"
    case Blocked{reason}: "blocked"
    case _: "waiting"
def physical_plan(+state: State) -> Maybe<&2, Plan.Plan>:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Measuring{index, capacity, engine}: Some{World.plan(engine)}
    case _: None{}
def requested_generation(+state: State) -> Nat:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Measuring{index, capacity, engine}: World.snapshot_generation(World.snapshot(engine))
    case Displaying{capacity, engine}: World.snapshot_generation(World.snapshot(engine))
    case _: 0n
def status_document(message: String, font: T.Presentation) -> Doc.Document:
  Doc.Document{Doc.Element{"@browser/status", "section",
    [Doc.Property{"role", "status"}, Doc.Property{"data-frame-observation", "off"}],
    Paint.text_presentation(font), Nil{}, [Doc.Text{message}]}, "Selvedge"}
def observed_lifecycle(+lifecycle: Lifecycle, +displayed: Maybe<&2, Content.AllocatedWorld>, +font: T.Presentation) -> Doc.Document:
  match lifecycle displayed:
    case Displaying{capacity, engine} Some{world}: Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, Renderer.nodes(world)}, "Selvedge"}
    case Blocked{problem} _: status_document(problem, font)
    case _ _: status_document("Preparing interface…", font)
def observed(+displayed: Maybe<&2, Content.AllocatedWorld>, +lifecycle: Lifecycle, +font: T.Presentation) -> Doc.Document:
  observed_lifecycle(lifecycle, displayed, font)
def observe(+state: State) -> Doc.Document:
  State{+legacy, serial, anchors, lifecycle, displayed} = state
  Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending} = legacy
  observed(displayed, lifecycle, T.Presentation{T.Body{}, T.Regular{}, F.scale(font)})
def published_document(ready: Bool, +state: State) -> Publication:
  match ready:
    case True{}: Publish{displayed_generation(state), observe(state)}
    case False{}: Publish{0n, observe(state)}
def publication_for(existing: Bool, +ready: Bool, current: Bool, state: State) -> Publication:
  match existing ready current:
    case True{} False{} _: KeepPublished{}
    case True{} True{} True{}: KeepPublished{}
    case _ _ _: published_document(ready, state)
def publication(+last_published: Nat, +state: State) -> Publication:
  publication_for(Bool.not(Nat.is_eq(last_published, 0n)), display_ready(state),
    Nat.is_eq(displayed_generation(state), last_published), state)
def probe_document(+job: Plan.Job) -> Doc.Document: Probe.document(job)
def probe_target_keys(+request: Content.Request) -> +List<String>: Probe.target_keys(request)
def decision_state(value: Decision) -> State:
  Decision{state, effects} = value
  state
def capture_anchor(key: String, left: Nat, top: Nat, width: Nat, height: Nat, state: State) -> Decision:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  Decision{State{legacy, serial, Shell.Anchor{key, Spatial.Box{left, top, width, height}} <> anchors, lifecycle, displayed}, Nil{}}
def legacy_focus_ticket(state: Legacy.State) -> Nat:
  Legacy.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, focus_ticket, reduced, capacity, scope}}, generation, realization, environment, font}, sequence, ticket, pending} = state
  focus_ticket
def focus_ticket(+state: State) -> Nat:
  legacy_focus_ticket(legacy(state))
def active_scope(+state: State) -> Focus.Scope:
  Legacy.active_focus_scope(legacy(state))
def empty() -> M.World(): Legacy.empty()
def program(+state: State) -> M.World(): Legacy.program(legacy(state))
def code_key(+source: Code.Source, +ordinal: Nat) -> String: Legacy.code_key(source, ordinal)
def font_budget(+font: F.State) -> Nat:
  match font:
    case F.Pending{generation, scale}: 1n
    case _: 0n
def source_changed(+input: Web.Input) -> Bool:
  match input:
    case Web.FrameObserved{generation, frame}: False{}
    case Web.PlatformInput{Platform.FocusObserved{identity}}: False{}
    case Web.PlatformInput{Platform.FocusApplied{ticket, identity}}: False{}
    case Web.PlatformInput{Platform.ReadingInput{task, generation, event}}: False{}
    case Web.PlatformInput{Platform.MotionPreference{reduced}}: False{}
    case _: True{}
def legacy_outside(+identity: String, +stored: Legacy.State) -> Legacy.OutsideDecision:
  Legacy.outside_event(identity, stored)
def append(+first: +List<Legacy.Effect>, +value: Decision) -> Decision:
  Decision{next, later} = value
  Decision{next, List.append(&2, Legacy.Effect, first, later)}
def current_font(+state: Legacy.State) -> F.State:
  Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending} = state
  font
def measurement_plan(+state: State) -> F.Plan:
  F.request(current_font(legacy(state)), Nil{})
def measurement_budget(+state: State) -> Nat:
  font_budget(current_font(legacy(state)))
def semantic_generation(+state: Legacy.State) -> Nat:
  Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending} = state
  generation
def set_lifecycle(+state: State, lifecycle: Lifecycle) -> State:
  State{legacy, serial, anchors, old, displayed} = state
  State{legacy, serial, anchors, lifecycle, displayed}
def no_candidate(state: State) -> Decision:
  Decision{set_lifecycle(state, Blocked{"The interface does not fit the available space"}), Nil{}}
def retry_candidate(+more: Bool, +index: Nat, +state: State) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{no_candidate(state)}
def selected(+outcome: Plan.Plan, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State) -> Search:
  match outcome:
    case Plan.Ready{world}: Stopped{admit(world, capacity, engine, state)}
    case Plan.Awaiting{generation, first, remaining}: Stopped{Decision{set_lifecycle(state, Measuring{index, capacity, engine}), Nil{}}}
    case Plan.Invalid{error}: Stopped{Decision{set_lifecycle(state, Blocked{"Physical source or receipt is invalid"}), Nil{}}}
    case Plan.Infeasible{failure}: retry_candidate(Nat.is_lt(index, 3n), index, state)
def surface_layers(surface: UI.Surface) -> +List<View.Layer>:
  UI.Surface{Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker}, base, overlays, scope} = surface
  layers
def viewport_box(environment: Design.Environment) -> Spatial.Box:
  Design.Environment{Design.Viewport{width, height}, dark, root} = environment
  Spatial.Box{0n, 0n, width, height}

# Browser feedback participates in the same authored tree and measurements.
def notice(+ticket: Nat, reason: String, +font: T.Presentation) -> Source.Node:
  Source.Box{"@browser/unknown/" ++ Nat.show(ticket), Source.Paragraph{},
    Shell.neutral(T.with_tier(font, T.Support{}), Space.Vertical{}, Space.StretchSize{}, Space.NaturalSize{}, Spatial.Stretch{}),
    [Source.RoleAttribute{"status"}],
    [Source.Text{"@browser/unknown/" ++ Nat.show(ticket) ++ "/text", "Connection interrupted. Submission status is unknown. " ++ reason,
      Source.ExplicitFont{T.with_tier(font, T.Support{})}, T.WrapWords{}}]}
def notices(entries: +List<Legacy.Pending>, +font: T.Presentation) -> +List<Source.Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{Legacy.Pending{ticket, completion, command, origin, Legacy.OutcomeUnknown{reason}}, rest}: notice(ticket, reason, font) <> notices(rest, font)
    case Con{entry, rest}: notices(rest, font)
def busy_attrs(busy: Bool, attrs: +List<Source.Attribute>) -> +List<Source.Attribute>:
  match busy:
    case True{}: Source.AriaAttribute{"busy", "true"} <> attrs
    case False{}: attrs
def main_children(tag: Source.BoxTag, children: +List<Source.Node>, pending: +List<Legacy.Pending>, font: T.Presentation) -> +List<Source.Node>:
  match tag:
    case Source.Main{}: List.append(&2, Source.Node, children, notices(pending, font))
    case _: children
def feedback_nodes(nodes: +List<Source.Node>, +pending: +List<Legacy.Pending>, +font: T.Presentation) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Box{+key, +tag, style, attrs, children}, rest}:
      Source.Box{key, tag, style, busy_attrs(Legacy.busy(pending, key), attrs), main_children(tag, feedback_nodes(children, pending, font), pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Control{+key, tag, style, attrs, name, enabled, first, remaining, children}, rest}:
      Source.Control{key, tag, style, busy_attrs(Legacy.busy(pending, key), attrs), name, enabled, first, remaining, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.NativeAttachment{+key, target, attrs, style, children}, rest}:
      Source.NativeAttachment{key, target, busy_attrs(Legacy.busy(pending, key), attrs), style, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Field{+key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}, rest}:
      Source.Field{key, kind, style, busy_attrs(Legacy.busy(pending, key), attrs), value, placeholder, options, policy, name, enabled, first, remaining} <> feedback_nodes(rest, pending, font)
    case Con{Source.RichText{key, style, content, attachments}, rest}:
      Source.RichText{key, style, content, feedback_nodes(attachments, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Text{key, value, choice, wrapping}, rest}:
      Source.Text{key, value, choice, wrapping} <> feedback_nodes(rest, pending, font)
    case Con{Source.Glyph{key, drawing, style}, rest}:
      Source.Glyph{key, drawing, style} <> feedback_nodes(rest, pending, font)
def only_root(nodes: +List<Source.Node>, fallback: Source.Node) -> Source.Node:
  match nodes:
    case Nil{}: fallback
    case Con{node, rest}: node
def pending(state: Legacy.State) -> +List<Legacy.Pending>:
  Legacy.State{web, sequence, ticket, entries} = state
  entries
def feedback_root(+source: Source.Node, +entries: +List<Legacy.Pending>, +font: T.Presentation) -> Source.Node:
  only_root(feedback_nodes(source <> Nil{}, entries, font), source)
def frozen(+source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: Spatial.Box, +state: State) -> Search:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), feedback_root(source, pending(legacy), font), font}, viewport)
  selected(World.plan(engine), index, capacity, engine, State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed})
def authored(+result: Shell.Result, +index: Nat, +capacity: View.Capacity, +font: T.Presentation,
  +viewport: Spatial.Box, +state: State) -> Search:
  match result:
    case Shell.Rejected{key, problem}: Stopped{Decision{set_lifecycle(state, Blocked{"Unsupported authored content: " ++ key}), Nil{}}}
    case Shell.Ready{source}: frozen(source, index, capacity, font, viewport, state)
def calibrated_body(+metric: T.Metric, +index: Nat, +state: State) -> Search:
  State{Legacy.State{Web.State{Platform.State{+core, platform}, generation, realization, +environment, +font}, sequence, ticket, +pending}, serial, +anchors, lifecycle, displayed} = state
  +stored: Legacy.State = Legacy.State{Web.State{Platform.State{core, platform}, generation, realization, environment, font}, sequence, ticket, pending}
  +capacity = candidate(index)
  +semantic = Order.ordered_surface(Legacy.mask_surface(UI.observe(capacity, core), pending))
  +layers = surface_layers(semantic)
  +surface = Web.appearance_surface(semantic, environment, font)
  +presentation: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, F.scale(font)}
  authored(Shell.source(surface, Design.parameters(F.scale(font), metric), capacity, layers, anchors, presentation),
    index, capacity, presentation, viewport_box(environment), State{stored, serial, anchors, lifecycle, displayed})
def calibrated(+body: Maybe<&2, T.Metric>, +index: Nat, +state: State) -> Search:
  match body:
    case None{}: Stopped{Decision{set_lifecycle(state, WaitingFont{}), Nil{}}}
    case Some{metric}: calibrated_body(metric, index, state)
def one_candidate(+index: Nat, +state: State) -> Search:
  calibrated(F.body(current_font(legacy(state))), index, state)
def search_step(search: Search) -> Search:
  match search:
    case Stopped{decision}: Stopped{decision}
    case Searching{index, state}: one_candidate(index, state)
# A bounded data machine visits one frozen candidate at a time.
def search_run(remaining: Nat, search: Search) -> Search:
  match remaining:
    case 0n: search
    case 1n+predecessor: search_run(predecessor, search_step(search))
def finish_search(search: Search) -> Decision:
  match search:
    case Stopped{decision}: decision
    case Searching{index, state}: no_candidate(state)
def build(index: Nat, state: State) -> Decision:
  finish_search(search_run(4n, Searching{index, state}))
def accepted(+rebuild: Bool, +first: +List<Legacy.Effect>, +state: State) -> Decision:
  match rebuild:
    case False{}: Decision{state, first}
    case True{}:
      append(first, build(0n, state))
def accept(+rebuild: Bool, +value: Legacy.Decision, +state: State) -> Decision:
  Legacy.Decision{next, first} = value
  State{old, serial, anchors, lifecycle, displayed} = state
  accepted(rebuild, first, State{next, serial, anchors, lifecycle, displayed})
def command_rejected(+ticket: Nat, +reason: String, +state: State) -> Decision: accept(True{}, Legacy.command_rejected(ticket, reason, legacy(state)), state)
def activate(+key: String, +state: State) -> Decision: accept(True{}, Legacy.activate(key, legacy(state)), state)
def edit_text(+key: String, +text: String, +state: State) -> Decision: accept(True{}, Legacy.edit_text(key, text, legacy(state)), state)
def confirm_text(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: State) -> Decision: accept(True{}, Legacy.confirm_text(key, keyboard, composing, control, alt, shift, meta, legacy(state)), state)
def edit_toggle(+key: String, +enabled: Bool, +state: State) -> Decision: accept(True{}, Legacy.edit_toggle(key, enabled, legacy(state)), state)
def attach(+key: String, +file: Services.File, +state: State) -> Decision: accept(True{}, Legacy.attach(key, file, legacy(state)), state)
def place(+key: String, +target: String, +state: State) -> Decision: accept(True{}, Legacy.place(key, target, legacy(state)), state)
def connect(+credential: String, +state: State) -> Decision: accept(True{}, Legacy.connect(credential, legacy(state)), state)
def directories_completed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directories_completed(ticket, ok, body, legacy(state)), state)
def code_source(+source: Code.Source, +ordinal: Nat, +text: String, +state: State) -> Decision: accept(True{}, Legacy.code_source(source, ordinal, text, legacy(state)), state)
def editor_event(+key: String, +event: Editor.Event, +state: State) -> Decision: accept(True{}, Legacy.editor_event(key, event, legacy(state)), state)
def reading(+task: Nat, +generation: Nat, +event: Reading.Event, +state: State) -> Decision: accept(False{}, Legacy.reading(task, generation, event, legacy(state)), state)
def streams(+body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.streams(body, legacy(state)), state)
def directory_listed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directory_listed(ticket, ok, body, legacy(state)), state)
def measurements(+observation: F.Observation, +state: State) -> Decision:
  accept(True{}, Legacy.measurements(observation, legacy(state)), state)
def received_frame(+owned: Bool, +frame: Rendered.Frame, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      accept(False{}, Legacy.native(Web.FrameObserved{semantic_generation(legacy(state)), frame}, legacy(state)), state)
def step(+input: Legacy.Input, +state: State) -> Decision:
  match input:
    case Legacy.Native{Web.FrameObserved{generation, frame}}:
      received_frame(display_ready(state) && Nat.is_eq(generation, displayed_generation(state)), frame, state)
    case Legacy.Native{+input}: accept(source_changed(input), Legacy.native(input, legacy(state)), state)
    case other: accept(True{}, Legacy.step(other, legacy(state)), state)
def outside_result(+result: Legacy.OutsideDecision, +state: State) -> OutsideDecision:
  Legacy.OutsideDecision{handled, decision} = result
  OutsideDecision{handled, accept(handled, decision, state)}
def outside_event(+identity: String, +state: State) -> OutsideDecision:
  outside_result(legacy_outside(identity, legacy(state)), state)
def key_result(+key: String, +result: Legacy.KeyResult, +state: State) -> KeyResult:
  Legacy.KeyResult{handled, decision} = result
  KeyResult{handled, accept(handled && String.eq(key, "Escape"), decision, state)}
def key_ready(+ready: Bool, +key: String, +shift: Bool, +state: State) -> KeyResult:
  match ready:
    case False{}: KeyResult{False{}, Decision{state, Nil{}}}
    case True{}:
      key_result(key, Legacy.ready_key_event(key, shift, legacy(state)), state)
def key_event(+key: String, +shift: Bool, +state: State) -> KeyResult:
  key_ready(display_ready(state), key, shift, state)
def receipt_selection(status: World.ReceiptStatus, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State) -> Decision:
  match status:
    case World.Rejected{reason}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
    case _: finish_search(search_run(4n, selected(World.plan(engine), index, capacity, engine, state)))
def measured_pending(+receipts: +List<String>, +state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, +engine}, displayed}:
      +next = World.receive(World.snapshot_generation(World.snapshot(engine)), receipts, engine)
      receipt_selection(World.receipt_status(next), index, capacity, next, State{legacy, serial, anchors, Measuring{index, capacity, engine}, displayed})
    case other: Decision{other, Nil{}}
def measured_current(+owned: Bool, +receipts: +List<String>, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: measured_pending(receipts, state)
def measurement_owned(+generation: Nat, state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Measuring{index, capacity, engine}: Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine)))
    case _: False{}
def measurement_failed(+owned: Bool, +reason: String, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
def physical_measurement_failed(+generation: Nat, +reason: String, +state: State) -> Decision:
  measurement_failed(measurement_owned(generation, state), reason, state)
def physical_measured(+generation: Nat, +receipts: +List<String>, +state: State) -> Decision:
  measured_current(measurement_owned(generation, state), receipts, state)
def capacity_index(capacity: View.Capacity) -> Nat:
  match capacity:
    case View.Capacity{True{}, True{}}: 0n
    case View.Capacity{True{}, False{}}: 1n
    case View.Capacity{False{}, True{}}: 2n
    case _: 3n
def refrozen_source(source: Source.Node, font: T.Presentation, viewport: Spatial.Box, +index: Nat, +capacity: View.Capacity, +state: State) -> Decision:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), source, font}, viewport)
  finish_search(search_run(4n, selected(World.plan(engine), index, capacity, engine,
    State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed})))
def refrozen(snapshot: Content.Snapshot, viewport: Spatial.Box, +index: Nat, +capacity: View.Capacity, +state: State) -> Decision:
  Content.Snapshot{old, source, font} = snapshot
  refrozen_source(source, font, viewport, index, capacity, state)
def refreeze(+index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State) -> Decision:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  refrozen(World.snapshot(engine), World.viewport(engine), index, capacity, State{legacy, serial, anchors, lifecycle, displayed})
def remeasure(+state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, engine}, displayed}: refreeze(index, capacity, engine, State{legacy, serial, anchors, Measuring{index, capacity, engine}, displayed})
    case State{legacy, serial, anchors, Displaying{capacity, engine}, displayed}: refreeze(capacity_index(capacity), capacity, engine, State{legacy, serial, anchors, Displaying{capacity, engine}, displayed})
    case other: Decision{other, Nil{}}
def key_decision(result: KeyResult) -> Decision:
  KeyResult{handled, decision} = result
  decision
def key_input(+key: String, +shift: Bool, +state: State) -> Decision: key_decision(key_event(key, shift, state))
