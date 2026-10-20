import ../layout/natural-size.bend as NaturalSize
import ../../interaction/conversation/OUTPUT.bend as Live
import ../controls/PROGRAM.bend as ControlsProgram
import ../layout/ADAPTATION.bend as Adaptation
import ../controls/NAVIGATION.bend as Navigation
import Base
import ../model-rules.bend as WebRules
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../interaction/session/PROOF.bend as SessionProof
import ../../interaction/interactive_markdown/DOCUMENTS.bend as InteractiveDocuments
import ../../interaction/interactive_markdown/TYPES.bend as Interactive
import ../../harness/INVARIANTS.bend as WorldInvariant
import ../../interaction/session/CONTRACT.bend as SessionRule
import ../document/MODEL.bend as CodeObservation
import ../../interaction/services/MODEL.bend as Services
import ../../bendlib/categories.bend as Categories
import ../../MODEL.bend as Model
import ../document/MODEL.bend as Document
import ./SEMANTICS.bend as Browser
import ./CONTRACT.bend as Rule
import ../../interaction/submission/MODEL.bend as Receipt
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ./frontend-utility.bend as Utility
import ./utility-proof.bend as UtilityProof
import ../appearance/TYPOGRAPHY.bend as T
import ./native-fields.bend as Native
import ../controls/CONTROLS.bend as NativeControls
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/services/CONTEXT.bend as Context
import ../../features/board/MODEL.bend as B
import ../../interaction/interactive_markdown/SYNTAX.bend as InteractiveSyntax
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../bendlib/stdlib.bend as Std
import ../document/SOURCE.bend as Source
import ./MODEL.bend as BrowserModel
import ../../interaction/MODEL.bend as Product
import ../../interaction/STATE.bend as InterfaceCore
import ../MODEL.bend as Web
import ../CONTRACT.bend as Interaction
import ../document/RENDERED.bend as Rendered
import ./PLATFORM.bend as Platform
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../PROOF.bend as Proof_laws
import ../../interaction/presentation/CONTRACT.bend as Rules_interface_program_rules
import ../../interaction/presentation/interaction-proof.bend as SemanticLookupEvidence
import ../document/presentation-order.bend as Order
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as AnchorGeometry
import ../focus/MODEL.bend as Focus
import ../focus/CONTRACT.bend as FocusRules
import ../layout/physical-plan.bend as Plan
import ../layout/MODEL.bend as World
import ../layout/CONTENT.bend as Content
import ../controls/SHELL.bend as Shell
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/VIEW.bend as ViewProgram
import ../../bendlib/logic-proof.bend as Logic
import ../document/FRAME.bend as SourceFrame
import ../document/render-contract.bend as FrameRules
import ../document/SPEC.bend as FrameSpec
import ../document/diagnostic-proof.bend as FrameEvidence
import ../document/render-proof.bend as FrameRequirements
import ./request.bend as Request
import ../../harness/transport/command-codec.bend as Codec
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes

def publication_focus_spec(+ready: Bool, ticket: Nat, before: Focus.Target) -> Maybe<&2, Platform.Input>:
  match ready:
    case True{}: Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}}
    case False{}: None{}

def publication_focus_checked(+generation: Nat, +ticket: Nat, +before: Focus.Target, +ready: Bool,
  observed: {Bool.not(Nat.is_eq(generation, 0n)) == ready : Bool}) ->
  {BrowserModel.publication_focus_admitted(Categories.admit_checked(BrowserModel.PublicationFocusCandidate, BrowserModel.publication_focus_predicate, BrowserModel.PublicationFocusCandidate{generation, ticket, before}, ready, observed)) == publication_focus_spec(ready, ticket, before) : Maybe<&2, Platform.Input>}:
  match ready:
    case True{}: {==}
    case False{}: {==}

def publication_focus_equation(+generation: Nat, +ticket: Nat, +before: Focus.Target) ->
  {BrowserModel.publication_focus_current(generation, ticket, before) == publication_focus_spec(Bool.not(Nat.is_eq(generation, 0n)), ticket, before) : Maybe<&2, Platform.Input>}:
  publication_focus_checked(generation, ticket, before, Bool.not(Nat.is_eq(generation, 0n)), {==})

def edit_text_owned_spec(+allowed: Bool, +key: String, +text: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_text(key, text, BrowserModel.legacy(state)), state)

def edit_text_checked(+key: String, +text: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_text_predicate(BrowserModel.TextEditCandidate{key, text, state}) == allowed : Bool}) ->
  {BrowserModel.edit_text_admitted(Categories.admit_checked(BrowserModel.TextEditCandidate, BrowserModel.edit_text_predicate, BrowserModel.TextEditCandidate{key, text, state}, allowed, observed), state) == edit_text_owned_spec(allowed, key, text, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_text_equation(+key: String, +text: String, +state: BrowserModel.State) ->
  {BrowserModel.edit_text(key, text, state) == edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state) : BrowserModel.Decision}:
  edit_text_checked(key, text, state, BrowserModel.field_owned(key, state), {==})

def edit_structured_text_owned_spec(+allowed: Bool, +key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_structured_text(key, text, parsed, BrowserModel.legacy(state)), state)

def edit_structured_text_checked(+key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_structured_text_predicate(BrowserModel.StructuredTextEditCandidate{key, text, parsed, state}) == allowed : Bool}) ->
  {BrowserModel.edit_structured_text_admitted(Categories.admit_checked(BrowserModel.StructuredTextEditCandidate, BrowserModel.edit_structured_text_predicate, BrowserModel.StructuredTextEditCandidate{key, text, parsed, state}, allowed, observed), state) == edit_structured_text_owned_spec(allowed, key, text, parsed, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_structured_text_equation(+key: String, +text: String, +parsed: Maybe<&2, J.Json>, +state: BrowserModel.State) ->
  {BrowserModel.edit_structured_text(key, text, parsed, state) == edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state) : BrowserModel.Decision}:
  edit_structured_text_checked(key, text, parsed, state, BrowserModel.structured_text_owned(key, state), {==})

def confirm_text_owned_spec(+allowed: Bool, +key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, BrowserModel.legacy(state)), state)

def confirm_text_checked(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.confirm_text_predicate(BrowserModel.TextConfirmationCandidate{key, keyboard, composing, control, alt, shift, meta, state}) == allowed : Bool}) ->
  {BrowserModel.confirm_text_admitted(Categories.admit_checked(BrowserModel.TextConfirmationCandidate, BrowserModel.confirm_text_predicate, BrowserModel.TextConfirmationCandidate{key, keyboard, composing, control, alt, shift, meta, state}, allowed, observed), state) == confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def confirm_text_equation(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: BrowserModel.State) ->
  {BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state) : BrowserModel.Decision}:
  confirm_text_checked(key, keyboard, composing, control, alt, shift, meta, state, BrowserModel.field_owned(key, state), {==})

def edit_toggle_owned_spec(+allowed: Bool, +key: String, +enabled: Bool, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.edit_toggle(key, enabled, BrowserModel.legacy(state)), state)

def edit_toggle_checked(+key: String, +enabled: Bool, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.edit_toggle_predicate(BrowserModel.ToggleEditCandidate{key, enabled, state}) == allowed : Bool}) ->
  {BrowserModel.edit_toggle_admitted(Categories.admit_checked(BrowserModel.ToggleEditCandidate, BrowserModel.edit_toggle_predicate, BrowserModel.ToggleEditCandidate{key, enabled, state}, allowed, observed), state) == edit_toggle_owned_spec(allowed, key, enabled, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def edit_toggle_equation(+key: String, +enabled: Bool, +state: BrowserModel.State) ->
  {BrowserModel.edit_toggle(key, enabled, state) == edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state) : BrowserModel.Decision}:
  edit_toggle_checked(key, enabled, state, BrowserModel.field_owned(key, state), {==})

def attach_owned_spec(+allowed: Bool, +key: String, +file: Services.SelectedFile, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, Browser.attach(key, file, BrowserModel.legacy(state)), state)

def attach_checked(+key: String, +file: Services.SelectedFile, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.attach_predicate(BrowserModel.AttachmentCandidate{key, file, state}) == allowed : Bool}) ->
  {BrowserModel.attach_admitted(Categories.admit_checked(BrowserModel.AttachmentCandidate, BrowserModel.attach_predicate, BrowserModel.AttachmentCandidate{key, file, state}, allowed, observed), state) == attach_owned_spec(allowed, key, file, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def attach_equation(+key: String, +file: Services.SelectedFile, +state: BrowserModel.State) ->
  {BrowserModel.attach(key, file, state) == attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state) : BrowserModel.Decision}:
  attach_checked(key, file, state, BrowserModel.field_owned(key, state), {==})

def received_frame_spec(+allowed: Bool, +received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.correlated_frame(frame, state)

def receive_frame_checked(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.receive_frame_predicate(BrowserModel.FrameCandidate{received, frame, state}) == allowed : Bool}) ->
  {BrowserModel.receive_frame_admitted(Categories.admit_checked(BrowserModel.FrameCandidate, BrowserModel.receive_frame_predicate, BrowserModel.FrameCandidate{received, frame, state}, allowed, observed), state) == received_frame_spec(allowed, received, frame, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def receive_frame_equation(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State) ->
  {BrowserModel.receive_frame(received, frame, state) == received_frame_spec(BrowserModel.frame_owned(received, state), received, frame, state) : BrowserModel.Decision}:
  receive_frame_checked(received, frame, state, BrowserModel.frame_owned(received, state), {==})

def measured_current_spec(+allowed: Bool, +ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.continue_latest(BrowserModel.measured_pending(receipts, state))

def physical_measured_checked(+ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.physical_measured_predicate(BrowserModel.MeasurementCandidate{ticket, receipts, state}) == allowed : Bool}) ->
  {BrowserModel.physical_measured_admitted(Categories.admit_checked(BrowserModel.MeasurementCandidate, BrowserModel.physical_measured_predicate, BrowserModel.MeasurementCandidate{ticket, receipts, state}, allowed, observed), state) == measured_current_spec(allowed, ticket, receipts, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def physical_measured_equation(+ticket: BrowserModel.MeasurementTicket, +receipts: +List<String>, +state: BrowserModel.State) ->
  {BrowserModel.physical_measured(ticket, receipts, state) == measured_current_spec(BrowserModel.measurement_owned(ticket, state), ticket, receipts, state) : BrowserModel.Decision}:
  physical_measured_checked(ticket, receipts, state, BrowserModel.measurement_owned(ticket, state), {==})

def native_focus_if_owned_spec(+allowed: Bool, +generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(False{}, Browser.native(Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}, BrowserModel.legacy(state)), state)

def native_focus_observed_checked(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.native_focus_observed_predicate(BrowserModel.NativeObservationCandidate{generation, owner, identity, state}) == allowed : Bool}) ->
  {BrowserModel.native_focus_observed_admitted(Categories.admit_checked(BrowserModel.NativeObservationCandidate, BrowserModel.native_focus_observed_predicate, BrowserModel.NativeObservationCandidate{generation, owner, identity, state}, allowed, observed), state) == native_focus_if_owned_spec(allowed, generation, owner, identity, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def native_focus_observed_equation(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State) ->
  {BrowserModel.native_focus_observed(generation, owner, identity, state) == native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state) : BrowserModel.Decision}:
  native_focus_observed_checked(generation, owner, identity, state, BrowserModel.native_observation_owned(generation, owner, identity, state), {==})

def measurement_failed_spec(+allowed: Bool, +ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State) -> BrowserModel.Decision:
  match allowed:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.utility_measurement_failure(reason, state)

def physical_measurement_failed_checked(+ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State, +allowed: Bool,
  observed: {BrowserModel.physical_measurement_failed_predicate(BrowserModel.MeasurementFailureCandidate{ticket, reason, state}) == allowed : Bool}) ->
  {BrowserModel.physical_measurement_failed_admitted(Categories.admit_checked(BrowserModel.MeasurementFailureCandidate, BrowserModel.physical_measurement_failed_predicate, BrowserModel.MeasurementFailureCandidate{ticket, reason, state}, allowed, observed), state) == measurement_failed_spec(allowed, ticket, reason, state) : BrowserModel.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: {==}

def physical_measurement_failed_equation(+ticket: BrowserModel.MeasurementTicket, +reason: String, +state: BrowserModel.State) ->
  {BrowserModel.physical_measurement_failed(ticket, reason, state) == measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state) : BrowserModel.Decision}:
  physical_measurement_failed_checked(ticket, reason, state, BrowserModel.measurement_owned(ticket, state), {==})

def update_spec(owned: Bool, binding: Native.Binding, found: Maybe<&2, SurfaceTypes.Node>) -> +List<Native.Update>:
  match owned:
    case False{}: Nil{}
    case True{}: Native.update_found(found, binding)

def update_checked(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>, +owned: Bool,
  observed: {Native.owned_node(binding, found) == owned : Bool}) ->
  {Native.update_admitted(Categories.admit_checked(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found}, owned, observed)) == update_spec(owned, binding, found) : +List<Native.Update>}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def update_equation(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) ->
  {Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})) == update_spec(Native.owned_node(binding, found), binding, found) : +List<Native.Update>}:
  update_checked(binding, found, Native.owned_node(binding, found), {==})

def field_binding_key(binding: Native.Binding) -> String:
  Native.Binding{key, kind, identity, meaning} = binding
  key

def native_scalar_requirement(value: J.Json) ->
  {InteractiveSyntax.scalar_text(value) == Rule.required_scalar_value(value) : String}:
  match value:
    case J.Null{}: {==}
    case J.Text{text}: {==}
    case J.Number{text}: {==}
    case J.Boolean{value}: {==}
    case J.Array{items}: {==}
    case J.Object{fields}: {==}

def native_local_value_requirement(+tag: String, +raw: String, +canonical: J.Json) ->
  {Bool.pick(String, String.eq(tag, "slider") || String.eq(tag, "select") || String.eq(tag, "checkbox"), InteractiveSyntax.scalar_text(canonical), raw) == Rule.required_local_value(tag, raw, canonical) : String}:
  Equal.cong(String, String,
    (value => Bool.pick(String, String.eq(tag, "slider") || String.eq(tag, "select") || String.eq(tag, "checkbox"), value, raw)),
    InteractiveSyntax.scalar_text(canonical), Rule.required_scalar_value(canonical), native_scalar_requirement(canonical))

def native_origin_requirement(origin: Context.Origin) ->
  {NativeControls.origin_text(origin) == Rule.required_origin_value(origin) : String}:
  match origin:
    case Context.EnvironmentDefaults{}: {==}
    case Context.ProjectDefaults{project}: {==}
    case Context.ParentTask{task}: {==}
    case Context.ProjectForParent{task, project}: {==}

def native_primary_requirement(workspace: Context.WorkspaceValue) ->
  {NativeControls.workspace_primary(workspace) == Rule.required_workspace_primary(workspace) : String}:
  match workspace:
    case Context.InheritedWorkspace{D.Workspace{roots, primary}}: {==}
    case Context.EnteredWorkspace{D.Workspace{roots, primary}}: {==}

def native_network_requirement(sandbox: Context.SandboxValue) ->
  {NativeControls.network_text(sandbox) == Rule.required_network_value(sandbox) : String}:
  match sandbox:
    case Context.InheritedSandbox{D.Sandbox{mode, network}}: {==}
    case Context.ChosenSandbox{D.Sandbox{mode, network}}: {==}

def native_context_value_requirement(field: Forms.Field, origin: Context.Origin, workspace: Context.WorkspaceValue, sandbox: Context.SandboxValue, approval: Context.ApprovalValue) ->
  {NativeControls.context_field_text(field, origin, workspace, sandbox, approval) == Rule.required_context_value(field, origin, workspace, sandbox, approval) : String}:
  match field:
    case Forms.MessageText{}: {==}
    case Forms.ProjectName{}: {==}
    case Forms.WorkName{}: {==}
    case Forms.CreateWorktree{}: {==}
    case Forms.TaskEnvironment{}: {==}
    case Forms.TaskTitlePrompt{}: {==}
    case Forms.AgentTitlePrompt{}: {==}
    case Forms.WorkspaceDirectories{}: {==}
    case Forms.WorkspacePrimary{}: native_primary_requirement(workspace)
    case Forms.ContextOrigin{}: native_origin_requirement(origin)
    case Forms.SandboxMode{}: {==}
    case Forms.NetworkAccess{}: native_network_requirement(sandbox)
    case Forms.ApprovalPolicy{}: {==}
    case Forms.ApprovalReviewer{}: {==}
    case Forms.ModelProfile{}: {==}
    case Forms.ReasoningEffort{}: {==}
    case Forms.DeliveryIntent{}: {==}
    case Forms.CardTitle{}: {==}
    case Forms.CardDescription{}: {==}
    case Forms.CardStage{}: {==}
    case Forms.CardPriority{}: {==}
    case Forms.CardOwner{}: {==}
    case Forms.CardProject{}: {==}
    case Forms.CardLabels{}: {==}
    case Forms.CardAttachments{}: {==}
    case Forms.ContinueCapture{}: {==}
    case Forms.AssistedCapture{}: {==}
    case Forms.AssistanceProfile{}: {==}
    case Forms.AgentName{}: {==}
    case Forms.AgentInstructions{}: {==}
    case Forms.AgentConcurrency{}: {==}
    case Forms.ForkCount{}: {==}
    case Forms.ForkMessages{}: {==}
    case Forms.CompactionSummary{}: {==}
    case Forms.TaskGraphDeclaration{}: {==}

def native_workspace_value_requirement(field: Forms.Field, roots: +List<String>, primary: Maybe<&2, String>) ->
  {NativeControls.workspace_field_text(field, roots, primary) == Rule.required_workspace_value(field, roots, primary) : String}:
  match field:
    case Forms.MessageText{}: {==}
    case Forms.ProjectName{}: {==}
    case Forms.WorkName{}: {==}
    case Forms.CreateWorktree{}: {==}
    case Forms.TaskEnvironment{}: {==}
    case Forms.TaskTitlePrompt{}: {==}
    case Forms.AgentTitlePrompt{}: {==}
    case Forms.WorkspaceDirectories{}: {==}
    case Forms.WorkspacePrimary{}: {==}
    case Forms.ContextOrigin{}: {==}
    case Forms.SandboxMode{}: {==}
    case Forms.NetworkAccess{}: {==}
    case Forms.ApprovalPolicy{}: {==}
    case Forms.ApprovalReviewer{}: {==}
    case Forms.ModelProfile{}: {==}
    case Forms.ReasoningEffort{}: {==}
    case Forms.DeliveryIntent{}: {==}
    case Forms.CardTitle{}: {==}
    case Forms.CardDescription{}: {==}
    case Forms.CardStage{}: {==}
    case Forms.CardPriority{}: {==}
    case Forms.CardOwner{}: {==}
    case Forms.CardProject{}: {==}
    case Forms.CardLabels{}: {==}
    case Forms.CardAttachments{}: {==}
    case Forms.ContinueCapture{}: {==}
    case Forms.AssistedCapture{}: {==}
    case Forms.AssistanceProfile{}: {==}
    case Forms.AgentName{}: {==}
    case Forms.AgentInstructions{}: {==}
    case Forms.AgentConcurrency{}: {==}
    case Forms.ForkCount{}: {==}
    case Forms.ForkMessages{}: {==}
    case Forms.CompactionSummary{}: {==}
    case Forms.TaskGraphDeclaration{}: {==}

def native_model_value_requirement(field: Forms.Field, profile: String, reasoning: String) ->
  {NativeControls.model_field_text(field, profile, reasoning) == Rule.required_model_value(field, profile, reasoning) : String}:
  match field:
    case Forms.MessageText{}: {==}
    case Forms.ProjectName{}: {==}
    case Forms.WorkName{}: {==}
    case Forms.CreateWorktree{}: {==}
    case Forms.TaskEnvironment{}: {==}
    case Forms.TaskTitlePrompt{}: {==}
    case Forms.AgentTitlePrompt{}: {==}
    case Forms.WorkspaceDirectories{}: {==}
    case Forms.WorkspacePrimary{}: {==}
    case Forms.ContextOrigin{}: {==}
    case Forms.SandboxMode{}: {==}
    case Forms.NetworkAccess{}: {==}
    case Forms.ApprovalPolicy{}: {==}
    case Forms.ApprovalReviewer{}: {==}
    case Forms.ModelProfile{}: {==}
    case Forms.ReasoningEffort{}: {==}
    case Forms.DeliveryIntent{}: {==}
    case Forms.CardTitle{}: {==}
    case Forms.CardDescription{}: {==}
    case Forms.CardStage{}: {==}
    case Forms.CardPriority{}: {==}
    case Forms.CardOwner{}: {==}
    case Forms.CardProject{}: {==}
    case Forms.CardLabels{}: {==}
    case Forms.CardAttachments{}: {==}
    case Forms.ContinueCapture{}: {==}
    case Forms.AssistedCapture{}: {==}
    case Forms.AssistanceProfile{}: {==}
    case Forms.AgentName{}: {==}
    case Forms.AgentInstructions{}: {==}
    case Forms.AgentConcurrency{}: {==}
    case Forms.ForkCount{}: {==}
    case Forms.ForkMessages{}: {==}
    case Forms.CompactionSummary{}: {==}
    case Forms.TaskGraphDeclaration{}: {==}

def native_edit_value_requirement(value: Forms.Observed, field: Forms.Field) ->
  {NativeControls.field_text(field, value) == Rule.required_edit_value(field, value) : String}:
  match value:
    case Forms.ToggleValue{enabled}: {==}
    case Forms.TextValue{text}: {==}
    case Forms.CountValue{count}: {==}
    case Forms.TextsValue{values}: {==}
    case Forms.WorkspaceValue{D.Workspace{roots, primary}}: native_workspace_value_requirement(field, roots, primary)
    case Forms.ContextValue{Context.ContextUnavailable{reason}, reviewers}: {==}
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: native_context_value_requirement(field, origin, workspace, sandbox, approval)
    case Forms.ModelValue{profile, reasoning}: native_model_value_requirement(field, profile, reasoning)
    case Forms.DeliveryValue{delivery}: {==}
    case Forms.StageValue{stage}: {==}
    case Forms.PriorityValue{priority}: {==}
    case Forms.OwnerValue{owner}: {==}
    case Forms.ProjectValue{project}: {==}
    case Forms.AttachmentsValue{files}: {==}
    case Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.OptionalTextValue{text}: {==}
    case Forms.NotApplicable{}: {==}

def native_edit_checked_requirement(field: Forms.Field, value: Forms.Observed, editor: U.Editor, entry: Forms.Entry, choices: +List<Forms.ChoiceValue>) ->
  {NativeControls.field_checked(SurfaceTypes.Edit{editor, field, entry, value, choices}) == Rule.required_checked(SurfaceTypes.Edit{editor, field, entry, value, choices}) : Bool}:
  match field value:
    case Forms.MessageText{} Forms.ToggleValue{enabled}: {==}
    case Forms.MessageText{} Forms.TextValue{text}: {==}
    case Forms.MessageText{} Forms.CountValue{count}: {==}
    case Forms.MessageText{} Forms.TextsValue{values}: {==}
    case Forms.MessageText{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.MessageText{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.MessageText{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.MessageText{} Forms.DeliveryValue{delivery}: {==}
    case Forms.MessageText{} Forms.StageValue{stage}: {==}
    case Forms.MessageText{} Forms.PriorityValue{priority}: {==}
    case Forms.MessageText{} Forms.OwnerValue{owner}: {==}
    case Forms.MessageText{} Forms.ProjectValue{project}: {==}
    case Forms.MessageText{} Forms.AttachmentsValue{files}: {==}
    case Forms.MessageText{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.MessageText{} Forms.OptionalTextValue{text}: {==}
    case Forms.MessageText{} Forms.NotApplicable{}: {==}
    case Forms.ProjectName{} Forms.ToggleValue{enabled}: {==}
    case Forms.WorkName{} Forms.ToggleValue{enabled}: {==}
    case Forms.CreateWorktree{} Forms.ToggleValue{enabled}: {==}
    case Forms.TaskEnvironment{} Forms.ToggleValue{enabled}: {==}
    case Forms.TaskTitlePrompt{} Forms.ToggleValue{enabled}: {==}
    case Forms.AgentTitlePrompt{} Forms.ToggleValue{enabled}: {==}
    case Forms.ProjectName{} Forms.TextValue{text}: {==}
    case Forms.WorkName{} Forms.TextValue{text}: {==}
    case Forms.CreateWorktree{} Forms.TextValue{text}: {==}
    case Forms.TaskEnvironment{} Forms.TextValue{text}: {==}
    case Forms.TaskTitlePrompt{} Forms.TextValue{text}: {==}
    case Forms.AgentTitlePrompt{} Forms.TextValue{text}: {==}
    case Forms.ProjectName{} Forms.CountValue{count}: {==}
    case Forms.WorkName{} Forms.CountValue{count}: {==}
    case Forms.CreateWorktree{} Forms.CountValue{count}: {==}
    case Forms.TaskEnvironment{} Forms.CountValue{count}: {==}
    case Forms.TaskTitlePrompt{} Forms.CountValue{count}: {==}
    case Forms.AgentTitlePrompt{} Forms.CountValue{count}: {==}
    case Forms.ProjectName{} Forms.TextsValue{values}: {==}
    case Forms.WorkName{} Forms.TextsValue{values}: {==}
    case Forms.CreateWorktree{} Forms.TextsValue{values}: {==}
    case Forms.TaskEnvironment{} Forms.TextsValue{values}: {==}
    case Forms.TaskTitlePrompt{} Forms.TextsValue{values}: {==}
    case Forms.AgentTitlePrompt{} Forms.TextsValue{values}: {==}
    case Forms.ProjectName{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.WorkName{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CreateWorktree{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.TaskEnvironment{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.TaskTitlePrompt{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AgentTitlePrompt{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ProjectName{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.WorkName{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CreateWorktree{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.TaskEnvironment{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.TaskTitlePrompt{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AgentTitlePrompt{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ProjectName{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.WorkName{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CreateWorktree{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.TaskEnvironment{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.TaskTitlePrompt{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AgentTitlePrompt{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ProjectName{} Forms.DeliveryValue{delivery}: {==}
    case Forms.WorkName{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CreateWorktree{} Forms.DeliveryValue{delivery}: {==}
    case Forms.TaskEnvironment{} Forms.DeliveryValue{delivery}: {==}
    case Forms.TaskTitlePrompt{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AgentTitlePrompt{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ProjectName{} Forms.StageValue{stage}: {==}
    case Forms.WorkName{} Forms.StageValue{stage}: {==}
    case Forms.CreateWorktree{} Forms.StageValue{stage}: {==}
    case Forms.TaskEnvironment{} Forms.StageValue{stage}: {==}
    case Forms.TaskTitlePrompt{} Forms.StageValue{stage}: {==}
    case Forms.AgentTitlePrompt{} Forms.StageValue{stage}: {==}
    case Forms.ProjectName{} Forms.PriorityValue{priority}: {==}
    case Forms.WorkName{} Forms.PriorityValue{priority}: {==}
    case Forms.CreateWorktree{} Forms.PriorityValue{priority}: {==}
    case Forms.TaskEnvironment{} Forms.PriorityValue{priority}: {==}
    case Forms.TaskTitlePrompt{} Forms.PriorityValue{priority}: {==}
    case Forms.AgentTitlePrompt{} Forms.PriorityValue{priority}: {==}
    case Forms.ProjectName{} Forms.OwnerValue{owner}: {==}
    case Forms.WorkName{} Forms.OwnerValue{owner}: {==}
    case Forms.CreateWorktree{} Forms.OwnerValue{owner}: {==}
    case Forms.TaskEnvironment{} Forms.OwnerValue{owner}: {==}
    case Forms.TaskTitlePrompt{} Forms.OwnerValue{owner}: {==}
    case Forms.AgentTitlePrompt{} Forms.OwnerValue{owner}: {==}
    case Forms.ProjectName{} Forms.ProjectValue{project}: {==}
    case Forms.WorkName{} Forms.ProjectValue{project}: {==}
    case Forms.CreateWorktree{} Forms.ProjectValue{project}: {==}
    case Forms.TaskEnvironment{} Forms.ProjectValue{project}: {==}
    case Forms.TaskTitlePrompt{} Forms.ProjectValue{project}: {==}
    case Forms.AgentTitlePrompt{} Forms.ProjectValue{project}: {==}
    case Forms.ProjectName{} Forms.AttachmentsValue{files}: {==}
    case Forms.WorkName{} Forms.AttachmentsValue{files}: {==}
    case Forms.CreateWorktree{} Forms.AttachmentsValue{files}: {==}
    case Forms.TaskEnvironment{} Forms.AttachmentsValue{files}: {==}
    case Forms.TaskTitlePrompt{} Forms.AttachmentsValue{files}: {==}
    case Forms.AgentTitlePrompt{} Forms.AttachmentsValue{files}: {==}
    case Forms.ProjectName{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.WorkName{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CreateWorktree{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.TaskEnvironment{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.TaskTitlePrompt{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AgentTitlePrompt{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ProjectName{} Forms.OptionalTextValue{text}: {==}
    case Forms.WorkName{} Forms.OptionalTextValue{text}: {==}
    case Forms.CreateWorktree{} Forms.OptionalTextValue{text}: {==}
    case Forms.TaskEnvironment{} Forms.OptionalTextValue{text}: {==}
    case Forms.TaskTitlePrompt{} Forms.OptionalTextValue{text}: {==}
    case Forms.AgentTitlePrompt{} Forms.OptionalTextValue{text}: {==}
    case Forms.ProjectName{} Forms.NotApplicable{}: {==}
    case Forms.WorkName{} Forms.NotApplicable{}: {==}
    case Forms.CreateWorktree{} Forms.NotApplicable{}: {==}
    case Forms.TaskEnvironment{} Forms.NotApplicable{}: {==}
    case Forms.TaskTitlePrompt{} Forms.NotApplicable{}: {==}
    case Forms.AgentTitlePrompt{} Forms.NotApplicable{}: {==}
    case Forms.WorkspaceDirectories{} Forms.ToggleValue{enabled}: {==}
    case Forms.WorkspaceDirectories{} Forms.TextValue{text}: {==}
    case Forms.WorkspaceDirectories{} Forms.CountValue{count}: {==}
    case Forms.WorkspaceDirectories{} Forms.TextsValue{values}: {==}
    case Forms.WorkspaceDirectories{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.WorkspaceDirectories{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.WorkspaceDirectories{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.WorkspaceDirectories{} Forms.DeliveryValue{delivery}: {==}
    case Forms.WorkspaceDirectories{} Forms.StageValue{stage}: {==}
    case Forms.WorkspaceDirectories{} Forms.PriorityValue{priority}: {==}
    case Forms.WorkspaceDirectories{} Forms.OwnerValue{owner}: {==}
    case Forms.WorkspaceDirectories{} Forms.ProjectValue{project}: {==}
    case Forms.WorkspaceDirectories{} Forms.AttachmentsValue{files}: {==}
    case Forms.WorkspaceDirectories{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.WorkspaceDirectories{} Forms.OptionalTextValue{text}: {==}
    case Forms.WorkspaceDirectories{} Forms.NotApplicable{}: {==}
    case Forms.WorkspacePrimary{} Forms.ToggleValue{enabled}: {==}
    case Forms.WorkspacePrimary{} Forms.TextValue{text}: {==}
    case Forms.WorkspacePrimary{} Forms.CountValue{count}: {==}
    case Forms.WorkspacePrimary{} Forms.TextsValue{values}: {==}
    case Forms.WorkspacePrimary{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.WorkspacePrimary{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.WorkspacePrimary{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.WorkspacePrimary{} Forms.DeliveryValue{delivery}: {==}
    case Forms.WorkspacePrimary{} Forms.StageValue{stage}: {==}
    case Forms.WorkspacePrimary{} Forms.PriorityValue{priority}: {==}
    case Forms.WorkspacePrimary{} Forms.OwnerValue{owner}: {==}
    case Forms.WorkspacePrimary{} Forms.ProjectValue{project}: {==}
    case Forms.WorkspacePrimary{} Forms.AttachmentsValue{files}: {==}
    case Forms.WorkspacePrimary{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.WorkspacePrimary{} Forms.OptionalTextValue{text}: {==}
    case Forms.WorkspacePrimary{} Forms.NotApplicable{}: {==}
    case Forms.ContextOrigin{} Forms.ToggleValue{enabled}: {==}
    case Forms.ContextOrigin{} Forms.TextValue{text}: {==}
    case Forms.ContextOrigin{} Forms.CountValue{count}: {==}
    case Forms.ContextOrigin{} Forms.TextsValue{values}: {==}
    case Forms.ContextOrigin{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ContextOrigin{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ContextOrigin{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ContextOrigin{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ContextOrigin{} Forms.StageValue{stage}: {==}
    case Forms.ContextOrigin{} Forms.PriorityValue{priority}: {==}
    case Forms.ContextOrigin{} Forms.OwnerValue{owner}: {==}
    case Forms.ContextOrigin{} Forms.ProjectValue{project}: {==}
    case Forms.ContextOrigin{} Forms.AttachmentsValue{files}: {==}
    case Forms.ContextOrigin{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ContextOrigin{} Forms.OptionalTextValue{text}: {==}
    case Forms.ContextOrigin{} Forms.NotApplicable{}: {==}
    case Forms.SandboxMode{} Forms.ToggleValue{enabled}: {==}
    case Forms.SandboxMode{} Forms.TextValue{text}: {==}
    case Forms.SandboxMode{} Forms.CountValue{count}: {==}
    case Forms.SandboxMode{} Forms.TextsValue{values}: {==}
    case Forms.SandboxMode{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.SandboxMode{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.SandboxMode{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.SandboxMode{} Forms.DeliveryValue{delivery}: {==}
    case Forms.SandboxMode{} Forms.StageValue{stage}: {==}
    case Forms.SandboxMode{} Forms.PriorityValue{priority}: {==}
    case Forms.SandboxMode{} Forms.OwnerValue{owner}: {==}
    case Forms.SandboxMode{} Forms.ProjectValue{project}: {==}
    case Forms.SandboxMode{} Forms.AttachmentsValue{files}: {==}
    case Forms.SandboxMode{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.SandboxMode{} Forms.OptionalTextValue{text}: {==}
    case Forms.SandboxMode{} Forms.NotApplicable{}: {==}
    case Forms.NetworkAccess{} Forms.ToggleValue{enabled}: {==}
    case Forms.NetworkAccess{} Forms.TextValue{text}: {==}
    case Forms.NetworkAccess{} Forms.CountValue{count}: {==}
    case Forms.NetworkAccess{} Forms.TextsValue{values}: {==}
    case Forms.NetworkAccess{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ContextUnavailable{reason}, reviewers}: {==}
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{D.Sandbox{mode, enabled}}, approval, guidance}, reviewers}: {==}
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{D.Sandbox{mode, enabled}}, approval, guidance}, reviewers}: {==}
    case Forms.NetworkAccess{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.NetworkAccess{} Forms.DeliveryValue{delivery}: {==}
    case Forms.NetworkAccess{} Forms.StageValue{stage}: {==}
    case Forms.NetworkAccess{} Forms.PriorityValue{priority}: {==}
    case Forms.NetworkAccess{} Forms.OwnerValue{owner}: {==}
    case Forms.NetworkAccess{} Forms.ProjectValue{project}: {==}
    case Forms.NetworkAccess{} Forms.AttachmentsValue{files}: {==}
    case Forms.NetworkAccess{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.NetworkAccess{} Forms.OptionalTextValue{text}: {==}
    case Forms.NetworkAccess{} Forms.NotApplicable{}: {==}
    case Forms.ApprovalPolicy{} Forms.ToggleValue{enabled}: {==}
    case Forms.ApprovalPolicy{} Forms.TextValue{text}: {==}
    case Forms.ApprovalPolicy{} Forms.CountValue{count}: {==}
    case Forms.ApprovalPolicy{} Forms.TextsValue{values}: {==}
    case Forms.ApprovalPolicy{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ApprovalPolicy{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ApprovalPolicy{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ApprovalPolicy{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ApprovalPolicy{} Forms.StageValue{stage}: {==}
    case Forms.ApprovalPolicy{} Forms.PriorityValue{priority}: {==}
    case Forms.ApprovalPolicy{} Forms.OwnerValue{owner}: {==}
    case Forms.ApprovalPolicy{} Forms.ProjectValue{project}: {==}
    case Forms.ApprovalPolicy{} Forms.AttachmentsValue{files}: {==}
    case Forms.ApprovalPolicy{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ApprovalPolicy{} Forms.OptionalTextValue{text}: {==}
    case Forms.ApprovalPolicy{} Forms.NotApplicable{}: {==}
    case Forms.ApprovalReviewer{} Forms.ToggleValue{enabled}: {==}
    case Forms.ApprovalReviewer{} Forms.TextValue{text}: {==}
    case Forms.ApprovalReviewer{} Forms.CountValue{count}: {==}
    case Forms.ApprovalReviewer{} Forms.TextsValue{values}: {==}
    case Forms.ApprovalReviewer{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ApprovalReviewer{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ApprovalReviewer{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ApprovalReviewer{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ApprovalReviewer{} Forms.StageValue{stage}: {==}
    case Forms.ApprovalReviewer{} Forms.PriorityValue{priority}: {==}
    case Forms.ApprovalReviewer{} Forms.OwnerValue{owner}: {==}
    case Forms.ApprovalReviewer{} Forms.ProjectValue{project}: {==}
    case Forms.ApprovalReviewer{} Forms.AttachmentsValue{files}: {==}
    case Forms.ApprovalReviewer{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ApprovalReviewer{} Forms.OptionalTextValue{text}: {==}
    case Forms.ApprovalReviewer{} Forms.NotApplicable{}: {==}
    case Forms.ModelProfile{} Forms.ToggleValue{enabled}: {==}
    case Forms.ModelProfile{} Forms.TextValue{text}: {==}
    case Forms.ModelProfile{} Forms.CountValue{count}: {==}
    case Forms.ModelProfile{} Forms.TextsValue{values}: {==}
    case Forms.ModelProfile{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ModelProfile{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ModelProfile{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ModelProfile{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ModelProfile{} Forms.StageValue{stage}: {==}
    case Forms.ModelProfile{} Forms.PriorityValue{priority}: {==}
    case Forms.ModelProfile{} Forms.OwnerValue{owner}: {==}
    case Forms.ModelProfile{} Forms.ProjectValue{project}: {==}
    case Forms.ModelProfile{} Forms.AttachmentsValue{files}: {==}
    case Forms.ModelProfile{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ModelProfile{} Forms.OptionalTextValue{text}: {==}
    case Forms.ModelProfile{} Forms.NotApplicable{}: {==}
    case Forms.ReasoningEffort{} Forms.ToggleValue{enabled}: {==}
    case Forms.ReasoningEffort{} Forms.TextValue{text}: {==}
    case Forms.ReasoningEffort{} Forms.CountValue{count}: {==}
    case Forms.ReasoningEffort{} Forms.TextsValue{values}: {==}
    case Forms.ReasoningEffort{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ReasoningEffort{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ReasoningEffort{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ReasoningEffort{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ReasoningEffort{} Forms.StageValue{stage}: {==}
    case Forms.ReasoningEffort{} Forms.PriorityValue{priority}: {==}
    case Forms.ReasoningEffort{} Forms.OwnerValue{owner}: {==}
    case Forms.ReasoningEffort{} Forms.ProjectValue{project}: {==}
    case Forms.ReasoningEffort{} Forms.AttachmentsValue{files}: {==}
    case Forms.ReasoningEffort{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ReasoningEffort{} Forms.OptionalTextValue{text}: {==}
    case Forms.ReasoningEffort{} Forms.NotApplicable{}: {==}
    case Forms.DeliveryIntent{} Forms.ToggleValue{enabled}: {==}
    case Forms.DeliveryIntent{} Forms.TextValue{text}: {==}
    case Forms.DeliveryIntent{} Forms.CountValue{count}: {==}
    case Forms.DeliveryIntent{} Forms.TextsValue{values}: {==}
    case Forms.DeliveryIntent{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.DeliveryIntent{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.DeliveryIntent{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.DeliveryIntent{} Forms.DeliveryValue{delivery}: {==}
    case Forms.DeliveryIntent{} Forms.StageValue{stage}: {==}
    case Forms.DeliveryIntent{} Forms.PriorityValue{priority}: {==}
    case Forms.DeliveryIntent{} Forms.OwnerValue{owner}: {==}
    case Forms.DeliveryIntent{} Forms.ProjectValue{project}: {==}
    case Forms.DeliveryIntent{} Forms.AttachmentsValue{files}: {==}
    case Forms.DeliveryIntent{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.DeliveryIntent{} Forms.OptionalTextValue{text}: {==}
    case Forms.DeliveryIntent{} Forms.NotApplicable{}: {==}
    case Forms.CardTitle{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardTitle{} Forms.TextValue{text}: {==}
    case Forms.CardTitle{} Forms.CountValue{count}: {==}
    case Forms.CardTitle{} Forms.TextsValue{values}: {==}
    case Forms.CardTitle{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardTitle{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardTitle{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardTitle{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardTitle{} Forms.StageValue{stage}: {==}
    case Forms.CardTitle{} Forms.PriorityValue{priority}: {==}
    case Forms.CardTitle{} Forms.OwnerValue{owner}: {==}
    case Forms.CardTitle{} Forms.ProjectValue{project}: {==}
    case Forms.CardTitle{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardTitle{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardTitle{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardTitle{} Forms.NotApplicable{}: {==}
    case Forms.CardDescription{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardDescription{} Forms.TextValue{text}: {==}
    case Forms.CardDescription{} Forms.CountValue{count}: {==}
    case Forms.CardDescription{} Forms.TextsValue{values}: {==}
    case Forms.CardDescription{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardDescription{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardDescription{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardDescription{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardDescription{} Forms.StageValue{stage}: {==}
    case Forms.CardDescription{} Forms.PriorityValue{priority}: {==}
    case Forms.CardDescription{} Forms.OwnerValue{owner}: {==}
    case Forms.CardDescription{} Forms.ProjectValue{project}: {==}
    case Forms.CardDescription{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardDescription{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardDescription{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardDescription{} Forms.NotApplicable{}: {==}
    case Forms.CardStage{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardStage{} Forms.TextValue{text}: {==}
    case Forms.CardStage{} Forms.CountValue{count}: {==}
    case Forms.CardStage{} Forms.TextsValue{values}: {==}
    case Forms.CardStage{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardStage{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardStage{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardStage{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardStage{} Forms.StageValue{stage}: {==}
    case Forms.CardStage{} Forms.PriorityValue{priority}: {==}
    case Forms.CardStage{} Forms.OwnerValue{owner}: {==}
    case Forms.CardStage{} Forms.ProjectValue{project}: {==}
    case Forms.CardStage{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardStage{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardStage{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardStage{} Forms.NotApplicable{}: {==}
    case Forms.CardPriority{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardPriority{} Forms.TextValue{text}: {==}
    case Forms.CardPriority{} Forms.CountValue{count}: {==}
    case Forms.CardPriority{} Forms.TextsValue{values}: {==}
    case Forms.CardPriority{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardPriority{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardPriority{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardPriority{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardPriority{} Forms.StageValue{stage}: {==}
    case Forms.CardPriority{} Forms.PriorityValue{priority}: {==}
    case Forms.CardPriority{} Forms.OwnerValue{owner}: {==}
    case Forms.CardPriority{} Forms.ProjectValue{project}: {==}
    case Forms.CardPriority{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardPriority{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardPriority{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardPriority{} Forms.NotApplicable{}: {==}
    case Forms.CardOwner{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardOwner{} Forms.TextValue{text}: {==}
    case Forms.CardOwner{} Forms.CountValue{count}: {==}
    case Forms.CardOwner{} Forms.TextsValue{values}: {==}
    case Forms.CardOwner{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardOwner{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardOwner{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardOwner{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardOwner{} Forms.StageValue{stage}: {==}
    case Forms.CardOwner{} Forms.PriorityValue{priority}: {==}
    case Forms.CardOwner{} Forms.OwnerValue{owner}: {==}
    case Forms.CardOwner{} Forms.ProjectValue{project}: {==}
    case Forms.CardOwner{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardOwner{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardOwner{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardOwner{} Forms.NotApplicable{}: {==}
    case Forms.CardProject{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardProject{} Forms.TextValue{text}: {==}
    case Forms.CardProject{} Forms.CountValue{count}: {==}
    case Forms.CardProject{} Forms.TextsValue{values}: {==}
    case Forms.CardProject{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardProject{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardProject{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardProject{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardProject{} Forms.StageValue{stage}: {==}
    case Forms.CardProject{} Forms.PriorityValue{priority}: {==}
    case Forms.CardProject{} Forms.OwnerValue{owner}: {==}
    case Forms.CardProject{} Forms.ProjectValue{project}: {==}
    case Forms.CardProject{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardProject{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardProject{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardProject{} Forms.NotApplicable{}: {==}
    case Forms.CardLabels{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardLabels{} Forms.TextValue{text}: {==}
    case Forms.CardLabels{} Forms.CountValue{count}: {==}
    case Forms.CardLabels{} Forms.TextsValue{values}: {==}
    case Forms.CardLabels{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardLabels{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardLabels{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardLabels{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardLabels{} Forms.StageValue{stage}: {==}
    case Forms.CardLabels{} Forms.PriorityValue{priority}: {==}
    case Forms.CardLabels{} Forms.OwnerValue{owner}: {==}
    case Forms.CardLabels{} Forms.ProjectValue{project}: {==}
    case Forms.CardLabels{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardLabels{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardLabels{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardLabels{} Forms.NotApplicable{}: {==}
    case Forms.CardAttachments{} Forms.ToggleValue{enabled}: {==}
    case Forms.CardAttachments{} Forms.TextValue{text}: {==}
    case Forms.CardAttachments{} Forms.CountValue{count}: {==}
    case Forms.CardAttachments{} Forms.TextsValue{values}: {==}
    case Forms.CardAttachments{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CardAttachments{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CardAttachments{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CardAttachments{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CardAttachments{} Forms.StageValue{stage}: {==}
    case Forms.CardAttachments{} Forms.PriorityValue{priority}: {==}
    case Forms.CardAttachments{} Forms.OwnerValue{owner}: {==}
    case Forms.CardAttachments{} Forms.ProjectValue{project}: {==}
    case Forms.CardAttachments{} Forms.AttachmentsValue{files}: {==}
    case Forms.CardAttachments{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CardAttachments{} Forms.OptionalTextValue{text}: {==}
    case Forms.CardAttachments{} Forms.NotApplicable{}: {==}
    case Forms.ContinueCapture{} Forms.ToggleValue{enabled}: {==}
    case Forms.ContinueCapture{} Forms.TextValue{text}: {==}
    case Forms.ContinueCapture{} Forms.CountValue{count}: {==}
    case Forms.ContinueCapture{} Forms.TextsValue{values}: {==}
    case Forms.ContinueCapture{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ContinueCapture{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ContinueCapture{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ContinueCapture{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ContinueCapture{} Forms.StageValue{stage}: {==}
    case Forms.ContinueCapture{} Forms.PriorityValue{priority}: {==}
    case Forms.ContinueCapture{} Forms.OwnerValue{owner}: {==}
    case Forms.ContinueCapture{} Forms.ProjectValue{project}: {==}
    case Forms.ContinueCapture{} Forms.AttachmentsValue{files}: {==}
    case Forms.ContinueCapture{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ContinueCapture{} Forms.OptionalTextValue{text}: {==}
    case Forms.ContinueCapture{} Forms.NotApplicable{}: {==}
    case Forms.AssistedCapture{} Forms.ToggleValue{enabled}: {==}
    case Forms.AssistedCapture{} Forms.TextValue{text}: {==}
    case Forms.AssistedCapture{} Forms.CountValue{count}: {==}
    case Forms.AssistedCapture{} Forms.TextsValue{values}: {==}
    case Forms.AssistedCapture{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AssistedCapture{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AssistedCapture{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AssistedCapture{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AssistedCapture{} Forms.StageValue{stage}: {==}
    case Forms.AssistedCapture{} Forms.PriorityValue{priority}: {==}
    case Forms.AssistedCapture{} Forms.OwnerValue{owner}: {==}
    case Forms.AssistedCapture{} Forms.ProjectValue{project}: {==}
    case Forms.AssistedCapture{} Forms.AttachmentsValue{files}: {==}
    case Forms.AssistedCapture{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AssistedCapture{} Forms.OptionalTextValue{text}: {==}
    case Forms.AssistedCapture{} Forms.NotApplicable{}: {==}
    case Forms.AssistanceProfile{} Forms.ToggleValue{enabled}: {==}
    case Forms.AssistanceProfile{} Forms.TextValue{text}: {==}
    case Forms.AssistanceProfile{} Forms.CountValue{count}: {==}
    case Forms.AssistanceProfile{} Forms.TextsValue{values}: {==}
    case Forms.AssistanceProfile{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AssistanceProfile{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AssistanceProfile{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AssistanceProfile{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AssistanceProfile{} Forms.StageValue{stage}: {==}
    case Forms.AssistanceProfile{} Forms.PriorityValue{priority}: {==}
    case Forms.AssistanceProfile{} Forms.OwnerValue{owner}: {==}
    case Forms.AssistanceProfile{} Forms.ProjectValue{project}: {==}
    case Forms.AssistanceProfile{} Forms.AttachmentsValue{files}: {==}
    case Forms.AssistanceProfile{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AssistanceProfile{} Forms.OptionalTextValue{text}: {==}
    case Forms.AssistanceProfile{} Forms.NotApplicable{}: {==}
    case Forms.AgentName{} Forms.ToggleValue{enabled}: {==}
    case Forms.AgentName{} Forms.TextValue{text}: {==}
    case Forms.AgentName{} Forms.CountValue{count}: {==}
    case Forms.AgentName{} Forms.TextsValue{values}: {==}
    case Forms.AgentName{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AgentName{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AgentName{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AgentName{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AgentName{} Forms.StageValue{stage}: {==}
    case Forms.AgentName{} Forms.PriorityValue{priority}: {==}
    case Forms.AgentName{} Forms.OwnerValue{owner}: {==}
    case Forms.AgentName{} Forms.ProjectValue{project}: {==}
    case Forms.AgentName{} Forms.AttachmentsValue{files}: {==}
    case Forms.AgentName{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AgentName{} Forms.OptionalTextValue{text}: {==}
    case Forms.AgentName{} Forms.NotApplicable{}: {==}
    case Forms.AgentInstructions{} Forms.ToggleValue{enabled}: {==}
    case Forms.AgentInstructions{} Forms.TextValue{text}: {==}
    case Forms.AgentInstructions{} Forms.CountValue{count}: {==}
    case Forms.AgentInstructions{} Forms.TextsValue{values}: {==}
    case Forms.AgentInstructions{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AgentInstructions{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AgentInstructions{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AgentInstructions{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AgentInstructions{} Forms.StageValue{stage}: {==}
    case Forms.AgentInstructions{} Forms.PriorityValue{priority}: {==}
    case Forms.AgentInstructions{} Forms.OwnerValue{owner}: {==}
    case Forms.AgentInstructions{} Forms.ProjectValue{project}: {==}
    case Forms.AgentInstructions{} Forms.AttachmentsValue{files}: {==}
    case Forms.AgentInstructions{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AgentInstructions{} Forms.OptionalTextValue{text}: {==}
    case Forms.AgentInstructions{} Forms.NotApplicable{}: {==}
    case Forms.AgentConcurrency{} Forms.ToggleValue{enabled}: {==}
    case Forms.AgentConcurrency{} Forms.TextValue{text}: {==}
    case Forms.AgentConcurrency{} Forms.CountValue{count}: {==}
    case Forms.AgentConcurrency{} Forms.TextsValue{values}: {==}
    case Forms.AgentConcurrency{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.AgentConcurrency{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.AgentConcurrency{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.AgentConcurrency{} Forms.DeliveryValue{delivery}: {==}
    case Forms.AgentConcurrency{} Forms.StageValue{stage}: {==}
    case Forms.AgentConcurrency{} Forms.PriorityValue{priority}: {==}
    case Forms.AgentConcurrency{} Forms.OwnerValue{owner}: {==}
    case Forms.AgentConcurrency{} Forms.ProjectValue{project}: {==}
    case Forms.AgentConcurrency{} Forms.AttachmentsValue{files}: {==}
    case Forms.AgentConcurrency{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.AgentConcurrency{} Forms.OptionalTextValue{text}: {==}
    case Forms.AgentConcurrency{} Forms.NotApplicable{}: {==}
    case Forms.ForkCount{} Forms.ToggleValue{enabled}: {==}
    case Forms.ForkCount{} Forms.TextValue{text}: {==}
    case Forms.ForkCount{} Forms.CountValue{count}: {==}
    case Forms.ForkCount{} Forms.TextsValue{values}: {==}
    case Forms.ForkCount{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ForkCount{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ForkCount{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ForkCount{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ForkCount{} Forms.StageValue{stage}: {==}
    case Forms.ForkCount{} Forms.PriorityValue{priority}: {==}
    case Forms.ForkCount{} Forms.OwnerValue{owner}: {==}
    case Forms.ForkCount{} Forms.ProjectValue{project}: {==}
    case Forms.ForkCount{} Forms.AttachmentsValue{files}: {==}
    case Forms.ForkCount{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ForkCount{} Forms.OptionalTextValue{text}: {==}
    case Forms.ForkCount{} Forms.NotApplicable{}: {==}
    case Forms.ForkMessages{} Forms.ToggleValue{enabled}: {==}
    case Forms.ForkMessages{} Forms.TextValue{text}: {==}
    case Forms.ForkMessages{} Forms.CountValue{count}: {==}
    case Forms.ForkMessages{} Forms.TextsValue{values}: {==}
    case Forms.ForkMessages{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.ForkMessages{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.ForkMessages{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.ForkMessages{} Forms.DeliveryValue{delivery}: {==}
    case Forms.ForkMessages{} Forms.StageValue{stage}: {==}
    case Forms.ForkMessages{} Forms.PriorityValue{priority}: {==}
    case Forms.ForkMessages{} Forms.OwnerValue{owner}: {==}
    case Forms.ForkMessages{} Forms.ProjectValue{project}: {==}
    case Forms.ForkMessages{} Forms.AttachmentsValue{files}: {==}
    case Forms.ForkMessages{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.ForkMessages{} Forms.OptionalTextValue{text}: {==}
    case Forms.ForkMessages{} Forms.NotApplicable{}: {==}
    case Forms.CompactionSummary{} Forms.ToggleValue{enabled}: {==}
    case Forms.CompactionSummary{} Forms.TextValue{text}: {==}
    case Forms.CompactionSummary{} Forms.CountValue{count}: {==}
    case Forms.CompactionSummary{} Forms.TextsValue{values}: {==}
    case Forms.CompactionSummary{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.CompactionSummary{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.CompactionSummary{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.CompactionSummary{} Forms.DeliveryValue{delivery}: {==}
    case Forms.CompactionSummary{} Forms.StageValue{stage}: {==}
    case Forms.CompactionSummary{} Forms.PriorityValue{priority}: {==}
    case Forms.CompactionSummary{} Forms.OwnerValue{owner}: {==}
    case Forms.CompactionSummary{} Forms.ProjectValue{project}: {==}
    case Forms.CompactionSummary{} Forms.AttachmentsValue{files}: {==}
    case Forms.CompactionSummary{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.CompactionSummary{} Forms.OptionalTextValue{text}: {==}
    case Forms.CompactionSummary{} Forms.NotApplicable{}: {==}
    case Forms.TaskGraphDeclaration{} Forms.ToggleValue{enabled}: {==}
    case Forms.TaskGraphDeclaration{} Forms.TextValue{text}: {==}
    case Forms.TaskGraphDeclaration{} Forms.CountValue{count}: {==}
    case Forms.TaskGraphDeclaration{} Forms.TextsValue{values}: {==}
    case Forms.TaskGraphDeclaration{} Forms.WorkspaceValue{workspace}: {==}
    case Forms.TaskGraphDeclaration{} Forms.ContextValue{preview, reviewers}: {==}
    case Forms.TaskGraphDeclaration{} Forms.ModelValue{profile, reasoning}: {==}
    case Forms.TaskGraphDeclaration{} Forms.DeliveryValue{delivery}: {==}
    case Forms.TaskGraphDeclaration{} Forms.StageValue{stage}: {==}
    case Forms.TaskGraphDeclaration{} Forms.PriorityValue{priority}: {==}
    case Forms.TaskGraphDeclaration{} Forms.OwnerValue{owner}: {==}
    case Forms.TaskGraphDeclaration{} Forms.ProjectValue{project}: {==}
    case Forms.TaskGraphDeclaration{} Forms.AttachmentsValue{files}: {==}
    case Forms.TaskGraphDeclaration{} Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.TaskGraphDeclaration{} Forms.OptionalTextValue{text}: {==}
    case Forms.TaskGraphDeclaration{} Forms.NotApplicable{}: {==}

def native_checked_requirement(meaning: SurfaceTypes.Meaning) ->
  {NativeControls.field_checked(meaning) == Rule.required_checked(meaning) : Bool}:
  match meaning:
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value}: {==}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.MovableCard{destinations, face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardSearch{filter}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.NoBinding{}, children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.ActionBinding{kind, enabled, pending}, children}}: {==}
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: {==}
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: native_edit_checked_requirement(field, value, editor, entry, choices)
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.HistorySearchQuery{query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}

def native_value_requirement(meaning: SurfaceTypes.Meaning) ->
  {NativeControls.node_value(meaning) == Rule.required_native_value(meaning) : String}:
  match meaning:
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value}: {==}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.MovableCard{destinations, face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardSearch{B.Filter{view, search, status, priority, date, assignee, creator, project, label}}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.NoBinding{}, children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: native_local_value_requirement(tag, raw, canonical)
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.ActionBinding{kind, enabled, pending}, children}}: {==}
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: {==}
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: native_edit_value_requirement(value, field)
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.HistorySearchQuery{query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}

def native_binding_requirement(original: SurfaceTypes.Meaning, current: SurfaceTypes.Meaning) ->
  {Native.same_meaning(original, current) == Rule.required_field_binding(original, current) : Bool}:
  match original current:
    case SurfaceTypes.SettingEntry{left_subject, left_value, left_input, left_availability} other: {==}
    case SurfaceTypes.ActivityRow{left_role} other: {==}
    case SurfaceTypes.ActivityGroup{left_activity, left_dismiss, left_outside, left_escape} other: {==}
    case SurfaceTypes.DecisionGroup{left_decision} other: {==}
    case SurfaceTypes.WorkspaceCollection{left_collection} other: {==}
    case SurfaceTypes.WorkspaceMember{left_collection, left_path} other: {==}
    case SurfaceTypes.ActionUnit{left_action} other: {==}
    case SurfaceTypes.ActionFeedback{left_feedback} other: {==}
    case SurfaceTypes.ActionExplanation{left_assessment} other: {==}
    case SurfaceTypes.ActionCommit{left_assessment, left_input, left_availability} other: {==}
    case SurfaceTypes.ObjectGroup{left_object} other: {==}
    case SurfaceTypes.SupportingControl{left_support, left_property, left_input, left_availability} other: {==}
    case SurfaceTypes.InformationText{left_role} other: {==}
    case SurfaceTypes.LayerRegion{left_dismiss, left_outside, left_escape} other: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{left_value} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.PanelToggle{left_expanded, left_input, left_availability} other: {==}
    case SurfaceTypes.CardContent{left_face} other: {==}
    case SurfaceTypes.MovableCard{left_destinations, left_face} other: {==}
    case SurfaceTypes.Region{} other: {==}
    case SurfaceTypes.PageContext{left_conversation} other: {==}
    case SurfaceTypes.ActivityContent{left_expanded, left_audit} other: {==}
    case SurfaceTypes.ProjectGroup{left_project, left_selected, left_expanded} other: {==}
    case SurfaceTypes.TaskRow{left_task, left_status, left_selected} other: {==}
    case SurfaceTypes.TaskChildren{left_task} other: {==}
    case SurfaceTypes.ProjectChooser{left_selected} other: {==}
    case SurfaceTypes.DirectoryRow{left_path, left_primary} other: {==}
    case SurfaceTypes.ContextSummary{left_observation} other: {==}
    case SurfaceTypes.ChoiceGroup{} other: {==}
    case SurfaceTypes.Choice{left_kind, left_classification, left_selected, left_description, left_input, left_availability} other: {==}
    case SurfaceTypes.PageRegion{left_region, left_position} other: {==}
    case SurfaceTypes.BoardLane{left_stage, left_count} other: {==}
    case SurfaceTypes.CardArchive{left_count} other: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.BoardSearch{left_filter} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.BoardGroup{left_grouping} other: {==}
    case SurfaceTypes.ReadOnly{left_text} other: {==}
    case SurfaceTypes.Fact{left_value} other: {==}
    case SurfaceTypes.RichText{left_source, left_value} other: {==}
    case SurfaceTypes.TaskFacts{left_details} other: {==}
    case SurfaceTypes.CodeFacts{left_view} other: {==}
    case SurfaceTypes.InteractiveRegion{left_identity, left_source_visible} other: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.NoBinding{}, left_children}} other: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{right_identity, right_occurrence, right_tag, right_attrs, Interactive.NoBinding{}, right_children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{right_identity, right_occurrence, right_tag, right_attrs, Interactive.FieldBinding{right_state_id, right_schema, right_raw, right_canonical, right_validation, right_enabled}, right_children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{right_identity, right_occurrence, right_tag, right_attrs, Interactive.ActionBinding{right_kind, right_enabled, right_pending}, right_children}}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.FieldBinding{left_state_id, left_schema, left_raw, left_canonical, left_validation, left_enabled}, left_children}} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{left_identity, left_occurrence, left_tag, left_attrs, Interactive.ActionBinding{left_kind, left_enabled, left_pending}, left_children}} other: {==}
    case SurfaceTypes.InteractiveView{left_event, left_command, left_label, left_enabled} other: {==}
    case SurfaceTypes.Activate{left_input, left_availability} other: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.Edit{left_editor, left_field, left_entry, left_value, left_choices} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.HistorySearchScope{scope_1, right_query, choices_1}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.HistorySearchScope{scope_1, right_query, choices_1}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.HistorySearchScope{scope_1, right_query, choices_1}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.SearchChoices{left_query} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.HistorySearchQuery{left_query} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, left_query, choices_0} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.ReceiveFile{left_editor, left_enabled} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.EnterDirectory{left_editor, left_text} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.SettingEntry{right_subject, right_value, right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActivityRow{right_role}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActivityGroup{right_activity, right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.DecisionGroup{right_decision}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.WorkspaceCollection{right_collection}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.WorkspaceMember{right_collection, right_path}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActionUnit{right_action}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActionFeedback{right_feedback}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActionExplanation{right_assessment}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActionCommit{right_assessment, right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ObjectGroup{right_object}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.SupportingControl{right_support, right_property, right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.InformationText{right_role}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.LayerRegion{right_dismiss, right_outside, right_escape}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.DirectoryBrowserLocation{right_value}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.PanelToggle{right_expanded, right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.CardContent{right_face}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.MovableCard{right_destinations, right_face}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.Region{}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.PageContext{right_conversation}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ActivityContent{right_expanded, right_audit}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ProjectGroup{right_project, right_selected, right_expanded}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.TaskRow{right_task, right_status, right_selected}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.TaskChildren{right_task}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ProjectChooser{right_selected}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.DirectoryRow{right_path, right_primary}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ContextSummary{right_observation}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.Choice{right_kind, right_classification, right_selected, right_description, right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.PageRegion{right_region, right_position}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.BoardLane{right_stage, right_count}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.CardArchive{right_count}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.BoardSearch{right_filter}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.BoardGroup{right_grouping}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ReadOnly{right_text}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.Fact{right_value}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.RichText{right_source, right_value}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.TaskFacts{right_details}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.CodeFacts{right_view}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.InteractiveRegion{right_identity, right_source_visible}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.InteractiveNode{right_node}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.InteractiveView{right_event, right_command, right_label, right_enabled}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.Activate{right_input, right_availability}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.Edit{right_editor, right_field, right_entry, right_value, right_choices}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.SearchChoices{right_query}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.HistorySearchQuery{right_query}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.HistorySearchScope{scope_0, right_query, choices_0}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.ReceiveFile{right_editor, right_enabled}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.EnterDirectory{right_editor, right_text}: {==}
    case SurfaceTypes.BoardProfile{left_automatic, left_selected, left_choices, left_enabled} SurfaceTypes.BoardProfile{right_automatic, right_selected, right_choices, right_enabled}: {==}

def native_projection_requirement(kind: Source.NativeFieldKind, +key: String, +semantic: String, +meaning: SurfaceTypes.Meaning) ->
  {Native.projected(key, kind, semantic, meaning) == Rule.required_field_projection(kind, key, semantic, meaning) : +List<Native.Update>}:
  match kind:
    case Source.ToggleField{}:
      Equal.cong(Bool, +List<Native.Update>,
        (checked => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetChecked{key, checked}]),
        NativeControls.field_checked(meaning), Rule.required_checked(meaning), native_checked_requirement(meaning))
    case Source.FileField{multiple}: {==}
    case Source.TextField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.MessageField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.TextAreaField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.SelectField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.MultiSelectField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.NumberField{minimum}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.RangeField{minimum, maximum, step}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.DecimalField{minimum, maximum, step}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.DirectoryField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.SearchField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))
    case Source.SecretField{}:
      Equal.cong(String, +List<Native.Update>,
        (value => [Native.SetIdentity{key, Native.Identity{key, semantic, meaning}}, Native.SetValue{key, value}]),
        NativeControls.node_value(meaning), Rule.required_native_value(meaning), native_value_requirement(meaning))

def field_authority_requirement(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) ->
  {Native.owned_node(binding, found) == Rule.required_mounted_field(binding, found) : Bool}:
  match binding found:
    case retained None{}: {==}
    case Native.Binding{+key, kind, +identity, +original} Some{SurfaceTypes.Node{+current, +semantic, label, role, +meaning, children}}:
      Equal.trans(Bool, Native.owned_node(binding, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}),
        (String.eq(key, UIIdentity.encode(current)) && SafeText.string_equal(identity, semantic)) && Native.same_meaning(original, meaning),
        Rule.required_mounted_field(binding, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}),
        Equal.cong(Bool, Bool, (same => (same && SafeText.string_equal(identity, semantic)) && Native.same_meaning(original, meaning)),
          SafeText.string_equal(key, UIIdentity.encode(current)), String.eq(key, UIIdentity.encode(current)), TextProof.public_refines(key, UIIdentity.encode(current))),
        Equal.trans(Bool,
          (String.eq(key, UIIdentity.encode(current)) && SafeText.string_equal(identity, semantic)) && Native.same_meaning(original, meaning),
          (String.eq(key, UIIdentity.encode(current)) && String.eq(identity, semantic)) && Native.same_meaning(original, meaning),
          Rule.required_mounted_field(binding, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}),
          Equal.cong(Bool, Bool, (same => (String.eq(key, UIIdentity.encode(current)) && same) && Native.same_meaning(original, meaning)),
            SafeText.string_equal(identity, semantic), String.eq(identity, semantic), TextProof.public_refines(identity, semantic)),
          Equal.cong(Bool, Bool, (bound => (String.eq(key, UIIdentity.encode(current)) && String.eq(identity, semantic)) && bound),
            Native.same_meaning(original, meaning), Rule.required_field_binding(original, meaning), native_binding_requirement(original, meaning))))

def field_write_requirement(owned: Bool, binding: Native.Binding, found: Maybe<&2, SurfaceTypes.Node>) ->
  {update_spec(owned, binding, found) == Rule.required_field_write(owned, binding, found) : +List<Native.Update>}:
  match owned binding found:
    case False{} retained ignored: {==}
    case True{} retained None{}: {==}
    case True{} Native.Binding{+key, kind, identity, original} Some{SurfaceTypes.Node{current, +semantic, label, role, +meaning, children}}:
      native_projection_requirement(kind, key, semantic, meaning)

def native_found_requirement(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>) ->
  {Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})) ==
    Rule.required_field_write(Rule.required_mounted_field(binding, found), binding, found) : +List<Native.Update>}:
  +owned: Bool = Native.owned_node(binding, found)
  Equal.trans(+List<Native.Update>,
    Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})),
    update_spec(owned, binding, found), Rule.required_field_write(Rule.required_mounted_field(binding, found), binding, found),
    update_equation(binding, found),
    Equal.trans(+List<Native.Update>, update_spec(owned, binding, found), Rule.required_field_write(owned, binding, found),
      Rule.required_field_write(Rule.required_mounted_field(binding, found), binding, found),
      field_write_requirement(owned, binding, found),
      Equal.cong(Bool, +List<Native.Update>, (accepted => Rule.required_field_write(accepted, binding, found)),
        owned, Rule.required_mounted_field(binding, found), field_authority_requirement(binding, found))))

def native_field_requirement(+binding: Native.Binding, +nodes: +List<SurfaceTypes.Node>) ->
  {Native.update(binding, nodes) ==
    Rule.required_field_write(Rule.required_mounted_field(binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
      binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))) : +List<Native.Update>}:
  Native.Binding{+key, kind, identity, meaning} = binding
  +found: Maybe<&2, SurfaceTypes.Node> = InterfaceView.find_node(nodes, key)
  +required: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(nodes, key)
  Equal.trans(+List<Native.Update>, Native.update(binding, nodes),
    Rule.required_field_write(Rule.required_mounted_field(binding, found), binding, found),
    Rule.required_field_write(Rule.required_mounted_field(binding, required), binding, required),
    native_found_requirement(binding, found),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<Native.Update>,
      (node => Rule.required_field_write(Rule.required_mounted_field(binding, node), binding, node)),
      found, required, Rules_interface_program_rules.complete_node_lookup(nodes, key)))

def code_sources_spec(+qualified: Bool, +generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State) -> BrowserModel.Decision:
  match qualified:
    case False{}: BrowserModel.Decision{state, Nil{}}
    case True{}: BrowserModel.accept(True{}, BrowserModel.code_sources_fold(observations, Browser.Decision{BrowserModel.legacy(state), Nil{}}), state)

def code_sources_checked(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State, +qualified: Bool,
  observed: {BrowserModel.code_batch_qualified(generation, observations, state) == qualified : Bool}) ->
  {BrowserModel.code_sources_admitted(Categories.admit_checked(BrowserModel.CodeSourcesCandidate, BrowserModel.code_sources_predicate, BrowserModel.CodeSourcesCandidate{generation, observations, state}, qualified, observed), state) == code_sources_spec(qualified, generation, observations, state) : BrowserModel.Decision}:
  match qualified:
    case False{}: {==}
    case True{}: {==}

def code_sources_equation(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: BrowserModel.State) ->
  {BrowserModel.code_sources(generation, observations, state) == code_sources_spec(BrowserModel.code_batch_qualified(generation, observations, state), generation, observations, state) : BrowserModel.Decision}:
  code_sources_checked(generation, observations, state, BrowserModel.code_batch_qualified(generation, observations, state), {==})

def receipt_recorded(+receipt: Maybe<&2, Receipt.Receipt>, decision: Browser.Decision) ->
  {Browser.decision_receipt(Browser.receipt_decision(receipt, decision)) == receipt : Maybe<&2, Receipt.Receipt>}:
  match decision:
    case Browser.Decision{Browser.State{web, sequence, next, pending, previous}, effects}: {==}

def direct(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, state: Browser.State) ->
  Rule.direct_claim(ticket, received, world, code, message, command, origin, status, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.DirectCompletion{}, state))

def confirmation(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, selected: M.Command,
  trigger: String, destination: U.Route, occurrence: Nat, state: Browser.State) ->
  Rule.confirmation_claim(ticket, received, world, code, message, command, origin, status, selected, trigger, destination, occurrence, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.ConfirmationCompletion{selected, trigger, destination, occurrence}, state))

def unknown_receipt(ticket: Nat, reason: String, +state: Browser.State) ->
  {Browser.decision_receipt(Browser.failed_completion(ticket, reason, state)) == Browser.operation_receipt(state) : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def accepted_receipt(command: J.Json, completion: E.Completion, origin: String, state: Browser.State) ->
  {Browser.decision_receipt(Browser.request_ready(False{}, command, completion, origin, state)) == None{} : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def Rule.browser_receipt_evidence():
  Rule.BrowserReceiptRequirements{direct, confirmation,
    received => world => reply => +state => {==},
    draft => receipt => +decision => {==},
    ticket => reason => +state => unknown_receipt(ticket, reason, state),
    command => completion => origin => state => accepted_receipt(command, completion, origin, state)}

def supported(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.supported(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def owned(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.owned(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def Rule.frontend_utility_evidence():
  Rule.FrontendUtilityRequirements{supported, +font => +reason => {==}, owned}

def unchanged(+record: Native.Record, +value: String,
  proof: {Native.canonical_same(Native.record_canonical(record), value) == True{} : Bool}) -> Rule.unchanged_claim(value, record):
  match record:
    case Native.Record{identity, +canonical, +session}:
      Std.transport(Bool, True{},
        (same => {Native.synchronized(same, value, Native.Record{identity, canonical, session}) == Native.Decision{Native.Record{identity, canonical, session}, False{}, False{}} : Native.Decision}),
        {==}, Native.canonical_same(canonical, value), proof)

def unmatched(+binding: Native.Binding, +found: Maybe<&2, SurfaceTypes.Node>,
  proof: {Native.owned_node(binding, found) == False{} : Bool}) -> Rule.unmatched_claim(binding, found):
  Equal.trans(+List<Native.Update>, Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, found})),
    update_spec(Native.owned_node(binding, found), binding, found), Nil{}, update_equation(binding, found),
    Std.transport(Bool, False{},
      (owned => {update_spec(owned, binding, found) == Nil{} : +List<Native.Update>}),
      {==}, Native.owned_node(binding, found), proof))

def matching(+binding: Native.Binding, +node: SurfaceTypes.Node,
  proof: {Native.owned_node(binding, Some{node}) == True{} : Bool}) -> Rule.matching_claim(binding, node):
  match binding node:
    case Native.Binding{+key, +kind, identity, original} SurfaceTypes.Node{current, semantic, label, role, +meaning, children}:
      Equal.trans(+List<Native.Update>, Native.update_admitted(Categories.admit(Native.UpdateCandidate, Native.update_predicate, Native.UpdateCandidate{binding, Some{node}})),
        update_spec(Native.owned_node(binding, Some{node}), binding, Some{node}), Native.projected(key, kind, semantic, meaning), update_equation(binding, Some{node}),
        Std.transport(Bool, True{},
          (owned => {update_spec(owned, Native.Binding{key, kind, identity, original}, Some{SurfaceTypes.Node{current, semantic, label, role, meaning, children}}) == Native.projected(key, kind, semantic, meaning) : +List<Native.Update>}),
          {==}, Native.owned_node(binding, Some{node}), proof))

def changed_composing(+identity: Maybe<&2, Native.Identity>, +old: Maybe<&2, String>, +value: String,
  proof: {Native.canonical_same(old, value) == False{} : Bool}) -> Rule.changed_composing_claim(identity, old, value):
  Std.transport(Bool, False{},
    (same => {Native.synchronized(same, value, Native.Record{identity, old, Native.Composing{}}) == Native.Decision{Native.Record{identity, Some{value}, Native.SupersededComposing{}}, False{}, True{}} : Native.Decision}),
    {==}, Native.canonical_same(old, value), proof)

def transaction(+record: Native.Record) -> Rule.transaction_claim(record):
  match record:
    case Native.Record{identity, canonical, session}: {==}

def equal_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == True{} : Bool}) -> Rule.equal_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, True{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{old}, canonical, session}, False{}, False{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)

def changed_rebind(+old: Native.Identity, +identity: Native.Identity, +canonical: Maybe<&2, String>, +session: Native.Session,
  proof: {Native.same_identity(old, identity) == False{} : Bool}) -> Rule.changed_rebind_claim(old, identity, canonical, session):
  Std.transport(Bool, False{},
    (same => {Native.rebound(same, identity, Native.Record{Some{old}, canonical, session}) == Native.Decision{Native.Record{Some{identity}, canonical, Native.rebind_session(session)}, False{}, True{}} : Native.Decision}),
    {==}, Native.same_identity(old, identity), proof)

def rejected_buffer(+value: String, +record: Native.Record) -> Rule.rejected_buffer_claim(value, record):
  match record:
    case Native.Record{identity, canonical, Native.Idle{}}: {==}
    case Native.Record{identity, canonical, Native.Composing{}}: {==}
    case Native.Record{identity, canonical, Native.SupersededComposing{}}: {==}
    case Native.Record{identity, canonical, Native.SupersededTail{}}: {==}

def Rule.native_fields_evidence():
  Rule.NativeFieldsRequirements{
    +identity => +canonical => +session => {==},
    +old => +identity => +canonical => +session => proof => equal_rebind(old, identity, canonical, session, proof),
    +old => +identity => +canonical => +session => proof => changed_rebind(old, identity, canonical, session, proof),
    {==},
    {==},
    +editor => +other => +field => +entry => +value => +choices => +new_field => +new_entry => +new_value => +new_choices => {==},
    +value => +record => proof => unchanged(record, value, proof),
    +binding => +found => proof => unmatched(binding, found, proof),
    +binding => +node => proof => matching(binding, node, proof),
    +identity => +old => +value => proof => changed_composing(identity, old, value, proof),
    +value => +record => rejected_buffer(value, record),
    +identity => +value => +session => rejected_buffer(value, Native.Record{identity, Some{value}, session}),
    +identity => +old => +value => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +identity => +canonical => {==},
    +record => transaction(record),
    +key => +semantic => +meaning => native_projection_requirement(Source.ToggleField{}, key, semantic, meaning),
    +key => +semantic => +meaning => native_projection_requirement(Source.TextField{}, key, semantic, meaning)}

def Rule.updates_empty(nodes): {==}

def Rule.updates_complete(binding, rest, nodes): {==}

def Rule.updates_basis(fields, controls, surface): {==}

def Rule.update_owner(key, kind, semantic, meaning, nodes): {==}

def Rule.all_field_projections(kind, key, semantic, meaning):
  match kind:
    case Source.TextField{}: native_projection_requirement(Source.TextField{}, key, semantic, meaning)
    case Source.MessageField{}: native_projection_requirement(Source.MessageField{}, key, semantic, meaning)
    case Source.TextAreaField{}: native_projection_requirement(Source.TextAreaField{}, key, semantic, meaning)
    case Source.SelectField{}: native_projection_requirement(Source.SelectField{}, key, semantic, meaning)
    case Source.MultiSelectField{}: native_projection_requirement(Source.MultiSelectField{}, key, semantic, meaning)
    case Source.ToggleField{}: native_projection_requirement(Source.ToggleField{}, key, semantic, meaning)
    case Source.NumberField{minimum}: native_projection_requirement(Source.NumberField{minimum}, key, semantic, meaning)
    case Source.RangeField{minimum, maximum, step}: native_projection_requirement(Source.RangeField{minimum, maximum, step}, key, semantic, meaning)
    case Source.DecimalField{minimum, maximum, step}: native_projection_requirement(Source.DecimalField{minimum, maximum, step}, key, semantic, meaning)
    case Source.FileField{multiple}: native_projection_requirement(Source.FileField{multiple}, key, semantic, meaning)
    case Source.DirectoryField{}: native_projection_requirement(Source.DirectoryField{}, key, semantic, meaning)
    case Source.SearchField{}: native_projection_requirement(Source.SearchField{}, key, semantic, meaning)
    case Source.SecretField{}: native_projection_requirement(Source.SecretField{}, key, semantic, meaning)

def Rule.edit_text_rejected(key, text, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_text(key, text, state), edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state),
    BrowserModel.Decision{state, Nil{}}, edit_text_equation(key, text, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_text_owned_spec(allowed, key, text, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.edit_text_accepted(key, text, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_text(key, text, state), edit_text_owned_spec(BrowserModel.field_owned(key, state), key, text, state),
    BrowserModel.accept(True{}, Browser.edit_text(key, text, BrowserModel.legacy(state)), state), edit_text_equation(key, text, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_text_owned_spec(allowed, key, text, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.edit_structured_text_rejected(key, text, parsed, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_structured_text(key, text, parsed, state), edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state),
    BrowserModel.Decision{state, Nil{}}, edit_structured_text_equation(key, text, parsed, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_structured_text_owned_spec(allowed, key, text, parsed, state)),
      BrowserModel.structured_text_owned(key, state), False{}, owned))

def Rule.edit_structured_text_accepted(key, text, parsed, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_structured_text(key, text, parsed, state), edit_structured_text_owned_spec(BrowserModel.structured_text_owned(key, state), key, text, parsed, state),
    BrowserModel.accept(True{}, Browser.edit_structured_text(key, text, parsed, BrowserModel.legacy(state)), state), edit_structured_text_equation(key, text, parsed, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_structured_text_owned_spec(allowed, key, text, parsed, state)),
      BrowserModel.structured_text_owned(key, state), True{}, owned))

def Rule.confirm_text_rejected(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state), confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state),
    BrowserModel.Decision{state, Nil{}}, confirm_text_equation(key, keyboard, composing, control, alt, shift, meta, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.confirm_text_accepted(key, keyboard, composing, control, alt, shift, meta, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.confirm_text(key, keyboard, composing, control, alt, shift, meta, state), confirm_text_owned_spec(BrowserModel.field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state),
    BrowserModel.accept(True{}, Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, BrowserModel.legacy(state)), state), confirm_text_equation(key, keyboard, composing, control, alt, shift, meta, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => confirm_text_owned_spec(allowed, key, keyboard, composing, control, alt, shift, meta, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.edit_toggle_rejected(key, enabled, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_toggle(key, enabled, state), edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state),
    BrowserModel.Decision{state, Nil{}}, edit_toggle_equation(key, enabled, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_toggle_owned_spec(allowed, key, enabled, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.edit_toggle_accepted(key, enabled, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.edit_toggle(key, enabled, state), edit_toggle_owned_spec(BrowserModel.field_owned(key, state), key, enabled, state),
    BrowserModel.accept(True{}, Browser.edit_toggle(key, enabled, BrowserModel.legacy(state)), state), edit_toggle_equation(key, enabled, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => edit_toggle_owned_spec(allowed, key, enabled, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def Rule.attach_rejected(key, file, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.attach(key, file, state), attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state),
    BrowserModel.Decision{state, Nil{}}, attach_equation(key, file, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => attach_owned_spec(allowed, key, file, state)),
      BrowserModel.field_owned(key, state), False{}, owned))

def Rule.attach_accepted(key, file, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.attach(key, file, state), attach_owned_spec(BrowserModel.field_owned(key, state), key, file, state),
    BrowserModel.accept(True{}, Browser.attach(key, file, BrowserModel.legacy(state)), state), attach_equation(key, file, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (allowed => attach_owned_spec(allowed, key, file, state)),
      BrowserModel.field_owned(key, state), True{}, owned))

def removed_choice_absent(+same: Bool, +entry: Browser.Pending,
  +rest: +List<Browser.Pending>, +ticket: Nat,
  matching: {Nat.is_eq(Browser.ticket_of(entry), ticket) == same : Bool},
  absent: {Browser.owns_ticket(rest, ticket) == False{} : Bool}) ->
  {Browser.owns_ticket(Browser.choose_removed(same, entry, rest), ticket) == False{} : Bool}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(Bool,
        Browser.owns_ticket(entry <> rest, ticket),
        Browser.owned_choice(False{}, Browser.owns_ticket(rest, ticket)),
        False{},
        Equal.cong(Bool, Bool,
          (selected => Browser.owned_choice(selected, Browser.owns_ticket(rest, ticket))),
          Nat.is_eq(Browser.ticket_of(entry), ticket), False{}, matching), absent)

def consumed_ticket(+pending: +List<Browser.Pending>, +ticket: Nat) ->
  {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool}:
  match pending:
    case Nil{}: {==}
    case Con{+entry, rest}:
      Browser.Pending{current, completion, command, origin, status} = entry
      removed_choice_absent(Nat.is_eq(current, ticket), entry, Browser.remove(rest, ticket), ticket,
        {==}, consumed_ticket(rest, ticket))

# A stale snapshot never touches the program or any local interaction state.

def stale_snapshot(+received: Nat, +world: M.World(), +state: Browser.State,
  stale: {Nat.is_lt(Rule.sequence(state), received) == False{} : Bool}) ->
  {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Browser.State{web, current, next, pending, receipt} = state
  Equal.cong(Bool, Browser.Decision,
    (newer => Browser.snapshot_new(newer, received, world, Browser.State{web, current, next, pending, receipt})),
    Nat.is_lt(current, received), False{}, stale)

def uncertain_entry_ticket(hit: Bool, entry: Browser.Pending, reason: String) ->
  {Browser.ticket_of(Browser.mark_uncertain(hit, entry, reason)) == Browser.ticket_of(entry) : Nat}:
  match hit:
    case False{}: {==}
    case True{}:
      Browser.Pending{ticket, completion, command, origin, status} = entry
      {==}

def uncertain_retains_tickets(+requests: +List<Browser.Pending>, +ticket: Nat, +reason: String, +observed: Nat) ->
  {Browser.owns_ticket(Browser.uncertain_pending(requests, ticket, reason), observed) ==
    Browser.owns_ticket(requests, observed) : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.trans(Bool,
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), Browser.owns_ticket(rest, observed)),
        Equal.cong(Nat, Bool,
          (key => Browser.owned_choice(Nat.is_eq(key, observed), Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed))),
          Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), Browser.ticket_of(entry),
          uncertain_entry_ticket(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)),
        Equal.cong(Bool, Bool,
          (tail => Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), tail)),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed), Browser.owns_ticket(rest, observed),
          uncertain_retains_tickets(rest, ticket, reason, observed)))

def document_key_event(+key: String, +shift: Bool, +state: Browser.State) -> Rule.document_key_event_law(key, shift, state):
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}, sequence, next, requests, receipt} = state
  {==}

def receipt_input(observation: F.Observation, state: Browser.State) ->
  {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision}:
  {==}

def finish_unchanged_transport(web: Web.State, core: InteractionTypes.State, effects: +List<Web.Effect>, sequence: Nat,
  next: Nat, pending: +List<Browser.Pending>, origin: String) ->
  {Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  match core:
    case InteractionTypes.State{application, services}: {==}

def finished_receipt_transport(decision: Web.Decision, +core: InteractionTypes.State,
  unchanged: {Web.product(decision) == Platform.unchanged(core) : InteractionTypes.Decision},
  +sequence: Nat, +next: Nat, +pending: +List<Browser.Pending>, +origin: String) ->
  {Rule.transport(Browser.finish(decision, sequence, next, pending, origin, None{})) == (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  Web.Decision{+web, +product, +effects} = decision
  Equal.trans((Nat & (Nat & +List<Browser.Pending>)),
    Rule.transport(Browser.finish(Web.Decision{web, product, effects}, sequence, next, pending, origin, None{})),
    Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})),
    (sequence, (next, pending)),
    Equal.cong(InteractionTypes.Decision, (Nat & (Nat & +List<Browser.Pending>)),
      (current => Rule.transport(Browser.finish(Web.Decision{web, current, effects}, sequence, next, pending, origin, None{}))),
      product, Platform.unchanged(core), unchanged),
    finish_unchanged_transport(web, core, effects, sequence, next, pending, origin))

def nodes_current_surface(+web: Web.State, sequence: Nat, next: Nat, +pending: +List<Browser.Pending>) ->
  {Browser.nodes(Browser.State{web, sequence, next, pending, None{}}) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(web)), pending))) : +List<SurfaceTypes.Node>}:
  match web:
    case Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}: {==}

def state_measurements_transport_evidence(+model_state: Browser.State, +observation: F.Observation) ->
  {Rule.transport(Browser.measurements(observation, Browser.with_receipt(None{}, model_state))) ==
    (Browser.sequence(model_state), (Browser.next_ticket(model_state), Browser.pending(model_state))) : (Nat & (Nat & +List<Browser.Pending>))}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  finished_receipt_transport(Web.step(Web.TypographyObserved{observation}, web),
    Interaction.model_core(Interaction.model_application(web)), Proof_laws.typography_product(web, observation), sequence, next, pending, "")

def state_nodes_current_surface_evidence(+model_state: Browser.State) ->
  {Browser.nodes(Browser.with_receipt(None{}, model_state)) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(Browser.web(model_state))), Browser.pending(model_state)))) : +List<SurfaceTypes.Node>}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  nodes_current_surface(web, sequence, next, pending)

def state_failed_transition_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, error), model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_preserves_web_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Rule.web_state(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))) == Browser.web(model_state) : Web.State}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_retains_ticket_evidence(+model_state: Browser.State, ticket: Nat, error: String, observed: Nat) ->
  {Browser.owns_ticket(Rule.pending(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))), observed) ==
        Browser.owns_ticket(Browser.pending(model_state), observed) : Bool}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  uncertain_retains_tickets(requests, ticket, error, observed)

def state_admitted_request_evidence(+model_state: Browser.State, command: J.Json, completion: E.Completion, origin: String) ->
  {Browser.request_ready(False{}, command, completion, origin, Browser.with_receipt(None{}, model_state)) ==
          Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(List.append(&2, Browser.Pending, Browser.pending(model_state), [Browser.Pending{Browser.next_ticket(model_state), completion, command, origin, Browser.AwaitingReceipt{}}]), Browser.with_next_ticket((Browser.next_ticket(model_state) + 1n : Nat), model_state))),
            [Browser.Command{Browser.next_ticket(model_state), command}]} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def state_stale_completion_evidence(+model_state: Browser.State, ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion) ->
  {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.with_receipt(None{}, model_state)), reply, completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state))) : Browser.Decision}:
  Browser.State{+web, +current, +next, +pending, +original_1} = model_state
  {==}

def Rule.browser_evidence():
  Rule.BrowserRequirements{
    state_measurements_transport_evidence,
    finish_unchanged_transport,
    receipt_input,
    state_nodes_current_surface_evidence,
    Rules_interface_program_rules.interface_evidence(),
    +input => +state => {==},
    input => +state => {==},
    document_key_event,
    state_failed_transition_evidence,
    tab => escape => shift => realization => state => {==},
    state_failed_preserves_web_evidence,
    state_failed_retains_ticket_evidence,
    consumed_ticket,
    stale_snapshot,
    state_admitted_request_evidence,
    state_stale_completion_evidence}

def stale_frames(+received: Nat, +frame: Rendered.Frame, +state: BrowserModel.State,
  proof: {BrowserModel.frame_owned(received, state) == False{} : Bool}) ->
  Rule.stale_frames_claim(received, frame, state):
  Equal.trans(BrowserModel.Decision, BrowserModel.receive_frame(received, frame, state), received_frame_spec(BrowserModel.frame_owned(received, state), received, frame, state),
    BrowserModel.Decision{state, Nil{}}, receive_frame_equation(received, frame, state),
    Std.transport(Bool, False{},
      (owned => {received_frame_spec(owned, received, frame, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.frame_owned(received, state), proof))

def stale_measurements(+received: BrowserModel.MeasurementTicket, +tokens: +List<String>, +state: BrowserModel.State,
  proof: {BrowserModel.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measured(received, tokens, state), measured_current_spec(BrowserModel.measurement_owned(received, state), received, tokens, state),
    BrowserModel.Decision{state, Nil{}}, physical_measured_equation(received, tokens, state),
    Std.transport(Bool, False{},
      (owned => {measured_current_spec(owned, received, tokens, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(received, state), proof))

def ready_document(+rendering_capacity: Nat, +legacy: Browser.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface, +attention: Navigation.Attention, +updates: BrowserModel.DisplayUpdates) ->
  Rule.ready_document_claim(BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{layout_capacity, engine, semantic}, Some{BrowserModel.published(world, layout_capacity, legacy, semantic)}, attention, updates}, rendering_capacity, layout_capacity, engine, world, semantic):
  match legacy:
    case Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}:
      match world:
        case Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}: {==}

def anchor_preserves_program(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: BrowserModel.State) ->
  Rule.anchor_preserves_program_claim(key, left, top, width, height, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match legacy:
        case Browser.State{web, sequence, ticket, pending, receipt}:
          match web:
            case Web.State{application, generation, realization, environment, font}:
              match environment:
                case Design.Environment{viewport, dark, root}:
                  match viewport:
                    case Design.Viewport{viewport_width, viewport_height}: {==}

def policy_spec(+accepted: Bool, +capacity: Nat, +state: BrowserModel.State) -> BrowserModel.Publication:
  match accepted:
    case True{}: BrowserModel.KeepPublished{BrowserModel.native_updates(state)}
    case False{}: BrowserModel.published_document(capacity, state)

def policy_checked(+capacity: Nat, +last: Nat, +state: BrowserModel.State, +accepted: Bool,
  observed: {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == accepted : Bool}) ->
  {BrowserModel.publication_policy_admitted(capacity, Categories.admit_checked(BrowserModel.PublicationCandidate, BrowserModel.publication_policy_predicate, BrowserModel.PublicationCandidate{capacity, last, state}, accepted, observed), state) == policy_spec(accepted, capacity, state) : BrowserModel.Publication}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def policy_equation(+capacity: Nat, +last: Nat, +state: BrowserModel.State) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == policy_spec(BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), capacity, state) : BrowserModel.Publication}:
  policy_checked(capacity, last, state, BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), {==})

def keep_policy(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  accepted: {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == True{} : Bool}) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  Equal.trans(BrowserModel.Publication, BrowserModel.publication_policy_at(capacity, last, state),
    policy_spec(BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), capacity, state),
    BrowserModel.KeepPublished{BrowserModel.native_updates(state)}, policy_equation(capacity, last, state),
    Equal.cong(Bool, BrowserModel.Publication, value => policy_spec(value, capacity, state),
      BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), True{}, accepted))

def pending_policy(+existing: Bool, pending: Bool, +ready: Bool, +current: Bool,
  waiting: {pending && ready && current == True{} : Bool}) ->
  {existing && ready && current == existing : Bool}:
  match existing pending ready current:
    case True{} True{} True{} True{}: {==}
    case True{} True{} True{} False{}: Logic.impossible({True{} && True{} && False{} == True{} : Bool}, waiting)
    case True{} True{} False{} True{}: Logic.impossible({True{} && False{} && True{} == True{} : Bool}, waiting)
    case True{} True{} False{} False{}: Logic.impossible({True{} && False{} && False{} == True{} : Bool}, waiting)
    case True{} False{} True{} True{}: Logic.impossible({True{} && True{} && True{} == True{} : Bool}, waiting)
    case True{} False{} True{} False{}: Logic.impossible({True{} && True{} && False{} == True{} : Bool}, waiting)
    case True{} False{} False{} True{}: Logic.impossible({True{} && False{} && True{} == True{} : Bool}, waiting)
    case True{} False{} False{} False{}: Logic.impossible({True{} && False{} && False{} == True{} : Bool}, waiting)
    case False{} True{} True{} True{}: {==}
    case False{} True{} True{} False{}: Logic.impossible({False{} && True{} && False{} == False{} : Bool}, waiting)
    case False{} True{} False{} True{}: Logic.impossible({False{} && False{} && True{} == False{} : Bool}, waiting)
    case False{} True{} False{} False{}: Logic.impossible({False{} && False{} && False{} == False{} : Bool}, waiting)
    case False{} False{} True{} True{}: Logic.impossible({False{} && True{} && True{} == False{} : Bool}, waiting)
    case False{} False{} True{} False{}: Logic.impossible({False{} && True{} && False{} == False{} : Bool}, waiting)
    case False{} False{} False{} True{}: Logic.impossible({False{} && False{} && True{} == False{} : Bool}, waiting)
    case False{} False{} False{} False{}: Logic.impossible({False{} && False{} && False{} == False{} : Bool}, waiting)

def pending_predicate(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  waiting: {Rule.publication_pending(last, state) == True{} : Bool}) ->
  {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == Bool.not(Nat.is_eq(last, 0n)) : Bool}:
  pending_policy(Bool.not(Nat.is_eq(last, 0n)), Rule.pending_lifecycle(BrowserModel.lifecycle(state)),
    BrowserModel.display_ready(state), Nat.is_eq(BrowserModel.displayed_generation(state), last), waiting)

def pending_publication_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(last, state) == True{} : Bool}) ->
  {BrowserModel.publication_policy_at(capacity, last, state) == BrowserModel.KeepPublished{BrowserModel.native_updates(state)} : BrowserModel.Publication}:
  keep_policy(capacity, last, state,
    Equal.trans(Bool, BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}), Bool.not(Nat.is_eq(last, 0n)), True{}, pending_predicate(capacity, last, state, waiting), existing))

def publication_preserves_pending_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  waiting: {Rule.publication_pending(last, state) == True{} : Bool}) -> Rule.publication_preserves_pending_claim_at(capacity, last, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.WaitingFont{}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.Measuring{index, layout_capacity, engine, semantic, round}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: pending_publication_at(capacity, last, state, existing, waiting)
        case BrowserModel.UtilityDisplaying{purpose, engine}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.UtilityRejected{problem}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.Displaying{layout_capacity, engine, semantic}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)
        case BrowserModel.Blocked{problem}: Logic.impossible(Rule.publication_preserves_pending_claim_at(capacity, last, state), waiting)

def blocked_publication_at(+capacity: Nat, +last_published: Nat, +legacy: Browser.State, +serial: Nat,
  +anchors: +List<Shell.Anchor>, +problem: String, +displayed: Maybe<&2, BrowserModel.Published>, +attention: Navigation.Attention, +updates: BrowserModel.DisplayUpdates) -> Rule.blocked_publication_claim_at(BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed, attention, updates}, capacity, last_published, problem):
  {==}

def current_predicate(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  ready: {BrowserModel.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}) ->
  {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, state}) == True{} : Bool}:
  Std.transport(Bool, True{},
    (has_existing => {has_existing && BrowserModel.display_ready(state) && Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}),
    Std.transport(Bool, True{},
      (is_ready => {True{} && is_ready && Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}),
      Std.transport(Bool, True{},
        (is_current => {True{} && True{} && is_current == True{} : Bool}),
        {==}, Nat.is_eq(BrowserModel.displayed_generation(state), last), current),
      BrowserModel.display_ready(state), ready), Bool.not(Nat.is_eq(last, 0n)), existing)

def publication_current_at(+capacity: Nat, +last: Nat, +state: BrowserModel.State,
  existing: {Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool},
  +ready: {BrowserModel.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(BrowserModel.displayed_generation(state), last) == True{} : Bool}) -> Rule.publication_current_claim_at(capacity, last, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.Displaying{layout_capacity, engine, semantic}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.WaitingFont{}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, layout_capacity, engine, semantic, round}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, None{}, attention, updates}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityRejected{problem}, Some{published}, attention, updates}: Logic.impossible(Rule.publication_current_claim_at(capacity, last, state), ready)
    case BrowserModel.State{legacy, serial, anchors, BrowserModel.Blocked{problem}, displayed, attention, updates}: keep_policy(capacity, last, state, current_predicate(capacity, last, state, existing, ready, current))

def frame_capture_program(+frame: Rendered.Frame, +state: BrowserModel.State) -> Rule.frame_capture_program_claim(frame, state):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{world, semantic, scope, basis, old}}: {==}

def Rule.forwarded_frame_uses_published_surface(model_state, world, semantic, scope, basis, old, frame):
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +original_1, attention, +updates} = model_state
  {==}

def Rule.failed_font_candidate_blocked(model_state, font_generation, scale, index):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +realization, +environment, +original_1}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.unmet_frame_status(model_state, semantic, frame_generation, frame, violations, capacity, engine):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +original_2}, +serial, +anchors, +original_3, +displayed, attention, +updates} = model_state
  {==}

def eligible_fields(+enabled: Bool, +visible: Bool, +scroll: Bool,
  admitted: {enabled == True{} : Bool}, reachable: {visible || scroll == True{} : Bool}) ->
  {enabled && (visible || scroll) == True{} : Bool}:
  match enabled visible scroll:
    case False{} True{} True{}: admitted
    case False{} True{} False{}: admitted
    case False{} False{} True{}: admitted
    case False{} False{} False{}: admitted
    case True{} True{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} False{} False{}: reachable

def Rule.enabled_reachable_tab_member(element, admitted, reachable):
  match element:
    case Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds}:
      eligible_fields(enabled, visible, scroll, admitted, reachable)

def Rule.rejected_native_focus_preserves_state(generation, owner, identity, state, rejected):
  Equal.trans(BrowserModel.Decision, BrowserModel.native_focus_observed(generation, owner, identity, state), native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state),
    BrowserModel.Decision{state, Nil{}}, native_focus_observed_equation(generation, owner, identity, state),
    Equal.cong(Bool, BrowserModel.Decision,
      (owned => native_focus_if_owned_spec(owned, generation, owner, identity, state)),
      BrowserModel.native_observation_owned(generation, owner, identity, state), False{}, rejected))

def Rule.missing_native_frame_rejects(semantic, owner, identity): {==}

def stale_native_focus_spec(+generation: Nat, +owner: String, +identity: String, +state: BrowserModel.State,
  stale: {BrowserModel.frame_owned(generation, state) == False{} : Bool}) ->
  {native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}:
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match displayed:
        case None{}: {==}
        case Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
          Equal.cong(Bool, BrowserModel.Decision,
            (current => native_focus_if_owned_spec(current && BrowserModel.source_delegates(source, owner) &&
              Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && BrowserModel.native_frame_owned(frame, semantic, owner, identity), generation, owner, identity, state)),
            Nat.is_eq(generation, published), False{}, stale)

def Rule.stale_native_focus_preserves_state(generation, owner, identity, state, stale):
  Equal.trans(BrowserModel.Decision, BrowserModel.native_focus_observed(generation, owner, identity, state), native_focus_if_owned_spec(BrowserModel.native_observation_owned(generation, owner, identity, state), generation, owner, identity, state),
    BrowserModel.Decision{state, Nil{}}, native_focus_observed_equation(generation, owner, identity, state),
    stale_native_focus_spec(generation, owner, identity, state, stale))

def Rule.stale_measurement_failure(ticket, reason, state, stale):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measurement_failed(ticket, reason, state), measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state),
    BrowserModel.Decision{state, Nil{}}, physical_measurement_failed_equation(ticket, reason, state),
    Std.transport(Bool, False{},
      (owned => {measurement_failed_spec(owned, ticket, reason, state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(ticket, state), stale))

def Rule.current_measurement_failure(ticket, reason, state, owned):
  Equal.trans(BrowserModel.Decision, BrowserModel.physical_measurement_failed(ticket, reason, state), measurement_failed_spec(BrowserModel.measurement_owned(ticket, state), ticket, reason, state),
    BrowserModel.utility_measurement_failure(reason, state), physical_measurement_failed_equation(ticket, reason, state),
    Std.transport(Bool, True{},
      (accepted => {measurement_failed_spec(accepted, ticket, reason, state) == BrowserModel.utility_measurement_failure(reason, state) : BrowserModel.Decision}),
      {==}, BrowserModel.measurement_owned(ticket, state), owned))

def Rule.measurement_ownership_only_measuring(ticket, state, owned):
  match ticket:
    case BrowserModel.MeasurementTicket{generation, received_round}:
      match state:
        case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
          match lifecycle:
            case BrowserModel.Measuring{index, capacity, engine, semantic, round}: {==}
            case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
            case BrowserModel.UtilityDisplaying{purpose, engine}: owned
            case BrowserModel.UtilityRejected{problem}: owned
            case BrowserModel.WaitingEnvironment{}: owned
            case BrowserModel.WaitingFont{}: owned
            case BrowserModel.Displaying{capacity, engine, semantic}: owned
            case BrowserModel.Blocked{problem}: owned

def Rule.measurement_request_unavailable(state, inactive):
  match state:
    case BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.Blocked{problem}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityRejected{problem}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}:
          Logic.impossible({BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>}, Equal.sym(Bool, True{}, False{}, inactive))
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}:
          Logic.impossible(
            {BrowserModel.measurement_request(BrowserModel.State{legacy, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed, attention, updates}) == None{} : Maybe<&2, BrowserModel.MeasurementRequest>},
            Equal.sym(Bool, True{}, False{}, inactive))

def Rule.measurement_wrong_round(model_state, generation, received_round, round, index, capacity, engine, semantic, same_generation, stale_round):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention, +updates} = model_state
  Std.transport(Bool, True{},
    (same => {same && Nat.is_eq(received_round, round) == False{} : Bool}),
    Std.transport(Bool, False{},
      (same_round => {True{} && same_round == False{} : Bool}),
      {==}, Nat.is_eq(received_round, round), stale_round),
    Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))), same_generation)

def Rule.measurement_request_canonical(model_state, index, capacity, engine, semantic, round, generation, first, remaining, awaiting):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention, +updates} = model_state
  Std.transport(Plan.Plan, Plan.Awaiting{generation, first, remaining},
    (plan => {BrowserModel.measurement_request_plan(plan, World.snapshot_generation(World.snapshot(engine)), round) ==
      Some{BrowserModel.MeasurementRequest{BrowserModel.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round}, Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, BrowserModel.MeasurementRequest>}),
    {==}, World.plan(engine), awaiting)

def Rule.render_violations_unmet(model_state, observed_generation, frame, violations):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.render_violations_awaiting(model_state, observed_generation):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.render_violations_realized(model_state, observed_generation, frame):
  BrowserModel.State{Browser.State{Web.State{+application, +generation, +original_1, +environment, +font}, +sequence, +ticket, +pending, +receipt}, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.pending_frame_effects(state):
  match state:
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityRejected{problem}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, None{}, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, None{}}}, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, semantic, scope, basis, Some{frame}}}, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingEnvironment{}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.WaitingFont{}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Blocked{problem}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Realized{observed_generation, frame}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.Unmet{observed_generation, frame, violations}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, None{}, attention, updates}: {==}
    case BrowserModel.State{Browser.State{Web.State{application, generation, Rendered.AwaitingFrame{observed_generation}, environment, font}, sequence, ticket, pending, receipt}, serial, anchors, BrowserModel.Displaying{capacity, engine, semantic}, Some{BrowserModel.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}, attention, updates}: {==}

def Rule.retained_frame_decision(first, state):
  Std.transport(+List<Browser.Effect>, BrowserModel.pending_frame_effects(state),
    (effects => {BrowserModel.accepted(False{}, first, state) == BrowserModel.Decision{state,
      List.append(&2, Browser.Effect, first, effects)} : BrowserModel.Decision}),
    {==}, Rule.pending_frame_effects_expected(state),
    Equal.sym(+List<Browser.Effect>, BrowserModel.pending_frame_effects(state),
      Rule.pending_frame_effects_expected(state), Rule.pending_frame_effects(state)))

def Rule.non_rebuild_preserves_observed_decision(next, first, state):
  match state:
    case BrowserModel.State{previous, serial, anchors, lifecycle, displayed, attention, updates}:
      Rule.retained_frame_decision(first,
        BrowserModel.State{next, serial, anchors, lifecycle, displayed, attention, updates})

def Rule.rebuilt_frame_decision(first, state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.Measuring{index, capacity, engine, semantic, round}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.WaitingEnvironment{}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.WaitingFont{}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.Displaying{capacity, engine, semantic}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.UtilityDisplaying{purpose, engine}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.UtilityRejected{problem}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}
    case BrowserModel.State{legacy, generation, anchors, BrowserModel.Blocked{problem}, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def layer_owner_policy(values: +List<View.Layer>, fallback: Maybe<&2, String>) ->
  {InterfaceView.modal_layer_scope(values, fallback) == Rule.required_layer_owner(values, fallback) : Maybe<&2, String>}:
  match values:
    case Nil{}: {==}
    case Con{View.Layer{View.ModalDialog{}, content, initial, restore, dismissal}, rest}: {==}
    case Con{View.Layer{View.AnchoredMenu{}, content, initial, restore, dismissal}, rest}: {==}
    case Con{View.Layer{View.TrailingDetails{}, content, initial, restore, dismissal}, rest}: layer_owner_policy(rest, fallback)

def preview_owner_policy(preview: Services.Preview, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.preview(preview), tail)) == Rule.required_preview_owner(preview, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match preview:
    case Services.NoPreview{}: {==}
    case Services.LoadingPreview{ticket, file, trigger}: {==}
    case Services.ReadyPreview{file, resource, image, trigger}: {==}
    case Services.FailedPreview{file, reason, trigger}: {==}

def directory_owner_policy(picker: Services.DirectoryPicker, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.directory_picker(picker), tail)) == Rule.required_directory_owner(picker, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match picker:
    case Services.NoDirectoryPicker{}: {==}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: {==}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: {==}
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: {==}

def settings_owner_policy(open: Bool, +close: InteractionTypes.Input, +connect: InteractionTypes.Input, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.settings_visible(open, close, connect), tail)) == Rule.required_settings_owner(open, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match open:
    case False{}: {==}
    case True{}: {==}

def layers_owner_policy(values: +List<View.Layer>, +state: InteractionTypes.State, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.layers(values, state), tail)) == Rule.required_layer_owner(values, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match values:
    case Nil{}: {==}
    case Con{View.Layer{View.ModalDialog{}, content, initial, restore, dismissal}, rest}: {==}
    case Con{View.Layer{View.AnchoredMenu{}, content, initial, restore, dismissal}, rest}: {==}
    case Con{View.Layer{View.TrailingDetails{}, content, initial, restore, dismissal}, rest}: layers_owner_policy(rest, state, tail)

def compact_layer_head_owner(+selected: Bool, +kind: View.LayerKind, +key: UIIdentity.Key, +semantic: String, +label: String,
  +meaning: SurfaceTypes.Meaning, +children: +List<SurfaceTypes.Node>, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(Con{InterfaceView.compact_overview_when(selected,
      SurfaceTypes.Node{key, semantic, label, InterfaceView.layer_role(kind), meaning, children}), tail}) ==
    InterfaceView.active_scope(Con{SurfaceTypes.Node{key, semantic, label, InterfaceView.layer_role(kind), meaning, children}, tail}) : Maybe<&2, String>}:
  match selected kind:
    case False{} original: {==}
    case True{} View.ModalDialog{}: {==}
    case True{} View.AnchoredMenu{}: {==}
    case True{} View.TrailingDetails{}: {==}

def compact_layers_owner_policy(values: +List<View.Layer>, +state: InteractionTypes.State, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.compact_overview_layers(InterfaceView.layers(values, state)), tail)) ==
    Rule.required_layer_owner(values, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match values:
    case Nil{}: {==}
    case Con{View.Layer{View.ModalDialog{}, +content, +initial, restore, +dismissal}, +rest}:
      +key: UIIdentity.Key = InterfaceView.layer_key(initial)
      +label: String = InterfaceView.activity_layer_label(InterfaceView.layer_activity(content, state), ViewProgram.layer_title(content), state)
      +meaning: SurfaceTypes.Meaning = InterfaceView.layer_meaning(InterfaceView.layer_activity(content, state), dismissal)
      +children: +List<SurfaceTypes.Node> = InterfaceView.layer_content(content, key, state)
      +remaining: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.compact_overview_layers(InterfaceView.layers(rest, state)), tail)
      +selected: Bool = String.eq(UIIdentity.encode(key), UIIdentity.encode(InterfaceView.layer_key("work-overview")))
      compact_layer_head_owner(selected, View.ModalDialog{}, key, initial, label, meaning, children, remaining)
    case Con{View.Layer{View.AnchoredMenu{}, +content, +initial, restore, +dismissal}, +rest}:
      +key: UIIdentity.Key = InterfaceView.layer_key(initial)
      +label: String = InterfaceView.activity_layer_label(InterfaceView.layer_activity(content, state), ViewProgram.layer_title(content), state)
      +meaning: SurfaceTypes.Meaning = InterfaceView.layer_meaning(InterfaceView.layer_activity(content, state), dismissal)
      +children: +List<SurfaceTypes.Node> = InterfaceView.layer_content(content, key, state)
      +remaining: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.compact_overview_layers(InterfaceView.layers(rest, state)), tail)
      +selected: Bool = String.eq(UIIdentity.encode(key), UIIdentity.encode(InterfaceView.layer_key("work-overview")))
      compact_layer_head_owner(selected, View.AnchoredMenu{}, key, initial, label, meaning, children, remaining)
    case Con{View.Layer{View.TrailingDetails{}, +content, +initial, restore, +dismissal}, +rest}:
      +key: UIIdentity.Key = InterfaceView.layer_key(initial)
      +label: String = InterfaceView.activity_layer_label(InterfaceView.layer_activity(content, state), ViewProgram.layer_title(content), state)
      +meaning: SurfaceTypes.Meaning = InterfaceView.layer_meaning(InterfaceView.layer_activity(content, state), dismissal)
      +children: +List<SurfaceTypes.Node> = InterfaceView.layer_content(content, key, state)
      +remaining: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.compact_overview_layers(InterfaceView.layers(rest, state)), tail)
      +selected: Bool = String.eq(UIIdentity.encode(key), UIIdentity.encode(InterfaceView.layer_key("work-overview")))
      Equal.trans((Maybe<&2, String>),
        InterfaceView.active_scope(Con{InterfaceView.compact_overview_when(selected,
          SurfaceTypes.Node{key, initial, label, SurfaceTypes.Details{}, meaning, children}), remaining}),
        InterfaceView.active_scope(remaining), Rule.required_layer_owner(rest, InterfaceView.active_scope(tail)),
        compact_layer_head_owner(selected, View.TrailingDetails{}, key, initial, label, meaning, children, remaining),
        compact_layers_owner_policy(rest, state, tail))

def navigation_layers_owner_policy(full: Bool, +views: +List<View.Layer>, +state: InteractionTypes.State, +tail: +List<SurfaceTypes.Node>) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), tail)) ==
    Rule.required_layer_owner(views, InterfaceView.active_scope(tail)) : Maybe<&2, String>}:
  match full:
    case True{}: layers_owner_policy(views, state, tail)
    case False{}: compact_layers_owner_policy(views, state, tail)

def navigation_owner_policy(full: Bool, arrangement: View.Arrangement, nav: View.Navigation, state: InteractionTypes.State) ->
  {InterfaceView.active_scope(InterfaceView.workspace_modal_navigation(full, arrangement, nav, state)) == Rule.required_navigation_owner(arrangement) : Maybe<&2, String>}:
  match full arrangement nav:
    case True{} View.Arrangement{View.ModalNavigation{}} View.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} View.Arrangement{View.ModalNavigation{}} View.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case True{} View.Arrangement{View.LeadingNavigation{}} original: {==}
    case False{} View.Arrangement{View.LeadingNavigation{}} original: {==}
    case True{} View.Arrangement{View.CollapsedNavigation{}} original: {==}
    case False{} View.Arrangement{View.CollapsedNavigation{}} original: {==}

def layers_navigation_policy(+full: Bool, +views: +List<View.Layer>, +arrangement: View.Arrangement, +nav: View.Navigation, +state: InteractionTypes.State) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), InterfaceView.workspace_modal_navigation(full, arrangement, nav, state))) ==
    Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)) : Maybe<&2, String>}:
  Equal.trans((Maybe<&2, String>),
    InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), InterfaceView.workspace_modal_navigation(full, arrangement, nav, state))),
    Rule.required_layer_owner(views, InterfaceView.active_scope(InterfaceView.workspace_modal_navigation(full, arrangement, nav, state))),
    Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)), navigation_layers_owner_policy(full, views, state, InterfaceView.workspace_modal_navigation(full, arrangement, nav, state)),
    Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => Rule.required_layer_owner(views, owner)),
      InterfaceView.active_scope(InterfaceView.workspace_modal_navigation(full, arrangement, nav, state)), Rule.required_navigation_owner(arrangement), navigation_owner_policy(full, arrangement, nav, state)))

def settings_layers_policy(+full: Bool, +open: Bool, +close: InteractionTypes.Input, +connect: InteractionTypes.Input,
  +views: +List<View.Layer>, +arrangement: View.Arrangement, +nav: View.Navigation, +state: InteractionTypes.State) ->
  {InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.settings_visible(open, close, connect),
      List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), InterfaceView.workspace_modal_navigation(full, arrangement, nav, state)))) ==
    Rule.required_settings_owner(open, Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement))) : Maybe<&2, String>}:
  +tail: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), InterfaceView.workspace_modal_navigation(full, arrangement, nav, state))
  Equal.trans((Maybe<&2, String>), InterfaceView.active_scope(List.append(&2, SurfaceTypes.Node, InterfaceView.settings_visible(open, close, connect), tail)),
    Rule.required_settings_owner(open, InterfaceView.active_scope(tail)), Rule.required_settings_owner(open, Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement))),
    settings_owner_policy(open, close, connect, tail),
    Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => Rule.required_settings_owner(open, owner)),
      InterfaceView.active_scope(tail), Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)), layers_navigation_policy(full, views, arrangement, nav, state)))

def Rule.assembled_foreground_owner(full, scene, state):
  InteractionTypes.Scene{View.Scene{+nav, main, +views, +arrangement, attention}, InteractionTypes.Settings{+open, access, appearance, open_action, +close_action, +connect_action}, transfers, +preview, code, +picker} = scene
  +tail: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.settings_visible(open, close_action, connect_action),
    List.append(&2, SurfaceTypes.Node, InterfaceView.navigation_layers(full, InterfaceView.layers(views, state)), InterfaceView.workspace_modal_navigation(full, arrangement, nav, state)))
  +directory: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, InterfaceView.directory_picker(picker), tail)
  +required_tail: Maybe<&2, String> = Rule.required_settings_owner(open, Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)))
  Equal.trans((Maybe<&2, String>), Rule.surface_owner(InterfaceView.assemble(full, scene, state)),
    Rule.required_preview_owner(preview, InterfaceView.active_scope(directory)), Rule.required_foreground_owner(scene), preview_owner_policy(preview, directory),
    Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => Rule.required_preview_owner(preview, owner)),
      InterfaceView.active_scope(directory), Rule.required_directory_owner(picker, required_tail),
      Equal.trans((Maybe<&2, String>), InterfaceView.active_scope(directory), Rule.required_directory_owner(picker, InterfaceView.active_scope(tail)), Rule.required_directory_owner(picker, required_tail),
        directory_owner_policy(picker, tail),
        Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => Rule.required_directory_owner(picker, owner)), InterfaceView.active_scope(tail), required_tail,
          settings_layers_policy(full, open, close_action, connect_action, views, arrangement, nav, state)))))

def scene_navigation_owner_policy(arrangement: View.Arrangement) ->
  {InterfaceView.navigation_scope(arrangement) == Rule.required_navigation_owner(arrangement) : Maybe<&2, String>}:
  match arrangement:
    case View.Arrangement{View.ModalNavigation{}}: {==}
    case View.Arrangement{View.LeadingNavigation{}}: {==}
    case View.Arrangement{View.CollapsedNavigation{}}: {==}

def scene_settings_owner_policy(open: Bool, fallback: Maybe<&2, String>) ->
  {InterfaceView.settings_scope(open, fallback) == Rule.required_settings_owner(open, fallback) : Maybe<&2, String>}:
  match open:
    case False{}: {==}
    case True{}: {==}

def scene_directory_owner_policy(picker: Services.DirectoryPicker, fallback: Maybe<&2, String>) ->
  {InterfaceView.directory_scope(picker, fallback) == Rule.required_directory_owner(picker, fallback) : Maybe<&2, String>}:
  match picker:
    case Services.NoDirectoryPicker{}: {==}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: {==}
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: {==}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: {==}

def scene_preview_owner_policy(preview: Services.Preview, fallback: Maybe<&2, String>) ->
  {InterfaceView.preview_scope(preview, fallback) == Rule.required_preview_owner(preview, fallback) : Maybe<&2, String>}:
  match preview:
    case Services.NoPreview{}: {==}
    case Services.LoadingPreview{ticket, file, trigger}: {==}
    case Services.ReadyPreview{file, resource, image, trigger}: {==}
    case Services.FailedPreview{file, reason, trigger}: {==}

def scene_layer_owner_policy(+views: +List<View.Layer>, +arrangement: View.Arrangement) ->
  {InterfaceView.modal_layer_scope(views, InterfaceView.navigation_scope(arrangement)) ==
    Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)) : Maybe<&2, String>}:
  Equal.trans((Maybe<&2, String>), InterfaceView.modal_layer_scope(views, InterfaceView.navigation_scope(arrangement)),
    Rule.required_layer_owner(views, InterfaceView.navigation_scope(arrangement)),
    Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement)),
    layer_owner_policy(views, InterfaceView.navigation_scope(arrangement)),
    Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => Rule.required_layer_owner(views, owner)),
      InterfaceView.navigation_scope(arrangement), Rule.required_navigation_owner(arrangement), scene_navigation_owner_policy(arrangement)))

def Rule.scene_foreground_owner(scene, state):
  InteractionTypes.Scene{View.Scene{nav, main, +views, +arrangement, attention}, InteractionTypes.Settings{+open, access, appearance, open_action, close_action, connect_action}, transfers, +attachment, code, +folder_picker} = scene
  +layer: Maybe<&2, String> = Rule.required_layer_owner(views, Rule.required_navigation_owner(arrangement))
  +settings: Maybe<&2, String> = Rule.required_settings_owner(open, layer)
  +directory: Maybe<&2, String> = Rule.required_directory_owner(folder_picker, settings)
  Equal.trans((Maybe<&2, String>), InterfaceView.assembled_scope(scene, state),
    InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, InterfaceView.settings_scope(open, layer))),
    Rule.required_foreground_owner(scene),
    Equal.cong((Maybe<&2, String>), (Maybe<&2, String>),
      (owner => InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, InterfaceView.settings_scope(open, owner)))),
      InterfaceView.modal_layer_scope(views, InterfaceView.navigation_scope(arrangement)), layer, scene_layer_owner_policy(views, arrangement)),
    Equal.trans((Maybe<&2, String>),
      InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, InterfaceView.settings_scope(open, layer))),
      InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, settings)), Rule.required_foreground_owner(scene),
      Equal.cong((Maybe<&2, String>), (Maybe<&2, String>),
        (owner => InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, owner))),
        InterfaceView.settings_scope(open, layer), settings, scene_settings_owner_policy(open, layer)),
      Equal.trans((Maybe<&2, String>), InterfaceView.preview_scope(attachment, InterfaceView.directory_scope(folder_picker, settings)),
        InterfaceView.preview_scope(attachment, directory), Rule.required_foreground_owner(scene),
        Equal.cong((Maybe<&2, String>), (Maybe<&2, String>), (owner => InterfaceView.preview_scope(attachment, owner)),
          InterfaceView.directory_scope(folder_picker, settings), directory, scene_directory_owner_policy(folder_picker, settings)),
        scene_preview_owner_policy(attachment, directory))))

def Rule.current_foreground_owner(stored):
  match stored:
    case Browser.State{Web.State{Platform.State{core, +platform}, generation, realization, environment, font}, sequence, ticket, pending, receipt}:
      Rule.scene_foreground_owner(InterfaceCore.observe(Web.capacity(platform), core), core)

def scope_nodes_requirement(found: Maybe<&2, SurfaceTypes.Node>) ->
  {InterfaceView.scope_node(found) == FocusRules.required_scope_nodes(found) : +List<SurfaceTypes.Node>}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def active_nodes_requirement(+surface: SurfaceTypes.Surface) ->
  {InterfaceView.active_nodes(surface) == FocusRules.required_active_nodes(surface) : +List<SurfaceTypes.Node>}:
  SurfaceTypes.Surface{content, base, +overlays, scope} = surface
  match scope:
    case None{}: {==}
    case Some{+key}:
      Equal.trans(+List<SurfaceTypes.Node>, InterfaceView.scope_node(InterfaceView.find_node(overlays, key)),
        FocusRules.required_scope_nodes(InterfaceView.find_node(overlays, key)),
        FocusRules.required_scope_nodes(Rules_interface_program_rules.first_named_node(overlays, key)),
        scope_nodes_requirement(InterfaceView.find_node(overlays, key)),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<SurfaceTypes.Node>, FocusRules.required_scope_nodes,
          InterfaceView.find_node(overlays, key), Rules_interface_program_rules.first_named_node(overlays, key),
          Rules_interface_program_rules.complete_node_lookup(overlays, key)))

def dismiss_choice_requirement(first: Maybe<&2, Browser.DismissTarget>, rest: Maybe<&2, Browser.DismissTarget>) ->
  {Browser.first_dismiss_target(first, rest) == Maybe.or(&2, Browser.DismissTarget, first, rest) : Maybe<&2, Browser.DismissTarget>}:
  match first:
    case None{}: {==}
    case Some{target}: {==}

def dismiss_meaning_requirement(meaning: SurfaceTypes.Meaning, key: UIIdentity.Key,
  fallback: Maybe<&2, Browser.DismissTarget>) ->
  {Browser.declared_dismiss_target(SurfaceTypes.layer_region(meaning), key, fallback) ==
    Rule.required_dismissal(meaning, key, fallback) : Maybe<&2, Browser.DismissTarget>}:
  match meaning:
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value}: {==}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.MovableCard{destinations, face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardSearch{filter}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}
    case SurfaceTypes.InteractiveNode{node}: {==}
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: {==}
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: {==}
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.HistorySearchQuery{query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}

def dismiss_requirement(nodes: +List<SurfaceTypes.Node>) ->
  {Browser.dismiss_target(nodes) == Rule.required_dismiss_target(nodes) : Maybe<&2, Browser.DismissTarget>}:
  match nodes:
    case Nil{}: {==}
    case Con{SurfaceTypes.Node{+key, semantic, label, role, +meaning, +children}, +rest}:
      +child: Maybe<&2, Browser.DismissTarget> = Browser.dismiss_target(children)
      +tail: Maybe<&2, Browser.DismissTarget> = Browser.dismiss_target(rest)
      +required_child: Maybe<&2, Browser.DismissTarget> = Rule.required_dismiss_target(children)
      +required_tail: Maybe<&2, Browser.DismissTarget> = Rule.required_dismiss_target(rest)
      +fallback: Maybe<&2, Browser.DismissTarget> = Maybe.or(&2, Browser.DismissTarget, child, tail)
      Equal.trans((Maybe<&2, Browser.DismissTarget>), Browser.dismiss_target(nodes),
        Browser.declared_dismiss_target(SurfaceTypes.layer_region(meaning), key, fallback), Rule.required_dismiss_target(nodes),
        Equal.cong((Maybe<&2, Browser.DismissTarget>), (Maybe<&2, Browser.DismissTarget>),
          (next => Browser.declared_dismiss_target(SurfaceTypes.layer_region(meaning), key, next)),
          Browser.first_dismiss_target(child, tail), fallback, dismiss_choice_requirement(child, tail)),
        Equal.trans((Maybe<&2, Browser.DismissTarget>),
          Browser.declared_dismiss_target(SurfaceTypes.layer_region(meaning), key, fallback),
          Rule.required_dismissal(meaning, key, fallback), Rule.required_dismiss_target(nodes),
          dismiss_meaning_requirement(meaning, key, fallback),
          Equal.trans((Maybe<&2, Browser.DismissTarget>),
            Rule.required_dismissal(meaning, key, fallback),
            Rule.required_dismissal(meaning, key, Maybe.or(&2, Browser.DismissTarget, required_child, tail)),
            Rule.required_dismissal(meaning, key, Maybe.or(&2, Browser.DismissTarget, required_child, required_tail)),
            Equal.cong((Maybe<&2, Browser.DismissTarget>), (Maybe<&2, Browser.DismissTarget>),
              (found => Rule.required_dismissal(meaning, key, Maybe.or(&2, Browser.DismissTarget, found, tail))), child, required_child, dismiss_requirement(children)),
            Equal.cong((Maybe<&2, Browser.DismissTarget>), (Maybe<&2, Browser.DismissTarget>),
              (found => Rule.required_dismissal(meaning, key, Maybe.or(&2, Browser.DismissTarget, required_child, found))), tail, required_tail, dismiss_requirement(rest)))))

def inspection_frame_requirement(frame: Maybe<&2, Rendered.Frame>, +active: +List<SurfaceTypes.Node>,
  +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Browser.DismissTarget>) ->
  {BrowserModel.inspect_frame(frame, active, layer, dismiss) == Rule.inspection_frame_expected(frame, active, layer, dismiss) : BrowserModel.RenderInspection}:
  match frame:
    case None{}: {==}
    case Some{Rendered.Frame{+viewport, +elements, +focused, +tabs, +native_focus}}:
      +observed: Rendered.Frame = Rendered.Frame{viewport, elements, focused, tabs, native_focus}
      Equal.trans(BrowserModel.RenderInspection, BrowserModel.inspect_frame(Some{observed}, active, layer, dismiss),
        BrowserModel.RenderInspection{Some{observed}, Some{FrameSpec.expected_tabs(active, elements, native_focus)}, Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss},
        Rule.inspection_frame_expected(Some{observed}, active, layer, dismiss),
        Equal.cong(+List<String>, BrowserModel.RenderInspection,
          (order => BrowserModel.RenderInspection{Some{observed}, Some{order}, Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss}),
          Rendered.expected_tabs(active, elements, native_focus), FrameSpec.expected_tabs(active, elements, native_focus), FrameRules.complete_ordered_tabs(active, elements, native_focus)),
        Equal.cong(Bool, BrowserModel.RenderInspection,
          (valid => BrowserModel.RenderInspection{Some{observed}, Some{FrameSpec.expected_tabs(active, elements, native_focus)}, Some{valid}, layer, dismiss}),
          Rendered.native_valid(native_focus, active, elements), FrameSpec.native_valid(native_focus, active, elements), FrameRules.complete_native_ownership(native_focus, active, elements)))

def realization_frame_requirement(realization: Rendered.State) ->
  {BrowserModel.realization_frame(realization) == Rule.inspection_frame(realization) : Maybe<&2, Rendered.Frame>}:
  match realization:
    case Rendered.AwaitingFrame{generation}: {==}
    case Rendered.Realized{generation, frame}: {==}
    case Rendered.Unmet{generation, frame, violations}: {==}

def inspection_display_requirement(+frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>,
  +displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.inspect_published(frame, layer, displayed) ==
    Rule.inspection_display_expected(frame, layer, displayed) : BrowserModel.RenderInspection}:
  match displayed:
    case None{}: {==}
    case Some{BrowserModel.Published{world, +semantic, scope, basis, published_frame}}:
      +active: +List<SurfaceTypes.Node> = InterfaceView.active_nodes(semantic)
      +required: +List<SurfaceTypes.Node> = FocusRules.required_active_nodes(semantic)
      Equal.trans(BrowserModel.RenderInspection, BrowserModel.inspect_published(frame, layer, displayed),
        BrowserModel.inspect_frame(frame, required, layer, Browser.dismiss_target(required)), Rule.inspection_display_expected(frame, layer, displayed),
        Equal.cong(+List<SurfaceTypes.Node>, BrowserModel.RenderInspection,
          (nodes => BrowserModel.inspect_frame(frame, nodes, layer, Browser.dismiss_target(nodes))), active, required, active_nodes_requirement(semantic)),
        Equal.trans(BrowserModel.RenderInspection, BrowserModel.inspect_frame(frame, required, layer, Browser.dismiss_target(required)),
          BrowserModel.inspect_frame(frame, required, layer, Rule.required_dismiss_target(required)), Rule.inspection_display_expected(frame, layer, displayed),
          Equal.cong((Maybe<&2, Browser.DismissTarget>), BrowserModel.RenderInspection,
            (target => BrowserModel.inspect_frame(frame, required, layer, target)), Browser.dismiss_target(required), Rule.required_dismiss_target(required), dismiss_requirement(required)),
          inspection_frame_requirement(frame, required, layer, Rule.required_dismiss_target(required))))


def inspection_product_at(+stored: Browser.State, +displayed: Maybe<&2, BrowserModel.Published>, +layer: Maybe<&2, String>) ->
  {BrowserModel.inspect_published(BrowserModel.realization_frame(Web.realization(Browser.web(stored))), layer, displayed) ==
    Rule.inspection_display_expected(Rule.inspection_frame(Web.realization(Browser.web(stored))), layer, displayed) : BrowserModel.RenderInspection}:
  +actual: Maybe<&2, Rendered.Frame> = BrowserModel.realization_frame(Web.realization(Browser.web(stored)))
  +required: Maybe<&2, Rendered.Frame> = Rule.inspection_frame(Web.realization(Browser.web(stored)))
  Equal.trans(BrowserModel.RenderInspection, BrowserModel.inspect_published(actual, layer, displayed),
    Rule.inspection_display_expected(actual, layer, displayed), Rule.inspection_display_expected(required, layer, displayed),
    inspection_display_requirement(actual, layer, displayed),
    Equal.cong((Maybe<&2, Rendered.Frame>), BrowserModel.RenderInspection,
      (frame => Rule.inspection_display_expected(frame, layer, displayed)), actual, required,
      realization_frame_requirement(Web.realization(Browser.web(stored)))))

def inspection_product(+stored: Browser.State, +displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.render_inspection_owned(False{}, stored, displayed) == Rule.inspection_owned_expected(False{}, stored, displayed) : BrowserModel.RenderInspection}:
  Equal.trans(BrowserModel.RenderInspection,
    BrowserModel.render_inspection_owned(False{}, stored, displayed),
    BrowserModel.inspect_published(BrowserModel.realization_frame(Web.realization(Browser.web(stored))),
      Rule.required_current_layer_key(stored), displayed),
    Rule.inspection_owned_expected(False{}, stored, displayed),
    Equal.cong((Maybe<&2, String>), BrowserModel.RenderInspection,
      (layer => BrowserModel.inspect_published(BrowserModel.realization_frame(Web.realization(Browser.web(stored))), layer, displayed)),
      Browser.current_layer_key(stored), Rule.required_current_layer_key(stored), Rule.current_foreground_owner(stored)),
    inspection_product_at(stored, displayed, Rule.required_current_layer_key(stored)))

def utility_inspection_requirement(displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.utility_inspection(displayed) == Rule.inspection_utility_expected(displayed) : BrowserModel.RenderInspection}:
  match displayed:
    case None{}: {==}
    case Some{BrowserModel.Published{+world, semantic, scope, basis, +frame}}:
      +actual: BrowserModel.RenderInspection = BrowserModel.utility_inspection(displayed)
      +with_expected: BrowserModel.RenderInspection = BrowserModel.RenderInspection{frame, Some{SourceFrame.tabs(FrameSpec.allocated_expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}
      +with_tabs: BrowserModel.RenderInspection = BrowserModel.RenderInspection{frame, Some{FrameSpec.allocated_tabs(FrameSpec.allocated_expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}
      Equal.trans(BrowserModel.RenderInspection, actual, with_expected, Rule.inspection_utility_expected(displayed),
        Equal.cong(+List<SourceFrame.Expected>, BrowserModel.RenderInspection,
          (entries => BrowserModel.RenderInspection{frame, Some{SourceFrame.tabs(entries)}, Some{SourceFrame.no_native(world)}, None{}, None{}}),
          SourceFrame.expected(world), FrameSpec.allocated_expected(world), FrameEvidence.allocated_expected(world)),
        Equal.trans(BrowserModel.RenderInspection, with_expected, with_tabs, Rule.inspection_utility_expected(displayed),
          Equal.cong(+List<String>, BrowserModel.RenderInspection,
            (order => BrowserModel.RenderInspection{frame, Some{order}, Some{SourceFrame.no_native(world)}, None{}, None{}}),
            SourceFrame.tabs(FrameSpec.allocated_expected(world)), FrameSpec.allocated_tabs(FrameSpec.allocated_expected(world)), FrameEvidence.allocated_tabs(FrameSpec.allocated_expected(world))),
          Equal.cong(Bool, BrowserModel.RenderInspection,
            (valid => BrowserModel.RenderInspection{frame, Some{FrameSpec.allocated_tabs(FrameSpec.allocated_expected(world))}, Some{valid}, None{}, None{}}),
            SourceFrame.no_native(world), FrameSpec.allocated_no_native(world), FrameEvidence.allocated_no_native(world))))

def inspection_owned(+utility: Bool, +stored: Browser.State, +displayed: Maybe<&2, BrowserModel.Published>) ->
  {BrowserModel.render_inspection_owned(utility, stored, displayed) == Rule.inspection_owned_expected(utility, stored, displayed) : BrowserModel.RenderInspection}:
  match utility:
    case True{}: utility_inspection_requirement(displayed)
    case False{}: inspection_product(stored, displayed)

def Rule.render_inspection(model_state):
  BrowserModel.State{+stored, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  inspection_owned(BrowserModel.auxiliary_owned(BrowserModel.State{stored, serial, anchors, lifecycle, displayed, attention, updates}), stored, displayed)

def state_ready_document_evidence(+model_state: BrowserModel.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface) ->
  Rule.ready_document_claim(BrowserModel.with_displayed(Some{BrowserModel.published(world, layout_capacity, BrowserModel.legacy(model_state), semantic)}, BrowserModel.with_lifecycle(BrowserModel.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +original_2, attention, +updates} = model_state
  ready_document(rendering_capacity, legacy, serial, anchors, layout_capacity, engine, world, semantic, attention, updates)

def state_blocked_publication_at_evidence(+model_state: BrowserModel.State, +capacity: Nat, +last_published: Nat, +problem: String) ->
  Rule.blocked_publication_claim_at(BrowserModel.with_lifecycle(BrowserModel.Blocked{problem}, model_state), capacity, last_published, problem):
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention, +updates} = model_state
  blocked_publication_at(capacity, last_published, legacy, serial, anchors, problem, displayed, attention, updates)

def Rule.evidence():
  Rule.Requirements{
    +shift => +identity => +initial => +restore => +occurrence => +basis => +semantic => +frame => +state => {==},
    Rule.native_fields_evidence,
    +frame => +state => frame_capture_program(frame, state),
    +key => +shift => +basis => +semantic => +frame => +state => {==},
    +received => +frame => +state => proof => stale_frames(received, frame, state, proof),
    +received => +tokens => +state => proof => stale_measurements(received, tokens, state, proof),
    state_ready_document_evidence,
    +key => +left => +top => +width => +height => +state => anchor_preserves_program(key, left, top, width, height, state),
    +capacity => +last_published => +state => existing => waiting => publication_preserves_pending_at(capacity, last_published, state, existing, waiting),
    state_blocked_publication_at_evidence,
    +capacity => +last_published => +state => existing => +ready => current => publication_current_at(capacity, last_published, state, existing, ready, current)}

def Rule.unconfirmed_publication_has_no_focus_feedback(document, fields, ticket, before, after):
  match before:
    case None{}: {==}
    case Some{target}:
      match after:
        case None{}: {==}
        case Some{target}: {==}

def Rule.retained_publication_has_no_focus_feedback(fields, ticket, before, after): {==}

def Rule.absent_focus_has_no_publication_feedback(publication, ticket, after):
  match publication:
    case BrowserModel.KeepPublished{fields}: {==}
    case BrowserModel.Publish{generation, document, fields}: {==}

def Rule.owned_focus_has_no_publication_feedback(publication, ticket, before, after):
  match publication:
    case BrowserModel.KeepPublished{fields}: {==}
    case BrowserModel.Publish{generation, document, fields}:
      match before:
        case None{}: {==}
        case Some{target}: {==}

def Rule.confirmed_publication_focus_loss(generation, document, fields, ticket, before, confirmed):
  Equal.trans(Maybe<&2, Platform.Input>, BrowserModel.publication_focus_current(generation, ticket, before),
    publication_focus_spec(Bool.not(Nat.is_eq(generation, 0n)), ticket, before), Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}},
    publication_focus_equation(generation, ticket, before),
    Std.transport(Bool, True{},
      (ready => {publication_focus_spec(ready, ticket, before) == Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}),
      {==}, Bool.not(Nat.is_eq(generation, 0n)), confirmed))

def Rule.failure_message(key, axis, required, available, reason):
  match axis:
    case Allocation.InlineAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}
    case Allocation.BlockAxis{}:
      match reason:
        case Allocation.AuthoredRangeConflict{}: {==}
        case Allocation.InsufficientSpace{}: {==}
        case Allocation.AllocationBoundExceeded{budget}: {==}

def Rule.infeasible_candidate_retries(index, state, failure): {==}

def Rule.infeasible_candidate_reports(model_state, index, failure):
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.selected_infeasible(failure, index, capacity, engine, state, semantic, round): {==}

def state_utility_publication_evidence(+model_state: BrowserModel.State, +world: Content.AllocatedWorld, +purpose: Utility.Purpose, +engine: World.Engine) ->
  {BrowserModel.utility_publish(world, purpose, engine, model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(Some{BrowserModel.Published{world, BrowserModel.current_legacy_surface(BrowserModel.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, BrowserModel.with_lifecycle(BrowserModel.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def state_correlated_frame_evidence(+model_state: BrowserModel.State, +frame: Rendered.Frame, +world: Content.AllocatedWorld, +semantic: SurfaceTypes.Surface, +scope: Focus.Scope, +basis: Native.Basis, +old: Maybe<&2, Rendered.Frame>) ->
  {BrowserModel.correlated_frame_owned(True{}, frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) ==
        BrowserModel.utility_frame_result(world, frame, BrowserModel.with_displayed(Some{BrowserModel.Published{world, semantic, scope, basis, old}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +original_1, attention, +updates} = model_state
  {==}

def state_correlated_measurement_failure_evidence(+model_state: BrowserModel.State, +purpose: Utility.Purpose, +engine: World.Engine, +round: Nat, +reason: String) ->
  {BrowserModel.utility_measurement_failure(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        BrowserModel.utility_fallback(reason, BrowserModel.with_lifecycle(BrowserModel.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +original_1, +displayed, attention, +updates} = model_state
  {==}

def state_rejected_frame_evidence(+model_state: BrowserModel.State, +first: Rendered.Violation, +rest: +List<Rendered.Violation>, +frame: Rendered.Frame) ->
  {BrowserModel.utility_frame_rejection(model_state) ==
        BrowserModel.Decision{BrowserModel.with_displayed(None{}, BrowserModel.with_lifecycle(BrowserModel.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : BrowserModel.Decision}:
  BrowserModel.State{+legacy, +serial, +anchors, +lifecycle, +displayed, attention, +updates} = model_state
  {==}

def Rule.recovery_evidence():
  Rule.RecoveryRequirements{
    Rule.frontend_utility_evidence(),
    FrameRules.source_frame_evidence(),
    +capacity => +lifecycle => +world => +font => {==},
    +capacity => +lifecycle => +font => {==},
    state_utility_publication_evidence,
    state_correlated_frame_evidence,
    +world => +purpose => +engine => +round => +glyph_only => +state => {==},
    state_correlated_measurement_failure_evidence,
    +frame => +state => {==},
    state_rejected_frame_evidence,
    +state => {==},
    +state => {==},
    +input => +state => {==}}

def project_request_at(+fields: +List<J.Field>, +operation: String,
  observed: {J.text(J.get(J.Object{fields}, "op")) == operation : String}) ->
  {Request.client(J.Object{fields}) == Request.object_request(operation, fields) : J.Json}:
  Equal.cong(String, J.Json, selected => Request.object_request(selected, fields),
    J.text(J.get(J.Object{fields}, "op")), operation, observed)

def worktree_field_operation(+value: J.Json, +guidance: +List<J.Field>, +fields: +List<J.Field>, +operation: String,
  observed: {J.text(J.get(J.Object{fields}, "op")) == operation : String}) ->
  {J.text(J.get(J.Object{Codec.optional_field("create_worktree", value, J.Field{"guidance", J.Object{guidance}} <> fields)}, "op")) == operation : String}:
  match value:
    case J.Null{}: observed
    case J.Boolean{enabled}: observed
    case J.Number{lexeme}: observed
    case J.Text{text}: observed
    case J.Array{items}: observed
    case J.Object{entries}: observed

def worktree_guidance_fields(+value: J.Json, guidance: +List<J.Field>, +fields: +List<J.Field>,
  retained: {Request.without_guidance(fields) == fields : +List<J.Field>}) ->
  {Request.without_guidance(Codec.optional_field("create_worktree", value, J.Field{"guidance", J.Object{guidance}} <> fields)) ==
    Codec.optional_field("create_worktree", value, fields) : +List<J.Field>}:
  match value:
    case J.Null{}: retained
    case J.Boolean{enabled}:
      Equal.cong(+List<J.Field>, +List<J.Field>, kept => J.Field{"create_worktree", J.Boolean{enabled}} <> kept,
        Request.without_guidance(fields), fields, retained)
    case J.Number{lexeme}:
      Equal.cong(+List<J.Field>, +List<J.Field>, kept => J.Field{"create_worktree", J.Number{lexeme}} <> kept,
        Request.without_guidance(fields), fields, retained)
    case J.Text{text}:
      Equal.cong(+List<J.Field>, +List<J.Field>, kept => J.Field{"create_worktree", J.Text{text}} <> kept,
        Request.without_guidance(fields), fields, retained)
    case J.Array{items}:
      Equal.cong(+List<J.Field>, +List<J.Field>, kept => J.Field{"create_worktree", J.Array{items}} <> kept,
        Request.without_guidance(fields), fields, retained)
    case J.Object{entries}:
      Equal.cong(+List<J.Field>, +List<J.Field>, kept => J.Field{"create_worktree", J.Object{entries}} <> kept,
        Request.without_guidance(fields), fields, retained)

def project_payload(name: String, workspace: J.Json, guidance: +List<J.Field>, create_worktree: J.Json) ->
  {Browser.request_payload(M.CreateProject{name, workspace, J.Object{guidance}, create_worktree}) ==
    J.Object{Codec.optional_field("create_worktree", create_worktree,
      [J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}}, J.Field{"workspace", workspace}])} : J.Json}:
  +guidance_value: +List<J.Field> = guidance
  +worktree_value: J.Json = create_worktree
  +fields: +List<J.Field> = [J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}}, J.Field{"workspace", workspace}]
  +request = Codec.optional_field("create_worktree", worktree_value, J.Field{"guidance", J.Object{guidance_value}} <> fields)
  Equal.trans(J.Json, Request.client(J.Object{request}), Request.object_request("create_project", request),
    J.Object{Codec.optional_field("create_worktree", worktree_value, fields)},
    project_request_at(request, "create_project", worktree_field_operation(worktree_value, guidance_value, fields, "create_project", {==})),
    Equal.cong(+List<J.Field>, J.Json, kept => J.Object{kept}, Request.without_guidance(request),
      Codec.optional_field("create_worktree", worktree_value, fields), worktree_guidance_fields(worktree_value, guidance_value, fields, {==})))

def update_payload_fields(id: Nat, selected_name: Maybe<&2, String>, selected_workspace: J.Json) -> +List<J.Field>:
  Codec.optional_field("workspace", selected_workspace, Codec.optional_field("name", D.optional_string(selected_name),
    [J.Field{"op", J.Text{"update_project"}}, J.Field{"project_id", J.nat(id)}]))

def update_payload_operation(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json) ->
  {J.text(J.get(J.Object{update_payload_fields(id, selected_name, selected_workspace)}, "op")) == "update_project" : String}:
  match selected_name:
    case None{}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}
    case Some{selected}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}

def update_payload_retained(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json) ->
  {Request.without_guidance(update_payload_fields(id, selected_name, selected_workspace)) ==
    update_payload_fields(id, selected_name, selected_workspace) : +List<J.Field>}:
  match selected_name:
    case None{}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}
    case Some{selected}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}

def update_payload(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json, guidance: +List<J.Field>, +create_worktree: J.Json) ->
  {Browser.request_payload(M.UpdateProject{id, selected_name, selected_workspace, J.Object{guidance}, create_worktree}) ==
    Codec.command_json(M.UpdateProject{id, selected_name, selected_workspace, J.Null{}, create_worktree}) : J.Json}:
  +id_value: Nat = id
  +guidance_value: +List<J.Field> = guidance
  +fields = update_payload_fields(id_value, selected_name, selected_workspace)
  +request = Codec.optional_field("create_worktree", create_worktree, J.Field{"guidance", J.Object{guidance_value}} <> fields)
  Equal.trans(J.Json, Request.client(J.Object{request}), Request.object_request("update_project", request),
    J.Object{Codec.optional_field("create_worktree", create_worktree, fields)},
    project_request_at(request, "update_project", worktree_field_operation(create_worktree, guidance_value, fields, "update_project",
      update_payload_operation(id_value, selected_name, selected_workspace))),
    Equal.cong(+List<J.Field>, J.Json, kept => J.Object{kept}, Request.without_guidance(request),
      Codec.optional_field("create_worktree", create_worktree, fields), worktree_guidance_fields(create_worktree, guidance_value, fields,
        update_payload_retained(id_value, selected_name, selected_workspace))))

def unrelated_pending(+entry: Browser.Pending, +rest: +List<Browser.Pending>, +ticket: Nat,
  distinct: {Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool}) ->
  {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>}:
  Browser.Pending{current, completion, command, origin, status} = entry
  Equal.cong(Bool, +List<Browser.Pending>,
    (hit => Browser.choose_removed(hit, Browser.Pending{current, completion, command, origin, status}, Browser.remove(rest, ticket))),
    Nat.is_eq(current, ticket), False{}, distinct)

def confirmation_failed_world(owned: Bool, reason: String, destination: U.Route, +program: M.World(), session: E.Session) ->
  {Rule.decision_world(SessionRule.confirmation_result_spec(owned, D.failure("command_not_submitted", reason), destination,
    E.Application{program, session})) == program : M.World()}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def rejected_work_creation_world(current: Bool, reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.work_creation_spec(current, D.failure("command_not_submitted", reason), E.from_program(program, E.retain_previews(session, program)))) == program : M.World()}:
  match current:
    case False{}: {==}
    case True{}: {==}

def rejected_side_creation_world(current: Bool, draft: Maybe<&2, U.Draft>, reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.side_creation_spec(current, draft, D.failure("command_not_submitted", reason), E.from_program(program, E.retain_previews(session, program)))) == program : M.World()}:
  match current:
    case False{}: {==}
    case True{}: {==}

def interactive_result_world(result: InteractiveDocuments.Decision, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(E.interactive_result(result, E.Application{program, session})) == program : M.World()}:
  match result:
    case InteractiveDocuments.Decision{state, effects}: {==}

def rejected_valid_world(completion: E.Completion, +reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.valid_completion_spec(completion, program, D.failure("command_not_submitted", reason), session)) == program : M.World()}:
  match completion:
    case E.WorkCreationCompletion{generation, layer_generation}: rejected_work_creation_world(E.work_creation_current(generation, layer_generation, session), reason, program, session)
    case E.SideCreationCompletion{parent, +draft, generation, layer_generation}: rejected_side_creation_world(E.side_creation_current(parent, draft, generation, layer_generation, E.retain_previews(session, program)), draft, reason, program, session)
    case E.InteractiveCompletion{+owner, +path, +ticket}:
      +retained: E.Session = E.retain_previews(session, program)
      +application: E.Application = E.Application{program, retained}
      +result: J.Json = D.failure("command_not_submitted", reason)
      +actual: E.Decision = E.interactive_completed(owner, path, ticket, result, application)
      +required: E.Decision = SessionRule.interactive_completion_spec(owner, path, ticket, result, application)
      Equal.trans(M.World(), Rule.decision_world(required), Rule.decision_world(actual), program,
        Equal.cong(E.Decision, M.World(), (decision => Rule.decision_world(decision)), required, actual,
          Equal.sym(E.Decision, actual, required, SessionProof.interactive_completion_complete(owner, path, ticket, result, application))),
        interactive_result_world(InteractiveDocuments.input(Interactive.EffectCompleted{owner, path, ticket, False{}, reason},
          E.interactive_data(retained)), program, retained))
    case E.ExecutionCompletion{task, profile, reasoning, remember}: {==}
    case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: {==}
    case E.DirectCompletion{}: {==}
    case E.WorktreePreferenceCompletion{draft, command}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, +previews, code, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
      confirmation_failed_world(SessionRule.confirmation_spec(layers, command, trigger, occurrence), reason, destination, program,
        E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git, interactive}, program))

def rejected_checked_world(+valid: Bool, +completion: E.Completion, +reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(SessionRule.completion_checked_spec(valid, completion, program, D.failure("command_not_submitted", reason), session, program)) == program : M.World()}:
  match valid:
    case False{}: {==}
    case True{}: rejected_valid_world(completion, reason, program, session)

def rejected_world(+completion: E.Completion, +reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})) == program : M.World()}:
  Equal.trans(M.World(), Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})),
    Rule.decision_world(SessionRule.completion_spec(completion, program, D.failure("command_not_submitted", reason), session, program)), program,
    Equal.cong(E.Decision, M.World(), decision => Rule.decision_world(decision),
      E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session}),
      SessionRule.completion_spec(completion, program, D.failure("command_not_submitted", reason), session, program),
      SessionProof.completed_refinement(completion, program, D.failure("command_not_submitted", reason), session, program)),
    rejected_checked_world(WorldInvariant.world(program), completion, reason, program, session))

def omission_step(+same: Bool, +name: String, +value: J.Json, +rest: +List<J.Field>,
  matching: {String.eq(name, "guidance") == same : Bool},
  absent: {J.find(rest, "guidance") == J.Null{} : J.Json}) ->
  {J.find(Request.kept_field(same, J.Field{name, value}, rest), "guidance") == J.Null{} : J.Json}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(J.Json,
        J.choose_field(SafeText.string_equal(name, "guidance"), value, J.find(rest, "guidance")),
        J.choose_field(String.eq(name, "guidance"), value, J.find(rest, "guidance")), J.Null{},
        Equal.cong(Bool, J.Json, (hit => J.choose_field(hit, value, J.find(rest, "guidance"))),
          SafeText.string_equal(name, "guidance"), String.eq(name, "guidance"), TextProof.public_refines(name, "guidance")),
        Equal.trans(J.Json,
          J.choose_field(String.eq(name, "guidance"), value, J.find(rest, "guidance")),
          J.choose_field(False{}, value, J.find(rest, "guidance")), J.Null{},
          Equal.cong(Bool, J.Json, (hit => J.choose_field(hit, value, J.find(rest, "guidance"))),
            String.eq(name, "guidance"), False{}, matching), absent))

def owned_field_absent(+fields: +List<J.Field>) ->
  {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json}:
  match fields:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      omission_step(String.eq(name, "guidance"), name, value, Request.without_guidance(rest), {==}, owned_field_absent(rest))

def state_current_world_evidence(+model_state: E.Application, completion: E.Completion, reason: String) ->
  {Rule.decision_world(E.complete_command(E.program(model_state), D.failure("command_not_submitted", reason), completion, model_state)) == E.program(model_state) : M.World()}:
  E.Application{+program, +session} = model_state
  rejected_world(completion, reason, program, session)

def state_settlement_evidence(+model_state: Browser.State, ticket: Nat, completion: E.Completion, command: J.Json, origin: String, status: Browser.RequestStatus, reason: String) ->
  {Browser.rejected_pending(Some{Browser.Pending{ticket, completion, command, origin, status}}, reason,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), Browser.product_input(Product.CommandCompleted{Browser.program(Browser.with_receipt(None{}, model_state)),
            D.failure("command_not_submitted", reason), completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state)))) : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def state_stale_evidence(+model_state: Browser.State, +ticket: Nat, reason: String, stale: {Browser.find(Browser.pending(model_state), ticket) == None{} : Maybe<&2, Browser.Pending>}) ->
  {Browser.command_rejected(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, model_state), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  Equal.cong(Maybe<&2, Browser.Pending>, Browser.Decision,
    (found => Browser.rejected_pending(found, reason, Browser.State{web, sequence, next, pending, None{}})),
    Browser.find(pending, ticket), None{}, stale)

def state_uncertain_evidence(+model_state: Browser.State, ticket: Nat, reason: String) ->
  {Browser.failed_completion(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, reason), model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def Rule.request_evidence():
  Rule.RequestRequirements{
    state_current_world_evidence,
    owned_field_absent,
    profile => reasoning => message => fields => {==},
    id => count => messages => fields => {==},
    project_payload,
    update_payload,
    id => revision => name => profile => reasoning => instructions => fields => concurrency => {==},
    +name => +value => +rest => unrelated =>
      Equal.cong(Bool, +List<J.Field>,
        (owned => Request.kept_field(owned, J.Field{name, value}, Request.without_guidance(rest))),
        String.eq(name, "guidance"), False{}, unrelated),
    state_settlement_evidence,
    state_stale_evidence,
    +pending => +ticket => consumed_ticket(pending, ticket),
    unrelated_pending,
    revision => +body => feedback => directory_entry => submitted => +reason => {==},
    state_uncertain_evidence,
    id => message => {==}}

# Bind the application and display interfaces beside their representations.
def application_state(decision: Browser.Decision) -> Browser.State:
  Browser.Decision{state, effects} = decision
  state

def application_effects(decision: Browser.Decision) -> +List<Browser.Effect>:
  Browser.Decision{state, effects} = decision
  effects

def display_effects(decision: BrowserModel.Decision) -> +List<Browser.Effect>:
  BrowserModel.Decision{state, effects} = decision
  effects

def completion_dispatch(+ticket: Nat, +serial: Nat, +world: M.World(), +reply: J.Json, +state: Browser.State) ->
  {Browser.step(Browser.Completed{ticket, serial, world, reply}, state) ==
    Browser.completed(Browser.find(Browser.pending(state), ticket), serial, world, reply, state) : Browser.Decision}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def application_operations() -> Model.ApplicationOperations<M.World(), Browser.State, Browser.Input, Browser.Decision, Browser.Pending, Browser.Effect>:
  Model.ApplicationOperations{
      world => serial => Browser.initial(world, serial),
      user => Browser.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.UserInput{user}}}}}},
      serial => world => Browser.Snapshot{serial, world},
      ticket => serial => world => reply => Browser.Completed{ticket, serial, world, reply},
      input => state => Browser.step(input, state), decision => application_state(decision), decision => application_effects(decision),
      state => effects => Browser.Decision{state, effects},
      state => Browser.program(state), state => Browser.sequence(state),
      ticket => state => Browser.find(Browser.pending(state), ticket),
      serial => world => state => Browser.snapshot(serial, world, state),
      found => serial => world => reply => state => Browser.completed(found, serial, world, reply, state),
      capacity => state => Browser.semantic_surface(capacity, state)}

def application_model() -> Model.Application(M.World(), Browser.State, Browser.Input, Browser.Decision, Browser.Pending, Browser.Effect):
  Categories.Membership{
    application_operations(),
    Categories.Intersection{
      Model.ApplicationInitialization{world => serial => {==}},
      Categories.Intersection{
        Model.ApplicationCorrelation{
          serial => world => state => {==},
          ticket => serial => world => reply => state => completion_dispatch(ticket, serial, world, reply, state)},
        Model.ApplicationOrdering{
          serial => world => state => stale => stale_snapshot(serial, world, state, stale),
          serial => world => reply => state => {==}}}}}

def display_operations() -> Model.DisplayOperations<M.World(), Browser.State, Browser.Input, Browser.Effect, BrowserModel.State, BrowserModel.Decision, BrowserModel.Publication, +List<Native.Update>, Document.Document>:
  Model.DisplayOperations{
          world => serial => BrowserModel.initial(world, serial), state => BrowserModel.legacy(state),
          state => BrowserModel.program(state),
          input => state => BrowserModel.step(input, state), decision => BrowserModel.decision_state(decision),
          decision => display_effects(decision), capacity => state => BrowserModel.observe(capacity, state),
          capacity => last => state => BrowserModel.publication(capacity, last, state),
          last => state => Rule.publication_pending(last, state),
          state => BrowserModel.native_updates(state), fields => BrowserModel.KeepPublished{fields}}

def display_model() -> Model.DisplayModel(M.World(), Browser.State, Browser.Input, Browser.Effect,
  world => serial => Browser.initial(world, serial), state => Browser.program(state)):
  (BrowserModel.State, (BrowserModel.Decision, (BrowserModel.Publication,
    (+List<Native.Update>, (Document.Document,
      Categories.Membership{
        display_operations(),
        Categories.Intersection{
          Model.DisplayComposition{
            world => serial => {==},
            state => {==}},
          Model.DisplayRetention{capacity => last => state => published => pending =>
            publication_preserves_pending_at(capacity, last, state, published, pending)}}})))))

def Rule.supporting_mask_evidence(blocked, support, property, input, availability):
  match blocked:
    case True{}: {==}
    case False{}: {==}

def supporting_compact_ready(requirement: Maybe<&2, Adaptation.RegionDemand>) ->
  {BrowserModel.supporting_width_admitted(ControlsProgram.CompactSupporting{}, requirement) == True{} : Bool}:
  match requirement:
    case None{}: {==}
    case Some{Adaptation.RegionDemand{available, preferred}}: {==}

def Rule.supporting_admission_evidence():
  Rule.SupportingAdmissionRequirements{
    {==},
    +available => +preferred => {==},
    supporting_compact_ready,
    +index => +world => {==},
    +world => +index => +capacity => +engine => +state => +semantic => round => {==},
    +world => index => +capacity => +engine => +state => +semantic => {==},
    world => +index => capacity => engine => +state => semantic => {==},
    +index => +state => {==}}

def navigation_interest_keeps_legacy(+attention: Navigation.Attention, +state: BrowserModel.State) ->
  {BrowserModel.legacy(BrowserModel.with_attention(attention, state)) == BrowserModel.legacy(state) : Browser.State}:
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, previous, updates}: {==}

def fresh_attention_candidate(+state: BrowserModel.State) -> Rule.fresh_attention_candidate(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      match lifecycle:
        case BrowserModel.WaitingEnvironment{}: {==}
        case BrowserModel.WaitingFont{}: {==}
        case BrowserModel.Measuring{index, capacity, engine, semantic, round}: {==}
        case BrowserModel.Displaying{capacity, engine, semantic}: {==}
        case BrowserModel.UtilityMeasuring{purpose, engine, round, glyph_only}: {==}
        case BrowserModel.UtilityDisplaying{purpose, engine}: {==}
        case BrowserModel.UtilityRejected{problem}: {==}
        case BrowserModel.Blocked{problem}: {==}

def Rule.navigation_evidence():
  Rule.NavigationRequirements{
    navigation_interest_keeps_legacy,
    +attention => +state => {==},
    +attention => +state => {==},
    fresh_attention_candidate}

def Rule.reviewer_field_gesture(editor, entry, value, text, state): {==}


def Rule.role_calibration_request(capacity, state):
  F.activity_request_correspondence(capacity, BrowserModel.current_font(BrowserModel.legacy(state)))

def Rule.missing_activity_calibration_waits(physical_capacity, body, index, state):
  {==}

def Rule.actual_activity_calibration(physical_capacity, body, primary, support, index, state):
  {==}


def Rule.frozen_candidate_captures_latest_update(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}:
      {==}

def Rule.admitted_candidate_marks_active_update(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}:
      {==}

def Rule.completed_display_remains_ready_while_measuring(state, published, index, capacity, engine, semantic, round):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      {==}

def Rule.remeasurement_retains_active_candidate(state, index, capacity, engine, semantic, round):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      {==}

def Rule.invalidation_discards_active_and_displayed(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      {==}

def snapshot_expected_equation(+expected_namespace: String, +namespace: String, +sequence: Nat, +program: M.World(), +state: BrowserModel.State, +owned: Bool,
  observed: {String.eq(expected_namespace, BrowserModel.current_namespace(state)) == owned : Bool}) ->
  {BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state) ==
    BrowserModel.snapshot_scope(owned, namespace, sequence, program, state) : BrowserModel.Decision}:
  Equal.cong(Bool, BrowserModel.Decision,
    accepted => BrowserModel.snapshot_scope(accepted, namespace, sequence, program, state),
    String.eq(expected_namespace, BrowserModel.current_namespace(state)), owned, observed)

def valid_snapshot_equation(+expected_namespace: String, +namespace: String, +sequence: Nat, +program: M.World(), +state: BrowserModel.State,
  valid: {Live.valid_namespace(namespace) == True{} : Bool},
  owned: {String.eq(expected_namespace, BrowserModel.current_namespace(state)) == True{} : Bool}) ->
  {BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state) ==
    BrowserModel.snapshot_namespace(True{}, namespace, sequence, program, state) : BrowserModel.Decision}:
  Equal.trans(BrowserModel.Decision,
    BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state),
    BrowserModel.snapshot_namespace(Live.valid_namespace(namespace), namespace, sequence, program, state),
    BrowserModel.snapshot_namespace(True{}, namespace, sequence, program, state),
    snapshot_expected_equation(expected_namespace, namespace, sequence, program, state, True{}, owned),
    Equal.cong(Bool, BrowserModel.Decision,
      accepted => BrowserModel.snapshot_namespace(accepted, namespace, sequence, program, state),
      Live.valid_namespace(namespace), True{}, valid))

def snapshot_namespace_equation(+expected_namespace: String, +namespace: String, +sequence: Nat, +program: M.World(), +state: BrowserModel.State, +same: Bool,
  valid: {Live.valid_namespace(namespace) == True{} : Bool},
  owned: {String.eq(expected_namespace, BrowserModel.current_namespace(state)) == True{} : Bool},
  observed: {String.eq(BrowserModel.current_namespace(state), namespace) == same : Bool}) ->
  {BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state) ==
    BrowserModel.snapshot_current(Bool.not(same) || Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), Bool.not(same), namespace, sequence, program, state) : BrowserModel.Decision}:
  Equal.trans(BrowserModel.Decision,
    BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state),
    BrowserModel.snapshot_current(Bool.not(String.eq(BrowserModel.current_namespace(state), namespace)) || Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), Bool.not(String.eq(BrowserModel.current_namespace(state), namespace)), namespace, sequence, program, state),
    BrowserModel.snapshot_current(Bool.not(same) || Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), Bool.not(same), namespace, sequence, program, state),
    valid_snapshot_equation(expected_namespace, namespace, sequence, program, state, valid, owned),
    Equal.cong(Bool, BrowserModel.Decision,
      accepted => BrowserModel.snapshot_current(Bool.not(accepted) || Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), Bool.not(accepted), namespace, sequence, program, state),
      String.eq(BrowserModel.current_namespace(state), namespace), same, observed))

def Rule.atomic_snapshot_rejects_stale(expected_namespace, namespace, sequence, program, state, valid, owned, same, stale):
  Equal.trans(BrowserModel.Decision,
    BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state),
    BrowserModel.snapshot_current(Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), False{}, namespace, sequence, program, state),
    BrowserModel.Decision{state, Nil{}},
    snapshot_namespace_equation(expected_namespace, namespace, sequence, program, state, True{}, valid, owned, same),
    Equal.cong(Bool, BrowserModel.Decision,
      accepted => BrowserModel.snapshot_current(accepted, False{}, namespace, sequence, program, state),
      Nat.is_le(Browser.sequence(BrowserModel.legacy(state)), sequence), False{}, stale))

def refresh_web_effects(+effects: +List<Web.Effect>) ->
  {Browser.wrap_web(effects) == List.foldr(~&2, ~Web.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.BrowserEffect{effect} <> rest), effects, Nil{}) : +List<Browser.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{+effect, +rest}:
      Equal.cong((+List<Browser.Effect>), (+List<Browser.Effect>), (tail => Browser.BrowserEffect{effect} <> tail),
        Browser.wrap_web(rest), List.foldr(~&2, ~Web.Effect, ~(+List<Browser.Effect>), ~(item => tail => Browser.BrowserEffect{item} <> tail), rest, Nil{}), refresh_web_effects(rest))

def refresh_service_effects(+effects: +List<Services.Effect>) ->
  {Browser.wrap_services(effects) == List.foldr(~&2, ~Services.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.Service{effect} <> rest), effects, Nil{}) : +List<Browser.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{+effect, +rest}:
      Equal.cong((+List<Browser.Effect>), (+List<Browser.Effect>), (tail => Browser.Service{effect} <> tail),
        Browser.wrap_services(rest), List.foldr(~&2, ~Services.Effect, ~(+List<Browser.Effect>), ~(item => tail => Browser.Service{item} <> tail), rest, Nil{}), refresh_service_effects(rest))

def refresh_duplicate_delivered_meaning(+value: Web.Decision, +sequence: Nat, +ticket: Nat,
  +pending: +List<Browser.Pending>, +receipt: Maybe<&2, Receipt.Receipt>) ->
  {Browser.duplicate_completed(value, sequence, ticket, pending, receipt) ==
    Rule.refresh_duplicate_delivered(value, sequence, ticket, pending, receipt) : Browser.Decision}:
  Web.Decision{+web, InteractionTypes.Decision{+core, +reply, +runtime, +interaction, +services, +durable}, +effects} = value
  +physical = List.foldr(~&2, ~Web.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.BrowserEffect{effect} <> rest), effects, Nil{})
  +service = List.foldr(~&2, ~Services.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.Service{effect} <> rest), services, Nil{})
  Equal.trans(Browser.Decision, Browser.duplicate_completed(value, sequence, ticket, pending, receipt),
    Browser.Decision{Browser.State{web, sequence, ticket, pending, receipt}, List.append(&2, Browser.Effect, physical, Browser.wrap_services(services))},
    Rule.refresh_duplicate_delivered(value, sequence, ticket, pending, receipt),
    Equal.cong(+List<Browser.Effect>, Browser.Decision,
      (prefix => Browser.Decision{Browser.State{web, sequence, ticket, pending, receipt}, List.append(&2, Browser.Effect, prefix, Browser.wrap_services(services))}),
      Browser.wrap_web(effects), physical, refresh_web_effects(effects)),
    Equal.cong(+List<Browser.Effect>, Browser.Decision,
      (suffix => Browser.Decision{Browser.State{web, sequence, ticket, pending, receipt}, List.append(&2, Browser.Effect, physical, suffix)}),
      Browser.wrap_services(services), service, refresh_service_effects(services)))

def refresh_commit_requirement(+decision: Platform.Decision, +generation: Nat,
  +environment: Design.Environment, +font: F.State) ->
  {Web.production_commit(Platform.realized_decision(decision), generation, environment, font) ==
    WebRules.committed_decision(Rule.expected_realized_decision(decision), generation, environment, font) : Web.Decision}:
  Equal.trans(Web.Decision, Web.production_commit(Platform.realized_decision(decision), generation, environment, font),
    Web.production_commit(Rule.expected_realized_decision(decision), generation, environment, font),
    WebRules.committed_decision(Rule.expected_realized_decision(decision), generation, environment, font),
    Equal.cong(Platform.Decision, Web.Decision,
      (realized => Web.production_commit(realized, generation, environment, font)),
      Platform.realized_decision(decision), Rule.expected_realized_decision(decision), Rule.realized_decision_exact(decision)),
    WebRules.production_commit_complete(Rule.expected_realized_decision(decision), generation, environment, font))

def refresh_duplicate_request_meaning(+completion: E.Completion, +stored: Browser.State) ->
  {Browser.duplicate_request(completion, stored) == Rule.refresh_duplicate_request(completion, stored) : Browser.Decision}:
  match completion stored:
    case E.WorkCreationCompletion{generation, layer_generation} _: {==}
    case E.SideCreationCompletion{parent, draft, generation, layer_generation} _: {==}
    case E.WorktreePreferenceCompletion{draft, command} _: {==}
    case E.DirectCompletion{} _: {==}
    case E.DraftCompletion{draft} _: {==}
    case E.ExecutionCompletion{task, profile, reasoning, remember} _: {==}
    case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence} _: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence} _: {==}
    case E.InteractiveCompletion{+owner, +path, +feedback} Browser.State{Web.State{Platform.State{+core, +platform}, +generation, realization, +environment, +font}, +sequence, +ticket, +pending, +receipt}:
      Platform.Platform{+readers, +editors, +focused, +focus_ticket, +reduced, +capacity, +scope} = platform
      +decision = Platform.after_core(Product.step(Product.InterfaceInput{InteractionTypes.Interactive{
        Interactive.EffectCompleted{owner, path, feedback, False{}, "This command is already pending"}}}, core),
        Platform.Platform{readers, editors, focused, focus_ticket, reduced, capacity, scope})
      +committed = WebRules.committed_decision(Rule.expected_realized_decision(decision), (generation + 1n : Nat), environment, font)
      Equal.trans(Browser.Decision, Browser.duplicate_request(completion, stored),
        Browser.duplicate_completed(committed, sequence, ticket, pending, receipt), Rule.refresh_duplicate_request(completion, stored),
        Equal.cong(Web.Decision, Browser.Decision,
          (result => Browser.duplicate_completed(result, sequence, ticket, pending, receipt)),
          Web.production_commit(Platform.realized_decision(decision), (generation + 1n : Nat), environment, font), committed,
          refresh_commit_requirement(decision, (generation + 1n : Nat), environment, font)),
        refresh_duplicate_delivered_meaning(committed, sequence, ticket, pending, receipt))

def refresh_commands_meaning(+pending: +List<Browser.Pending>, +wire: J.Json) ->
  {Browser.contains_command(pending, wire) == Rule.refresh_command_present(wire, pending) : Bool}:
  match pending:
    case Nil{}: {==}
    case Con{Browser.Pending{ticket, completion, +command, origin, status}, +rest}:
      Equal.cong(Bool, Bool, (tail => J.same(command, wire) || tail),
        Browser.contains_command(rest, wire), Rule.refresh_command_present(wire, rest), refresh_commands_meaning(rest, wire))

def refresh_request_meaning(+duplicate: Bool, +wire: J.Json, +completion: E.Completion, +origin: String, +state: Browser.State) ->
  {Browser.request_ready(duplicate, wire, completion, origin, state) == Rule.refresh_command(duplicate, wire, completion, origin, state) : Browser.Decision}:
  match duplicate state:
    case True{} stored: refresh_duplicate_request_meaning(completion, stored)
    case False{} Browser.State{web, sequence, ticket, pending, receipt}: {==}

def Rule.duplicate_command_settles_its_feedback(wire, completion, origin, stored):
  refresh_duplicate_request_meaning(completion, stored)

def refresh_session_intents(+decision: E.Decision, +services: Services.State) ->
  {Rule.refresh_product_intents(InterfaceCore.application_result(decision, services)) == SessionRule.business_effects(decision) : +List<M.Effect()> & +List<E.Effect>}:
  match decision:
    case E.Decision{application, reply, runtime, interaction, durable}: {==}

def Rule.duplicate_feedback_has_no_business_intents(owner, path, ticket, core):
  match core:
    case InteractionTypes.State{+application, +services}:
      +result = D.failure("command_already_pending", "This command is already pending")
      +feedback = E.interactive_input(Interactive.EffectCompleted{owner, path, ticket, False{}, "This command is already pending"}, application)
      Equal.trans(+List<M.Effect()> & +List<E.Effect>,
        Rule.refresh_product_intents(Product.step(Product.InterfaceInput{InteractionTypes.Interactive{
          Interactive.EffectCompleted{owner, path, ticket, False{}, "This command is already pending"}}}, InteractionTypes.State{application, services})),
        SessionRule.business_effects(feedback), (Nil{}, Nil{}), refresh_session_intents(feedback, services),
        SessionRule.interactive_feedback_is_terminal(owner, path, ticket, result, application))

def refresh_append_meaning(+value: Browser.Decision, +before: +List<Browser.Effect>) ->
  {BrowserModel.synchronized_result(value, before) == Rule.refresh_append(value, before) : Browser.Decision}:
  match value:
    case Browser.Decision{state, effects}: {==}

def refresh_io_append_meaning(+value: Browser.Decision, +before: +List<Browser.Effect>) ->
  {Browser.append_decision(before, value) == Rule.refresh_append(value, before) : Browser.Decision}:
  match value:
    case Browser.Decision{state, effects}: {==}

def refresh_io_meaning(+effect: E.Effect, +origin: String, +state: Browser.State) ->
  {Browser.collect_one(effect, origin, state) == Rule.refresh_io(effect, origin, state) : Browser.Decision}:
  match effect:
    case E.RequestCommand{+command, +completion}:
      +wire = Request.client(Codec.command_json(command))
      Equal.trans(Browser.Decision, Browser.request_ready(Browser.contains_command(Browser.pending(state), wire), wire, completion, origin, state),
        Browser.request_ready(Rule.refresh_command_present(wire, Browser.pending(state)), wire, completion, origin, state),
        Rule.refresh_command(Rule.refresh_command_present(wire, Browser.pending(state)), wire, completion, origin, state),
        Equal.cong(Bool, Browser.Decision, (duplicate => Browser.request_ready(duplicate, wire, completion, origin, state)),
          Browser.contains_command(Browser.pending(state), wire), Rule.refresh_command_present(wire, Browser.pending(state)), refresh_commands_meaning(Browser.pending(state), wire)),
        refresh_request_meaning(Rule.refresh_command_present(wire, Browser.pending(state)), wire, completion, origin, state))
    case E.ContentEffect{identity, value}: {==}
    case E.ObserveWorkspaceGit{ticket, primary}: {==}
    case E.ObserveDirectories{ticket, entered}: {==}
    case E.LocateHistoryMessage{task, message_index}: {==}
    case E.Attend{target}: {==}
    case E.PersistModelPreference{profile, reasoning}: {==}
    case E.InteractiveEffect{value}: {==}
    case E.ObserveInteractiveMarkdown{document}: {==}
    case E.ForgetInteractiveMarkdown{key}: {==}

def refresh_io_step_meaning(+effect: E.Effect, +origin: String, +state: Browser.State, +before: +List<Browser.Effect>) ->
  {Browser.append_decision(before, Browser.collect_one(effect, origin, state)) == Rule.refresh_io_step(origin, Browser.Decision{state, before}, effect) : Browser.Decision}:
  Equal.trans(Browser.Decision,
    Browser.append_decision(before, Browser.collect_one(effect, origin, state)), Browser.append_decision(before, Rule.refresh_io(effect, origin, state)),
    Rule.refresh_append(Rule.refresh_io(effect, origin, state), before),
    Equal.cong(Browser.Decision, Browser.Decision, (result => Browser.append_decision(before, result)),
      Browser.collect_one(effect, origin, state), Rule.refresh_io(effect, origin, state), refresh_io_meaning(effect, origin, state)),
    refresh_io_append_meaning(Rule.refresh_io(effect, origin, state), before))

def refresh_io_fold(+effects: +List<E.Effect>, +origin: String, +accumulator: Browser.Decision) ->
  {Browser.collect_loop(effects, origin, accumulator) == Rule.refresh_io_sequence(effects, origin, accumulator) : Browser.Decision}:
  match effects accumulator:
    case Nil{} Browser.Decision{state, before}: {==}
    case Con{+effect, +rest} Browser.Decision{+state, +before}:
      +actual = Browser.append_decision(before, Browser.collect_one(effect, origin, state))
      +required = Rule.refresh_io_step(origin, Browser.Decision{state, before}, effect)
      Equal.trans(Browser.Decision, Browser.collect_loop(rest, origin, actual),
        Rule.refresh_io_sequence(rest, origin, actual), Rule.refresh_io_sequence(rest, origin, required),
        refresh_io_fold(rest, origin, actual),
        Equal.cong(Browser.Decision, Browser.Decision, (next => Rule.refresh_io_sequence(rest, origin, next)),
          actual, required, refresh_io_step_meaning(effect, origin, state, before)))

def refresh_collected_meaning(+value: Browser.Decision, +effects: +List<Web.Effect>, +services: +List<Services.Effect>) ->
  {Browser.collected_finish(value, effects, services) == Rule.refresh_completed(value, effects, services) : Browser.Decision}:
  Browser.Decision{+state, +requests} = value
  +web = List.foldr(~&2, ~Web.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.BrowserEffect{effect} <> rest), effects, Nil{})
  +service = List.foldr(~&2, ~Services.Effect, ~(+List<Browser.Effect>), ~(effect => rest => Browser.Service{effect} <> rest), services, Nil{})
  Equal.trans(Browser.Decision,
    Browser.collected_finish(value, effects, services),
    Browser.Decision{state, List.append(&2, Browser.Effect, web, List.append(&2, Browser.Effect, requests, Browser.wrap_services(services)))},
    Rule.refresh_completed(value, effects, services),
    Equal.cong((+List<Browser.Effect>), Browser.Decision,
      (prefix => Browser.Decision{state, List.append(&2, Browser.Effect, prefix, List.append(&2, Browser.Effect, requests, Browser.wrap_services(services)))}),
      Browser.wrap_web(effects), web, refresh_web_effects(effects)),
    Equal.cong((+List<Browser.Effect>), Browser.Decision,
      (suffix => Browser.Decision{state, List.append(&2, Browser.Effect, web, List.append(&2, Browser.Effect, requests, suffix))}),
      Browser.wrap_services(services), service, refresh_service_effects(services)))

def refresh_finish_meaning(+value: Web.Decision, +sequence: Nat, +ticket: Nat, +pending: +List<Browser.Pending>, +receipt: Maybe<&2, Receipt.Receipt>) ->
  {Browser.finish(value, sequence, ticket, pending, "", receipt) == Rule.refresh_finish(value, sequence, ticket, pending, receipt) : Browser.Decision}:
  Web.Decision{+web, InteractionTypes.Decision{+core, +reply, +runtime, +interaction, +services, +durable}, +effects} = value
  +initial: Browser.State = Browser.State{web, sequence, ticket, pending, receipt}
  +required = Rule.refresh_io_sequence(interaction, "", Browser.Decision{initial, Nil{}})
  Equal.trans(Browser.Decision, Browser.finish(value, sequence, ticket, pending, "", receipt),
    Browser.collected_finish(required, effects, services), Rule.refresh_finish(value, sequence, ticket, pending, receipt),
    Equal.cong(Browser.Decision, Browser.Decision, (result => Browser.collected_finish(result, effects, services)),
      Browser.collect(interaction, "", initial), required, refresh_io_fold(interaction, "", Browser.Decision{initial, Nil{}})),
    refresh_collected_meaning(required, effects, services))

def refresh_product_meaning(+input: Product.Input, +stored: Browser.State) ->
  {Browser.product_input(input, stored) == Rule.product_refresh(input, stored) : Browser.Decision}:
  Browser.State{Web.State{Platform.State{+core, +platform}, +generation, realization, +environment, +font}, +sequence, +ticket, +pending, +receipt} = stored
  Platform.Platform{+readers, +editors, +focused, +focus_ticket, +reduced, +capacity, +scope} = platform
  +decision = Platform.after_core(Product.step(input, core), Platform.Platform{readers, editors, focused, focus_ticket, reduced, capacity, scope})
  +committed = WebRules.committed_decision(Rule.expected_realized_decision(decision), (generation + 1n : Nat), environment, font)
  Equal.trans(Browser.Decision, Browser.product_input(input, stored),
    Browser.finish(committed, sequence, ticket, pending, "", receipt), Rule.product_refresh(input, stored),
    Equal.cong(Web.Decision, Browser.Decision, (result => Browser.finish(result, sequence, ticket, pending, "", receipt)),
      Web.production_commit(Platform.realized_decision(decision), (generation + 1n : Nat), environment, font), committed,
      refresh_commit_requirement(decision, (generation + 1n : Nat), environment, font)),
    refresh_finish_meaning(committed, sequence, ticket, pending, receipt))

def refresh_product_chain(+input: Product.Input, +value: Browser.Decision) ->
  {BrowserModel.synchronized_result(Browser.product_input(input, Rule.refresh_stored(value)), Rule.refresh_effects(value)) ==
    Rule.refresh_append(Rule.product_refresh(input, Rule.refresh_stored(value)), Rule.refresh_effects(value)) : Browser.Decision}:
  Browser.Decision{+stored, +effects} = value
  Equal.trans(Browser.Decision,
    BrowserModel.synchronized_result(Browser.product_input(input, stored), effects),
    BrowserModel.synchronized_result(Rule.product_refresh(input, stored), effects),
    Rule.refresh_append(Rule.product_refresh(input, stored), effects),
    Equal.cong(Browser.Decision, Browser.Decision, (result => BrowserModel.synchronized_result(result, effects)),
      Browser.product_input(input, stored), Rule.product_refresh(input, stored), refresh_product_meaning(input, stored)),
    refresh_append_meaning(Rule.product_refresh(input, stored), effects))

def refresh_environment_meaning(+namespace: String, +fresh: Bool, +allowed: Bool, +value: Browser.Decision) ->
  {BrowserModel.environment_result(namespace, fresh, allowed, value) == Rule.refresh_environment(namespace, fresh, allowed, value) : Browser.Decision}:
  Browser.Decision{+stored, +effects} = value
  refresh_product_chain(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{
    namespace, Browser.sequence(stored), fresh, allowed}}}, value)

def refresh_sync_observed(+value: Browser.Decision, +first: +List<Browser.Effect>) ->
  {BrowserModel.synchronize_observed(value, first) ==
    Rule.refresh_append(Rule.product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}},
      Rule.refresh_stored(value)), List.append(&2, Browser.Effect, first, Rule.refresh_effects(value))) : Browser.Decision}:
  Browser.Decision{+stored, +later} = value
  refresh_product_chain(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}},
    Browser.Decision{stored, List.append(&2, Browser.Effect, first, later)})

def refresh_sync_after(+actual: Browser.Decision, +required: Browser.Decision, +first: +List<Browser.Effect>,
  +same: {actual == required : Browser.Decision}) ->
  {BrowserModel.synchronize_observed(actual, first) ==
    Rule.refresh_append(Rule.product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}},
      Rule.refresh_stored(required)), List.append(&2, Browser.Effect, first, Rule.refresh_effects(required))) : Browser.Decision}:
  Equal.trans(Browser.Decision, BrowserModel.synchronize_observed(actual, first), BrowserModel.synchronize_observed(required, first),
    Rule.refresh_append(Rule.product_refresh(Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}},
      Rule.refresh_stored(required)), List.append(&2, Browser.Effect, first, Rule.refresh_effects(required))),
    Equal.cong(Browser.Decision, Browser.Decision, (value => BrowserModel.synchronize_observed(value, first)), actual, required, same),
    refresh_sync_observed(required, first))

def refresh_sync_meaning(+value: Browser.Decision) ->
  {BrowserModel.synchronize_interactive(value) == Rule.refresh_sync(value) : Browser.Decision}:
  Browser.Decision{+stored, +effects} = value
  +session = Rule.refresh_session(stored)
  +input: Product.Input = Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{
    E.namespace(session), Browser.sequence(stored), E.interactive_fresh(session), E.interactive_allowed(session)}}}
  refresh_sync_after(Browser.product_input(input, stored), Rule.product_refresh(input, stored), effects,
    refresh_product_meaning(input, stored))

def refresh_reset_meaning(+changed: Bool, +stored: Browser.State) ->
  {Browser.namespace_reset(changed, stored) == Rule.refresh_reset(changed, stored) : Browser.State}:
  match changed stored:
    case False{} _: {==}
    case True{} Browser.State{web, sequence, ticket, pending, receipt}: {==}

def refresh_world_meaning(+newer: Bool, +sequence: Nat, +program: M.World(), +stored: Browser.State) ->
  {Browser.snapshot_new(newer, sequence, program, stored) == Rule.refresh_world(newer, sequence, program, stored) : Browser.Decision}:
  match newer stored:
    case False{} _: {==}
    case True{} Browser.State{+web, old_sequence, +ticket, +pending, +receipt}:
      refresh_product_meaning(Product.ProgramObserved{program}, Browser.State{web, sequence, ticket, pending, receipt})

def refresh_connection_meaning(+changed: Bool, +access: Services.Access) ->
  {changed || BrowserModel.connection_lost(access) == Rule.reconnect_needed(changed, access) : Bool}:
  match changed access:
    case False{} Services.NotConnected{}: {==}
    case False{} Services.Connecting{ticket}: {==}
    case False{} Services.Connected{connection}: {==}
    case False{} Services.ConnectionLost{connection, reason}: {==}
    case True{} Services.NotConnected{}: {==}
    case True{} Services.Connecting{ticket}: {==}
    case True{} Services.Connected{connection}: {==}
    case True{} Services.ConnectionLost{connection, reason}: {==}

def refresh_connect_meaning(+needed: Bool, +value: Browser.Decision) ->
  {BrowserModel.reconnect_current(needed, value) == Rule.refresh_connect(needed, value) : Browser.Decision}:
  match needed value:
    case False{} _: {==}
    case True{} Browser.Decision{+stored, +first}:
      refresh_product_chain(Product.InterfaceInput{InteractionTypes.ServiceInput{Services.Connect{}}}, Browser.Decision{stored, first})

def refresh_reconnect_meaning(+changed: Bool, +value: Browser.Decision) ->
  {BrowserModel.reconnect_result(changed, value) ==
    Rule.refresh_connect(Rule.reconnect_needed(changed, Rule.refresh_stored_access(Rule.refresh_stored(value))), value) : Browser.Decision}:
  Browser.Decision{+stored, +first} = value
  +access = Services.access(InterfaceCore.services(Platform.core(Web.application(Browser.web(stored)))))
  Equal.trans(Browser.Decision, BrowserModel.reconnect_result(changed, value),
    BrowserModel.reconnect_current(Rule.reconnect_needed(changed, access), value), Rule.refresh_connect(Rule.reconnect_needed(changed, access), value),
    Equal.cong(Bool, Browser.Decision, (needed => BrowserModel.reconnect_current(needed, value)),
      changed || BrowserModel.connection_lost(access), Rule.reconnect_needed(changed, access), refresh_connection_meaning(changed, access)),
    refresh_connect_meaning(Rule.reconnect_needed(changed, access), value))

def refresh_snapshot_world(+changed: Bool, +sequence: Nat, +program: M.World(), +state: BrowserModel.State) ->
  {Browser.snapshot_new(changed || Nat.is_lt(Browser.sequence(BrowserModel.legacy(state)), sequence), sequence, program,
      Browser.namespace_reset(changed, BrowserModel.legacy(state))) ==
    Rule.refresh_world(changed || Nat.is_lt(Browser.sequence(BrowserModel.legacy(state)), sequence), sequence, program,
      Rule.refresh_reset(changed, BrowserModel.legacy(state))) : Browser.Decision}:
  +newer = changed || Nat.is_lt(Browser.sequence(BrowserModel.legacy(state)), sequence)
  Equal.trans(Browser.Decision,
    Browser.snapshot_new(newer, sequence, program, Browser.namespace_reset(changed, BrowserModel.legacy(state))),
    Browser.snapshot_new(newer, sequence, program, Rule.refresh_reset(changed, BrowserModel.legacy(state))),
    Rule.refresh_world(newer, sequence, program, Rule.refresh_reset(changed, BrowserModel.legacy(state))),
    Equal.cong(Browser.State, Browser.Decision, (stored => Browser.snapshot_new(newer, sequence, program, stored)),
      Browser.namespace_reset(changed, BrowserModel.legacy(state)), Rule.refresh_reset(changed, BrowserModel.legacy(state)),
      refresh_reset_meaning(changed, BrowserModel.legacy(state))),
    refresh_world_meaning(newer, sequence, program, Rule.refresh_reset(changed, BrowserModel.legacy(state))))

def snapshot_recovery_requirement(+changed: Bool, +namespace: String, +sequence: Nat,
  +program: M.World(), +state: BrowserModel.State) ->
  {BrowserModel.snapshot_result(changed, namespace, sequence, program, state) ==
    Rule.snapshot_transfer(changed, namespace, sequence, program, state) : Browser.Decision}:
  +actual = Browser.snapshot_new(changed || Nat.is_lt(Browser.sequence(BrowserModel.legacy(state)), sequence), sequence, program,
    Browser.namespace_reset(changed, BrowserModel.legacy(state)))
  +required = Rule.refresh_world(changed || Nat.is_lt(Browser.sequence(BrowserModel.legacy(state)), sequence), sequence, program,
    Rule.refresh_reset(changed, BrowserModel.legacy(state)))
  +environment = BrowserModel.environment_result(namespace, True{}, True{}, required)
  +target = Rule.refresh_environment(namespace, True{}, True{}, required)
  Equal.trans(Browser.Decision, BrowserModel.snapshot_result(changed, namespace, sequence, program, state),
    BrowserModel.reconnect_result(changed, environment), Rule.snapshot_transfer(changed, namespace, sequence, program, state),
    Equal.cong(Browser.Decision, Browser.Decision, (value => BrowserModel.reconnect_result(changed, BrowserModel.environment_result(namespace, True{}, True{}, value))),
      actual, required, refresh_snapshot_world(changed, sequence, program, state)),
    Equal.trans(Browser.Decision, BrowserModel.reconnect_result(changed, environment), BrowserModel.reconnect_result(changed, target),
      Rule.snapshot_transfer(changed, namespace, sequence, program, state),
      Equal.cong(Browser.Decision, Browser.Decision, (value => BrowserModel.reconnect_result(changed, value)), environment, target,
        refresh_environment_meaning(namespace, True{}, True{}, required)),
      refresh_reconnect_meaning(changed, target)))

def Rule.snapshot_recovery_complete(changed, namespace, sequence, program, state):
  snapshot_recovery_requirement(changed, namespace, sequence, program, state)

def refresh_invalidation_meaning(+invalid: Bool, +state: BrowserModel.State) ->
  {BrowserModel.invalidate_if(invalid, state) == Rule.refresh_invalidated(invalid, state) : BrowserModel.State}:
  match invalid state:
    case False{} _: {==}
    case True{} BrowserModel.State{legacy, serial, anchors, lifecycle, displayed, attention, updates}: {==}

def refresh_builder_prefix(+first: +List<Browser.Effect>, result: BrowserModel.Decision) ->
  Rule.RefreshPrefix<first, BrowserModel.append(first, result)>:
  match result:
    case BrowserModel.Decision{state, effects}: Rule.RefreshPrefix{effects, {==}}

def refresh_accepted_meaning(+first: +List<Browser.Effect>, +state: BrowserModel.State) ->
  Rule.refresh_delivery_at(BrowserModel.advance_update(state), first, BrowserModel.accepted(True{}, first, state)):
  match state:
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.Measuring{+index, +capacity, +engine, +semantic, +round}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}: {==}
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.WaitingEnvironment{}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.WaitingFont{}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.Displaying{capacity, engine, semantic}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.Blocked{reason}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.UtilityMeasuring{purpose, engine, round, glyph}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.UtilityDisplaying{purpose, engine}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))
    case BrowserModel.State{+stored, +serial, +anchors, BrowserModel.UtilityRejected{reason}, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}}:
      refresh_builder_prefix(first, BrowserModel.build(0n, BrowserModel.advance_update(state)))

def refresh_accept_synced_meaning(+synced: Browser.Decision, +state: BrowserModel.State) ->
  Rule.refresh_prepared_delivery(Rule.refresh_ready_synced(synced, state), BrowserModel.accept_synchronized(True{}, synced, state)):
  Browser.Decision{+next, +effects} = synced
  BrowserModel.State{old, +serial, +anchors, +lifecycle, +displayed, +attention, BrowserModel.DisplayUpdates{+latest, +active, +published, +semantic_latest}} = state
  refresh_accepted_meaning(effects, BrowserModel.State{next, serial, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}})

def refresh_accept_meaning(+value: Browser.Decision, +state: BrowserModel.State) ->
  Rule.RefreshDelivery(value, state, BrowserModel.accept(True{}, value, state)):
  Std.transport(Browser.Decision, Rule.refresh_sync(value),
    (synced => Rule.refresh_prepared_delivery(Rule.refresh_ready_synced(Rule.refresh_sync(value), state), BrowserModel.accept_synchronized(True{}, synced, state))),
    refresh_accept_synced_meaning(Rule.refresh_sync(value), state),
    BrowserModel.synchronize_interactive(value), refresh_sync_meaning(value))

def refresh_accept_transport(+actual: Browser.Decision, +required: Browser.Decision,
  +actual_state: BrowserModel.State, +required_state: BrowserModel.State,
  +value_equal: {actual == required : Browser.Decision}, +state_equal: {actual_state == required_state : BrowserModel.State}) ->
  Rule.RefreshDelivery(required, required_state, BrowserModel.accept(True{}, actual, actual_state)):
  Std.transport(Browser.Decision, required,
    (value => Rule.RefreshDelivery(required, required_state, BrowserModel.accept(True{}, value, actual_state))),
    Std.transport(BrowserModel.State, required_state,
      (state => Rule.RefreshDelivery(required, required_state, BrowserModel.accept(True{}, required, state))),
      refresh_accept_meaning(required, required_state), actual_state, state_equal),
    actual, value_equal)

def refresh_connecting_meaning(+access: Services.Access, +ticket: Nat) ->
  {Services.expected_access(access, ticket) == Rule.connecting_ticket(access, ticket) : Bool}:
  match access:
    case Services.NotConnected{}: {==}
    case Services.Connecting{expected}: {==}
    case Services.Connected{connection}: {==}
    case Services.ConnectionLost{connection, reason}: {==}

def refresh_authentication_owner(+namespace: String, +ticket: Nat, +state: BrowserModel.State) ->
  {BrowserModel.authentication_owned(namespace, ticket, state) == Rule.authentication_owner(namespace, ticket, state) : Bool}:
  Equal.cong(Bool, Bool, (owned => String.eq(namespace, Rule.refresh_namespace(state)) && owned),
    Services.expected_access(Rule.refresh_access(state), ticket), Rule.connecting_ticket(Rule.refresh_access(state), ticket),
    refresh_connecting_meaning(Rule.refresh_access(state), ticket))

def refresh_failure_owner(+namespace: String, +sequence: Nat,+connection: Nat,  +authentication: Maybe<&2, Nat>, +state: BrowserModel.State) ->
  {BrowserModel.network_failure_owned(namespace, sequence, connection, authentication, state) == Rule.failure_owner(namespace, sequence, connection, authentication, state) : Bool}:
  match authentication:
    case None{}: {==}
    case Some{ticket}: refresh_authentication_owner(namespace, ticket, state)

def refresh_failure_sequence(+authentication: Maybe<&2, Nat>, +sequence: Nat, +state: BrowserModel.State) ->
  {BrowserModel.network_failure_sequence(authentication, sequence, state) == Rule.failure_sequence(authentication, sequence, state) : Nat}:
  match authentication:
    case None{}: {==}
    case Some{ticket}: {==}

def refresh_failure_service(+authentication: Maybe<&2, Nat>, +connection: Nat, +reason: String, +value: Browser.Decision) ->
  {BrowserModel.network_failure_after(authentication, connection, reason, value) ==
    Rule.refresh_append(Rule.product_refresh(Rule.failed_service(authentication, connection, reason), Rule.refresh_stored(value)), Rule.refresh_effects(value)) : Browser.Decision}:
  match authentication value:
    case None{} Browser.Decision{+stored, +effects}:
      refresh_product_chain(Product.Disconnected{connection, reason}, Browser.Decision{stored, effects})
    case Some{ticket} Browser.Decision{+stored, +effects}:
      refresh_product_chain(Product.Authenticated{ticket, Fail{reason}}, Browser.Decision{stored, effects})

def refresh_failure_transfer(+namespace: String, +sequence: Nat,+connection: Nat,  +reason: String, +revoked: Bool,
  +authentication: Maybe<&2, Nat>, +state: BrowserModel.State) ->
  {BrowserModel.network_failure_result(namespace, sequence, connection, reason, revoked, authentication, state) ==
    Rule.failure_transfer(namespace, sequence, connection, reason, revoked, authentication, state) : Browser.Decision}:
  +input: Product.Input = Product.InterfaceInput{InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{
    namespace, sequence, False{}, Bool.not(revoked) && Rule.refresh_allowed(state)}}}
  +actual = Browser.product_input(input, BrowserModel.legacy(state))
  +required = Rule.product_refresh(input, BrowserModel.legacy(state))
  Equal.trans(Browser.Decision, BrowserModel.network_failure_result(namespace, sequence, connection, reason, revoked, authentication, state),
    BrowserModel.network_failure_after(authentication, connection, reason, required), Rule.failure_transfer(namespace, sequence, connection, reason, revoked, authentication, state),
    Equal.cong(Browser.Decision, Browser.Decision, (result => BrowserModel.network_failure_after(authentication, connection, reason, result)),
      actual, required, refresh_product_meaning(input, BrowserModel.legacy(state))),
    refresh_failure_service(authentication, connection, reason, required))

def refresh_failure_at_sequence(+namespace: String, +sequence: Nat,+connection: Nat,  +reason: String, +revoked: Bool,
  +authentication: Maybe<&2, Nat>, +state: BrowserModel.State) ->
  {BrowserModel.network_failure_result(namespace, BrowserModel.network_failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state) ==
    Rule.failure_transfer(namespace, Rule.failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state) : Browser.Decision}:
  Equal.trans(Browser.Decision,
    BrowserModel.network_failure_result(namespace, BrowserModel.network_failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state),
    BrowserModel.network_failure_result(namespace, Rule.failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state),
    Rule.failure_transfer(namespace, Rule.failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state),
    Equal.cong(Nat, Browser.Decision, (at => BrowserModel.network_failure_result(namespace, at, connection, reason, revoked, authentication, state)),
      BrowserModel.network_failure_sequence(authentication, sequence, state), Rule.failure_sequence(authentication, sequence, state), refresh_failure_sequence(authentication, sequence, state)),
    refresh_failure_transfer(namespace, Rule.failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state))

def refresh_failure_current(+owned: Bool, +namespace: String, +sequence: Nat,+connection: Nat,  +reason: String, +revoked: Bool,
  +authentication: Maybe<&2, Nat>, +state: BrowserModel.State) ->
  Rule.NetworkFailure(owned, namespace, sequence, connection, reason, revoked, authentication, state,
    BrowserModel.network_failed_current(owned, namespace, sequence, connection, reason, revoked, authentication, state)):
  match owned:
    case False{}: {==}
    case True{}:
      refresh_accept_transport(
        BrowserModel.network_failure_result(namespace, BrowserModel.network_failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state),
        Rule.failure_transfer(namespace, Rule.failure_sequence(authentication, sequence, state), connection, reason, revoked, authentication, state),
        BrowserModel.invalidate_if(revoked, state), Rule.refresh_invalidated(revoked, state),
        refresh_failure_at_sequence(namespace, sequence, connection, reason, revoked, authentication, state), refresh_invalidation_meaning(revoked, state))

def Rule.scoped_network_failure_complete(namespace, sequence, connection, reason, revoked, authentication, state):
  Std.transport(Bool, Rule.failure_owner(namespace, sequence, connection, authentication, state),
    (owned => Rule.NetworkFailure(Rule.failure_owner(namespace, sequence, connection, authentication, state), namespace, sequence, connection, reason, revoked, authentication, state,
      BrowserModel.network_failed_current(owned, namespace, sequence, connection, reason, revoked, authentication, state))),
    refresh_failure_current(Rule.failure_owner(namespace, sequence, connection, authentication, state), namespace, sequence, connection, reason, revoked, authentication, state),
    BrowserModel.network_failure_owned(namespace, sequence, connection, authentication, state), refresh_failure_owner(namespace, sequence, connection, authentication, state))

def refresh_authenticated_transfer(+ticket: Nat, +value: Browser.Decision) ->
  {BrowserModel.authenticated_result(ticket, value) == Rule.authenticated_transfer(ticket, value) : Browser.Decision}:
  Browser.Decision{+stored, +effects} = value
  refresh_product_chain(Product.Authenticated{ticket, Done{Unit{}}}, value)

def refresh_authenticated_snapshot_transfer(+changed: Bool, +namespace: String, +sequence: Nat, +program: M.World(),
  +ticket: Nat, +state: BrowserModel.State) ->
  {BrowserModel.authenticated_result(ticket, BrowserModel.snapshot_result(changed, namespace, sequence, program, state)) ==
    Rule.authenticated_transfer(ticket, Rule.snapshot_transfer(changed, namespace, sequence, program, state)) : Browser.Decision}:
  Equal.trans(Browser.Decision,
    BrowserModel.authenticated_result(ticket, BrowserModel.snapshot_result(changed, namespace, sequence, program, state)),
    BrowserModel.authenticated_result(ticket, Rule.snapshot_transfer(changed, namespace, sequence, program, state)),
    Rule.authenticated_transfer(ticket, Rule.snapshot_transfer(changed, namespace, sequence, program, state)),
    Equal.cong(Browser.Decision, Browser.Decision, (value => BrowserModel.authenticated_result(ticket, value)),
      BrowserModel.snapshot_result(changed, namespace, sequence, program, state), Rule.snapshot_transfer(changed, namespace, sequence, program, state),
      Rule.snapshot_recovery_complete(changed, namespace, sequence, program, state)),
    refresh_authenticated_transfer(ticket, Rule.snapshot_transfer(changed, namespace, sequence, program, state)))

def refresh_authenticated_current(+stale: Bool, +changed: Bool, +namespace: String, +sequence: Nat,
  +program: M.World(), +ticket: Nat, +state: BrowserModel.State) ->
  Rule.authenticated_current(stale, changed, namespace, sequence, program, ticket, state,
    BrowserModel.authenticated_snapshot_current(stale, changed, namespace, sequence, program, ticket, state)):
  match stale:
    case True{}:
      refresh_accept_transport(BrowserModel.authenticated_result(ticket, Browser.Decision{BrowserModel.legacy(state), Nil{}}),
        Rule.authenticated_transfer(ticket, Browser.Decision{BrowserModel.legacy(state), Nil{}}), state, state,
        refresh_authenticated_transfer(ticket, Browser.Decision{BrowserModel.legacy(state), Nil{}}), {==})
    case False{}:
      +invalid = changed || BrowserModel.view_removed(program, state)
      refresh_accept_transport(BrowserModel.authenticated_result(ticket, BrowserModel.snapshot_result(changed, namespace, sequence, program, state)),
        Rule.authenticated_transfer(ticket, Rule.snapshot_transfer(changed, namespace, sequence, program, state)),
        BrowserModel.invalidate_if(invalid, state), Rule.refresh_invalidated(invalid, state),
        refresh_authenticated_snapshot_transfer(changed, namespace, sequence, program, ticket, state), refresh_invalidation_meaning(invalid, state))

def refresh_authenticated_valid(+valid: Bool, +namespace: String, +sequence: Nat, +program: M.World(), +ticket: Nat, +state: BrowserModel.State) ->
  Rule.authenticated_valid(valid, namespace, sequence, program, ticket, state,
    BrowserModel.authenticated_snapshot_valid(valid, namespace, sequence, program, ticket, state)):
  match valid:
    case False{}:
      Rule.scoped_network_failure_complete(Rule.refresh_namespace(state), Browser.sequence(BrowserModel.legacy(state)), ticket,
        "Invalid service data namespace", True{}, Some{ticket}, state)
    case True{}:
      +changed = Bool.not(String.eq(Rule.refresh_namespace(state), namespace))
      refresh_authenticated_current(Bool.not(changed) && Nat.is_lt(sequence, Browser.sequence(BrowserModel.legacy(state))),
        changed, namespace, sequence, program, ticket, state)

def refresh_authenticated_owned(+owned: Bool, +namespace: String, +sequence: Nat, +program: M.World(), +ticket: Nat, +state: BrowserModel.State) ->
  Rule.AuthenticatedSnapshot(owned, namespace, sequence, program, ticket, state,
    BrowserModel.authenticated_snapshot_owned(owned, namespace, sequence, program, ticket, state)):
  match owned:
    case False{}: {==}
    case True{}: refresh_authenticated_valid(Live.valid_namespace(namespace), namespace, sequence, program, ticket, state)

def Rule.scoped_authentication_complete(expected_namespace, namespace, sequence, program, ticket, state):
  Std.transport(Bool, Rule.authentication_owner(expected_namespace, ticket, state),
    (owned => Rule.AuthenticatedSnapshot(Rule.authentication_owner(expected_namespace, ticket, state), namespace, sequence, program, ticket, state,
      BrowserModel.authenticated_snapshot_owned(owned, namespace, sequence, program, ticket, state))),
    refresh_authenticated_owned(Rule.authentication_owner(expected_namespace, ticket, state), namespace, sequence, program, ticket, state),
    BrowserModel.authentication_owned(expected_namespace, ticket, state), refresh_authentication_owner(expected_namespace, ticket, state))

def Rule.atomic_snapshot_changes_namespace(expected_namespace, namespace, sequence, program, state, valid, owned, changed):
  Std.transport(BrowserModel.Decision,
    BrowserModel.snapshot_current(True{}, True{}, namespace, sequence, program, state),
    (actual => Rule.RefreshDelivery(Rule.snapshot_transfer(True{}, namespace, sequence, program, state), Rule.refresh_invalidated(True{}, state), actual)),
    refresh_accept_transport(BrowserModel.snapshot_result(True{}, namespace, sequence, program, state), Rule.snapshot_transfer(True{}, namespace, sequence, program, state),
      BrowserModel.invalidate_if(True{} || BrowserModel.view_removed(program, state), state), Rule.refresh_invalidated(True{}, state),
      Rule.snapshot_recovery_complete(True{}, namespace, sequence, program, state), refresh_invalidation_meaning(True{}, state)),
    BrowserModel.snapshot_environment(expected_namespace, namespace, sequence, program, state),
    snapshot_namespace_equation(expected_namespace, namespace, sequence, program, state, False{}, valid, owned, changed))

def completed_namespace_equation(+ticket: Nat, +namespace: String, +sequence: Nat, +program: M.World(), +reply: J.Json, +state: BrowserModel.State, +same: Bool,
  observed: {String.eq(BrowserModel.current_namespace(state), namespace) == same : Bool}) ->
  {BrowserModel.completed_environment(ticket, namespace, sequence, program, reply, state) ==
    BrowserModel.completed_current(Bool.not(same), ticket, namespace, sequence, program, reply, state) : BrowserModel.Decision}:
  Equal.cong(Bool, BrowserModel.Decision,
    accepted => BrowserModel.completed_current(Bool.not(accepted), ticket, namespace, sequence, program, reply, state),
    String.eq(BrowserModel.current_namespace(state), namespace), same, observed)

def Rule.foreign_namespace_completion_ignored(ticket, namespace, sequence, program, reply, state, changed):
  completed_namespace_equation(ticket, namespace, sequence, program, reply, state, False{}, changed)

def Rule.same_namespace_completion_preserves_environment(ticket, namespace, sequence, program, reply, state, same):
  completed_namespace_equation(ticket, namespace, sequence, program, reply, state, True{}, same)


def Rule.namespace_switch_clears_previous_requests(web, sequence, next, pending, receipt): {==}

def Rule.same_namespace_retains_requests(state): {==}


def Rule.foreign_snapshot_request_ignored(expected_namespace, namespace, sequence, program, state, foreign):
  snapshot_expected_equation(expected_namespace, namespace, sequence, program, state, False{}, foreign)

def Rule.foreign_transport_environment_ignored(namespace, sequence, fresh, allowed, state, foreign):
  Equal.cong(Bool, BrowserModel.Decision,
    same => BrowserModel.transport_current(same && Nat.is_eq(sequence, Browser.sequence(BrowserModel.legacy(state))), namespace, sequence, fresh, allowed && BrowserModel.source_allowed(state), state),
    String.eq(namespace, BrowserModel.current_namespace(state)), False{}, foreign)

def false_transport_epoch(+same: Bool, +namespace: String, +sequence: Nat, +fresh: Bool, +allowed: Bool, +state: BrowserModel.State) ->
  {BrowserModel.transport_current(same && False{}, namespace, sequence, fresh, allowed && BrowserModel.source_allowed(state), state) == BrowserModel.Decision{state, Nil{}} : BrowserModel.Decision}:
  match same:
    case True{}: {==}
    case False{}: {==}

def Rule.stale_transport_environment_ignored(namespace, sequence, fresh, allowed, state, stale):
  Equal.trans(BrowserModel.Decision,
    BrowserModel.transport_environment(namespace, sequence, fresh, allowed, state),
    BrowserModel.transport_current(String.eq(namespace, BrowserModel.current_namespace(state)) && False{}, namespace, sequence, fresh, allowed && BrowserModel.source_allowed(state), state),
    BrowserModel.Decision{state, Nil{}},
    Equal.cong(Bool, BrowserModel.Decision,
      current => BrowserModel.transport_current(String.eq(namespace, BrowserModel.current_namespace(state)) && current, namespace, sequence, fresh, allowed && BrowserModel.source_allowed(state), state),
      Nat.is_eq(sequence, Browser.sequence(BrowserModel.legacy(state))), False{}, stale),
    false_transport_epoch(String.eq(namespace, BrowserModel.current_namespace(state)), namespace, sequence, fresh, allowed, state))


def false_display_policy(existing: Bool, current: Bool) ->
  {existing && False{} && current == False{} : Bool}:
  match existing:
    case True{}: {==}
    case False{}: {==}

def invalidation_predicate(+capacity: Nat, +last: Nat, +state: BrowserModel.State) ->
  {BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last, BrowserModel.invalidate_display(state)}) == False{} : Bool}:
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      false_display_policy(Bool.not(Nat.is_eq(last, 0n)), Nat.is_eq(0n, last))

def Rule.invalidation_clears_publication(capacity, last_published, state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, updates}:
      Equal.trans(BrowserModel.Publication,
        BrowserModel.publication(capacity, last_published, BrowserModel.invalidate_display(state)),
        policy_spec(BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last_published, BrowserModel.invalidate_display(state)}), capacity, BrowserModel.invalidate_display(state)),
        BrowserModel.Publish{0n, BrowserModel.observe(capacity, BrowserModel.invalidate_display(state)), Nil{}},
        policy_equation(capacity, last_published, BrowserModel.invalidate_display(state)),
        Equal.cong(Bool, BrowserModel.Publication,
          accepted => policy_spec(accepted, capacity, BrowserModel.invalidate_display(state)),
          BrowserModel.publication_policy_predicate(BrowserModel.PublicationCandidate{capacity, last_published, BrowserModel.invalidate_display(state)}), False{},
          invalidation_predicate(capacity, last_published, state)))


def commit_refresh_at_equation(sequence: Maybe<&2, Nat>, notice: J.Json, state: BrowserModel.State) ->
  {BrowserModel.commit_refresh_needed_at(sequence, notice, state) == Rule.required_commit_refresh_at(sequence, notice, state) : Bool}:
  match sequence:
    case None{}: {==}
    case Some{received}: {==}

def Rule.commit_refresh_needed_complete(notice, state):
  commit_refresh_at_equation(J.natural(J.get(notice, "sequence")), notice, state)

def Rule.undecodable_commit_refreshes(notice, state, undecodable):
  Equal.trans(Bool, BrowserModel.commit_refresh_needed(notice, state), Rule.required_commit_refresh(notice, state), True{},
    Rule.commit_refresh_needed_complete(notice, state),
    Equal.cong(Maybe<&2, Nat>, Bool, sequence => Rule.required_commit_refresh_at(sequence, notice, state),
      J.natural(J.get(notice, "sequence")), None{}, undecodable))

def Rule.covered_commit_skips_refresh(notice, state, sequence, decoded, covered):
  Equal.trans(Bool, BrowserModel.commit_refresh_needed(notice, state), Rule.required_commit_refresh(notice, state), False{},
    Rule.commit_refresh_needed_complete(notice, state),
    Equal.trans(Bool, Rule.required_commit_refresh(notice, state), Rule.required_commit_refresh_at(Some{sequence}, notice, state), False{},
      Equal.cong(Maybe<&2, Nat>, Bool, received => Rule.required_commit_refresh_at(received, notice, state),
        J.natural(J.get(notice, "sequence")), Some{sequence}, decoded),
      Equal.cong(Bool, Bool, value => Bool.not(value), Rule.required_commit_covered(notice, sequence, state), True{}, covered)))

def Rule.uncovered_commit_refreshes(notice, state, sequence, decoded, uncovered):
  Equal.trans(Bool, BrowserModel.commit_refresh_needed(notice, state), Rule.required_commit_refresh(notice, state), True{},
    Rule.commit_refresh_needed_complete(notice, state),
    Equal.trans(Bool, Rule.required_commit_refresh(notice, state), Rule.required_commit_refresh_at(Some{sequence}, notice, state), True{},
      Equal.cong(Maybe<&2, Nat>, Bool, received => Rule.required_commit_refresh_at(received, notice, state),
        J.natural(J.get(notice, "sequence")), Some{sequence}, decoded),
      Equal.cong(Bool, Bool, value => Bool.not(value), Rule.required_commit_covered(notice, sequence, state), False{}, uncovered)))


def activation_nonreserved(+key: String, +state: BrowserModel.State,
  ordinary: {String.eq(key, "@browser/retry") == False{} : Bool}) ->
  {BrowserModel.activate(key, state) == BrowserModel.activate_ready(
    Bool.not(BrowserModel.activation_owned(key, state)) ||
    (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
    (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state) : BrowserModel.Decision}:
  Equal.cong(Bool, BrowserModel.Decision, reserved => BrowserModel.activate_reserved(reserved, key, state),
    String.eq(key, "@browser/retry"), False{}, ordinary)

def Rule.unowned_activation_is_inert(key, state, ordinary, unowned):
  Equal.trans(BrowserModel.Decision, BrowserModel.activate(key, state),
    BrowserModel.activate_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
    BrowserModel.Decision{state, Nil{}}, activation_nonreserved(key, state, ordinary),
    Equal.cong(Bool, BrowserModel.Decision,
      owned => BrowserModel.activate_ready(Bool.not(owned) ||
        (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
        (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
      BrowserModel.activation_owned(key, state), False{}, unowned))

def middle_true(left: Bool, right: Bool) -> {left || True{} || right == True{} : Bool}:
  match left:
    case True{}: {==}
    case False{}: {==}

def right_true(left: Bool, middle: Bool) -> {left || middle || True{} == True{} : Bool}:
  match left middle:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def pending_activation_guard(+key: String, +state: BrowserModel.State,
  pending: {BrowserModel.semantic_pending(state) == True{} : Bool},
  external: {BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key)) == True{} : Bool}) ->
  {Bool.not(BrowserModel.activation_owned(key, state)) ||
    (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
    (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == True{} : Bool}:
  Std.transport(Bool, True{},
    value => {Bool.not(BrowserModel.activation_owned(key, state)) ||
      (value && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == True{} : Bool},
    Std.transport(Bool, True{},
      value => {Bool.not(BrowserModel.activation_owned(key, state)) || value ||
        (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == True{} : Bool},
      middle_true(Bool.not(BrowserModel.activation_owned(key, state)),
        Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))),
      BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key)), external),
    BrowserModel.semantic_pending(state), pending)

def Rule.semantic_pending_external_activation_is_inert(key, state, ordinary, pending, external):
  Equal.trans(BrowserModel.Decision, BrowserModel.activate(key, state),
    BrowserModel.activate_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
    BrowserModel.Decision{state, Nil{}}, activation_nonreserved(key, state, ordinary),
    Equal.cong(Bool, BrowserModel.Decision, blocked => BrowserModel.activate_ready(blocked, key, state),
      Bool.not(BrowserModel.activation_owned(key, state)) ||
        (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
        (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))),
      True{}, pending_activation_guard(key, state, pending, external)))

def disconnected_activation_guard(+key: String, +state: BrowserModel.State,
  disconnected: {BrowserModel.service_connected(state) == False{} : Bool},
  submit: {BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key)) == True{} : Bool}) ->
  {Bool.not(BrowserModel.activation_owned(key, state)) ||
    (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
    (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == True{} : Bool}:
  Std.transport(Bool, False{},
    value => {Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(value) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == True{} : Bool},
    Std.transport(Bool, True{},
      value => {Bool.not(BrowserModel.activation_owned(key, state)) ||
        (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) || value == True{} : Bool},
      right_true(Bool.not(BrowserModel.activation_owned(key, state)),
        BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))),
      BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key)), submit),
    BrowserModel.service_connected(state), disconnected)

def Rule.disconnected_submit_is_inert(key, state, ordinary, disconnected, submit):
  Equal.trans(BrowserModel.Decision, BrowserModel.activate(key, state),
    BrowserModel.activate_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
    BrowserModel.Decision{state, Nil{}}, activation_nonreserved(key, state, ordinary),
    Equal.cong(Bool, BrowserModel.Decision, blocked => BrowserModel.activate_ready(blocked, key, state),
      Bool.not(BrowserModel.activation_owned(key, state)) ||
        (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
        (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))),
      True{}, disconnected_activation_guard(key, state, disconnected, submit)))


def Rule.changed_attention_advances_latest(attention, state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, previous, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}:
      {==}

def Rule.initial_update_stamps(program, sequence): {==}

def Rule.semantic_update_complete(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.presentation_update_complete(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.semantic_pending_is_publication_lag(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.presentation_preserves_semantic_pending(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.attention_preserves_prior_semantic_update(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.publication_uses_active_semantic_stamp(state):
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, displayed, attention, BrowserModel.DisplayUpdates{latest, active, published, semantic_latest}}: {==}

def Rule.old_active_publication_remains_blocked(state, behind):
  Equal.trans(Bool, BrowserModel.semantic_pending(BrowserModel.publish_update(state)),
    Rule.required_active_semantic_pending(state), True{}, Rule.publication_uses_active_semantic_stamp(state), behind)

def attention_ready_equation(blocked: Bool, key: String, state: BrowserModel.State) ->
  {BrowserModel.activate_ready(blocked, key, state) == Rule.required_activation_ready(blocked, key, state) : BrowserModel.Decision}:
  match blocked:
    case True{}: {==}
    case False{}: {==}

def attention_activation_equation(reserved: Bool, +key: String, +state: BrowserModel.State) ->
  {BrowserModel.activate_reserved(reserved, key, state) == Rule.required_activation_reserved(reserved, key, state) : BrowserModel.Decision}:
  match reserved:
    case True{}: {==}
    case False{}:
      Equal.trans(BrowserModel.Decision, BrowserModel.activate_reserved(False{}, key, state),
        Rule.required_activation_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
          (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
          (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
        Rule.required_activation_reserved(False{}, key, state),
        attention_ready_equation(Bool.not(BrowserModel.activation_owned(key, state)) ||
          (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
          (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
        Equal.cong(Bool, BrowserModel.Decision,
          pending => Rule.required_activation_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
            (pending && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
            (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
          BrowserModel.semantic_pending(state), Rule.required_semantic_pending(state), Rule.semantic_pending_is_publication_lag(state)))

def Rule.activation_complete(key, state):
  attention_activation_equation(String.eq(key, "@browser/retry"), key, state)

def attention_caught_up_guard(+key: String, +state: BrowserModel.State,
  owned: {BrowserModel.activation_owned(key, state) == True{} : Bool},
  caught_up: {BrowserModel.semantic_pending(state) == False{} : Bool},
  connected: {BrowserModel.service_connected(state) == True{} : Bool}) ->
  {Bool.not(BrowserModel.activation_owned(key, state)) ||
    (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
    (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == False{} : Bool}:
  Std.transport(Bool, True{},
    value => {Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(value) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == False{} : Bool},
    Std.transport(Bool, False{},
      value => {Bool.not(BrowserModel.activation_owned(key, state)) ||
        (value && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
        (Bool.not(True{}) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == False{} : Bool},
      Std.transport(Bool, True{},
        value => {Bool.not(value) ||
          (False{} && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
          (Bool.not(True{}) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) == False{} : Bool},
        {==}, BrowserModel.activation_owned(key, state), owned),
      BrowserModel.semantic_pending(state), caught_up),
    BrowserModel.service_connected(state), connected)

def Rule.caught_up_owned_activation_is_admitted(key, state, ordinary, owned, caught_up, connected):
  Equal.trans(BrowserModel.Decision, BrowserModel.activate(key, state),
    BrowserModel.activate_ready(Bool.not(BrowserModel.activation_owned(key, state)) ||
      (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
      (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))), key, state),
    BrowserModel.accept(True{}, Browser.activate(key, BrowserModel.legacy(state)), state),
    activation_nonreserved(key, state, ordinary),
    Equal.cong(Bool, BrowserModel.Decision, blocked => BrowserModel.activate_ready(blocked, key, state),
      Bool.not(BrowserModel.activation_owned(key, state)) ||
        (BrowserModel.semantic_pending(state) && BrowserModel.external_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))) ||
        (Bool.not(BrowserModel.service_connected(state)) && BrowserModel.submit_action(InterfaceView.find_node(InterfaceView.active_nodes(BrowserModel.current_surface(state)), key))),
      False{}, attention_caught_up_guard(key, state, owned, caught_up, connected)))

def attention_binding_kind_equation(kind: Interactive.ActionKind, key: String, owned: Bool, enabled: Bool, busy: Bool, pending: Bool) ->
  {[Native.SetEnabled{key, owned && enabled && Bool.not(busy) && Bool.not(pending && BrowserModel.model_external_kind(kind))}] ==
    [Native.SetEnabled{key, owned && enabled && Bool.not(busy) && Bool.not(pending && Rule.required_model_external_kind(kind))}] : +List<Native.Update>}:
  match kind:
    case Interactive.SetAction{}: {==}
    case Interactive.ResetAction{}: {==}
    case Interactive.DraftAction{}: {==}
    case Interactive.SubmitAction{}: {==}
    case Interactive.CopyAction{}: {==}
    case Interactive.OpenUrlAction{}: {==}

def Rule.action_binding_updates_complete(key, found, pending, owned):
  match found:
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{component, occurrence, tag, attributes, Interactive.ActionBinding{kind, enabled, busy}, children}}, nested}}:
      attention_binding_kind_equation(kind, key, owned, enabled, busy, pending)
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{component, occurrence, tag, attributes, Interactive.NoBinding{}, children}}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{component, occurrence, tag, attributes, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveView{event, command, label_value, enabled}, nested}}: {==}
    case None{}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.SettingEntry{meaning_subject, meaning_value, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActivityRow{meaning_role}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActivityGroup{meaning_activity, meaning_dismiss, meaning_outside, meaning_escape}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.DecisionGroup{meaning_decision}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.WorkspaceCollection{meaning_collection}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.WorkspaceMember{meaning_collection, meaning_path}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActionUnit{meaning_action}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActionFeedback{meaning_feedback}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActionExplanation{meaning_assessment}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActionCommit{meaning_assessment, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ObjectGroup{meaning_object}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.SupportingControl{meaning_support, meaning_property, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InformationText{meaning_role}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.LayerRegion{meaning_dismiss, meaning_outside, meaning_escape}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.DirectoryBrowserLocation{meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.PanelToggle{meaning_expanded, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.CardContent{meaning_face}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.MovableCard{meaning_destinations, meaning_face}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.Region{}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.PageContext{meaning_conversation}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ActivityContent{meaning_expanded, meaning_audit}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ProjectGroup{meaning_project, meaning_selected, meaning_expanded}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.TaskRow{meaning_task, meaning_status, meaning_selected}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.TaskChildren{meaning_task}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ProjectChooser{meaning_selected}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.DirectoryRow{meaning_path, meaning_primary}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ContextSummary{meaning_observation}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ChoiceGroup{}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.Choice{meaning_kind, meaning_classification, meaning_selected, meaning_description, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.PageRegion{meaning_region, meaning_position}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.BoardLane{meaning_stage, meaning_count}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.CardArchive{meaning_count}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.BoardSearch{meaning_filter}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.BoardGroup{meaning_grouping}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ReadOnly{meaning_text}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.Fact{meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.RichText{meaning_source, meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.TaskFacts{meaning_details}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.CodeFacts{meaning_view}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.InteractiveRegion{meaning_identity, meaning_source_visible}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.Activate{meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.Edit{meaning_editor, meaning_field, meaning_entry, meaning_value, meaning_choices}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.SearchChoices{meaning_query}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.HistorySearchQuery{meaning_query}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.HistorySearchScope{scope_0, meaning_query, choices_0}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.ReceiveFile{meaning_editor, meaning_enabled}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.EnterDirectory{meaning_editor, meaning_text}, nested}}: {==}
    case Some{SurfaceTypes.Node{identity, semantic, label, role, SurfaceTypes.BoardProfile{meaning_automatic, meaning_selected, meaning_choices, meaning_enabled}, nested}}: {==}

def Rule.physical_invalidation_complete(before, after): {==}

def ordinary_invalidation_values(+allowed: Bool, +removed: Bool) ->
  {Bool.not(True{}) || (allowed && Bool.not(allowed)) || (Bool.not(removed) && removed) == False{} : Bool}:
  match allowed removed:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def Rule.ordinary_updates_retain_physical_probes(before, after, same_namespace, same_access, same_view):
  Std.transport(Bool, True{},
    same => {Bool.not(same) ||
      (BrowserModel.source_allowed(before) && Bool.not(BrowserModel.source_allowed(after))) ||
      (Bool.not(BrowserModel.view_removed(BrowserModel.program(before), before)) &&
        BrowserModel.view_removed(BrowserModel.program(after), before)) == False{} : Bool},
    Std.transport(Bool, BrowserModel.source_allowed(before),
      allowed => {Bool.not(True{}) ||
        (BrowserModel.source_allowed(before) && Bool.not(allowed)) ||
        (Bool.not(BrowserModel.view_removed(BrowserModel.program(before), before)) &&
          BrowserModel.view_removed(BrowserModel.program(after), before)) == False{} : Bool},
      Std.transport(Bool, BrowserModel.view_removed(BrowserModel.program(before), before),
        removed => {Bool.not(True{}) ||
          (BrowserModel.source_allowed(before) && Bool.not(BrowserModel.source_allowed(before))) ||
          (Bool.not(BrowserModel.view_removed(BrowserModel.program(before), before)) && removed) == False{} : Bool},
        ordinary_invalidation_values(BrowserModel.source_allowed(before), BrowserModel.view_removed(BrowserModel.program(before), before)),
        BrowserModel.view_removed(BrowserModel.program(after), before), same_view),
      BrowserModel.source_allowed(after), same_access),
    String.eq(BrowserModel.current_namespace(before), BrowserModel.current_namespace(after)), same_namespace)


def native_named_deferred_fallback(+found: Maybe<&2, SurfaceTypes.Node>, fallback: Unit -> Maybe<&2, SurfaceTypes.Node>) ->
  {Native.find_named_fallback(found, fallback) == InterfaceView.prefer_node(found, fallback(Unit{})) : Maybe<&2, SurfaceTypes.Node>}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def native_named_deferred_match(+same: Bool, +node: SurfaceTypes.Node,
  descendants: Unit -> Maybe<&2, SurfaceTypes.Node>, siblings: Unit -> Maybe<&2, SurfaceTypes.Node>) ->
  {Native.find_named_match(same, node, descendants, siblings) ==
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node},
      InterfaceView.prefer_node(descendants(Unit{}), siblings(Unit{}))) : Maybe<&2, SurfaceTypes.Node>}:
  match same:
    case True{}: {==}
    case False{}: native_named_deferred_fallback(descendants(Unit{}), siblings)

def native_named_branches(+same: Bool, +node: SurfaceTypes.Node,
  +child: Maybe<&2, SurfaceTypes.Node>, +required_child: Maybe<&2, SurfaceTypes.Node>,
  +sibling: Maybe<&2, SurfaceTypes.Node>, +required_sibling: Maybe<&2, SurfaceTypes.Node>,
  children_equal: {child == required_child : Maybe<&2, SurfaceTypes.Node>},
  siblings_equal: {sibling == required_sibling : Maybe<&2, SurfaceTypes.Node>}) ->
  {Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(child, sibling)) ==
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(required_child, required_sibling)) : Maybe<&2, SurfaceTypes.Node>}:
  Equal.trans((Maybe<&2, SurfaceTypes.Node>),
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(child, sibling)),
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(required_child, sibling)),
    Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(required_child, required_sibling)),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
      (found => Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(found, sibling))),
      child, required_child, children_equal),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
      (found => Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(required_child, found))),
      sibling, required_sibling, siblings_equal))

def native_named_lookup_complete(+nodes: +List<SurfaceTypes.Node>, +key: String) ->
  {Native.find_named(Native.prepare_named(nodes), key) == Rules_interface_program_rules.first_named_node(nodes, key) : Maybe<&2, SurfaceTypes.Node>}:
  match nodes:
    case Nil{}: {==}
    case Con{SurfaceTypes.Node{+current, +semantic, +label, +role, +meaning, +children}, +rest}:
      +node: SurfaceTypes.Node = SurfaceTypes.Node{current, semantic, label, role, meaning, children}
      +encoded: String = UIIdentity.encode(current)
      +same: Bool = SafeText.string_equal(encoded, key)
      +required_match: Bool = String.eq(encoded, key)
      +child: Maybe<&2, SurfaceTypes.Node> = Native.find_named(Native.prepare_named(children), key)
      +sibling: Maybe<&2, SurfaceTypes.Node> = Native.find_named(Native.prepare_named(rest), key)
      +required_child: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(children, key)
      +required_sibling: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(rest, key)
      +actual: Maybe<&2, SurfaceTypes.Node> = Native.find_named_match(same, node, (_ => child), (_ => sibling))
      +deferred: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(child, sibling))
      +selected: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), same, Some{node}, InterfaceView.prefer_node(required_child, required_sibling))
      +compared: Maybe<&2, SurfaceTypes.Node> = Bool.pick((Maybe<&2, SurfaceTypes.Node>), required_match, Some{node}, InterfaceView.prefer_node(required_child, required_sibling))
      +target: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(node <> rest, key)
      Equal.trans((Maybe<&2, SurfaceTypes.Node>), actual, deferred, target,
        native_named_deferred_match(same, node, (_ => child), (_ => sibling)),
        Equal.trans((Maybe<&2, SurfaceTypes.Node>), deferred, selected, target,
          native_named_branches(same, node, child, required_child, sibling, required_sibling,
            native_named_lookup_complete(children, key), native_named_lookup_complete(rest, key)),
          Equal.trans((Maybe<&2, SurfaceTypes.Node>), selected, compared, target,
            Equal.cong(Bool, (Maybe<&2, SurfaceTypes.Node>),
              (matches => Bool.pick((Maybe<&2, SurfaceTypes.Node>), matches, Some{node}, InterfaceView.prefer_node(required_child, required_sibling))),
              same, required_match, TextProof.public_refines(encoded, key)),
            Equal.cong((Maybe<&2, SurfaceTypes.Node>), (Maybe<&2, SurfaceTypes.Node>),
              (found => Rules_interface_program_rules.first_named_node_step(key, node, found)),
              InterfaceView.prefer_node(required_child, required_sibling),
              Rules_interface_program_rules.first_named_flat(List.append(&2, SurfaceTypes.Node,
                Rules_interface_program_rules.preorder_nodes(children), Rules_interface_program_rules.preorder_nodes(rest)), key),
              Equal.sym((Maybe<&2, SurfaceTypes.Node>),
                Rules_interface_program_rules.first_named_flat(List.append(&2, SurfaceTypes.Node,
                  Rules_interface_program_rules.preorder_nodes(children), Rules_interface_program_rules.preorder_nodes(rest)), key),
                InterfaceView.prefer_node(required_child, required_sibling),
                SemanticLookupEvidence.first_named_append(Rules_interface_program_rules.preorder_nodes(children),
                  Rules_interface_program_rules.preorder_nodes(rest), key))))))

def native_named_update_complete(+binding: Native.Binding, +nodes: +List<SurfaceTypes.Node>) ->
  {Native.update_named(binding, Native.prepare_named(nodes)) ==
    Rule.required_field_write(Rule.required_mounted_field(binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
      binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))) : +List<Native.Update>}:
  Native.Binding{+key, kind, semantic, meaning} = binding
  +found: Maybe<&2, SurfaceTypes.Node> = Native.find_named(Native.prepare_named(nodes), key)
  +required: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(nodes, key)
  Equal.trans(+List<Native.Update>, Native.update_named(binding, Native.prepare_named(nodes)),
    Rule.required_field_write(Rule.required_mounted_field(binding, found), binding, found),
    Rule.required_field_write(Rule.required_mounted_field(binding, required), binding, required),
    native_found_requirement(binding, found),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<Native.Update>,
      (node => Rule.required_field_write(Rule.required_mounted_field(binding, node), binding, node)),
      found, required, native_named_lookup_complete(nodes, key)))

def native_append_updates_equal(+first: +List<Native.Update>, +original_first: +List<Native.Update>,
  +rest: +List<Native.Update>, +original_rest: +List<Native.Update>,
  first_equal: {first == original_first : +List<Native.Update>},
  rest_equal: {rest == original_rest : +List<Native.Update>}) ->
  {List.append(&2, Native.Update, first, rest) == List.append(&2, Native.Update, original_first, original_rest) : +List<Native.Update>}:
  Equal.trans(+List<Native.Update>, List.append(&2, Native.Update, first, rest),
    List.append(&2, Native.Update, original_first, rest), List.append(&2, Native.Update, original_first, original_rest),
    Equal.cong(+List<Native.Update>, +List<Native.Update>, (updates => List.append(&2, Native.Update, updates, rest)), first, original_first, first_equal),
    Equal.cong(+List<Native.Update>, +List<Native.Update>, (updates => List.append(&2, Native.Update, original_first, updates)), rest, original_rest, rest_equal))

def field_updates_requirement(fields: +List<Native.Binding>, +nodes: +List<SurfaceTypes.Node>) ->
  {Native.updates_fields(fields, nodes) == Rule.required_field_updates(fields, nodes) : +List<Native.Update>}:
  match fields:
    case Nil{}: {==}
    case Con{+binding, +rest}:
      Native.Binding{+key, +kind, +semantic, +meaning} = binding
      native_append_updates_equal(Native.update(binding, nodes),
        Rule.required_field_write(Rule.required_mounted_field(binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
          binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
        Native.updates_fields(rest, nodes), Rule.required_field_updates(rest, nodes),
        native_field_requirement(binding, nodes), field_updates_requirement(rest, nodes))

def interactive_event_requirement(found: Maybe<&2, SurfaceTypes.Node>) ->
  {BrowserModel.interactive_event(found) == Rule.required_interactive_event(found) : Maybe<&2, Interactive.EventIdentity>}:
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SettingEntry{meaning_subject, meaning_value, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityRow{meaning_role}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityGroup{meaning_activity, meaning_dismiss, meaning_outside, meaning_escape}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DecisionGroup{meaning_decision}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceCollection{meaning_collection}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceMember{meaning_collection, meaning_path}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionUnit{meaning_action}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionFeedback{meaning_feedback}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionExplanation{meaning_assessment}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionCommit{meaning_assessment, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ObjectGroup{meaning_object}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SupportingControl{meaning_support, meaning_property, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{meaning_role}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.LayerRegion{meaning_dismiss, meaning_outside, meaning_escape}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryBrowserLocation{meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PanelToggle{meaning_expanded, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{meaning_face}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{meaning_destinations, meaning_face}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Region{}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{meaning_conversation}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityContent{meaning_expanded, meaning_audit}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectGroup{meaning_project, meaning_selected, meaning_expanded}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskRow{meaning_task, meaning_status, meaning_selected}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskChildren{meaning_task}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectChooser{meaning_selected}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryRow{meaning_path, meaning_primary}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ContextSummary{meaning_observation}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ChoiceGroup{}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{meaning_kind, meaning_classification, meaning_selected, meaning_description, meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{meaning_region, meaning_position}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardLane{meaning_stage, meaning_count}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardArchive{meaning_count}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardSearch{meaning_filter}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardGroup{meaning_grouping}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{meaning_text}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Fact{meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{meaning_source, meaning_value}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskFacts{meaning_details}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CodeFacts{meaning_view}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveRegion{meaning_identity, meaning_source_visible}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{meaning_identity, meaning_occurrence, meaning_tag, meaning_attrs, meaning_binding, meaning_children}}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveView{meaning_event, meaning_command, meaning_label, meaning_enabled}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Activate{meaning_input, meaning_availability}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Edit{meaning_editor, meaning_field, meaning_entry, meaning_value, meaning_choices}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SearchChoices{meaning_query}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.HistorySearchQuery{meaning_query}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.HistorySearchScope{scope_0, meaning_query, choices_0}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReceiveFile{meaning_editor, meaning_enabled}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.EnterDirectory{meaning_editor, meaning_text}, nested}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardProfile{meaning_automatic, meaning_selected, meaning_choices, meaning_enabled}, nested}}: {==}

def interactive_mount_requirement(left: Maybe<&2, Interactive.EventIdentity>, right: Maybe<&2, Interactive.EventIdentity>) ->
  {BrowserModel.matching_interactive_events(left, right) == Rule.required_same_mount(left, right) : Bool}:
  match left right:
    case None{} None{}: {==}
    case None{} Some{current}: {==}
    case Some{old} None{}: {==}
    case Some{old} Some{current}: {==}

def interactive_nodes_requirement(+old: Maybe<&2, SurfaceTypes.Node>, +current: Maybe<&2, SurfaceTypes.Node>) ->
  {BrowserModel.matching_interactive_nodes(old, current) ==
    Rule.required_same_mount(Rule.required_interactive_event(old), Rule.required_interactive_event(current)) : Bool}:
  Equal.trans(Bool, BrowserModel.matching_interactive_nodes(old, current),
    Rule.required_same_mount(BrowserModel.interactive_event(old), BrowserModel.interactive_event(current)),
    Rule.required_same_mount(Rule.required_interactive_event(old), Rule.required_interactive_event(current)),
    interactive_mount_requirement(BrowserModel.interactive_event(old), BrowserModel.interactive_event(current)),
    Equal.trans(Bool, Rule.required_same_mount(BrowserModel.interactive_event(old), BrowserModel.interactive_event(current)),
      Rule.required_same_mount(Rule.required_interactive_event(old), BrowserModel.interactive_event(current)),
      Rule.required_same_mount(Rule.required_interactive_event(old), Rule.required_interactive_event(current)),
      Equal.cong((Maybe<&2, Interactive.EventIdentity>), Bool,
        (event => Rule.required_same_mount(event, BrowserModel.interactive_event(current))),
        BrowserModel.interactive_event(old), Rule.required_interactive_event(old), interactive_event_requirement(old)),
      Equal.cong((Maybe<&2, Interactive.EventIdentity>), Bool,
        (event => Rule.required_same_mount(Rule.required_interactive_event(old), event)),
        BrowserModel.interactive_event(current), Rule.required_interactive_event(current), interactive_event_requirement(current))))

def action_found_requirement(+node: SurfaceTypes.Node, +key: String, +found: Maybe<&2, SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.action_binding_updates(key, found, pending, BrowserModel.matching_interactive_nodes(Some{node}, found)) ==
    Rule.required_action_binding_updates(key, found, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(found))) : +List<Native.Update>}:
  Equal.trans(+List<Native.Update>,
    BrowserModel.action_binding_updates(key, found, pending, BrowserModel.matching_interactive_nodes(Some{node}, found)),
    Rule.required_action_binding_updates(key, found, pending, BrowserModel.matching_interactive_nodes(Some{node}, found)),
    Rule.required_action_binding_updates(key, found, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(found))),
    Rule.action_binding_updates_complete(key, found, pending, BrowserModel.matching_interactive_nodes(Some{node}, found)),
    Equal.cong(Bool, +List<Native.Update>, (owned => Rule.required_action_binding_updates(key, found, pending, owned)),
      BrowserModel.matching_interactive_nodes(Some{node}, found),
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(found)),
      interactive_nodes_requirement(Some{node}, found)))

def current_action_requirement(+node: SurfaceTypes.Node, +key: UIIdentity.Key, +current: +List<SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.current_action_update(node, key, current, pending) ==
    Rule.required_action_binding_updates(UIIdentity.encode(key), Rules_interface_program_rules.first_named_node(current, UIIdentity.encode(key)), pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}),
        Rule.required_interactive_event(Rules_interface_program_rules.first_named_node(current, UIIdentity.encode(key))))) : +List<Native.Update>}:
  +encoded: String = UIIdentity.encode(key)
  +found: Maybe<&2, SurfaceTypes.Node> = InterfaceView.find_node(current, encoded)
  +required: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(current, encoded)
  Equal.trans(+List<Native.Update>, BrowserModel.current_action_update(node, key, current, pending),
    Rule.required_action_binding_updates(encoded, found, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(found))),
    Rule.required_action_binding_updates(encoded, required, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(required))),
    action_found_requirement(node, encoded, found, pending),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<Native.Update>,
      (next => Rule.required_action_binding_updates(encoded, next, pending,
        Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(next)))),
      found, required, Rules_interface_program_rules.complete_node_lookup(current, encoded)))

def Rule.action_update_complete(node, current, pending):
  SurfaceTypes.Node{+key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, nested}}:
      match binding:
        case Interactive.NoBinding{}: {==}
        case Interactive.FieldBinding{state, schema, raw, canonical, validation, enabled}: {==}
        case Interactive.ActionBinding{kind, enabled, busy}: current_action_requirement(node, key, current, pending)
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}: current_action_requirement(node, key, current, pending)
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value}: {==}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.MovableCard{destinations, face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardSearch{filter}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: {==}
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.HistorySearchQuery{query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}

def action_updates_requirement(published: +List<SurfaceTypes.Node>, +current: +List<SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.action_updates(published, current, pending) == Rule.required_action_updates(published, current, pending) : +List<Native.Update>}:
  match published:
    case Nil{}: {==}
    case Con{+node, +rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, +children} = node
      native_append_updates_equal(BrowserModel.action_update(node, current, pending), Rule.required_action_update(node, current, pending),
        List.append(&2, Native.Update, BrowserModel.action_updates(children, current, pending), BrowserModel.action_updates(rest, current, pending)),
        List.append(&2, Native.Update, Rule.required_action_updates(children, current, pending), Rule.required_action_updates(rest, current, pending)),
        Rule.action_update_complete(node, current, pending),
        native_append_updates_equal(BrowserModel.action_updates(children, current, pending), Rule.required_action_updates(children, current, pending),
          BrowserModel.action_updates(rest, current, pending), Rule.required_action_updates(rest, current, pending),
          action_updates_requirement(children, current, pending), action_updates_requirement(rest, current, pending)))

def native_named_fields_complete(fields: +List<Native.Binding>, +nodes: +List<SurfaceTypes.Node>) ->
  {Native.updates_fields_named(fields, Native.prepare_named(nodes)) == Rule.required_field_updates(fields, nodes) : +List<Native.Update>}:
  match fields:
    case Nil{}: {==}
    case Con{+binding, +rest}:
      Native.Binding{+key, +kind, +semantic, +meaning} = binding
      native_append_updates_equal(Native.update_named(binding, Native.prepare_named(nodes)),
        Rule.required_field_write(Rule.required_mounted_field(binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
          binding, Rules_interface_program_rules.first_named_node(nodes, field_binding_key(binding))),
        Native.updates_fields_named(rest, Native.prepare_named(nodes)), Rule.required_field_updates(rest, nodes),
        native_named_update_complete(binding, nodes), native_named_fields_complete(rest, nodes))

def native_named_current_action_complete(+node: SurfaceTypes.Node, +key: UIIdentity.Key, +current: +List<SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.current_action_named_update(node, key, Native.prepare_named(current), pending) ==
    Rule.required_action_binding_updates(UIIdentity.encode(key), Rules_interface_program_rules.first_named_node(current, UIIdentity.encode(key)), pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}),
        Rule.required_interactive_event(Rules_interface_program_rules.first_named_node(current, UIIdentity.encode(key))))) : +List<Native.Update>}:
  +encoded: String = UIIdentity.encode(key)
  +found: Maybe<&2, SurfaceTypes.Node> = Native.find_named(Native.prepare_named(current), encoded)
  +required: Maybe<&2, SurfaceTypes.Node> = Rules_interface_program_rules.first_named_node(current, encoded)
  Equal.trans(+List<Native.Update>, BrowserModel.current_action_named_update(node, key, Native.prepare_named(current), pending),
    Rule.required_action_binding_updates(encoded, found, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(found))),
    Rule.required_action_binding_updates(encoded, required, pending,
      Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(required))),
    action_found_requirement(node, encoded, found, pending),
    Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<Native.Update>,
      (next => Rule.required_action_binding_updates(encoded, next, pending,
        Rule.required_same_mount(Rule.required_interactive_event(Some{node}), Rule.required_interactive_event(next)))),
      found, required, native_named_lookup_complete(current, encoded)))

def native_named_action_complete(+node: SurfaceTypes.Node, +current: +List<SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.action_named_update(node, Native.prepare_named(current), pending) == Rule.required_action_update(node, current, pending) : +List<Native.Update>}:
  SurfaceTypes.Node{+key, semantic, label, role, meaning, children} = node
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, nested}}:
      match binding:
        case Interactive.NoBinding{}: {==}
        case Interactive.FieldBinding{state, schema, raw, canonical, validation, enabled}: {==}
        case Interactive.ActionBinding{kind, enabled, busy}: native_named_current_action_complete(node, key, current, pending)
    case SurfaceTypes.InteractiveView{event, command, label_value, enabled}: native_named_current_action_complete(node, key, current, pending)
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value}: {==}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.MovableCard{destinations, face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardSearch{filter}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: {==}
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.HistorySearchQuery{query}: {==}
    case SurfaceTypes.HistorySearchScope{scope_0, query, choices_0}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}


def native_named_actions_complete(old: +List<SurfaceTypes.Node>, +current: +List<SurfaceTypes.Node>, +pending: Bool) ->
  {BrowserModel.action_updates_named(old, Native.prepare_named(current), pending) == Rule.required_action_updates(old, current, pending) : +List<Native.Update>}:
  match old:
    case Nil{}: {==}
    case Con{+node, +rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, +children} = node
      native_append_updates_equal(BrowserModel.action_named_update(node, Native.prepare_named(current), pending), Rule.required_action_update(node, current, pending),
        List.append(&2, Native.Update, BrowserModel.action_updates_named(children, Native.prepare_named(current), pending), BrowserModel.action_updates_named(rest, Native.prepare_named(current), pending)),
        List.append(&2, Native.Update, Rule.required_action_updates(children, current, pending), Rule.required_action_updates(rest, current, pending)),
        native_named_action_complete(node, current, pending),
        native_append_updates_equal(BrowserModel.action_updates_named(children, Native.prepare_named(current), pending), Rule.required_action_updates(children, current, pending),
          BrowserModel.action_updates_named(rest, Native.prepare_named(current), pending), Rule.required_action_updates(rest, current, pending),
          native_named_actions_complete(children, current, pending), native_named_actions_complete(rest, current, pending)))

def native_plain_actions_scoped_requirement(+old: +List<SurfaceTypes.Node>, +surface: SurfaceTypes.Surface, +pending: Bool) ->
  {BrowserModel.action_updates(old, InterfaceView.active_nodes(surface), pending) ==
    Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending) : +List<Native.Update>}:
  Equal.trans(+List<Native.Update>, BrowserModel.action_updates(old, InterfaceView.active_nodes(surface), pending),
    Rule.required_action_updates(old, InterfaceView.active_nodes(surface), pending),
    Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
    action_updates_requirement(old, InterfaceView.active_nodes(surface), pending),
    Equal.cong(+List<SurfaceTypes.Node>, +List<Native.Update>, (nodes => Rule.required_action_updates(old, nodes, pending)),
      InterfaceView.active_nodes(surface), FocusRules.required_active_nodes(surface), active_nodes_requirement(surface)))

def native_named_actions_scoped_requirement(+old: +List<SurfaceTypes.Node>, +surface: SurfaceTypes.Surface, +pending: Bool) ->
  {BrowserModel.action_updates_named(old, Native.prepare_named(InterfaceView.active_nodes(surface)), pending) ==
    Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending) : +List<Native.Update>}:
  Equal.trans(+List<Native.Update>, BrowserModel.action_updates_named(old, Native.prepare_named(InterfaceView.active_nodes(surface)), pending),
    Rule.required_action_updates(old, InterfaceView.active_nodes(surface), pending),
    Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
    native_named_actions_complete(old, InterfaceView.active_nodes(surface), pending),
    Equal.cong(+List<SurfaceTypes.Node>, +List<Native.Update>, (nodes => Rule.required_action_updates(old, nodes, pending)),
      InterfaceView.active_nodes(surface), FocusRules.required_active_nodes(surface), active_nodes_requirement(surface)))

def native_named_scope_complete(+fields: +List<Native.Binding>, +controls: +List<String>,
  +old: +List<SurfaceTypes.Node>, +surface: SurfaceTypes.Surface, +pending: Bool) ->
  {BrowserModel.native_updates_named_scope(Native.Basis{fields, controls}, old, surface, pending) ==
    List.append(&2, Native.Update, Rule.required_field_updates(fields, Native.forest(surface)),
      Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending)) : +List<Native.Update>}:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  match scope:
    case None{}:
      native_append_updates_equal(Native.updates_fields_named(fields, Native.prepare_named(Native.forest(surface))),
        Rule.required_field_updates(fields, Native.forest(surface)),
        BrowserModel.action_updates_named(old, Native.prepare_named(Native.forest(surface)), pending),
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
        native_named_fields_complete(fields, Native.forest(surface)), native_named_actions_complete(old, Native.forest(surface), pending))
    case Some{key}:
      native_append_updates_equal(Native.updates_fields_named(fields, Native.prepare_named(Native.forest(surface))),
        Rule.required_field_updates(fields, Native.forest(surface)),
        BrowserModel.action_updates_named(old, Native.prepare_named(InterfaceView.active_nodes(surface)), pending),
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
        native_named_fields_complete(fields, Native.forest(surface)), native_named_actions_scoped_requirement(old, surface, pending))

def native_named_families_complete(fields_many: Bool, actions_many: Bool, +fields: +List<Native.Binding>,
  +controls: +List<String>, +old: +List<SurfaceTypes.Node>, +surface: SurfaceTypes.Surface, +pending: Bool) ->
  {BrowserModel.native_updates_families(fields_many, actions_many, Native.Basis{fields, controls}, old, surface, pending) ==
    List.append(&2, Native.Update, Rule.required_field_updates(fields, Native.forest(surface)),
      Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending)) : +List<Native.Update>}:
  match fields_many actions_many:
    case False{} False{}:
      native_append_updates_equal(Native.updates(Native.Basis{fields, controls}, surface),
        Rule.required_field_updates(fields, Native.forest(surface)),
        BrowserModel.action_updates(old, InterfaceView.active_nodes(surface), pending),
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
        field_updates_requirement(fields, Native.forest(surface)), native_plain_actions_scoped_requirement(old, surface, pending))
    case True{} False{}:
      native_append_updates_equal(Native.updates_fields_named(fields, Native.prepare_named(Native.forest(surface))),
        Rule.required_field_updates(fields, Native.forest(surface)),
        BrowserModel.action_updates(old, InterfaceView.active_nodes(surface), pending),
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
        native_named_fields_complete(fields, Native.forest(surface)), native_plain_actions_scoped_requirement(old, surface, pending))
    case False{} True{}:
      native_append_updates_equal(Native.updates(Native.Basis{fields, controls}, surface),
        Rule.required_field_updates(fields, Native.forest(surface)),
        BrowserModel.action_updates_named(old, Native.prepare_named(InterfaceView.active_nodes(surface)), pending),
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
        field_updates_requirement(fields, Native.forest(surface)), native_named_actions_scoped_requirement(old, surface, pending))
    case True{} True{}: native_named_scope_complete(fields, controls, old, surface, pending)

def native_action_scope_policy(+published: SurfaceTypes.Surface, +current: SurfaceTypes.Surface, +pending: Bool) ->
  {Rule.required_action_updates(InterfaceView.active_nodes(published), FocusRules.required_active_nodes(current), pending) ==
    Rule.required_action_updates(FocusRules.required_active_nodes(published), FocusRules.required_active_nodes(current), pending) : +List<Native.Update>}:
  Equal.cong(+List<SurfaceTypes.Node>, +List<Native.Update>,
    (nodes => Rule.required_action_updates(nodes, FocusRules.required_active_nodes(current), pending)),
    InterfaceView.active_nodes(published), FocusRules.required_active_nodes(published), active_nodes_requirement(published))

def native_mounts_requirement(+fields: +List<Native.Binding>, +published: SurfaceTypes.Surface,
  +current: SurfaceTypes.Surface, +pending: Bool) ->
  {List.append(&2, Native.Update, Rule.required_field_updates(fields, Native.forest(current)),
    Rule.required_action_updates(FocusRules.required_active_nodes(published), FocusRules.required_active_nodes(current), pending)) ==
    Rule.required_native_mounts(fields, published, current, pending) : +List<Native.Update>}:
  SurfaceTypes.Surface{content, base, overlays, active} = current
  {==}

def native_updates_named_complete(+state: BrowserModel.State) ->
  {BrowserModel.native_updates(state) == Rule.required_native_updates(state) : +List<Native.Update>}:
  match state:
    case BrowserModel.State{legacy, generation, anchors, lifecycle, None{}, attention, updates}: {==}
    case BrowserModel.State{legacy, generation, anchors, lifecycle, Some{BrowserModel.Published{world, +semantic, scope, +basis, frame}}, attention, updates}:
      Native.Basis{+fields, +controls} = basis
      +surface: SurfaceTypes.Surface = BrowserModel.current_surface(state)
      +old: +List<SurfaceTypes.Node> = InterfaceView.active_nodes(semantic)
      +pending: Bool = BrowserModel.semantic_pending(state)
      +actual: +List<Native.Update> = BrowserModel.native_updates(state)
      +required_fields: +List<Native.Update> = Rule.required_field_updates(fields, Native.forest(surface))
      +required: +List<Native.Update> = List.append(&2, Native.Update, required_fields,
        Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending))
      +scoped: +List<Native.Update> = List.append(&2, Native.Update, required_fields,
        Rule.required_action_updates(FocusRules.required_active_nodes(semantic), FocusRules.required_active_nodes(surface), pending))
      Equal.trans(+List<Native.Update>, actual, required, Rule.required_native_updates(state),
        native_named_families_complete(Native.fields_many(fields), BrowserModel.actions_many(old), fields, controls, old, surface, pending),
        Equal.trans(+List<Native.Update>, required, scoped, Rule.required_native_updates(state),
          Equal.cong(+List<Native.Update>, +List<Native.Update>, (actions => List.append(&2, Native.Update, required_fields, actions)),
            Rule.required_action_updates(old, FocusRules.required_active_nodes(surface), pending),
            Rule.required_action_updates(FocusRules.required_active_nodes(semantic), FocusRules.required_active_nodes(surface), pending),
            native_action_scope_policy(semantic, surface, pending)),
          Equal.trans(+List<Native.Update>, scoped,
            List.append(&2, Native.Update, required_fields,
              Rule.required_action_updates(FocusRules.required_active_nodes(semantic), FocusRules.required_active_nodes(surface), Rule.required_semantic_pending(state))),
            Rule.required_native_updates(state),
            Equal.cong(Bool, +List<Native.Update>,
              (lag => List.append(&2, Native.Update, required_fields,
                Rule.required_action_updates(FocusRules.required_active_nodes(semantic), FocusRules.required_active_nodes(surface), lag))),
              pending, Rule.required_semantic_pending(state), Rule.semantic_pending_is_publication_lag(state)),
            native_mounts_requirement(fields, semantic, surface, Rule.required_semantic_pending(state)))))

def Rule.native_updates_use_semantic_lag(state):
  native_updates_named_complete(state)
