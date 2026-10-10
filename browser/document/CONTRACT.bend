import Base
import ../controls/GEOMETRY.bend as Geometry
import ./SPEC.bend as Spec
import ./RENDERED.bend as Rendered
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/IDENTITY.bend as UIIdentity
import ../appearance/ICONS.bend as Iconography
import ../controls/MODEL.bend as Authored
import ../controls/authored-primitives.bend as Factory
import ./SOURCE.bend as Source
import ../layout/physical-space.bend as Model
import ../../harness/DOMAIN.bend as Domain
import ../layout/GEOMETRY.bend as SpatialModel
import ../layout/SPACE.bend as Space
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/enclosure.bend as Enclosure
import ../appearance/MODEL.bend as Appearance
import ../appearance/DESIGN.bend as Design
import ../controls/PROGRAM.bend as Controls
import ../../interaction/INPUT.bend as User
import ../../interaction/session/MODEL.bend as Experience
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/services/CONTEXT.bend as Workspace
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/VIEW.bend as View2
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../interaction/submission/field-options.bend as FieldOptions
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../bendlib/json.bend as J
import ../runtime/PLATFORM.bend as Platform
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ./presentation-order.bend as Order
import ../MODEL.bend as Model2

def projected_action(input: InteractionTypes.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) -> Controls.Representation:
  Controls.ActionPresentation{face, behavior, geometry} = projection
  Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}

def label_properties(value: Design.Style) -> (SpatialModel.Flow & (SpatialModel.Overflow & (Nat & Nat))):
  Design.Style{text, chrome, alignment, flow, overflow, +frame, minimum, maximum, states} = value
  (flow, (overflow, (Enclosure.inline(Enclosure.frame_content(frame)), Enclosure.block(Enclosure.frame_content(frame)))))

def name_geometry_law(-visual: Design.Style) -> Type:
  {label_properties(Appearance.project_label_style(visual)) == (SpatialModel.BlockFlow{}, (SpatialModel.SingleLineOverflow{}, (0n, 0n))) : (SpatialModel.Flow & (SpatialModel.Overflow & (Nat & Nat)))}

def chooser_draft_observation_law(-id: Nat, -fallback: Design.Style) -> Type:
  {Design.style_text(Appearance.chooser_style(Some{id}, fallback)) == Design.style_text(fallback) : T.Presentation}

def first_control(values: +List<Design.Node>) -> Controls.Representation:
  match values:
    case Nil{}: Controls.NoControl{}
    case Con{Design.Node{key, semantic, label, role, meaning, visual, control, children}, rest}: control

def project_reference_law(-key: UIIdentity.Key, -semantic: String, -label: String, -role: SurfaceTypes.Role, -children: +List<SurfaceTypes.Node>, -context: Controls.Context, -project: Nat, -selected: Bool, -expanded: Bool) -> Type:
  {Controls.source_reference(Controls.enter(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectGroup{project, selected, expanded}, children}, context)) == Controls.SourceFamily{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectGroup{project, selected, expanded}, children}} : Controls.SourceFamily}

def task_reference_law(-key: UIIdentity.Key, -semantic: String, -label: String, -role: SurfaceTypes.Role, -children: +List<SurfaceTypes.Node>, -context: Controls.Context, -task: Nat, -status: View.TaskStatus, -selected: Bool) -> Type:
  {Controls.source_reference(Controls.enter(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskRow{task, status, selected}, children}, context)) == Controls.SourceFamily{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskRow{task, status, selected}, children}} : Controls.SourceFamily}

def chooser_reference_law(-key: UIIdentity.Key, -semantic: String, -label: String, -role: SurfaceTypes.Role, -children: +List<SurfaceTypes.Node>, -context: Controls.Context, -selected: Maybe<&2, Nat>) -> Type:
  {Controls.source_reference(Controls.enter(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectChooser{selected}, children}, context)) == Controls.SourceFamily{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectChooser{selected}, children}} : Controls.SourceFamily}

def status_extent(node: Source.Node) -> Model.AxisSize & (Model.AxisSize & Enclosure.Extent):
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attrs, children}: (width, (height, minimum))
    case _: (Model.ExactSize{0n}, (Model.ExactSize{0n}, Enclosure.Extent{0n, 0n}))

type ProjectPresentationRequirements is Type:
  ProjectPresentationRequirements{
    disclosure_typed: @+project:Nat -> {Controls.project_control_input(InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Controls.ProjectDisclosure{} : Controls.ProjectControl},
    name_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Controls.ProjectName{} : Controls.ProjectControl},
    create_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Controls.ProjectCreate{} : Controls.ProjectControl},
    more_typed: @+project:Nat -> @+trigger:String -> {Controls.project_control_input(InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Controls.ProjectMore{} : Controls.ProjectControl},
    disclosure_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectDisclosure{}, name, expanded, fallback) == Controls.IconFace{Controls.disclosure_glyph(expanded)} : Controls.Face},
    project_family_projection: @+area:Controls.Area -> @+owner:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+children:+List<SurfaceTypes.Node> -> @+input:InteractionTypes.Input -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry ->
      {Controls.contextual_source_presentation(area, Controls.SourceFamily{SurfaceTypes.Node{owner, semantic, label, role, SurfaceTypes.ProjectGroup{project, selected, expanded}, children}}, input, name, face, behavior, geometry) ==
        Controls.project_presentation(Controls.project_control_matches(input, project), Controls.project_control_input(input), expanded, name, face, behavior, geometry) : Controls.ActionPresentation},
    unscoped_projection: @+area:Controls.Area -> @+input:InteractionTypes.Input -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry ->
      {Controls.contextual_source_presentation(area, Controls.Unscoped{}, input, name, face, behavior, geometry) == Controls.ActionPresentation{face, behavior, geometry} : Controls.ActionPresentation},
    complete_action_projection: @+area:Controls.Area -> @+family:Controls.SourceFamily -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback -> {Controls.source_action(area, family, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}) ==
        projected_action(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback) : Controls.Representation},
    disclosure_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectDisclosure{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(24n, 24n), icon, radius, leading} : Controls.Geometry},
    create_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectCreate{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading} : Controls.Geometry},
    more_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectMore{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading} : Controls.Geometry},
    name_geometry: @+visual:Design.Style -> name_geometry_law(visual),
    chevron_paths: {(Iconography.path(Controls.ChevronRight{}), Iconography.path(Controls.ChevronDown{})) == ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String},
    chooser_value_binding: @+trigger:String -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> {Controls.chooser_presentation(InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, name, face, behavior, geometry) == Controls.ActionPresentation{Controls.PickerFace{Some{Controls.Folder{}}, name}, behavior, geometry} : Controls.ActionPresentation},
    create_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectCreate{}, name, expanded, fallback) == Controls.IconFace{Controls.Plus{}} : Controls.Face},
    more_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectMore{}, name, expanded, fallback) == Controls.IconFace{Controls.MoreDots{}} : Controls.Face},
    chooser_draft_observation: @+id:Nat -> @+fallback:Design.Style -> chooser_draft_observation_law(id, fallback),
    source_group_style: @+typography:T.Presentation -> @+key:UIIdentity.Key -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> {Appearance.final_style(key, SurfaceTypes.ProjectGroup{project, selected, expanded}, context, representation, fallback, typography) == Appearance.project_group_style(typography) : Design.Style},
    source_task_style: @+typography:T.Presentation -> @+key:UIIdentity.Key -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+task:Nat -> @+status:View.TaskStatus -> @+selected:Bool -> {Appearance.final_style(key, SurfaceTypes.TaskRow{task, status, selected}, context, representation, fallback, typography) == Appearance.navigation_family_style(selected, 6n, 5n, typography) : Design.Style},
    project_reference: @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+children:+List<SurfaceTypes.Node> -> @+context:Controls.Context -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> project_reference_law(key, semantic, label, role, children, context, project, selected, expanded),
    task_reference: @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+children:+List<SurfaceTypes.Node> -> @+context:Controls.Context -> @+task:Nat -> @+status:View.TaskStatus -> @+selected:Bool -> task_reference_law(key, semantic, label, role, children, context, task, status, selected),
    chooser_reference: @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+children:+List<SurfaceTypes.Node> -> @+context:Controls.Context -> @+selected:Maybe<&2, Nat> -> chooser_reference_law(key, semantic, label, role, children, context, selected),
    complete_control_binding: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+meaning:SurfaceTypes.Meaning -> @+children:+List<SurfaceTypes.Node> -> @+context:Controls.Context -> {first_control(Appearance.nodes_at([SurfaceTypes.Node{key, semantic, label, role, meaning, children}], context, typography, in_main, start)) == Controls.represent(key, meaning, label, role, Controls.enter(SurfaceTypes.Node{key, semantic, label, role, meaning, children}, context)) : Controls.Representation},
    actual_header_style: @+typography:T.Presentation -> @+key:UIIdentity.Key -> @+owner:UIIdentity.Key -> @+owner_semantic:String -> @+owner_label:String -> @+owner_role:SurfaceTypes.Role -> @+owner_children:+List<SurfaceTypes.Node> -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+area:Controls.Area -> @+selection:Controls.Selection -> @+code:Maybe<&2, Code.Scene> -> @+appearance:Services.Appearance -> @+access:Services.Access -> @+open:Bool -> @+layers:+List<View.Layer> -> @+execution:Maybe<&2, Workspace.Observation> -> @+representation:Controls.Representation -> @+fallback:Design.Style -> {Appearance.final_style(key, SurfaceTypes.Region{}, Controls.Context{area, selection, code, appearance, access, open, layers, execution, Controls.SourceFamily{SurfaceTypes.Node{owner, owner_semantic, owner_label, owner_role, SurfaceTypes.ProjectGroup{project, selected, expanded}, owner_children}}}, representation, fallback, typography) ==
        Appearance.source_style(UIIdentity.same(key, UIIdentity.part(owner, "actions")), Controls.SourceFamily{SurfaceTypes.Node{owner, owner_semantic, owner_label, owner_role, SurfaceTypes.ProjectGroup{project, selected, expanded}, owner_children}}, fallback, typography) : Design.Style},
    working_status_glyph: {Controls.task_status_glyph(View.TaskStatus{Domain.Active{}, True{}}) == Controls.PlayTriangle{} : Controls.Icon},
    ready_status_glyph: {Controls.task_status_glyph(View.TaskStatus{Domain.Active{}, False{}}) == Controls.Check{} : Controls.Icon},
    paused_status_glyph: @working:Bool -> {Controls.task_status_glyph(View.TaskStatus{Domain.Frozen{}, working}) == Controls.PauseBars{} : Controls.Icon},
    stopped_status_glyph: @working:Bool -> {Controls.task_status_glyph(View.TaskStatus{Domain.Stopped{}, working}) == Controls.StopSquare{} : Controls.Icon},
    archived_status_glyph: @working:Bool -> {Controls.task_status_glyph(View.TaskStatus{Domain.Archived{}, working}) == Controls.ArchiveBox{} : Controls.Icon},
    status_indicator: @+key:UIIdentity.Key -> @+status:View.TaskStatus -> @+visual:Design.Style ->
      {Authored.task_status_indicator(key, status, visual) == Source.Box{key, Source.Span{}, Factory.glyph_style(visual, 16n, 16n),
        [Source.DataAttribute{"native-key", UIIdentity.encode(key)}, Source.RoleAttribute{"img"}, Source.AriaAttribute{"label", View2.task_status_label(status)}, Source.TitleAttribute{View2.task_status_label(status)}],
        [Source.Glyph{UIIdentity.part(key, "indicator"), Iconography.drawing(Controls.task_status_glyph(status), 16n), Factory.glyph_style(visual, 16n, 16n)}]} : Source.Node},
    status_indicator_extent: @+key:UIIdentity.Key -> @status:View.TaskStatus -> @visual:Design.Style ->
      {status_extent(Authored.task_status_indicator(key, status, visual)) == (Model.ExactSize{16n}, (Model.ExactSize{16n}, Enclosure.Extent{16n, 16n})) : Model.AxisSize & (Model.AxisSize & Enclosure.Extent)},
    status_child_indicator: @+key:UIIdentity.Key -> @role:SurfaceTypes.Role -> @meaning:SurfaceTypes.Meaning -> @nodes:+List<Source.Node> -> @+rest:+List<Authored.Child> -> @+status:View.TaskStatus -> @+visual:Design.Style ->
      {Authored.task_children(Authored.Child{key, role, meaning, Controls.NoControl{}, nodes} <> rest, status, visual) == Authored.task_status_indicator(key, status, visual) <> Authored.task_children(rest, status, visual) : +List<Source.Node>}}

law project_presentation_evidence:
  ProjectPresentationRequirements

def instructions_text_when(empty: Bool, value: String) -> String:
  match empty:
    case True{}: "No project instructions"
    case False{}: value

def instructions_text(+value: String) -> String:
  instructions_text_when(String.eq(value, ""), value)

def project_law(+owner: UIIdentity.Key, +label: String, +directory: String, +revision: String, +instructions: String, +visual: Design.Style) -> Type:
  {Authored.project_context_facts(owner, label, Domain.ProjectContext{directory, revision, instructions}, visual) ==
    [Authored.group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), Authored.fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), Authored.fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), Authored.fact(UIIdentity.part(owner, "instructions"), "Instructions", instructions_text(instructions), visual)])] : +List<Source.Node>}

def projection_law(+owner: UIIdentity.Key, +task: Nat, +roots: +List<String>, +primary: Maybe<&2, String>, +mode: Domain.SandboxMode, +network: Bool, +approval: Domain.ApprovalPolicy, +project: Maybe<&2, Nat>, +guidance: Domain.ProjectContext, +access: Domain.ExecutionAccess, +id: String, +provider: String, +name: String, +policy: Reasoning.Policy, +options: Maybe<&2, Domain.ReasoningOptions>, +reasoning: String, +model_guidance: Domain.ProjectContext, +tools: +List<Domain.Tool>, +lineage: +List<Nat>, +queued: +List<String>, +status: Domain.Status, +phase: Domain.Phase, +visual: Design.Style) -> Type:
  {Authored.task_details(owner, View.TaskDetails{Workspace.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy, options}, reasoning, model_guidance}, tools, lineage, queued, status, phase}, visual) ==
    [Authored.group(UIIdentity.part(owner, "@facts"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.append([Authored.fact(UIIdentity.part(owner, "@workspace"), "Working directories", FieldOptions.joined(roots), visual), Authored.fact(UIIdentity.part(owner, "@primary"), "Primary directory", FieldOptions.optional_text(primary), visual), Authored.fact(UIIdentity.part(owner, "@sandbox"), "Filesystem access", Workspace.filesystem_summary(access, mode), visual), Authored.fact(UIIdentity.part(owner, "@network"), "Network access", Workspace.network_summary(access, network), visual), Authored.fact(UIIdentity.part(owner, "@approval"), "Approval policy", Domain.approval_name(approval), visual), Authored.fact(UIIdentity.part(owner, "@model"), "Model", name, visual), Authored.fact(UIIdentity.part(owner, "@reasoning"), "Reasoning", reasoning, visual), Authored.fact(UIIdentity.part(owner, "@status"), "Status", Domain.status_name(status), visual), Authored.fact(UIIdentity.part(owner, "@phase"), "Phase", Tasks.phase_name(phase), visual), Authored.fact(UIIdentity.part(owner, "@messages"), "Queued messages", FieldOptions.joined(queued), visual), Authored.group(UIIdentity.part(owner, "@tools"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.text(UIIdentity.part(UIIdentity.part(owner, "@tools"), "title"), "Tools", visual, T.Body{}, T.Strong{}) <> Authored.tool_detail_nodes(UIIdentity.part(owner, "@tools"), tools, visual)), Authored.fact(UIIdentity.part(owner, "@lineage"), "Ancestor tasks", FieldOptions.joined(Authored.ancestor_names(lineage)), visual)], Authored.append(Authored.project_context_facts(UIIdentity.part(owner, "@task-project"), "Task project context", guidance, visual), Authored.project_context_facts(UIIdentity.part(owner, "@model-project"), "Model project context", model_guidance, visual))))] : +List<Source.Node>}

type TaskDetailsRequirements is Type:
  TaskDetailsRequirements{
    missing_project: @+owner:UIIdentity.Key -> @+label:String -> @+visual:Design.Style -> {Authored.project_context_facts(owner, label, Domain.NoProject{}, visual) == Nil{} : +List<Source.Node>},
    frozen_project: @+owner:UIIdentity.Key -> @+label:String -> @+directory:String -> @+revision:String -> @+instructions:String -> @+visual:Design.Style -> project_law(owner, label, directory, revision, instructions, visual),
    no_tools: @+owner:UIIdentity.Key -> @+visual:Design.Style -> {Authored.tool_detail_nodes(owner, Nil{}, visual) == Nil{} : +List<Source.Node>},
    every_tool: @+owner:UIIdentity.Key -> @+name:String -> @+description:String -> @+schema:J.Json -> @+source:Domain.Source -> @+rest:+List<Domain.Tool> -> @+visual:Design.Style ->
      {Authored.tool_detail_nodes(owner, Con{Domain.Tool{name, description, schema, source}, rest}, visual) == Authored.fact(UIIdentity.entity(owner, "tool", name), name, description, visual) <> Authored.tool_detail_nodes(owner, rest, visual) : +List<Source.Node>},
    no_ancestors: {Authored.ancestor_names(Nil{}) == Nil{} : +List<String>},
    ancestor_order: @+ancestor:Nat -> @+rest:+List<Nat> -> {Authored.ancestor_names(Con{ancestor, rest}) == Nat.show(ancestor) <> Authored.ancestor_names(rest) : +List<String>},
    complete_projection: @+owner:UIIdentity.Key -> @+task:Nat -> @+roots:+List<String> -> @+primary:Maybe<&2,String> -> @+mode:Domain.SandboxMode -> @+network:Bool -> @+approval:Domain.ApprovalPolicy -> @+project:Maybe<&2,Nat> -> @+guidance:Domain.ProjectContext -> @+access:Domain.ExecutionAccess -> @+id:String -> @+provider:String -> @+name:String -> @+policy:Reasoning.Policy -> @+options:Maybe<&2,Domain.ReasoningOptions> -> @+reasoning:String -> @+model_guidance:Domain.ProjectContext -> @+tools:+List<Domain.Tool> -> @+lineage:+List<Nat> -> @+queued:+List<String> -> @+status:Domain.Status -> @+phase:Domain.Phase -> @+visual:Design.Style -> projection_law(owner, task, roots, primary, mode, network, approval, project, guidance, access, id, provider, name, policy, options, reasoning, model_guidance, tools, lineage, queued, status, phase, visual)}

law task_details_evidence:
  TaskDetailsRequirements

def decision_state(decision: Model2.Decision) -> Model2.State:
  Model2.Decision{state, product, effects} = decision
  state

def state_capacity(+state: Model2.State) -> View.Capacity:
  +observed_application_1 = Model2.application(state)
  +platform = Platform.platform(observed_application_1)
  Model2.capacity(platform)

def state_environment(+state: Model2.State) -> Design.Environment:
  +environment = Model2.environment(state)
  environment

def decision_capacity(decision: Model2.Decision) -> View.Capacity:
  state_capacity(decision_state(decision))

def decision_environment(decision: Model2.Decision) -> Design.Environment:
  state_environment(decision_state(decision))

def original_core(application: Platform.State) -> InteractionTypes.State:
  Model2.model_core(application)

def original_platform(application: Platform.State) -> Platform.Platform:
  Model2.model_platform(application)

def platform_decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  Model2.capacity(platform)

type PresentationRequirements is Type:
  PresentationRequirements{
    environment_observed_preserves_core: @+model_state:Model2.State ->  @+environment:Design.Environment -> {Model2.product(Model2.step(Model2.EnvironmentObserved{environment}, model_state)) == Platform.unchanged(original_core(Model2.application(model_state))) : InteractionTypes.Decision},
    environment_observed_stores_environment: @+model_state:Model2.State ->  @+environment:Design.Environment -> {decision_environment(Model2.step(Model2.EnvironmentObserved{environment}, model_state)) == environment : Design.Environment},
    frame_preserves_environment: @+model_state:Model2.State ->  @received:Nat -> @frame:Rendered.Frame -> {decision_environment(Model2.step(Model2.FrameObserved{received, frame}, model_state)) == Model2.environment(model_state) : Design.Environment},
    element_preserves_environment: @+model_state:Model2.State ->  @key:String -> @gesture:SurfaceTypes.Gesture -> {decision_environment(Model2.step(Model2.ElementInput{key, gesture}, model_state)) == Model2.environment(model_state) : Design.Environment},
    reflow_sets_requested_capacity: @+decision:Platform.Decision -> @+requested:View.Capacity ->
      {platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity},
    environment_observed_preserves_capacity: @+model_state:Model2.State ->  @+environment:Design.Environment -> {decision_capacity(Model2.step(Model2.EnvironmentObserved{environment}, model_state)) == state_capacity(model_state) : View.Capacity}}

law presentation_evidence:
  PresentationRequirements

type NodePayload is Data:
  NodePayload{key: UIIdentity.Key, semantic: String, label: String, role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning}

type SurfacePayload is Data:
  SurfacePayload{content: InteractionTypes.Scene, scope: Maybe<&2, String>}

def node_payload(value: SurfaceTypes.Node) -> NodePayload:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = value
  NodePayload{key, semantic, label, role, meaning}

def surface_payload(surface: SurfaceTypes.Surface) -> SurfacePayload:
  SurfaceTypes.Surface{content, base, overlays, active_scope} = surface
  SurfacePayload{content, active_scope}

def specified_header_representation(representation: Controls.Representation) -> Bool:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: True{}
    case _: False{}

def specified_header_child(+value: SurfaceTypes.Node, +context: Controls.Context) -> Bool:
  SurfaceTypes.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  specified_header_representation(Controls.represent(key, meaning, label, role, local))

def header_step(value: SurfaceTypes.Node, include: Bool, +tail: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match include:
    case True{}: value <> tail
    case False{}: tail

def body_step(value: SurfaceTypes.Node, include: Bool, +tail: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match include:
    case True{}: tail
    case False{}: value <> tail

def specified_header(values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      header_step(value, specified_header_child(value, context), specified_header(rest, context))

def specified_body(values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      body_step(value, specified_header_child(value, context), specified_body(rest, context))

def specified_parts(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> Order.DialogParts:
  Order.DialogParts{specified_header(values, context), specified_body(values, context)}

def specified_order(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  List.append(&2, SurfaceTypes.Node, specified_header(values, context), specified_body(values, context))

def specified_children(role: SurfaceTypes.Role, values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match role:
    case SurfaceTypes.Dialog{}:
      specified_order(values, context)
    case _: values

def non_dialog_order_observation(role: SurfaceTypes.Role, +values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match role:
    case SurfaceTypes.Dialog{}: values
    case _: Order.ordered_children(role, values, context)

def occurrence_step(included: Bool, rest: Nat) -> Nat:
  match included:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

def count_key(node: SurfaceTypes.Node) -> UIIdentity.Key:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  key

type CountPredicate is Data:
  CountAll{}
  CountKey{key: UIIdentity.Key}

def count_matches(predicate: CountPredicate, value: SurfaceTypes.Node) -> Bool:
  match predicate:
    case CountAll{}: True{}
    case CountKey{key}: String.eq(InterfaceView.node_key(value), UIIdentity.encode(key))

def count_by(+predicate: CountPredicate, values: +List<SurfaceTypes.Node>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{+value, rest}: occurrence_step(count_matches(predicate, value), count_by(predicate, rest))

type PresentationOrderRequirements is Type:
  PresentationOrderRequirements{
    non_dialog_order: @role:SurfaceTypes.Role -> @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {non_dialog_order_observation(role, values, context) == values : +List<SurfaceTypes.Node>},
    dialog_partition_specification: @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {Order.partition_dialog_children(values, context) == specified_parts(values, context) : Order.DialogParts},
    dialog_partition_length: @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {List.length(&2, SurfaceTypes.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        List.length(&2, SurfaceTypes.Node, values) : Nat},
    dialog_partition_occurrences: @target:SurfaceTypes.Node -> @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {count_by(CountKey{count_key(target)},
          Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        count_by(CountKey{count_key(target)}, values) : Nat},
    ordered_children_reference: @values:+List<SurfaceTypes.Node> -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<SurfaceTypes.Node>},
    dialog_order_idempotent: @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {Order.ordered_children(SurfaceTypes.Dialog{}, Order.ordered_children(SurfaceTypes.Dialog{}, values, context), context) ==
        Order.ordered_children(SurfaceTypes.Dialog{}, values, context) : +List<SurfaceTypes.Node>},
    node_payload_preserved: @value:SurfaceTypes.Node -> @children:+List<SurfaceTypes.Node> ->
      {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload},
    surface_content_scope_preserved: @surface:SurfaceTypes.Surface ->
      {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload},
    model_observes_ordered_surface: @+model_state:Model2.State ->  {Model2.observed_surface(model_state) ==
        Order.ordered_surface(Model2.surface(Model2.application(model_state))) : SurfaceTypes.Surface}
  }

law presentation_order_evidence:
  PresentationOrderRequirements

law base_classifier:
  for +key: UIIdentity.Key
  for +role: SurfaceTypes.Role
  {Order.base_region(key, role) == Order.base_region_navigation(Order.is_navigation(key, role), key, role) : Order.BaseRegion}

law navigation_role:
  for +key: UIIdentity.Key
  {Order.base_region(key, SurfaceTypes.Navigation{}) == Order.NavigationRegion{} : Order.BaseRegion}

law navigation_precedence:
  for +key: UIIdentity.Key
  for +role: SurfaceTypes.Role
  {Order.base_region_navigation(True{}, key, role) == Order.NavigationRegion{} : Order.BaseRegion}

law remaining_region:
  for +key: UIIdentity.Key
  for +role: SurfaceTypes.Role
  {Order.base_region_navigation(False{}, key, role) == Order.base_region_role(key, role) : Order.BaseRegion}

law main_precedence:
  for +key: UIIdentity.Key
  {Order.base_region_role(key, SurfaceTypes.Main{}) == Order.MainRegion{} : Order.BaseRegion}

law footer_region:
  {Order.footer_region(True{}) == Order.NavigationFooterRegion{} : Order.BaseRegion}

law other_region:
  {Order.footer_region(False{}) == Order.OtherRegion{} : Order.BaseRegion}

law base_partition_navigation:
  for +node: SurfaceTypes.Node
  for +navigation: +List<SurfaceTypes.Node>
  for +footer: +List<SurfaceTypes.Node>
  for +main: +List<SurfaceTypes.Node>
  for +other: +List<SurfaceTypes.Node>
  {Order.prepend_base(Order.NavigationRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{node <> navigation, footer, main, other} : Order.BaseParts}

law base_partition_footer:
  for +node: SurfaceTypes.Node
  for +navigation: +List<SurfaceTypes.Node>
  for +footer: +List<SurfaceTypes.Node>
  for +main: +List<SurfaceTypes.Node>
  for +other: +List<SurfaceTypes.Node>
  {Order.prepend_base(Order.NavigationFooterRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, node <> footer, main, other} : Order.BaseParts}

law base_partition_main:
  for +node: SurfaceTypes.Node
  for +navigation: +List<SurfaceTypes.Node>
  for +footer: +List<SurfaceTypes.Node>
  for +main: +List<SurfaceTypes.Node>
  for +other: +List<SurfaceTypes.Node>
  {Order.prepend_base(Order.MainRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, node <> main, other} : Order.BaseParts}

law base_partition_other:
  for +node: SurfaceTypes.Node
  for +navigation: +List<SurfaceTypes.Node>
  for +footer: +List<SurfaceTypes.Node>
  for +main: +List<SurfaceTypes.Node>
  for +other: +List<SurfaceTypes.Node>
  {Order.prepend_base(Order.OtherRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, main, node <> other} : Order.BaseParts}

law base_partition_empty:
  {Order.partition_base(Nil{}) == Order.BaseParts{Nil{}, Nil{}, Nil{}, Nil{}} : Order.BaseParts}

law base_partition_step:
  for +key: UIIdentity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +meaning: SurfaceTypes.Meaning
  for +children: +List<SurfaceTypes.Node>
  for +rest: +List<SurfaceTypes.Node>
  {Order.partition_base(SurfaceTypes.Node{key, semantic, label, role, meaning, children} <> rest) == Order.prepend_base(Order.base_region(key, role), SurfaceTypes.Node{key, semantic, label, role, meaning, children}, Order.partition_base(rest)) : Order.BaseParts}

law base_region_order:
  for +navigation: +List<SurfaceTypes.Node>
  for +footer: +List<SurfaceTypes.Node>
  for +main: +List<SurfaceTypes.Node>
  for +other: +List<SurfaceTypes.Node>
  {Order.flatten_base(Order.BaseParts{navigation, footer, main, other}) == List.append(&2, SurfaceTypes.Node, navigation, List.append(&2, SurfaceTypes.Node, footer, List.append(&2, SurfaceTypes.Node, main, other))) : +List<SurfaceTypes.Node>}

law ordered_base_partition:
  for +values: +List<SurfaceTypes.Node>
  {Order.ordered_base(values) == Order.flatten_base(Order.partition_base(values)) : +List<SurfaceTypes.Node>}

law ordered_surface_base:
  for +content: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  for +scope: Maybe<&2, String>
  {Order.ordered_surface(SurfaceTypes.Surface{content, base, overlays, scope}) == SurfaceTypes.Surface{content, Order.ordered_base(Order.ordered_nodes(base, Controls.initial(content))), Order.ordered_nodes(overlays, Controls.initial(content)), scope} : SurfaceTypes.Surface}

def non_main_role(role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.Main{}: False{}
    case _: True{}

law remaining_role_classification:
  for +key: UIIdentity.Key
  for +role: SurfaceTypes.Role
  for belongs: {non_main_role(role) == True{} : Bool}
  {Order.base_region_role(key, role) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}

def clear(faults: +List<Rendered.Violation>) -> Bool:
  match faults:
    case Nil{}: True{}
    case Con{fault, rest}: False{}

def realized_tag(state: Rendered.State) -> Bool:
  match state:
    case Rendered.Realized{generation, frame}: True{}
    case _: False{}

type Requirements is Type:
  Requirements{
    reflection: @+surface:SurfaceTypes.Surface -> @+frame:Rendered.Frame ->
      {clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool},
    realized_sound: @+current:Nat -> @+received:Nat -> @+surface:SurfaceTypes.Surface ->
      @+frame:Rendered.Frame -> @+previous:Rendered.State ->
      @owned:{Nat.is_eq(current, received) == True{} : Bool} ->
      @realized:{Rendered.observe(current, received, surface, frame, previous) == Rendered.Realized{current, frame} : Rendered.State} ->
      {Spec.valid(surface, frame) == True{} : Bool}
  }

law evidence:
  Requirements

law dialog_actions_region_geometry:
  for found: Maybe<&2, Rendered.Element>
  for viewport: Geometry.Rect
  {Spec.region_geometry_valid(SurfaceTypes.DialogActions{}, found, viewport) == Spec.bounded_region(found, viewport) : Bool}

law dialog_actions_children_visible:
  for inherited: Bool
  for found: Maybe<&2, Rendered.Element>
  for viewport: Geometry.Rect
  {Spec.child_persistent(inherited, SurfaceTypes.DialogActions{}, found, viewport) == True{} : Bool}
