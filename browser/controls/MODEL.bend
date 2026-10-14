import ../layout/ACTIVITY.bend as Activity
import ../layout/natural-size.bend as NaturalSize
import ./NAVIGATION.bend as Navigation
import ./SIDEBAR.bend as Sidebar
import ./navigation-proof.bend as NavigationProof
import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/experience/MODEL.bend as UXTypes
import ../../interaction/experience/ACTIVITY.bend as UXActivity
import ../layout/HIERARCHY.bend as Hierarchy
import ../../interaction/presentation/INFORMATION.bend as Information
import Base
import ../reading/MODEL.bend as ReadingBinding
import ../../interaction/IDENTITY.bend as UIIdentity
import ../document/SOURCE.bend as Source
import ../appearance/MODEL.bend as Appearance
import ./authored-primitives.bend as Factory
import ./CONTROLS.bend as AuthoredControls
import ./BUTTONS.bend as Buttons
import ./button-proof.bend as ButtonProof
import ./authored-proof.bend as AuthoredProof
import ../appearance/DESIGN.bend as Design
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T
import ./PROGRAM.bend as Controls
import ../document/MODEL.bend as Doc
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/submission/field-options.bend as FieldOptions
import ../../interaction/services/CONTEXT.bend as Context
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/INPUT.bend as User
import ../../interaction/session/MODEL.bend as Experience
import ../../interaction/conversation/MODEL.bend as Conversation
import ../../harness/DOMAIN.bend as Domain
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../features/board/MODEL.bend as Board
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/VIEW.bend as View2

type Problem is Data:
  InvalidDialogOrder{}
  OrphanCode{target: Source.NativeTarget}
  ConflictingCodeOwners{expected: Code.Source, actual: Code.Source}

type Authorship is Data:
  Authored{nodes: +List<Source.Node>}
  Rejected{key: UIIdentity.Key, problem: Problem}

# Child metadata survives authorship without retaining a second design tree.

type Child is Data:
  Child{key: UIIdentity.Key, role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning,
    control: Controls.Representation, nodes: +List<Source.Node>}

type Forest is Data:
  Ready{children: +List<Child>}
  Failed{key: UIIdentity.Key, problem: Problem}

def append(+left: +List<Source.Node>, +right: +List<Source.Node>) -> +List<Source.Node>:
  List.append(&2, Source.Node, left, right)

def all_nodes(+values: +List<Child>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}: append(nodes, all_nodes(rest))

def ordinary(+values: +List<Source.Node>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}: ordinary(rest)
    case Con{node, rest}: node <> ordinary(rest)

def native(+values: +List<Source.Node>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      Source.NativeAttachment{key, target, attributes, style, children} <> native(rest)
    case Con{node, rest}: native(rest)

def text(+key: UIIdentity.Key, +value: String, +visual: Design.Style, +tier: T.Tier, +emphasis: T.Emphasis) -> Source.Node:
  Source.constructed_text_node(Source.construct_text(Source.TextRequest{key, value, Source.ExplicitFont{T.inherit_activity(Design.style_text(visual), T.with_emphasis(T.with_tier(Design.style_text(visual), tier), emphasis))}, T.NormalAnywhere{}}))

def group(+key: UIIdentity.Key, +visual: Design.Style, +direction: Model.Direction, +width: Model.AxisSize,
  +height: Model.AxisSize, +children: +List<Source.Node>) -> Source.Node:
  Source.constructed_box_node(Source.construct_box(Source.BoxRequest{key, Source.Div{}, Factory.content_style(visual, direction, width, height, AuthoredControls.parent_gap(visual)), Nil{}, children}))

def role_tag(+role: SurfaceTypes.Role) -> Source.BoxTag:
  match role:
    case SurfaceTypes.Navigation{}: Source.Navigation{}
    case SurfaceTypes.NavigationHeader{}: Source.Header{}
    case SurfaceTypes.Main{}: Source.Main{}
    case SurfaceTypes.Heading{}: Source.Header{}
    case SurfaceTypes.Activity{}: Source.Section{}
    case SurfaceTypes.Dialog{}: Source.Section{}
    case SurfaceTypes.Card{}: Source.Article{}
    case SurfaceTypes.UserMessage{}: Source.Article{}
    case SurfaceTypes.AssistantMessage{}: Source.Article{}
    case _: Source.Div{}

def role_name(+value: SurfaceTypes.Role) -> String:
  match value:
    case SurfaceTypes.NavigationHeader{}: "navigation-header"
    case SurfaceTypes.Heading{}: "heading"
    case SurfaceTypes.Timeline{}: "timeline"
    case SurfaceTypes.Composer{}: "composer"
    case SurfaceTypes.ComposerActions{}: "composer-actions"
    case SurfaceTypes.DialogActions{}: "dialog-actions"
    case SurfaceTypes.ApprovalQueue{}: "approvals"
    case SurfaceTypes.UserMessage{}: "user-message"
    case SurfaceTypes.AssistantMessage{}: "agent-message"
    case SurfaceTypes.Activity{}: "activity"
    case SurfaceTypes.Navigation{}: "navigation"
    case SurfaceTypes.Main{}: "main"
    case SurfaceTypes.Section{}: "section"
    case _: "content"

def reading_attributes(+role: SurfaceTypes.Role, +key: UIIdentity.Key) -> +List<Source.Attribute>:
  match role:
    case SurfaceTypes.UserMessage{}: [Source.DataAttribute{"reading-key", UIIdentity.encode(key)}]
    case SurfaceTypes.AssistantMessage{}: [Source.DataAttribute{"reading-key", UIIdentity.encode(key)}]
    case SurfaceTypes.Activity{}: [Source.DataAttribute{"reading-key", UIIdentity.encode(key)}]
    case _: Nil{}

def attributes(+key: UIIdentity.Key, +semantic: String, +role: SurfaceTypes.Role) -> +List<Source.Attribute>:
  List.append(&2, Source.Attribute, [Source.DataAttribute{"native-key", UIIdentity.encode(key)}, Source.DataAttribute{"region", role_name(role)}, Source.DataAttribute{"semantic", semantic}], reading_attributes(role, key))

# Observation identity belongs to the source node receiving the decoration.

def native_attribute_value(+owned: Bool, +key: UIIdentity.Key, +name: String, +value: String) -> Source.Attribute:
  match owned:
    case True{}: Source.DataAttribute{"native-key", UIIdentity.encode(key)}
    case False{}: Source.DataAttribute{name, value}

def native_attribute(+key: UIIdentity.Key, +attribute: Source.Attribute) -> Source.Attribute:
  match attribute:
    case Source.DataAttribute{+name, value}: native_attribute_value(String.eq(name, "native-key"), key, name, value)
    case other: other

def native_attributes(+key: UIIdentity.Key, +extra: +List<Source.Attribute>) -> +List<Source.Attribute>:
  match extra:
    case Nil{}: Nil{}
    case Con{attribute, rest}: native_attribute(key, attribute) <> native_attributes(key, rest)

def add_attributes(+node: Source.Node, +extra: +List<Source.Attribute>) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, native_attributes(key, extra)), children}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: Source.Control{key, tag, style, List.append(&2, Source.Attribute, attrs, native_attributes(key, extra)), name, enabled, first, remaining, children}
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: Source.Field{key, kind, style, List.append(&2, Source.Attribute, attrs, native_attributes(key, extra)), value, placeholder, options, policy, name, enabled, first, remaining}
    case other: other

def role_style(+visual: Design.Style, +role: SurfaceTypes.Role) -> Source.Style:
  match role:
    case SurfaceTypes.Main{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case SurfaceTypes.Timeline{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case SurfaceTypes.Details{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case SurfaceTypes.UserMessage{}: Factory.style(visual, Factory.adaptive_natural_width(visual), Model.NaturalSize{}, Model.Confined{})
    case _: Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{})

def section_caption(+empty: Bool, +key: UIIdentity.Key, +label: String, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [Source.Box{UIIdentity.part(key, "@title"), Source.Heading2{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual)]}]

def caption(+key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +visual: Design.Style) -> +List<Source.Node>:
  match role:
    case SurfaceTypes.NavigationHeader{}: [Source.Box{UIIdentity.part(key, "@brand"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"navigation-brand", ""}], [text(UIIdentity.part(UIIdentity.part(key, "@brand"), "text"), label, visual, T.Section{}, T.Medium{})]}]
    case SurfaceTypes.Heading{}: [AuthoredControls.owned_text(key, Information.SurfaceTitle{}, label, visual)]
    case SurfaceTypes.Section{}:
      section_caption(String.is_empty(label), key, label, visual)
    case _: Nil{}

def box(+key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attrs: +List<Source.Attribute>, +children: +List<Source.Node>) -> Source.Node:
  Source.constructed_box_node(Source.construct_box(Source.BoxRequest{key, tag, style, attrs, children}))

def target_source(+target: Source.NativeTarget) -> Code.Source:
  match target:
    case Source.ToolbarTarget{Code.Identity{source, ordinal}}: source
    case Source.CodeBodyTarget{Code.Identity{source, ordinal}, wrap}: source

def owner_validation(+matches: Bool, +owner: UIIdentity.Key, +expected: Code.Source, +actual: Code.Source) -> Authorship:
  match matches:
    case True{}: Authored{Nil{}}
    case False{}: Rejected{owner, ConflictingCodeOwners{expected, actual}}

def target_validation(+source: Maybe<&2, Code.Source>, +owner: UIIdentity.Key, +key: UIIdentity.Key, +target: Source.NativeTarget) -> Authorship:
  match source:
    case None{}: Rejected{key, OrphanCode{target}}
    case Some{+expected}: owner_validation(String.eq(Code.source_key(expected), Code.source_key(target_source(target))), owner, expected, target_source(target))

def merge_validation(+first: Authorship, +rest: Authorship) -> Authorship:
  match first:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{unused}: rest

def check_owners(+values: +List<Source.Node>, +owner: UIIdentity.Key, +source: Maybe<&2, Code.Source>) -> Authorship:
  match values:
    case Nil{}: Authored{Nil{}}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      merge_validation(target_validation(source, owner, key, target), check_owners(rest, owner, source))
    case Con{other, rest}: check_owners(rest, owner, source)

def toolbar_reserve(+values: +List<Source.Node>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{Source.NativeAttachment{key, Source.ToolbarTarget{identity}, attributes, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}, children}, rest}: Nat.max(minimum_height, toolbar_reserve(rest))
    case Con{other, rest}: toolbar_reserve(rest)

def toolbar_preferred(+values: +List<Child>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{Child{key, role, meaning, Controls.Action{Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}}, nodes}, rest}: Nat.max(Controls.geometry_preferred_height(geometry), toolbar_preferred(rest))
    case Con{other, rest}: toolbar_preferred(rest)

def code_surface(+visual: Design.Style) -> Source.CodeSurface:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Source.CodeSurface{Design.style_frame(visual), chrome}

def rich_policy(+visual: Design.Style, +code_visual: Design.Style, +reserve: Nat) -> Source.RichPolicy:
  +body = T.resolved_size(T.resolved(Design.style_text(visual)))
  +code = T.with_tier(Design.style_text(visual), T.CodeBody{})
  Source.RichPolicy{code_surface(code_visual), reserve, body, Nat.mul(2n, body), code, False{}}

def rich_leaf(+key: UIIdentity.Key, +value: String, +visual: Design.Style, +code_visual: Design.Style, +source: Maybe<&2, Code.Source>, +attachments: +List<Source.Node>, +native_owner: Maybe<&2, String>) -> Source.Node:
  Source.RichText{key, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Source.RichContent{source, value, rich_policy(visual, code_visual, toolbar_reserve(attachments))}, attachments, native_owner}

def rich_checked(+result: Authorship, +key: UIIdentity.Key, +role: SurfaceTypes.Role, +value: String, +visual: Design.Style, +code_visual: Design.Style, +children: +List<Child>, +source: Maybe<&2, Code.Source>) -> Authorship:
  match result:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{unused}: Authored{[box(key, role_tag(role), role_style(visual, role), Nil{}, rich_leaf(UIIdentity.part(key, "markdown"), value, visual, code_visual, source, native(all_nodes(children)), Some{UIIdentity.encode(key)}) <> ordinary(all_nodes(children)))]}

def rich(+key: UIIdentity.Key, +role: SurfaceTypes.Role, +value: String, +visual: Design.Style, +code_visual: Design.Style, +children: +List<Child>, +source: Maybe<&2, Code.Source>) -> Authorship:
  rich_checked(check_owners(native(all_nodes(children)), key, source), key, role, value, visual, code_visual, children, source)

def code_toolbar(+toolbar: +List<Source.Node>, +key: UIIdentity.Key, +identity: Code.Identity, +visual: Design.Style, +preferred: Nat, +body: Source.Node, +remaining: +List<Source.Node>) -> +List<Source.Node>:
  match toolbar:
    case Nil{}: body <> remaining
    case Con{first, rest}:
      Source.NativeAttachment{UIIdentity.part(key, "toolbar"), Source.ToolbarTarget{identity}, Factory.binding_attributes(key), Factory.with_minimum(Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Extent{0n, preferred}), first <> rest} <> body <> remaining

def code_children(+key: UIIdentity.Key, +identity: Code.Identity, +wrap: Bool, +visual: Design.Style, +children: +List<Child>) -> +List<Source.Node>:
  +body_style = Factory.with_alignments(Factory.with_font(Factory.content_style(visual, Model.Vertical{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), Source.ExplicitFont{T.with_tier(Design.style_text(visual), T.CodeBody{})}), Spatial.Leading{}, Spatial.Leading{})
  code_toolbar(ordinary(all_nodes(children)), key, identity, visual, toolbar_preferred(children), Source.NativeAttachment{UIIdentity.part(key, "wrap"), Source.CodeBodyTarget{identity, wrap}, Nil{}, body_style, Nil{}}, native(all_nodes(children)))

def orphan(+values: +List<Source.Node>, +original: +List<Source.Node>) -> Authorship:
  match values:
    case Nil{}: Authored{original}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}: Rejected{key, OrphanCode{target}}
    case Con{other, rest}: orphan(rest, original)

def position_name(+value: Composition.Position) -> String:
  match value:
    case Composition.HeadingPosition{}: "heading"
    case Composition.BodyPosition{}: "body"
    case Composition.DockPosition{}: "dock"

def position_style(+visual: Design.Style, +position: Composition.Position) -> Source.Style:
  match position:
    case Composition.BodyPosition{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case _: Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{})

def region_style(+visual: Design.Style, region: Composition.Region, position: Composition.Position) -> Source.Style:
  match region:
    case Composition.ConversationTitle{}: Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{})
    case Composition.TaskActions{}:
      Factory.with_alignments(Factory.with_direction(
        Factory.with_frame(Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}),
          Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.InlineControls{}}}),
        Model.Horizontal{}), Spatial.Leading{}, Spatial.Centered{})
    case Composition.BoardControls{}:
      Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.ComposerControls{}}), Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Model.ResponsiveHorizontal{})
    case Composition.BoardStages{}:
      Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.BoardColumns{}}), Model.StretchSize{}, Model.StretchSize{}, Model.ScrollHorizontally{}), Model.Horizontal{})
    case _: position_style(visual, position)

def context_kind(+value: Context.Observation) -> String:
  match value:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.InheritedWorkspace{workspace}, Context.InheritedSandbox{sandbox}, Context.InheritedApproval{approval}, guidance}}: "inherited"
    case Context.DraftExecution{other}: "custom"
    case Context.CommittedExecution{context}: "committed"

def fact_display_choice(empty: Bool, value: String) -> String:
  match empty:
    case True{}: "—"
    case False{}: value

def fact_display_value(+value: String) -> String:
  fact_display_choice(String.eq(value, ""), value)

def fact(+key: UIIdentity.Key, +label: String, +value: String, +visual: Design.Style) -> Source.Node:
  group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [text(UIIdentity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), text(UIIdentity.part(key, "value"), fact_display_value(value), visual, T.Body{}, T.Regular{})])

def project_instructions(empty: Bool, instructions: String) -> String:
  match empty:
    case True{}: "No project instructions"
    case False{}: instructions

def project_context_facts(+owner: UIIdentity.Key, +label: String, +value: Domain.ProjectContext, +visual: Design.Style) -> +List<Source.Node>:
  match value:
    case Domain.NoProject{}: Nil{}
    case Domain.ProjectContext{directory, revision, instructions}:
      present: @body:String -> +List<Source.Node> = (body => [group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), fact(UIIdentity.part(owner, "instructions"), "Instructions", body, visual)])])
      present(project_instructions(String.eq(instructions, ""), instructions))

def tool_detail_nodes(+owner: UIIdentity.Key, +tools: +List<Domain.Tool>, +visual: Design.Style) -> +List<Source.Node>:
  match tools:
    case Nil{}: Nil{}
    case Con{Domain.Tool{name, description, schema, source}, rest}:
      fact(UIIdentity.entity(owner, "tool", name), name, description, visual) <> tool_detail_nodes(owner, rest, visual)

def ancestor_names(+lineage: +List<Nat>) -> +List<String>:
  List.foldr(&2, Nat, +List<String>, (ancestor => rest => Nat.show(ancestor) <> rest), lineage, Nil{})

def task_details(+owner: UIIdentity.Key, +value: View.TaskDetails, +visual: Design.Style) -> +List<Source.Node>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy, options}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  +task_project = project_context_facts(UIIdentity.part(owner, "@task-project"), "Task project context", guidance, visual)
  +model_project = project_context_facts(UIIdentity.part(owner, "@model-project"), "Model project context", model_guidance, visual)
  +tool_nodes = tool_detail_nodes(UIIdentity.part(owner, "@tools"), tools, visual)
  +ancestors = ancestor_names(lineage)
  [group(UIIdentity.part(owner, "@facts"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, append([fact(UIIdentity.part(owner, "@workspace"), "Working directories", FieldOptions.joined(roots), visual), fact(UIIdentity.part(owner, "@primary"), "Primary directory", FieldOptions.optional_text(primary), visual), fact(UIIdentity.part(owner, "@sandbox"), "Filesystem access", Context.filesystem_summary(access, mode), visual), fact(UIIdentity.part(owner, "@network"), "Network access", Context.network_summary(access, network), visual), fact(UIIdentity.part(owner, "@approval"), "Approval policy", Domain.approval_name(approval), visual), fact(UIIdentity.part(owner, "@model"), "Model", name, visual), fact(UIIdentity.part(owner, "@reasoning"), "Reasoning", reasoning, visual), fact(UIIdentity.part(owner, "@status"), "Status", Domain.status_name(status), visual), fact(UIIdentity.part(owner, "@phase"), "Phase", Tasks.phase_name(phase), visual), fact(UIIdentity.part(owner, "@messages"), "Queued messages", FieldOptions.joined(queued), visual), group(UIIdentity.part(owner, "@tools"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, text(UIIdentity.part(UIIdentity.part(owner, "@tools"), "title"), "Tools", visual, T.Body{}, T.Strong{}) <> tool_nodes), fact(UIIdentity.part(owner, "@lineage"), "Ancestor tasks", FieldOptions.joined(ancestors), visual)], append(task_project, model_project)))]

def audit_nodes(+values: +List<Conversation.AuditFace>, +key: UIIdentity.Key, +visual: Design.Style, +code_visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.AuditFace{+id, kind, title, source}, rest}:
      group(UIIdentity.part(key, "audit/" ++ Nat.show(id)), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [text(UIIdentity.part(key, "audit-title" ++ Nat.show(id)), title, visual, T.Body{}, T.Strong{}), rich_leaf(UIIdentity.part(key, "audit-body" ++ Nat.show(id)), Conversation.audit_detail(source), visual, code_visual, None{}, Nil{}, None{})]) <> audit_nodes(rest, key, visual, code_visual)

def disclosure(+control: Controls.Representation) -> Bool:
  match control:
    case Controls.Action{Controls.Button{InteractionTypes.ApplicationInput{Experience.UserInput{User.SetDisclosure{task, group, occurrence, expanded}}}, availability, name, face, behavior, geometry, placement, feedback}}: True{}
    case _: False{}

def activity_header_selected(+selected: Bool, +nodes: +List<Source.Node>, +rest: +List<Source.Node>) -> +List<Source.Node>:
  match selected:
    case True{}: append(ordinary(nodes), rest)
    case False{}: rest

def activity_header(+values: +List<Child>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      activity_header_selected(disclosure(control), nodes, activity_header(rest))

def activity_content_selected(+selected: Bool, +nodes: +List<Source.Node>, +rest: +List<Source.Node>) -> +List<Source.Node>:
  match selected:
    case True{}: rest
    case False{}: append(ordinary(nodes), rest)

def activity_content(+values: +List<Child>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      activity_content_selected(disclosure(control), nodes, activity_content(rest))

def activity_title(+key: UIIdentity.Key, +label: String, +visual: Design.Style, +values: +List<Source.Node>) -> +List<Source.Node>:
  match values:
    case Nil{}: [text(UIIdentity.part(key, "@summary"), label, visual, T.Body{}, T.Regular{})]
    case other: other

def expanded_content(+expanded: Bool, +children: +List<Source.Node>) -> +List<Source.Node>:
  match expanded:
    case True{}: children
    case False{}: Nil{}

def board_group_name(+value: SurfaceTypes.BoardGrouping) -> String:
  match value:
    case SurfaceTypes.ViewChoices{}: "view-choices"
    case SurfaceTypes.SearchArea{}: "search"
    case SurfaceTypes.WorkStatus{}: "work-status"
    case SurfaceTypes.SecondaryActions{}: "secondary-actions"
    case SurfaceTypes.PrimaryAction{}: "primary-action"

def board_group_label(+value: SurfaceTypes.BoardGrouping) -> String:
  match value:
    case SurfaceTypes.ViewChoices{}: "看板视图"
    case SurfaceTypes.SearchArea{}: "任务搜索"
    case SurfaceTypes.WorkStatus{}: "当前工作状态"
    case SurfaceTypes.SecondaryActions{}: "看板筛选和设置"
    case SurfaceTypes.PrimaryAction{}: "主要操作"

def lane_create(+stage: Board.Stage, +meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.NewCard{requested}}}}, availability}: String.eq(Board.stage_name(stage), Board.stage_name(requested))
    case _: False{}

def same_boolean(+expected: Bool, +actual: Bool) -> Bool:
  match expected:
    case True{}: actual
    case False{}: Bool.not(actual)

def lane_children_selected(+selected: Bool, +nodes: +List<Source.Node>, +rest: +List<Source.Node>) -> +List<Source.Node>:
  match selected:
    case True{}: append(ordinary(nodes), rest)
    case False{}: rest

def lane_children(+values: +List<Child>, +want: Bool, +stage: Board.Stage) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      lane_children_selected(same_boolean(want, lane_create(stage, meaning)), nodes, lane_children(rest, want, stage))

def empty_lane_present(+empty: Bool, +key: UIIdentity.Key, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: [box(UIIdentity.part(key, "@empty"), Source.Paragraph{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"board-empty", ""}], [text(UIIdentity.part(UIIdentity.part(key, "@empty"), "text"), "暂无任务", visual, T.Support{}, T.Regular{})])]
    case False{}: Nil{}

def empty_lane(+count: Nat, +key: UIIdentity.Key, +visual: Design.Style) -> +List<Source.Node>:
  empty_lane_present(Nat.is_eq(count, 0n), key, visual)

def scroll_content(+value: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, old_scroll, position}, font, chrome, states} = value
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, Model.ScrollVertically{}, position}, font, chrome, states}

def lane(+key: UIIdentity.Key, +label: String, +stage: Board.Stage, +count: Nat, +visual: Design.Style, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  Source.constructed_control_node(Source.construct_control(Source.ControlRequest{key, Source.SectionControl{}, Factory.with_direction(Factory.style(visual, Model.LimitedSize{Design.lane_minimum_width(parameters), 0n, Design.lane_minimum_width(parameters)}, Model.StretchSize{}, Model.Confined{}), Model.Vertical{}), [Source.DataAttribute{"board-stage", Board.stage_name(stage)}, Source.DataAttribute{"board-count", Nat.show(count)}], label, True{}, Doc.DropCard{UIIdentity.encode(key)}, Nil{},
    [box(UIIdentity.part(key, "@heading"), Source.Header{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.DataAttribute{"board-lane-heading", ""}],
      [group(UIIdentity.part(key, "@heading-leading"), visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, [box(UIIdentity.part(key, "@stage-mark"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"board-stage-mark", Board.stage_name(stage)}, Source.AriaAttribute{"hidden", "true"}], Nil{}), text(UIIdentity.part(key, "@title"), label, visual, T.Support{}, T.Medium{}), text(UIIdentity.part(key, "@count"), Nat.show(count), visual, T.Support{}, T.Regular{})]), group(UIIdentity.part(key, "@heading-trailing"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, lane_children(children, True{}, stage))]),
     box(UIIdentity.part(key, "@cards"), Source.Div{}, scroll_content(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.StretchSize{}, AuthoredControls.parent_gap(visual))), [Source.DataAttribute{"board-cards", ""}], append(empty_lane(count, key, visual), lane_children(children, False{}, stage)))]}))

def optional_text_present(+empty: Bool, +value: String, +key: UIIdentity.Key, +part: String, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [text(UIIdentity.part(key, "@" ++ part), value, visual, T.Support{}, T.Regular{})]

def optional_text(+value: String, +key: UIIdentity.Key, +part: String, +visual: Design.Style) -> +List<Source.Node>:
  optional_text_present(String.is_empty(value), value, key, part, visual)

def pinned(+found: Bool, +key: UIIdentity.Key, +visual: Design.Style) -> +List<Source.Node>:
  match found:
    case True{}: [text(UIIdentity.part(key, "@pinned"), "置顶", visual, T.Support{}, T.Regular{})]
    case False{}: Nil{}

def card_labels(+values: +List<String>, +key: UIIdentity.Key, +index: Nat, +visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: text(UIIdentity.part(key, "@label/" ++ Nat.show(index)), value, visual, T.Support{}, T.Regular{}) <> card_labels(rest, key, Nat.add(index, 1n), visual)

def more_action(+meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{object}, trigger}}}}, availability}: True{}
    case _: False{}

def card_actions_selected(+selected: Bool, +nodes: +List<Source.Node>, +rest: +List<Source.Node>) -> +List<Source.Node>:
  match selected:
    case True{}: append(ordinary(nodes), rest)
    case False{}: rest

def card_actions(+values: +List<Child>, +want: Bool) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      match meaning:
        case SurfaceTypes.MovableCard{destinations, face}: card_actions(rest, want)
        case _: card_actions_selected(same_boolean(want, more_action(meaning)), nodes, card_actions(rest, want))

def card_title(+key: UIIdentity.Key, +title: String, +visual: Design.Style, +actions: +List<Source.Node>) -> +List<Source.Node>:
  match actions:
    case Nil{}: [text(UIIdentity.part(key, "@title"), title, visual, T.Body{}, T.Strong{})]
    case other: other

def card_grip(+value: Controls.Representation, +key: UIIdentity.Key, +visual: Design.Style) -> +List<Source.Node>:
  match value:
    case Controls.Movable{Controls.MovableControl{destinations, face, name, handle, geometry}}: [AuthoredControls.glyph(UIIdentity.part(key, "@grip"), handle, visual, AuthoredControls.face_icon_size(geometry))]
    case _: Nil{}

def card_movement_nodes(values: +List<Child>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, SurfaceTypes.MovableCard{destinations, face}, control, nodes}, rest}: nodes
    case Con{other, rest}: card_movement_nodes(rest)

def card_movement_control(values: +List<Child>) -> Controls.Representation:
  match values:
    case Nil{}: Controls.NoControl{}
    case Con{Child{key, role, SurfaceTypes.MovableCard{destinations, face}, control, nodes}, rest}: control
    case Con{other, rest}: card_movement_control(rest)

def card_movement_available(values: +List<Child>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Child{key, role, SurfaceTypes.MovableCard{destinations, face}, control, nodes}, rest}: InterfaceView.has_available_destination(destinations)
    case Con{other, rest}: card_movement_available(rest)

def card(+key: UIIdentity.Key, +face: View.CardFace, +visual: Design.Style, +children: +List<Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> Source.Node:
  View.CardFace{+id, +title, description, priority, pinned_value, +status, project, labels, owner, updated} = face
  Source.constructed_control_node(Source.construct_control(Source.ControlRequest{key, Source.ArticleControl{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.DataAttribute{"card-id", Nat.show(id)}, Source.DataAttribute{"card-title", title}, Source.DraggableAttribute{FieldOptions.boolean(movable)}], title, movable, Doc.DragCard{UIIdentity.encode(key)}, [Doc.DropCard{UIIdentity.encode(key)}],
    append(append(card_grip(representation, key, visual), [group(UIIdentity.part(key, "@metadata"), visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, append([text(UIIdentity.part(key, "@reference"), Board.identifier(id), visual, T.Support{}, T.Regular{}), text(UIIdentity.part(key, "@priority"), Board.priority_label(priority), visual, T.Support{}, T.Regular{})], append(pinned(pinned_value, key, visual), optional_text(status, key, "status", visual)))),
      group(UIIdentity.part(key, "@actions"), visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, [group(UIIdentity.part(key, "@open"), visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, card_title(key, title, visual, card_actions(children, False{}))), group(UIIdentity.part(key, "@more"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, card_actions(children, True{}))])]),
      append(optional_text(description, key, "description", visual), append([group(UIIdentity.part(key, "@context"), visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, append(optional_text(project, key, "project", visual), card_labels(labels, key, 0n, visual)))], [group(UIIdentity.part(key, "@movement"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, card_movement_nodes(children)), box(UIIdentity.part(key, "@footer"), Source.Footer{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.DataAttribute{"card-footer", ""}], append(optional_text(owner, key, "owner", visual), optional_text(updated, key, "updated", visual)))])))}))

def task_status_size() -> Nat:
  16n

def task_status_indicator(+key: UIIdentity.Key, +status: View.TaskStatus, +visual: Design.Style) -> Source.Node:
  +caption = View2.task_status_label(status)
  box(key, Source.Span{}, Factory.glyph_style(visual, task_status_size(), task_status_size()),
    [Source.DataAttribute{"native-key", UIIdentity.encode(key)}, Source.RoleAttribute{"img"}, Source.AriaAttribute{"label", caption}, Source.TitleAttribute{caption}],
    [AuthoredControls.glyph(UIIdentity.part(key, "indicator"), Controls.task_status_glyph(status), visual, task_status_size())])

def task_children(+values: +List<Child>, +status: View.TaskStatus, +visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{+key, role, meaning, control, nodes}, rest}:
      match control:
        case Controls.Action{Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}}: append(ordinary(nodes), task_children(rest, status, visual))
        case _: task_status_indicator(key, status, visual) <> task_children(rest, status, visual)

def compound(+key: UIIdentity.Key, +label: String, +field: Forms.Field, +visual: Design.Style, +children: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.AriaAttribute{"labelledby", UIIdentity.encode(AuthoredControls.information_key(key, Information.FieldLabel{}))}, Source.DataAttribute{"field", Forms.key(field)}, Source.TabIndexAttribute{"-1"}], AuthoredControls.owned_text(key, Information.FieldLabel{}, label, visual) <> children)

def compound_owned(key: UIIdentity.Key, label: String, +field: Forms.Field, visual: Design.Style, children: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"field", Forms.key(field)}, Source.TabIndexAttribute{"-1"}], children)

def compound_directory(field: Forms.Field, value: Forms.Observed, key: UIIdentity.Key, label: String, visual: Design.Style, children: +List<Source.Node>) -> Source.Node:
  match field value:
    case Forms.WorkspaceDirectories{} Forms.WorkspaceValue{workspace}: compound_owned(key, label, field, visual, children)
    case Forms.WorkspaceDirectories{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: compound_owned(key, label, field, visual, children)
    case _ _: compound(key, label, field, visual, children)

def chooser_selection(+value: Maybe<&2, Nat>) -> +List<Source.Attribute>:
  match value:
    case None{}: Nil{}
    case Some{selected}: [Source.DataAttribute{"selected-project", Nat.show(selected)}]

def button_source(+key: UIIdentity.Key, +visual: Design.Style, representation: Controls.Representation) -> Source.Node:
  match representation:
    case Controls.Action{button}: Buttons.constructed_node(Buttons.construct(key, visual, button))
    case _: AuthoredControls.invalid(key, visual, "invalid-action-representation")

def movable_source(key: UIIdentity.Key, representation: Controls.Representation, visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Movable{control}: AuthoredControls.constructed_movable_node(AuthoredControls.construct_movable(key, control, visual, parameters))
    case _: AuthoredControls.invalid(key, visual, "invalid-movable-representation")

def input_source(key: UIIdentity.Key, representation: Controls.Representation, visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Input{input}: AuthoredControls.constructed_input_node(AuthoredControls.construct_input(key, input, visual, parameters))
    case _: AuthoredControls.invalid(key, visual, "invalid-input-representation")

def input_style_width(style: Source.Style) -> Model.AxisSize:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  width

def input_node_width(node: Source.Node) -> Model.AxisSize:
  match node:
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}: input_style_width(style)
    case Source.Box{key, tag, style, attributes, children}: input_style_width(style)
    case _: Model.StretchSize{}

def supported_input_source(capacity: Nat, +key: UIIdentity.Key, +native: Source.Node, +visual: Design.Style, first: Source.Node, rest: +List<Source.Node>) -> Source.Node:
  box(UIIdentity.part(key, "@input-support"), Source.Div{},
    Factory.content_style(visual, Model.Vertical{}, input_node_width(native), Model.NaturalSize{}, Hierarchy.member_gap(Hierarchy.for_text(capacity, Design.style_text(visual)))),
    Nil{}, native <> first <> rest)

def input_support_content(capacity: Nat, content: +List<Source.Node>, +key: UIIdentity.Key, representation: Controls.Representation, +visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match content:
    case Nil{}: input_source(key, representation, visual, parameters)
    case Con{first, rest}: supported_input_source(capacity, key, input_source(key, representation, visual, parameters), visual, first, rest)

def input_with_support(capacity: Nat, +key: UIIdentity.Key, +representation: Controls.Representation, visual: Design.Style, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Source.Node:
  match representation:
    case Controls.Input{input}: input_support_content(capacity, content, key, representation, visual, parameters)
    case _: input_source(key, representation, visual, parameters)

def layer_title(role: SurfaceTypes.Role, key: UIIdentity.Key, label: String, visual: Design.Style, content: +List<Source.Node>) -> +List<Source.Node>:
  match role:
    case SurfaceTypes.Dialog{}: content
    case _: AuthoredControls.owned_text(key, Information.SurfaceTitle{}, label, visual) <> content

def subject_attributes(+subject: UXTypes.Subject) -> +List<Source.Attribute>:
  UXTypes.Subject{editor, field} = subject
  [Source.DataAttribute{"property", UX.subject_key(subject)}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(subject))}, Source.DataAttribute{"field", Forms.key(field)}]

def owned_members(+capacity: Nat, +key: UIIdentity.Key, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  box(UIIdentity.part(key, "@members"), Source.Div{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.member_frame(Hierarchy.for_text(capacity, Design.style_text(visual)))), Nil{}, content)

def owned_group(+capacity: Nat, +key: UIIdentity.Key, label: String, +visual: Design.Style, attributes: +List<Source.Attribute>, content: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.heading_frame(Hierarchy.for_text(capacity, Design.style_text(visual)))), Source.AriaAttribute{"labelledby", UIIdentity.encode(AuthoredControls.information_key(key, Information.GroupTitle{}))} <> attributes,
    [AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual), owned_members(capacity, key, visual, content)])

def decision_group(+capacity: Nat, key: UIIdentity.Key, +decision: UXTypes.Decision, visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  owned_group(capacity, key, UX.decision_question(decision), visual, Source.RoleAttribute{"radiogroup"} <> subject_attributes(UX.decision_subject(decision)), content)

def object_group(+capacity: Nat, +key: UIIdentity.Key, object: UXTypes.Object, label: String, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.heading_frame(Hierarchy.for_text(capacity, Design.style_text(visual)))), [Source.AriaAttribute{"labelledby", UIIdentity.encode(AuthoredControls.information_key(key, Information.GroupTitle{}))}, Source.DataAttribute{"object-owner", UX.object_key(object)}],
    [AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual), box(UIIdentity.part(key, "@members"), Source.Div{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.grouped_frame(Hierarchy.for_text(capacity, Design.style_text(visual)), Enclosure.frame_content(Hierarchy.member_frame(Hierarchy.for_text(capacity, Design.style_text(visual)))))), Nil{}, content)])

def collection_subject(collection: UXTypes.Collection) -> UXTypes.Subject:
  UXTypes.Subject{UX.collection_editor(collection), Forms.WorkspaceDirectories{}}

def workspace_collection(+capacity: Nat, key: UIIdentity.Key, +collection: UXTypes.Collection, label: String, visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  owned_group(capacity, key, label, visual, Source.TabIndexAttribute{"-1"} <> subject_attributes(collection_subject(collection)), content)

def workspace_member(+key: UIIdentity.Key, +collection: UXTypes.Collection, +path: String, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  box(key, Source.Div{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    List.append(&2, Source.Attribute, subject_attributes(collection_subject(collection)), [Source.AriaAttribute{"label", path}, Source.DataAttribute{"member", path}, Source.DataAttribute{"reference-property", UX.subject_key(UXTypes.Subject{UX.collection_editor(collection), Forms.WorkspacePrimary{}})}, Source.DataAttribute{"primary", FieldOptions.boolean(UX.is_primary(collection, path))}]),
    [box(UIIdentity.part(key, "path"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.TitleAttribute{path}], [text(UIIdentity.part(UIIdentity.part(key, "path"), "text"), path, visual, T.Body{}, T.Regular{})]), group(UIIdentity.part(key, "controls"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, content)])

def action_unit(key: UIIdentity.Key, +action: UXTypes.ActionUnit, visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    List.append(&2, Source.Attribute, [Source.DataAttribute{"action-owner", UX.action_key(UX.identity(action))}], List.append(&2, Source.Attribute, subject_attributes(UX.content_subject(action)), AuthoredControls.focus_attributes(AuthoredControls.AggregateFocus{}))), content)

def assessment_subject(field: Maybe<&2, UXTypes.Subject>) -> +List<Source.Attribute>:
  match field:
    case None{}: Nil{}
    case Some{subject}: subject_attributes(subject)

def explanation_visible(blocked: Bool, +key: UIIdentity.Key, +assessment: UXTypes.Assessment, +visual: Design.Style) -> Source.Node:
  match blocked:
    case False{}: box(key, Source.Span{}, Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}), Nil{}, Nil{})
    case True{}: box(key, Source.Div{}, role_style(visual, SurfaceTypes.Content{}), List.append(&2, Source.Attribute, [Source.DataAttribute{"action-owner", UX.action_key(UX.assessment_identity(assessment))}, Source.TitleAttribute{Controls.assessment_help(UX.assessment_obstructions(assessment))}], assessment_subject(UX.assessment_field(assessment))), [text(UIIdentity.part(key, "reason"), UX.assessment_reason(assessment), visual, T.Support{}, T.Regular{})])

def action_explanation(key: UIIdentity.Key, +assessment: UXTypes.Assessment, +visual: Design.Style) -> Source.Node:
  explanation_visible(Bool.not(String.eq(UX.assessment_reason(assessment), "")), key, assessment, visual)

def support_property_keys(subjects: +List<UXTypes.Subject>) -> String:
  match subjects:
    case Nil{}: ""
    case Con{subject, Nil{}}: UX.subject_key(subject)
    case Con{subject, rest}: UX.subject_key(subject) ++ "|" ++ support_property_keys(rest)

def support_properties(subjects: +List<UXTypes.Subject>) -> +List<Source.Attribute>:
  [Source.DataAttribute{"support-properties", support_property_keys(subjects)}]

def supporting_control_visible(visible: Bool, key: UIIdentity.Key, +support: UXTypes.Support, +property: UXTypes.Property, label: String, visual: Design.Style, representation: Controls.Representation) -> Source.Node:
  match visible:
    case False{}: box(key, Source.Span{}, Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.DataAttribute{"action-owner", UX.action_key(UX.support_identity(support))}], Nil{})
    case True{}: add_attributes(button_source(key, visual, representation), List.append(&2, Source.Attribute, [Source.DataAttribute{"action-owner", UX.action_key(UX.support_identity(support))}, Source.TitleAttribute{UX.property_help(property)}], List.append(&2, Source.Attribute, support_properties(UX.support_subjects(support)), [Source.DataAttribute{"object-owner", UX.object_key(UX.property_owner(property))}, Source.DataAttribute{"source-owner", UX.property_source_key(property)}])))

def supporting_control(key: UIIdentity.Key, +support: UXTypes.Support, +property: UXTypes.Property, label: String, visual: Design.Style, representation: Controls.Representation) -> Source.Node:
  supporting_control_visible(UX.support_visible(support), key, support, property, label, visual, representation)

def action_feedback(+key: UIIdentity.Key, feedback: UXTypes.Feedback, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  UXTypes.Feedback{+editor, +revision, +reason} = feedback
  box(key, Source.Div{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.RoleAttribute{"alert"}, Source.DataAttribute{"action-owner", UX.action_key(UXTypes.ActionIdentity{editor, revision})}, Source.DataAttribute{"action-revision", Nat.show(revision)}, Source.DataAttribute{"action-reason", reason}], text(UIIdentity.part(key, "text"), reason, visual, T.Body{}, T.Regular{}) <> content)

def grouped_children(values: +List<Child>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      match meaning:
        case SurfaceTypes.DecisionGroup{decision}: True{}
        case SurfaceTypes.ObjectGroup{object}: True{}
        case SurfaceTypes.WorkspaceCollection{collection}: True{}
        case _: grouped_children(rest)

def layer_attributes_found(found: Maybe<&2, SurfaceTypes.LayerBehavior>, +key: UIIdentity.Key) -> +List<Source.Attribute>:
  match found:
    case None{}: Nil{}
    case Some{SurfaceTypes.LayerBehavior{dismiss, outside, escape}}:
      [Source.AriaAttribute{"labelledby", UIIdentity.encode(AuthoredControls.information_key(key, Information.SurfaceTitle{}))}, Source.DataAttribute{"layer-key", UIIdentity.encode(key)}, Source.DataAttribute{"layer-outside", FieldOptions.boolean(outside)}, Source.DataAttribute{"layer-escape", FieldOptions.boolean(escape)}, Source.TabIndexAttribute{"-1"}]

def layer_attributes(+key: UIIdentity.Key, meaning: SurfaceTypes.Meaning) -> +List<Source.Attribute>:
  layer_attributes_found(SurfaceTypes.layer_region(meaning), key)

def activity_group(+capacity: Nat, +key: UIIdentity.Key, label: String, +role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning, activity: UXActivity.Activity, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  box(key, role_tag(role), Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    Hierarchy.grouped_frame(Hierarchy.for_text(capacity, Design.style_text(visual)), Enclosure.ambient(Activity.length(capacity, Design.style_text(visual), 8n), Activity.length(capacity, Design.style_text(visual), 8n)))),
    List.append(&2, Source.Attribute, layer_attributes(key, meaning), [Source.DataAttribute{"activity-owner", UX.object_key(UXActivity.object(activity))}]), layer_title(role, key, label, visual, content))

def grouped_menu_visible(+capacity: Nat, role: SurfaceTypes.Role, grouped: Bool, node: Source.Node) -> Source.Node:
  match role grouped node:
    case SurfaceTypes.Menu{} True{} Source.Box{key, tag, +style, attributes, nodes}:
      Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
      Source.Box{key, tag, Factory.with_frame(style, Hierarchy.grouped_frame(Hierarchy.for_text(capacity, Source.resolve_font(font, T.Presentation{T.Body{}, T.Regular{}, T.Scale{0n}})), Enclosure.frame_content(frame))), attributes, nodes}
    case _ _ other: other

def grouped_menu(+capacity: Nat, role: SurfaceTypes.Role, children: +List<Child>, node: Source.Node) -> Source.Node:
  grouped_menu_visible(capacity, role, grouped_children(children), node)

def regular_content(capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> Source.Node:
  match meaning:
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: activity_group(capacity, key, label, role, meaning, activity, visual, content)
    case SurfaceTypes.DecisionGroup{decision}: decision_group(capacity, key, decision, visual, content)
    case SurfaceTypes.ObjectGroup{object}: object_group(capacity, key, object, label, visual, content)
    case SurfaceTypes.WorkspaceCollection{collection}: workspace_collection(capacity, key, collection, label, visual, content)
    case SurfaceTypes.WorkspaceMember{collection, path}: workspace_member(key, collection, path, visual, content)
    case SurfaceTypes.ActionUnit{action}: action_unit(key, action, visual, content)
    case SurfaceTypes.SupportingControl{support, property, input, availability}: supporting_control(key, support, property, label, visual, representation)
    case SurfaceTypes.ActionCommit{assessment, input, availability}: add_attributes(button_source(key, visual, representation), [Source.DataAttribute{"action-owner", UX.action_key(UX.assessment_identity(assessment))}, Source.TitleAttribute{Controls.assessment_help(UX.assessment_obstructions(assessment))}])
    case SurfaceTypes.ActionExplanation{assessment}: action_explanation(key, assessment, visual)
    case SurfaceTypes.ActionFeedback{feedback}: action_feedback(key, feedback, visual, content)
    case SurfaceTypes.Edit{+editor, +field, Forms.DirectoryCollection{}, value, choices}: add_attributes(compound_directory(field, value, key, label, visual, content), [Source.DataAttribute{"property", UX.subject_key(UXTypes.Subject{editor, field})}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(UXTypes.Subject{editor, field}))}])
    case SurfaceTypes.Edit{editor, field, Forms.FileCollection{}, value, choices}: compound(key, label, field, visual, content)
    case SurfaceTypes.PanelToggle{expanded, input, availability}: button_source(key, visual, representation)
    case SurfaceTypes.Activate{input, availability}: button_source(key, visual, representation)
    case SurfaceTypes.Choice{kind, icon, selected, description, input, availability}: button_source(key, visual, representation)
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: box(key, Source.Div{}, role_style(visual, role), [Source.DataAttribute{"project", Nat.show(project)}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}, Source.DataAttribute{"expanded", FieldOptions.boolean(expanded)}], content)
    case SurfaceTypes.TaskRow{task, status, selected}: box(key, Source.Div{}, role_style(visual, role), [Source.DataAttribute{"task", Nat.show(task)}, Source.DataAttribute{"status", View2.task_status_label(status)}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}], task_children(children, status, visual))
    case SurfaceTypes.ProjectChooser{selected}: box(key, Source.Div{}, Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}), chooser_selection(selected), content)
    case SurfaceTypes.DirectoryRow{path, primary}: box(key, Source.Div{}, role_style(visual, role), [Source.AriaAttribute{"label", path}, Source.DataAttribute{"primary", FieldOptions.boolean(primary)}], [box(UIIdentity.part(key, "path"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.TitleAttribute{path}], [text(UIIdentity.part(UIIdentity.part(key, "path"), "text"), path, visual, T.Body{}, T.Regular{})]), group(UIIdentity.part(key, "controls"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, content)])
    case SurfaceTypes.ContextSummary{observation}: box(key, Source.Div{}, role_style(visual, role), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"context-kind", context_kind(observation)}], text(UIIdentity.part(key, "provenance"), label, visual, T.Support{}, T.Regular{}) <> content)
    case SurfaceTypes.ChoiceGroup{}: box(key, Source.Section{}, role_style(visual, role), [Source.RoleAttribute{"radiogroup"}, Source.AriaAttribute{"labelledby", UIIdentity.encode(AuthoredControls.information_key(key, Information.GroupTitle{}))}], AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual) <> content)
    case SurfaceTypes.PageRegion{region, position}: box(key, Source.Div{}, region_style(visual, region, position), [Source.DataAttribute{"page-position", position_name(position)}, Source.DataAttribute{"page-region", Composition.region_name(region)}], content)
    case SurfaceTypes.BoardGroup{grouping}: box(key, Source.Div{}, Factory.with_direction(Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.Confined{}), Model.Horizontal{}), [Source.DataAttribute{"board-group", board_group_name(grouping)}, Source.AriaAttribute{"label", board_group_label(grouping)}], content)
    case SurfaceTypes.BoardLane{stage, count}: lane(key, label, stage, count, visual, children, parameters)
    case SurfaceTypes.CardArchive{count}: Source.constructed_control_node(Source.construct_control(Source.ControlRequest{key, Source.DivControl{}, role_style(visual, role), [Source.DataAttribute{"card-archive", Nat.show(count)}], label, True{}, Doc.DropCard{UIIdentity.encode(key)}, Nil{}, content}))
    case SurfaceTypes.CardContent{face}: card(key, face, visual, children, card_movement_control(children), parameters, card_movement_available(children))
    case SurfaceTypes.MovableCard{destinations, face}: movable_source(key, representation, visual, parameters)
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: box(key, role_tag(role), role_style(visual, role), layer_attributes(key, meaning), layer_title(role, key, label, visual, content))
    case SurfaceTypes.ActivityContent{expanded, audit}: box(key, Source.Section{}, role_style(visual, role), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"expanded", FieldOptions.boolean(expanded)}], append(activity_title(key, label, visual, activity_header(children)), expanded_content(expanded, append(activity_content(children), audit_nodes(audit, key, visual, Appearance.style(SurfaceTypes.CodeBlock{}, SurfaceTypes.ActivityContent{expanded, audit}, Design.style_text(visual)))))))
    case SurfaceTypes.TaskFacts{details}: box(key, Source.Section{}, role_style(visual, role), Nil{}, append(task_details(key, details, visual), content))
    case SurfaceTypes.Fact{value}: fact(key, label, value, visual)
    case SurfaceTypes.InformationText{text_role}: box(key, role_tag(role), role_style(visual, role), Nil{}, [AuthoredControls.owned_text(key, text_role, label, visual)])
    case SurfaceTypes.ReadOnly{value}: box(key, Source.Div{}, role_style(visual, role), [Source.RoleAttribute{"alert"}, Source.AriaAttribute{"label", label}], text(UIIdentity.part(key, "text"), value, visual, T.Body{}, T.Regular{}) <> content)
    case SurfaceTypes.PageContext{conversation}: box(key, role_tag(role), role_style(visual, role), [Source.AriaAttribute{"label", label}], append(caption(key, label, role, visual), content))
    case SurfaceTypes.Region{}: box(key, role_tag(role), role_style(visual, role), [Source.AriaAttribute{"label", label}], append(caption(key, label, role, visual), content))
    case other: input_with_support(capacity, key, representation, visual, parameters, content)

def dialog_operation(+role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.DialogActions{}: True{}
    case _: False{}

def dialog_only_actions(+children: +List<Child>) -> Bool:
  match children:
    case Nil{}: True{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      dialog_operation(role) && dialog_only_actions(rest)

def dialog_ordered_tail(operation: Bool, only_actions: Unit -> Bool, ordered: Unit -> Bool) -> Bool:
  match operation:
    case True{}: only_actions(Unit{})
    case False{}: ordered(Unit{})

# A declared action region cannot precede content in a dialog.

def dialog_ordered(+children: +List<Child>) -> Bool:
  match children:
    case Nil{}: True{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      dialog_ordered_tail(dialog_operation(role), unit => dialog_only_actions(rest), unit => dialog_ordered(rest))

# Only a contiguous operation suffix belongs in the footer; earlier controls
# stay beside the content that followed them in the semantic reading sequence.

type DialogParts is Data:
  TrailingActions{actions: +List<Source.Node>}
  BodyAndActions{body: +List<Source.Node>, actions: +List<Source.Node>}

def dialog_prepend_trailing(+operation: Bool, +nodes: +List<Source.Node>, +actions: +List<Source.Node>) -> DialogParts:
  match operation:
    case True{}: TrailingActions{append(ordinary(nodes), actions)}
    case False{}: BodyAndActions{ordinary(nodes), actions}

def dialog_prepend(+operation: Bool, +nodes: +List<Source.Node>, +parts: DialogParts) -> DialogParts:
  match parts:
    case TrailingActions{actions}: dialog_prepend_trailing(operation, nodes, actions)
    case BodyAndActions{body, actions}:
      BodyAndActions{append(ordinary(nodes), body), actions}

def dialog_parts(+children: +List<Child>) -> DialogParts:
  match children:
    case Nil{}: TrailingActions{Nil{}}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      dialog_prepend(dialog_operation(role), nodes, dialog_parts(rest))

def dialog_part_body(+parts: DialogParts) -> +List<Source.Node>:
  match parts:
    case TrailingActions{actions}: Nil{}
    case BodyAndActions{body, actions}: body

def dialog_part_actions(+parts: DialogParts) -> +List<Source.Node>:
  match parts:
    case TrailingActions{actions}: actions
    case BodyAndActions{body, actions}: actions

def dialog_body(+children: +List<Child>) -> +List<Source.Node>:
  dialog_part_body(dialog_parts(children))

def dialog_actions(+children: +List<Child>) -> +List<Source.Node>:
  dialog_part_actions(dialog_parts(children))

def dialog_partition_style(part: Enclosure.Part, value: Source.Style) -> Source.Style:
  match part:
    case Enclosure.Body{}:
      Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = value
      Source.Style{Source.Layout{direction, main, cross, frame, width, Model.StretchSize{}, minimum, Model.ScrollVertically{}, position}, font, chrome, states}
    case _: value

def dialog_partition_frame_when(+capacity: Nat, enabled: Bool, visual: Design.Style, part: Enclosure.Part, arrangement: Enclosure.Arrangement) -> Enclosure.Frame:
  match enabled:
    case False{}: Enclosure.Frame{Enclosure.partition(part), arrangement}
    case True{}: Hierarchy.grouped_frame(Hierarchy.for_text(capacity, Design.style_text(visual)), Enclosure.ambient(0n, 0n))

def dialog_partition_frame(+capacity: Nat, +visual: Design.Style, part: Enclosure.Part, arrangement: Enclosure.Arrangement) -> Enclosure.Frame:
  dialog_partition_frame_when(capacity, T.is_activity(Design.style_text(visual)), visual, part, arrangement)

def dialog_partition(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> Source.Node:
  +style = Factory.with_frame(Factory.content_style(visual, direction, Model.StretchSize{}, Model.NaturalSize{}, 0n), dialog_partition_frame(capacity, visual, part, arrangement))
  box(key, tag, dialog_partition_style(part, style), Nil{}, content)

def dialog_optional(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> +List<Source.Node>:
  match content:
    case Nil{}: Nil{}
    case values: [dialog_partition(capacity, key, tag, visual, direction, part, arrangement, values)]

def dialog_content(+capacity: Nat, +key: UIIdentity.Key, +label: String, +visual: Design.Style, +children: +List<Child>) -> +List<Source.Node>:
  +parts = dialog_parts(children)
  dialog_partition(capacity, UIIdentity.part(key, "@dialog-header"), Source.Header{}, visual, Model.Vertical{}, Enclosure.Header{}, Enclosure.EmbeddedContent{0n},
    [box(UIIdentity.part(key, "@title"), Source.Heading2{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [AuthoredControls.owned_text(key, Information.SurfaceTitle{}, label, visual)])]) <>
  append(dialog_optional(capacity, UIIdentity.part(key, "@dialog-body"), Source.Div{}, visual, Model.Vertical{}, Enclosure.Body{}, Enclosure.SeparateFrames{Enclosure.DialogSections{}}, dialog_part_body(parts)),
    dialog_optional(capacity, UIIdentity.part(key, "@dialog-footer"), Source.Footer{}, visual, Model.ResponsiveHorizontal{}, Enclosure.Footer{}, Enclosure.SeparateFrames{Enclosure.DialogActions{}}, dialog_part_actions(parts)))

# Only the composer aggregate delegates its focus appearance to message fields.
def composer_focus(role: SurfaceTypes.Role, node: Source.Node) -> Source.Node:
  match role node:
    case SurfaceTypes.Composer{} Source.Box{key, tag, style, attributes, children}:
      Source.Box{key, tag, style, List.append(&2, Source.Attribute, attributes, AuthoredControls.focus_attributes(AuthoredControls.AggregateFocus{})), children}
    case _ other: other

def meaning_focus(meaning: SurfaceTypes.Meaning, role: SurfaceTypes.Role, node: Source.Node) -> Source.Node:
  match meaning:
    case SurfaceTypes.ActionUnit{action}: node
    case _: composer_focus(role, node)

def navigation_exposure(visible: Bool) -> Source.Exposure:
  match visible:
    case True{}: Source.Exposed{}
    case False{}: Source.Concealed{}



def sidebar_entry(+key: UIIdentity.Key, +owner: UIIdentity.Key, +depth: Nat, +visual: Design.Style, +entry: Sidebar.Entry) -> Source.Node:
  Sidebar.constructed_node(Sidebar.construct(key, owner, depth, visual, entry))

def navigation_project_commands(+key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, visible:Bool, +visual:Design.Style, toggled:Maybe<&2, Sidebar.Command>, opened:Maybe<&2, Sidebar.Command>, created:Maybe<&2, Sidebar.Command>, mored:Maybe<&2, Sidebar.Command>, fallback:+List<Source.Node>) -> Source.Node:
  match toggled opened created mored:
    case Some{toggle} Some{open} Some{create} Some{more}: sidebar_entry(key, owner, depth, visual, Sidebar.ProjectActions{toggle, open, create, more, visible})
    case _ _ _ _: box(key, Source.Div{}, role_style(visual, SurfaceTypes.Section{}), Nil{}, fallback)

def navigation_project_header(+key: UIIdentity.Key, +owner: UIIdentity.Key, +depth: Nat, visible: Bool, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  match content:
    case Con{+toggle, Con{+open, Con{+create, Con{+more, Nil{}}}}}: navigation_project_commands(key, owner, depth, visible, visual, Sidebar.capture(toggle), Sidebar.capture(open), Sidebar.capture(create), Sidebar.capture(more), [toggle, open, create, more])
    case other: box(key, Source.Div{}, role_style(visual, SurfaceTypes.Section{}), Nil{}, other)

def navigation_single_command(+key:UIIdentity.Key, +owner:UIIdentity.Key, +depth:Nat, +visual:Design.Style, captured:Maybe<&2, Sidebar.Command>, status:+List<Source.Node>, fallback:Source.Node) -> Source.Node:
  match captured:
    case Some{command}: sidebar_entry(key, owner, depth, visual, Sidebar.SingleAction{command, status})
    case None{}: fallback

def navigation_task_row(+key: UIIdentity.Key, +owner: UIIdentity.Key, +depth: Nat, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  match content:
    case Con{+primary, Con{+status, Nil{}}}: navigation_single_command(key, owner, depth, visual, Sidebar.capture(primary), [status], box(key, Source.Div{}, role_style(visual, SurfaceTypes.Section{}), Nil{}, [primary, status]))
    case other: box(key, Source.Div{}, role_style(visual, SurfaceTypes.Section{}), Nil{}, other)

def sidebar_collection(+key:UIIdentity.Key, +kind:Sidebar.CollectionKind, +visual:Design.Style, +content:+List<Source.Node>) -> Source.Node:
  Sidebar.constructed_collection_node(Sidebar.construct_collection(Sidebar.CollectionRequest{key, kind, visual, content}))

def navigation_section(+key:UIIdentity.Key, +visual:Design.Style, +children:+List<Child>) -> Source.Node:
  match children:
    case Con{Child{caption_key, caption_role, SurfaceTypes.InformationText{Information.NavigationCaption{}}, caption_control, caption_nodes}, rest}: sidebar_collection(key, Sidebar.Section{}, visual, List.append(&2, Source.Node, ordinary(caption_nodes), ordinary(all_nodes(rest))))
    case other: sidebar_collection(key, Sidebar.Members{}, visual, ordinary(all_nodes(other)))

def navigation_group(+key: UIIdentity.Key, depth: Nat, visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  add_attributes(sidebar_collection(key, Sidebar.Section{}, visual, content), [Source.DataAttribute{"navigation-depth", Nat.show(depth)}])

def navigation_row_meaning(meaning: SurfaceTypes.Meaning, key: UIIdentity.Key, owner: UIIdentity.Key, +depth: Nat, visible: Bool, +visual: Design.Style, +children: +List<Child>) -> Source.Node:
  match meaning:
    case SurfaceTypes.TaskRow{+task, +status, selected}: add_attributes(navigation_task_row(key, owner, depth, visual, task_children(children, status, visual)), [Source.DataAttribute{"task", Nat.show(task)}, Source.DataAttribute{"status", View2.task_status_label(status)}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}])
    case _: navigation_project_header(key, owner, depth, visible, visual, ordinary(all_nodes(children)))


def navigation_group_meaning(meaning: SurfaceTypes.Meaning, key: UIIdentity.Key, depth: Nat, visual: Design.Style, children: +List<Source.Node>) -> Source.Node:
  match meaning:
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: add_attributes(navigation_group(key, depth, visual, children), [Source.DataAttribute{"project", Nat.show(project)}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}, Source.DataAttribute{"expanded", FieldOptions.boolean(expanded)}])
    case _: navigation_group(key, depth, visual, children)

def regular_plain(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  match role:
    case SurfaceTypes.Dialog{}: regular_content(capacity, key, label, role, meaning, visual, representation, children, parameters, dialog_content(capacity, key, label, visual, children))
    case _: grouped_menu(capacity, role, children, meaning_focus(meaning, role, regular_content(capacity, key, label, role, meaning, visual, representation, children, parameters, ordinary(all_nodes(children)))))

def regular_navigation(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.NavigationGroup{depth}: navigation_group_meaning(meaning, key, depth, visual, ordinary(all_nodes(children)))
    case Controls.NavigationRow{owner, depth, visible, feedback_active}: navigation_row_meaning(meaning, key, owner, depth, visible, visual, children)
    case _: regular_plain(capacity, key, label, role, meaning, visual, representation, children, parameters)



def regular(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  match role:
    case SurfaceTypes.NavigationEntry{selected}:
      +primary = button_source(key, visual, representation)
      navigation_single_command(UIIdentity.part(key, "@navigation-entry"), key, 0n, visual, Sidebar.capture(primary), Nil{}, primary)
    case SurfaceTypes.NavigationCollection{}: sidebar_collection(key, Sidebar.Collection{}, visual, ordinary(all_nodes(children)))
    case SurfaceTypes.NavigationSection{}: navigation_section(key, visual, children)
    case SurfaceTypes.Section{}: regular_navigation(capacity, key, label, role, meaning, visual, representation, children, parameters)
    case _: regular_plain(capacity, key, label, role, meaning, visual, representation, children, parameters)

def read_only_role(+capacity: Nat, +role: SurfaceTypes.Role, +key: UIIdentity.Key, +label: String, +value: String, +visual: Design.Style, +code_visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters, +source: Maybe<&2, Code.Source>) -> Authorship:
  match role:
    case SurfaceTypes.Alert{}: Authored{regular(capacity, key, label, role, SurfaceTypes.ReadOnly{value}, visual, control, children, parameters) <> native(all_nodes(children))}
    case other: rich(key, other, value, visual, code_visual, children, source)

# Native attachments remain the same nodes while passing through ordinary parents.


def authored_node_content(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Authorship:
  match meaning:
    case SurfaceTypes.CodeFacts{Code.Scene{identity, literal, wrap, copy, enabled, controls}}: Authored{code_children(key, identity, wrap, visual, children)}
    case SurfaceTypes.ReadOnly{value}: read_only_role(capacity, role, key, label, value, visual, Appearance.style(SurfaceTypes.CodeBlock{}, SurfaceTypes.ReadOnly{value}, Design.style_text(visual)), control, children, parameters, None{})
    case SurfaceTypes.RichText{source, value}: read_only_role(capacity, role, key, label, value, visual, Appearance.style(SurfaceTypes.CodeBlock{}, SurfaceTypes.ReadOnly{value}, Design.style_text(visual)), control, children, parameters, Some{source})
    case other: Authored{regular(capacity, key, label, role, other, visual, control, children, parameters) <> native(all_nodes(children))}

def authored_node_ordered(+capacity: Nat, ordered: Bool, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Authorship:
  match ordered:
    case False{}: Rejected{key, InvalidDialogOrder{}}
    case True{}: authored_node_content(capacity, key, label, role, meaning, visual, control, children, parameters)

def authored_node(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Authorship:
  match role:
    case SurfaceTypes.Dialog{}: authored_node_ordered(capacity, dialog_ordered(children), key, label, SurfaceTypes.Dialog{}, meaning, visual, control, children, parameters)
    case other: authored_node_content(capacity, key, label, other, meaning, visual, control, children, parameters)

def decorate_nodes(+values: +List<Source.Node>, +attrs: +List<Source.Attribute>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: add_attributes(node, attrs) <> decorate_nodes(rest, attrs)

def finish_node(+result: Authorship, +key: UIIdentity.Key, +semantic: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +control: Controls.Representation) -> Forest:
  match result:
    case Rejected{key, problem}: Failed{key, problem}
    case Authored{nodes}: Ready{[Child{key, role, meaning, control, decorate_nodes(nodes, attributes(key, semantic, role))}]}

def context_from_meaning(+context: Maybe<&2, ReadingBinding.Context>, +meaning: SurfaceTypes.Meaning) -> Maybe<&2, ReadingBinding.Context>:
  match meaning:
    case SurfaceTypes.PageContext{Some{Conversation.Identity{task, generation}}}: Some{ReadingBinding.Context{task, generation}}
    case SurfaceTypes.PageContext{None{}}: None{}
    case _: context

def reading_box(+context: ReadingBinding.Context, +role: SurfaceTypes.Role, +node: Source.Node, +visual: Design.Style) -> Source.Node:
  match role node:
    case SurfaceTypes.Timeline{} Source.Box{key, tag, style, attrs, children}:
      Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, [Source.ReadingAttribute{ReadingBinding.Binding{context, ReadingBinding.ReadingViewport{}}}]),
        [box(UIIdentity.part(key, "@reading-content"), Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}), [Source.ReadingAttribute{ReadingBinding.Binding{context, ReadingBinding.Content{}}}], children)]}
    case SurfaceTypes.Composer{} Source.Box{key, tag, style, attrs, children}:
      Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, [Source.ReadingAttribute{ReadingBinding.Binding{context, ReadingBinding.Dock{}}}]), children}
    case _ other: other

def reading_match(+matches: Bool, +context: ReadingBinding.Context, +role: SurfaceTypes.Role, +node: Source.Node, +visual: Design.Style) -> Source.Node:
  match matches:
    case True{}: reading_box(context, role, node, visual)
    case False{}: node

def reading_nodes(+nodes: +List<Source.Node>, +context: ReadingBinding.Context, +key: UIIdentity.Key, +role: SurfaceTypes.Role, +visual: Design.Style) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: reading_match(UIIdentity.same(Source.key_of(node), key), context, role, node, visual) <> reading_nodes(rest, context, key, role, visual)

def reading_root(+context: Maybe<&2, ReadingBinding.Context>, +key: UIIdentity.Key, +role: SurfaceTypes.Role, +result: Authorship, +visual: Design.Style) -> Authorship:
  match context result:
    case Some{context} Authored{nodes}: Authored{reading_nodes(nodes, context, key, role, visual)}
    case _ other: other

def construct_in_context(+capacity: Nat, +children: Forest, +key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, ReadingBinding.Context>) -> Forest:
  match children:
    case Failed{key, problem}: Failed{key, problem}
    case Ready{children}: finish_node(reading_root(context, key, role, authored_node(capacity, key, label, role, meaning, visual, control, children, parameters), visual), key, semantic, role, meaning, control)

def construct(+capacity: Nat, +children: Forest, +key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters) -> Forest:
  construct_in_context(capacity, children, key, semantic, label, role, meaning, visual, control, parameters, None{})

def combine(+first: Forest, +rest: Forest) -> Forest:
  match first:
    case Failed{key, problem}: Failed{key, problem}
    case Ready{first}:
      match rest:
        case Failed{key, problem}: Failed{key, problem}
        case Ready{rest}: Ready{List.append(&2, Child, first, rest)}

# A page context scopes its descendants; siblings retain their enclosing context.

def forest_in_context(+capacity: Nat, +values: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, ReadingBinding.Context>) -> Forest:
  match values:
    case Nil{}: Ready{Nil{}}
    case Con{node, rest}:
      match node:
        case Design.Node{key, semantic, label, role, meaning, visual, control, children}:
          +current = context_from_meaning(context, meaning)
          combine(construct_in_context(capacity, forest_in_context(capacity, children, parameters, current), key, semantic, label, role, meaning, visual, control, parameters, current), forest_in_context(capacity, rest, parameters, context))

def forest(+capacity: Nat, +values: +List<Design.Node>, +parameters: Design.LayoutParameters) -> Forest:
  forest_in_context(capacity, values, parameters, None{})

def finish_forest(+value: Forest) -> Authorship:
  match value:
    case Failed{key, problem}: Rejected{key, problem}
    case Ready{children}:
      +values = all_nodes(children)
      orphan(values, values)

def nodes(+capacity: Nat, +values: +List<Design.Node>, +parameters: Design.LayoutParameters) -> Authorship:
  finish_forest(forest(capacity, values, parameters))

def background_attributes(+active: Maybe<&2, String>) -> +List<Source.Attribute>:
  match active:
    case None{}: Nil{}
    case Some{key}: [Source.InertAttribute{}, Source.AriaAttribute{"hidden", "true"}]

def modal_ownership(+owns: Bool) -> +List<Source.Attribute>:
  match owns:
    case True{}: [Source.RoleAttribute{"dialog"}, Source.AriaAttribute{"modal", "true"}]
    case False{}: [Source.InertAttribute{}, Source.AriaAttribute{"hidden", "true"}]

def modal_attributes(+active: Maybe<&2, String>, +key: UIIdentity.Key) -> +List<Source.Attribute>:
  match active:
    case None{}: Nil{}
    case Some{current}: modal_ownership(String.eq(current, UIIdentity.encode(key)))

def scoped_children(+values: +List<Child>, +active: Maybe<&2, String>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{+key, role, meaning, control, nodes}, rest}:
      append(decorate_nodes(nodes, modal_attributes(active, key)), scoped_children(rest, active))

def overlay_forest(+value: Forest, +active: Maybe<&2, String>) -> Authorship:
  match value:
    case Failed{key, problem}: Rejected{key, problem}
    case Ready{children}:
      +values = scoped_children(children, active)
      orphan(values, values)

def background(+result: Authorship, +active: Maybe<&2, String>) -> Authorship:
  match result:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{values}: Authored{decorate_nodes(values, background_attributes(active))}

def base(+capacity: Nat, +surface: Design.Surface, +parameters: Design.LayoutParameters) -> Authorship:
  Design.Surface{content, theme, base, overlays, active_scope} = surface
  background(nodes(capacity, base, parameters), active_scope)

def overlays(+capacity: Nat, +surface: Design.Surface, +parameters: Design.LayoutParameters) -> Authorship:
  Design.Surface{content, theme, base, overlays, active_scope} = surface
  overlay_forest(forest(capacity, overlays, parameters), active_scope)

def layout_of_lane(node: Source.Node) -> Maybe<&2, Source.Style>:
  match node:
    case Source.Control{key, tag, style, attributes, label, enabled, event, events, children}: Some{style}
    case _: None{}

# The supporting slot owns residual room, independent of its current text demand.
def supporting_region_key(key: UIIdentity.Key) -> Bool:
  match key:
    case UIIdentity.Part{parent, part}: String.eq(part, "supporting-controls")
    case _: False{}

def supporting_form_name(form: Controls.SupportingForm) -> String:
  match form:
    case Controls.FullSupporting{}: "full"
    case Controls.CompactSupporting{}: "compact"

def supporting_region_style(style: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  Source.Style{Source.Layout{direction, Spatial.Leading{}, cross, frame, Model.StretchSize{}, height, minimum, scroll, position}, font, chrome, states}

def supporting_region_box(selected: Bool, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, form: Controls.SupportingForm) -> Source.Node:
  match selected:
    case True{}: Source.Box{key, tag, supporting_region_style(style), List.append(&2, Source.Attribute, attributes, [Source.DataAttribute{"allocated-region", "supporting-controls"}, Source.DataAttribute{"supporting-form", supporting_form_name(form)}]), children}
    case False{}: Source.Box{key, tag, style, attributes, children}

def supporting_region_nodes(nodes: +List<Source.Node>, +form: Controls.SupportingForm) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Box{+key, tag, style, attributes, children}, rest}:
      supporting_region_box(supporting_region_key(key), key, tag, style, attributes, supporting_region_nodes(children, form), form) <> supporting_region_nodes(rest, form)
    case Con{Source.Control{key, tag, style, attributes, name, enabled, first, remaining, children}, rest}:
      Source.Control{key, tag, style, attributes, name, enabled, first, remaining, supporting_region_nodes(children, form)} <> supporting_region_nodes(rest, form)
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      Source.NativeAttachment{key, target, attributes, style, supporting_region_nodes(children, form)} <> supporting_region_nodes(rest, form)
    case Con{other, rest}: other <> supporting_region_nodes(rest, form)

def only_supporting_node(nodes: +List<Source.Node>, fallback: Source.Node) -> Source.Node:
  match nodes:
    case Con{node, rest}: node
    case Nil{}: fallback

def supporting_region_node(+node: Source.Node, form: Controls.SupportingForm) -> Source.Node:
  only_supporting_node(supporting_region_nodes(node <> Nil{}, form), node)

def first_supporting_form(first: Maybe<&2, Controls.SupportingForm>, rest: Maybe<&2, Controls.SupportingForm>) -> Maybe<&2, Controls.SupportingForm>:
  match first:
    case Some{form}: Some{form}
    case None{}: rest

def form_attribute(attributes: +List<Source.Attribute>) -> Maybe<&2, Controls.SupportingForm>:
  match attributes:
    case Nil{}: None{}
    case Con{Source.DataAttribute{"supporting-form", "full"}, rest}: Some{Controls.FullSupporting{}}
    case Con{Source.DataAttribute{"supporting-form", "compact"}, rest}: Some{Controls.CompactSupporting{}}
    case Con{other, rest}: form_attribute(rest)

def supporting_region_form_nodes(nodes: +List<Source.Node>) -> Maybe<&2, Controls.SupportingForm>:
  match nodes:
    case Nil{}: None{}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      first_supporting_form(form_attribute(attributes), first_supporting_form(supporting_region_form_nodes(children), supporting_region_form_nodes(rest)))
    case Con{Source.Control{key, tag, style, attributes, name, enabled, first, remaining, children}, rest}:
      first_supporting_form(supporting_region_form_nodes(children), supporting_region_form_nodes(rest))
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      first_supporting_form(supporting_region_form_nodes(children), supporting_region_form_nodes(rest))
    case Con{other, rest}: supporting_region_form_nodes(rest)

def supporting_region_form(node: Source.Node) -> Maybe<&2, Controls.SupportingForm>:
  supporting_region_form_nodes(node <> Nil{})
