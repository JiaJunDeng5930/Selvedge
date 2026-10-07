import Base
import ../physical-renderer-rules.bend as Rule
import ../physical-renderer.bend as Renderer
import ../physical-content.bend as Content
import ../physical-allocation.bend as Allocation
import ../source.bend as Source
import ../document.bend as Doc
import ../typography.bend as T
import ../paint-rules.bend as PaintRule
import ../physical-space.bend as Model
import ../spatial.bend as Spatial
import ../enclosure.bend as Enclosure
import ../../core/ui-identity.bend as Identity

def rich_parent(+capacity: Nat, +font: T.Presentation, policy: Source.RichPolicy) ->
  {Rule.text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))}:
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
  Rule.reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content):
  Equal.cong(Bool, +List<Doc.Property>,
    (is_content => Renderer.reading_styles(is_content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style))))),
    Renderer.reading_content(attrs), content, recognized)

def observation_appended(attrs: +List<Doc.Property>, +key: String) ->
  {Rule.last_attribute(Renderer.properties(attrs, [Doc.Property{"data-frame-key", key}])) == Some{Doc.Property{"data-frame-key", key}} : Maybe<&2, Doc.Property>}:
  match attrs:
    case Nil{}: {==}
    case Con{first, rest}:
      match rest:
        case Nil{}: {==}
        case Con{next, tail}: observation_appended(Con{next, tail}, key)

def field_observation(+kind: Source.NativeFieldKind, +key: Identity.Key, +style: Source.Style,
  +attrs: +List<Source.Attribute>, attributes: +List<Doc.Property>, +styles: +List<Doc.Property>, events: +List<Doc.DOMEvent>, children: +List<Doc.Node>, +identity: String) ->
  {Rule.field_observation(kind, Renderer.observed_field(kind, identity, Renderer.native_field_leaf(kind, key, style, attrs, attributes, styles, events, children))) == Some{Doc.Property{"data-frame-key", identity}} : Maybe<&2, Doc.Property>}:
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

def leaf_observation(+capacity: Nat, +value: Content.Value, physical_key: String, bounds: Spatial.Box,
  canvas: Enclosure.Extent, +rule: Model.Rule, +interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) ->
  Rule.leaf_observation_claim(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned):
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
  Rule.container_observation_claim(capacity, value, interaction, styles, children, native):
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

def Rule.evidence():
  Rule.Requirements{key => dom_key => tag => attrs => styles => events => children => {==}, identity => dom_key => attrs => styles => events => input_key => input_attrs => input_styles => input_events => input_children => rest => {==}, owner => target => key => identity => native_target => attrs => style => original => font => interaction => rule => bounds => canvas => direction => children => {==}, leaf_observation, container_observation, reading_box, styles => {==}, styles => {==}, rich_parent, generation => key => tag => style => children => font => theme => {==}, admitted_world, rejected_world}
