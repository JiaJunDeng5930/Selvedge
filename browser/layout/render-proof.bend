import Base
import ../document/SOURCE.bend as Source
import ./physical-space.bend as Model
import ../document/MODEL.bend as Doc
import ./render-contract.bend as RulePhysicalControlRules
import ../../interaction/IDENTITY.bend as Identity
import ../appearance/TYPOGRAPHY.bend as T
import ../appearance/DESIGN.bend as D
import ./geometry-proof.bend as ProofGeometryProof
import ../controls/PROGRAM.bend as C
import ./RENDERER.bend as Renderer
import ../appearance/CONTRACT.bend as PaintRule
import ./CONTENT.bend as Content
import ./PROGRAM.bend as Allocation
import ./GEOMETRY.bend as SpatialModel
import ./enclosure.bend as E
import ./SOURCE.bend as SourceSource

def attributes_consume_control_states(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String,
  interaction: Model.Interaction<Doc.DOMEvent>) -> RulePhysicalControlRules.control_attributes_claim(tag, attrs, name, interaction):
  {==}

def rendered_controls_consume_control_states(key: Identity.Key, tag: Source.ControlTag, style: Source.Style,
  attrs: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.DOMEvent,
  remaining: +List<Doc.DOMEvent>, original_children: +List<Source.Node>, font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool) ->
  RulePhysicalControlRules.control_render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native):
  {==}

def background_uses_rest_channel(chrome: D.Chrome) -> RulePhysicalControlRules.background_channel_claim(chrome):
  D.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def foreground_uses_rest_channel(chrome: D.Chrome) -> RulePhysicalControlRules.foreground_channel_claim(chrome):
  D.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def RulePhysicalControlRules.control_evidence():
  RulePhysicalControlRules.ControlRequirements{background_uses_rest_channel, foreground_uses_rest_channel, attributes_consume_control_states, rendered_controls_consume_control_states}

def RulePhysicalControlRules.keyboard_activation_total(event):
  match event:
    case Doc.Activate{key}: {==}
    case Doc.EditText{key}: {==}
    case Doc.ConfirmText{key}: {==}
    case Doc.EditToggle{key}: {==}
    case Doc.SelectFiles{key}: {==}
    case Doc.DragCard{key}: {==}
    case Doc.DropCard{key}: {==}
    case Doc.PlaceCard{key, target}: {==}
    case Doc.SelectDestination{key}: {==}

def RulePhysicalControlRules.keyboard_activation_empty(): {==}

def RulePhysicalControlRules.keyboard_activation_cons(ProofGeometryProof.first,remaining): {==}

def RulePhysicalControlRules.keyboard_control_display_only(): {==}

def RulePhysicalControlRules.keyboard_control_operable(ProofGeometryProof.first,remaining,enabled): {==}

def RulePhysicalControlRules.keyboard_attribute_projection(active,interaction,name):
  match active:
    case True{}: {==}
    case False{}: {==}

def RulePhysicalControlRules.nonnative_attribute_projection(attrs,name,interaction): {==}

def RulePhysicalControlRules.control_attribute_projection(tag,attrs,name,interaction):
  match tag:
    case Source.Button{}: {==}
    case Source.Summary{}: {==}
    case Source.ArticleControl{}: {==}
    case Source.DivControl{}: {==}
    case Source.SectionControl{}: {==}
    case Source.SpanControl{}: {==}

def RulePhysicalControlRules.source_control_interaction(key,tag,style,attrs,name,enabled,ProofGeometryProof.first,remaining,children): {==}

def RulePhysicalControlRules.rendered_control_projection(capacity,key,tag,style,attrs,name,enabled,ProofGeometryProof.first,remaining,original_children,font,interaction,styles,children,native): {==}

def RulePhysicalControlRules.native_field_probe_appearance(kind): {==}

def RulePhysicalControlRules.native_field_rendered_appearance(kind, rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def RulePhysicalControlRules.toggle_field_probe_appearance(): {==}

def RulePhysicalControlRules.toggle_field_rendered_appearance(rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def RulePhysicalControlRules.other_native_field_appearance(minimum, multiple): {==}

def RulePhysicalControlRules.toggle_geometry_bounded(): {==}

def RulePhysicalControlRules.toggle_geometry_centered(): {==}

def RulePhysicalControlRules.toggle_probe_rectangle(): {==}

def RulePhysicalControlRules.toggle_target_rectangle(): {==}

def RulePhysicalControlRules.toggle_visual_rectangle(style):
  Source.Style{layout, font, D.Chrome{foreground, background, border, width, radius, shadow}, states} = style
  {==}

def RulePhysicalControlRules.production_toggle_face(key, meaning, name, placement, availability, typography, parameters):
  match placement:
    case C.AccessibleOnly{}: {==}
    case C.AboveInput{}: {==}
    case C.BesideInput{}: {==}

def RulePhysicalControlRules.unchecked_toggle_glyph(key): {==}

def RulePhysicalControlRules.toggle_authoring_allocation(key, meaning, name, placement, availability, visual, parameters):
  match placement visual:
    case C.AccessibleOnly{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case C.AboveInput{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case C.BesideInput{} D.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}

def RulePhysicalControlRules.beside_label_activation(key, name, visual, field):
  D.Style{text, D.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def RulePhysicalControlRules.toggle_rendered_composition(key, style, attrs, attributes, styles, events, children): {==}

def RulePhysicalControlRules.measurement_probe_targets(request, roots): {==}

def RulePhysicalControlRules.native_target_probe_targets(request, roots): {==}

def rich_parent(+capacity: Nat, +font: T.Presentation, policy: Source.RichPolicy) ->
  {RulePhysicalControlRules.text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))}:
  match policy:
    case Source.RichPolicy{Source.CodeSurface{frame, surface}, toolbar, gap, indent, code, wrap}: {==}

def admitted_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, valid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), True{}, valid)

def rejected_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, invalid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), False{}, invalid)

def reading_box(+capacity: Nat, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool,
  recognized: {Renderer.reading_content(attrs) == content : Bool}) ->
  RulePhysicalControlRules.reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content):
  Equal.cong(Bool, +List<Doc.Property>,
    (is_content => Renderer.reading_styles(is_content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style))))),
    Renderer.reading_content(attrs), content, recognized)

def observation_appended(attrs: +List<Doc.Property>, +key: String) ->
  {RulePhysicalControlRules.last_attribute(Renderer.properties(attrs, [Doc.Property{"data-frame-key", key}])) == Some{Doc.Property{"data-frame-key", key}} : Maybe<&2, Doc.Property>}:
  match attrs:
    case Nil{}: {==}
    case Con{first, rest}:
      match rest:
        case Nil{}: {==}
        case Con{next, tail}: observation_appended(Con{next, tail}, key)

def field_observation(+kind: Source.NativeFieldKind, +key: Identity.Key, +style: Source.Style,
  +attrs: +List<Source.Attribute>, attributes: +List<Doc.Property>, +styles: +List<Doc.Property>, events: +List<Doc.DOMEvent>, children: +List<Doc.Node>, +identity: String) ->
  {RulePhysicalControlRules.field_observation(kind, Renderer.observed_field(kind, identity, Renderer.native_field_leaf(kind, key, style, attrs, attributes, styles, events, children))) == Some{Doc.Property{"data-frame-key", identity}} : Maybe<&2, Doc.Property>}:
  match kind:
    case Source.TextField{}: observation_appended(attributes, identity)
    case Source.MessageField{}: observation_appended(attributes, identity)
    case Source.TextAreaField{}: observation_appended(attributes, identity)
    case Source.SelectField{}: observation_appended(attributes, identity)
    case Source.MultiSelectField{}: observation_appended(attributes, identity)
    case Source.NumberField{minimum}: observation_appended(attributes, identity)
    case Source.FileField{multiple}: observation_appended(attributes, identity)
    case Source.DirectoryField{}: observation_appended(attributes, identity)
    case Source.SearchField{}: observation_appended(attributes, identity)
    case Source.SecretField{}: observation_appended(attributes, identity)
    case Source.ToggleField{}: observation_appended(attributes, identity)

def leaf_observation(+capacity: Nat, +value: Content.Value, physical_key: String, bounds: SpatialModel.Box,
  canvas: E.Extent, +rule: Model.Rule, +interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) ->
  RulePhysicalControlRules.leaf_observation_claim(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned):
  match value:
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: observation_appended(Renderer.text_attributes(wrap, text), Renderer.observation_key(value))
    case Content.Value{Source.Glyph{key, picture, style}, font}: {==}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}:
      match content:
        case Source.RichContent{source, text, policy}: {==}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}:
      field_observation(kind, key, style, attrs,
        Renderer.properties(Renderer.field_authored(kind, attrs), Renderer.properties(Renderer.field_attributes(kind, text),
          Renderer.properties([Doc.Property{"class", "native-control"}, Doc.Property{"placeholder", placeholder}, Doc.Property{"aria-label", name}], Renderer.availability(interaction, True{})))),
        Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), Renderer.properties(Renderer.visual(style), Renderer.field_padding(kind, rule)))),
        Renderer.event_list(interaction), Renderer.choices(options, key), Renderer.observation_key(value))
    case Content.Value{Source.Box{key, tag, style, attrs, children}, font}: {==}
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, font}: {==}
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, children}, font}: {==}

def container_observation(+capacity: Nat, +value: Content.Value, interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, +native: Bool) ->
  RulePhysicalControlRules.container_observation_claim(capacity, value, interaction, styles, children, native):
  match value:
    case Content.Value{Source.Box{key, tag, style, attrs, original}, font}: observation_appended(Renderer.attributes(attrs), Renderer.observation_key(value))
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, original}, font}: observation_appended(Renderer.control_attributes(tag, attrs, name, interaction), Renderer.observation_key(value))
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, original}, font}:
      match native:
        case True{}: {==}
        case False{}: {==}
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: {==}
    case Content.Value{Source.Glyph{key, picture, style}, font}: {==}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}: {==}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: {==}

def RulePhysicalControlRules.renderer_evidence():
  RulePhysicalControlRules.RendererRequirements{key => dom_key => tag => attrs => styles => events => children => {==}, identity => dom_key => attrs => styles => events => input_key => input_attrs => input_styles => input_events => input_children => rest => {==}, owner => target => key => identity => native_target => attrs => style => original => font => interaction => rule => bounds => canvas => direction => children => {==}, leaf_observation, container_observation, reading_box, styles => {==}, styles => {==}, rich_parent, generation => key => tag => style => children => font => theme => {==}, admitted_world, rejected_world}

def measured_minimum_bound(+observation: Content.Observation) ->
  {Nat.is_le(RulePhysicalControlRules.minimum_width(SourceSource.text_natural_demand(T.SingleLine{}, observation)), SourceSource.observation_advance(observation)) == True{} : Bool}:
  ProofGeometryProof.min_le_second(SourceSource.observation_minimum(observation), SourceSource.observation_advance(observation))

def natural_preferred_bound(+observation: Content.Observation) ->
  {Nat.is_le(SourceSource.observation_preferred(observation), RulePhysicalControlRules.preferred_width(SourceSource.text_natural_demand(T.SingleLine{}, observation))) == True{} : Bool}:
  ProofGeometryProof.max_right(Nat.min(SourceSource.observation_minimum(observation), SourceSource.observation_advance(observation)), SourceSource.observation_preferred(observation))

def demand_policy(+wrapping: T.Wrapping, +observation: Content.Observation) -> RulePhysicalControlRules.demand_claim(wrapping, observation):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.UnbrokenLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def attributes_policy(+wrapping: T.Wrapping, +text: String) -> RulePhysicalControlRules.text_space_attributes_claim(wrapping, text):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.UnbrokenLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def RulePhysicalControlRules.text_space_evidence():
  RulePhysicalControlRules.TextSpaceRequirements{
    measured_minimum_bound,
    natural_preferred_bound,
    demand_policy,
    label => text => choice => +wrapping => key => font => rule => +observation => roots => policies => {==},
    +capacity => +key => +text => choice => font => bounds => canvas => rule => interaction => styles => owned => {==},
    attributes_policy}

def RulePhysicalControlRules.unbroken_width(observation): {==}

def RulePhysicalControlRules.unbroken_dimensions(observation): {==}

def RulePhysicalControlRules.unbroken_height(key,height): {==}

def RulePhysicalControlRules.unbroken_render(capacity,key,text,choice,font,bounds,ProofGeometryProof.canvas,rule,interaction,styles,owned): {==}

def RulePhysicalControlRules.unbroken_metric(metric):
  match metric:
    case T.Metric{key,minimum,preferred,height,advance}: {==}
