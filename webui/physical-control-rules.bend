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

def activation_expected(event: Doc.Event) -> Bool:
  match event:
    case Doc.Activate{key}: True{}
    case _: False{}

def keyboard_attributes_expected(active: Bool, interaction: Model.Interaction<Doc.Event>, name: String) -> +List<Doc.Property>:
  match active:
    case True{}: [Paint.property("tabindex", Renderer.control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)]
    case False{}: [Paint.property("tabindex", "-1"), Paint.property("aria-label", name)]

def control_attributes_expected(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String, interaction: Model.Interaction<Doc.Event>) -> +List<Doc.Property>:
  match tag:
    case Source.Button{}: Renderer.properties(Renderer.attributes(attrs), Paint.property("type", "button") <> Paint.property("aria-label", name) <> Renderer.availability(interaction, True{}))
    case Source.Summary{}: Renderer.properties(Renderer.attributes(attrs), Paint.property("aria-label", name) <> Renderer.availability(interaction, False{}))
    case _: Renderer.nonnative_control_attributes(attrs, name, interaction)

law keyboard_activation_total:
  for event: Doc.Event
  {Doc.keyboard_activation(event) == activation_expected(event) : Bool}

law keyboard_activation_empty:
  {Doc.keyboard_activations(Nil{}) == False{} : Bool}

law keyboard_activation_cons:
  for +first: Doc.Event
  for +remaining: +List<Doc.Event>
  {Doc.keyboard_activations(first <> remaining) == Bool.or(Doc.keyboard_activation(first), Doc.keyboard_activations(remaining)) : Bool}

law keyboard_control_display_only:
  {Renderer.keyboard_control(Model.DisplayOnly{}) == False{} : Bool}

law keyboard_control_operable:
  for first: Doc.Event
  for remaining: +List<Doc.Event>
  for enabled: Bool
  {Renderer.keyboard_control(Model.Operable{first,remaining,enabled}) == Doc.keyboard_activations(first <> remaining) : Bool}

law keyboard_attribute_projection:
  for +active: Bool
  for +interaction: Model.Interaction<Doc.Event>
  for +name: String
  {Renderer.keyboard_control_attributes(active,interaction,name) == keyboard_attributes_expected(active,interaction,name) : +List<Doc.Property>}

law nonnative_attribute_projection:
  for +attrs: +List<Source.Attribute>
  for +name: String
  for +interaction: Model.Interaction<Doc.Event>
  {Renderer.nonnative_control_attributes(attrs,name,interaction) == Renderer.properties(Renderer.attributes(attrs), Renderer.properties(Renderer.keyboard_control_attributes(Renderer.keyboard_control(interaction),interaction,name), Renderer.availability(interaction,False{}))) : +List<Doc.Property>}

law control_attribute_projection:
  for +tag: Source.ControlTag
  for +attrs: +List<Source.Attribute>
  for +name: String
  for +interaction: Model.Interaction<Doc.Event>
  {Renderer.control_attribute_details(tag,attrs,name,interaction) == control_attributes_expected(tag,attrs,name,interaction) : +List<Doc.Property>}

law source_control_interaction:
  for key: UIIdentity.Key
  for tag: Source.ControlTag
  for style: Source.Style
  for attrs: +List<Source.Attribute>
  for name: String
  for +enabled: Bool
  for +first: Doc.Event
  for +remaining: +List<Doc.Event>
  for children: +List<Source.Node>
  {Source.interaction_of(Source.Control{key,tag,style,attrs,name,enabled,first,remaining,children}) == Model.Operable{first,remaining,enabled} : Model.Interaction<Doc.Event>}

def rendered_control_claim(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.ControlTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +name: String, +enabled: Bool, +first: Doc.Event,
  +remaining: +List<Doc.Event>, +original_children: +List<Source.Node>, +font: T.Presentation,
  +interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, +children: +List<Doc.Node>, native: Bool) -> Type:
  {Renderer.container_at(capacity,Content.Value{Source.Control{key,tag,style,attrs,name,enabled,first,remaining,original_children},font},interaction,styles,children,native) ==
    Doc.Element{UIIdentity.encode(key),Source.control_tag_name(tag),Renderer.control_attributes(tag,attrs,name,interaction),
      Renderer.properties(styles,Renderer.properties(Renderer.primitive_styles_at(capacity,Content.Value{Source.Control{key,tag,style,attrs,name,enabled,first,remaining,original_children},font}),Renderer.control_visual(style))),
      Renderer.event_list(interaction),children} : Doc.Node}

law rendered_control_projection:
  for capacity: Nat
  for key: UIIdentity.Key
  for tag: Source.ControlTag
  for style: Source.Style
  for attrs: +List<Source.Attribute>
  for name: String
  for enabled: Bool
  for first: Doc.Event
  for remaining: +List<Doc.Event>
  for original_children: +List<Source.Node>
  for font: T.Presentation
  for interaction: Model.Interaction<Doc.Event>
  for styles: +List<Doc.Property>
  for children: +List<Doc.Node>
  for native: Bool
  rendered_control_claim(capacity,key,tag,style,attrs,name,enabled,first,remaining,original_children,font,interaction,styles,children,native)
