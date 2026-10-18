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
import ./SPACE.bend as Space
import ./allocation-proof.bend as AllocationProof
import ../../bendlib/algebra-proof.bend as Alg

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
    case Doc.EditStructuredText{key}: {==}
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
    (is_content => Renderer.reading_styles(is_content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.properties(Renderer.visual(style), Renderer.inline_text_styles(style)))))),
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
    case Source.RangeField{minimum, maximum, step}: observation_appended(attributes, identity)
    case Source.DecimalField{minimum, maximum, step}: observation_appended(attributes, identity)
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

def rich_alignment(+key: Identity.Key, extent: E.Extent, rule: Model.Rule, children: +List<Doc.Node>) -> RulePhysicalControlRules.rich_alignment_claim(key, extent, rule, children):
  E.Extent{width, height} = extent
  Model.Rule{direction, main, cross, frame, border, width_rule, height_rule, minimum, scroll, position} = rule
  match direction:
    case Model.Horizontal{}:
      match main:
        case SpatialModel.Stretch{}: {==}
        case SpatialModel.Leading{}: {==}
        case SpatialModel.Trailing{}: {==}
        case SpatialModel.Centered{}: {==}
    case Model.ResponsiveHorizontal{}:
      match main:
        case SpatialModel.Stretch{}: {==}
        case SpatialModel.Leading{}: {==}
        case SpatialModel.Trailing{}: {==}
        case SpatialModel.Centered{}: {==}
    case Model.Vertical{}:
      match cross:
        case SpatialModel.Stretch{}: {==}
        case SpatialModel.Leading{}: {==}
        case SpatialModel.Trailing{}: {==}
        case SpatialModel.Centered{}: {==}
    case Model.Layered{}:
      match cross:
        case SpatialModel.Stretch{}: {==}
        case SpatialModel.Leading{}: {==}
        case SpatialModel.Trailing{}: {==}
        case SpatialModel.Centered{}: {==}

def container_alignment(+capacity: Nat, +value: Content.Value, +interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, +children: +List<Doc.Node>, +native: Bool) -> RulePhysicalControlRules.container_alignment_claim(capacity, value, interaction, styles, children, native):
  match value:
    case Content.Value{Source.Box{key, tag, +style, attrs, original}, font}:
      Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, source_font, chrome, states} = style
      match direction:
        case Model.Horizontal{}:
          match main:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.ResponsiveHorizontal{}:
          match main:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.Vertical{}:
          match cross:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.Layered{}:
          match cross:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
    case Content.Value{Source.Control{key, tag, +style, attrs, name, enabled, first, remaining, original}, font}:
      Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, source_font, chrome, states} = style
      match direction:
        case Model.Horizontal{}:
          match main:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.ResponsiveHorizontal{}:
          match main:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.Vertical{}:
          match cross:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
        case Model.Layered{}:
          match cross:
            case SpatialModel.Leading{}: {==}
            case SpatialModel.Trailing{}: {==}
            case SpatialModel.Centered{}: {==}
            case SpatialModel.Stretch{}: {==}
    case Content.Value{Source.Text{key, text, choice, wrapping}, font}: {==}
    case Content.Value{Source.Glyph{key, drawing, style}, font}: {==}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: {==}
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, original}, font}: {==}
    case Content.Value{Source.RichText{key, style, content, attachments, native_owner}, font}: {==}

def RulePhysicalControlRules.renderer_evidence():
  RulePhysicalControlRules.RendererRequirements{container_alignment, rich_alignment, key => dom_key => tag => attrs => styles => events => children => {==}, identity => dom_key => attrs => styles => events => input_key => input_attrs => input_styles => input_events => input_children => rest => {==}, owner => target => key => identity => native_target => attrs => style => original => font => interaction => rule => bounds => canvas => direction => children => {==}, leaf_observation, container_observation, reading_box, styles => {==}, styles => {==}, rich_parent, generation => key => tag => style => children => font => theme => {==}, admitted_world, rejected_world}

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

def owned_step_complete(+matches: Bool, +node: Doc.Node, +actual: +List<Doc.Node>, +expected: +List<Doc.Node>,
  same: {actual == expected : +List<Doc.Node>}) ->
  {Renderer.choose(+List<Doc.Node>, matches, node <> actual, actual) ==
    RulePhysicalControlRules.required_owned_step(matches, node, expected) : +List<Doc.Node>}:
  match matches:
    case True{}: Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (later => node <> later), actual, expected, same)
    case False{}: same

def owned_complete(+values: +List<Renderer.Owned>, +key: String) ->
  {Renderer.owned_nodes(values, key) == RulePhysicalControlRules.required_owned_nodes(values, key) : +List<Doc.Node>}:
  match values:
    case Nil{}: {==}
    case Con{Renderer.Owned{+owner, +node}, +rest}:
      owned_step_complete(String.eq(owner, key), node, Renderer.owned_nodes(rest, key),
        RulePhysicalControlRules.required_owned_nodes(rest, key), owned_complete(rest, key))

def required_owned_matches(+owner: String, +node: Doc.Node, +rest: +List<Renderer.Owned>, +key: String,
  matches: {String.eq(owner, key) == True{} : Bool}) ->
  {RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{owner, node} <> rest, key) ==
    node <> RulePhysicalControlRules.required_owned_nodes(rest, key) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>,
    (current => RulePhysicalControlRules.required_owned_step(current, node, RulePhysicalControlRules.required_owned_nodes(rest, key))),
    String.eq(owner, key), True{}, matches)

def required_owned_nonmatches(+owner: String, +node: Doc.Node, +rest: +List<Renderer.Owned>, +key: String,
  matches: {String.eq(owner, key) == False{} : Bool}) ->
  {RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{owner, node} <> rest, key) ==
    RulePhysicalControlRules.required_owned_nodes(rest, key) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>,
    (current => RulePhysicalControlRules.required_owned_step(current, node, RulePhysicalControlRules.required_owned_nodes(rest, key))),
    String.eq(owner, key), False{}, matches)

def required_owned_append_step(+matches: Bool, +node: Doc.Node, +actual: +List<Doc.Node>, +first: +List<Doc.Node>, +later: +List<Doc.Node>,
  same: {actual == List.append(&2, Doc.Node, first, later) : +List<Doc.Node>}) ->
  {RulePhysicalControlRules.required_owned_step(matches, node, actual) ==
    List.append(&2, Doc.Node, RulePhysicalControlRules.required_owned_step(matches, node, first), later) : +List<Doc.Node>}:
  match matches:
    case True{}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (values => node <> values), actual, List.append(&2, Doc.Node, first, later), same)
    case False{}: same

def required_owned_append(+first: +List<Renderer.Owned>, +later: +List<Renderer.Owned>, +key: String) ->
  {RulePhysicalControlRules.required_owned_nodes(List.append(&2, Renderer.Owned, first, later), key) ==
    List.append(&2, Doc.Node, RulePhysicalControlRules.required_owned_nodes(first, key), RulePhysicalControlRules.required_owned_nodes(later, key)) : +List<Doc.Node>}:
  match first:
    case Nil{}: {==}
    case Con{Renderer.Owned{+owner, +node}, +rest}:
      required_owned_append_step(String.eq(owner, key), node,
        RulePhysicalControlRules.required_owned_nodes(List.append(&2, Renderer.Owned, rest, later), key),
        RulePhysicalControlRules.required_owned_nodes(rest, key), RulePhysicalControlRules.required_owned_nodes(later, key),
        required_owned_append(rest, later, key))

def RulePhysicalControlRules.owned_nodes_complete(values, key): owned_complete(values, key)

def RulePhysicalControlRules.owned_nodes_empty(key): {==}

def RulePhysicalControlRules.owned_nodes_matching(owner, node, rest, key, matches):
  Equal.trans(+List<Doc.Node>, Renderer.owned_nodes(Renderer.Owned{owner, node} <> rest, key),
    RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{owner, node} <> rest, key),
    node <> RulePhysicalControlRules.required_owned_nodes(rest, key),
    owned_complete(Renderer.Owned{owner, node} <> rest, key), required_owned_matches(owner, node, rest, key, matches))

def RulePhysicalControlRules.owned_nodes_nonmatching(owner, node, rest, key, matches):
  Equal.trans(+List<Doc.Node>, Renderer.owned_nodes(Renderer.Owned{owner, node} <> rest, key),
    RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{owner, node} <> rest, key),
    RulePhysicalControlRules.required_owned_nodes(rest, key),
    owned_complete(Renderer.Owned{owner, node} <> rest, key), required_owned_nonmatches(owner, node, rest, key, matches))

def RulePhysicalControlRules.owned_nodes_concatenated(first, later, key):
  Equal.trans(+List<Doc.Node>, Renderer.owned_nodes(List.append(&2, Renderer.Owned, first, later), key),
    RulePhysicalControlRules.required_owned_nodes(List.append(&2, Renderer.Owned, first, later), key),
    List.append(&2, Doc.Node, RulePhysicalControlRules.required_owned_nodes(first, key), RulePhysicalControlRules.required_owned_nodes(later, key)),
    owned_complete(List.append(&2, Renderer.Owned, first, later), key), required_owned_append(first, later, key))

def RulePhysicalControlRules.owned_nodes_repeated(first_owner, first, second_owner, second, rest, key, first_matches, second_matches):
  Equal.trans(+List<Doc.Node>, Renderer.owned_nodes(Renderer.Owned{first_owner, first} <> Renderer.Owned{second_owner, second} <> rest, key),
    first <> RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{second_owner, second} <> rest, key),
    first <> second <> RulePhysicalControlRules.required_owned_nodes(rest, key),
    RulePhysicalControlRules.owned_nodes_matching(first_owner, first, Renderer.Owned{second_owner, second} <> rest, key, first_matches),
    Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (values => first <> values),
      RulePhysicalControlRules.required_owned_nodes(Renderer.Owned{second_owner, second} <> rest, key),
      second <> RulePhysicalControlRules.required_owned_nodes(rest, key), required_owned_matches(second_owner, second, rest, key, second_matches)))

def chart_sub_self(+value: Nat) -> {Nat.sub(value, value) == 0n : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: chart_sub_self(rest)

def chart_mul_one(+value: Nat) -> {Nat.mul(value, 1n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.mul(rest, 1n), rest, chart_mul_one(rest))

def chart_div_one_acc(+value: Nat, +count: Nat) ->
  {Nat.divmod.go(value, 0n, count, 0n) == (Nat.add(value, count), 0n) : (Nat & Nat)}:
  match value:
    case 0n: {==}
    case 1n+rest:
      Equal.trans(Nat & Nat, Nat.divmod.go(rest, 0n, 1n+count, 0n), (Nat.add(rest, 1n+count), 0n), (1n+Nat.add(rest, count), 0n),
        chart_div_one_acc(rest, 1n+count),
        Equal.cong(Nat, Nat & Nat, (n => (n, 0n)), Nat.add(rest, 1n+count), 1n+Nat.add(rest, count), Alg.nat_add_succ(rest, count)))

def chart_div_one(+value: Nat) -> {Nat.div(value, 1n) == value : Nat}:
  Equal.trans(Nat, Nat.div(value, 1n), Nat.add(value, 0n), value,
    Equal.cong(Nat & Nat, Nat, (pair => Pair.fst(Nat, Nat, pair)), Nat.divmod.go(value, 0n, 0n, 0n), (Nat.add(value, 0n), 0n), chart_div_one_acc(value, 0n)),
    Alg.nat_add_zero(value))

def RulePhysicalControlRules.chart_scroll_allocation(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width):
  # browser/layout/geometry-proof.zero_le
  %Equal.sym(Bool, Cmp.is_le(Nat.cmp(0n, Nat.sub(width, 0n))), True{}, ProofGeometryProof.zero_le(Nat.sub(width, 0n))) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Allocation.redistribute_first_first(Model.Tree<Content.Value, Doc.DOMEvent>, Space.feasible_pack(Allocation.Tagged<Model.Tree<Content.Value, Doc.DOMEvent>>, _, [Space.Slot{Allocation.Tagged{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Fill{0n}}, Space.Rigid{0n}}], 0n, Nat.sub(width, 0n)), 1n, 0n, Nat.sub(width, 0n)), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/render-proof.chart_div_one
  %Equal.sym(Nat, Pair.fst(Nat, Nat, Nat.divmod.go(Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n), 0n, 0n, 0n)), Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n), chart_div_one(Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n))) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n), Nat.mul(_, 1n)), 0n)))), Nat.sub(width, 0n))), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n), Nat.mul(_, 1n)), 0n))))}}], 0n, Nat.sub(width, 0n)), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/allocation-proof.subtract_zero
  %Equal.sym(Nat, Nat.sub(Nat.sub(Nat.sub(width, 0n), 0n), 0n), Nat.sub(Nat.sub(width, 0n), 0n), AllocationProof.subtract_zero(Nat.sub(Nat.sub(width, 0n), 0n))) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n)))), Nat.sub(width, 0n))), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n))))}}], 0n, Nat.sub(width, 0n)), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/allocation-proof.subtract_zero
  %Equal.sym(Nat, Nat.sub(Nat.sub(width, 0n), 0n), Nat.sub(width, 0n), AllocationProof.subtract_zero(Nat.sub(width, 0n))) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n)))), Nat.sub(width, 0n))), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n))))}}], 0n, Nat.sub(width, 0n)), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/allocation-proof.subtract_zero
  %Equal.sym(Nat, Nat.sub(width, 0n), width, AllocationProof.subtract_zero(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n)))), _)), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(_, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(_, Nat.mul(_, 1n)), 0n))))}}], 0n, _), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/render-proof.chart_mul_one
  %Equal.sym(Nat, Nat.mul(width, 1n), width, chart_mul_one(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(width, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(width, _), 0n)))), width)), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(width, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(Nat.sub(width, _), 0n))))}}], 0n, width), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/render-proof.chart_sub_self
  %Equal.sym(Nat, Nat.sub(width, width), 0n, chart_sub_self(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(Nat.add(width, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(_, 0n)))), width)), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{Nat.add(width, Allocation.dispatch_surplus_extra_1(Cmp.is_eq(Nat.cmp(_, 0n))))}}], 0n, width), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # bendlib/algebra-proof.nat_add_zero
  %Equal.sym(Nat, Nat.add(width, 0n), width, Alg.nat_add_zero(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, Cmp.is_le(Nat.cmp(_, width)), [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{_}}], 0n, width), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/geometry-proof.le_refl
  %Equal.sym(Bool, Cmp.is_le(Nat.cmp(width, width)), True{}, ProofGeometryProof.le_refl(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.dispatch_fit_width_16(Content.Value, Doc.DOMEvent, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, _, [Space.Slot{RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), Space.Rigid{width}}], 0n, width), RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), []), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/geometry-proof.zero_le
  %Equal.sym(Bool, Cmp.is_le(Nat.cmp(0n, width)), True{}, ProofGeometryProof.zero_le(width)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.finish_width_iteration(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.WidthMinimumChecked{_, RulePhysicalControlRules.chart_tree(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values), width, 0n, RulePhysicalControlRules.chart_viewport_rule, 0n, Allocation.WidthRootReturn{}}, []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), viewport_key, width, 22n), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/geometry-proof.max_right
  %Equal.sym(Bool, Cmp.is_le(Nat.cmp(480n, Nat.max(Nat.sub(width, 0n), 480n))), True{}, ProofGeometryProof.max_right(Nat.sub(width, 0n), 480n)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.finish_width_iteration(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.WidthContainerPlan{Allocation.dispatch_prepare_inline_children_11(Content.Value, Doc.DOMEvent, Allocation.dispatch_prepare_slots_9(Model.Tree<Content.Value, Doc.DOMEvent>, Allocation.redistribute_first_first(Model.Tree<Content.Value, Doc.DOMEvent>, Space.feasible_pack(Allocation.Tagged<Model.Tree<Content.Value, Doc.DOMEvent>>, _, [Space.Slot{Allocation.Tagged{Model.Container{canvas_key, canvas, Model.DisplayOnly{}, RulePhysicalControlRules.chart_canvas_rule, [Model.Leaf{axes_key, axes, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}}, Model.Leaf{values_key, values, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}}]}, Space.Rigid{480n}}, Space.Rigid{480n}}], 0n, Nat.max(Nat.sub(width, 0n), 480n)), 0n, 0n, Nat.max(Nat.sub(width, 0n), 480n)), viewport_key, Allocation.InlineAxis{}, SpatialModel.Leading{}, Nat.max(Nat.sub(width, 0n), 480n)), Allocation.Horizontal{}), viewport_key, viewport, Model.DisplayOnly{}, RulePhysicalControlRules.chart_viewport_rule, width, 0n, Allocation.WidthRootReturn{}}, []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), viewport_key, width, 22n), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/geometry-proof.max_right
  %Equal.sym(Bool, Cmp.is_le(Nat.cmp(480n, Nat.max(Nat.sub(width, 0n), 480n))), True{}, ProofGeometryProof.max_right(Nat.sub(width, 0n), 480n)) :
    {Allocation.dispatch_allocate_22(Content.Value, Doc.DOMEvent, Allocation.finish_width_iteration(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.width_step(Content.Value, Doc.DOMEvent, Allocation.WidthContainerPlan{Allocation.dispatch_prepare_inline_children_11(Content.Value, Doc.DOMEvent, Allocation.dispatch_prepare_slots_9(Model.Tree<Content.Value, Doc.DOMEvent>, Space.feasible_pack(Model.Tree<Content.Value, Doc.DOMEvent>, _, [Space.Slot{Model.Container{canvas_key, canvas, Model.DisplayOnly{}, RulePhysicalControlRules.chart_canvas_rule, [Model.Leaf{axes_key, axes, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}}, Model.Leaf{values_key, values, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}}]}, Space.Rigid{480n}}], 0n, Nat.max(Nat.sub(width, 0n), 480n)), viewport_key, Allocation.InlineAxis{}, SpatialModel.Leading{}, Nat.max(Nat.sub(width, 0n), 480n)), Allocation.Horizontal{}), viewport_key, viewport, Model.DisplayOnly{}, RulePhysicalControlRules.chart_viewport_rule, width, 0n, Allocation.WidthRootReturn{}}, []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), []), viewport_key, width, 22n), SpatialModel.Box{0n, 0n, width, 240n}) == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  # browser/layout/allocation-proof.subtract_zero
  %Equal.sym(Nat, Nat.sub(width, 0n), width, AllocationProof.subtract_zero(width)) :
    {Allocation.Allocated{Allocation.AllocatedContainer{viewport_key, viewport, Model.DisplayOnly{}, RulePhysicalControlRules.chart_viewport_rule, SpatialModel.Box{0n, 0n, width, 240n}, E.Extent{Nat.max(_, 480n), 240n}, Allocation.Horizontal{}, [Allocation.AllocatedContainer{canvas_key, canvas, Model.DisplayOnly{}, RulePhysicalControlRules.chart_canvas_rule, SpatialModel.Box{0n, 0n, 480n, 240n}, E.Extent{480n, 240n}, Allocation.Layered{}, [Allocation.AllocatedLeaf{axes_key, axes, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}, SpatialModel.Box{0n, 0n, 480n, 240n}, E.Extent{480n, 240n}}, Allocation.AllocatedLeaf{values_key, values, Model.DisplayOnly{}, RulePhysicalControlRules.chart_glyph_rule, Space.Demand{E.Extent{480n, 240n}, E.Extent{480n, 240n}}, Model.FixedHeight{240n}, SpatialModel.Box{0n, 0n, 480n, 240n}, E.Extent{480n, 240n}}]}]}} == Allocation.Allocated{RulePhysicalControlRules.allocated_chart(viewport_key, canvas_key, axes_key, values_key, viewport, canvas, axes, values, width)} : Allocation.Outcome<Content.Value, Doc.DOMEvent>}
  {==}
