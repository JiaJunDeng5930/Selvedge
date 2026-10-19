import ../controls/NAVIGATION.bend as Navigation
import Base
import ../../bendlib/string-equality.bend as SafeText
import ../layout/ADAPTATION.bend as Adaptation
import ../controls/PROGRAM.bend as Controls
import ../controls/MODEL.bend as Authored
import ../../bendlib/categories.bend as Categories
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as AnchorGeometry
import ./native-fields.bend as NativeFields
import ../layout/physical-space.bend as Space
import ../document/RENDERED.bend as Rendered
import ../document/MODEL.bend as CodeObservation
import ./frontend-utility.bend as Utility
import ./utility-proof.bend as UtilityProof
import ../document/FRAME.bend as SourceFrame
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ./PLATFORM.bend as Platform
import ../layout/MODEL.bend as World
import ../layout/physical-plan.bend as Plan
import ../layout/CONTENT.bend as Content
import ../layout/RENDERER.bend as Renderer
import ../layout/physical-probe.bend as Probe
import ../controls/SHELL.bend as Shell
import ../document/SOURCE.bend as Source
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/natural-size.bend as NaturalSize
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../focus/MODEL.bend as Focus
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/COMMANDS.bend as Commands
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../interaction/INPUT.bend as UserInput
import ../editor/MODEL.bend as Editor
import ../reading/MODEL.bend as Reading
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/conversation/OUTPUT.bend as Live
import ../../interaction/session/MODEL.bend as E
import ../../interaction/MODEL.bend as Product
import ../../bendlib/json.bend as J
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/interactive_markdown/TYPES.bend as IM
import ../../interaction/interactive_markdown/SYNTAX.bend as IMSyntax
import ../../interaction/STATE.bend as InteractionState

type MeasurementTicket is Data:
  MeasurementTicket{generation: Nat, round: Nat}

type MeasurementRequest is Data:
  MeasurementRequest{ticket: MeasurementTicket, plan: Plan.Plan}

type Lifecycle is Data:
  WaitingEnvironment{}
  WaitingFont{}
  Measuring{candidate_index: Nat, capacity: View.Capacity, engine: World.Engine, semantic: SurfaceTypes.Surface, round: Nat}
  Displaying{capacity: View.Capacity, engine: World.Engine, semantic: SurfaceTypes.Surface}
  UtilityMeasuring{purpose: Utility.Purpose, engine: World.Engine, round: Nat, glyph_only: Bool}
  UtilityDisplaying{purpose: Utility.Purpose, engine: World.Engine}
  UtilityRejected{problem: String}
  Blocked{problem: String}

type Published is Data:
  Published{world: Content.AllocatedWorld, semantic: SurfaceTypes.Surface, scope: Focus.Scope,
    basis: NativeFields.Basis, frame: Maybe<&2, Rendered.Frame>}

type DisplayUpdates is Data:
  DisplayUpdates{latest: Nat, active: Nat, published: Nat, semantic_latest: Nat}

type State is Data:
  State{legacy: Legacy.State, generation: Nat, anchors: +List<Shell.Anchor>, lifecycle: Lifecycle,
    displayed: Maybe<&2, Published>, attention: Navigation.Attention, updates: DisplayUpdates}

def display_pending(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, active, published, semantic_latest}} = state
  Bool.not(Nat.is_eq(latest, published))

def semantic_pending(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, active, published, semantic_latest}} = state
  Nat.is_lt(published, semantic_latest)

def advance_update(state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{+latest, active, published, semantic_latest}} = state
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{(latest + 1n : Nat), active, published, (latest + 1n : Nat)}}

def advance_presentation(state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, active, published, semantic_latest}} = state
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{(latest + 1n : Nat), active, published, semantic_latest}}

def freeze_update(state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{+latest, active, published, semantic_latest}} = state
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, latest, published, semantic_latest}}

def publish_update(state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, +active, published, semantic_latest}} = state
  State{legacy, serial, anchors, lifecycle, displayed, attention, DisplayUpdates{latest, active, active, semantic_latest}}

def active_measurement(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Measuring{index, capacity, engine, semantic, round}: True{}
    case _: False{}

def generation(state: State) -> Nat:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  value_generation

def anchors(state: State) -> +List<Shell.Anchor>:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  value_anchors

def lifecycle(state: State) -> Lifecycle:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  value_lifecycle

def displayed(state: State) -> Maybe<&2, Published>:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  value_displayed

def with_lifecycle(value: Lifecycle, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  State{value_legacy, value_generation, value_anchors, value, value_displayed, attention, updates}

def with_displayed(value: Maybe<&2, Published>, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value, attention, updates}

type RenderInspection is Data:
  RenderInspection{frame: Maybe<&2, Rendered.Frame>, expected_tabs: Maybe<&2, +List<String>>,
    native_valid: Maybe<&2, Bool>, current_layer: Maybe<&2, String>, dismiss_target: Maybe<&2, Legacy.DismissTarget>}

type Publication is Data:
  KeepPublished{fields: +List<NativeFields.Update>}
  Publish{generation: Nat, document: CodeObservation.Document, fields: +List<NativeFields.Update>}

type Decision is Data:
  Decision{state: State, effects: +List<Legacy.Effect>}

type KeyResult is Data:
  KeyResult{handled: Bool, decision: Decision}

type Search is Data:
  Searching{index: Nat, state: State}
  Stopped{decision: Decision}

type OutsideDecision is Data:
  OutsideDecision{handled: Bool, decision: Decision}

def realization_frame(realization: Rendered.State) -> Maybe<&2, Rendered.Frame>:
  match realization:
    case Rendered.AwaitingFrame{generation}: None{}
    case Rendered.Realized{generation, frame}: Some{frame}
    case Rendered.Unmet{generation, frame, violations}: Some{frame}

def inspect_frame(frame: Maybe<&2, Rendered.Frame>, +active: +List<SurfaceTypes.Node>, +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Legacy.DismissTarget>) -> RenderInspection:
  match frame:
    case None{}: RenderInspection{None{}, None{}, None{}, layer, dismiss}
    case Some{+observed}:
      Rendered.Frame{viewport, elements, focused, tabs, native_focus} = observed
      RenderInspection{Some{observed}, Some{Rendered.expected_tabs(active, elements, native_focus)},
        Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss}

def inspect_published(frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>, displayed: Maybe<&2, Published>) -> RenderInspection:
  match displayed:
    case None{}: RenderInspection{frame, None{}, None{}, layer, None{}}
    case Some{Published{world, semantic, scope, basis, published_frame}}:
      +active = InterfaceView.active_nodes(semantic)
      +dismiss = Legacy.dismiss_target(active)
      inspect_frame(frame, active, layer, dismiss)

def utility_owned(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}: Utility.owned(source)
    case None{}: False{}

def utility_inspection(displayed: Maybe<&2, Published>) -> RenderInspection:
  match displayed:
    case None{}: RenderInspection{None{}, None{}, None{}, None{}, None{}}
    case Some{Published{+world, semantic, scope, basis, frame}}:
      RenderInspection{frame, Some{SourceFrame.tabs(SourceFrame.expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}

def render_inspection_owned(utility: Bool, +stored: Legacy.State, +displayed: Maybe<&2, Published>) -> RenderInspection:
  match utility:
    case True{}: utility_inspection(displayed)
    case False{}:
      +observed_web_1 = Legacy.web(stored)
      +realization = Web.realization(observed_web_1)
      inspect_published(realization_frame(realization), Legacy.current_layer_key(stored), displayed)

def utility_rejected(lifecycle: Lifecycle) -> Bool:
  match lifecycle:
    case UtilityRejected{reason}: True{}
    case _: False{}

def auxiliary_owned(+state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  utility_owned(state) || utility_rejected(lifecycle)

def render_inspection(+state: State) -> RenderInspection:
  State{stored, serial, anchors, lifecycle, displayed, attention, updates} = state
  render_inspection_owned(auxiliary_owned(state), stored, displayed)

def pending_frame_effects_for(lifecycle: Lifecycle, realization: Rendered.State, displayed: Maybe<&2, Published>) -> +List<Legacy.Effect>:
  match lifecycle:
    case Displaying{capacity, engine, semantic}:
      match realization:
        case Rendered.AwaitingFrame{generation}:
          match displayed:
            case Some{Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
              [Legacy.BrowserEffect{Web.MeasureFrame{physical_generation}}]
            case None{}: Nil{}
        case _: Nil{}
    case UtilityDisplaying{purpose, engine}:
      match displayed:
        case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, None{}}}: [Legacy.BrowserEffect{Web.MeasureFrame{generation}}]
        case _: Nil{}
    case _: Nil{}

def pending_frame_effects(+state: State) -> +List<Legacy.Effect>:
  State{+observed_state_1, serial, anchors, lifecycle, displayed, attention, updates} = state
  +observed_web_2 = Legacy.web(observed_state_1)
  +realization = Web.realization(observed_web_2)
  pending_frame_effects_for(lifecycle, realization, displayed)

def with_generation(value: Nat, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  State{value_legacy, value, value_anchors, value_lifecycle, value_displayed, attention, updates}

def with_legacy(value: Legacy.State, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates} = state
  State{value, value_generation, value_anchors, value_lifecycle, value_displayed, attention, updates}

def attention(state: State) -> Navigation.Attention:
  State{legacy, generation, anchors, lifecycle, displayed, value, updates} = state
  value


def initial(+program: M.World(), +sequence: Nat) -> State:
  State{Legacy.initial(program, sequence), 0n, Nil{}, WaitingEnvironment{}, None{}, Navigation.initial(), DisplayUpdates{0n, 0n, 0n, 0n}}

def legacy(+state: State) -> Legacy.State:
  State{value, generation, anchors, lifecycle, displayed, attention, updates} = state
  value

def candidate_form_remainder(remainder: Nat) -> Controls.SupportingForm:
  match remainder:
    case 0n: Controls.FullSupporting{}
    case _: Controls.CompactSupporting{}

def candidate_form(index: Nat) -> Controls.SupportingForm:
  candidate_form_remainder(Nat.mod(index, 2n))

def candidate_pair(pair: Nat) -> View.Capacity:
  match pair:
    case 0n: View.Capacity{True{}, True{}}
    case 1n: View.Capacity{True{}, False{}}
    case 2n: View.Capacity{False{}, True{}}
    case _: View.Capacity{False{}, False{}}

def candidate(index: Nat) -> View.Capacity:
  candidate_pair(Nat.div(index, 2n))

def semantic_surface(+capacity: View.Capacity, +state: Legacy.State) -> SurfaceTypes.Surface:
  Legacy.semantic_surface(capacity, state)

def published(+world: Content.AllocatedWorld, +capacity: View.Capacity, +state: Legacy.State, +semantic: SurfaceTypes.Surface) -> Published:
  Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies} = world
  Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(state)), NativeFields.basis([source], semantic), None{}}

def admitted(+decision: Legacy.Decision, +world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +serial: Nat, +anchors: +List<Shell.Anchor>, +semantic: SurfaceTypes.Surface, attention: Navigation.Attention, updates: DisplayUpdates) -> Decision:
  Legacy.Decision{+accepted, collected} = decision
  Decision{publish_update(State{accepted, serial, anchors, Displaying{capacity, engine, semantic}, Some{published(world, capacity, accepted, semantic)}, attention, updates}), collected}

def current_legacy_surface(+state: Legacy.State) -> SurfaceTypes.Surface:
  +observed_web_1 = Legacy.web(state)
  +observed_application_2 = Web.application(observed_web_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +capacity = Platform.capacity(observed_platform_3)
  Legacy.semantic_surface(capacity, state)

def current_surface(+state: State) -> SurfaceTypes.Surface:
  current_legacy_surface(legacy(state))

def published_world(value: Published) -> Content.AllocatedWorld:
  Published{world, semantic, scope, basis, frame} = value
  world

def model_external_kind(kind: IM.ActionKind) -> Bool:
  match kind:
    case IM.SetAction{}: False{}
    case IM.ResetAction{}: False{}
    case _: True{}

def interactive_event(found: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, IM.EventIdentity>:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children}}, nested}}: Some{IM.EventIdentity{identity, occurrence}}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveView{event, command, label_value, enabled}, nested}}: Some{event}
    case _: None{}

def matching_interactive_events(left: Maybe<&2, IM.EventIdentity>, right: Maybe<&2, IM.EventIdentity>) -> Bool:
  match left right:
    case Some{old} Some{current}: IMSyntax.same_event(old, current)
    case None{} None{}: True{}
    case _ _: False{}

def matching_interactive_nodes(old: Maybe<&2, SurfaceTypes.Node>, current: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  matching_interactive_events(interactive_event(old), interactive_event(current))

def action_binding_updates(+key: String, found: Maybe<&2, SurfaceTypes.Node>, pending: Bool, owned: Bool) -> +List<NativeFields.Update>:
  match found:
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{component, occurrence, tag, attributes, IM.ActionBinding{kind, enabled, busy}, children}}, nested}}:
      [NativeFields.SetEnabled{key, owned && enabled && Bool.not(busy) && Bool.not(pending && model_external_kind(kind))}]
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveView{event, command, label_value, enabled}, nested}}:
      [NativeFields.SetEnabled{key, owned && enabled}]
    case _: [NativeFields.SetEnabled{key, False{}}]

def current_action_update(+node: SurfaceTypes.Node, key: UIIdentity.Key, +current: +List<SurfaceTypes.Node>, pending: Bool) -> +List<NativeFields.Update>:
  +encoded: String = UIIdentity.encode(key)
  +found: Maybe<&2, SurfaceTypes.Node> = InterfaceView.find_node(current, encoded)
  action_binding_updates(encoded, found, pending, matching_interactive_nodes(Some{node}, found))

def action_update(+node: SurfaceTypes.Node, +current: +List<SurfaceTypes.Node>, pending: Bool) -> +List<NativeFields.Update>:
  SurfaceTypes.Node{+key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.ActionBinding{kind, enabled, busy}, nested}}:
      current_action_update(node, key, current, pending)
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}:
      current_action_update(node, key, current, pending)
    case _: Nil{}

def action_updates(nodes: +List<SurfaceTypes.Node>, +current: +List<SurfaceTypes.Node>, +pending: Bool) -> +List<NativeFields.Update>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      List.append(&2, NativeFields.Update, action_update(node, current, pending),
        List.append(&2, NativeFields.Update, action_updates(children, current, pending), action_updates(rest, current, pending)))

type ActionQueryCount is Data:
  NoActions{}
  OneAction{}
  ManyActions{}

def action_query(node: SurfaceTypes.Node) -> Bool:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, IM.ActionBinding{kind, enabled, busy}, nested}}: True{}
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}: True{}
    case _: False{}

def action_count_add(present: Bool, count: ActionQueryCount) -> ActionQueryCount:
  match present count:
    case False{} retained: retained
    case True{} NoActions{}: OneAction{}
    case True{} OneAction{}: ManyActions{}
    case True{} ManyActions{}: ManyActions{}

def action_count_continue(count: ActionQueryCount, rest: ActionQueryCount -> ActionQueryCount) -> ActionQueryCount:
  match count:
    case ManyActions{}: ManyActions{}
    case retained: rest(retained)

def action_count(nodes: +List<SurfaceTypes.Node>, count: ActionQueryCount) -> ActionQueryCount:
  match nodes count:
    case retained ManyActions{}: ManyActions{}
    case Nil{} initial: initial
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, +children}, rest} initial:
      action_count_continue(action_count_add(action_query(SurfaceTypes.Node{key, semantic, label, role, meaning, children}), initial), (after_node =>
        action_count_continue(action_count(children, after_node), (after_children =>
          action_count(rest, after_children)))))

def action_count_many(count: ActionQueryCount) -> Bool:
  match count:
    case ManyActions{}: True{}
    case _: False{}

def actions_many(nodes: +List<SurfaceTypes.Node>) -> Bool:
  action_count_many(action_count(nodes, NoActions{}))

def current_action_named_update(+node: SurfaceTypes.Node, key: UIIdentity.Key,
  +current: +List<NativeFields.NamedSemanticNode>, pending: Bool) -> +List<NativeFields.Update>:
  +encoded: String = UIIdentity.encode(key)
  +found: Maybe<&2, SurfaceTypes.Node> = NativeFields.find_named(current, encoded)
  action_binding_updates(encoded, found, pending, matching_interactive_nodes(Some{node}, found))

def action_named_update(+node: SurfaceTypes.Node, +current: +List<NativeFields.NamedSemanticNode>, pending: Bool) -> +List<NativeFields.Update>:
  SurfaceTypes.Node{+key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.ActionBinding{kind, enabled, busy}, nested}}:
      current_action_named_update(node, key, current, pending)
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}:
      current_action_named_update(node, key, current, pending)
    case _: Nil{}

def action_updates_named(nodes: +List<SurfaceTypes.Node>, +current: +List<NativeFields.NamedSemanticNode>, +pending: Bool) -> +List<NativeFields.Update>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      List.append(&2, NativeFields.Update, action_named_update(node, current, pending),
        List.append(&2, NativeFields.Update, action_updates_named(children, current, pending), action_updates_named(rest, current, pending)))

def native_updates_named_scope(+basis: NativeFields.Basis, +old: +List<SurfaceTypes.Node>,
  +surface: SurfaceTypes.Surface, +pending: Bool) -> +List<NativeFields.Update>:
  NativeFields.Basis{fields, controls} = basis
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  match scope:
    case None{}:
      +named = NativeFields.prepare_named(NativeFields.forest(surface))
      List.append(&2, NativeFields.Update, NativeFields.updates_fields_named(fields, named),
        action_updates_named(old, named, pending))
    case Some{key}:
      +named_fields = NativeFields.prepare_named(NativeFields.forest(surface))
      +named_actions = NativeFields.prepare_named(InterfaceView.active_nodes(surface))
      List.append(&2, NativeFields.Update, NativeFields.updates_fields_named(fields, named_fields),
        action_updates_named(old, named_actions, pending))

def native_updates_families(fields_many: Bool, actions_many: Bool, +basis: NativeFields.Basis,
  +old: +List<SurfaceTypes.Node>, +surface: SurfaceTypes.Surface, +pending: Bool) -> +List<NativeFields.Update>:
  match fields_many actions_many basis:
    case False{} False{} retained:
      List.append(&2, NativeFields.Update, NativeFields.updates(retained, surface),
        action_updates(old, InterfaceView.active_nodes(surface), pending))
    case True{} False{} NativeFields.Basis{fields, controls}:
      +named_fields = NativeFields.prepare_named(NativeFields.forest(surface))
      List.append(&2, NativeFields.Update, NativeFields.updates_fields_named(fields, named_fields),
        action_updates(old, InterfaceView.active_nodes(surface), pending))
    case False{} True{} retained:
      +named_actions = NativeFields.prepare_named(InterfaceView.active_nodes(surface))
      List.append(&2, NativeFields.Update, NativeFields.updates(retained, surface),
        action_updates_named(old, named_actions, pending))
    case True{} True{} retained: native_updates_named_scope(retained, old, surface, pending)

def native_updates(+state: State) -> +List<NativeFields.Update>:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: Nil{}
    case Some{Published{world, semantic, scope, +basis, frame}}:
      NativeFields.Basis{fields, controls} = basis
      +surface: SurfaceTypes.Surface = current_surface(state)
      +old: +List<SurfaceTypes.Node> = InterfaceView.active_nodes(semantic)
      native_updates_families(NativeFields.fields_many(fields), actions_many(old), basis, old, surface, semantic_pending(state))

def field_owned(+key: String, +state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: False{}
    case Some{Published{world, semantic, scope, basis, frame}}: NativeFields.field_owned(basis, key, current_surface(state))

def admit(+world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: SurfaceTypes.Surface) -> Decision:
  State{+observed_state_1, serial, anchors, lifecycle, displayed, attention, updates} = state
  +observed_web_2 = Legacy.web(observed_state_1)
  +observed_application_3 = Web.application(observed_web_2)
  +core = Platform.core(observed_application_3)
  +platform = Platform.platform(observed_application_3)
  +generation = Web.generation(observed_web_2)
  +environment = Web.environment(observed_web_2)
  +font = Web.typography(observed_web_2)
  +sequence = Legacy.sequence(observed_state_1)
  +ticket = Legacy.next_ticket(observed_state_1)
  +pending = Legacy.pending(observed_state_1)
  +receipt = Legacy.receipt(observed_state_1)
  +decision = Platform.reflow_capacity(Platform.Decision{Platform.unchanged(core), platform, Nil{}}, capacity)
  admitted(Legacy.finish(Web.production_commit(decision, generation, environment, font), sequence, ticket, pending, "", receipt), world, capacity, engine, serial, anchors, semantic, attention, updates)

def display_ready(+state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle displayed:
    case UtilityRejected{problem} _: False{}
    case _ Some{value}: True{}
    case _ None{}: False{}

def displayed_generation(+state: State) -> Nat:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: 0n
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}: generation

def realization_status(realization: Rendered.State) -> String:
  match realization:
    case Rendered.AwaitingFrame{generation}: "awaiting-frame"
    case Rendered.Realized{generation, frame}: "ready"
    case Rendered.Unmet{generation, frame, violations}: "unmet"

def legacy_render_status(+state: Legacy.State) -> String:
  +observed_web_1 = Legacy.web(state)
  +realization = Web.realization(observed_web_1)
  realization_status(realization)

def utility_render_status(displayed: Maybe<&2, Published>) -> String:
  match displayed:
    case Some{Published{world, semantic, scope, basis, Some{frame}}}: "ready"
    case _: "awaiting-frame"

def render_status(+state: State) -> String:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Displaying{capacity, engine, semantic}: legacy_render_status(legacy)
    case UtilityDisplaying{purpose, engine}: utility_render_status(displayed)
    case UtilityRejected{reason}: "blocked"
    case Blocked{reason}: "blocked"
    case _: "waiting"

def realization_violations(realization: Rendered.State) -> +List<Rendered.Violation>:
  match realization:
    case Rendered.Unmet{generation, frame, violations}: violations
    case _: Nil{}

def render_violations(+state: State) -> +List<Rendered.Violation>:
  realization_violations(Web.realization(Legacy.web(legacy(state))))

def measurement_request_plan(plan: Plan.Plan, generation: Nat, round: Nat) -> Maybe<&2, MeasurementRequest>:
  match plan:
    case Plan.Awaiting{plan_generation, first, remaining}:
      Some{MeasurementRequest{MeasurementTicket{generation, round}, Plan.Awaiting{plan_generation, first, remaining}}}
    case other: None{}

def measurement_request(+state: State) -> Maybe<&2, MeasurementRequest>:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Measuring{index, capacity, +engine, semantic, round}:
      measurement_request_plan(World.plan(engine), World.snapshot_generation(World.snapshot(engine)), round)
    case UtilityMeasuring{purpose, +engine, round, glyph_only}:
      measurement_request_plan(World.plan(engine), World.snapshot_generation(World.snapshot(engine)), round)
    case other: None{}

def application_document(nodes: +List<CodeObservation.Node>) -> CodeObservation.Document:
  CodeObservation.Document{CodeObservation.Element{"@browser/application", "div", [CodeObservation.Property{"class", "native-application"}], Nil{}, Nil{}, nodes}, "Selvedge"}

def observed_lifecycle_at(+capacity: Nat, +lifecycle: Lifecycle, +displayed: Maybe<&2, Published>, +font: T.Presentation) -> CodeObservation.Document:
  match displayed:
    case Some{world}: application_document(Renderer.nodes(published_world(world)))
    case None{}: application_document(Nil{})

def observed_lifecycle(+lifecycle: Lifecycle, +displayed: Maybe<&2, Published>, +font: T.Presentation) -> CodeObservation.Document:
  observed_lifecycle_at(NaturalSize.limit(), lifecycle, displayed, font)

def observed(+displayed: Maybe<&2, Published>, +lifecycle: Lifecycle, +font: T.Presentation) -> CodeObservation.Document:
  observed_lifecycle(lifecycle, displayed, font)

def observe(+capacity: Nat, +state: State) -> CodeObservation.Document:
  State{+legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  +observed_web_1 = Legacy.web(legacy)
  +font = Web.typography(observed_web_1)
  observed_lifecycle_at(capacity, lifecycle, displayed, T.Presentation{T.Body{}, T.Regular{}, F.scale(font)})

def display_category() -> State -> Type: Categories.holds(State, state => display_ready(state))

def published_document_at(+capacity: Nat, member: Categories.Membership<State, display_category()>) -> Publication:
  Categories.Membership{+state, evidence} = member
  Publish{displayed_generation(state), observe(capacity, state), native_updates(state)}

def published_document_admitted(+capacity: Nat, admission: Maybe<&1, Categories.Membership<State, display_category()>>, +state: State) -> Publication:
  match admission:
    case Some{member}: published_document_at(capacity, member)
    case None{}: Publish{0n, observe(capacity, state), native_updates(state)}

def published_document(+capacity: Nat, +state: State) -> Publication:
  published_document_admitted(capacity, Categories.admit(State, candidate => display_ready(candidate), state), state)

type PublicationCandidate is Data:
  PublicationCandidate{capacity: Nat, last_published: Nat, state: State}

def publication_policy_predicate(candidate: PublicationCandidate) -> Bool:
  PublicationCandidate{capacity, +last_published, +state} = candidate
  Bool.not(Nat.is_eq(last_published, 0n)) &&
    display_ready(state) && Nat.is_eq(displayed_generation(state), last_published)

def publication_policy_category() -> PublicationCandidate -> Type:
  Categories.holds(PublicationCandidate, publication_policy_predicate)

def publication_policy_owned(member: Categories.Membership<PublicationCandidate, publication_policy_category()>) -> Publication:
  Categories.Membership{PublicationCandidate{capacity, last_published, state}, evidence} = member
  KeepPublished{native_updates(state)}

def publication_policy_admitted(+capacity: Nat, admission: Maybe<&1, Categories.Membership<PublicationCandidate, publication_policy_category()>>, +state: State) -> Publication:
  match admission:
    case Some{member}: publication_policy_owned(member)
    case None{}: published_document(capacity, state)

def publication_policy_at(+capacity: Nat, +last_published: Nat, +state: State) -> Publication:
  publication_policy_admitted(capacity, Categories.admit(PublicationCandidate, publication_policy_predicate, PublicationCandidate{capacity, last_published, state}), state)

def publication_lifecycle_at(+capacity: Nat, lifecycle: Lifecycle, +last_published: Nat, +state: State) -> Publication:
  match lifecycle:
    case UtilityRejected{problem}: Publish{0n, observe(capacity, state), native_updates(state)}
    case other: publication_policy_at(capacity, last_published, state)

def publication(+capacity: Nat, +last_published: Nat, +state: State) -> Publication:
  publication_lifecycle_at(capacity, lifecycle(state), last_published, state)

type PublicationFocusCandidate is Data:
  PublicationFocusCandidate{generation: Nat, ticket: Nat, before: Focus.Target}

def publication_focus_predicate(candidate: PublicationFocusCandidate) -> Bool:
  PublicationFocusCandidate{generation, ticket, before} = candidate
  Bool.not(Nat.is_eq(generation, 0n))

def publication_focus_category() -> PublicationFocusCandidate -> Type: Categories.holds(PublicationFocusCandidate, publication_focus_predicate)

def publication_focus_loss(member: Categories.Membership<PublicationFocusCandidate, publication_focus_category()>) -> Maybe<&2, Platform.Input>:
  Categories.Membership{PublicationFocusCandidate{generation, ticket, before}, evidence} = member
  Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}}

def publication_focus_admitted(admission: Maybe<&1, Categories.Membership<PublicationFocusCandidate, publication_focus_category()>>) -> Maybe<&2, Platform.Input>:
  match admission:
    case Some{member}: publication_focus_loss(member)
    case None{}: None{}

def publication_focus_current(generation: Nat, ticket: Nat, before: Focus.Target) -> Maybe<&2, Platform.Input>:
  publication_focus_admitted(Categories.admit(PublicationFocusCandidate, publication_focus_predicate, PublicationFocusCandidate{generation, ticket, before}))

def publication_focus_feedback(+publication: Publication, ticket: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>) -> Maybe<&2, Platform.Input>:
  match publication before after:
    case Publish{generation, document, fields} Some{target} None{}:
      publication_focus_current(generation, ticket, target)
    case _ _ _: None{}

def probe_document(+job: Plan.Job) -> CodeObservation.Document: Probe.document(job)

def probe_target_keys(+job: Plan.Job) -> +List<String>: Probe.target_keys(job)

def decision_state(value: Decision) -> State:
  Decision{state, effects} = value
  state

def visible_anchor(environment: Design.Environment, left: AnchorGeometry.Origin, top: AnchorGeometry.Origin, width: Nat, height: Nat) -> AnchorGeometry.Box:
  Design.Environment{Design.Viewport{viewport_width, viewport_height}, dark, root} = environment
  AnchorGeometry.visible(left, top, width, height, viewport_width, viewport_height)

def capture_anchor(key: String, left: AnchorGeometry.Origin, top: AnchorGeometry.Origin, width: Nat, height: Nat, +state: State) -> Decision:
  State{+legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  bounds = visible_anchor(Web.environment(Legacy.web(legacy)), left, top, width, height)
  Decision{State{legacy, serial, Shell.Anchor{key, bounds} <> anchors, lifecycle, displayed, attention, updates}, Nil{}}

def legacy_focus_ticket(+state: Legacy.State) -> Nat:
  +observed_web_1 = Legacy.web(state)
  +observed_application_2 = Web.application(observed_web_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +focus_ticket = Platform.focus_ticket(observed_platform_3)
  focus_ticket

def focus_ticket(+state: State) -> Nat:
  legacy_focus_ticket(legacy(state))

def scope_if_rejected(rejected: Bool, +scope: Focus.Scope) -> Focus.Scope:
  match rejected:
    case True{}: Focus.Document{}
    case False{}: scope

def active_scope(+state: State) -> Focus.Scope:
  State{+legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: scope_if_rejected(utility_rejected(lifecycle), Legacy.active_focus_scope(legacy))
    case Some{Published{world, semantic, scope, basis, frame}}: scope

def empty() -> M.World(): Legacy.empty()

def program(+state: State) -> M.World(): Legacy.program(legacy(state))

def code_key(+source: Code.Source, +ordinal: Nat) -> String: Legacy.code_key(source, ordinal)

def activity_font_budget(metrics: Maybe<&2, F.ActivityMetrics>) -> Nat:
  match metrics:
    case None{}: 1n
    case Some{metrics}: 0n

def font_budget(+font: F.State) -> Nat:
  match font:
    case F.Pending{generation, scale}: 1n
    case F.Ready{generation, scale, body, content}:
      activity_font_budget(F.activity_metrics(F.Ready{generation, scale, body, content}))
    case F.Failed{generation, scale}: 0n

def source_changed(+input: Web.Input) -> Bool:
  match input:
    case Web.FrameObserved{generation, frame}: False{}
    case Web.PlatformInput{Platform.FocusObserved{identity}}: False{}
    case Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}: False{}
    case Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}: False{}
    case Web.PlatformInput{Platform.ReadingInput{task, generation, event}}: False{}
    case Web.PlatformInput{Platform.MotionPreference{reduced}}: False{}
    case _: True{}

def legacy_outside(+identity: String, +stored: Legacy.State) -> Legacy.OutsideDecision:
  Legacy.outside_event(identity, stored)

def append(+first: +List<Legacy.Effect>, +value: Decision) -> Decision:
  Decision{next, later} = value
  Decision{next, List.append(&2, Legacy.Effect, first, later)}

def current_font(+state: Legacy.State) -> F.State:
  +observed_web_1 = Legacy.web(state)
  +font = Web.typography(observed_web_1)
  font

def measurement_plan_at(capacity: Nat, +state: State) -> F.Plan:
  F.activity_request_plan(capacity, current_font(legacy(state)))

def measurement_plan(+state: State) -> F.Plan:
  measurement_plan_at(NaturalSize.limit(), state)

def measurement_budget(+state: State) -> Nat:
  font_budget(current_font(legacy(state)))

def semantic_generation(+state: Legacy.State) -> Nat:
  +observed_web_1 = Legacy.web(state)
  +generation = Web.generation(observed_web_1)
  generation

def set_lifecycle(+state: State, lifecycle: Lifecycle) -> State:
  State{legacy, serial, anchors, old, displayed, attention, updates} = state
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates}

def no_candidate(state: State) -> Decision:
  Decision{set_lifecycle(state, Blocked{"The interface does not fit the available space"}), Nil{}}

def retry_candidate(+more: Bool, +index: Nat, +state: State) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{no_candidate(state)}

def failure_axis(axis: Allocation.Axis) -> String:
  match axis:
    case Allocation.InlineAxis{}: "width"
    case Allocation.BlockAxis{}: "height"

def failure_reason(reason: Allocation.FailureReason) -> String:
  match reason:
    case Allocation.AuthoredRangeConflict{}: "authored range conflict"
    case Allocation.InsufficientSpace{}: "insufficient space"
    case Allocation.AllocationBoundExceeded{budget}: "allocation bound exceeded (budget " ++ Nat.show(budget) ++ ")"

def failure_message(failure: Allocation.Failure) -> String:
  Allocation.Failure{key, axis, required, available, reason} = failure
  "The interface does not fit the available space: " ++ key ++ "; " ++ failure_axis(axis) ++
    " required " ++ Nat.show(required) ++ "px, available " ++ Nat.show(available) ++ "px; " ++ failure_reason(reason)

def infeasible_candidate(+more: Bool, +index: Nat, +state: State, failure: Allocation.Failure) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{Decision{set_lifecycle(state, Blocked{failure_message(failure)}), Nil{}}}

def supporting_width_admitted(form: Controls.SupportingForm, requirement: Maybe<&2, Adaptation.RegionDemand>) -> Bool:
  match form requirement:
    case Controls.FullSupporting{} None{}: True{}
    case Controls.FullSupporting{} Some{Adaptation.RegionDemand{available, preferred}}:
      Nat.is_le(preferred, available)
    case Controls.CompactSupporting{} _: True{}

def supporting_admitted(index: Nat, world: Content.AllocatedWorld) -> Bool:
  supporting_width_admitted(candidate_form(index), Adaptation.world_region_demand(world,
    Adaptation.RegionAttribute{"allocated-region", "supporting-controls"}))

def supporting_retry(more: Bool, index: Nat, state: State) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{no_candidate(state)}

def selected_supporting(admitted: Bool, +world: Content.AllocatedWorld, +index: Nat, capacity: View.Capacity, engine: World.Engine, state: State, semantic: SurfaceTypes.Surface) -> Search:
  match admitted:
    case True{}: Stopped{admit(world, capacity, engine, state, semantic)}
    case False{}: supporting_retry(Nat.is_lt(index, 7n), index, state)

def selected(+outcome: Plan.Plan, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: SurfaceTypes.Surface, round: Nat) -> Search:
  match outcome:
    case Plan.Ready{world}: selected_supporting(supporting_admitted(index, world), world, index, capacity, engine, state, semantic)
    case Plan.Awaiting{generation, first, remaining}: Stopped{Decision{set_lifecycle(state, Measuring{index, capacity, engine, semantic, round}), Nil{}}}
    case Plan.Invalid{error}: Stopped{Decision{set_lifecycle(state, Blocked{"Physical source or receipt is invalid"}), Nil{}}}
    case Plan.Infeasible{failure}: infeasible_candidate(Nat.is_lt(index, 7n), index, state, failure)

def surface_layers(surface: SurfaceTypes.Surface) -> +List<View.Layer>:
  SurfaceTypes.Surface{InteractionTypes.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker}, base, overlays, scope} = surface
  layers

def viewport_box(environment: Design.Environment) -> AnchorGeometry.Box:
  Design.Environment{Design.Viewport{width, height}, dark, root} = environment
  AnchorGeometry.Box{0n, 0n, width, height}

# Browser feedback participates in the same authored tree and measurements.

def notice(+ticket: Nat, reason: String, +font: T.Presentation) -> Source.Node:
  Source.Box{UIIdentity.entity(UIIdentity.place("@browser"), "unknown", Nat.show(ticket)), Source.Paragraph{},
    Shell.neutral(T.with_tier(font, T.Support{}), Space.Vertical{}, Space.StretchSize{}, Space.NaturalSize{}, AnchorGeometry.Stretch{}),
    [Source.RoleAttribute{"status"}],
    [Source.Text{UIIdentity.part(UIIdentity.entity(UIIdentity.place("@browser"), "unknown", Nat.show(ticket)), "text"), "Connection interrupted. Submission status is unknown. " ++ reason,
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
      Source.Box{key, tag, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), main_children(tag, feedback_nodes(children, pending, font), pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Control{+key, tag, style, attrs, name, enabled, first, remaining, children}, rest}:
      Source.Control{key, tag, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), name, enabled, first, remaining, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.NativeAttachment{+key, target, attrs, style, children}, rest}:
      Source.NativeAttachment{key, target, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), style, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Field{+key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}, rest}:
      Source.Field{key, kind, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), value, placeholder, options, policy, name, enabled, first, remaining} <> feedback_nodes(rest, pending, font)
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}:
      Source.RichText{key, style, content, feedback_nodes(attachments, pending, font), native_owner} <> feedback_nodes(rest, pending, font)
    case Con{Source.Text{key, value, choice, wrapping}, rest}:
      Source.Text{key, value, choice, wrapping} <> feedback_nodes(rest, pending, font)
    case Con{Source.Glyph{key, drawing, style}, rest}:
      Source.Glyph{key, drawing, style} <> feedback_nodes(rest, pending, font)

def only_root(nodes: +List<Source.Node>, fallback: Source.Node) -> Source.Node:
  match nodes:
    case Nil{}: fallback
    case Con{node, rest}: node

def pending(+state: Legacy.State) -> +List<Legacy.Pending>:
  +entries = Legacy.pending(state)
  entries

def feedback_root(+source: Source.Node, +entries: +List<Legacy.Pending>, +font: T.Presentation) -> Source.Node:
  only_root(feedback_nodes(source <> Nil{}, entries, font), source)

def frozen(+source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: AnchorGeometry.Box, +state: State, +semantic: SurfaceTypes.Surface) -> Search:
  State{legacy, +serial, anchors, lifecycle, displayed, attention, updates} = state
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), feedback_root(source, pending(legacy), font), font}, viewport)
  selected(World.plan(engine), index, capacity, engine, freeze_update(State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed, attention, updates}), semantic, 0n)

def authored(+result: Shell.ShellAuthorship, +index: Nat, +capacity: View.Capacity, +font: T.Presentation,
  +viewport: AnchorGeometry.Box, +state: State, +semantic: SurfaceTypes.Surface) -> Search:
  match result:
    case Shell.Rejected{key, problem}: Stopped{Decision{set_lifecycle(state, Blocked{"Unsupported authored content: " ++ UIIdentity.encode(key)}), Nil{}}}
    case Shell.Ready{source}: frozen(source, index, capacity, font, viewport, state, semantic)

def calibrated_parameters_at(physical_capacity: Nat, parameters: Maybe<&2, Design.LayoutParameters>, +index: Nat, +state: State) -> Search:
  match parameters:
    case None{}: Stopped{Decision{set_lifecycle(state, Blocked{"Font metrics exceed supported layout size."}), Nil{}}}
    case Some{parameters}:
      State{+observed_state_1, serial, +anchors, lifecycle, displayed, attention, updates} = state
      +observed_web_2 = Legacy.web(observed_state_1)
      +observed_application_3 = Web.application(observed_web_2)
      +environment = Web.environment(observed_web_2)
      +font = Web.typography(observed_web_2)
      +stored: Legacy.State = Legacy.with_web(Web.with_application(observed_application_3, observed_web_2), observed_state_1)
      +capacity = candidate(index)
      +semantic = semantic_surface(capacity, stored)
      +layers = surface_layers(semantic)
      +surface = Web.appearance_surface_supporting_navigation(semantic, environment, font, candidate_form(index), attention)
      +presentation: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, F.scale(font)}
      authored(Shell.source_supporting(physical_capacity, surface, parameters, capacity, layers, anchors, presentation, candidate_form(index)),
        index, capacity, presentation, viewport_box(environment), State{stored, serial, anchors, lifecycle, displayed, attention, updates}, semantic)

def calibrated_parameters(parameters: Maybe<&2, Design.LayoutParameters>, index: Nat, state: State) -> Search:
  calibrated_parameters_at(NaturalSize.limit(), parameters, index, state)

def calibrated_activity_metrics_at(+physical_capacity: Nat, body: T.Metric, metrics: Maybe<&2, F.ActivityMetrics>, +index: Nat, +state: State) -> Search:
  match metrics:
    case None{}: Stopped{Decision{set_lifecycle(state, WaitingFont{}), Nil{}}}
    case Some{F.ActivityMetrics{primary, support}}:
      calibrated_parameters_at(physical_capacity, Design.parameters(physical_capacity, F.scale(current_font(legacy(state))), body, primary, support), index, state)

def calibrated_activity_metrics(body: T.Metric, metrics: Maybe<&2, F.ActivityMetrics>, index: Nat, state: State) -> Search:
  calibrated_activity_metrics_at(NaturalSize.limit(), body, metrics, index, state)

def calibrated_body_at(+physical_capacity: Nat, metric: T.Metric, +index: Nat, +state: State) -> Search:
  calibrated_activity_metrics_at(physical_capacity, metric, F.activity_metrics_at(physical_capacity, current_font(legacy(state))), index, state)

def calibrated_body(metric: T.Metric, index: Nat, state: State) -> Search:
  calibrated_body_at(NaturalSize.limit(), metric, index, state)

def calibrated(+body: Maybe<&2, T.Metric>, +index: Nat, +state: State) -> Search:
  match body:
    case None{}: Stopped{Decision{set_lifecycle(state, WaitingFont{}), Nil{}}}
    case Some{metric}: calibrated_body(metric, index, state)

def font_candidate(font: F.State, +index: Nat, +state: State) -> Search:
  match font:
    case F.Failed{generation, scale}: Stopped{Decision{set_lifecycle(state, Blocked{"Font measurements could not be validated."}), Nil{}}}
    case other: calibrated(F.body(other), index, state)

def one_candidate(+index: Nat, +state: State) -> Search:
  font_candidate(current_font(legacy(state)), index, state)

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

def utility_publish(+world: Content.AllocatedWorld, purpose: Utility.Purpose, engine: World.Engine, state: State) -> Decision:
  State{+stored, serial, anchors, lifecycle, displayed, attention, updates} = state
  Decision{State{stored, serial, anchors, UtilityDisplaying{purpose, engine},
    Some{Published{world, current_legacy_surface(stored), Focus.Document{}, NativeFields.Basis{Nil{}, Nil{}}, None{}}}, attention, updates}, Nil{}}

def utility_selected(plan: Plan.Plan, +purpose: Utility.Purpose, +engine: World.Engine, round: Nat, glyph_only: Bool, +state: State) -> Decision:
  match plan:
    case Plan.Ready{world}: utility_publish(world, purpose, engine, state)
    case Plan.Awaiting{generation, first, remaining}: Decision{set_lifecycle(state, UtilityMeasuring{purpose, engine, round, glyph_only}), Nil{}}
    case Plan.Infeasible{failure}: Decision{set_lifecycle(state, Blocked{failure_message(failure)}), Nil{}}
    case Plan.Invalid{error}: Decision{set_lifecycle(state, Blocked{"Frontend utility source is invalid"}), Nil{}}

def utility_start(+purpose: Utility.Purpose, +glyph_only: Bool, +state: State) -> Decision:
  State{+stored, +serial, anchors, lifecycle, displayed, attention, updates} = state
  +observed_web_1 = Legacy.web(stored)
  +environment = Web.environment(observed_web_1)
  +font = Web.typography(observed_web_1)
  +presentation: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, F.scale(font)}
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), UtilityProof.source(purpose, presentation, glyph_only), presentation}, viewport_box(environment))
  utility_selected(World.plan(engine), purpose, engine, 0n, glyph_only, State{stored, (serial + 1n : Nat), anchors, lifecycle, displayed, attention, updates})

def utility_if_needed(decision: Decision) -> Decision:
  Decision{+state, effects} = decision
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case WaitingEnvironment{}: append(effects, utility_start(Utility.Preparing{}, False{}, state))
    case WaitingFont{}: append(effects, utility_start(Utility.Preparing{}, False{}, state))
    case Blocked{reason}: append(effects, utility_start(Utility.Recovery{reason}, False{}, state))
    case _: Decision{state, effects}

def build(index: Nat, state: State) -> Decision:
  utility_if_needed(finish_search(search_run(8n, Searching{index, state})))

def continue_pending(pending: Bool, +state: State, effects: +List<Legacy.Effect>) -> Decision:
  match pending:
    case True{}: append(effects, build(0n, state))
    case False{}: Decision{state, effects}

def normal_candidate_finished(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Displaying{capacity, engine, semantic}: True{}
    case _: False{}

def continue_latest(decision: Decision) -> Decision:
  Decision{+state, effects} = decision
  continue_pending(display_pending(state) && normal_candidate_finished(state), state, effects)

def accept_measuring(measuring: Bool, first: +List<Legacy.Effect>, +state: State) -> Decision:
  match measuring:
    case True{}: Decision{state, first}
    case False{}: append(first, build(0n, state))

def accept_updated(first: +List<Legacy.Effect>, +state: State) -> Decision:
  accept_measuring(active_measurement(state), first, state)

def accepted(+rebuild: Bool, +first: +List<Legacy.Effect>, +state: State) -> Decision:
  match rebuild:
    case False{}: Decision{state, List.append(&2, Legacy.Effect, first, pending_frame_effects(state))}
    case True{}: accept_updated(first, advance_update(state))

def synchronized_result(value: Legacy.Decision, first: +List<Legacy.Effect>) -> Legacy.Decision:
  Legacy.Decision{synced, later} = value
  Legacy.Decision{synced, List.append(&2, Legacy.Effect, first, later)}

def synchronize_observed(value: Legacy.Decision, first: +List<Legacy.Effect>) -> Legacy.Decision:
  Legacy.Decision{next, effects} = value
  synchronized_result(Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}}}}, next), List.append(&2, Legacy.Effect, first, effects))

def synchronize_interactive(value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{+next, first} = value
  +session = E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(next)))))
  synchronize_observed(Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{E.namespace(session), Legacy.sequence(next), E.interactive_fresh(session), E.interactive_allowed(session)}}}}}, next), first)

def accept_synchronized(+rebuild: Bool, value: Legacy.Decision, +state: State) -> Decision:
  Legacy.Decision{next, first} = value
  State{old, serial, anchors, lifecycle, displayed, attention, updates} = state
  accepted(rebuild, first, State{next, serial, anchors, lifecycle, displayed, attention, updates})

def accept(+rebuild: Bool, value: Legacy.Decision, +state: State) -> Decision:
  match rebuild:
    case False{}: accept_synchronized(False{}, value, state)
    case True{}: accept_synchronized(True{}, synchronize_interactive(value), state)

def current_namespace(state: State) -> String:
  E.namespace(E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(legacy(state)))))))

def source_allowed(state: State) -> Bool:
  E.interactive_allowed(E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(legacy(state)))))))

def source_fresh(state: State) -> Bool:
  E.interactive_fresh(E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(legacy(state)))))))

def invalidate_display(state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  State{legacy, serial, anchors, WaitingEnvironment{}, None{}, attention, updates}

def invalidate_if(changed: Bool, state: State) -> State:
  match changed:
    case True{}: invalidate_display(state)
    case False{}: state

def environment_result(namespace: String, fresh: Bool, allowed: Bool, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{+next, first} = value
  synchronized_result(Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{namespace, Legacy.sequence(next), fresh, allowed}}}}}, next), first)

def viewed_task_exists(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: True{}

def viewed_task_removed(route: UserInput.Route, program: M.World()) -> Bool:
  match route:
    case UserInput.Conversation{task}: Bool.not(viewed_task_exists(Tasks.find(Commands.entries(program), task)))
    case _: False{}

def view_removed(program: M.World(), state: State) -> Bool:
  viewed_task_removed(E.route(E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(legacy(state))))))), program)

def physical_invalidated(+before: State, +after: State) -> Bool:
  Bool.not(String.eq(current_namespace(before), current_namespace(after))) ||
    (source_allowed(before) && Bool.not(source_allowed(after))) ||
    (Bool.not(view_removed(Legacy.program(legacy(before)), before)) &&
      view_removed(Legacy.program(legacy(after)), before))

def service_access(state: State) -> Services.Access:
  Services.access(InteractionState.services(Platform.core(Web.application(Legacy.web(legacy(state))))))

def connection_lost(access: Services.Access) -> Bool:
  match access:
    case Services.ConnectionLost{connection, reason}: True{}
    case _: False{}

def reconnect_current(needed: Bool, value: Legacy.Decision) -> Legacy.Decision:
  match needed:
    case False{}: value
    case True{}:
      Legacy.Decision{next, first} = value
      synchronized_result(Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ServiceInput{Services.Connect{}}}}}, next), first)

def reconnect_result(+changed: Bool, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{+next, first} = value
  reconnect_current(changed || connection_lost(Services.access(InteractionState.services(Platform.core(Web.application(Legacy.web(next)))))), Legacy.Decision{next, first})

def snapshot_result(+changed: Bool, +namespace: String, +sequence: Nat, program: M.World(), +state: State) -> Legacy.Decision:
  reconnect_result(changed, environment_result(namespace, True{}, True{}, Legacy.snapshot_new(changed || Nat.is_lt(Legacy.sequence(legacy(state)), sequence), sequence, program, Legacy.namespace_reset(changed, legacy(state)))))

def snapshot_current(accepted: Bool, +changed: Bool, +namespace: String, +sequence: Nat, +program: M.World(), +state: State) -> Decision:
  match accepted:
    # DEFENSE: A refresh response may carry an older durable sequence than a command response already accepted in this namespace.
    case False{}: Decision{state, Nil{}}
    case True{}:
      accept(True{}, snapshot_result(changed, namespace, sequence, program, state), invalidate_if(changed || view_removed(program, state), state))

def recover_namespace(value: Legacy.Decision, state: State) -> Decision:
  Legacy.Decision{observed, effects} = value
  utility_if_needed(Decision{set_lifecycle(with_legacy(observed, invalidate_display(state)), Blocked{"Invalid service data namespace"}), effects})

def invalid_namespace(+state: State) -> Decision:
  recover_namespace(synchronize_interactive(environment_result(current_namespace(state), False{}, False{}, Legacy.Decision{legacy(state), Nil{}})), state)

def snapshot_namespace(valid: Bool, +namespace: String, +sequence: Nat, program: M.World(), +state: State) -> Decision:
  match valid:
    # DEFENSE: The service snapshot protocol requires a valid data namespace before exposing or persisting its source values.
    case False{}: invalid_namespace(state)
    case True{}:
      +changed = Bool.not(String.eq(current_namespace(state), namespace))
      snapshot_current(changed || Nat.is_le(Legacy.sequence(legacy(state)), sequence), changed, namespace, sequence, program, state)

def snapshot_scope(owned: Bool, +namespace: String, sequence: Nat, program: M.World(), +state: State) -> Decision:
  match owned:
    # DEFENSE: A refresh started before a service restart may return after the browser has accepted a different data namespace.
    case False{}: Decision{state, Nil{}}
    case True{}: snapshot_namespace(Live.valid_namespace(namespace), namespace, sequence, program, state)

def snapshot_environment(expected_namespace: String, namespace: String, sequence: Nat, program: M.World(), +state: State) -> Decision:
  snapshot_scope(String.eq(expected_namespace, current_namespace(state)), namespace, sequence, program, state)

def transport_current(owned: Bool, namespace: String, sequence: Nat, fresh: Bool, +allowed: Bool, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      accept(True{}, Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{namespace, sequence, fresh, allowed}}}}}, legacy(state)), invalidate_if(Bool.not(allowed), state))

def transport_environment(+namespace: String, +sequence: Nat, fresh: Bool, allowed: Bool, +state: State) -> Decision:
  transport_current(String.eq(namespace, current_namespace(state)) && Nat.is_eq(sequence, Legacy.sequence(legacy(state))), namespace, sequence, fresh, allowed && source_allowed(state), state)

def authentication_owned(+namespace: String, ticket: Nat, +state: State) -> Bool:
  String.eq(namespace, current_namespace(state)) && Services.expected_access(service_access(state), ticket)

def network_failure_owned(+namespace: String, sequence: Nat,+connection: Nat,  authentication: Maybe<&2, Nat>, +state: State) -> Bool:
  match authentication:
    case None{}: String.eq(namespace, current_namespace(state)) && (Nat.is_eq(sequence, Legacy.sequence(legacy(state))) && Services.live_connection(service_access(state), connection))
    case Some{ticket}: authentication_owned(namespace, ticket, state)

def network_failure_sequence(authentication: Maybe<&2, Nat>, sequence: Nat, state: State) -> Nat:
  match authentication:
    case None{}: sequence
    case Some{ticket}: Legacy.sequence(legacy(state))

def network_failure_input(authentication: Maybe<&2, Nat>, +connection: Nat, reason: String) -> Product.Input:
  match authentication:
    case None{}: Product.Disconnected{connection, reason}
    case Some{ticket}: Product.Authenticated{ticket, Fail{reason}}

def network_failure_after(authentication: Maybe<&2, Nat>, +connection: Nat, reason: String, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{next, first} = value
  synchronized_result(Legacy.native(Web.PlatformInput{Platform.ProductInput{network_failure_input(authentication, connection, reason)}}, next), first)

def network_failure_result(namespace: String, sequence: Nat,+connection: Nat,  reason: String, revoked: Bool, authentication: Maybe<&2, Nat>, +state: State) -> Legacy.Decision:
  network_failure_after(authentication, connection, reason, Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{namespace, sequence, False{}, Bool.not(revoked) && source_allowed(state)}}}}}, legacy(state)))

def network_failed_current(owned: Bool, namespace: String, sequence: Nat,+connection: Nat,  reason: String, +revoked: Bool, +authentication: Maybe<&2, Nat>, +state: State) -> Decision:
  match owned:
    # DEFENSE: An earlier HTTP/SSE request can fail after a replacement connection or namespace has already taken ownership.
    case False{}: Decision{state, Nil{}}
    case True{}:
      accept(True{}, network_failure_result(namespace, network_failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state), invalidate_if(revoked, state))

def network_failed(+namespace: String, +sequence: Nat,+connection: Nat,  reason: String, revoked: Bool, +authentication: Maybe<&2, Nat>, +state: State) -> Decision:
  network_failed_current(network_failure_owned(namespace, sequence, connection, authentication, state), namespace, sequence, connection, reason, revoked, authentication, state)

def authenticated_result(ticket: Nat, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{next, first} = value
  synchronized_result(Legacy.native(Web.PlatformInput{Platform.ProductInput{Product.Authenticated{ticket, Done{Unit{}}}}}, next), first)

# DEFENSE: Authentication refresh can return a snapshot older than an independently completed command in the same namespace.
def authenticated_snapshot_current(stale: Bool, +changed: Bool, namespace: String, sequence: Nat, +program: M.World(), ticket: Nat, +state: State) -> Decision:
  match stale:
    case True{}: accept(True{}, authenticated_result(ticket, Legacy.Decision{legacy(state), Nil{}}), state)
    case False{}:
      accept(True{}, authenticated_result(ticket, snapshot_result(changed, namespace, sequence, program, state)), invalidate_if(changed || view_removed(program, state), state))

def authenticated_snapshot_valid(valid: Bool, +namespace: String, +sequence: Nat, program: M.World(), +ticket: Nat, +state: State) -> Decision:
  match valid:
    # DEFENSE: Authentication snapshots must carry the current service data-namespace format before sources are authorized.
    case False{}: network_failed(current_namespace(state), Legacy.sequence(legacy(state)), ticket, "Invalid service data namespace", True{}, Some{ticket}, state)
    case True{}:
      +changed = Bool.not(String.eq(current_namespace(state), namespace))
      authenticated_snapshot_current(Bool.not(changed) && Nat.is_lt(sequence, Legacy.sequence(legacy(state))), changed, namespace, sequence, program, ticket, state)

def authenticated_snapshot_owned(owned: Bool, +namespace: String, sequence: Nat, program: M.World(), ticket: Nat, +state: State) -> Decision:
  match owned:
    # DEFENSE: A sign-in request can finish after its authentication ticket or data namespace has been superseded.
    case False{}: Decision{state, Nil{}}
    case True{}: authenticated_snapshot_valid(Live.valid_namespace(namespace), namespace, sequence, program, ticket, state)

def authenticated_snapshot(expected_namespace: String, namespace: String, sequence: Nat, program: M.World(), +ticket: Nat, +state: State) -> Decision:
  authenticated_snapshot_owned(authentication_owned(expected_namespace, ticket, state), namespace, sequence, program, ticket, state)

def completed_current(changed: Bool, ticket: Nat, namespace: String, +sequence: Nat, +program: M.World(), reply: J.Json, +state: State) -> Decision:
  match changed:
    # DEFENSE: A command accepted by the old service can return after the browser has switched to a new data namespace.
    case True{}: Decision{state, Nil{}}
    case False{}: accept(True{}, Legacy.step(Legacy.Completed{ticket, sequence, program, reply}, legacy(state)),
      invalidate_if(Nat.is_le(Legacy.sequence(legacy(state)), sequence) && view_removed(program, state), state))

def completed_environment(ticket: Nat, +namespace: String, sequence: Nat, program: M.World(), reply: J.Json, +state: State) -> Decision:
  completed_current(Bool.not(String.eq(current_namespace(state), namespace)), ticket, namespace, sequence, program, reply, state)

def command_rejected(+ticket: Nat, +reason: String, +state: State) -> Decision: accept(True{}, Legacy.command_rejected(ticket, reason, legacy(state)), state)

def external_action(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, IM.ActionBinding{kind, enabled, pending}, children}}, nested}}:
      model_external_kind(kind)
    case _: False{}

def interactive_native_owned(event: Maybe<&2, IM.EventIdentity>, basis: NativeFields.Basis, key: String) -> Bool:
  match event:
    case None{}: True{}
    case Some{identity}: NativeFields.control_owned(basis, key)

def activation_owned(+key: String, +state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: matching_interactive_nodes(None{}, InterfaceView.find_node(InterfaceView.active_nodes(current_surface(state)), key))
    case Some{Published{world, semantic, scope, basis, frame}}:
      interactive_native_owned(interactive_event(InterfaceView.find_node(InterfaceView.active_nodes(current_surface(state)), key)), basis, key) &&
        matching_interactive_nodes(InterfaceView.find_node(InterfaceView.active_nodes(semantic), key), InterfaceView.find_node(InterfaceView.active_nodes(current_surface(state)), key))

def submit_action(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, IM.ActionBinding{IM.SubmitAction{}, enabled, pending}, children}}, nested}}: True{}
    case _: False{}

def service_connected(state: State) -> Bool:
  Services.connected(Services.access(InteractionState.services(Platform.core(Web.application(Legacy.web(legacy(state)))))))

def commit_refresh_needed_at(sequence: Maybe<&2, Nat>, +notice: J.Json, +state: State) -> Bool:
  match sequence:
    # DEFENSE: A dequeued watch commit whose sequence is missing or outside the immediate Nat protocol cannot establish that the current snapshot covers it.
    case None{}: True{}
    case Some{received}:
      Bool.not(String.eq(J.text(J.get(notice, "type")), "commit") &&
        Live.valid_namespace(current_namespace(state)) &&
        String.eq(J.text(J.get(notice, "namespace")), current_namespace(state)) &&
        source_fresh(state) && source_allowed(state) && service_connected(state) &&
        Nat.is_le(received, Legacy.sequence(legacy(state))))

def commit_refresh_needed(+notice: J.Json, state: State) -> Bool:
  commit_refresh_needed_at(J.natural(J.get(notice, "sequence")), notice, state)

def activate_ready(blocked: Bool, +key: String, +state: State) -> Decision:
  match blocked:
    # DEFENSE: A native click can arrive during semantic publication lag, after its owner changes, or while submission is disconnected.
    case True{}: Decision{state, Nil{}}
    case False{}: accept(True{}, Legacy.activate(key, legacy(state)), state)

def activate_reserved(reserved: Bool, +key: String, +state: State) -> Decision:
  match reserved:
    case True{}: accept(True{}, Legacy.activate(key, legacy(state)), state)
    case False{}:
      activate_ready(Bool.not(activation_owned(key, state)) ||
        (semantic_pending(state) && external_action(InterfaceView.find_node(InterfaceView.active_nodes(current_surface(state)), key))) ||
        (Bool.not(service_connected(state)) && submit_action(InterfaceView.find_node(InterfaceView.active_nodes(current_surface(state)), key))), key, state)

def activate(+key: String, +state: State) -> Decision:
  activate_reserved(String.eq(key, "@browser/retry"), key, state)

type TextEditCandidate is Data:
  TextEditCandidate{key: String, text: String, state: State}

def edit_text_predicate(candidate: TextEditCandidate) -> Bool:
  TextEditCandidate{+key, +text, +state} = candidate
  field_owned(key, state)

def edit_text_category() -> TextEditCandidate -> Type: Categories.holds(TextEditCandidate, edit_text_predicate)

def edit_text_owned(member: Categories.Membership<TextEditCandidate, edit_text_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  TextEditCandidate{+key, +text, +state} = candidate
  accept(True{}, Legacy.edit_text(key, text, legacy(state)), state)

def edit_text_admitted(admission: Maybe<&1, Categories.Membership<TextEditCandidate, edit_text_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: A queued text event can outlive its current field owner or mount occurrence after a publication.
    case None{}: Decision{state, Nil{}}
    case Some{member}: edit_text_owned(member)

def edit_text(+key: String, +text: String, +state: State) -> Decision:
  edit_text_admitted(Categories.admit(TextEditCandidate, edit_text_predicate, TextEditCandidate{key, text, state}), state)

type StructuredTextEditCandidate is Data:
  StructuredTextEditCandidate{key: String, text: String, parsed: Maybe<&2, J.Json>, state: State}

def structured_text_owned(+key: String, +state: State) -> Bool:
  field_owned(key, state) && Legacy.structured_text_source(Legacy.found_node(key, legacy(state)))

def edit_structured_text_predicate(candidate: StructuredTextEditCandidate) -> Bool:
  StructuredTextEditCandidate{+key, text, parsed, +state} = candidate
  structured_text_owned(key, state)

def edit_structured_text_category() -> StructuredTextEditCandidate -> Type: Categories.holds(StructuredTextEditCandidate, edit_structured_text_predicate)

def edit_structured_text_owned(member: Categories.Membership<StructuredTextEditCandidate, edit_structured_text_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  StructuredTextEditCandidate{+key, text, parsed, +state} = candidate
  accept(True{}, Legacy.edit_structured_text(key, text, parsed, legacy(state)), state)

def edit_structured_text_admitted(admission: Maybe<&1, Categories.Membership<StructuredTextEditCandidate, edit_structured_text_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: A queued structured-text event may belong to a superseded field mount or a field no longer accepting structured text.
    case None{}: Decision{state, Nil{}}
    case Some{member}: edit_structured_text_owned(member)

def edit_structured_text(+key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: State) -> Decision:
  edit_structured_text_admitted(Categories.admit(StructuredTextEditCandidate, edit_structured_text_predicate, StructuredTextEditCandidate{key, text, parsed, state}), state)

type TextConfirmationCandidate is Data:
  TextConfirmationCandidate{key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, state: State}

def confirm_text_predicate(candidate: TextConfirmationCandidate) -> Bool:
  TextConfirmationCandidate{+key, +keyboard, +composing, +control, +alt, +shift, +meta, +state} = candidate
  field_owned(key, state)

def confirm_text_category() -> TextConfirmationCandidate -> Type: Categories.holds(TextConfirmationCandidate, confirm_text_predicate)

def confirm_text_owned(member: Categories.Membership<TextConfirmationCandidate, confirm_text_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  TextConfirmationCandidate{+key, +keyboard, +composing, +control, +alt, +shift, +meta, +state} = candidate
  accept(True{}, Legacy.confirm_text(key, keyboard, composing, control, alt, shift, meta, legacy(state)), state)

def confirm_text_admitted(admission: Maybe<&1, Categories.Membership<TextConfirmationCandidate, confirm_text_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: An Enter/composition confirmation can be delivered after its field owner or mount occurrence has changed.
    case None{}: Decision{state, Nil{}}
    case Some{member}: confirm_text_owned(member)

def confirm_text(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: State) -> Decision:
  confirm_text_admitted(Categories.admit(TextConfirmationCandidate, confirm_text_predicate, TextConfirmationCandidate{key, keyboard, composing, control, alt, shift, meta, state}), state)

type ToggleEditCandidate is Data:
  ToggleEditCandidate{key: String, enabled: Bool, state: State}

def edit_toggle_predicate(candidate: ToggleEditCandidate) -> Bool:
  ToggleEditCandidate{+key, +enabled, +state} = candidate
  field_owned(key, state)

def edit_toggle_category() -> ToggleEditCandidate -> Type: Categories.holds(ToggleEditCandidate, edit_toggle_predicate)

def edit_toggle_owned(member: Categories.Membership<ToggleEditCandidate, edit_toggle_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  ToggleEditCandidate{+key, +enabled, +state} = candidate
  accept(True{}, Legacy.edit_toggle(key, enabled, legacy(state)), state)

def edit_toggle_admitted(admission: Maybe<&1, Categories.Membership<ToggleEditCandidate, edit_toggle_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: A native checkbox event can arrive after its field owner or mount occurrence is replaced.
    case None{}: Decision{state, Nil{}}
    case Some{member}: edit_toggle_owned(member)

def edit_toggle(+key: String, +enabled: Bool, +state: State) -> Decision:
  edit_toggle_admitted(Categories.admit(ToggleEditCandidate, edit_toggle_predicate, ToggleEditCandidate{key, enabled, state}), state)

type AttachmentCandidate is Data:
  AttachmentCandidate{key: String, file: Services.SelectedFile, state: State}

def attach_predicate(candidate: AttachmentCandidate) -> Bool:
  AttachmentCandidate{+key, +file, +state} = candidate
  field_owned(key, state)

def attach_category() -> AttachmentCandidate -> Type: Categories.holds(AttachmentCandidate, attach_predicate)

def attach_owned(member: Categories.Membership<AttachmentCandidate, attach_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  AttachmentCandidate{+key, +file, +state} = candidate
  accept(True{}, Legacy.attach(key, file, legacy(state)), state)

def attach_admitted(admission: Maybe<&1, Categories.Membership<AttachmentCandidate, attach_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: The file picker can complete after its originating field owner or mount occurrence has been replaced.
    case None{}: Decision{state, Nil{}}
    case Some{member}: attach_owned(member)

def attach(+key: String, +file: Services.SelectedFile, +state: State) -> Decision:
  attach_admitted(Categories.admit(AttachmentCandidate, attach_predicate, AttachmentCandidate{key, file, state}), state)

def place(+key: String, +target: String, +state: State) -> Decision: accept(True{}, Legacy.place(key, target, legacy(state)), state)

def connect(+state: State) -> Decision: accept(True{}, Legacy.connect(legacy(state)), state)

def workspace_git_completed(+ticket: Nat, +available: Bool, +state: State) -> Decision: accept(True{}, Legacy.workspace_git_completed(ticket, available, legacy(state)), state)

def directories_completed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directories_completed(ticket, ok, body, legacy(state)), state)

def code_same_source(left: Code.Source, right: Code.Source) -> Bool:
  String.eq(Code.source_key(left), Code.source_key(right))

def code_declared_owned(declared: Maybe<&2, Code.Source>, value: String, source: Code.Source, source_value: String) -> Bool:
  match declared:
    case None{}: False{}
    case Some{owner}: code_same_source(owner, source) && SafeText.string_equal(value, source_value)

def code_content_owned(content: Source.RichContent, +identity: Code.Identity, +source_value: String) -> Bool:
  Source.RichContent{declared, value, policy} = content
  Code.Identity{source, ordinal} = identity
  code_declared_owned(declared, value, source, source_value)

def code_node_owned(+node: Source.Node, +identity: Code.Identity, +source_value: String) -> Bool:
  match node:
    case Source.RichText{key, style, content, attachments, native_owner}: code_content_owned(content, identity, source_value)
    case _: False{}

def code_children_owned(nodes: +List<Source.Node>, +identity: Code.Identity, +source_value: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}:
      code_content_owned(content, identity, source_value) || code_children_owned(attachments, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.Text{key, value, font, wrapping}, rest}:
      code_children_owned(rest, identity, source_value)
    case Con{Source.Glyph{key, drawing, style}, rest}:
      code_children_owned(rest, identity, source_value)
    case Con{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, rest}:
      code_children_owned(rest, identity, source_value)

def code_source_owned(+node: Source.Node, +identity: Code.Identity, +source_value: String) -> Bool:
  nodes: +List<Source.Node> = Con{node, Nil{}}
  code_children_owned(nodes, identity, source_value)

def code_observations_owned(observations: +List<CodeObservation.Observation>, +source: Source.Node) -> Bool:
  match observations:
    case Nil{}: True{}
    case Con{CodeObservation.Observation{identity, text, source_value}, rest}:
      code_source_owned(source, identity, source_value) && code_observations_owned(rest, source)

def code_batch_owned(observations: +List<CodeObservation.Observation>, source: Source.Node) -> Bool:
  match observations:
    case Nil{}: False{}
    case Con{observation, rest}: code_observations_owned(Con{observation, rest}, source)

def known_code_observations(observations: +List<CodeObservation.Observation>, +session: E.Session) -> Bool:
  match observations:
    case Nil{}: True{}
    case Con{CodeObservation.Observation{identity, text, source_value}, rest}:
      E.code_source_known(identity, session) && known_code_observations(rest, session)

def code_batch_qualified(+generation: Nat, +observations: +List<CodeObservation.Observation>, state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: False{}
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      code_batch_owned(observations, source) && known_code_observations(observations,
        E.session(InteractionState.application(Platform.core(Web.application(Legacy.web(legacy))))))

# NOTE: Qualify against one published snapshot before any source update can publish a new generation.

def code_sources_fold(observations: +List<CodeObservation.Observation>, decision: Legacy.Decision) -> Legacy.Decision:
  match observations:
    case Nil{}: decision
    case Con{CodeObservation.Observation{Code.Identity{source, ordinal}, text, source_value}, rest}:
      Legacy.Decision{state, effects} = decision
      code_sources_fold(rest, Legacy.append_decision(effects, Legacy.code_source(source, ordinal, text, state)))

type CodeSourcesCandidate is Data:
  CodeSourcesCandidate{generation: Nat, observations: +List<CodeObservation.Observation>, state: State}

def code_sources_predicate(candidate: CodeSourcesCandidate) -> Bool:
  CodeSourcesCandidate{+generation, +observations, +state} = candidate
  code_batch_qualified(generation, observations, state)

def code_sources_category() -> CodeSourcesCandidate -> Type: Categories.holds(CodeSourcesCandidate, code_sources_predicate)

def code_sources_if_qualified(member: Categories.Membership<CodeSourcesCandidate, code_sources_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  CodeSourcesCandidate{+generation, +observations, +state} = candidate
  accept(True{}, code_sources_fold(observations, Legacy.Decision{legacy(state), Nil{}}), state)

def code_sources_admitted(admission: Maybe<&1, Categories.Membership<CodeSourcesCandidate, code_sources_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: Paced Markdown parsing can report code after the published source text or source identity has been replaced.
    case None{}: Decision{state, Nil{}}
    case Some{member}: code_sources_if_qualified(member)

def code_sources(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: State) -> Decision:
  code_sources_admitted(Categories.admit(CodeSourcesCandidate, code_sources_predicate, CodeSourcesCandidate{generation, observations, state}), state)

def editor_event(+key: String, +event: Editor.EditorEvent, +state: State) -> Decision: accept(True{}, Legacy.editor_event(key, event, legacy(state)), state)

def reading(+task: Nat, +generation: Nat, +event: Reading.ReadingEvent, +state: State) -> Decision: accept(False{}, Legacy.reading(task, generation, event, legacy(state)), state)

def stream_notice_owned(+body: J.Json, +state: State) -> Bool:
  Bool.not(String.eq(current_namespace(state), "")) && String.eq(J.text(J.get(body, "namespace")), current_namespace(state))

def streams_current(owned: Bool, body: J.Json, +state: State) -> Decision:
  match owned:
    # DEFENSE: Buffered SSE observations from an old service namespace must not update the current conversation.
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, Legacy.streams(body, legacy(state)), state)

def streams(+body: J.Json, +state: State) -> Decision:
  streams_current(stream_notice_owned(body, state), body, state)

def directory_listed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directory_listed(ticket, ok, body, legacy(state)), state)

def measurements(+observation: F.Observation, +state: State) -> Decision:
  accept(True{}, Legacy.measurements(observation, legacy(state)), state)

type ForwardFrameCandidate is Data:
  ForwardFrameCandidate{state: State, frame: Rendered.Frame}

def forward_frame_predicate(candidate: ForwardFrameCandidate) -> Bool:
  ForwardFrameCandidate{state, frame} = candidate
  display_ready(state)

def forward_frame_category() -> ForwardFrameCandidate -> Type: Categories.holds(ForwardFrameCandidate, forward_frame_predicate)

def frame_forward_calculation(+state: State, +frame: Rendered.Frame) -> Decision:
  State{+stored, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: Decision{State{stored, serial, anchors, lifecycle, None{}, attention, updates}, Nil{}}
    case Some{+value}:
      Published{+world, semantic, scope, basis, old} = value
      accept(False{}, Legacy.observe_frame_with(semantic_generation(stored), semantic, frame, stored, SourceFrame.expectations(world, frame)),
        State{stored, serial, anchors, lifecycle, Some{value}, attention, updates})

def frame_forward_ready(member: Categories.Membership<ForwardFrameCandidate, forward_frame_category()>) -> Decision:
  Categories.Membership{ForwardFrameCandidate{state, frame}, evidence} = member
  frame_forward_calculation(state, frame)

def frame_forward_admitted(admission: Maybe<&1, Categories.Membership<ForwardFrameCandidate, forward_frame_category()>>, state: State) -> Decision:
  match admission:
    case None{}: Decision{state, Nil{}}
    case Some{member}: frame_forward_ready(member)

def frame_forward(+state: State, +frame: Rendered.Frame) -> Decision:
  frame_forward_admitted(Categories.admit(ForwardFrameCandidate, forward_frame_predicate, ForwardFrameCandidate{state, frame}), state)

def frame_capture(+frame: Rendered.Frame, state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: State{legacy, serial, anchors, lifecycle, None{}, attention, updates}
    case Some{Published{world, semantic, scope, basis, old}}:
      State{legacy, serial, anchors, lifecycle, Some{Published{world, semantic, scope, basis, Some{frame}}}, attention, updates}

def frame_owned(+received: Nat, +state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: False{}
    case Some{published}: Nat.is_eq(received, displayed_generation(state))

def utility_frame_calculation(frame: Rendered.Frame, state: State) -> Decision:
  Decision{frame_capture(frame, state), Nil{}}

def utility_frame_rejection(state: State) -> Decision:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  Decision{State{legacy, serial, anchors, UtilityRejected{"Frontend utility frame does not match its admitted source"}, None{}, attention, updates}, Nil{}}

def frame_violations_empty(violations: +List<Rendered.Violation>) -> Bool:
  match violations:
    case Nil{}: True{}
    case Con{first, rest}: False{}

type UtilityFrameCandidate is Data:
  UtilityFrameCandidate{world: Content.AllocatedWorld, frame: Rendered.Frame, state: State}

def utility_frame_predicate(candidate: UtilityFrameCandidate) -> Bool:
  UtilityFrameCandidate{world, frame, state} = candidate
  frame_violations_empty(SourceFrame.check(world, frame))

def utility_frame_category() -> UtilityFrameCandidate -> Type: Categories.holds(UtilityFrameCandidate, utility_frame_predicate)

def utility_frame_owned(member: Categories.Membership<UtilityFrameCandidate, utility_frame_category()>) -> Decision:
  Categories.Membership{UtilityFrameCandidate{world, frame, state}, evidence} = member
  utility_frame_calculation(frame, state)

def utility_frame_admitted(admission: Maybe<&1, Categories.Membership<UtilityFrameCandidate, utility_frame_category()>>, state: State) -> Decision:
  match admission:
    case Some{member}: utility_frame_owned(member)
    # DEFENSE: The physical frame contract requires native focus, exposure and geometry to match the admitted recovery source.
    case None{}: utility_frame_rejection(state)

def utility_frame_result(+world: Content.AllocatedWorld, +frame: Rendered.Frame, +state: State) -> Decision:
  utility_frame_admitted(Categories.admit(UtilityFrameCandidate, utility_frame_predicate, UtilityFrameCandidate{world, frame, state}), state)

def correlated_frame_owned(utility: Bool, +frame: Rendered.Frame, +state: State) -> Decision:
  match utility:
    case False{}: frame_forward(frame_capture(frame, state), frame)
    case True{}:
      State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
      match displayed:
        case None{}: Decision{state, Nil{}}
        case Some{Published{world, semantic, scope, basis, old}}:
          utility_frame_result(world, frame, state)

def correlated_frame(+frame: Rendered.Frame, +state: State) -> Decision:
  correlated_frame_owned(utility_owned(state), frame, state)

type FrameCandidate is Data:
  FrameCandidate{received: Nat, frame: Rendered.Frame, state: State}

def receive_frame_predicate(candidate: FrameCandidate) -> Bool:
  FrameCandidate{+received, +frame, +state} = candidate
  frame_owned(received, state)

def receive_frame_category() -> FrameCandidate -> Type: Categories.holds(FrameCandidate, receive_frame_predicate)

def received_frame(member: Categories.Membership<FrameCandidate, receive_frame_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  FrameCandidate{+received, +frame, +state} = candidate
  correlated_frame(frame, state)

def receive_frame_admitted(admission: Maybe<&1, Categories.Membership<FrameCandidate, receive_frame_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: An animation-frame callback can deliver geometry after a newer display generation has been published.
    case None{}: Decision{state, Nil{}}
    case Some{member}: received_frame(member)

def receive_frame(+received: Nat, +frame: Rendered.Frame, +state: State) -> Decision:
  receive_frame_admitted(Categories.admit(FrameCandidate, receive_frame_predicate, FrameCandidate{received, frame, state}), state)

def rich_delegates(node: Source.Node, +owner: String) -> Bool:
  match node:
    case Source.RichText{key, style, content, attachments, Some{delegated}}: SafeText.string_equal(delegated, owner)
    case _: False{}

def source_children_delegate(nodes: +List<Source.Node>, +owner: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{node, rest}:
      match node:
        case Source.NativeAttachment{key, target, attributes, style, +children}:
          (rich_delegates(Source.NativeAttachment{key, target, attributes, style, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Box{key, tag, style, attributes, +children}:
          (rich_delegates(Source.Box{key, tag, style, attributes, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, +children}:
          (rich_delegates(Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Text{key, value, font, wrapping}:
          (rich_delegates(Source.Text{key, value, font, wrapping}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.Glyph{key, drawing, style}:
          (rich_delegates(Source.Glyph{key, drawing, style}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
          (rich_delegates(Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.RichText{key, style, content, +attachments, native_owner}:
          (rich_delegates(Source.RichText{key, style, content, attachments, native_owner}, owner) || source_children_delegate(attachments, owner)) || source_children_delegate(rest, owner)

def source_delegates(+node: Source.Node, +owner: String) -> Bool:
  source_children_delegate([node], owner)

def native_pair(entries: +List<Rendered.NativeFocus>, +owner: String, +identity: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{Rendered.NativeFocus{key, parent}, rest}: (SafeText.string_equal(key, identity) && SafeText.string_equal(parent, owner)) || native_pair(rest, owner, identity)

def native_frame_owned(frame: Maybe<&2, Rendered.Frame>, +semantic: SurfaceTypes.Surface, +owner: String, +identity: String) -> Bool:
  match frame:
    case None{}: False{}
    case Some{Rendered.Frame{viewport, +elements, focused, order, +native_focus}}:
      Rendered.native_valid(native_focus, InterfaceView.active_nodes(semantic), elements) && native_pair(native_focus, owner, identity)

def native_observation_owned(+generation: Nat, +owner: String, +identity: String, state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: False{}
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, +semantic, scope, basis, frame}}:
      Nat.is_eq(generation, published) && source_delegates(source, owner) &&
      Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && native_frame_owned(frame, semantic, owner, identity)

type NativeObservationCandidate is Data:
  NativeObservationCandidate{generation: Nat, owner: String, identity: String, state: State}

def native_focus_observed_predicate(candidate: NativeObservationCandidate) -> Bool:
  NativeObservationCandidate{+generation, +owner, +identity, +state} = candidate
  native_observation_owned(generation, owner, identity, state)

def native_focus_observed_category() -> NativeObservationCandidate -> Type: Categories.holds(NativeObservationCandidate, native_focus_observed_predicate)

def native_focus_if_owned(member: Categories.Membership<NativeObservationCandidate, native_focus_observed_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  NativeObservationCandidate{+generation, +owner, +identity, +state} = candidate
  accept(False{}, Legacy.native(Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}, legacy(state)), state)

def native_focus_observed_admitted(admission: Maybe<&1, Categories.Membership<NativeObservationCandidate, native_focus_observed_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: Native link focus can be delivered after its Markdown owner, link identity or display generation has changed.
    case None{}: Decision{state, Nil{}}
    case Some{member}: native_focus_if_owned(member)

def native_focus_observed(+generation: Nat, +owner: String, +identity: String, +state: State) -> Decision:
  native_focus_observed_admitted(Categories.admit(NativeObservationCandidate, native_focus_observed_predicate, NativeObservationCandidate{generation, owner, identity, state}), state)

type AuxiliaryFocusCandidate is Data:
  AuxiliaryFocusCandidate{input: Web.Input, state: State}

def auxiliary_focus_predicate(candidate: AuxiliaryFocusCandidate) -> Bool:
  AuxiliaryFocusCandidate{input, state} = candidate
  Bool.not(auxiliary_owned(state))

def auxiliary_focus_category() -> AuxiliaryFocusCandidate -> Type: Categories.holds(AuxiliaryFocusCandidate, auxiliary_focus_predicate)

def auxiliary_focus_owned(member: Categories.Membership<AuxiliaryFocusCandidate, auxiliary_focus_category()>) -> Decision:
  Categories.Membership{AuxiliaryFocusCandidate{input, +state}, evidence} = member
  accept(False{}, Legacy.native(input, legacy(state)), state)

def auxiliary_focus_admitted(admission: Maybe<&1, Categories.Membership<AuxiliaryFocusCandidate, auxiliary_focus_category()>>, state: State) -> Decision:
  match admission:
    case Some{member}: auxiliary_focus_owned(member)
    # DEFENSE: Focus feedback from the normal document cannot alter the independently owned recovery/utility display.
    case None{}: Decision{state, Nil{}}

def auxiliary_focus(+input: Web.Input, +state: State) -> Decision:
  auxiliary_focus_admitted(Categories.admit(AuxiliaryFocusCandidate, auxiliary_focus_predicate, AuxiliaryFocusCandidate{input, state}), state)


def outside_result(+result: Legacy.OutsideDecision, +state: State) -> OutsideDecision:
  Legacy.OutsideDecision{handled, decision} = result
  OutsideDecision{handled, accept(handled, decision, state)}

type OutsideCandidate is Data:
  OutsideCandidate{identity: String, state: State}

def outside_predicate(candidate: OutsideCandidate) -> Bool:
  OutsideCandidate{identity, state} = candidate
  Bool.not(auxiliary_owned(state))

def outside_category() -> OutsideCandidate -> Type: Categories.holds(OutsideCandidate, outside_predicate)

def outside_owned(member: Categories.Membership<OutsideCandidate, outside_category()>) -> OutsideDecision:
  Categories.Membership{OutsideCandidate{identity, +state}, evidence} = member
  outside_result(legacy_outside(identity, legacy(state)), state)

def outside_admitted(admission: Maybe<&1, Categories.Membership<OutsideCandidate, outside_category()>>, state: State) -> OutsideDecision:
  match admission:
    case Some{member}: outside_owned(member)
    # DEFENSE: A native outside-click for the normal document cannot dismiss an independently owned recovery/utility display.
    case None{}: OutsideDecision{False{}, Decision{state, Nil{}}}

def outside_event(+identity: String, +state: State) -> OutsideDecision:
  outside_admitted(Categories.admit(OutsideCandidate, outside_predicate, OutsideCandidate{identity, state}), state)

def observed_eligible(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && (visible || scroll)

def published_order_predicate(+basis: NativeFields.Basis, +elements: +List<Rendered.Element>, +semantic: SurfaceTypes.Surface, +native_focus: +List<Rendered.NativeFocus>, +key: String) -> Bool:
  (NativeFields.control_owned(basis, key) || Rendered.native_owned(native_focus, InterfaceView.active_nodes(semantic), elements, key)) && observed_eligible(Rendered.find_element(elements, key))

def published_order_category(+basis: NativeFields.Basis, +elements: +List<Rendered.Element>, +semantic: SurfaceTypes.Surface, +native_focus: +List<Rendered.NativeFocus>) -> String -> Type:
  Categories.holds(String, key => published_order_predicate(basis, elements, semantic, native_focus, key))

def published_order_eligible(-basis: NativeFields.Basis, -elements: +List<Rendered.Element>, -semantic: SurfaceTypes.Surface, -native_focus: +List<Rendered.NativeFocus>, member: Categories.Membership<String, published_order_category(basis, elements, semantic, native_focus)>, tail: +List<String>) -> +List<String>:
  Categories.Membership{key, evidence} = member
  key <> tail

def published_order_admitted(-basis: NativeFields.Basis, -elements: +List<Rendered.Element>, -semantic: SurfaceTypes.Surface, -native_focus: +List<Rendered.NativeFocus>, admission: Maybe<&1, Categories.Membership<String, published_order_category(basis, elements, semantic, native_focus)>>, tail: +List<String>) -> +List<String>:
  match admission:
    case None{}: tail
    case Some{member}: published_order_eligible(basis, elements, semantic, native_focus, member, tail)

def published_order(order: +List<String>, +basis: NativeFields.Basis, +elements: +List<Rendered.Element>, +semantic: SurfaceTypes.Surface, +native_focus: +List<Rendered.NativeFocus>) -> +List<String>:
  match order:
    case Nil{}: Nil{}
    case Con{+key, rest}:
      published_order_admitted(basis, elements, semantic, native_focus, Categories.admit(String, candidate => published_order_predicate(basis, elements, semantic, native_focus, candidate), key), published_order(rest, basis, elements, semantic, native_focus))

def native_target_match(hit: Bool, owner: String, identity: String, fallback: Focus.Target) -> Focus.Target:
  match hit:
    case True{}: Focus.Content{owner, identity}
    case False{}: fallback

def native_target(entries: +List<Rendered.NativeFocus>, +key: String) -> Focus.Target:
  match entries:
    case Nil{}: Focus.Product{key}
    case Con{Rendered.NativeFocus{+identity, owner}, rest}:
      native_target_match(SafeText.string_equal(identity, key), owner, identity, native_target(rest, key))

def native_focus_predicate(semantic: SurfaceTypes.Surface, elements: +List<Rendered.Element>, entries: +List<Rendered.NativeFocus>) -> Bool:
  Rendered.native_valid(entries, InterfaceView.active_nodes(semantic), elements)

def native_focus_category(semantic: SurfaceTypes.Surface, elements: +List<Rendered.Element>) -> +List<Rendered.NativeFocus> -> Type:
  Categories.holds(+List<Rendered.NativeFocus>, entries => native_focus_predicate(semantic, elements, entries))

def admitted_native_focus(-semantic: SurfaceTypes.Surface, -elements: +List<Rendered.Element>, member: Categories.Membership<+List<Rendered.NativeFocus>, native_focus_category(semantic, elements)>) -> +List<Rendered.NativeFocus>:
  Categories.Membership{entries, evidence} = member
  entries

def native_focus_admitted(-semantic: SurfaceTypes.Surface, -elements: +List<Rendered.Element>, admission: Maybe<&1, Categories.Membership<+List<Rendered.NativeFocus>, native_focus_category(semantic, elements)>>) -> +List<Rendered.NativeFocus>:
  match admission:
    case None{}: Nil{}
    case Some{member}: admitted_native_focus(semantic, elements, member)

def published_target(found: Maybe<&2, String>, native_focus: +List<Rendered.NativeFocus>) -> Maybe<&2, Focus.Target>:
  match found:
    case None{}: None{}
    case Some{key}: Some{native_target(native_focus, key)}

def published_cycle(scope: Focus.Scope, basis: NativeFields.Basis, +semantic: SurfaceTypes.Surface, frame: Maybe<&2, Rendered.Frame>, reverse: Bool) -> Maybe<&2, Focus.Target>:
  match frame:
    case None{}: None{}
    case Some{Rendered.Frame{viewport, +elements, focused, +order, +native_focus}}:
      published_target(Focus.cycle(scope, published_order(order, basis, elements, semantic, native_focus), focused, reverse),
        native_focus_admitted(semantic, elements, Categories.admit(+List<Rendered.NativeFocus>, entries => native_focus_predicate(semantic, elements, entries), native_focus)))

def published_escape(found: Maybe<&2, Legacy.DismissTarget>, +state: State) -> KeyResult:
  match found:
    case None{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Some{Legacy.DismissTarget{identity, input, outside, +escape}}:
      KeyResult{escape, accept(escape, Legacy.dismiss_permitted(escape && Legacy.outside_layer_owned(identity, Legacy.current_layer_key(legacy(state))), input, legacy(state)), state)}

def published_key_kind(tab: Bool, escape: Bool, shift: Bool, scope: Focus.Scope, basis: NativeFields.Basis, semantic: SurfaceTypes.Surface, frame: Maybe<&2, Rendered.Frame>, +state: State) -> KeyResult:
  match tab escape:
    case True{} _: KeyResult{True{}, accept(False{}, Legacy.cycle_target_found(published_cycle(scope, basis, semantic, frame, shift), legacy(state)), state)}
    case False{} True{}: published_escape(Legacy.dismiss_target(InterfaceView.active_nodes(semantic)), state)
    case False{} False{}: KeyResult{False{}, Decision{state, Nil{}}}

def published_key(+key: String, shift: Bool, +scope: Focus.Scope, basis: NativeFields.Basis, semantic: SurfaceTypes.Surface, frame: Maybe<&2, Rendered.Frame>, +state: State) -> KeyResult:
  match scope:
    case Focus.Document{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Focus.Temporary{identity, initial, restore, occurrence}:
      published_key_kind(String.eq(key, "Tab"), String.eq(key, "Escape"), shift, scope, basis, semantic, frame, state)

def key_captured(+key: String, +shift: Bool, +state: State) -> KeyResult:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Some{Published{world, semantic, scope, basis, frame}}: published_key(key, shift, scope, basis, semantic, frame, state)

def key_event(+key: String, +shift: Bool, +received: Nat, +frame: Rendered.Frame, +state: State) -> KeyResult:
  key_captured(key, shift, decision_state(receive_frame(received, frame, state)))

def receipt_selection(status: World.ReceiptStatus, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: SurfaceTypes.Surface, round: Nat) -> Decision:
  match status:
    case World.Rejected{reason}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
    case _: finish_search(search_run(8n, selected(World.plan(engine), index, capacity, engine, state, semantic, round)))

def utility_fallback(reason: String, state: State) -> Decision:
  utility_start(Utility.Recovery{reason}, True{}, state)

# DEFENSE: A physical measurement failure in the recovery view gets one glyph-only recovery attempt; a failed glyph-only attempt blocks instead of looping.
def utility_measurement_failure(reason: String, +state: State) -> Decision:
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case UtilityMeasuring{purpose, engine, round, False{}}: utility_fallback(reason, state)
    case UtilityMeasuring{purpose, engine, round, True{}}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
    case _: utility_start(Utility.Recovery{reason}, False{}, state)

def utility_receipt(status: World.ReceiptStatus, +purpose: Utility.Purpose, +engine: World.Engine, round: Nat, glyph_only: Bool, +state: State) -> Decision:
  match status:
    case World.Rejected{reason}: utility_measurement_failure(reason, state)
    case _: utility_selected(World.plan(engine), purpose, engine, round, glyph_only, state)

def measured_pending(+receipts: +List<String>, +state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, +engine, semantic, +round}, displayed, attention, updates}:
      +next = World.receive(World.snapshot_generation(World.snapshot(engine)), receipts, engine)
      utility_if_needed(receipt_selection(World.receipt_status(next), index, capacity, next, State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed, attention, updates}, semantic, (round + 1n : Nat)))
    case State{legacy, serial, anchors, UtilityMeasuring{purpose, +engine, +round, glyph_only}, displayed, attention, updates}:
      +next = World.receive(World.snapshot_generation(World.snapshot(engine)), receipts, engine)
      utility_receipt(World.receipt_status(next), purpose, next, (round + 1n : Nat), glyph_only, State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates})
    case other: Decision{other, Nil{}}

def measurement_owned(ticket: MeasurementTicket, state: State) -> Bool:
  MeasurementTicket{generation, received_round} = ticket
  State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Measuring{index, capacity, engine, semantic, round}: Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) && Nat.is_eq(received_round, round)
    case UtilityMeasuring{purpose, engine, round, glyph_only}: Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) && Nat.is_eq(received_round, round)
    case _: False{}

type MeasurementCandidate is Data:
  MeasurementCandidate{ticket: MeasurementTicket, receipts: +List<String>, state: State}

def physical_measured_predicate(candidate: MeasurementCandidate) -> Bool:
  MeasurementCandidate{+ticket, +receipts, +state} = candidate
  measurement_owned(ticket, state)

def physical_measured_category() -> MeasurementCandidate -> Type: Categories.holds(MeasurementCandidate, physical_measured_predicate)

def measured_current(member: Categories.Membership<MeasurementCandidate, physical_measured_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  MeasurementCandidate{+ticket, +receipts, +state} = candidate
  continue_latest(measured_pending(receipts, state))

def physical_measured_admitted(admission: Maybe<&1, Categories.Membership<MeasurementCandidate, physical_measured_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: Awaited font or Markdown measurement can finish after the owning display generation or receipt round has changed.
    case None{}: Decision{state, Nil{}}
    case Some{member}: measured_current(member)

def physical_measured(+ticket: MeasurementTicket, +receipts: +List<String>, +state: State) -> Decision:
  physical_measured_admitted(Categories.admit(MeasurementCandidate, physical_measured_predicate, MeasurementCandidate{ticket, receipts, state}), state)

type MeasurementFailureCandidate is Data:
  MeasurementFailureCandidate{ticket: MeasurementTicket, reason: String, state: State}

def physical_measurement_failed_predicate(candidate: MeasurementFailureCandidate) -> Bool:
  MeasurementFailureCandidate{+ticket, +reason, +state} = candidate
  measurement_owned(ticket, state)

def physical_measurement_failed_category() -> MeasurementFailureCandidate -> Type: Categories.holds(MeasurementFailureCandidate, physical_measurement_failed_predicate)

def measurement_failed(member: Categories.Membership<MeasurementFailureCandidate, physical_measurement_failed_category()>) -> Decision:
  Categories.Membership{candidate, evidence} = member
  MeasurementFailureCandidate{+ticket, +reason, +state} = candidate
  utility_measurement_failure(reason, state)

def physical_measurement_failed_admitted(admission: Maybe<&1, Categories.Membership<MeasurementFailureCandidate, physical_measurement_failed_category()>>, state: State) -> Decision:
  match admission:
    # DEFENSE: A cancelled measurement can report failure after a newer generation or receipt round owns the display.
    case None{}: Decision{state, Nil{}}
    case Some{member}: measurement_failed(member)

def physical_measurement_failed(+ticket: MeasurementTicket, +reason: String, +state: State) -> Decision:
  physical_measurement_failed_admitted(Categories.admit(MeasurementFailureCandidate, physical_measurement_failed_predicate, MeasurementFailureCandidate{ticket, reason, state}), state)

def remeasure(+state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed, attention, updates}: Decision{State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed, attention, updates}, Nil{}}
    case State{legacy, serial, anchors, Displaying{capacity, engine, semantic}, displayed, attention, updates}: build(0n, State{legacy, serial, anchors, Displaying{capacity, engine, semantic}, displayed, attention, updates})
    case State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates}:
      utility_start(purpose, glyph_only, State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates})
    case State{legacy, serial, anchors, UtilityDisplaying{purpose, engine}, displayed, attention, updates}:
      utility_start(purpose, False{}, State{legacy, serial, anchors, UtilityDisplaying{purpose, engine}, displayed, attention, updates})
    case other: Decision{other, Nil{}}

def key_decision(result: KeyResult) -> Decision:
  KeyResult{handled, decision} = result
  decision

def key_input(+key: String, +shift: Bool, +received: Nat, +frame: Rendered.Frame, +state: State) -> Decision: key_decision(key_event(key, shift, received, frame, state))

def key_handled(result: KeyResult) -> Bool:
  KeyResult{handled, decision} = result
  handled





def with_attention(value: Navigation.Attention, state: State) -> State:
  State{legacy, generation, anchors, lifecycle, displayed, previous, updates} = state
  State{legacy, generation, anchors, lifecycle, displayed, value, updates}

def attention_refresh(+state: State) -> Decision:
  State{legacy, generation, anchors, lifecycle, displayed, attention, updates} = state
  match lifecycle:
    case Displaying{capacity, +engine, semantic}: build(0n, state)
    case Measuring{index, capacity, engine, semantic, round}: Decision{state, Nil{}}
    case _: Decision{state, Nil{}}

def attention_changed(changed: Bool, value: Navigation.Attention, state: State) -> Decision:
  match changed:
    case False{}: Decision{state, Nil{}}
    case True{}: attention_refresh(advance_presentation(with_attention(value, state)))


def attention_change(valid: Bool, +value: Navigation.Attention, +state: State) -> Decision:
  match valid:
    case False{}: Decision{state, Nil{}}
    case True{}: attention_changed(Bool.not(Navigation.same(value, attention(state))), value, state)


# DEFENSE: A pointer observation may still name a navigation row removed by a concurrent publication.
def navigation_pointer_fields(+owner: Maybe<&2, String>, +state: State, previous: Navigation.Attention) -> Decision:
  Navigation.Attention{hovered, focused, capable} = previous
  attention_change(Navigation.admitted(owner, InterfaceView.active_nodes(current_surface(state))), Navigation.Attention{owner, focused, capable}, state)

def navigation_pointer(+owner: Maybe<&2, String>, +state: State) -> Decision:
  navigation_pointer_fields(owner, state, attention(state))

# DEFENSE: A focus observation may still name a navigation row removed by a concurrent publication.
def navigation_focus_fields(+owner: Maybe<&2, String>, +state: State, previous: Navigation.Attention) -> Decision:
  Navigation.Attention{hovered, focused, capable} = previous
  attention_change(Navigation.admitted(owner, InterfaceView.active_nodes(current_surface(state))), Navigation.Attention{hovered, owner, capable}, state)

def navigation_focus(+owner: Maybe<&2, String>, +state: State) -> Decision:
  navigation_focus_fields(owner, state, attention(state))

def navigation_hover_fields(capable: Bool, state: State, previous: Navigation.Attention) -> Decision:
  Navigation.Attention{hovered, focused, previous_capable} = previous
  attention_change(True{}, Navigation.Attention{hovered, focused, capable}, state)

def navigation_hover(capable: Bool, +state: State) -> Decision:
  navigation_hover_fields(capable, state, attention(state))

def step(+input: Legacy.Input, +state: State) -> Decision:
  match input:
    case Legacy.Native{Web.PlatformInput{Platform.NavigationPointerObserved{owner}}}: navigation_pointer(owner, state)
    case Legacy.Native{Web.PlatformInput{Platform.NavigationFocusObserved{owner}}}: navigation_focus(owner, state)
    case Legacy.Native{Web.PlatformInput{Platform.NavigationHoverObserved{capable}}}: navigation_hover(capable, state)
    case Legacy.Native{Web.CodeSourcesObserved{generation, observations}}: code_sources(generation, observations, state)
    case Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.CodeSource{identity, text}}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.ContentInput{identity, Code.SourceChanged{text}}}}}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.NativeFocusObserved{generation, owner, identity}}: native_focus_observed(generation, owner, identity, state)
    case Legacy.Native{Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.FrameObserved{generation, frame}}:
      receive_frame(generation, frame, state)
    case Legacy.Native{Web.PlatformInput{Platform.FocusObserved{identity}}}: auxiliary_focus(Web.PlatformInput{Platform.FocusObserved{identity}}, state)
    case Legacy.Native{Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}}: auxiliary_focus(Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}, state)
    case Legacy.Native{Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}}: auxiliary_focus(Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}, state)
    case Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{namespace, sequence, fresh, allowed}}}}}}:
      transport_environment(namespace, sequence, fresh, allowed, state)
    case Legacy.Native{Web.EnvironmentObserved{environment}}:
      accept(True{}, Legacy.native(Web.EnvironmentObserved{environment}, legacy(state)), with_lifecycle(WaitingEnvironment{}, state))
    case Legacy.Native{+input}: accept(source_changed(input), Legacy.native(input, legacy(state)), state)
    case other: accept(True{}, Legacy.step(other, legacy(state)), state)

def presentation_phase(state: State) -> Lifecycle:
  State{legacy, generation, anchors, phase, displayed, attention, updates} = state
  phase
