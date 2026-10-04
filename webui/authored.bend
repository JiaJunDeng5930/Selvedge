import Base
import ./source.bend as Source
import ./authored-primitives.bend as Factory
import ./authored-controls.bend as AuthoredControls
import ./design.bend as Design
import ./physical-space.bend as Model
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./typography.bend as T
import ./controls.bend as Controls
import ./document.bend as Doc
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ../core/code-block.bend as Code
import ../core/form-fields.bend as Forms
import ../core/field-options.bend as FieldOptions
import ../core/user-context.bend as Context
import ../core/ui-world.bend as View
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/user-conversation.bend as Conversation
import ../core/SYSTEM.bend as Core
import ../bendlib/domain.bend as Domain
import ../BOARD.bend as Board

type Problem is Data:
  OrphanCode{target: Source.NativeTarget}
  ConflictingCodeOwners{expected: Code.Source, actual: Code.Source}

type Result is Data:
  Authored{nodes: +List<Source.Node>}
  Rejected{key: String, problem: Problem}

# Child metadata survives authorship without retaining a second design tree.
type Child is Data:
  Child{key: String, role: UI.Role, meaning: UI.Meaning,
    control: Controls.Representation, nodes: +List<Source.Node>}

type Forest is Data:
  Ready{children: +List<Child>}
  Failed{key: String, problem: Problem}

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

def text(+key: String, +value: String, +visual: Design.Style, +tier: T.Tier, +emphasis: T.Emphasis) -> Source.Node:
  Source.Text{key, value, Source.ExplicitFont{T.with_emphasis(T.with_tier(Design.style_text(visual), tier), emphasis)}, T.NormalAnywhere{}}

def group(+key: String, +visual: Design.Style, +direction: Model.Direction, +width: Model.AxisSize,
  +height: Model.AxisSize, +children: +List<Source.Node>) -> Source.Node:
  Source.Box{key, Source.Div{}, Factory.content_style(visual, direction, width, height, AuthoredControls.parent_gap(visual)), Nil{}, children}

def role_tag(+role: UI.Role) -> Source.BoxTag:
  match role:
    case UI.Navigation{}: Source.Navigation{}
    case UI.NavigationHeader{}: Source.Header{}
    case UI.Main{}: Source.Main{}
    case UI.Heading{}: Source.Header{}
    case UI.Activity{}: Source.Section{}
    case UI.Dialog{}: Source.Section{}
    case UI.Card{}: Source.Article{}
    case UI.UserMessage{}: Source.Article{}
    case UI.AssistantMessage{}: Source.Article{}
    case _: Source.Div{}

def role_name(+value: UI.Role) -> String:
  match value:
    case UI.NavigationHeader{}: "navigation-header"
    case UI.Heading{}: "heading"
    case UI.Timeline{}: "timeline"
    case UI.Composer{}: "composer"
    case UI.ComposerActions{}: "composer-actions"
    case UI.ApprovalQueue{}: "approvals"
    case UI.UserMessage{}: "user-message"
    case UI.AssistantMessage{}: "agent-message"
    case UI.Activity{}: "activity"
    case UI.Navigation{}: "navigation"
    case UI.Main{}: "main"
    case UI.Section{}: "section"
    case _: "content"

def reading_attributes(+role: UI.Role, +key: String) -> +List<Source.Attribute>:
  match role:
    case UI.UserMessage{}: [Source.DataAttribute{"reading-key", key}]
    case UI.AssistantMessage{}: [Source.DataAttribute{"reading-key", key}]
    case UI.Activity{}: [Source.DataAttribute{"reading-key", key}]
    case _: Nil{}

def attributes(+key: String, +semantic: String, +role: UI.Role) -> +List<Source.Attribute>:
  List.append(&2, Source.Attribute, [Source.DataAttribute{"native-key", key}, Source.DataAttribute{"region", role_name(role)}, Source.DataAttribute{"semantic", semantic}], reading_attributes(role, key))

def add_attributes(+node: Source.Node, +extra: +List<Source.Attribute>) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, extra), children}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: Source.Control{key, tag, style, List.append(&2, Source.Attribute, attrs, extra), name, enabled, first, remaining, children}
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: Source.Field{key, kind, style, List.append(&2, Source.Attribute, attrs, extra), value, placeholder, options, policy, name, enabled, first, remaining}
    case other: other

def role_style(+visual: Design.Style, +role: UI.Role) -> Source.Style:
  match role:
    case UI.Main{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case UI.Timeline{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case UI.Details{}: Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollVertically{})
    case UI.UserMessage{}: Factory.style(visual, Factory.natural_width(visual), Model.NaturalSize{}, Model.Confined{})
    case _: Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{})

def section_caption(+empty: Bool, +key: String, +label: String, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [Source.Box{key ++ "/@title", Source.Heading2{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [text(key ++ "/@title/text", label, visual, T.Body{}, T.Medium{})]}]

def caption(+key: String, +label: String, +role: UI.Role, +visual: Design.Style) -> +List<Source.Node>:
  match role:
    case UI.NavigationHeader{}: [Source.Box{key ++ "/@brand", Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"navigation-brand", ""}], [text(key ++ "/@brand/text", label, visual, T.Section{}, T.Medium{})]}]
    case UI.Heading{}: [text(key ++ "/@title", label, visual, T.Body{}, T.Regular{})]
    case UI.Dialog{}: [Source.Box{key ++ "/@title", Source.Heading2{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [text(key ++ "/@title/text", label, visual, T.Body{}, T.Medium{})]}]
    case UI.Section{}:
      section_caption(String.is_empty(label), key, label, visual)
    case _: Nil{}

def box(+key: String, +tag: Source.BoxTag, +style: Source.Style, +attrs: +List<Source.Attribute>, +children: +List<Source.Node>) -> Source.Node:
  Source.Box{key, tag, style, attrs, children}

def source_of(+values: +List<Child>) -> Maybe<&2, Code.Source>:
  match values:
    case Nil{}: None{}
    case Con{Child{key, role, UI.CodeFacts{Code.Scene{Code.Identity{source, ordinal}, literal, wrap, copy, enabled, controls}}, control, nodes}, rest}: Some{source}
    case Con{child, rest}: source_of(rest)

def target_source(+target: Source.NativeTarget) -> Code.Source:
  match target:
    case Source.ToolbarTarget{Code.Identity{source, ordinal}}: source
    case Source.CodeBodyTarget{Code.Identity{source, ordinal}, wrap}: source

def owner_validation(+matches: Bool, +owner: String, +expected: Code.Source, +actual: Code.Source) -> Result:
  match matches:
    case True{}: Authored{Nil{}}
    case False{}: Rejected{owner, ConflictingCodeOwners{expected, actual}}

def target_validation(+source: Maybe<&2, Code.Source>, +owner: String, +key: String, +target: Source.NativeTarget) -> Result:
  match source:
    case None{}: Rejected{key, OrphanCode{target}}
    case Some{+expected}: owner_validation(String.eq(Code.source_key(expected), Code.source_key(target_source(target))), owner, expected, target_source(target))

def merge_validation(+first: Result, +rest: Result) -> Result:
  match first:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{unused}: rest

def check_owners(+values: +List<Source.Node>, +owner: String, +source: Maybe<&2, Code.Source>) -> Result:
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
    case Con{Child{key, role, meaning, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, nodes}, rest}: Nat.max(Controls.geometry_preferred_height(geometry), toolbar_preferred(rest))
    case Con{other, rest}: toolbar_preferred(rest)

def rich_policy(+visual: Design.Style, +reserve: Nat) -> Source.RichPolicy:
  +body = T.resolved_size(T.resolved(Design.style_text(visual)))
  +code = T.with_tier(Design.style_text(visual), T.CodeBody{})
  +padding = T.resolved_size(T.resolved(code))
  Source.RichPolicy{Enclosure.Insets{padding, padding}, reserve, body, Nat.mul(2n, body), code, False{}}

def rich_leaf(+key: String, +value: String, +visual: Design.Style, +source: Maybe<&2, Code.Source>, +attachments: +List<Source.Node>) -> Source.Node:
  Source.RichText{key, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Source.RichContent{source, value, rich_policy(visual, toolbar_reserve(attachments))}, attachments}

def rich_checked(+result: Result, +key: String, +role: UI.Role, +value: String, +visual: Design.Style, +children: +List<Child>) -> Result:
  match result:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{unused}: Authored{[box(key, role_tag(role), role_style(visual, role), Nil{}, rich_leaf(key ++ "/markdown", value, visual, source_of(children), native(all_nodes(children))) <> ordinary(all_nodes(children)))]}

def rich(+key: String, +role: UI.Role, +value: String, +visual: Design.Style, +children: +List<Child>) -> Result:
  rich_checked(check_owners(native(all_nodes(children)), key, source_of(children)), key, role, value, visual, children)

def code_toolbar(+toolbar: +List<Source.Node>, +key: String, +identity: Code.Identity, +visual: Design.Style, +preferred: Nat, +body: Source.Node, +remaining: +List<Source.Node>) -> +List<Source.Node>:
  match toolbar:
    case Nil{}: body <> remaining
    case Con{first, rest}:
      Source.NativeAttachment{key ++ "/toolbar", Source.ToolbarTarget{identity}, Factory.binding_attributes(key), Factory.with_minimum(Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Extent{0n, preferred}), first <> rest} <> body <> remaining

def code_children(+key: String, +identity: Code.Identity, +wrap: Bool, +visual: Design.Style, +children: +List<Child>) -> +List<Source.Node>:
  +body_style = Factory.with_alignments(Factory.with_font(Factory.content_style(visual, Model.Vertical{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), Source.ExplicitFont{T.with_tier(Design.style_text(visual), T.CodeBody{})}), Spatial.Leading{}, Spatial.Leading{})
  code_toolbar(ordinary(all_nodes(children)), key, identity, visual, toolbar_preferred(children), Source.NativeAttachment{key ++ "/wrap", Source.CodeBodyTarget{identity, wrap}, Nil{}, body_style, Nil{}}, native(all_nodes(children)))

def orphan(+values: +List<Source.Node>, +original: +List<Source.Node>) -> Result:
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

def context_kind(+value: Context.Observation) -> String:
  match value:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.InheritedWorkspace{workspace}, Context.InheritedSandbox{sandbox}, Context.InheritedApproval{approval}, guidance}}: "inherited"
    case Context.DraftExecution{other}: "custom"
    case Context.CommittedExecution{context}: "committed"

def fact(+key: String, +label: String, +value: String, +visual: Design.Style) -> Source.Node:
  group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [text(key ++ "/label", label, visual, T.Body{}, T.Strong{}), text(key ++ "/value", value, visual, T.Body{}, T.Regular{})])

def task_details(+owner: String, +value: View.TaskDetails, +visual: Design.Style) -> +List<Source.Node>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  [group(owner ++ "/@facts", visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [fact(owner ++ "/@workspace", "Working directories", FieldOptions.joined(roots), visual), fact(owner ++ "/@primary", "Primary directory", FieldOptions.optional_text(primary), visual), fact(owner ++ "/@sandbox", "Filesystem access", Domain.sandbox_mode_name(mode), visual), fact(owner ++ "/@network", "Network access", FieldOptions.boolean(network), visual), fact(owner ++ "/@approval", "Approval policy", Domain.approval_name(approval), visual), fact(owner ++ "/@model", "Model", name, visual), fact(owner ++ "/@reasoning", "Reasoning", reasoning, visual), fact(owner ++ "/@messages", "Queued messages", FieldOptions.joined(queued), visual)])]

def audit_nodes(+values: +List<Conversation.AuditFace>, +key: String, +visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.AuditFace{+id, kind, title, source}, rest}:
      group(key ++ "/audit/" ++ Nat.show(id), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [text(key ++ "/audit-title/" ++ Nat.show(id), title, visual, T.Body{}, T.Strong{}), rich_leaf(key ++ "/audit-body/" ++ Nat.show(id), Conversation.audit_detail(source), visual, None{}, Nil{})]) <> audit_nodes(rest, key, visual)

def disclosure(+control: Controls.Representation) -> Bool:
  match control:
    case Controls.Action{Core.ApplicationInput{Experience.UserInput{User.SetDisclosure{task, group, occurrence, expanded}}}, availability, name, face, behavior, geometry, placement, help, feedback}: True{}
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

def activity_title(+key: String, +label: String, +visual: Design.Style, +values: +List<Source.Node>) -> +List<Source.Node>:
  match values:
    case Nil{}: [text(key ++ "/@summary", label, visual, T.Body{}, T.Regular{})]
    case other: other

def expanded_content(+expanded: Bool, +children: +List<Source.Node>) -> +List<Source.Node>:
  match expanded:
    case True{}: children
    case False{}: Nil{}

def board_group_name(+value: UI.BoardGrouping) -> String:
  match value:
    case UI.ViewChoices{}: "view-choices"
    case UI.SearchArea{}: "search"
    case UI.WorkStatus{}: "work-status"
    case UI.SecondaryActions{}: "secondary-actions"
    case UI.PrimaryAction{}: "primary-action"

def board_group_label(+value: UI.BoardGrouping) -> String:
  match value:
    case UI.ViewChoices{}: "看板视图"
    case UI.SearchArea{}: "任务搜索"
    case UI.WorkStatus{}: "当前工作状态"
    case UI.SecondaryActions{}: "看板筛选和设置"
    case UI.PrimaryAction{}: "主要操作"

def lane_create(+stage: Board.Stage, +meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.ComposerAction{subject, Core.ApplicationInput{Experience.UserInput{User.Activate{User.NewCard{requested}}}}, availability}: String.eq(Board.stage_name(stage), Board.stage_name(requested))
    case UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.NewCard{requested}}}}, availability}: String.eq(Board.stage_name(stage), Board.stage_name(requested))
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

def empty_lane_present(+empty: Bool, +key: String, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: [box(key ++ "/@empty", Source.Paragraph{}, Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"board-empty", ""}], [text(key ++ "/@empty/text", "暂无任务", visual, T.Support{}, T.Regular{})])]
    case False{}: Nil{}

def empty_lane(+count: Nat, +key: String, +visual: Design.Style) -> +List<Source.Node>:
  empty_lane_present(Nat.is_eq(count, 0n), key, visual)

def scroll_content(+value: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, old_scroll, position}, font, chrome, states} = value
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, Model.ScrollVertically{}, position}, font, chrome, states}

def lane(+key: String, +label: String, +stage: Board.Stage, +count: Nat, +visual: Design.Style, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  Source.Control{key, Source.SectionControl{}, Factory.with_direction(Factory.style(visual, Model.LimitedSize{Design.main_minimum_width(parameters), 0n, Design.main_minimum_width(parameters)}, Model.StretchSize{}, Model.Confined{}), Model.Vertical{}), [Source.DataAttribute{"board-stage", Board.stage_name(stage)}, Source.DataAttribute{"board-count", Nat.show(count)}], label, True{}, Doc.DropCard{key}, Nil{},
    [box(key ++ "/@heading", Source.Header{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.DataAttribute{"board-lane-heading", ""}],
      [group(key ++ "/@heading-leading", visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, [box(key ++ "/@stage-mark", Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"board-stage-mark", Board.stage_name(stage)}, Source.AriaAttribute{"hidden", "true"}], Nil{}), text(key ++ "/@title", label, visual, T.Support{}, T.Medium{}), text(key ++ "/@count", Nat.show(count), visual, T.Support{}, T.Regular{})]), group(key ++ "/@heading-trailing", visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, lane_children(children, True{}, stage))]),
     box(key ++ "/@cards", Source.Div{}, scroll_content(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.StretchSize{}, AuthoredControls.parent_gap(visual))), [Source.DataAttribute{"board-cards", ""}], append(empty_lane(count, key, visual), lane_children(children, False{}, stage)))]}

def optional_text_present(+empty: Bool, +value: String, +key: String, +part: String, +visual: Design.Style) -> +List<Source.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [text(key ++ "/@" ++ part, value, visual, T.Support{}, T.Regular{})]

def optional_text(+value: String, +key: String, +part: String, +visual: Design.Style) -> +List<Source.Node>:
  optional_text_present(String.is_empty(value), value, key, part, visual)

def pinned(+found: Bool, +key: String, +visual: Design.Style) -> +List<Source.Node>:
  match found:
    case True{}: [text(key ++ "/@pinned", "置顶", visual, T.Support{}, T.Regular{})]
    case False{}: Nil{}

def card_labels(+values: +List<String>, +key: String, +index: Nat, +visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: text(key ++ "/@label/" ++ Nat.show(index), value, visual, T.Support{}, T.Regular{}) <> card_labels(rest, key, Nat.add(index, 1n), visual)

def more_action(+meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.ComposerAction{subject, Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{object}, trigger}}}}, availability}: True{}
    case UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{object}, trigger}}}}, availability}: True{}
    case _: False{}

def card_actions_selected(+selected: Bool, +nodes: +List<Source.Node>, +rest: +List<Source.Node>) -> +List<Source.Node>:
  match selected:
    case True{}: append(ordinary(nodes), rest)
    case False{}: rest

def card_actions(+values: +List<Child>, +want: Bool) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{key, role, meaning, control, nodes}, rest}:
      card_actions_selected(same_boolean(want, more_action(meaning)), nodes, card_actions(rest, want))

def card_title(+key: String, +title: String, +visual: Design.Style, +actions: +List<Source.Node>) -> +List<Source.Node>:
  match actions:
    case Nil{}: [text(key ++ "/@title", title, visual, T.Body{}, T.Strong{})]
    case other: other

def card_grip(+value: Controls.Representation, +key: String, +visual: Design.Style) -> +List<Source.Node>:
  match value:
    case Controls.Movable{destinations, face, name, handle, geometry, help}: [AuthoredControls.glyph(key ++ "/@grip", handle, visual, AuthoredControls.face_icon_size(geometry))]
    case _: Nil{}

def card(+key: String, +face: View.CardFace, +visual: Design.Style, +children: +List<Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> Source.Node:
  View.CardFace{+id, +title, description, priority, pinned_value, +status, project, labels, owner, updated} = face
  Source.Control{key, Source.ArticleControl{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.DataAttribute{"card-id", Nat.show(id)}, Source.DataAttribute{"card-title", title}, Source.DraggableAttribute{FieldOptions.boolean(movable)}], title, movable, Doc.DragCard{key}, [Doc.DropCard{key}],
    append(append(card_grip(representation, key, visual), [group(key ++ "/@metadata", visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, append([text(key ++ "/@reference", "SV-" ++ Nat.show(id), visual, T.Support{}, T.Regular{}), text(key ++ "/@priority", Board.priority_label(priority), visual, T.Support{}, T.Regular{})], append(pinned(pinned_value, key, visual), optional_text(status, key, "status", visual)))),
      group(key ++ "/@actions", visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, [group(key ++ "/@open", visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, card_title(key, title, visual, card_actions(children, False{}))), group(key ++ "/@more", visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, append(card_actions(children, True{}), [AuthoredControls.movable_choices(key, representation, visual, parameters)]))])]),
      append(optional_text(description, key, "description", visual), append([group(key ++ "/@context", visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, append(optional_text(project, key, "project", visual), card_labels(labels, key, 0n, visual)))], [box(key ++ "/@footer", Source.Footer{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.DataAttribute{"card-footer", ""}], append(optional_text(owner, key, "owner", visual), optional_text(updated, key, "updated", visual)))])))}

def task_children(+values: +List<Child>, +status: String, +visual: Design.Style) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{+key, role, meaning, control, nodes}, rest}:
      match control:
        case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: append(ordinary(nodes), task_children(rest, status, visual))
        case _: box(key, Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.AriaAttribute{"label", status}, Source.TitleAttribute{status}], [text(key ++ "/indicator", "●", visual, T.Support{}, T.Medium{}), text(key ++ "/status", status, visual, T.Support{}, T.Medium{})]) <> task_children(rest, status, visual)

def compound(+key: String, +label: String, +field: Forms.Field, +visual: Design.Style, +children: +List<Source.Node>) -> Source.Node:
  box(key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"field", Forms.key(field)}, Source.TabIndexAttribute{"-1"}], children)

def chooser_selection(+value: Maybe<&2, Nat>) -> +List<Source.Attribute>:
  match value:
    case None{}: Nil{}
    case Some{selected}: [Source.DataAttribute{"selected-project", Nat.show(selected)}]

def regular_content(+key: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> Source.Node:
  match meaning:
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: compound(key, label, field, visual, content)
    case UI.Edit{editor, field, Forms.FileCollection{}, value, choices}: compound(key, label, field, visual, content)
    case UI.ComposerAction{subject, input, availability}: AuthoredControls.action(key, visual, representation)
    case UI.PanelToggle{expanded, input, availability}: AuthoredControls.action(key, visual, representation)
    case UI.Activate{input, availability}: AuthoredControls.action(key, visual, representation)
    case UI.Choice{selected, description, input, availability}: AuthoredControls.action(key, visual, representation)
    case UI.ProjectGroup{project, selected, expanded}: box(key, Source.Div{}, role_style(visual, role), [Source.DataAttribute{"project", Nat.show(project)}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}, Source.DataAttribute{"expanded", FieldOptions.boolean(expanded)}], content)
    case UI.TaskRow{task, status, selected}: box(key, Source.Div{}, role_style(visual, role), [Source.DataAttribute{"task", Nat.show(task)}, Source.DataAttribute{"status", status}, Source.DataAttribute{"selected", FieldOptions.boolean(selected)}], task_children(children, status, visual))
    case UI.ProjectChooser{selected}: box(key, Source.Div{}, role_style(visual, role), chooser_selection(selected), content)
    case UI.DirectoryRow{path, primary}: box(key, Source.Div{}, role_style(visual, role), [Source.AriaAttribute{"label", path}, Source.DataAttribute{"primary", FieldOptions.boolean(primary)}], [box(key ++ "/path", Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.TitleAttribute{path}], [text(key ++ "/path/text", path, visual, T.Body{}, T.Regular{})]), group(key ++ "/controls", visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, content)])
    case UI.ContextSummary{observation}: box(key, Source.Div{}, role_style(visual, role), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"context-kind", context_kind(observation)}], text(key ++ "/provenance", label, visual, T.Support{}, T.Regular{}) <> content)
    case UI.ChoiceGroup{}: box(key, Source.Section{}, role_style(visual, role), [Source.RoleAttribute{"radiogroup"}, Source.AriaAttribute{"label", label}], text(key ++ "/label", label, visual, T.Support{}, T.Regular{}) <> content)
    case UI.PageRegion{region, position}: box(key, Source.Div{}, position_style(visual, position), [Source.DataAttribute{"page-position", position_name(position)}, Source.DataAttribute{"page-region", Composition.region_name(region)}], content)
    case UI.BoardGroup{grouping}: box(key, Source.Div{}, Factory.with_direction(Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.ScrollHorizontally{}), Model.Horizontal{}), [Source.DataAttribute{"board-group", board_group_name(grouping)}, Source.AriaAttribute{"label", board_group_label(grouping)}], content)
    case UI.BoardLane{stage, count}: lane(key, label, stage, count, visual, children, parameters)
    case UI.CardArchive{count}: Source.Control{key, Source.DivControl{}, role_style(visual, role), [Source.DataAttribute{"card-archive", Nat.show(count)}], label, True{}, Doc.DropCard{key}, Nil{}, content}
    case UI.MovableCard{destinations, face}: card(key, face, visual, children, representation, parameters, AuthoredControls.has_available_destination(destinations))
    case UI.LayerRegion{dismiss, outside, escape}: box(key, role_tag(role), role_style(visual, role), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"layer-key", key}, Source.DataAttribute{"layer-outside", FieldOptions.boolean(outside)}, Source.DataAttribute{"layer-escape", FieldOptions.boolean(escape)}, Source.TabIndexAttribute{"-1"}], append(caption(key, label, role, visual), content))
    case UI.ActivityContent{expanded, audit}: box(key, Source.Section{}, role_style(visual, role), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"expanded", FieldOptions.boolean(expanded)}], append(activity_title(key, label, visual, activity_header(children)), expanded_content(expanded, append(activity_content(children), audit_nodes(audit, key, visual)))))
    case UI.TaskFacts{details}: box(key, Source.Section{}, role_style(visual, role), Nil{}, append(task_details(key, details, visual), content))
    case UI.ReadOnly{value}: box(key, Source.Div{}, role_style(visual, role), [Source.RoleAttribute{"alert"}, Source.AriaAttribute{"label", label}], text(key ++ "/text", value, visual, T.Body{}, T.Regular{}) <> content)
    case UI.PageContext{conversation}: box(key, role_tag(role), role_style(visual, role), [Source.AriaAttribute{"label", label}], append(caption(key, label, role, visual), content))
    case UI.Region{}: box(key, role_tag(role), role_style(visual, role), [Source.AriaAttribute{"label", label}], append(caption(key, label, role, visual), content))
    case other: AuthoredControls.input(key, other, representation, visual, parameters)

def regular(+key: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Source.Node:
  regular_content(key, label, role, meaning, visual, representation, children, parameters, ordinary(all_nodes(children)))

def read_only_role(+role: UI.Role, +key: String, +label: String, +value: String, +visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Result:
  match role:
    case UI.Alert{}: Authored{regular(key, label, role, UI.ReadOnly{value}, visual, control, children, parameters) <> native(all_nodes(children))}
    case other: rich(key, other, value, visual, children)

# Native attachments remain the same nodes while passing through ordinary parents.
def authored_node(+key: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Child>, +parameters: Design.LayoutParameters) -> Result:
  match meaning:
    case UI.CodeFacts{Code.Scene{identity, literal, wrap, copy, enabled, controls}}: Authored{code_children(key, identity, wrap, visual, children)}
    case UI.ReadOnly{value}: read_only_role(role, key, label, value, visual, control, children, parameters)
    case other: Authored{regular(key, label, role, other, visual, control, children, parameters) <> native(all_nodes(children))}

def decorate_nodes(+values: +List<Source.Node>, +attrs: +List<Source.Attribute>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: add_attributes(node, attrs) <> decorate_nodes(rest, attrs)

def finish_node(+result: Result, +key: String, +semantic: String, +role: UI.Role, +meaning: UI.Meaning, +control: Controls.Representation) -> Forest:
  match result:
    case Rejected{key, problem}: Failed{key, problem}
    case Authored{nodes}: Ready{[Child{key, role, meaning, control, decorate_nodes(nodes, attributes(key, semantic, role))}]}

def construct(+children: Forest, +key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters) -> Forest:
  match children:
    case Failed{key, problem}: Failed{key, problem}
    case Ready{children}: finish_node(authored_node(key, label, role, meaning, visual, control, children, parameters), key, semantic, role, meaning, control)

def combine(+first: Forest, +rest: Forest) -> Forest:
  match first:
    case Failed{key, problem}: Failed{key, problem}
    case Ready{first}:
      match rest:
        case Failed{key, problem}: Failed{key, problem}
        case Ready{rest}: Ready{List.append(&2, Child, first, rest)}

# Both descents use original child/rest lists, so construction is structurally bounded.
def forest(+values: +List<Design.Node>, +parameters: Design.LayoutParameters) -> Forest:
  match values:
    case Nil{}: Ready{Nil{}}
    case Con{node, rest}:
      match node:
        case Design.Node{key, semantic, label, role, meaning, visual, control, children}:
          combine(construct(forest(children, parameters), key, semantic, label, role, meaning, visual, control, parameters), forest(rest, parameters))

def finish_forest(+value: Forest) -> Result:
  match value:
    case Failed{key, problem}: Rejected{key, problem}
    case Ready{children}:
      +values = all_nodes(children)
      orphan(values, values)

def nodes(+values: +List<Design.Node>, +parameters: Design.LayoutParameters) -> Result:
  finish_forest(forest(values, parameters))

def background_attributes(+active: Maybe<&2, String>) -> +List<Source.Attribute>:
  match active:
    case None{}: Nil{}
    case Some{key}: [Source.InertAttribute{}, Source.AriaAttribute{"hidden", "true"}]

def modal_ownership(+owns: Bool) -> +List<Source.Attribute>:
  match owns:
    case True{}: [Source.RoleAttribute{"dialog"}, Source.AriaAttribute{"modal", "true"}]
    case False{}: [Source.InertAttribute{}, Source.AriaAttribute{"hidden", "true"}]

def modal_attributes(+active: Maybe<&2, String>, +key: String) -> +List<Source.Attribute>:
  match active:
    case None{}: Nil{}
    case Some{current}: modal_ownership(String.eq(current, key))

def scoped_children(+values: +List<Child>, +active: Maybe<&2, String>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{+key, role, meaning, control, nodes}, rest}:
      append(decorate_nodes(nodes, modal_attributes(active, key)), scoped_children(rest, active))

def overlay_forest(+value: Forest, +active: Maybe<&2, String>) -> Result:
  match value:
    case Failed{key, problem}: Rejected{key, problem}
    case Ready{children}:
      +values = scoped_children(children, active)
      orphan(values, values)

def background(+result: Result, +active: Maybe<&2, String>) -> Result:
  match result:
    case Rejected{key, problem}: Rejected{key, problem}
    case Authored{values}: Authored{decorate_nodes(values, background_attributes(active))}

def base(+surface: Design.Surface, +parameters: Design.LayoutParameters) -> Result:
  Design.Surface{content, theme, base, overlays, active_scope} = surface
  background(nodes(base, parameters), active_scope)

def overlays(+surface: Design.Surface, +parameters: Design.LayoutParameters) -> Result:
  Design.Surface{content, theme, base, overlays, active_scope} = surface
  overlay_forest(forest(overlays, parameters), active_scope)
