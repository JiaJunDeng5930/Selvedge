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

def parameter_source(+capacity: Nat, scale: T.Scale, key: String, minimum: Nat, preferred: Nat, height: Nat, advance: Nat) -> RuleSourceRules.parameter_source(capacity, scale, key, minimum, preferred, height, advance): {==}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat) -> RuleSourceRules.parameter_calculations(capacity, scale, height, advance): {==}

def page_region(key: UIIdentity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.page_region(key, region, position, visual, control, children, parameters, content): {==}

def board_group(key: UIIdentity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.board_group(key, label, grouping, visual, control, children, parameters, content): {==}

def confined_content_minimum(width: Nat, height: Nat) -> RuleSourceRules.confined_content_minimum(width, height): {==}

def board_group_content_minimum(key: UIIdentity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> RuleSourceRules.board_group_content_minimum(key, label, grouping, visual, control, children, parameters, content, width, height):
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

def fact_source_dispatch(key: UIIdentity.Key, label: String, role: SurfaceTypes.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.fact_source_dispatch(key, label, role, value, visual, representation, children, parameters, content): {==}

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


def RuleSourceRules.movement_field_has_own_identity(key, destinations, face, name, handle, geometry, visual, parameters): {==}

def RuleSourceRules.movement_child_is_authored(key, role, destinations, face, control, nodes, rest): {==}

def RuleSourceRules.card_source_dispatch(key, label, role, face, visual, representation, children, parameters, content): {==}

def RuleSourceRules.movement_source_dispatch(key, label, role, destinations, face, visual, representation, children, parameters, content): {==}


def scalar_information(+key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +text_role: Information.TextRole, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.scalar_information(key, label, role, text_role, visual, representation, children, parameters, content):
  owned_information(key, text_role, label, visual)

def field_label(+key: UIIdentity.Key, +label: String, +visual: Design.Style, field: Source.Node) -> RuleSourceRules.field_label(key, label, visual, field):
  owned_information(key, Information.FieldLabel{}, label, visual)

def option_label(+key: UIIdentity.Key, +label: String, description: Maybe<&2, String>, +icon: Maybe<&2, Controls.Icon>, selected: Bool, +visual: Design.Style, geometry: Controls.Geometry) -> RuleSourceRules.option_label(key, label, description, icon, selected, visual, geometry):
  match icon:
    case None{}: owned_information(key, Information.OptionLabel{}, label, visual)
    case Some{glyph}: owned_information(key, Information.OptionLabel{}, label, visual)

def option_description(+key: UIIdentity.Key, +value: String, +visual: Design.Style) -> RuleSourceRules.option_description(key, value, visual):
  owned_information(key, Information.Description{}, value, visual)

def group_title(+key: UIIdentity.Key, +label: String, +role: SurfaceTypes.Role, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.group_title(key, label, role, visual, representation, children, parameters, content):
  owned_information(key, Information.GroupTitle{}, label, visual)

def panel_title(+key: UIIdentity.Key, +label: String, dismiss: InteractionTypes.Input, outside: Bool, escape: Bool, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.panel_title(key, label, dismiss, outside, escape, visual, representation, children, parameters, content):
  owned_information(key, Information.SurfaceTitle{}, label, visual)

def dialog_title(+key: UIIdentity.Key, +label: String, +visual: Design.Style, children: +List<Authored.Child>) -> RuleSourceRules.dialog_title(key, label, visual, children):
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
    case Information.Description{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}
    case Information.Status{}:
      Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
      {==}

def RuleSourceRules.evidence():
  RuleSourceRules.Requirements{owned_alignment, owned_width, owned_foreground, +value => {==}, owned_information, scalar_information, field_label, option_label, option_description, group_title, panel_title, dialog_title, +key => {==}, option_reference, compound_label, role => area => {==}, selected => {==}, user_width_policy, user_message_width, fact_display_value, fact_content, fact_source_dispatch, native_field_footprint, card_regions, board_group_content_minimum, board_group, confined_content_minimum, page_region, parameter_calculations, board_controls, board_stages, heading_caption, lane_style, parameter_source, position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}
