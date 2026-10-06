import Base
import ../core/ui-identity.bend as UIIdentity
import ./document.bend as Doc
import ./source.bend as Source
import ./physical-content.bend as Content
import ./physical-space.bend as Model
import ./physical-renderer.bend as Renderer
import ./typography.bend as T
import ./design.bend as Design
import ./paint.bend as Paint

# The marker connects authored control states to the browser's native selectors.
def first_attribute(values: +List<Doc.Property>) -> Maybe<&2, Doc.Property>:
  match values:
    case Nil{}: None{}
    case Con{value, rest}: Some{value}

def first_rendered_attribute(node: Doc.Node) -> Maybe<&2, Doc.Property>:
  match node:
    case Doc.Element{key, tag, attributes, styles, events, children}: first_attribute(attributes)
    case _: None{}

def attributes_claim(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String,
  interaction: Model.Interaction<Doc.Event>) -> Type:
  {first_attribute(Renderer.control_attributes(tag, attrs, name, interaction)) ==
    Some{Doc.Property{"class", "native-control"}} : Maybe<&2, Doc.Property>}

def render_claim(key: UIIdentity.Key, tag: Source.ControlTag, style: Source.Style,
  attrs: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.Event,
  remaining: +List<Doc.Event>, original_children: +List<Source.Node>, font: T.Presentation,
  interaction: Model.Interaction<Doc.Event>, styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool) -> Type:
  {first_rendered_attribute(Renderer.container(Content.Value{
      Source.Control{key, tag, style, attrs, name, enabled, first, remaining, original_children}, font},
      interaction, styles, children, native)) ==
    Some{Doc.Property{"class", "native-control"}} : Maybe<&2, Doc.Property>}

def property_pick(found: Bool, value: String, following: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case True{}: Some{value}
    case False{}: following

def property_value(+values: +List<Doc.Property>, +name: String) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Con{Doc.Property{key, value}, rest}:
      property_pick(String.eq(key, name), value, property_value(rest, name))

def background_channel_claim(+chrome: Design.Chrome) -> Type:
  Design.Chrome{foreground, +background, border, width, radius, shadow} = chrome
  {(property_value(Renderer.control_chrome(chrome), "--native-rest-background"),
    property_value(Renderer.control_chrome(chrome), "background")) ==
    (Some{Paint.paint(background)}, None{}) : (Maybe<&2, String> & Maybe<&2, String>)}

def foreground_channel_claim(+chrome: Design.Chrome) -> Type:
  Design.Chrome{+foreground, background, border, width, radius, shadow} = chrome
  {(property_value(Renderer.control_chrome(chrome), "--native-rest-color"),
    property_value(Renderer.control_chrome(chrome), "color")) ==
    (Some{Paint.paint(foreground)}, None{}) : (Maybe<&2, String> & Maybe<&2, String>)}

type Requirements is Type:
  Requirements{
    background_uses_rest_channel: @chrome:Design.Chrome -> background_channel_claim(chrome),
    foreground_uses_rest_channel: @chrome:Design.Chrome -> foreground_channel_claim(chrome),
    attributes_consume_control_states: @tag:Source.ControlTag -> @attrs:+List<Source.Attribute> -> @name:String ->
      @interaction:Model.Interaction<Doc.Event> -> attributes_claim(tag, attrs, name, interaction),
    rendered_controls_consume_control_states: @key:UIIdentity.Key -> @tag:Source.ControlTag -> @style:Source.Style ->
      @attrs:+List<Source.Attribute> -> @name:String -> @enabled:Bool -> @first:Doc.Event ->
      @remaining:+List<Doc.Event> -> @original_children:+List<Source.Node> -> @font:T.Presentation ->
      @interaction:Model.Interaction<Doc.Event> -> @styles:+List<Doc.Property> -> @children:+List<Doc.Node> ->
      @native:Bool -> render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native)}

law evidence:
  Requirements
