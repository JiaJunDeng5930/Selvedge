import ../../bendlib/stdlib.bend as Std
import ../../interaction/services/CONTEXT.bend as Workspace
import ../../interaction/experience/MODEL.bend as UXTypes
import ../../interaction/INPUT.bend as User
import ../controls/CONTROLS.bend as AuthoredControls
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/INFORMATION.bend as Information
import Base
import ./SOURCE.bend as Source
import ./source-contract.bend as RuleSourceRules
import ../appearance/DESIGN.bend as Design
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/geometry-proof.bend as ProofGeometryProof
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../features/board/MODEL.bend as Board
import ../controls/MODEL.bend as Authored
import ../controls/PROGRAM.bend as Controls
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/presentation/MODEL.bend as View
import ../layout/physical-space.bend as Model
import ../controls/authored-primitives.bend as Factory

def native_field_footprint(+kind: Source.NativeFieldKind, +style: Source.ResolvedStyle) -> RuleSourceRules.native_field_footprint(kind, style):
  match kind:
    case Source.ToggleField{}:
      Source.ResolvedStyle{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
        Design.Chrome{foreground, background, border, border_width, radius, shadow}, states} = style
      {==}
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def position_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> RuleSourceRules.position_is_authored(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def border_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> RuleSourceRules.border_is_chrome(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main_alignment, cross_alignment, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def font_resolution(choice: Source.FontChoice, +parent: T.Presentation) -> RuleSourceRules.inherited_font(choice, parent):
  match choice:
    case Source.InheritFont{}: {==}
    case Source.ExplicitFont{presentation}: {==}

def event_ownership(+node: Source.Node) -> RuleSourceRules.operation_is_structurally_present(node):
  match node:
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}

def bounded_policy_factory(columns_extra: Nat, +lines_extra: Nat, additional_lines: Nat) ->
  RuleSourceRules.field_policy_is_bounded(Source.field_policy(columns_extra, lines_extra, additional_lines)):
  %Equal.sym(Bool, Nat.is_le(0n, columns_extra), True{}, ProofGeometryProof.zero_le(columns_extra)) :
    {_ && Nat.is_le(1n, 1n+lines_extra) && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(0n, lines_extra), True{}, ProofGeometryProof.zero_le(lines_extra)) :
    {True{} && _ && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)), True{},
    ProofGeometryProof.le_add(1n+lines_extra, additional_lines)) :
    {True{} && True{} && _ == True{} : Bool}
  {==}

def board_controls(visual: Design.Style, position: Composition.Position) -> RuleSourceRules.board_controls(visual, position): {==}

def board_stages(visual: Design.Style, position: Composition.Position) -> RuleSourceRules.board_stages(visual, position): {==}

def owned_information(+owner: UIIdentity.Key, +role: Information.TextRole, +value: String, +visual: Design.Style) -> RuleSourceRules.owned_information(owner, role, value, visual):
  match role:
    case Information.IntroductionTitle{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.SurfaceTitle{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.GroupTitle{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.FieldLabel{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.FieldValue{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.OptionLabel{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.NavigationCaption{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.Description{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}
    case Information.Status{}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      T.Presentation{tier, emphasis, scale} = text
      {==}


def heading_caption(key: UIIdentity.Key, label: String, visual: Design.Style) -> RuleSourceRules.heading_caption(key, label, visual):
  owned_information(key, Information.SurfaceTitle{}, label, visual)

def lane_style(key: UIIdentity.Key, label: String, stage: Board.Stage, count: Nat, visual: Design.Style, children: +List<Authored.Child>, parameters: Design.LayoutParameters) -> RuleSourceRules.lane_style(key, label, stage, count, visual, children, parameters): {==}

def parameter_source(+capacity: Nat, scale: T.Scale, key: String, minimum: Nat, preferred: Nat, height: Nat, advance: Nat, +primary: T.Metric, +support: T.Metric) -> RuleSourceRules.parameter_source(capacity, scale, key, minimum, preferred, height, advance, primary, support):
  T.Metric{primary_key, primary_minimum, primary_preferred, primary_height, primary_advance} = primary
  T.Metric{support_key, support_minimum, support_preferred, support_height, support_advance} = support
  {==}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat, primary_advance: Nat, support_advance: Nat) -> RuleSourceRules.parameter_calculations(capacity, scale, height, advance, primary_advance, support_advance): {==}

def page_region(+capacity: Nat, key: UIIdentity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.page_region(capacity, key, region, position, visual, control, children, parameters, content): {==}

def board_group(+capacity: Nat, key: UIIdentity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.board_group(capacity, key, label, grouping, visual, control, children, parameters, content): {==}

def confined_content_minimum(width: Nat, height: Nat) -> RuleSourceRules.confined_content_minimum(width, height): {==}

def board_group_content_minimum(+capacity: Nat, key: UIIdentity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> RuleSourceRules.board_group_content_minimum(capacity, key, label, grouping, visual, control, children, parameters, content, width, height):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def card_regions(+key: UIIdentity.Key, +face: View.CardFace, +visual: Design.Style, +children: +List<Authored.Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> RuleSourceRules.card_regions(key, face, visual, children, representation, parameters, movable):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  {==}

def fact_display_choice(empty: Bool, +value: String) -> {Authored.fact_display_choice(empty, value) == RuleSourceRules.expected_fact_value(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def fact_display_value(+value: String) -> RuleSourceRules.fact_display_value(value):
  fact_display_choice(String.eq(value, ""), value)

def fact_content(+key: UIIdentity.Key, +label: String, +value: String, +visual: Design.Style) -> RuleSourceRules.fact_content(key, label, value, visual):
  Equal.cong(String, Source.Node,
    (displayed => Authored.group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), Authored.text(UIIdentity.part(key, "value"), displayed, visual, T.Body{}, T.Regular{})])),
    Authored.fact_display_value(value), RuleSourceRules.expected_fact_value(String.eq(value, ""), value), fact_display_value(value))

def fact_source_dispatch(+capacity: Nat, key: UIIdentity.Key, label: String, role: SurfaceTypes.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.fact_source_dispatch(capacity, key, label, role, value, visual, representation, children, parameters, content): {==}

def user_width_choice(+full_width: Bool, +percent: Nat) -> {Factory.adaptive_width_cap(full_width, percent) == RuleSourceRules.adaptive_user_width_choice(full_width, percent) : Model.AxisSize}:
  match full_width:
    case True{}: {==}
    case False{}: {==}

def user_width_policy(+visual: Design.Style) -> {Factory.adaptive_natural_width(visual) == RuleSourceRules.adaptive_user_width(visual) : Model.AxisSize}:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +percent, states} = visual
  user_width_choice(Nat.is_eq(percent, 100n), percent)

def user_message_width(+visual: Design.Style) -> RuleSourceRules.user_message_width(visual):
  Equal.cong(Model.AxisSize, Source.Style,
    width => Factory.style(visual, width, Model.NaturalSize{}, Model.Confined{}),
    Factory.adaptive_natural_width(visual), RuleSourceRules.adaptive_user_width(visual), user_width_policy(visual))


def RuleSourceRules.placement_choices_empty(): {==}

def RuleSourceRules.placement_choices_available(target, label, input, rest): {==}

def RuleSourceRules.placement_choices_needs_directory_observation(target, label, input, rest): {==}

def RuleSourceRules.placement_choices_unavailable(target, label, input, reason, rest): {==}

def RuleSourceRules.movement_field_has_own_identity(key, destinations, face, name, handle, geometry, visual, parameters): {==}

def RuleSourceRules.movement_child_is_authored(key, role, destinations, face, control, nodes, rest): {==}

def RuleSourceRules.card_source_dispatch(capacity, key, label, role, face, visual, representation, children, parameters, content): {==}

def RuleSourceRules.movement_source_dispatch(capacity, key, label, role, destinations, face, visual, representation, children, parameters, content): {==}


def scalar_information(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +text_role: Information.TextRole, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.scalar_information(capacity, key, label, role, text_role, visual, representation, children, parameters, content):
  owned_information(key, text_role, label, visual)

def field_label(+key: UIIdentity.Key, +label: String, +visual: Design.Style, field: Source.Node) -> RuleSourceRules.field_label(key, label, visual, field):
  owned_information(key, Information.FieldLabel{}, label, visual)

def choice_leading_information(+enabled: Bool, +key: UIIdentity.Key, +label: String, +description: Maybe<&2, String>, +icon: Maybe<&2, Controls.Icon>, +selected: Bool, +visual: Design.Style, +geometry: Controls.Geometry, parameters: Design.LayoutParameters) ->
  {RuleSourceRules.option_text(AuthoredControls.choice_members(enabled, label, description, icon, selected, key, visual, geometry, parameters)) ==
    RuleSourceRules.information_observation(AuthoredControls.owned_text(key, Information.OptionLabel{}, label, visual)) : RuleSourceRules.InformationObservation}:
  match enabled:
    case True{}:
      match icon:
        case None{}: {==}
        case Some{glyph}: {==}
    case False{}:
      match icon:
        case None{}: {==}
        case Some{glyph}: {==}

def option_label(+key: UIIdentity.Key, +label: String, description: Maybe<&2, String>, +icon: Maybe<&2, Controls.Icon>, selected: Bool, +visual: Design.Style, geometry: Controls.Geometry, +parameters: Design.LayoutParameters) -> RuleSourceRules.option_label(key, label, description, icon, selected, visual, geometry, parameters):
  +owned_description: Maybe<&2, String> = description
  +owned_selected: Bool = selected
  +owned_geometry: Controls.Geometry = geometry
  Std.transport(RuleSourceRules.InformationObservation,
    RuleSourceRules.information_observation(AuthoredControls.owned_text(key, Information.OptionLabel{}, label, visual)),
    (observation => {observation == RuleSourceRules.required_information(key, Information.OptionLabel{}, label, visual) : RuleSourceRules.InformationObservation}),
    owned_information(key, Information.OptionLabel{}, label, visual),
    RuleSourceRules.option_text(AuthoredControls.face(key, Controls.ChoiceFace{label, owned_description, icon, owned_selected}, visual, owned_geometry, parameters)),
    choice_leading_information(T.is_activity(AuthoredControls.parent_font(visual)), key, label, owned_description, icon, owned_selected, visual, Controls.geometry_at(AuthoredControls.parent_font(visual), owned_geometry), parameters))

def option_description(+key: UIIdentity.Key, +value: String, +visual: Design.Style, parameters: Design.LayoutParameters) -> RuleSourceRules.option_description(key, value, visual, parameters):
  owned_information(key, Information.Description{}, value, visual)

def group_title(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.group_title(capacity, key, label, role, visual, representation, children, parameters, content):
  owned_information(key, Information.GroupTitle{}, label, visual)

def panel_title_unheaded(+key: UIIdentity.Key, +label: String, +visual: Design.Style, content: +List<Source.Node>) -> RuleSourceRules.panel_title_heading(False{}, key, label, visual, content):
  match label:
    case "": {==}
    case SCon{head, tail}: owned_information(key, Information.SurfaceTitle{}, label, visual)

def panel_title_heading(navigation: Bool, key: UIIdentity.Key, label: String, visual: Design.Style, content: +List<Source.Node>) -> RuleSourceRules.panel_title_heading(navigation, key, label, visual, content):
  match navigation:
    case True{}: {==}
    case False{}: panel_title_unheaded(key, label, visual, content)

def panel_title(+capacity: Nat, +key: UIIdentity.Key, +label: String, dismiss: InteractionTypes.Input, outside: Bool, escape: Bool, +visual: Design.Style, representation: Controls.Representation, +children: +List<Authored.Child>, parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> RuleSourceRules.panel_title(capacity, key, label, dismiss, outside, escape, visual, representation, children, parameters, content):
  panel_title_heading(Authored.has_activity_navigation(children), key, label, visual, content)

def dialog_title(+capacity: Nat, +key: UIIdentity.Key, +label: String, +visual: Design.Style, children: +List<Authored.Child>) -> RuleSourceRules.dialog_title(capacity, key, label, visual, children):
  owned_information(key, Information.SurfaceTitle{}, label, visual)

def owned_alignment(+owner: UIIdentity.Key, +role: Information.TextRole, value: String, visual: Design.Style) -> RuleSourceRules.owned_alignment(owner, role, value, visual):
  match role:
    case Information.IntroductionTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.SurfaceTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.GroupTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldValue{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.OptionLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.NavigationCaption{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Description{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Status{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}

def option_reference(+key: UIIdentity.Key, +label: String, +description: Maybe<&2, String>, icon: Maybe<&2, Controls.Icon>, selected: Bool) -> RuleSourceRules.option_reference(key, label, description, icon, selected):
  match description:
    case None{}: {==}
    case Some{text}: {==}

def compound_label(+key: UIIdentity.Key, +label: String, field: Forms.Field, +visual: Design.Style, children: +List<Source.Node>) -> RuleSourceRules.compound_label(key, label, field, visual, children):
  owned_information(key, Information.FieldLabel{}, label, visual)

def owned_width(owner: UIIdentity.Key, role: Information.TextRole, value: String, visual: Design.Style) -> {RuleSourceRules.information_width(AuthoredControls.owned_text(owner, role, value, visual)) == Some{Model.StretchSize{}} : Maybe<&2, Model.AxisSize>}:
  match role:
    case Information.IntroductionTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.SurfaceTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.GroupTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldValue{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.OptionLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.NavigationCaption{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Description{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Status{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}

def owned_foreground(+owner: UIIdentity.Key, +role: Information.TextRole, value: String, +visual: Design.Style) -> RuleSourceRules.owned_foreground(owner, role, value, visual):
  match role:
    case Information.IntroductionTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.SurfaceTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.GroupTitle{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.FieldValue{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.OptionLabel{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.NavigationCaption{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Description{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Status{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}

def experience_source(+capacity: Nat, +key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> RuleSourceRules.experience_source(capacity, key, label, role, meaning, visual, representation, children, parameters, content):
  match meaning:
    case SurfaceTypes.ActivityRow{row}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
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
    case SurfaceTypes.Activate{input, availability}: {==}
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: {==}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: {==}
    case SurfaceTypes.SearchChoices{query}: {==}
    case SurfaceTypes.ReceiveFile{editor, enabled}: {==}
    case SurfaceTypes.EnterDirectory{editor, text}: {==}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: {==}

def owned_group_source(+capacity: Nat, +key: UIIdentity.Key, +label: String, +visual: Design.Style, +attributes: +List<Source.Attribute>, +content: +List<Source.Node>) -> RuleSourceRules.owned_group_source(capacity, key, label, visual, attributes, content):
  {==}

def property_source(+editor: User.Editor, +field: Forms.Field, +key: UIIdentity.Key, entry: Forms.Entry, observed: Forms.Observed, choices: +List<Forms.ChoiceValue>) -> RuleSourceRules.property_source(editor, field, key, entry, observed, choices):
  {==}

def subject_source(+subject: UXTypes.Subject) -> RuleSourceRules.subject_source(subject):
  UXTypes.Subject{editor, field} = subject
  {==}

def selected_marker(+selected: Bool, +key: UIIdentity.Key, +visual: Design.Style, +size: Nat) -> RuleSourceRules.selected_marker(selected, key, visual, size):
  match selected:
    case True{}: {==}
    case False{}: {==}

def slot_emphasis(+scale: T.Scale) -> RuleSourceRules.slot_emphasis(scale):
  {==}

def member_source(+key: UIIdentity.Key, +collection: UXTypes.Collection, +path: String, +visual: Design.Style, parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> RuleSourceRules.member_source(key, collection, path, visual, parameters, content):
  {==}

def action_source(+key: UIIdentity.Key, +action: UXTypes.ActionUnit, +visual: Design.Style, +content: +List<Source.Node>) -> RuleSourceRules.action_source(key, action, visual, content):
  {==}

def feedback_source(+key: UIIdentity.Key, +feedback: UXTypes.Feedback, +visual: Design.Style, +content: +List<Source.Node>) -> RuleSourceRules.feedback_source(key, feedback, visual, content):
  UXTypes.Feedback{editor, revision, reason} = feedback
  {==}

def aggregate_focus(+visual: Design.Style) -> RuleSourceRules.aggregate_focus(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {==}

def grouped_menu_source(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +content: +List<Source.Node>) -> RuleSourceRules.grouped_menu_source(capacity, key, tag, style, attributes, content):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def support_source(visible: Bool, +key: UIIdentity.Key, +support: UXTypes.Support, +property: UXTypes.Property, +label: String, +visual: Design.Style, +representation: Controls.Representation, +parameters: Design.LayoutParameters) -> RuleSourceRules.support_source(visible, key, support, property, label, visual, representation, parameters):
  match visible:
    case False{}: {==}
    case True{}: {==}

def typed_action_style(+key: UIIdentity.Key, +action: UXTypes.ActionUnit, family: Controls.SourceFamily, representation: Controls.Representation, +visual: Design.Style, typography: T.Presentation) -> RuleSourceRules.typed_action_style(key, action, family, representation, visual, typography):
  {==}

def action_focus_states(+chrome: Design.Chrome, +states: Design.ControlStates) -> RuleSourceRules.action_focus_states(chrome, states):
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match states:
    case Design.Passive{}: {==}
    case Design.SurfaceFeedback{hover, pressed}: {==}
    case Design.Interactive{hover, pressed, opacity, focus}: {==}

def alternative_rest(+typography: T.Presentation) -> RuleSourceRules.alternative_rest(typography):
  T.Presentation{tier, emphasis, scale} = typography
  {==}

def alternative_states(+typography: T.Presentation) -> RuleSourceRules.alternative_states(typography):
  {==}

def object_source(+capacity: Nat, +key: UIIdentity.Key, +object: UXTypes.Object, +label: String, +visual: Design.Style, +content: +List<Source.Node>) -> RuleSourceRules.object_source(capacity, key, object, label, visual, content):
  {==}

def compound_directory_source(+field: Forms.Field, +value: Forms.Observed, +key: UIIdentity.Key, +label: String, +visual: Design.Style, +children: +List<Source.Node>) -> RuleSourceRules.compound_directory_source(field, value, key, label, visual, children):
  match field:
    case Forms.WorkspaceDirectories{}:
      match value:
        case Forms.WorkspaceValue{workspace}: {==}
        case Forms.ContextValue{preview, reviewers}:
          match preview:
            case Workspace.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: {==}
            case Workspace.ContextUnavailable{reason}: {==}
        case Forms.ToggleValue{enabled}: {==}
        case Forms.TextValue{text}: {==}
        case Forms.CountValue{count}: {==}
        case Forms.TextsValue{values}: {==}
        case Forms.ModelValue{profile, reasoning}: {==}
        case Forms.DeliveryValue{delivery}: {==}
        case Forms.StageValue{stage}: {==}
        case Forms.PriorityValue{priority}: {==}
        case Forms.OwnerValue{owner}: {==}
        case Forms.ProjectValue{project}: {==}
        case Forms.AttachmentsValue{files}: {==}
        case Forms.AssistanceValue{enabled, profile}: {==}
        case Forms.OptionalTextValue{text}: {==}
        case Forms.NotApplicable{}: {==}
    case Forms.MessageText{}: {==}
    case Forms.ProjectName{}: {==}
    case Forms.CreateWorktree{}: {==}
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

def directory_source(+capacity: Nat, +editor: User.Editor, +field: Forms.Field, value: Forms.Observed, choices: +List<Forms.ChoiceValue>, +key: UIIdentity.Key, label: String, role: SurfaceTypes.Role, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.directory_source(capacity, editor, field, value, choices, key, label, role, visual, representation, children, parameters, content):
  {==}

def RuleSourceRules.evidence():
  RuleSourceRules.Requirements{compound_directory_source, directory_source, object_source, support_source, typed_action_style, action_focus_states, alternative_rest, alternative_states, member_source, action_source, feedback_source, aggregate_focus, grouped_menu_source, experience_source, owned_group_source, property_source, subject_source, selected_marker, slot_emphasis, owned_alignment, owned_width, owned_foreground, +value => {==}, owned_information, scalar_information, field_label, option_label, option_description, group_title, panel_title, dialog_title, +key => {==}, option_reference, compound_label, role => area => {==}, selected => {==}, user_width_policy, user_message_width, fact_display_value, fact_content, fact_source_dispatch, native_field_footprint, card_regions, board_group_content_minimum, board_group, confined_content_minimum, page_region, parameter_calculations, board_controls, board_stages, heading_caption, lane_style, parameter_source, position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}
