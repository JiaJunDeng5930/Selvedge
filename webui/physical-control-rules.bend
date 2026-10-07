import Base
import ../core/ui-identity.bend as UIIdentity
import ./document.bend as Doc
import ./source.bend as Source
import ./physical-content.bend as Content
import ./physical-space.bend as Model
import ./physical-renderer.bend as Renderer
import ./physical-probe.bend as Probe
import ./physical-plan.bend as Plan
import ./typography.bend as T
import ./design.bend as Design
import ./paint.bend as Paint
import ./authored-controls.bend as Authoring
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./surfaces.bend as Surfaces
import ../core/interface.bend as InterfaceView
import ../core/ui-world.bend as View

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
  interaction: Model.Interaction<Doc.DOMEvent>) -> Type:
  {first_attribute(Renderer.control_attributes(tag, attrs, name, interaction)) ==
    Some{Doc.Property{"class", "native-control"}} : Maybe<&2, Doc.Property>}

def render_claim(key: UIIdentity.Key, tag: Source.ControlTag, style: Source.Style,
  attrs: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.DOMEvent,
  remaining: +List<Doc.DOMEvent>, original_children: +List<Source.Node>, font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool) -> Type:
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
      @interaction:Model.Interaction<Doc.DOMEvent> -> attributes_claim(tag, attrs, name, interaction),
    rendered_controls_consume_control_states: @key:UIIdentity.Key -> @tag:Source.ControlTag -> @style:Source.Style ->
      @attrs:+List<Source.Attribute> -> @name:String -> @enabled:Bool -> @first:Doc.DOMEvent ->
      @remaining:+List<Doc.DOMEvent> -> @original_children:+List<Source.Node> -> @font:T.Presentation ->
      @interaction:Model.Interaction<Doc.DOMEvent> -> @styles:+List<Doc.Property> -> @children:+List<Doc.Node> ->
      @native:Bool -> render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native)}

law evidence:
  Requirements

def activation_expected(event: Doc.DOMEvent) -> Bool:
  match event:
    case Doc.Activate{key}: True{}
    case _: False{}

def keyboard_attributes_expected(active: Bool, interaction: Model.Interaction<Doc.DOMEvent>, name: String) -> +List<Doc.Property>:
  match active:
    case True{}: [Paint.property("tabindex", Renderer.control_tabindex(interaction)), Paint.property("role", "button"), Paint.property("aria-label", name)]
    case False{}: [Paint.property("tabindex", "-1"), Paint.property("aria-label", name)]

def control_attributes_expected(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String, interaction: Model.Interaction<Doc.DOMEvent>) -> +List<Doc.Property>:
  match tag:
    case Source.Button{}: Renderer.properties(Renderer.attributes(attrs), Paint.property("type", "button") <> Paint.property("aria-label", name) <> Renderer.availability(interaction, True{}))
    case Source.Summary{}: Renderer.properties(Renderer.attributes(attrs), Paint.property("aria-label", name) <> Renderer.availability(interaction, False{}))
    case _: Renderer.nonnative_control_attributes(attrs, name, interaction)

law keyboard_activation_total:
  for event: Doc.DOMEvent
  {Doc.keyboard_activation(event) == activation_expected(event) : Bool}

law keyboard_activation_empty:
  {Doc.keyboard_activations(Nil{}) == False{} : Bool}

law keyboard_activation_cons:
  for +first: Doc.DOMEvent
  for +remaining: +List<Doc.DOMEvent>
  {Doc.keyboard_activations(first <> remaining) == Bool.or(Doc.keyboard_activation(first), Doc.keyboard_activations(remaining)) : Bool}

law keyboard_control_display_only:
  {Renderer.keyboard_control(Model.DisplayOnly{}) == False{} : Bool}

law keyboard_control_operable:
  for first: Doc.DOMEvent
  for remaining: +List<Doc.DOMEvent>
  for enabled: Bool
  {Renderer.keyboard_control(Model.Operable{first,remaining,enabled}) == Doc.keyboard_activations(first <> remaining) : Bool}

law keyboard_attribute_projection:
  for +active: Bool
  for +interaction: Model.Interaction<Doc.DOMEvent>
  for +name: String
  {Renderer.keyboard_control_attributes(active,interaction,name) == keyboard_attributes_expected(active,interaction,name) : +List<Doc.Property>}

law nonnative_attribute_projection:
  for +attrs: +List<Source.Attribute>
  for +name: String
  for +interaction: Model.Interaction<Doc.DOMEvent>
  {Renderer.nonnative_control_attributes(attrs,name,interaction) == Renderer.properties(Renderer.attributes(attrs), Renderer.properties(Renderer.keyboard_control_attributes(Renderer.keyboard_control(interaction),interaction,name), Renderer.availability(interaction,False{}))) : +List<Doc.Property>}

law control_attribute_projection:
  for +tag: Source.ControlTag
  for +attrs: +List<Source.Attribute>
  for +name: String
  for +interaction: Model.Interaction<Doc.DOMEvent>
  {Renderer.control_attribute_details(tag,attrs,name,interaction) == control_attributes_expected(tag,attrs,name,interaction) : +List<Doc.Property>}

law source_control_interaction:
  for key: UIIdentity.Key
  for tag: Source.ControlTag
  for style: Source.Style
  for attrs: +List<Source.Attribute>
  for name: String
  for +enabled: Bool
  for +first: Doc.DOMEvent
  for +remaining: +List<Doc.DOMEvent>
  for children: +List<Source.Node>
  {Source.interaction_of(Source.Control{key,tag,style,attrs,name,enabled,first,remaining,children}) == Model.Operable{first,remaining,enabled} : Model.Interaction<Doc.DOMEvent>}

def rendered_control_claim(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.ControlTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +name: String, +enabled: Bool, +first: Doc.DOMEvent,
  +remaining: +List<Doc.DOMEvent>, +original_children: +List<Source.Node>, +font: T.Presentation,
  +interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, +children: +List<Doc.Node>, native: Bool) -> Type:
  {Renderer.container_at(capacity,Content.Value{Source.Control{key,tag,style,attrs,name,enabled,first,remaining,original_children},font},interaction,styles,children,native) ==
    Doc.Element{UIIdentity.encode(key),Source.control_tag_name(tag),Renderer.properties(Renderer.control_attributes(tag,attrs,name,interaction), [Doc.Property{"data-frame-key", Renderer.observation_key(Content.Value{Source.Control{key,tag,style,attrs,name,enabled,first,remaining,original_children},font})}]),
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
  for first: Doc.DOMEvent
  for remaining: +List<Doc.DOMEvent>
  for original_children: +List<Source.Node>
  for font: T.Presentation
  for interaction: Model.Interaction<Doc.DOMEvent>
  for styles: +List<Doc.Property>
  for children: +List<Doc.Node>
  for native: Bool
  rendered_control_claim(capacity,key,tag,style,attrs,name,enabled,first,remaining,original_children,font,interaction,styles,children,native)

# Probe and committed field styles consume the same native appearance policy.
law native_field_probe_appearance:
  for kind: Source.NativeFieldKind
  {property_value(Probe.field_box_styles(kind), "appearance") ==
    Some{Source.native_field_appearance(kind)} : Maybe<&2, String>}

law native_field_rendered_appearance:
  for kind: Source.NativeFieldKind
  for rule: Model.Rule
  {property_value(Renderer.field_padding(kind, rule), "appearance") ==
    Some{Source.native_field_appearance(kind)} : Maybe<&2, String>}

law toggle_field_probe_appearance:
  {property_value(Probe.field_box_styles(Source.ToggleField{}), "appearance") ==
    Some{"none"} : Maybe<&2, String>}

law toggle_field_rendered_appearance:
  for rule: Model.Rule
  {property_value(Renderer.field_padding(Source.ToggleField{}, rule), "appearance") ==
    Some{"none"} : Maybe<&2, String>}

law other_native_field_appearance:
  for minimum: Nat
  for multiple: Bool
  {[Source.native_field_appearance(Source.TextField{}),
    Source.native_field_appearance(Source.MessageField{}),
    Source.native_field_appearance(Source.TextAreaField{}),
    Source.native_field_appearance(Source.SelectField{}),
    Source.native_field_appearance(Source.MultiSelectField{}),
    Source.native_field_appearance(Source.NumberField{minimum}),
    Source.native_field_appearance(Source.FileField{multiple}),
    Source.native_field_appearance(Source.DirectoryField{}),
    Source.native_field_appearance(Source.SearchField{}),
    Source.native_field_appearance(Source.SecretField{})] ==
    ["none", "none", "none", "none", "none", "none", "none", "none", "none", "none"] : +List<String>}

# These projections inspect the authored and rendered production values.
def field_axes(node: Source.Node) -> (Model.AxisSize & Model.AxisSize):
  match node:
    case Source.Field{key, kind, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: (width, height)
    case Source.Box{key, tag, style, attrs, Con{caption, Con{field, Nil{}}}}: field_axes(field)
    case _: (Model.NaturalSize{}, Model.NaturalSize{})

def label_caption(node: Source.Node) -> (Source.BoxTag & Model.AxisSize):
  match node:
    case Source.Box{key, tag, style, attrs, Con{Source.Box{caption_key, caption_tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, caption_attrs, children}, rest}}: (tag, width)
    case _: (Source.Div{}, Model.NaturalSize{})

law toggle_geometry_bounded:
  {Nat.is_le(Source.toggle_visual_size(Source.native_toggle_geometry()), Source.toggle_target_size(Source.native_toggle_geometry())) == True{} : Bool}

law toggle_geometry_centered:
  {Source.toggle_center_offset(Source.native_toggle_geometry()) == 8n : Nat}

law toggle_probe_rectangle:
  {(property_value(Probe.field_box_styles(Source.ToggleField{}), "width"), property_value(Probe.field_box_styles(Source.ToggleField{}), "height")) ==
    (Some{"32px"}, Some{"32px"}) : (Maybe<&2, String> & Maybe<&2, String>)}

law toggle_target_rectangle:
  {(property_value(Renderer.toggle_target_styles(), "width"), property_value(Renderer.toggle_target_styles(), "height")) ==
    (Some{"32px"}, Some{"32px"}) : (Maybe<&2, String> & Maybe<&2, String>)}

law toggle_visual_rectangle:
  for style: Source.Style
  {(property_value(Renderer.toggle_visual_styles(style), "width"), property_value(Renderer.toggle_visual_styles(style), "height"), property_value(Renderer.toggle_visual_styles(style), "left"), property_value(Renderer.toggle_visual_styles(style), "top")) ==
    (Some{"16px"}, Some{"16px"}, Some{"8px"}, Some{"8px"}) : (Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String>)}

def toggle_face_styles(node: Source.Node) -> +List<Doc.Property>:
  match node:
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: Renderer.toggle_visual_styles(style)
    case Source.Box{key, tag, style, attrs, Con{caption, Con{field, Nil{}}}}: toggle_face_styles(field)
    case _: Nil{}

law production_toggle_face:
  for key: UIIdentity.Key
  for meaning: InterfaceView.Meaning
  for name: String
  for placement: Controls.LabelPlacement
  for availability: View.Availability
  for typography: T.Presentation
  for parameters: Design.LayoutParameters
  +styles = toggle_face_styles(Authoring.input_widget(Controls.ToggleInput{}, key, meaning, name, placement,
    availability, Appearance.toggle_field(typography), parameters))
  {(property_value(styles, "width"), property_value(styles, "height"), property_value(styles, "border-width"),
      property_value(styles, "border-radius"), property_value(styles, "border-color"), property_value(styles, "background")) ==
    (Some{"16px"}, Some{"16px"}, Some{"1px"}, Some{"3px"}, Some{Paint.paint(Design.ThemeToken{"--color-token-input-border"})},
      Some{Paint.paint(Design.SurfacePaint{Surfaces.Field{}, Surfaces.Rest{}})}) :
    (Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String>)}

law unchecked_toggle_glyph:
  for key: UIIdentity.Key
  {Renderer.toggle_glyph(key, False{}) == Nil{} : +List<Doc.Node>}

law toggle_authoring_allocation:
  for key: UIIdentity.Key
  for meaning: InterfaceView.Meaning
  for name: String
  for placement: Controls.LabelPlacement
  for availability: View.Availability
  for visual: Design.Style
  for parameters: Design.LayoutParameters
  {field_axes(Authoring.input_widget(Controls.ToggleInput{}, key, meaning, name, placement, availability, visual, parameters)) ==
    (Model.ExactSize{32n}, Model.ExactSize{32n}) : (Model.AxisSize & Model.AxisSize)}

law beside_label_activation:
  for key: UIIdentity.Key
  for name: String
  for visual: Design.Style
  for field: Source.Node
  {label_caption(Authoring.label_field(Controls.BesideInput{}, key, name, visual, field)) ==
    (Source.Label{}, Model.StretchSize{}) : (Source.BoxTag & Model.AxisSize)}

law toggle_rendered_composition:
  for key: UIIdentity.Key
  for style: Source.Style
  for attrs: +List<Source.Attribute>
  for attributes: +List<Doc.Property>
  for styles: +List<Doc.Property>
  for events: +List<Doc.DOMEvent>
  for children: +List<Doc.Node>
  {Renderer.native_field_leaf(Source.ToggleField{}, key, style, attrs, attributes, styles, events, children) ==
    Doc.Element{UIIdentity.encode(UIIdentity.part(key, "toggle-target")), "span", Nil{}, Renderer.properties(styles,
      [Paint.property("background", "transparent"), Paint.property("border", "0"), Paint.property("padding", "0"),
         Paint.property("width", Paint.px(Source.toggle_target_size(Source.native_toggle_geometry()))),
         Paint.property("height", Paint.px(Source.toggle_target_size(Source.native_toggle_geometry())))]), Nil{},
      [Doc.Element{UIIdentity.encode(key), "input", attributes, Renderer.properties(styles, Renderer.toggle_target_styles()), events, children},
       Doc.Element{UIIdentity.encode(UIIdentity.part(key, "toggle-visual")), "span", [Paint.property("aria-hidden", "true")],
         Renderer.toggle_visual_styles(style), Nil{}, Renderer.toggle_glyph(UIIdentity.part(key, "toggle-check"), Renderer.toggle_checked(attrs))}]} : Doc.Node}


law measurement_probe_targets:
  for request: Content.Request
  for roots: +List<Content.AllocatedNative>
  {Probe.target_keys(Plan.Job{request, roots, Plan.Measure{}}) == Nil{} : +List<String>}

law native_target_probe_targets:
  for request: Content.Request
  for roots: +List<Content.AllocatedNative>
  {Probe.target_keys(Plan.Job{request, roots, Plan.TargetsOnly{}}) ==
    Probe.request_declared_target_keys(request) : +List<String>}
