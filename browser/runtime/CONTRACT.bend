import ../appearance/DESIGN.bend as Design
import ../../interaction/conversation/OUTPUT.bend as Live
import ../controls/NAVIGATION.bend as Navigation
import ../../interaction/experience/MODEL.bend as UXTypes
import Base
import ../model-rules.bend as WebRules
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/interactive_markdown/TYPES.bend as IM
import ../../interaction/interactive_markdown/SCENE.bend as IMScene
import ../../interaction/interactive_markdown/SYNTAX.bend as IMSyntax
import ../../interaction/STATE.bend as ProductState
import ../layout/ADAPTATION.bend as Adaptation
import ../layout/natural-size.bend as NaturalSize
import ../../bendlib/categories.bend as Categories
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as AnchorGeometry
import ../focus/MODEL.bend as Focus
import ../focus/CONTRACT.bend as FocusRules
import ../controls/GEOMETRY.bend as NativeGeometry
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
import ../../interaction/submission/field-options.bend as FieldOptions
import ../../interaction/services/CONTEXT.bend as Context
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
import ../document/SPEC.bend as FrameSpec
import ../editor/MODEL.bend as Editor
import ../../harness/features/MODEL.bend as F2
import ../controls/PROGRAM.bend as Controls2

def unchanged_claim(+value: String, +record: Native.Record) -> Type:
  {Native.step(Native.Synchronize{value}, record) == Native.Decision{record, False{}, False{}} : Native.Decision}

def unmatched_claim(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) -> Type:
  {Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})) == Nil{} : +List<Native.Update>}

def matching_claim(+binding: Native.Binding, +node: SurfaceTypes.Node) -> Type:
  Native.Binding{key, kind, identity, original} = binding
  SurfaceTypes.Node{current, semantic, label, role, meaning, children} = node
  {Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, Some{node}})) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}

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

def required_scalar_value(value: J.Json) -> String:
  match value:
    case J.Text{text}: text
    case J.Number{text}: text
    case J.Boolean{value}: Bool.show(value)
    case _: ""

def required_local_value(+tag: String, raw: String, canonical: J.Json) -> String:
  Bool.pick(String, (String.eq(tag, "slider") || String.eq(tag, "select")) || String.eq(tag, "checkbox"),
    required_scalar_value(canonical), raw)

def required_origin_value(origin: Context.Origin) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{project}: "project/" ++ Nat.show(project)
    case Context.ParentTask{task}: "parent/" ++ Nat.show(task)
    case Context.ProjectForParent{task, project}: "project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project)

def required_workspace_primary(workspace: Context.WorkspaceValue) -> String:
  match workspace:
    case Context.InheritedWorkspace{D.Workspace{roots, primary}}: FieldOptions.optional_text(primary)
    case Context.EnteredWorkspace{D.Workspace{roots, primary}}: FieldOptions.optional_text(primary)

def required_network_value(sandbox: Context.SandboxValue) -> String:
  match sandbox:
    case Context.InheritedSandbox{D.Sandbox{mode, network}}: FieldOptions.boolean(network)
    case Context.ChosenSandbox{D.Sandbox{mode, network}}: FieldOptions.boolean(network)

def required_context_value(field: Forms.Field, origin: Context.Origin, workspace: Context.WorkspaceValue,
  sandbox: Context.SandboxValue, approval: Context.ApprovalValue) -> String:
  match field:
    case Forms.ContextOrigin{}: required_origin_value(origin)
    case Forms.WorkspaceDirectories{}: FieldOptions.workspace_text(workspace)
    case Forms.WorkspacePrimary{}: required_workspace_primary(workspace)
    case Forms.SandboxMode{}: FieldOptions.sandbox_text(sandbox)
    case Forms.NetworkAccess{}: required_network_value(sandbox)
    case Forms.ApprovalPolicy{}: Context.approval_option(Context.observed_approval(approval))
    case Forms.ApprovalReviewer{}: Context.approval_option(Context.observed_approval(approval))
    case _: ""

def required_workspace_value(field: Forms.Field, roots: +List<String>, primary: Maybe<&2, String>) -> String:
  match field:
    case Forms.WorkspacePrimary{}: FieldOptions.optional_text(primary)
    case _: FieldOptions.joined(roots)

def required_model_value(field: Forms.Field, profile: String, reasoning: String) -> String:
  match field:
    case Forms.ReasoningEffort{}: reasoning
    case _: profile

def required_edit_value(field: Forms.Field, value: Forms.Observed) -> String:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}:
      required_context_value(field, origin, workspace, sandbox, approval)
    case Forms.WorkspaceValue{D.Workspace{roots, primary}}: required_workspace_value(field, roots, primary)
    case Forms.ModelValue{profile, reasoning}: required_model_value(field, profile, reasoning)
    case other: FieldOptions.observed(other)

def required_native_value(meaning: SurfaceTypes.Meaning) -> String:
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, IM.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: required_local_value(tag, raw, canonical)
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: required_edit_value(field, value)
    case SurfaceTypes.BoardSearch{B.Filter{view, search, status, priority, date, assignee, creator, project, label}}: search
    case SurfaceTypes.SearchChoices{query}: query
    case SurfaceTypes.EnterDirectory{editor, text}: text
    case SurfaceTypes.DirectoryBrowserLocation{value}: value
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: selected
    case _: ""

def required_checked(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, IM.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: J.boolean(canonical)
    case SurfaceTypes.Edit{editor, field, entry, Forms.ToggleValue{enabled}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{enabled, profile}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{D.Sandbox{mode, enabled}}, approval, guidance}, reviewers}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{D.Sandbox{mode, enabled}}, approval, guidance}, reviewers}, choices}: enabled
    case _: False{}

def checkbox_claim(+key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) -> Type:
  {Native.projected(key, Source.ToggleField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, required_checked(meaning)}] : +List<Native.Update>}

def text_claim(+key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) -> Type:
  {Native.projected(key, Source.TextField{}, semantic, meaning) == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, required_native_value(meaning)}] : +List<Native.Update>}

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

def required_rejected_session(session: Native.Session) -> Native.Session:
  match session:
    case Native.Idle{}: Native.Idle{}
    case Native.Composing{}: Native.SupersededComposing{}
    case Native.SupersededComposing{}: Native.SupersededComposing{}
    case Native.SupersededTail{}: Native.SupersededTail{}

def rejected_buffer_claim(+value: String, +record: Native.Record) -> Type:
  Native.Record{identity, canonical, session} = record
  {Native.step(Native.Reject{value}, record) ==
    Native.Decision{Native.Record{identity, Some{value}, required_rejected_session(session)}, False{}, True{}} : Native.Decision}

def rejected_equal_buffer_claim(+identity: Maybe<&2, Native.Identity>, +value: String, +session: Native.Session) -> Type:
  {Native.step(Native.Reject{value}, Native.Record{identity, Some{value}, session}) ==
    Native.Decision{Native.Record{identity, Some{value}, required_rejected_session(session)}, False{}, True{}} : Native.Decision}

def rejected_composing_buffer_claim(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String) -> Type:
  {Native.step(Native.Reject{value}, Native.Record{identity, old, Native.Composing{}}) ==
    Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}

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
    rejected_buffer: @+value:String -> @+record:Native.Record -> rejected_buffer_claim(value, record),
    rejected_equal_buffer: @+identity:Maybe<&2, Native.Identity> -> @+value:String -> @+session:Native.Session -> rejected_equal_buffer_claim(identity, value, session),
    rejected_composing_buffer: @+identity:Maybe<&2, Native.Identity> -> @+old:Maybe<&2, String> -> @+value:String -> rejected_composing_buffer_claim(identity, old, value),
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
    Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{Native.Binding{key, kind, semantic, meaning}, InterfaceView.find_node(nodes, key)})) : +List<Native.Update>}

def field_projection(kind: Source.NativeFieldKind, key: String, semantic: String, meaning: SurfaceTypes.Meaning, actual: +List<Native.Update>) -> Type:
  match kind:
    case Source.ToggleField{}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, required_checked(meaning)}] : +List<Native.Update>}
    case Source.FileField{multiple}: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}] : +List<Native.Update>}
    case _: {actual == [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, required_native_value(meaning)}] : +List<Native.Update>}

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

law edit_structured_text_rejected:
  for +key: String
  for +text: String
  for +parsed: Maybe<&2, J.Json>
  for +state: Browser.State
  for owned: {Browser.structured_text_owned(key, state) == False{} : Bool}
  {Browser.edit_structured_text(key, text, parsed, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law edit_structured_text_accepted:
  for +key: String
  for +text: String
  for +parsed: Maybe<&2, J.Json>
  for +state: Browser.State
  for owned: {Browser.structured_text_owned(key, state) == True{} : Bool}
  {Browser.edit_structured_text(key, text, parsed, state) == Browser.accept(True{}, Legacy.edit_structured_text(key, text, parsed, Browser.legacy(state)), state) : Browser.Decision}

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
  {Browser.frame_forward_calculation(Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state), frame) ==
    Browser.accept(False{}, Legacy.observe_frame_with(Browser.semantic_generation(Browser.legacy(model_state)), semantic, frame, Browser.legacy(model_state), SourceFrame.expectations(world, frame)),
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

def required_source_state(state: Browser.State) -> Browser.State:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{+latest, active, published, semantic_latest}} = state
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{(latest + 1n : Nat), active, published, (latest + 1n : Nat)}}

def required_presentation_state(state: Browser.State) -> Browser.State:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, active, published, semantic_latest}} = state
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{(latest + 1n : Nat), active, published, semantic_latest}}

def required_semantic_pending(state: Browser.State) -> Bool:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, active, published, semantic_latest}} = state
  Nat.is_lt(published, semantic_latest)

def required_active_semantic_pending(state: Browser.State) -> Bool:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, active, published, semantic_latest}} = state
  Nat.is_lt(active, semantic_latest)

def required_source_update(lifecycle: Browser.Lifecycle, first: +List<Legacy.Effect>, state: Browser.State) -> Browser.Decision:
  match lifecycle:
    case Browser.Measuring{index, capacity, engine, semantic, round}: Browser.Decision{state, first}
    case _: Browser.append(first, Browser.build(0n, state))

def rebuilt_frame_decision_claim(+first: +List<Legacy.Effect>, +state: Browser.State) -> Type:
  {Browser.accepted(True{}, first, state) == required_source_update(Browser.lifecycle(state), first, required_source_state(state)) : Browser.Decision}

def required_dismissal(meaning: SurfaceTypes.Meaning, key: UIIdentity.Key,
  fallback: Maybe<&2, Legacy.DismissTarget>) -> Maybe<&2, Legacy.DismissTarget>:
  match meaning:
    case SurfaceTypes.LayerRegion{input, outside, escape}: Some{Legacy.DismissTarget{UIIdentity.encode(key), input, outside, escape}}
    case SurfaceTypes.ActivityGroup{activity, input, outside, escape}: Some{Legacy.DismissTarget{UIIdentity.encode(key), input, outside, escape}}
    case _: fallback

def required_dismiss_target(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, Legacy.DismissTarget>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      required_dismissal(meaning, key,
        Maybe.or(&2, Legacy.DismissTarget, required_dismiss_target(children), required_dismiss_target(rest)))

def inspection_frame_expected(frame: Maybe<&2, Rendered.Frame>, +active: +List<SurfaceTypes.Node>, +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Legacy.DismissTarget>) -> Browser.RenderInspection:
  match frame:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, layer, dismiss}
    case Some{+observed}:
      Rendered.Frame{viewport, elements, focused, tabs, native_focus} = observed
      Browser.RenderInspection{Some{observed}, Some{FrameSpec.expected_tabs(active, elements, native_focus)},
        Some{FrameSpec.native_valid(native_focus, active, elements)}, layer, dismiss}

def inspection_frame(realization: Rendered.State) -> Maybe<&2, Rendered.Frame>:
  match realization:
    case Rendered.AwaitingFrame{generation}: None{}
    case Rendered.Realized{generation, frame}: Some{frame}
    case Rendered.Unmet{generation, frame, violations}: Some{frame}

def inspection_display_expected(+frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{frame, None{}, None{}, layer, None{}}
    case Some{Browser.Published{world, semantic, scope, basis, published_frame}}:
      +active = FocusRules.required_active_nodes(semantic)
      +dismiss = required_dismiss_target(active)
      inspection_frame_expected(frame, active, layer, dismiss)

# Foreground services shield the underlying interaction. Detail panels do not.
def required_layer_owner(layers: +List<View.Layer>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match layers:
    case Nil{}: fallback
    case Con{View.Layer{View.ModalDialog{}, content, initial, restore, dismissal}, rest}:
      Some{UIIdentity.encode(UIIdentity.Entity{UIIdentity.Place{"/layers"}, "layer", initial})}
    case Con{View.Layer{View.AnchoredMenu{}, content, initial, restore, dismissal}, rest}:
      Some{UIIdentity.encode(UIIdentity.Entity{UIIdentity.Place{"/layers"}, "layer", initial})}
    case Con{other, rest}: required_layer_owner(rest, fallback)

def required_navigation_owner(arrangement: View.Arrangement) -> Maybe<&2, String>:
  match arrangement:
    case View.Arrangement{View.ModalNavigation{}}: Some{UIIdentity.encode(UIIdentity.Place{"/navigation"})}
    case _: None{}

def required_settings_owner(open: Bool, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match open:
    case True{}: Some{UIIdentity.encode(UIIdentity.Place{"/layers/settings"})}
    case False{}: fallback

def required_directory_owner(picker: Services.DirectoryPicker, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match picker:
    case Services.NoDirectoryPicker{}: fallback
    case _: Some{UIIdentity.encode(UIIdentity.Place{"/layers/directory-picker"})}

def required_preview_owner(preview: Services.Preview, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match preview:
    case Services.NoPreview{}: fallback
    case _: Some{UIIdentity.encode(UIIdentity.Place{"/layers/attachment-preview"})}

def required_foreground_owner(scene: InteractionTypes.Scene) -> Maybe<&2, String>:
  InteractionTypes.Scene{View.Scene{nav, main, layers, arrangement, attention}, InteractionTypes.Settings{open, access, appearance, open_action, close_action, connect_action}, transfers, preview, code, picker} = scene
  required_preview_owner(preview, required_directory_owner(picker,
    required_settings_owner(open, required_layer_owner(layers, required_navigation_owner(arrangement)))))

def surface_owner(surface: SurfaceTypes.Surface) -> Maybe<&2, String>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  scope

law assembled_foreground_owner:
  for +scene: InteractionTypes.Scene
  for +state: InteractionTypes.State
  {surface_owner(InterfaceView.assemble(scene, state)) == required_foreground_owner(scene) : Maybe<&2, String>}

law scene_foreground_owner:
  for +scene: InteractionTypes.Scene
  for state: InteractionTypes.State
  {InterfaceView.assembled_scope(scene, state) == required_foreground_owner(scene) : Maybe<&2, String>}

def required_current_layer_key(+stored: Legacy.State) -> Maybe<&2, String>:
  +application = Web.application(Legacy.web(stored))
  required_foreground_owner(ProductState.observe(Web.capacity(Platform.platform(application)), Platform.core(application)))

law current_foreground_owner:
  for +stored: Legacy.State
  {Legacy.current_layer_key(stored) == required_current_layer_key(stored) : Maybe<&2, String>}

def inspection_expected(+stored: Legacy.State, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  +observed_web_1 = Legacy.web(stored)
  +realization = Web.realization(observed_web_1)
  +layer = required_current_layer_key(stored)
  inspection_display_expected(inspection_frame(realization), layer, displayed)

def inspection_utility_expected(displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, None{}, None{}}
    case Some{Browser.Published{+world, semantic, scope, basis, frame}}:
      Browser.RenderInspection{frame, Some{FrameSpec.allocated_tabs(FrameSpec.allocated_expected(world))}, Some{FrameSpec.allocated_no_native(world)}, None{}, None{}}

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
    rejected_draft: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @directory_entry:String -> @submitted:Nat -> @+reason:String ->
      {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted,
          D.failure("command_not_submitted", reason)) ==
          U.Draft{revision, body, E.command_rejection_feedback(body, submitted, D.failure("command_not_submitted", reason)), directory_entry} : U.Draft},
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

def publication_pending(+last_published: Nat, +state: Browser.State) -> Bool:
  +lifecycle = Browser.lifecycle(state)
  pending_lifecycle(lifecycle) && Browser.display_ready(state) &&
    Nat.is_eq(Browser.displayed_generation(state), last_published)

def blocked_publication_claim_at(+model_state: Browser.State, +capacity: Nat, +last_published: Nat, +problem: String) -> Type:
  {Browser.publication(capacity, last_published, Browser.with_lifecycle(Browser.Blocked{problem}, model_state)) ==
    Browser.publication_policy_at(capacity, last_published,
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
      {publication_pending(last_published, state) == True{} : Bool} -> publication_preserves_pending_claim_at(capacity, last_published, state),
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

def observed_accept_expected(+next: Legacy.State, +first: +List<Legacy.Effect>, state: Browser.State) -> Browser.Decision:
  match state:
    case Browser.State{previous, +serial, +anchors, +lifecycle, +displayed, +attention, +updates}:
      Browser.Decision{Browser.State{next, serial, anchors, lifecycle, displayed, attention, updates},
        List.append(&2, Legacy.Effect, first,
          pending_frame_effects_expected(Browser.State{next, serial, anchors, lifecycle, displayed, attention, updates}))}

law non_rebuild_preserves_observed_decision:
  for +next: Legacy.State
  for +first: +List<Legacy.Effect>
  for +state: Browser.State
  {Browser.accept(False{}, Legacy.Decision{next, first}, state) ==
    observed_accept_expected(next, first, state) : Browser.Decision}

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
    Browser.infeasible_candidate(Nat.is_lt(index, 7n), index, state, failure) : Browser.Search}

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
        Browser.utility_frame_result(world, frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision},
    ready_admission: @+world:Content.AllocatedWorld -> @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+glyph_only:Bool -> @+state:Browser.State ->
      {Browser.utility_selected(Plan.Ready{world}, purpose, engine, round, glyph_only, state) == Browser.utility_publish(world, purpose, engine, state) : Browser.Decision},
    correlated_measurement_failure: @+model_state:Browser.State ->  @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+reason:String ->
      {Browser.utility_measurement_failure(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        Browser.utility_fallback(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : Browser.Decision},
    valid_frame: @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.utility_frame_calculation(frame, state) == Browser.Decision{Browser.frame_capture(frame, state), Nil{}} : Browser.Decision},
    rejected_frame: @+model_state:Browser.State ->  @+first:Rendered.Violation -> @+rest:+List<Rendered.Violation> -> @+frame:Rendered.Frame -> {Browser.utility_frame_rejection(model_state) ==
        Browser.Decision{Browser.with_displayed(None{}, Browser.with_lifecycle(Browser.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : Browser.Decision},
    retry_dispatch: @+state:Browser.State ->
      {Browser.activate("@browser/retry", state) == Browser.accept(True{}, Legacy.activate("@browser/retry", Browser.legacy(state)), state) : Browser.Decision},
    retry_mount: @+state:Legacy.State ->
      {Legacy.activate("@browser/retry", state) == Legacy.native(Web.Mount{}, state) : Legacy.Decision},
    document_focus: @+input:Web.Input -> @+state:Browser.State ->
      {Browser.auxiliary_focus_admitted(None{}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}}

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

def supporting_mask(blocked: Bool, +support: UXTypes.Support, +property: UXTypes.Property, +input: InteractionTypes.Input, +availability: View.Availability) -> Type:
  match blocked:
    case True{}: {Legacy.mask_meaning(blocked, SurfaceTypes.SupportingControl{support, property, input, availability}) == SurfaceTypes.SupportingControl{support, property, input, View.Unavailable{"Request pending"}} : SurfaceTypes.Meaning}
    case False{}: {Legacy.mask_meaning(blocked, SurfaceTypes.SupportingControl{support, property, input, availability}) == SurfaceTypes.SupportingControl{support, property, input, availability} : SurfaceTypes.Meaning}

law supporting_mask_evidence:
  for blocked: Bool
  for +support: UXTypes.Support
  for +property: UXTypes.Property
  for +input: InteractionTypes.Input
  for +availability: View.Availability
  supporting_mask(blocked, support, property, input, availability)

# A full form compares its real one-line demand with its allocated inner room.
type SupportingAdmissionRequirements is Type:
  SupportingAdmissionRequirements{
    missing_full: {Browser.supporting_width_admitted(Controls2.FullSupporting{}, None{}) == True{} : Bool},
    full_room: @+available:Nat -> @+preferred:Nat ->
      {Browser.supporting_width_admitted(Controls2.FullSupporting{}, Some{Adaptation.RegionDemand{available, preferred}}) == Nat.is_le(preferred, available) : Bool},
    compact_ready: @requirement:Maybe<&2, Adaptation.RegionDemand> ->
      {Browser.supporting_width_admitted(Controls2.CompactSupporting{}, requirement) == True{} : Bool},
    complete_observation: @+index:Nat -> @+world:Content.AllocatedWorld ->
      {Browser.supporting_admitted(index, world) == Browser.supporting_width_admitted(Browser.candidate_form(index), Adaptation.world_region_demand(world, Adaptation.RegionAttribute{"allocated-region", "supporting-controls"})) : Bool},
    ready: @+world:Content.AllocatedWorld -> @+index:Nat -> @+capacity:View.Capacity -> @+engine:World.Engine -> @+state:Browser.State -> @+semantic:SurfaceTypes.Surface -> @round:Nat ->
      {Browser.selected(Plan.Ready{world}, index, capacity, engine, state, semantic, round) == Browser.selected_supporting(Browser.supporting_admitted(index, world), world, index, capacity, engine, state, semantic) : Browser.Search},
    admitted: @+world:Content.AllocatedWorld -> @index:Nat -> @+capacity:View.Capacity -> @+engine:World.Engine -> @+state:Browser.State -> @+semantic:SurfaceTypes.Surface ->
      {Browser.selected_supporting(True{}, world, index, capacity, engine, state, semantic) == Browser.Stopped{Browser.admit(world, capacity, engine, state, semantic)} : Browser.Search},
    rejected: @world:Content.AllocatedWorld -> @+index:Nat -> @capacity:View.Capacity -> @engine:World.Engine -> @+state:Browser.State -> @semantic:SurfaceTypes.Surface ->
      {Browser.selected_supporting(False{}, world, index, capacity, engine, state, semantic) == Browser.supporting_retry(Nat.is_lt(index, 7n), index, state) : Browser.Search},
    terminal: @+index:Nat -> @+state:Browser.State -> {Browser.supporting_retry(False{}, index, state) == Browser.Stopped{Browser.no_candidate(state)} : Browser.Search}}

law supporting_admission_evidence:
  SupportingAdmissionRequirements

def fresh_attention_phase(phase: Browser.Lifecycle, +state: Browser.State) -> Type:
  match phase:
    case Browser.Displaying{capacity, engine, semantic}:
      {Browser.attention_refresh(state) == Browser.build(0n, state) : Browser.Decision}
    case Browser.Measuring{index, capacity, engine, semantic, round}:
      {Browser.attention_refresh(state) == Browser.Decision{state, Nil{}} : Browser.Decision}
    case _:
      {Browser.attention_refresh(state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def fresh_attention_candidate(+state: Browser.State) -> Type:
  fresh_attention_phase(Browser.presentation_phase(state), state)

type NavigationRequirements is Type:
  NavigationRequirements{
    interest_keeps_legacy: @+attention:Navigation.Attention -> @+state:Browser.State ->
      {Browser.legacy(Browser.with_attention(attention, state)) == Browser.legacy(state) : Legacy.State},
    invalid_owner: @+attention:Navigation.Attention -> @+state:Browser.State ->
      {Browser.attention_change(False{}, attention, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    identical_interest: @+attention:Navigation.Attention -> @+state:Browser.State ->
      {Browser.attention_changed(False{}, attention, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    fresh_layout_derivation: @+state:Browser.State -> fresh_attention_candidate(state)}

law navigation_evidence:
  NavigationRequirements

law reviewer_field_gesture:
  @editor:U.Editor -> @entry:Forms.Entry -> @value:Forms.Observed -> @+text:String -> @state:Legacy.State ->
    {Legacy.field_text(editor, Forms.ApprovalReviewer{}, entry, value, text, state) == Legacy.approval_gesture(text) : Maybe<&2, SurfaceTypes.Gesture>}


law role_calibration_request:
  @+capacity:Nat -> @+state:Browser.State ->
  {Browser.measurement_plan_at(capacity, state) == F.request_at(capacity, Browser.current_font(Browser.legacy(state)), F.activity_specifications(capacity, F.scale(Browser.current_font(Browser.legacy(state))))) : F.Plan}

law missing_activity_calibration_waits:
  @physical_capacity:Nat -> @body:T.Metric -> @+index:Nat -> @+state:Browser.State ->
  {Browser.calibrated_activity_metrics_at(physical_capacity, body, None{}, index, state) == Browser.Stopped{Browser.Decision{Browser.set_lifecycle(state, Browser.WaitingFont{}), Nil{}}} : Browser.Search}

law actual_activity_calibration:
  @+physical_capacity:Nat -> @body:T.Metric -> @primary:T.Metric -> @support:T.Metric -> @+index:Nat -> @+state:Browser.State ->
  {Browser.calibrated_activity_metrics_at(physical_capacity, body, Some{F.ActivityMetrics{primary, support}}, index, state) == Browser.calibrated_parameters_at(physical_capacity, Design.parameters(physical_capacity, F.scale(Browser.current_font(Browser.legacy(state))), body, primary, support), index, state) : Browser.Search}


def required_freeze_state(state: Browser.State) -> Browser.State:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{+latest, active, published, semantic_latest}} = state
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, latest, published, semantic_latest}}

def required_publish_state(state: Browser.State) -> Browser.State:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, +active, published, semantic_latest}} = state
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{latest, active, active, semantic_latest}}

law frozen_candidate_captures_latest_update:
  for +state: Browser.State
  {Browser.freeze_update(state) == required_freeze_state(state) : Browser.State}

law admitted_candidate_marks_active_update:
  for +state: Browser.State
  {Browser.publish_update(state) == required_publish_state(state) : Browser.State}

law completed_display_remains_ready_while_measuring:
  for +state: Browser.State
  for +published: Browser.Published
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: SurfaceTypes.Surface
  for +round: Nat
  {Browser.display_ready(Browser.with_displayed(Some{published}, Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, state))) == True{} : Bool}

law remeasurement_retains_active_candidate:
  for +state: Browser.State
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: SurfaceTypes.Surface
  for +round: Nat
  {Browser.remeasure(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, state)) ==
    Browser.Decision{Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, state), Nil{}} : Browser.Decision}

def required_invalidated_state(state: Browser.State) -> Browser.State:
  Browser.State{legacy, generation, anchors, lifecycle, displayed, attention, updates} = state
  Browser.State{legacy, generation, anchors, Browser.WaitingEnvironment{}, None{}, attention, updates}

law invalidation_discards_active_and_displayed:
  for +state: Browser.State
  {Browser.invalidate_display(state) == required_invalidated_state(state) : Browser.State}

# Refresh transactions interpret product, focus and physical-commit meanings.
# Their IO is delivered in order; no accepted command is silently discarded.
def refresh_session(stored: Legacy.State) -> E.Session:
  E.session(ProductState.application(Platform.core(Web.application(Legacy.web(stored)))))

def refresh_namespace(state: Browser.State) -> String:
  E.namespace(refresh_session(Browser.legacy(state)))

def refresh_stored_access(stored: Legacy.State) -> Services.Access:
  Services.access(ProductState.services(Platform.core(Web.application(Legacy.web(stored)))))

def refresh_access(state: Browser.State) -> Services.Access:
  refresh_stored_access(Browser.legacy(state))

def refresh_allowed(state: Browser.State) -> Bool:
  E.interactive_allowed(refresh_session(Browser.legacy(state)))

def connecting_ticket(access: Services.Access, ticket: Nat) -> Bool:
  match access:
    case Services.Connecting{expected}: Nat.is_eq(expected, ticket)
    case _: False{}

def authentication_owner(namespace: String, ticket: Nat, +state: Browser.State) -> Bool:
  String.eq(namespace, refresh_namespace(state)) && connecting_ticket(refresh_access(state), ticket)

def failure_owner(+namespace: String, sequence: Nat, authentication: Maybe<&2, Nat>, +state: Browser.State) -> Bool:
  match authentication:
    case None{}: String.eq(namespace, refresh_namespace(state)) && Nat.is_eq(sequence, Legacy.sequence(Browser.legacy(state)))
    case Some{ticket}: authentication_owner(namespace, ticket, state)

def failure_sequence(authentication: Maybe<&2, Nat>, sequence: Nat, state: Browser.State) -> Nat:
  match authentication:
    case None{}: sequence
    case Some{ticket}: Legacy.sequence(Browser.legacy(state))

def refresh_command_matches(+wire: J.Json, entry: Legacy.Pending) -> Bool:
  Legacy.Pending{ticket, completion, command, origin, status} = entry
  J.same(command, wire)

def refresh_command_present(+wire: J.Json, pending: +List<Legacy.Pending>) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{entry, rest}: refresh_command_matches(wire, entry) || refresh_command_present(wire, rest)

def expected_realized_decision(decision: Platform.Decision) -> Platform.Decision:
  Platform.Decision{InteractionTypes.Decision{+core, +reply, +runtime, +interaction, +services, +durable},
    Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}, +source} = decision
  Platform.Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable},
    Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope},
    expected_effects(InterfaceView.observe(capacity, core), source)}

def refreshed_platform(input: Product.Input, state: Platform.State) -> Platform.Decision:
  Platform.State{core, platform} = state
  expected_realized_decision(Platform.after_core(Product.step(input, core), platform))

def refresh_duplicate_delivered(value: Web.Decision, sequence: Nat, ticket: Nat,
  pending: +List<Legacy.Pending>, receipt: Maybe<&2, Receipt.Receipt>) -> Legacy.Decision:
  Web.Decision{web, InteractionTypes.Decision{core, reply, runtime, interaction, services, durable}, effects} = value
  Legacy.Decision{Legacy.State{web, sequence, ticket, pending, receipt},
    List.append(&2, Legacy.Effect,
      List.foldr(~&2, ~Web.Effect, ~(+List<Legacy.Effect>), ~(effect => rest => Legacy.BrowserEffect{effect} <> rest), effects, Nil{}),
      List.foldr(~&2, ~Services.Effect, ~(+List<Legacy.Effect>), ~(effect => rest => Legacy.Service{effect} <> rest), services, Nil{}))}

# A duplicate wire cannot issue a second command. The second interactive
# request must nevertheless settle its own captured feedback correlation.
def refresh_duplicate_request(completion: E.Completion, stored: Legacy.State) -> Legacy.Decision:
  match completion stored:
    case E.InteractiveCompletion{owner, path, feedback} Legacy.State{+web, sequence, ticket, pending, receipt}:
      refresh_duplicate_delivered(WebRules.committed_decision(refreshed_platform(Product.InterfaceInput{
        InteractionTypes.Interactive{IM.EffectCompleted{owner, path, feedback, False{}, "This command is already pending"}}}, Web.application(web)),
        (Web.generation(web) + 1n : Nat), Web.environment(web), Web.typography(web)), sequence, ticket, pending, receipt)
    case _ state: Legacy.Decision{state, Nil{}}

def refresh_command(duplicate: Bool, +wire: J.Json, completion: E.Completion, origin: String, state: Legacy.State) -> Legacy.Decision:
  match duplicate state:
    case True{} stored: refresh_duplicate_request(completion, stored)
    case False{} Legacy.State{web, sequence, +ticket, pending, receipt}:
      Legacy.Decision{Legacy.State{web, sequence, (ticket + 1n : Nat),
        List.append(&2, Legacy.Pending, pending, [Legacy.Pending{ticket, completion, wire, origin, Legacy.AwaitingReceipt{}}]), None{}},
        [Legacy.Command{ticket, wire}]}

def refresh_io(effect: E.Effect, origin: String, +stored: Legacy.State) -> Legacy.Decision:
  match effect:
    case E.RequestCommand{command, completion}:
      +wire = Request.client(Codec.command_json(command))
      refresh_command(refresh_command_present(wire, Legacy.pending(stored)), wire, completion, origin, stored)
    case E.InteractiveEffect{effect}: Legacy.Decision{stored, [Legacy.InteractiveEffect{effect}]}
    case E.ObserveInteractiveMarkdown{document}: Legacy.Decision{stored, [Legacy.ObserveInteractiveMarkdown{document}]}
    case E.ForgetInteractiveMarkdown{key}: Legacy.Decision{stored, [Legacy.ForgetInteractiveMarkdown{key}]}
    case E.PersistModelPreference{profile, reasoning}: Legacy.Decision{stored, [Legacy.PersistModelPreference{profile, reasoning}]}
    case E.ObserveDirectories{ticket, entered}: Legacy.Decision{stored, [Legacy.Directories{ticket, entered}]}
    case _: Legacy.Decision{stored, Nil{}}

def refresh_append(value: Legacy.Decision, before: +List<Legacy.Effect>) -> Legacy.Decision:
  Legacy.Decision{stored, after} = value
  Legacy.Decision{stored, List.append(&2, Legacy.Effect, before, after)}

def refresh_io_step(+origin: String, accumulator: Legacy.Decision, effect: E.Effect) -> Legacy.Decision:
  Legacy.Decision{stored, previous} = accumulator
  refresh_append(refresh_io(effect, origin, stored), previous)

def refresh_io_sequence(effects: +List<E.Effect>, +origin: String, initial: Legacy.Decision) -> Legacy.Decision:
  match effects:
    case Nil{}: initial
    case Con{effect, rest}: refresh_io_sequence(rest, origin, refresh_io_step(origin, initial, effect))

def refresh_completed(value: Legacy.Decision, effects: +List<Web.Effect>, services: +List<Services.Effect>) -> Legacy.Decision:
  Legacy.Decision{next, requests} = value
  Legacy.Decision{next, List.append(&2, Legacy.Effect,
    List.foldr(~&2, ~Web.Effect, ~(+List<Legacy.Effect>), ~(effect => rest => Legacy.BrowserEffect{effect} <> rest), effects, Nil{}),
    List.append(&2, Legacy.Effect, requests,
      List.foldr(~&2, ~Services.Effect, ~(+List<Legacy.Effect>), ~(effect => rest => Legacy.Service{effect} <> rest), services, Nil{})))}

def refresh_finish(value: Web.Decision, sequence: Nat, ticket: Nat, pending: +List<Legacy.Pending>, receipt: Maybe<&2, Receipt.Receipt>) -> Legacy.Decision:
  Web.Decision{web, InteractionTypes.Decision{core, reply, runtime, interaction, services, durable}, effects} = value
  refresh_completed(refresh_io_sequence(interaction, "", Legacy.Decision{Legacy.State{web, sequence, ticket, pending, receipt}, Nil{}}), effects, services)

def product_refresh(input: Product.Input, stored: Legacy.State) -> Legacy.Decision:
  Legacy.State{+web, sequence, ticket, pending, receipt} = stored
  refresh_finish(WebRules.committed_decision(refreshed_platform(input, Web.application(web)),
    (Web.generation(web) + 1n : Nat), Web.environment(web), Web.typography(web)), sequence, ticket, pending, receipt)

def refresh_environment(namespace: String, fresh: Bool, allowed: Bool, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{+stored, effects} = value
  refresh_append(product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{
    namespace, Legacy.sequence(stored), fresh, allowed}}}, stored), effects)

def refresh_stored(value: Legacy.Decision) -> Legacy.State:
  Legacy.Decision{stored, effects} = value
  stored

def refresh_effects(value: Legacy.Decision) -> +List<Legacy.Effect>:
  Legacy.Decision{stored, effects} = value
  effects

def refresh_sync(value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{+stored, effects} = value
  +session = refresh_session(stored)
  +observed = product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{
    E.InteractiveEnvironmentObserved{E.namespace(session), Legacy.sequence(stored), E.interactive_fresh(session), E.interactive_allowed(session)}}}, stored)
  refresh_append(product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}}, refresh_stored(observed)),
    List.append(&2, Legacy.Effect, effects, refresh_effects(observed)))

def refresh_reset(changed: Bool, stored: Legacy.State) -> Legacy.State:
  match changed stored:
    case False{} value: value
    case True{} Legacy.State{web, sequence, ticket, pending, receipt}: Legacy.State{web, sequence, ticket, Nil{}, None{}}

def refresh_world(newer: Bool, sequence: Nat, program: M.World(), stored: Legacy.State) -> Legacy.Decision:
  match newer stored:
    case False{} value: Legacy.Decision{value, Nil{}}
    case True{} Legacy.State{web, old_sequence, ticket, pending, receipt}:
      product_refresh(Product.ProgramObserved{program}, Legacy.State{web, sequence, ticket, pending, receipt})

def reconnect_needed(changed: Bool, access: Services.Access) -> Bool:
  match access:
    case Services.ConnectionLost{reason}: True{}
    case _: changed

def refresh_connect(needed: Bool, value: Legacy.Decision) -> Legacy.Decision:
  match needed value:
    case False{} result: result
    case True{} Legacy.Decision{stored, before}:
      refresh_append(product_refresh(Product.InterfaceInput{InteractionTypes.ServiceInput{Services.Connect{}}}, stored), before)

def snapshot_transfer(+changed: Bool, namespace: String, +sequence: Nat, program: M.World(), +state: Browser.State) -> Legacy.Decision:
  +value = refresh_environment(namespace, True{}, True{},
    refresh_world(changed || Nat.is_lt(Legacy.sequence(Browser.legacy(state)), sequence), sequence, program, refresh_reset(changed, Browser.legacy(state))))
  refresh_connect(reconnect_needed(changed, refresh_stored_access(refresh_stored(value))), value)

def failed_service(authentication: Maybe<&2, Nat>, reason: String) -> Product.Input:
  match authentication:
    case None{}: Product.Disconnected{reason}
    case Some{ticket}: Product.Authenticated{ticket, Fail{reason}}

def failure_transfer(namespace: String, sequence: Nat, reason: String, revoked: Bool, +authentication: Maybe<&2, Nat>, +state: Browser.State) -> Legacy.Decision:
  +observed = product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{
    E.InteractiveEnvironmentObserved{namespace, sequence, False{}, Bool.not(revoked) && refresh_allowed(state)}}}, Browser.legacy(state))
  refresh_append(product_refresh(failed_service(authentication, reason), refresh_stored(observed)), refresh_effects(observed))

def authenticated_transfer(ticket: Nat, value: Legacy.Decision) -> Legacy.Decision:
  Legacy.Decision{stored, first} = value
  refresh_append(product_refresh(Product.Authenticated{ticket, Done{Unit{}}}, stored), first)

def refresh_invalidated(invalid: Bool, state: Browser.State) -> Browser.State:
  match invalid state:
    case False{} retained: retained
    case True{} Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      Browser.State{legacy, serial, anchors, Browser.WaitingEnvironment{}, None{}, attention, updates}

def refresh_ready_synced(value: Legacy.Decision, state: Browser.State) -> (Browser.State & +List<Legacy.Effect>):
  Legacy.Decision{stored, effects} = value
  Browser.State{old, serial, anchors, lifecycle, displayed, attention, Browser.DisplayUpdates{+latest, active, published, semantic_latest}} = state
  (Browser.State{stored, serial, anchors, lifecycle, displayed, attention,
    Browser.DisplayUpdates{(latest + 1n : Nat), active, published, (latest + 1n : Nat)}}, effects)

def refresh_ready(value: Legacy.Decision, state: Browser.State) -> (Browser.State & +List<Legacy.Effect>):
  refresh_ready_synced(refresh_sync(value), state)

# Layout owns candidate selection. This transaction owns the entire ordered IO
# prefix. While a frozen measurement is active it must not restart that work.
def refresh_delivered(value: Browser.Decision) -> +List<Legacy.Effect>:
  Browser.Decision{state, effects} = value
  effects

type RefreshPrefix<-prefix: +List<Legacy.Effect>, -actual: Browser.Decision> is Type:
  RefreshPrefix{suffix: +List<Legacy.Effect>, effects: {refresh_delivered(actual) == List.append(&2, Legacy.Effect, prefix, suffix) : +List<Legacy.Effect>}}

def refresh_delivery_at(+prepared: Browser.State, prefix: +List<Legacy.Effect>, actual: Browser.Decision) -> Type:
  Browser.State{stored, serial, anchors, lifecycle, displayed, attention, updates} = prepared
  match lifecycle:
    case Browser.Measuring{index, capacity, engine, semantic, round}: {actual == Browser.Decision{prepared, prefix} : Browser.Decision}
    case _: RefreshPrefix<prefix, actual>

def refresh_prepared_delivery(value: Browser.State & +List<Legacy.Effect>, actual: Browser.Decision) -> Type:
  match value:
    case (prepared, prefix): refresh_delivery_at(prepared, prefix, actual)

def RefreshDelivery(value: Legacy.Decision, state: Browser.State, actual: Browser.Decision) -> Type:
  refresh_prepared_delivery(refresh_ready(value, state), actual)

def NetworkFailure(owned: Bool, +namespace: String, +sequence: Nat, +reason: String, +revoked: Bool,
  +authentication: Maybe<&2, Nat>, +state: Browser.State, actual: Browser.Decision) -> Type:
  match owned:
    case False{}: {actual == Browser.Decision{state, Nil{}} : Browser.Decision}
    case True{}:
      RefreshDelivery(failure_transfer(namespace, failure_sequence(authentication, sequence, state), reason, revoked, authentication, state),
        refresh_invalidated(revoked, state), actual)

def refresh_product_intents(decision: InteractionTypes.Decision) -> +List<M.Effect()> & +List<E.Effect>:
  InteractionTypes.Decision{core, reply, runtime, interaction, services, durable} = decision
  (runtime, interaction)

law duplicate_feedback_has_no_business_intents:
  for +owner: IM.Owner
  for +path: String
  for +ticket: Nat
  for +core: InteractionTypes.State
  {refresh_product_intents(Product.step(Product.InterfaceInput{InteractionTypes.Interactive{
    IM.EffectCompleted{owner, path, ticket, False{}, "This command is already pending"}}}, core)) ==
    (Nil{}, Nil{}) : +List<M.Effect()> & +List<E.Effect>}

law duplicate_command_settles_its_feedback:
  @+wire:J.Json -> @+completion:E.Completion -> @+origin:String -> @+stored:Legacy.State ->
  {Legacy.request_ready(True{}, wire, completion, origin, stored) == refresh_duplicate_request(completion, stored) : Legacy.Decision}

law snapshot_recovery_complete:
  @+changed:Bool -> @namespace:String -> @+sequence:Nat -> @program:M.World() -> @+state:Browser.State ->
  {Browser.snapshot_result(changed, namespace, sequence, program, state) == snapshot_transfer(changed, namespace, sequence, program, state) : Legacy.Decision}

law scoped_network_failure_complete:
  @+namespace:String -> @+sequence:Nat -> @+reason:String -> @+revoked:Bool -> @+authentication:Maybe<&2, Nat> -> @+state:Browser.State ->
  NetworkFailure(failure_owner(namespace, sequence, authentication, state), namespace, sequence, reason, revoked, authentication, state,
    Browser.network_failed(namespace, sequence, reason, revoked, authentication, state))

def authenticated_current(stale: Bool, +changed: Bool, namespace: String, sequence: Nat, +program: M.World(), ticket: Nat, +state: Browser.State, actual: Browser.Decision) -> Type:
  match stale:
    case True{}: RefreshDelivery(authenticated_transfer(ticket, Legacy.Decision{Browser.legacy(state), Nil{}}), state, actual)
    case False{}:
      RefreshDelivery(authenticated_transfer(ticket, snapshot_transfer(changed, namespace, sequence, program, state)),
        refresh_invalidated(changed || Browser.view_removed(program, state), state), actual)

def authenticated_valid(valid: Bool, +namespace: String, +sequence: Nat, program: M.World(), +ticket: Nat, +state: Browser.State, actual: Browser.Decision) -> Type:
  match valid:
    case False{}: NetworkFailure(authentication_owner(refresh_namespace(state), ticket, state), refresh_namespace(state), Legacy.sequence(Browser.legacy(state)),
      "Invalid service data namespace", True{}, Some{ticket}, state, actual)
    case True{}:
      +changed = Bool.not(String.eq(refresh_namespace(state), namespace))
      authenticated_current(Bool.not(changed) && Nat.is_lt(sequence, Legacy.sequence(Browser.legacy(state))), changed, namespace, sequence, program, ticket, state, actual)

def AuthenticatedSnapshot(owned: Bool, +namespace: String, sequence: Nat, program: M.World(), ticket: Nat, state: Browser.State, actual: Browser.Decision) -> Type:
  match owned:
    case False{}: {actual == Browser.Decision{state, Nil{}} : Browser.Decision}
    case True{}: authenticated_valid(Live.valid_namespace(namespace), namespace, sequence, program, ticket, state, actual)

law scoped_authentication_complete:
  @+expected_namespace:String -> @+namespace:String -> @+sequence:Nat -> @+program:M.World() -> @+ticket:Nat -> @+state:Browser.State ->
  AuthenticatedSnapshot(authentication_owner(expected_namespace, ticket, state), namespace, sequence, program, ticket, state,
    Browser.authenticated_snapshot(expected_namespace, namespace, sequence, program, ticket, state))

law atomic_snapshot_rejects_stale:
  for +expected_namespace: String
  for +namespace: String
  for +sequence: Nat
  for +program: M.World()
  for +state: Browser.State
  for valid: {Live.valid_namespace(namespace) == True{} : Bool}
  for owned: {String.eq(expected_namespace, Browser.current_namespace(state)) == True{} : Bool}
  for same: {String.eq(Browser.current_namespace(state), namespace) == True{} : Bool}
  for stale: {Nat.is_le(Legacy.sequence(Browser.legacy(state)), sequence) == False{} : Bool}
  {Browser.snapshot_environment(expected_namespace, namespace, sequence, program, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law atomic_snapshot_changes_namespace:
  for +expected_namespace: String
  for +namespace: String
  for +sequence: Nat
  for +program: M.World()
  for +state: Browser.State
  for valid: {Live.valid_namespace(namespace) == True{} : Bool}
  for owned: {String.eq(expected_namespace, Browser.current_namespace(state)) == True{} : Bool}
  for changed: {String.eq(Browser.current_namespace(state), namespace) == False{} : Bool}
  RefreshDelivery(snapshot_transfer(True{}, namespace, sequence, program, state), refresh_invalidated(True{}, state),
    Browser.snapshot_environment(expected_namespace, namespace, sequence, program, state))


law foreign_namespace_completion_ignored:
  for +ticket: Nat
  for +namespace: String
  for +sequence: Nat
  for +program: M.World()
  for +reply: J.Json
  for +state: Browser.State
  for changed: {String.eq(Browser.current_namespace(state), namespace) == False{} : Bool}
  {Browser.completed_environment(ticket, namespace, sequence, program, reply, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law same_namespace_completion_preserves_environment:
  for +ticket: Nat
  for +namespace: String
  for +sequence: Nat
  for +program: M.World()
  for +reply: J.Json
  for +state: Browser.State
  for same: {String.eq(Browser.current_namespace(state), namespace) == True{} : Bool}
  {Browser.completed_environment(ticket, namespace, sequence, program, reply, state) ==
    Browser.accept(True{}, Legacy.step(Legacy.Completed{ticket, sequence, program, reply}, Browser.legacy(state)),
      Browser.invalidate_if(Nat.is_le(Legacy.sequence(Browser.legacy(state)), sequence) && Browser.view_removed(program, state), state)) : Browser.Decision}


law namespace_switch_clears_previous_requests:
  for +web: Web.State
  for +sequence: Nat
  for +next: Nat
  for pending: +List<Legacy.Pending>
  for receipt: Maybe<&2, Receipt.Receipt>
  {Legacy.namespace_reset(True{}, Legacy.State{web, sequence, next, pending, receipt}) ==
    Legacy.State{web, sequence, next, Nil{}, None{}} : Legacy.State}

law same_namespace_retains_requests:
  for +state: Legacy.State
  {Legacy.namespace_reset(False{}, state) == state : Legacy.State}


law foreign_snapshot_request_ignored:
  for +expected_namespace: String
  for +namespace: String
  for +sequence: Nat
  for +program: M.World()
  for +state: Browser.State
  for foreign: {String.eq(expected_namespace, Browser.current_namespace(state)) == False{} : Bool}
  {Browser.snapshot_environment(expected_namespace, namespace, sequence, program, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law foreign_transport_environment_ignored:
  for +namespace: String
  for +sequence: Nat
  for +fresh: Bool
  for +allowed: Bool
  for +state: Browser.State
  for foreign: {String.eq(namespace, Browser.current_namespace(state)) == False{} : Bool}
  {Browser.transport_environment(namespace, sequence, fresh, allowed, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law stale_transport_environment_ignored:
  for +namespace: String
  for +sequence: Nat
  for +fresh: Bool
  for +allowed: Bool
  for +state: Browser.State
  for stale: {Nat.is_eq(sequence, Legacy.sequence(Browser.legacy(state))) == False{} : Bool}
  {Browser.transport_environment(namespace, sequence, fresh, allowed, state) == Browser.Decision{state, Nil{}} : Browser.Decision}


law invalidation_clears_publication:
  for +capacity: Nat
  for +last_published: Nat
  for +state: Browser.State
  {Browser.publication(capacity, last_published, Browser.invalidate_display(state)) ==
    Browser.Publish{0n, Browser.observe(capacity, Browser.invalidate_display(state)), Nil{}} : Browser.Publication}


def required_commit_covered(+notice: J.Json, sequence: Nat, +state: Browser.State) -> Bool:
  String.eq(J.text(J.get(notice, "type")), "commit") &&
    Live.valid_namespace(Browser.current_namespace(state)) &&
    String.eq(J.text(J.get(notice, "namespace")), Browser.current_namespace(state)) &&
    Browser.source_fresh(state) && Browser.source_allowed(state) && Browser.service_connected(state) &&
    Nat.is_le(sequence, Legacy.sequence(Browser.legacy(state)))

def required_commit_refresh_at(sequence: Maybe<&2, Nat>, notice: J.Json, state: Browser.State) -> Bool:
  match sequence:
    case None{}: True{}
    case Some{received}: Bool.not(required_commit_covered(notice, received, state))

def required_commit_refresh(+notice: J.Json, state: Browser.State) -> Bool:
  required_commit_refresh_at(J.natural(J.get(notice, "sequence")), notice, state)

law commit_refresh_needed_complete:
  for +notice: J.Json
  for +state: Browser.State
  {Browser.commit_refresh_needed(notice, state) == required_commit_refresh(notice, state) : Bool}

law undecodable_commit_refreshes:
  for +notice: J.Json
  for +state: Browser.State
  for undecodable: {J.natural(J.get(notice, "sequence")) == None{} : Maybe<&2, Nat>}
  {Browser.commit_refresh_needed(notice, state) == True{} : Bool}

law covered_commit_skips_refresh:
  for +notice: J.Json
  for +state: Browser.State
  for +sequence: Nat
  for decoded: {J.natural(J.get(notice, "sequence")) == Some{sequence} : Maybe<&2, Nat>}
  for covered: {required_commit_covered(notice, sequence, state) == True{} : Bool}
  {Browser.commit_refresh_needed(notice, state) == False{} : Bool}

law uncovered_commit_refreshes:
  for +notice: J.Json
  for +state: Browser.State
  for +sequence: Nat
  for decoded: {J.natural(J.get(notice, "sequence")) == Some{sequence} : Maybe<&2, Nat>}
  for uncovered: {required_commit_covered(notice, sequence, state) == False{} : Bool}
  {Browser.commit_refresh_needed(notice, state) == True{} : Bool}


law unowned_activation_is_inert:
  for +key: String
  for +state: Browser.State
  for ordinary: {String.eq(key, "@browser/retry") == False{} : Bool}
  for unowned: {Browser.activation_owned(key, state) == False{} : Bool}
  {Browser.activate(key, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law semantic_pending_external_activation_is_inert:
  for +key: String
  for +state: Browser.State
  for ordinary: {String.eq(key, "@browser/retry") == False{} : Bool}
  for pending: {Browser.semantic_pending(state) == True{} : Bool}
  for external: {Browser.external_action(InterfaceView.find_node(InterfaceView.active_nodes(Browser.current_surface(state)), key)) == True{} : Bool}
  {Browser.activate(key, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law disconnected_submit_is_inert:
  for +key: String
  for +state: Browser.State
  for ordinary: {String.eq(key, "@browser/retry") == False{} : Bool}
  for disconnected: {Browser.service_connected(state) == False{} : Bool}
  for submit: {Browser.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(Browser.current_surface(state)), key)) == True{} : Bool}
  {Browser.activate(key, state) == Browser.Decision{state, Nil{}} : Browser.Decision}


law changed_attention_advances_latest:
  for +attention: Navigation.Attention
  for +state: Browser.State
  {Browser.attention_changed(True{}, attention, state) ==
    Browser.attention_refresh(required_presentation_state(Browser.with_attention(attention, state))) : Browser.Decision}

law initial_update_stamps:
  for +program: M.World()
  for +sequence: Nat
  {Browser.initial(program, sequence) ==
    Browser.State{Legacy.initial(program, sequence), 0n, Nil{}, Browser.WaitingEnvironment{}, None{}, Navigation.initial(), Browser.DisplayUpdates{0n, 0n, 0n, 0n}} : Browser.State}

law semantic_update_complete:
  for +state: Browser.State
  {Browser.advance_update(state) == required_source_state(state) : Browser.State}

law presentation_update_complete:
  for +state: Browser.State
  {Browser.advance_presentation(state) == required_presentation_state(state) : Browser.State}

law semantic_pending_is_publication_lag:
  for +state: Browser.State
  {Browser.semantic_pending(state) == required_semantic_pending(state) : Bool}

law presentation_preserves_semantic_pending:
  for +state: Browser.State
  {Browser.semantic_pending(Browser.advance_presentation(state)) == Browser.semantic_pending(state) : Bool}

law attention_preserves_prior_semantic_update:
  for +state: Browser.State
  {Browser.semantic_pending(Browser.advance_presentation(Browser.advance_update(state))) == Browser.semantic_pending(Browser.advance_update(state)) : Bool}

law publication_uses_active_semantic_stamp:
  for +state: Browser.State
  {Browser.semantic_pending(Browser.publish_update(state)) == required_active_semantic_pending(state) : Bool}

law old_active_publication_remains_blocked:
  for +state: Browser.State
  for behind: {required_active_semantic_pending(state) == True{} : Bool}
  {Browser.semantic_pending(Browser.publish_update(state)) == True{} : Bool}

def required_activation_ready(blocked: Bool, key: String, +state: Browser.State) -> Browser.Decision:
  match blocked:
    case True{}: Browser.Decision{state, Nil{}}
    case False{}: Browser.accept(True{}, Legacy.activate(key, Browser.legacy(state)), state)

def required_activation_reserved(reserved: Bool, +key: String, +state: Browser.State) -> Browser.Decision:
  match reserved:
    case True{}: Browser.accept(True{}, Legacy.activate(key, Browser.legacy(state)), state)
    case False{}:
      required_activation_ready(Bool.not(Browser.activation_owned(key, state)) ||
        (required_semantic_pending(state) && Browser.external_action(InterfaceView.find_node(InterfaceView.active_nodes(Browser.current_surface(state)), key))) ||
        (Bool.not(Browser.service_connected(state)) && Browser.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(Browser.current_surface(state)), key))), key, state)

law activation_complete:
  for +key: String
  for +state: Browser.State
  {Browser.activate(key, state) == required_activation_reserved(String.eq(key, "@browser/retry"), key, state) : Browser.Decision}

law caught_up_owned_activation_is_admitted:
  for +key: String
  for +state: Browser.State
  for ordinary: {String.eq(key, "@browser/retry") == False{} : Bool}
  for owned: {Browser.activation_owned(key, state) == True{} : Bool}
  for caught_up: {Browser.semantic_pending(state) == False{} : Bool}
  for connected: {Browser.service_connected(state) == True{} : Bool}
  {Browser.activate(key, state) == Browser.accept(True{}, Legacy.activate(key, Browser.legacy(state)), state) : Browser.Decision}

def required_model_external_kind(kind: IM.ActionKind) -> Bool:
  match kind:
    case IM.SetAction{}: False{}
    case IM.ResetAction{}: False{}
    case _: True{}

def required_action_binding_updates(+key: String, found: Maybe<&2, SurfaceTypes.Node>, pending: Bool, owned: Bool) -> +List<Native.Update>:
  match found:
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{component, occurrence, tag, attributes, IM.ActionBinding{kind, enabled, busy}, children}}, nested}}:
      [Native.SetEnabled{key, owned && enabled && Bool.not(busy) && Bool.not(pending && required_model_external_kind(kind))}]
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveView{event, command, label_value, enabled}, nested}}:
      [Native.SetEnabled{key, owned && enabled}]
    case _: [Native.SetEnabled{key, False{}}]

law action_binding_updates_complete:
  for +key: String
  for +found: Maybe<&2, SurfaceTypes.Node>
  for +pending: Bool
  for +owned: Bool
  {Browser.action_binding_updates(key, found, pending, owned) == required_action_binding_updates(key, found, pending, owned) : +List<Native.Update>}

# A published mount may receive native writes only while its current semantic
# owner, field contract and occurrence still agree. Draft value changes are not
# a change of authority.
def required_field_binding(original: SurfaceTypes.Meaning, current: SurfaceTypes.Meaning) -> Bool:
  match original current:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}} SurfaceTypes.InteractiveNode{IM.ExpandedNode{other_identity, other_occurrence, other_tag, other_attrs, IM.FieldBinding{other_state, other_schema, other_raw, other_canonical, other_validation, other_enabled}, other_children}}:
      UIIdentity.same(IMScene.key(identity), IMScene.key(other_identity)) && Nat.is_eq(occurrence, other_occurrence) && String.eq(state_id, other_state) && String.eq(tag, other_tag) && IMSyntax.same_schema(schema, other_schema)
    case SurfaceTypes.Edit{editor, field, entry, value, choices} SurfaceTypes.Edit{other, new_field, new_entry, new_value, new_choices}: U.same_editor(editor, other)
    case SurfaceTypes.EnterDirectory{editor, text} SurfaceTypes.EnterDirectory{other, new_text}: U.same_editor(editor, other)
    case SurfaceTypes.ReceiveFile{editor, enabled} SurfaceTypes.ReceiveFile{other, new_enabled}: U.same_editor(editor, other)
    case SurfaceTypes.SearchChoices{query} SurfaceTypes.SearchChoices{new_query}: True{}
    case SurfaceTypes.BoardSearch{filter} SurfaceTypes.BoardSearch{new_filter}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value} SurfaceTypes.DirectoryBrowserLocation{new_value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled} SurfaceTypes.BoardProfile{new_automatic, new_selected, new_choices, new_enabled}: True{}
    case _ _: False{}

def required_mounted_field(binding: Native.Binding, found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match binding found:
    case retained None{}: False{}
    case Native.Binding{key, kind, identity, original} Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}:
      (String.eq(key, UIIdentity.encode(current)) && String.eq(identity, semantic)) && required_field_binding(original, meaning)

def required_field_projection(kind: Source.NativeFieldKind, +key: String, semantic: String, +meaning: SurfaceTypes.Meaning) -> +List<Native.Update>:
  match kind:
    case Source.ToggleField{}: [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, required_checked(meaning)}]
    case Source.FileField{multiple}: [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}]
    case _: [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, required_native_value(meaning)}]

def required_field_write(owned: Bool, binding: Native.Binding, found: Maybe<&2, SurfaceTypes.Node>) -> +List<Native.Update>:
  match owned binding found:
    case True{} Native.Binding{key, kind, identity, original} Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}:
      required_field_projection(kind, key, semantic, meaning)
    case _ _ _: Nil{}

def required_field_updates(fields: +List<Native.Binding>, +current: +List<SurfaceTypes.Node>) -> +List<Native.Update>:
  match fields:
    case Nil{}: Nil{}
    case Con{+binding, rest}:
      Native.Binding{key, kind, identity, meaning} = binding
      +found: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(current, key)
      List.append(&2, Native.Update, required_field_write(required_mounted_field(binding, found), binding, found),
        required_field_updates(rest, current))

def required_interactive_event(found: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, IM.EventIdentity>:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attributes, binding, children}}, nested}}: Some{IM.EventIdentity{identity, occurrence}}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveView{event, command, label_value, enabled}, nested}}: Some{event}
    case _: None{}

def required_same_mount(left: Maybe<&2, IM.EventIdentity>, right: Maybe<&2, IM.EventIdentity>) -> Bool:
  match left right:
    case Some{old} Some{current}: IMSyntax.same_event(old, current)
    case None{} None{}: True{}
    case _ _: False{}

def required_action_update(+node: SurfaceTypes.Node, +current: +List<SurfaceTypes.Node>, pending: Bool) -> +List<Native.Update>:
  SurfaceTypes.Node{+key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.ActionBinding{kind, enabled, busy}, nested}}:
      +encoded: String = UIIdentity.encode(key)
      +found: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(current, encoded)
      required_action_binding_updates(encoded, found, pending,
        required_same_mount(Some{IM.EventIdentity{identity, occurrence}}, required_interactive_event(found)))
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}:
      +encoded: String = UIIdentity.encode(key)
      +found: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(current, encoded)
      required_action_binding_updates(encoded, found, pending,
        required_same_mount(Some{event}, required_interactive_event(found)))
    case _: Nil{}

def required_action_updates(published: +List<SurfaceTypes.Node>, +current: +List<SurfaceTypes.Node>, +pending: Bool) -> +List<Native.Update>:
  match published:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      List.append(&2, Native.Update, required_action_update(node, current, pending),
        List.append(&2, Native.Update, required_action_updates(children, current, pending), required_action_updates(rest, current, pending)))

def required_native_mounts(fields: +List<Native.Binding>, +published: SurfaceTypes.Surface,
  +current: SurfaceTypes.Surface, pending: Bool) -> +List<Native.Update>:
  SurfaceTypes.Surface{content, base, overlays, active} = current
  List.append(&2, Native.Update, required_field_updates(fields, List.append(&2, SurfaceTypes.Node, base, overlays)),
    required_action_updates(FocusRules.required_active_nodes(published), FocusRules.required_active_nodes(current), pending))

def required_native_updates(+state: Browser.State) -> +List<Native.Update>:
  Browser.State{legacy, serial, anchors, lifecycle, displayed, attention, updates} = state
  match displayed:
    case None{}: Nil{}
    case Some{Browser.Published{world, semantic, scope, Native.Basis{fields, controls}, frame}}:
      required_native_mounts(fields, semantic, Browser.current_surface(state), required_semantic_pending(state))

law native_updates_use_semantic_lag:
  for +state: Browser.State
  {Browser.native_updates(state) == required_native_updates(state) : +List<Native.Update>}


def required_physical_reset(+before: Browser.State, +after: Browser.State) -> Bool:
  Bool.not(String.eq(Browser.current_namespace(before), Browser.current_namespace(after))) ||
    (Browser.source_allowed(before) && Bool.not(Browser.source_allowed(after))) ||
    (Bool.not(Browser.view_removed(Browser.program(before), before)) &&
      Browser.view_removed(Browser.program(after), before))

law physical_invalidation_complete:
  for +before: Browser.State
  for +after: Browser.State
  {Browser.physical_invalidated(before, after) == required_physical_reset(before, after) : Bool}

law ordinary_updates_retain_physical_probes:
  for +before: Browser.State
  for +after: Browser.State
  for same_namespace: {String.eq(Browser.current_namespace(before), Browser.current_namespace(after)) == True{} : Bool}
  for same_access: {Browser.source_allowed(after) == Browser.source_allowed(before) : Bool}
  for same_view: {Browser.view_removed(Browser.program(after), before) == Browser.view_removed(Browser.program(before), before) : Bool}
  {Browser.physical_invalidated(before, after) == False{} : Bool}



law realized_decision_exact:
  for +decision: Platform.Decision
  {Platform.realized_decision(decision) == expected_realized_decision(decision) : Platform.Decision}

# A successful empty composer submission clears only that editor's transient
# selection/composition. Other editors keep their native state.
def required_submission_clear(body: U.Body) -> Bool:
  match body:
    case U.NewTask{U.Text{text}, profile, reasoning, context}: String.eq(text, "")
    case U.Message{task, U.Text{text}, delivery}: String.eq(text, "")
    case _: False{}

def required_editor_reconciliation(found: Maybe<&2, U.Draft>, editor: Editor.Editor) -> Editor.Editor:
  match found editor:
    case Some{U.Draft{revision, body, U.Accepted{submitted, result}, directory}} Editor.Editor{+owner, +selection, +composing}:
      Bool.pick(Editor.Editor, required_submission_clear(body),
        Editor.Editor{owner, NativeGeometry.Selection{0n, 0n, "none"}, False{}}, Editor.Editor{owner, selection, composing})
    case ignored retained: retained

def required_editors(editors: +List<Editor.Editor>, +drafts: +List<U.Draft>) -> +List<Editor.Editor>:
  match editors:
    case Nil{}: Nil{}
    case Con{Editor.Editor{+owner, selection, composing}, rest}:
      required_editor_reconciliation(E.find_draft(drafts, owner), Editor.Editor{owner, selection, composing}) <> required_editors(rest, drafts)

def required_platform_commit(decision: InteractionTypes.Decision, platform: Platform.Platform) -> Platform.Decision:
  InteractionTypes.Decision{+core, +reply, +runtime, +interaction, +services, +durable} = decision
  Platform.Platform{+readers, editors, +focused, +ticket, reduced, +capacity, +previous} = platform
  +application = ProductState.application(core)
  +current = Focus.current(core, capacity)
  +transition = FocusRules.required_transition(previous, current, focused, FocusRules.required_target_eligible(InterfaceView.observe(capacity, core), focused))
  +next_ticket = FocusRules.required_focus_ticket(transition, interaction, ticket)
  Platform.Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable},
    Platform.Platform{readers, required_editors(editors, E.drafts(E.session(application))), focused, next_ticket, reduced, capacity, current},
    List.append(&2, Platform.Effect, FocusRules.required_scope_effects(transition, previous, current, interaction, next_ticket),
      FocusRules.required_layout(application, readers))}

law after_core_complete:
  for +decision: InteractionTypes.Decision
  for +platform: Platform.Platform
  {Platform.after_core(decision, platform) == required_platform_commit(decision, platform) : Platform.Decision}


law action_update_complete:
  for +node: SurfaceTypes.Node
  for +current: +List<SurfaceTypes.Node>
  for +pending: Bool
  {Browser.action_update(node, current, pending) == required_action_update(node, current, pending) : +List<Native.Update>}


law content_owner_classification:
  for +found: Maybe<&2, SurfaceTypes.Node>
  {Platform.found_content_owner(found) == FocusRules.required_content_owner(found) : Bool}

def required_content_focus_observation(+core: InteractionTypes.State, platform: Platform.Platform, owner: String, identity: String) -> Platform.Decision:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Platform.Decision{Platform.unchanged(core),
    Platform.Platform{readers, editors, Focus.Content{owner, identity}, (ticket + 1n : Nat), reduced, capacity, scope}, Nil{}}

law available_surface_content_focus_observation:
  for +core: InteractionTypes.State
  for +platform: Platform.Platform
  for +owner: String
  for +identity: String
  for +node: SurfaceTypes.Node
  for found: {InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(Platform.capacity(platform), core)), owner) ==
    Some{node} : Maybe<&2, SurfaceTypes.Node>}
  for eligible: {FocusRules.required_content_owner(Some{node}) == True{} : Bool}
  {Platform.step(Platform.ContentFocusObserved{owner, identity}, Platform.State{core, platform}) ==
    required_content_focus_observation(core, platform, owner, identity) : Platform.Decision}
