import Base
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as AnchorGeometry
import ../focus/MODEL.bend as Focus
import ./native-fields.bend as Native
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../document/FRAME.bend as SourceFrame
import ./PLATFORM.bend as Platform
import ../appearance/FONT.bend as F
import ../appearance/TYPOGRAPHY.bend as T
import ./MODEL.bend as Browser
import ../layout/physical-plan.bend as Plan
import ./SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ../document/RENDERED.bend as Rendered
import ../layout/MODEL.bend as World
import ../layout/CONTENT.bend as Content
import ../layout/RENDERER.bend as Renderer
import ../document/MODEL.bend as Doc
import ../../interaction/presentation/MODEL.bend as View
import ../../harness/MODEL.bend as M
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../interaction/submission/MODEL.bend as Receipt
import ../document/SOURCE.bend as Source
import ../controls/CONTROLS.bend as Controls
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/services/MODEL.bend as Services
import ./request.bend as Request
import ../../interaction/MODEL.bend as Product
import ../../features/board/MODEL.bend as B
import ../../features/board/CODEC.bend as BoardCodec
import ../../harness/transport/command-codec.bend as Codec
import ./frontend-utility.bend as Utility
import ../appearance/MODEL.bend as Appearance
import ../../interaction/IDENTITY.bend as Identity
import ../document/presentation-order.bend as Order
import ../CONTRACT.bend as Interaction
import ../../interaction/presentation/CONTRACT.bend as Rules_interface_program_rules
import ../../interaction/TYPES.bend as InteractionTypes
import ../document/render-contract.bend as FrameRules
import ../editor/MODEL.bend as Editor
import ../../harness/features/MODEL.bend as F2
import ../controls/PROGRAM.bend as Controls2

def unchanged_claim(+value: String, +record: Native.Record) -> Type:
  {Native.step(Native.Synchronize{value}, record) == Native.Decision{record, False{}, False{}} : Native.Decision}

def unmatched_claim(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) -> Type:
  {Native.update_owned(Native.owned_node(binding, found), binding, found) == Nil{} : +List<Native.Update>}

def matching_claim(+binding: Native.Binding, +node: SurfaceTypes.Node) -> Type:
  Native.Binding{key, kind, identity, original} = binding
  SurfaceTypes.Node{current, semantic, label, role, meaning, children} = node
  {Native.update_owned(Native.owned_node(binding, Some{node}), binding, Some{node}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}

def changed_composing_claim(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String) -> Type:
  {Native.step(Native.Synchronize{value}, Native.Record{identity, old, Native.Composing{}}) ==
    Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}

def superseded_end_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.CompositionEnded{}, Native.Record{identity, canonical, Native.SupersededComposing{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}

def superseded_tail_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.InputObserved{}, Native.Record{identity, canonical, Native.SupersededTail{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}

def superseded_input_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.InputObserved{}, Native.Record{identity, canonical, Native.SupersededComposing{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}

def superseded_tail_end_claim(+identity: Maybe<&2, Native.Identity>, +canonical: Maybe<&2, String>) -> Type:
  {Native.step(Native.CompositionEnded{}, Native.Record{identity, canonical, Native.SupersededTail{}}) ==
    Native.Decision{Native.Record{identity, canonical, Native.SupersededTail{}}, False{}, True{}} : Native.Decision}

def transaction_claim(+record: Native.Record) -> Type:
  Native.Record{identity, canonical, session} = record
  {Native.step(Native.InputStarted{}, record) == Native.Decision{Native.Record{identity, canonical, Native.Idle{}}, False{}, False{}} : Native.Decision}

def checkbox_claim(+key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) -> Type:
  {Native.projected(key, Source.ToggleField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, Controls.field_checked(meaning)}] : +List<Native.Update>}

def text_claim(+key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) -> Type:
  {Native.projected(key, Source.TextField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, Controls.node_value(meaning)}] : +List<Native.Update>}

def editor_owner_claim(+editor: U.Editor, +other: U.Editor, +field: Forms.Field, +entry: Forms.Entry, +value: Forms.Observed, +choices: +List<Forms.ChoiceValue>, +new_field: Forms.Field, +new_entry: Forms.Entry, +new_value: Forms.Observed, +new_choices: +List<Forms.ChoiceValue>) -> Type:
  {Native.same_meaning(SurfaceTypes.Edit{editor, field, entry, value, choices}, SurfaceTypes.Edit{other, new_field, new_entry, new_value, new_choices}) == U.same_editor(editor, other) : Bool}

def unbound_claim(+identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{None{}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, session}, False{}, False{}} : Native.Decision}

def equal_rebind_claim(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{old}, canonical, session}, False{}, False{}} : Native.Decision}

def changed_rebind_claim(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session) -> Type:
  {Native.step(Native.Rebind{identity}, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, Native.rebind_session(session)}, False{}, True{}} : Native.Decision}

def rebind_composing_claim() -> Type:
  {Native.rebind_session(Native.Composing{}) == Native.SupersededComposing{} : Native.Session}

def rebind_idle_claim() -> Type:
  {Native.rebind_session(Native.Idle{}) == Native.SupersededTail{} : Native.Session}

type NativeFieldsRequirements is Type:
  NativeFieldsRequirements{
    unbound: @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> unbound_claim(identity, canonical, session),
    equal_rebind: @+old:Native.Identity -> @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> {Native.same_identity(old, identity) == True{} : Bool} -> equal_rebind_claim(old, identity, canonical, session),
    changed_rebind: @+old:Native.Identity -> @+identity:Native.Identity -> @+canonical:Maybe<&2, String> -> @+session:Native.Session -> {Native.same_identity(old, identity) == False{} : Bool} -> changed_rebind_claim(old, identity, canonical, session),
    rebind_composing: rebind_composing_claim(),
    rebind_idle: rebind_idle_claim(),
    editor_owner: @+editor:U.Editor -> @+other:U.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> -> @+new_field:Forms.Field -> @+new_entry:Forms.Entry -> @+new_value:Forms.Observed -> @+new_choices:+List<Forms.ChoiceValue> -> editor_owner_claim(editor, other, field, entry, value, choices, new_field, new_entry, new_value, new_choices),
    unchanged: @+value:String -> @+record:Native.Record ->
      {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool} -> unchanged_claim(value, record),
    unmatched: @+binding:Native.Binding -> @+found:Maybe<&2, SurfaceTypes.Node> ->
      {Native.owned_node(binding, found) == False{} : Bool} -> unmatched_claim(binding, found),
    matching: @+binding:Native.Binding -> @+node:SurfaceTypes.Node ->
      {Native.owned_node(binding, Some{node}) == True{} : Bool} -> matching_claim(binding, node),
    changed_composing: @+identity:Maybe<&2, Native.Identity> -> @+old:Maybe<&2, String> -> @+value:String ->
      {Native.canonical_same(old, value) == False{} : Bool} -> changed_composing_claim(identity, old, value),
    superseded_end: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_end_claim(identity, canonical),
    superseded_tail: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_tail_claim(identity, canonical),
    superseded_input: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_input_claim(identity, canonical),
    superseded_tail_end: @+identity:Maybe<&2, Native.Identity> -> @+canonical:Maybe<&2, String> -> superseded_tail_end_claim(identity, canonical),
    transaction: @+record:Native.Record -> transaction_claim(record),
    checkbox: @+key:String -> @+semantic:String -> @+meaning:SurfaceTypes.Meaning -> checkbox_claim(key, semantic, meaning),
    text: @+key:String -> @+semantic:String -> @+meaning:SurfaceTypes.Meaning -> text_claim(key, semantic, meaning)}

law native_fields_evidence:
  NativeFieldsRequirements

law updates_empty:
  for nodes: +List<SurfaceTypes.Node>
  {Native.updates_fields(Nil{}, nodes) == Nil{} : +List<Native.Update>}

law updates_complete:
  for +binding: Native.Binding
  for +rest: +List<Native.Binding>
  for +nodes: +List<SurfaceTypes.Node>
  {Native.updates_fields(binding <> rest, nodes) == List.append(&2, Native.Update, Native.update(binding, nodes), Native.updates_fields(rest, nodes)) : +List<Native.Update>}

law updates_basis:
  for fields: +List<Native.Binding>
  for controls: +List<String>
  for surface: SurfaceTypes.Surface
  {Native.updates(Native.Basis{fields, controls}, surface) == Native.updates_fields(fields, Native.forest(surface)) : +List<Native.Update>}

law update_owner:
  for +key: String
  for +kind: Source.NativeFieldKind
  for +semantic: String
  for +meaning: SurfaceTypes.Meaning
  for +nodes: +List<SurfaceTypes.Node>
  {Native.update(Native.Binding{key, kind, semantic, meaning}, nodes) ==
    Native.update_owned(Native.owned_node(Native.Binding{key, kind, semantic, meaning}, InterfaceView.find_node(nodes, key)), Native.Binding{key, kind, semantic, meaning}, InterfaceView.find_node(nodes, key)) : +List<Native.Update>}

def field_projection(kind: Source.NativeFieldKind, key: String, semantic: String, meaning: SurfaceTypes.Meaning, actual: +List<Native.Update>) -> Type:
  match kind:
    case Source.ToggleField{}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, Controls.field_checked(meaning)}] : +List<Native.Update>}
    case Source.FileField{multiple}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}] : +List<Native.Update>}
    case _: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, Controls.node_value(meaning)}] : +List<Native.Update>}

law all_field_projections:
  for +kind: Source.NativeFieldKind
  for +key: String
  for +semantic: String
  for +meaning: SurfaceTypes.Meaning
  field_projection(kind, key, semantic, meaning, Native.projected(key, kind, semantic, meaning))

law edit_text_rejected:
  for +key: String
  for +text: String
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.edit_text(key, text, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law edit_text_accepted:
  for +key: String
  for +text: String
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.edit_text(key, text, state) == Browser.accept(True{}, Legacy.edit_text(key, text, Browser.legacy(state)), state) : Browser.Decision}

law confirm_text_rejected:
  for +key: String
  for +keyboard: String
  for +composing: Bool
  for +control: Bool
  for +alt: Bool
  for +shift: Bool
  for +meta: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law confirm_text_accepted:
  for +key: String
  for +keyboard: String
  for +composing: Bool
  for +control: Bool
  for +alt: Bool
  for +shift: Bool
  for +meta: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.accept(True{}, Legacy.confirm_text(key, keyboard, composing, control, alt, shift, meta, Browser.legacy(state)), state) : Browser.Decision}

law edit_toggle_rejected:
  for +key: String
  for +enabled: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.edit_toggle(key, enabled, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law edit_toggle_accepted:
  for +key: String
  for +enabled: Bool
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.edit_toggle(key, enabled, state) == Browser.accept(True{}, Legacy.edit_toggle(key, enabled, Browser.legacy(state)), state) : Browser.Decision}

law attach_rejected:
  for +key: String
  for +file: Services.SelectedFile
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == False{} : Bool}
  {Browser.attach(key, file, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law attach_accepted:
  for +key: String
  for +file: Services.SelectedFile
  for +state: Browser.State
  for owned: {Browser.field_owned(key, state) == True{} : Bool}
  {Browser.attach(key, file, state) == Browser.accept(True{}, Legacy.attach(key, file, Browser.legacy(state)), state) : Browser.Decision}

def decision_world(decision: E.Decision) -> M.World():
  E.Decision{+observed_state_1, reply, runtime, interaction, durable} = decision
  +program = E.program(observed_state_1)
  program

type FrontendUtilityRequirements is Type:
  FrontendUtilityRequirements{
    supported: @+purpose:Utility.Purpose -> @+font:T.Presentation -> @+glyph_only:Bool ->
      {Utility.supported(Utility.source(purpose, font, glyph_only)) == True{} : Bool},
    retry_identity_and_event: @+font:T.Presentation -> @+reason:String ->
      {Utility.retry(font, reason) == Source.Control{Utility.retry_key(), Source.Button{}, Utility.retry_style(font),
        [Source.DataAttribute{"native-key", Identity.encode(Utility.retry_key())}, Source.TitleAttribute{"Retry rendering: " ++ reason}], "Retry rendering: " ++ reason,
        True{}, Doc.Activate{"@browser/retry"}, Nil{},
        [Controls.glyph(Identity.part(Utility.retry_key(), "icon"), Controls2.Refresh{}, Appearance.ordinary_button(font), 16n)]} : Source.Node},
    source_owned: @+purpose:Utility.Purpose -> @+font:T.Presentation -> @+glyph_only:Bool ->
      {Utility.owned(Utility.source(purpose, font, glyph_only)) == True{} : Bool}}

law frontend_utility_evidence:
  FrontendUtilityRequirements

def stale_frames_claim(+received: Nat, +frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.step(Legacy.Native{Web.FrameObserved{received, frame}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def stale_measurements_claim(+received: Browser.MeasurementTicket, +tokens: +List<String>, +state: Browser.State) -> Type:
  {Browser.physical_measured(received, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def ready_document_claim(+model_state: Browser.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface) -> Type:
  {Browser.observe(rendering_capacity, Browser.with_displayed(Some{Browser.published(world, layout_capacity, Browser.legacy(model_state), semantic)}, Browser.with_lifecycle(Browser.Displaying{layout_capacity, engine, semantic}, model_state))) ==
    Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, Renderer.nodes(world)}, "Selvedge"} : Doc.Document}

def anchor_preserves_program_claim(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: Browser.State) -> Type:
  {Browser.program(Browser.decision_state(Browser.capture_anchor(key, left, top, width, height, state))) == Browser.program(state) : M.World()}

def frame_capture_program_claim(+frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.program(Browser.frame_capture(frame, state)) == Browser.program(state) : M.World()}

def document_keyboard_claim(+key: String, +shift: Bool, +basis: Native.Basis, +semantic: SurfaceTypes.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.published_key(key, shift, Focus.Document{}, basis, semantic, frame, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}

def temporary_tab_claim(+shift: Bool, +identity: String, +initial: String, +restore: String, +occurrence: Maybe<&2, Nat>, +basis: Native.Basis, +semantic: SurfaceTypes.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.key_handled(Browser.published_key("Tab", shift, Focus.Temporary{identity, initial, restore, occurrence}, basis, semantic, frame, state)) == True{} : Bool}

law forwarded_frame_uses_published_surface:
  for +model_state: Browser.State
  for +world: Content.AllocatedWorld
  for +semantic: SurfaceTypes.Surface
  for +scope: Focus.Scope
  for +basis: Native.Basis
  for +old: Maybe<&2, Rendered.Frame>
  for +frame: Rendered.Frame
  {Browser.frame_forward_ready(True{}, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state), frame) ==
    Browser.accept(False{}, Legacy.observe_frame(Browser.semantic_generation(Browser.legacy(model_state)), semantic, frame, Browser.legacy(model_state)),
      Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision}

law failed_font_candidate_blocked:
  for +model_state: Browser.State
  for +font_generation: Nat
  for +scale: T.Scale
  for +index: Nat
  {Browser.one_candidate(index, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_typography(F.Failed{font_generation, scale}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state)) ==
    Browser.Stopped{Browser.Decision{Browser.with_lifecycle(Browser.Blocked{"Font measurements could not be validated."}, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_typography(F.Failed{font_generation, scale}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state)), Nil{}}} : Browser.Search}

def element_enabled(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds} = element
  enabled

def element_reachable(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds} = element
  visible || scroll

law enabled_reachable_tab_member:
  for +element: Rendered.Element
  for admitted: {element_enabled(element) == True{} : Bool}
  for reachable: {element_reachable(element) == True{} : Bool}
  {Browser.observed_eligible(Some{element}) == True{} : Bool}

law rejected_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for rejected: {Browser.native_observation_owned(generation, owner, identity, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law missing_native_frame_rejects:
  for semantic: SurfaceTypes.Surface
  for owner: String
  for identity: String
  {Browser.native_frame_owned(None{}, semantic, owner, identity) == False{} : Bool}

law stale_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for stale: {Browser.frame_owned(generation, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law render_violations_unmet:
  for +model_state: Browser.State
  for +observed_generation: Nat
  for +frame: Rendered.Frame
  for +violations: +List<Rendered.Violation>
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.Unmet{observed_generation, frame, violations}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == violations : +List<Rendered.Violation>}

law render_violations_awaiting:
  for +model_state: Browser.State
  for +observed_generation: Nat
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.AwaitingFrame{observed_generation}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == Nil{} : +List<Rendered.Violation>}

law render_violations_realized:
  for +model_state: Browser.State
  for +observed_generation: Nat
  for +frame: Rendered.Frame
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.Realized{observed_generation, frame}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == Nil{} : +List<Rendered.Violation>}

def rebuilt_frame_decision_claim(+first: +List<Legacy.Effect>, +state: Browser.State) -> Type:
  {Browser.accepted(True{}, first, state) == Browser.append(first, Browser.build(0n, state)) : Browser.Decision}

def inspection_frame_expected(frame: Maybe<&2, Rendered.Frame>, +active: +List<SurfaceTypes.Node>, +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Legacy.DismissTarget>) -> Browser.RenderInspection:
  match frame:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, layer, dismiss}
    case Some{+observed}:
      Rendered.Frame{viewport, elements, focused, tabs, native_focus} = observed
      Browser.RenderInspection{Some{observed}, Some{Rendered.expected_tabs(active, elements, native_focus)},
        Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss}

def inspection_frame(realization: Rendered.State) -> Maybe<&2, Rendered.Frame>:
  match realization:
    case Rendered.AwaitingFrame{generation}: None{}
    case Rendered.Realized{generation, frame}: Some{frame}
    case Rendered.Unmet{generation, frame, violations}: Some{frame}

def inspection_display_expected(+frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{frame, None{}, None{}, layer, None{}}
    case Some{Browser.Published{world, semantic, scope, basis, published_frame}}:
      +active = InterfaceView.active_nodes(semantic)
      +dismiss = Legacy.dismiss_target(active)
      inspection_frame_expected(frame, active, layer, dismiss)

def inspection_expected(+stored: Legacy.State, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  +observed_web_1 = Legacy.web(stored)
  +realization = Web.realization(observed_web_1)
  +layer = Legacy.current_layer_key(stored)
  inspection_display_expected(inspection_frame(realization), layer, displayed)

def inspection_utility_expected(displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, None{}, None{}}
    case Some{Browser.Published{+world, semantic, scope, basis, frame}}:
      Browser.RenderInspection{frame, Some{SourceFrame.tabs(SourceFrame.expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}

def inspection_owned_expected(utility: Bool, +stored: Legacy.State, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match utility:
    case True{}: inspection_utility_expected(displayed)
    case False{}: inspection_expected(stored, displayed)

def render_inspection_claim(+model_state: Browser.State) -> Type:
  {Browser.render_inspection(model_state) ==
    inspection_owned_expected(Browser.auxiliary_owned(model_state), Browser.legacy(model_state), Browser.displayed(model_state)) : Browser.RenderInspection}

law rebuilt_frame_decision:
  for +first: +List<Legacy.Effect>
  for +state: Browser.State
  rebuilt_frame_decision_claim(first, state)

law render_inspection:
  for +model_state: Browser.State
  render_inspection_claim(model_state)

def failure_axis_text(axis: Allocation.Axis) -> String:
  match axis:
    case Allocation.InlineAxis{}: "width"
    case Allocation.BlockAxis{}: "height"

def failure_reason_text(reason: Allocation.FailureReason) -> String:
  match reason:
    case Allocation.AuthoredRangeConflict{}: "authored range conflict"
    case Allocation.InsufficientSpace{}: "insufficient space"
    case Allocation.AllocationBoundExceeded{budget}: "allocation bound exceeded (budget " ++ Nat.show(budget) ++ ")"

law failure_message:
  for +key: String
  for +axis: Allocation.Axis
  for +required: Nat
  for +available: Nat
  for +reason: Allocation.FailureReason
  {Browser.failure_message(Allocation.Failure{key, axis, required, available, reason}) ==
    "The interface does not fit the available space: " ++ key ++ "; " ++
      failure_axis_text(axis) ++
      " required " ++ Nat.show(required) ++ "px, available " ++ Nat.show(available) ++ "px; " ++
      failure_reason_text(reason) : String}

law infeasible_candidate_retries:
  for +index: Nat
  for +state: Browser.State
  for +failure: Allocation.Failure
  {Browser.infeasible_candidate(True{}, index, state, failure) == Browser.Searching{(index + 1n : Nat), state} : Browser.Search}

law infeasible_candidate_reports:
  for +model_state: Browser.State
  for +index: Nat
  for +failure: Allocation.Failure
  {Browser.infeasible_candidate(False{}, index, model_state, failure) ==
    Browser.Stopped{Browser.Decision{Browser.with_lifecycle(Browser.Blocked{Browser.failure_message(failure)}, model_state), Nil{}}} : Browser.Search}

def sequence(+state: Legacy.State) -> Nat:
  +sequence = Legacy.sequence(state)
  sequence

# Admission reserves its ticket and carries the original completion exactly once.

def document_state(+state: Legacy.State) -> Legacy.State:
  +web = Legacy.web(state)
  +application = Web.application(web)
  +platform = Platform.platform(application)
  Legacy.with_receipt(None{}, Legacy.with_web(Web.with_application(
    Platform.with_platform(Platform.with_scope(Focus.Document{}, platform), application), web), state))

def document_key_event_law(-key: String, -shift: Bool, -state: Legacy.State) -> Type:
  {Legacy.key_event(key, shift, document_state(state)) ==
    Legacy.KeyResult{False{}, Legacy.Decision{document_state(state), Nil{}}} : Legacy.KeyResult}

law editing_retains_selection:
  for revision: Nat
  for body: U.Body
  for directory_entry: String
  for editor: Editor.Editor
  {Platform.synchronize_editor(Some{U.Draft{revision, body, U.Editing{}, directory_entry}}, editor) == editor : Editor.Editor}

def effects(decision: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, result} = decision
  result

def pending(decision: Legacy.Decision) -> +List<Legacy.Pending>:
  Legacy.Decision{+observed_state_1, effects} = decision
  +requests = Legacy.pending(observed_state_1)
  requests

def web_state(decision: Legacy.Decision) -> Web.State:
  Legacy.Decision{+observed_state_1, effects} = decision
  +web = Legacy.web(observed_state_1)
  web

def transport(decision: Legacy.Decision) -> (Nat & (Nat & +List<Legacy.Pending>)):
  Legacy.Decision{+observed_state_1, effects} = decision
  +sequence = Legacy.sequence(observed_state_1)
  +next = Legacy.next_ticket(observed_state_1)
  +pending = Legacy.pending(observed_state_1)
  (sequence, (next, pending))

law merge_reflow_product:
  for +product: InteractionTypes.Decision
  for effects: +List<Platform.Effect>
  for refreshed: Platform.Decision
  {Platform.decision_product(Platform.merge_reflow(product, effects, refreshed)) == product : InteractionTypes.Decision}

def decision_surface(decision: Platform.Decision) -> SurfaceTypes.Surface:
  Platform.Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable}, platform, result} = decision
  InterfaceView.observe(Platform.capacity(platform), core)

law realized_preserves_product:
  for decision: Platform.Decision
  {Platform.decision_product(Platform.realized_decision(decision)) == Platform.decision_product(decision) : InteractionTypes.Decision}

law realized_empty:
  for product: InteractionTypes.Decision
  for platform: Platform.Platform
  {Platform.realized_decision(Platform.Decision{product, platform, Nil{}}) == Platform.Decision{product, platform, Nil{}} : Platform.Decision}

def ticket(+platform: Platform.Platform) -> Nat:
  editors = Platform.editors(platform)
  +ticket = Platform.focus_ticket(platform)
  ticket

def direct_claim(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Legacy.RequestStatus, state: Legacy.State) -> Type:
  {Legacy.decision_receipt(Legacy.completed(Some{Legacy.Pending{ticket, E.DirectCompletion{}, command, origin, status}},
    received, world, D.failure(code, message), state)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>}

def confirmation_claim(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Legacy.RequestStatus, selected: M.Command,
  trigger: String, destination: U.Route, occurrence: Nat, state: Legacy.State) -> Type:
  {Legacy.decision_receipt(Legacy.completed(Some{Legacy.Pending{ticket, E.ConfirmationCompletion{selected, trigger, destination, occurrence}, command, origin, status}},
    received, world, D.failure(code, message), state)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>}

type BrowserReceiptRequirements is Type:
  BrowserReceiptRequirements{
    direct: @+ticket:Nat -> @received:Nat -> @world:M.World() -> @+code:String -> @+message:String ->
      @command:J.Json -> @+origin:String -> @status:Legacy.RequestStatus -> @state:Legacy.State ->
      direct_claim(ticket, received, world, code, message, command, origin, status, state),
    confirmation: @+ticket:Nat -> @received:Nat -> @world:M.World() -> @+code:String -> @+message:String ->
      @command:J.Json -> @+origin:String -> @status:Legacy.RequestStatus -> @selected:M.Command -> @trigger:String -> @destination:U.Route -> @occurrence:Nat -> @state:Legacy.State ->
      confirmation_claim(ticket, received, world, code, message, command, origin, status, selected, trigger, destination, occurrence, state),
    stale: @received:Nat -> @world:M.World() -> @reply:J.Json -> @+state:Legacy.State ->
      {Legacy.completed(None{}, received, world, reply, state) == Legacy.Decision{state, Nil{}} : Legacy.Decision},
    draft: @draft:U.Draft -> @receipt:Maybe<&2, Receipt.Receipt> -> @+decision:Legacy.Decision ->
      {Legacy.completion_receipt(E.DraftCompletion{draft}, receipt, decision) == decision : Legacy.Decision},
    unknown: @ticket:Nat -> @reason:String -> @+state:Legacy.State ->
      {Legacy.decision_receipt(Legacy.failed_completion(ticket, reason, state)) == Legacy.operation_receipt(state) : Maybe<&2, Receipt.Receipt>},
    duplicate: @command:J.Json -> @completion:E.Completion -> @origin:String -> @+state:Legacy.State ->
      {Legacy.request_ready(True{}, command, completion, origin, state) == Legacy.Decision{state, Nil{}} : Legacy.Decision},
    accepted: @command:J.Json -> @completion:E.Completion -> @origin:String -> @state:Legacy.State ->
      {Legacy.decision_receipt(Legacy.request_ready(False{}, command, completion, origin, state)) == None{} : Maybe<&2, Receipt.Receipt>}}

law browser_receipt_evidence:
  BrowserReceiptRequirements

type RequestRequirements is Type:
  RequestRequirements{
    current_world: @+model_state:E.Application ->  @completion:E.Completion -> @reason:String -> {decision_world(E.complete_command(E.program(model_state), D.failure("command_not_submitted", reason), completion, model_state)) == E.program(model_state) : M.World()},
    owned_field_absent: @+fields:+List<J.Field> -> {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json},
    create: @profile:String -> @reasoning:String -> @message:String -> @fields:+List<J.Field> ->
      {Legacy.request_payload(M.Create{profile, reasoning, message, J.Object{fields}}) ==
          J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}},
            J.Field{"op", J.Text{"create"}}, J.Field{"profile", J.Text{profile}},
            J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}]} : J.Json},
    fork: @id:Nat -> @count:Nat -> @messages:+List<String> -> @fields:+List<J.Field> ->
      {Legacy.request_payload(M.Fork{id, count, messages, J.Object{fields}}) ==
          J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}}, J.Field{"op", J.Text{"fork"}},
            J.Field{"task_id", J.nat(id)}, J.Field{"child_count", J.nat(count)},
            J.Field{"messages", J.Array{J.text_items(messages)}}]} : J.Json},
    project: @name:String -> @workspace:J.Json -> @guidance:+List<J.Field> ->
      {Legacy.request_payload(M.CreateProject{name, workspace, J.Object{guidance}}) ==
        J.Object{[J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}}, J.Field{"workspace", workspace}]} : J.Json},
    update: @id:Nat -> @+name:Maybe<&2, String> -> @+workspace:J.Json -> @guidance:+List<J.Field> ->
      {Legacy.request_payload(M.UpdateProject{id, name, workspace, J.Object{guidance}}) ==
        Codec.command_json(M.UpdateProject{id, name, workspace, J.Null{}}) : J.Json},
    agent: @id:Maybe<&2, Nat> -> @revision:Nat -> @name:String -> @profile:String -> @reasoning:String ->
      @instructions:String -> @fields:+List<J.Field> -> @concurrency:Nat ->
      {Legacy.request_payload(M.FeatureCommand{F2.BoardCommand{B.SaveAgent{id, revision,
          B.AgentProfile{revision, name, profile, reasoning, instructions, J.Object{fields}, concurrency}}}}) ==
          BoardCodec.command("save_board_agent", J.Field{"agent", J.Text{BoardCodec.id_text(id)}} <>
            BoardCodec.agent_fields(B.AgentProfile{revision, name, profile, reasoning, instructions,
              J.Object{Request.without_guidance(fields)}, concurrency})) : J.Json},
    preserve_field: @+name:String -> @+value:J.Json -> @+rest:+List<J.Field> ->
      @unrelated:{String.eq(name, "guidance") == False{} : Bool} ->
      {Request.without_guidance(J.Field{name, value} <> rest) == J.Field{name, value} <> Request.without_guidance(rest) : +List<J.Field>},
    settlement: @+model_state:Legacy.State ->  @ticket:Nat -> @completion:E.Completion -> @command:J.Json -> @origin:String -> @status:Legacy.RequestStatus ->
      @reason:String -> {Legacy.rejected_pending(Some{Legacy.Pending{ticket, completion, command, origin, status}}, reason,
          Legacy.with_receipt(None{}, model_state)) ==
          Legacy.completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), Legacy.product_input(Product.CommandCompleted{Legacy.program(Legacy.with_receipt(None{}, model_state)),
            D.failure("command_not_submitted", reason), completion},
            Legacy.with_receipt(None{}, Legacy.with_pending(Legacy.remove(Legacy.pending(model_state), ticket), model_state)))) : Legacy.Decision},
    stale: @+model_state:Legacy.State ->  @+ticket:Nat -> @reason:String ->
      @absent:{Legacy.find(Legacy.pending(model_state), ticket) == None{} : Maybe<&2, Legacy.Pending>} -> {Legacy.command_rejected(ticket, reason, Legacy.with_receipt(None{}, model_state)) ==
        Legacy.Decision{Legacy.with_receipt(None{}, model_state), Nil{}} : Legacy.Decision},
    consumed: @+pending:+List<Legacy.Pending> -> @+ticket:Nat -> {Legacy.owns_ticket(Legacy.remove(pending, ticket), ticket) == False{} : Bool},
    other_pending: @+entry:Legacy.Pending -> @+rest:+List<Legacy.Pending> -> @+ticket:Nat ->
      @distinct:{Nat.is_eq(Legacy.ticket_of(entry), ticket) == False{} : Bool} ->
      {Legacy.remove(entry <> rest, ticket) == entry <> Legacy.remove(rest, ticket) : +List<Legacy.Pending>},
    rejected_draft: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @directory_entry:String -> @submitted:Nat -> @reason:String ->
      {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted,
          D.failure("command_not_submitted", reason)) ==
          U.Draft{revision, body, U.Rejected{submitted, reason}, directory_entry} : U.Draft},
    uncertain: @+model_state:Legacy.State ->  @ticket:Nat -> @reason:String -> {Legacy.failed_completion(ticket, reason, Legacy.with_receipt(None{}, model_state)) ==
        Legacy.Decision{Legacy.with_receipt(None{}, Legacy.with_pending(Legacy.uncertain_pending(Legacy.pending(model_state), ticket, reason), model_state)), Nil{}} : Legacy.Decision},
    other_command: @id:Nat -> @message:String -> {Legacy.request_payload(M.Send{id, message}) == Codec.command_json(M.Send{id, message}) : J.Json}}

law request_evidence:
  RequestRequirements

law stale_measurement_failure:
  for +ticket: Browser.MeasurementTicket
  for +reason: String
  for +state: Browser.State
  for stale: {Browser.measurement_owned(ticket, state) == False{} : Bool}
  {Browser.physical_measurement_failed(ticket, reason, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law current_measurement_failure:
  for +ticket: Browser.MeasurementTicket
  for +reason: String
  for +state: Browser.State
  for owned: {Browser.measurement_owned(ticket, state) == True{} : Bool}
  {Browser.physical_measurement_failed(ticket, reason, state) ==
    Browser.utility_measurement_failure(reason, state) : Browser.Decision}

law unconfirmed_publication_has_no_focus_feedback:
  for +document: Doc.Document
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(Browser.Publish{0n, document, fields}, ticket, before, after) == None{} : Maybe<&2, Platform.Input>}

law retained_publication_has_no_focus_feedback:
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(Browser.KeepPublished{fields}, ticket, before, after) == None{} : Maybe<&2, Platform.Input>}

law absent_focus_has_no_publication_feedback:
  for +publication: Browser.Publication
  for +ticket: Nat
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(publication, ticket, None{}, after) == None{} : Maybe<&2, Platform.Input>}

law owned_focus_has_no_publication_feedback:
  for +publication: Browser.Publication
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Focus.Target
  {Browser.publication_focus_feedback(publication, ticket, before, Some{after}) == None{} : Maybe<&2, Platform.Input>}

law confirmed_publication_focus_loss:
  for +generation: Nat
  for +document: Doc.Document
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Focus.Target
  for confirmed: {Bool.not(Nat.is_eq(generation, 0n)) == True{} : Bool}
  {Browser.publication_focus_feedback(Browser.Publish{generation, document, fields}, ticket, Some{before}, None{}) ==
    Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}

type BrowserRequirements is Type:
  BrowserRequirements{
    measurements_transport: @+model_state:Legacy.State ->  @+observation: F.Observation -> {transport(Legacy.measurements(observation, Legacy.with_receipt(None{}, model_state))) ==
    (Legacy.sequence(model_state), (Legacy.next_ticket(model_state), Legacy.pending(model_state))) : (Nat & (Nat & +List<Legacy.Pending>))},
    finish_unchanged_transport: @web: Web.State -> @core: InteractionTypes.State -> @effects: +List<Web.Effect> -> @sequence: Nat -> @next: Nat -> @pending: +List<Legacy.Pending> -> @origin: String -> {transport(Legacy.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Legacy.Pending>))},
    receipt_input: @observation: F.Observation -> @state: Legacy.State -> {Legacy.measurements(observation, state) == Legacy.step(Legacy.Native{Web.TypographyObserved{observation}}, state) : Legacy.Decision},
    nodes_current_surface: @+model_state:Legacy.State ->  {Legacy.nodes(Legacy.with_receipt(None{}, model_state)) == InterfaceView.active_nodes(Order.ordered_surface(Legacy.mask_surface(Web.surface(Interaction.model_application(Legacy.web(model_state))), Legacy.pending(model_state)))) : +List<SurfaceTypes.Node>},
    interface_bridge: Rules_interface_program_rules.InterfaceRequirements,
    dismissal_allowed: @+input:InteractionTypes.Input -> @+state:Legacy.State ->
      {Legacy.dismiss_permitted(True{}, input, state) ==
        Legacy.product_input(Product.InterfaceInput{input}, state) : Legacy.Decision},
    dismissal_refused: @input:InteractionTypes.Input -> @+state:Legacy.State ->
      {Legacy.dismiss_permitted(False{}, input, state) == Legacy.Decision{state, Nil{}} : Legacy.Decision},
    document_key_event: @+key:String -> @+shift:Bool -> @+state:Legacy.State ->
      document_key_event_law(key, shift, state),
    failed_transition: @+model_state:Legacy.State ->  @ticket:Nat -> @error:String -> {Legacy.step(Legacy.Failed{ticket, error}, Legacy.with_receipt(None{}, model_state)) ==
        Legacy.Decision{Legacy.with_receipt(None{}, Legacy.with_pending(Legacy.uncertain_pending(Legacy.pending(model_state), ticket, error), model_state)), Nil{}} : Legacy.Decision},
    document_key: @tab:Bool -> @escape:Bool -> @shift:Bool -> @realization:Rendered.State -> @state:Legacy.State ->
      {Legacy.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Legacy.Decision{state, Nil{}} : Legacy.Decision},
    failed_preserves_web: @+model_state:Legacy.State ->  @ticket:Nat -> @error:String -> {web_state(Legacy.step(Legacy.Failed{ticket, error}, Legacy.with_receipt(None{}, model_state))) == Legacy.web(model_state) : Web.State},
    failed_retains_ticket: @+model_state:Legacy.State ->  @ticket:Nat -> @error:String -> @observed:Nat ->
      {Legacy.owns_ticket(pending(Legacy.step(Legacy.Failed{ticket, error}, Legacy.with_receipt(None{}, model_state))), observed) ==
        Legacy.owns_ticket(Legacy.pending(model_state), observed) : Bool},
    consumed_ticket: @+pending:+List<Legacy.Pending> -> @+ticket:Nat ->
      {Legacy.owns_ticket(Legacy.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Legacy.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Legacy.snapshot(received, world, state) == Legacy.Decision{state, Nil{}} : Legacy.Decision},
    admitted_request: @+model_state:Legacy.State ->  @command:J.Json -> @completion:E.Completion -> @origin:String ->
      {Legacy.request_ready(False{}, command, completion, origin, Legacy.with_receipt(None{}, model_state)) ==
          Legacy.Decision{Legacy.with_receipt(None{}, Legacy.with_pending(List.append(&2, Legacy.Pending, Legacy.pending(model_state), [Legacy.Pending{Legacy.next_ticket(model_state), completion, command, origin, Legacy.AwaitingReceipt{}}]), Legacy.with_next_ticket((Legacy.next_ticket(model_state) + 1n : Nat), model_state))),
            [Legacy.Command{Legacy.next_ticket(model_state), command}]} : Legacy.Decision},
    stale_completion: @+model_state:Legacy.State ->  @ticket:Nat -> @received:Nat -> @supplied:M.World() -> @reply:J.Json ->
      @completion:E.Completion -> {Legacy.complete_new(False{}, ticket, received, supplied, reply, completion,
          Legacy.with_receipt(None{}, model_state)) ==
          Legacy.product_input(Product.CommandCompleted{
            Legacy.program(Legacy.with_receipt(None{}, model_state)), reply, completion},
            Legacy.with_receipt(None{}, Legacy.with_pending(Legacy.remove(Legacy.pending(model_state), ticket), model_state))) : Legacy.Decision}}

law browser_evidence:
  BrowserRequirements

def expected_focus(found: Maybe<&2, String>, ticket: Nat) -> +List<Platform.Effect>:
  match found:
    case None{}: Nil{}
    case Some{key}: [Platform.Focus{ticket, Focus.Product{key}}]

def expected_effects(+surface: SurfaceTypes.Surface, source: +List<Platform.Effect>) -> +List<Platform.Effect>:
  match source:
    case Nil{}: Nil{}
    case Con{Platform.Focus{ticket, Focus.Product{requested}}, rest}:
      List.append(&2, Platform.Effect, expected_focus(InterfaceView.focus_target(surface, requested), ticket), expected_effects(surface, rest))
    case Con{Platform.ScopeFocus{ticket, previous, current}, rest}:
      List.append(&2, Platform.Effect, expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), expected_effects(surface, rest))
    case Con{other, rest}: other <> expected_effects(surface, rest)

law step_realizes_effects:
  for +input: Platform.Input
  for +state: Platform.State
  {effects(Platform.step(input, state)) == expected_effects(decision_surface(Platform.step_raw(input, state)), effects(Platform.step_raw(input, state))) : +List<Platform.Effect>}


# Internal scope intents must be discharged before effects leave the platform.

def external_effects(source: +List<Platform.Effect>) -> Bool:
  match source:
    case Nil{}: True{}
    case Con{Platform.ScopeFocus{ticket, previous, current}, rest}: False{}
    case Con{other, rest}: external_effects(rest)

law realized_effects_are_external:
  for +surface: SurfaceTypes.Surface
  for source: +List<Platform.Effect>
  {external_effects(Platform.realized_effects(surface, source)) == True{} : Bool}

law actual_step_effects_are_external:
  for input: Platform.Input
  for state: Platform.State
  {external_effects(effects(Platform.step(input, state))) == True{} : Bool}

def capacity(+platform: Platform.Platform) -> View.Capacity:
  editors = Platform.editors(platform)
  +capacity = Platform.capacity(platform)
  capacity

def pending_lifecycle(lifecycle: Browser.Lifecycle) -> Bool:
  match lifecycle:
    case Browser.WaitingEnvironment{}: True{}
    case Browser.WaitingFont{}: True{}
    case Browser.Measuring{index, capacity, engine, semantic, round}: True{}
    case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: True{}
    case other: False{}

def publication_pending(+state: Browser.State) -> Bool:
  +lifecycle = Browser.lifecycle(state)
  pending_lifecycle(lifecycle)

def blocked_publication_claim_at(+model_state: Browser.State, +capacity: Nat, +last_published: Nat, +problem: String) -> Type:
  {Browser.publication(capacity, last_published, Browser.with_lifecycle(Browser.Blocked{problem}, model_state)) ==
    Browser.publication_policy_at(capacity, Bool.not(Nat.is_eq(last_published, 0n)), False{},
      Nat.is_eq(Browser.displayed_generation(Browser.with_lifecycle(Browser.Blocked{problem}, model_state)), last_published),
      Browser.with_lifecycle(Browser.Blocked{problem}, model_state)) : Browser.Publication}

def publication_preserves_pending_claim_at(+capacity: Nat, +last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(capacity, last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

def publication_current_claim_at(+capacity: Nat, +last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(capacity, last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

type Requirements is Type:
  Requirements{
    temporary_tab: @+shift:Bool -> @+identity:String -> @+initial:String -> @+restore:String -> @+occurrence:Maybe<&2, Nat> -> @+basis:Native.Basis -> @+semantic:SurfaceTypes.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> temporary_tab_claim(shift, identity, initial, restore, occurrence, basis, semantic, frame, state),
    native_fields: NativeFieldsRequirements,
    frame_capture_program: @+frame:Rendered.Frame -> @+state:Browser.State -> frame_capture_program_claim(frame, state),
    document_keyboard: @+key:String -> @+shift:Bool -> @+basis:Native.Basis -> @+semantic:SurfaceTypes.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> document_keyboard_claim(key, shift, basis, semantic, frame, state),
    stale_frames: @+received:Nat -> @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.frame_owned(received, state) == False{} : Bool} -> stale_frames_claim(received, frame, state),
    stale_measurements: @+received:Browser.MeasurementTicket -> @+tokens:+List<String> -> @+state:Browser.State ->
      {Browser.measurement_owned(received, state) == False{} : Bool} -> stale_measurements_claim(received, tokens, state),
    ready_document: @+model_state:Browser.State ->  @+rendering_capacity:Nat -> @+layout_capacity:View.Capacity -> @+engine:World.Engine -> @+world:Content.AllocatedWorld -> @+semantic:SurfaceTypes.Surface -> ready_document_claim(Browser.with_displayed(Some{Browser.published(world, layout_capacity, Browser.legacy(model_state), semantic)}, Browser.with_lifecycle(Browser.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic),
    anchor_preserves_program: @+key:String -> @+left:AnchorGeometry.Origin -> @+top:AnchorGeometry.Origin -> @+width:Nat -> @+height:Nat -> @+state:Browser.State -> anchor_preserves_program_claim(key, left, top, width, height, state),
    publication_preserves_pending_at: @+capacity:Nat -> @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {publication_pending(state) == True{} : Bool} -> publication_preserves_pending_claim_at(capacity, last_published, state),
    blocked_publication_at: @+model_state:Browser.State ->  @+capacity:Nat -> @+last_published:Nat -> @+problem:String -> blocked_publication_claim_at(Browser.with_lifecycle(Browser.Blocked{problem}, model_state), capacity, last_published, problem),
    publication_current_at: @+capacity:Nat -> @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      @+ready:{Browser.display_ready(state) == True{} : Bool} ->
      {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool} -> publication_current_claim_at(capacity, last_published, state)}

law unmet_frame_status:
  for +model_state: Browser.State
  for +semantic: SurfaceTypes.Surface
  for +frame_generation: Nat
  for +frame: Rendered.Frame
  for +violations: +List<Rendered.Violation>
  for +capacity: View.Capacity
  for +engine: World.Engine
  {Browser.render_status(Browser.with_lifecycle(Browser.Displaying{capacity, engine, semantic}, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_realization(Rendered.Unmet{frame_generation, frame, violations}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state))) == "unmet" : String}

def measuring_lifecycle(lifecycle: Browser.Lifecycle) -> Bool:
  match lifecycle:
    case Browser.Measuring{index, capacity, engine, semantic, round}: True{}
    case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: True{}
    case other: False{}

def measurement_phase(+state: Browser.State) -> Bool:
  +lifecycle = Browser.lifecycle(state)
  measuring_lifecycle(lifecycle)

law measurement_ownership_only_measuring:
  for +ticket: Browser.MeasurementTicket
  for +state: Browser.State
  for owned: {Browser.measurement_owned(ticket, state) == True{} : Bool}
  {measurement_phase(state) == True{} : Bool}

law measurement_request_unavailable:
  for +state: Browser.State
  for inactive: {measurement_phase(state) == False{} : Bool}
  {Browser.measurement_request(state) == None{} : Maybe<&2, Browser.MeasurementRequest>}

law measurement_wrong_round:
  for +model_state: Browser.State
  for +generation: Nat
  for +received_round: Nat
  for +round: Nat
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: SurfaceTypes.Surface
  for same_generation: {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == True{} : Bool}
  for stale_round: {Nat.is_eq(received_round, round) == False{} : Bool}
  {Browser.measurement_owned(Browser.MeasurementTicket{generation, received_round},
    Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) == False{} : Bool}

law measurement_request_canonical:
  for +model_state: Browser.State
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: SurfaceTypes.Surface
  for +round: Nat
  for +generation: Nat
  for +first: Plan.Job
  for +remaining: +List<Plan.Job>
  for awaiting: {World.plan(engine) == Plan.Awaiting{generation, first, remaining} : Plan.Plan}
  {Browser.measurement_request(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
    Some{Browser.MeasurementRequest{Browser.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round},
      Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, Browser.MeasurementRequest>}

def pending_frame_effects_expected_for(lifecycle: Browser.Lifecycle, realization: Rendered.State, displayed: Maybe<&2, Browser.Published>) -> +List<Legacy.Effect>:
  match lifecycle:
    case Browser.Displaying{capacity, engine, semantic}:
      match realization:
        case Rendered.AwaitingFrame{generation}:
          match displayed:
            case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}:
              [Legacy.BrowserEffect{Web.MeasureFrame{physical_generation}}]
            case None{}: Nil{}
        case _: Nil{}
    case Browser.UtilityDisplaying{purpose, engine}:
      match displayed:
        case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, None{}}}: [Legacy.BrowserEffect{Web.MeasureFrame{generation}}]
        case _: Nil{}
    case _: Nil{}

def pending_frame_effects_expected(+state: Browser.State) -> +List<Legacy.Effect>:
  +observed_legacy_1 = Browser.legacy(state)
  +observed_web_2 = Legacy.web(observed_legacy_1)
  +realization = Web.realization(observed_web_2)
  +lifecycle = Browser.lifecycle(state)
  +displayed = Browser.displayed(state)
  pending_frame_effects_expected_for(lifecycle, realization, displayed)

def pending_frame_effects_claim(+state: Browser.State) -> Type:
  {Browser.pending_frame_effects(state) == pending_frame_effects_expected(state) : +List<Legacy.Effect>}

def retained_frame_decision_claim(+first: +List<Legacy.Effect>, +state: Browser.State) -> Type:
  {Browser.accepted(False{}, first, state) == Browser.Decision{state,
    List.append(&2, Legacy.Effect, first, pending_frame_effects_expected(state))} : Browser.Decision}

law pending_frame_effects:
  for +state: Browser.State
  pending_frame_effects_claim(state)

law retained_frame_decision:
  for +first: +List<Legacy.Effect>
  for +state: Browser.State
  retained_frame_decision_claim(first, state)

law evidence:
  Requirements

law selected_infeasible:
  for +failure: Allocation.Failure
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +state: Browser.State
  for +semantic: SurfaceTypes.Surface
  for +round: Nat
  {Browser.selected(Plan.Infeasible{failure}, index, capacity, engine, state, semantic, round) ==
    Browser.infeasible_candidate(Nat.is_lt(index, 3n), index, state, failure) : Browser.Search}

type RecoveryRequirements is Type:
  RecoveryRequirements{
    utility_sources: FrontendUtilityRequirements,
    source_frames: FrameRules.SourceFrameRequirements,
    admitted_document: @+capacity:Nat -> @+lifecycle:Browser.Lifecycle -> @+world:Browser.Published -> @+font:T.Presentation ->
      {Browser.observed_lifecycle_at(capacity, lifecycle, Some{world}, font) == Browser.application_document(Renderer.nodes(Browser.published_world(world))) : Doc.Document},
    empty_without_admission: @+capacity:Nat -> @+lifecycle:Browser.Lifecycle -> @+font:T.Presentation ->
      {Browser.observed_lifecycle_at(capacity, lifecycle, None{}, font) == Browser.application_document(Nil{}) : Doc.Document},
    utility_publication: @+model_state:Browser.State ->  @+world:Content.AllocatedWorld -> @+purpose:Utility.Purpose -> @+engine:World.Engine -> {Browser.utility_publish(world, purpose, engine, model_state) ==
        Browser.Decision{Browser.with_displayed(Some{Browser.Published{world, Browser.current_legacy_surface(Browser.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, Browser.with_lifecycle(Browser.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : Browser.Decision},
    correlated_frame: @+model_state:Browser.State ->  @+frame:Rendered.Frame -> @+world:Content.AllocatedWorld -> @+semantic:SurfaceTypes.Surface -> @+scope:Focus.Scope -> @+basis:Native.Basis -> @+old:Maybe<&2, Rendered.Frame> ->
      {Browser.correlated_frame_owned(True{}, frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) ==
        Browser.utility_frame_result(SourceFrame.check(world, frame), frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision},
    ready_admission: @+world:Content.AllocatedWorld -> @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+glyph_only:Bool -> @+state:Browser.State ->
      {Browser.utility_selected(Plan.Ready{world}, purpose, engine, round, glyph_only, state) == Browser.utility_publish(world, purpose, engine, state) : Browser.Decision},
    correlated_measurement_failure: @+model_state:Browser.State ->  @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+reason:String ->
      {Browser.utility_measurement_failure(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        Browser.utility_fallback(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : Browser.Decision},
    valid_frame: @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.utility_frame_result(Nil{}, frame, state) == Browser.Decision{Browser.frame_capture(frame, state), Nil{}} : Browser.Decision},
    rejected_frame: @+model_state:Browser.State ->  @+first:Rendered.Violation -> @+rest:+List<Rendered.Violation> -> @+frame:Rendered.Frame -> {Browser.utility_frame_result(first <> rest, frame, model_state) ==
        Browser.Decision{Browser.with_displayed(None{}, Browser.with_lifecycle(Browser.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : Browser.Decision},
    retry_dispatch: @+state:Browser.State ->
      {Browser.activate("@browser/retry", state) == Browser.accept(True{}, Legacy.activate("@browser/retry", Browser.legacy(state)), state) : Browser.Decision},
    retry_mount: @+state:Legacy.State ->
      {Legacy.activate("@browser/retry", state) == Legacy.native(Web.Mount{}, state) : Legacy.Decision},
    document_focus: @+input:Web.Input -> @+state:Browser.State ->
      {Browser.auxiliary_focus_owned(True{}, input, state) == Browser.Decision{state, Nil{}} : Browser.Decision}}

law recovery_evidence:
  RecoveryRequirements

law changed_capacity_product:
  for decision: Platform.Decision
  for capacity: View.Capacity
  {Platform.decision_product(Platform.changed_capacity(decision, capacity)) == Platform.decision_product(decision) : InteractionTypes.Decision}

law retained_capacity_product:
  for same: Bool
  for +decision: Platform.Decision
  for capacity: View.Capacity
  {Platform.decision_product(Platform.retained_capacity(same, decision, capacity)) == Platform.decision_product(decision) : InteractionTypes.Decision}

law reflow_preserves_product:
  for +decision: Platform.Decision
  for +capacity: View.Capacity
  {Platform.decision_product(Platform.reflow_capacity(decision, capacity)) == Platform.decision_product(decision) : InteractionTypes.Decision}

# Product focus is resolved against the returned state; other effects retain order.

def loss_effects(core: InteractionTypes.State, +platform: Platform.Platform, target: Focus.Target) -> +List<Platform.Effect>:
  match target:
    case Focus.Product{identity}: expected_focus(InterfaceView.focus_target(InterfaceView.observe(capacity(platform), core), identity), ticket(platform))
    case Focus.Content{owner, identity}: [Platform.Focus{ticket(platform), Focus.Content{owner, identity}}]

law failed_focus_receipt:
  for +model_state: Platform.State
  for +received: Nat
  for +target: Focus.Target
  for +observed: Maybe<&2, Focus.Target>
  for failed: {Platform.focus_confirmed(target, observed) == False{} : Bool}
  {Platform.step(Platform.FocusApplied{received, target, observed}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), Nil{}} : Platform.Decision}

law publication_focus_after_some:
  for +model_state: Platform.State
  for +received: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Focus.Target
  {Platform.step(Platform.PublicationFocusObserved{received, before, Some{after}}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), Nil{}} : Platform.Decision}

law publication_focus_before_none:
  for +model_state: Platform.State
  for +received: Nat
  for +after: Maybe<&2, Focus.Target>
  {Platform.step(Platform.PublicationFocusObserved{received, None{}, after}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), Nil{}} : Platform.Decision}

law publication_focus_stale:
  for +model_state: Platform.State
  for +received: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  for stale: {Nat.is_eq(received, ticket(Platform.platform(model_state))) == False{} : Bool}
  {Platform.step(Platform.PublicationFocusObserved{received, before, after}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), Nil{}} : Platform.Decision}

law publication_focus_inactive:
  for +model_state: Platform.State
  for +received: Nat
  for +target: Focus.Target
  for inactive: {Platform.active_target(Platform.core(model_state), capacity(Platform.platform(model_state)), target) == False{} : Bool}
  {Platform.step(Platform.PublicationFocusObserved{received, Some{target}, None{}}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), Nil{}} : Platform.Decision}

law publication_focus_loss:
  for +model_state: Platform.State
  for +received: Nat
  for +target: Focus.Target
  for current: {Nat.is_eq(received, ticket(Platform.platform(model_state))) == True{} : Bool}
  for active: {Platform.active_target(Platform.core(model_state), capacity(Platform.platform(model_state)), target) == True{} : Bool}
  {Platform.step(Platform.PublicationFocusObserved{received, Some{target}, None{}}, model_state) == Platform.Decision{Platform.unchanged(Platform.core(model_state)), Platform.platform(model_state), loss_effects(Platform.core(model_state), Platform.platform(model_state), target)} : Platform.Decision}
