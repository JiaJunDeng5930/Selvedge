import Base
import ./physical-renderer.bend as Renderer
import ./physical-content.bend as Content
import ./physical-allocation.bend as Allocation
import ./source.bend as Source
import ./document.bend as Doc
import ./typography.bend as T
import ./paint.bend as Paint
import ./paint-rules.bend as PaintRule
import ./authored-shell.bend as Shell
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./physical-space.bend as Model
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ../core/ui-identity.bend as Identity

def text_properties(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (PaintRule.property_value(values, "font-family"), (PaintRule.property_value(values, "font-size"),
    (PaintRule.property_value(values, "line-height"), PaintRule.property_value(values, "font-weight"))))

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def reading_box_claim(+capacity: Nat, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool) -> Type:
  {node_styles(Renderer.container_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}, interaction, styles, children, native)) ==
    Renderer.reading_styles(content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style)))) : +List<Doc.Property>}

def last_attribute(values: +List<Doc.Property>) -> Maybe<&2, Doc.Property>:
  match values:
    case Nil{}: None{}
    case Con{first, Nil{}}: Some{first}
    case Con{first, rest}: last_attribute(rest)

def observation(node: Doc.Node) -> Maybe<&2, Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: last_attribute(attrs)
    case _: None{}


# The carrier is the native control, including the input inside toggle drawing.
def field_observation(+kind: Source.NativeFieldKind, node: Doc.Node) -> Maybe<&2, Doc.Property>:
  match kind:
    case Source.ToggleField{}:
      match node:
        case Doc.Element{key, "span", Nil{}, styles, events, Con{Doc.Element{input_key, "input", attrs, input_styles, input_events, input_children}, rest}}:
          last_attribute(attrs)
        case _: None{}
    case Source.TextField{}: observation(node)
    case Source.MessageField{}: observation(node)
    case Source.TextAreaField{}: observation(node)
    case Source.SelectField{}: observation(node)
    case Source.MultiSelectField{}: observation(node)
    case Source.NumberField{minimum}: observation(node)
    case Source.FileField{multiple}: observation(node)
    case Source.DirectoryField{}: observation(node)
    case Source.SearchField{}: observation(node)
    case Source.SecretField{}: observation(node)

def native_carrier_attributes(value: Renderer.Owned) -> +List<Doc.Property>:
  match value:
    case Renderer.Owned{owner, Doc.TargetProperties{key, target, attrs, styles}}: attrs
    case _: Nil{}

def leaf_observation_claim(+capacity: Nat, +value: Content.Value, physical_key: String, bounds: Spatial.Box,
  canvas: Enclosure.Extent, rule: Model.Rule, interaction: Model.Interaction<Doc.Event>, styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) -> Type:
  match value:
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Glyph{key, picture, style}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: {field_observation(kind, Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case _: {True{} == True{} : Bool}

def container_observation_claim(+capacity: Nat, +value: Content.Value, interaction: Model.Interaction<Doc.Event>, styles: +List<Doc.Property>, children: +List<Doc.Node>, +native: Bool) -> Type:
  match value:
    case Content.Value{Source.Box{key, tag, style, attrs, original}, font}: {observation(Renderer.container_at(capacity, value, interaction, styles, children, native)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, original}, font}: {observation(Renderer.container_at(capacity, value, interaction, styles, children, native)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, original}, font}:
      match native:
        case True{}: {Renderer.container_at(capacity, value, interaction, styles, children, native) == Doc.Element{Identity.encode(key), "div", Nil{}, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), Renderer.visual(style))), Nil{}, children} : Doc.Node}
        case False{}: {True{} == True{} : Bool}
    case _: {True{} == True{} : Bool}

type Requirements is Type:
  Requirements{
    observed_element: @key:String -> @dom_key:String -> @tag:String -> @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.Event> -> @children:+List<Doc.Node> ->
      {Renderer.observed(key, Doc.Element{dom_key, tag, attrs, styles, events, children}) == Doc.Element{dom_key, tag, Renderer.properties(attrs, [Doc.Property{"data-frame-key", key}]), styles, events, children} : Doc.Node},
    observed_toggle: @identity:String -> @dom_key:String -> @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.Event> -> @input_key:String -> @input_attrs:+List<Doc.Property> -> @input_styles:+List<Doc.Property> -> @input_events:+List<Doc.Event> -> @input_children:+List<Doc.Node> -> @rest:+List<Doc.Node> ->
      {Renderer.observed_field(Source.ToggleField{}, identity, Doc.Element{dom_key, "span", attrs, styles, events, Con{Doc.Element{input_key, "input", input_attrs, input_styles, input_events, input_children}, rest}}) ==
        Doc.Element{dom_key, "span", attrs, styles, events, Con{Doc.Element{input_key, "input", Renderer.properties(input_attrs, [Doc.Property{"data-frame-key", identity}]), input_styles, input_events, input_children}, rest}} : Doc.Node},
    native_attachment_carrier: @owner:String -> @target:Source.NativeTarget -> @key:String -> @+identity:Identity.Key -> @+native_target:Source.NativeTarget -> @+attrs:+List<Source.Attribute> -> @+style:Source.Style -> @+original:+List<Source.Node> -> @+font:T.Presentation -> @interaction:Model.Interaction<Doc.Event> -> @rule:Model.Rule -> @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @direction:Allocation.ResolvedDirection -> @children:+List<Allocation.AllocatedTree<Content.Value, Doc.Event>> ->
      {native_carrier_attributes(Renderer.allocated_native_properties(owner, target, Allocation.AllocatedContainer{key, Content.Value{Source.NativeAttachment{identity, native_target, attrs, style, original}, font}, interaction, rule, bounds, canvas, direction, children})) == Renderer.attributes(attrs) : +List<Doc.Property>},
    leaf_observation: @+capacity:Nat -> @+value:Content.Value -> @physical_key:String -> @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @+rule:Model.Rule -> @+interaction:Model.Interaction<Doc.Event> -> @+styles:+List<Doc.Property> -> @owned:+List<Renderer.Owned> ->
      leaf_observation_claim(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned),
    container_observation: @+capacity:Nat -> @+value:Content.Value -> @interaction:Model.Interaction<Doc.Event> -> @styles:+List<Doc.Property> -> @children:+List<Doc.Node> -> @+native:Bool ->
      container_observation_claim(capacity, value, interaction, styles, children, native),
    reading_box: @+capacity:Nat -> @+key:Identity.Key -> @+tag:Source.BoxTag -> @+style:Source.Style ->
      @+attrs:+List<Source.Attribute> -> @+original:+List<Source.Node> -> @+font:T.Presentation ->
      @interaction:Model.Interaction<Doc.Event> -> @+styles:+List<Doc.Property> -> @children:+List<Doc.Node> -> @native:Bool ->
      @+content:Bool -> @recognized:{Renderer.reading_content(attrs) == content : Bool} ->
      reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content),
    reading_content: @styles:+List<Doc.Property> ->
      {Renderer.reading_styles(True{}, styles) == Renderer.properties(styles, [Paint.property("padding-bottom", "var(--reading-composer-reserve, 0px)")]) : +List<Doc.Property>},
    reading_noncontent: @styles:+List<Doc.Property> -> {Renderer.reading_styles(False{}, styles) == styles : +List<Doc.Property>},
    rich_parent: @+capacity:Nat -> @+font:T.Presentation -> @policy:Source.RichPolicy ->
      {text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))},
    root_theme: @generation:Nat -> @key:Identity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @children:+List<Source.Node> -> @font:T.Presentation -> @theme:Design.Theme ->
      {Renderer.root_theme(Content.Snapshot{generation, Source.Box{key, tag, style, [Source.DataAttribute{"theme", Shell.theme_name(theme)}], children}, font}) ==
        Doc.TargetProperties{"@browser/root-theme", "@document/root", [Doc.Property{"data-theme", Shell.theme_name(theme)}], Paint.focus_indicator_style(Appearance.default_focus_indicator())} : Doc.Node},
    admitted_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.Event> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @valid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) ==
        (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>},
    rejected_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.Event> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @invalid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}}

law evidence:
  Requirements
