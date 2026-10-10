import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SOURCE.bend as PhysicalSource
import ./RENDERER.bend as Renderer
import ./CONTENT.bend as Content
import ./physical-space.bend as Model
import ../document/SOURCE.bend as Source
import ../appearance/TYPOGRAPHY.bend as T
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ./GEOMETRY.bend as Spatial
import ../document/MODEL.bend as Doc
import ../appearance/PROGRAM.bend as Paint
import ./physical-probe.bend as Probe
import ./physical-plan.bend as Plan
import ../appearance/DESIGN.bend as Design
import ../controls/CONTROLS.bend as Authoring
import ../controls/PROGRAM.bend as Controls
import ../appearance/MODEL.bend as Appearance
import ../controls/SURFACES.bend as Surfaces
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ./PROGRAM.bend as Allocation
import ../appearance/CONTRACT.bend as PaintRule
import ../controls/SHELL.bend as Shell

def minimum_width(demand: Space.Demand) -> Nat:
  Space.Demand{Enclosure.Extent{width, height}, preferred} = demand
  width

def preferred_width(demand: Space.Demand) -> Nat:
  Space.Demand{minimum, Enclosure.Extent{width, height}} = demand
  width

def text_space_render_claim(+capacity: Nat, +key: UIIdentity.Key, +text: String, choice: Source.FontChoice, font: T.Presentation,
  bounds: Spatial.Box, canvas: Enclosure.Extent, rule: Model.Rule, interaction: Model.Interaction<Doc.DOMEvent>,
  styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) -> Type:
  +value : Content.Value = Content.Value{Source.Text{key, text, choice, T.SingleLine{}}, font}
  {Renderer.leaf_at(capacity, value, UIIdentity.encode(key), bounds, canvas, rule, interaction, styles, owned) ==
    Doc.Element{UIIdentity.encode(key), "span", [Doc.Property{"title", text}, Doc.Property{"data-frame-key", UIIdentity.encode(key)}],
      Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), [Paint.property("text-overflow", "ellipsis")])),
      Nil{}, [Doc.Text{text}]} : Doc.Node}

def text_space_attributes_claim(+wrapping: T.Wrapping, +text: String) -> Type:
  match wrapping:
    case T.SingleLine{}: {Renderer.text_attributes(wrapping, text) == [Doc.Property{"title", text}] : +List<Doc.Property>}
    case _: {Renderer.text_attributes(wrapping, text) == Nil{} : +List<Doc.Property>}

law unbroken_height:
  for key: String
  for height: Nat
  {PhysicalSource.text_height(T.UnbrokenLine{},key,height) == Model.FixedHeight{height} : Model.Height}

def unbroken_render_claim(+capacity: Nat, +key: UIIdentity.Key, +text: String, choice: Source.FontChoice, font: T.Presentation,
  bounds: Spatial.Box, canvas: Enclosure.Extent, rule: Model.Rule, interaction: Model.Interaction<Doc.DOMEvent>,
  styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) -> Type:
  +value : Content.Value = Content.Value{Source.Text{key,text,choice,T.UnbrokenLine{}},font}
  {Renderer.leaf_at(capacity,value,UIIdentity.encode(key),bounds,canvas,rule,interaction,styles,owned) ==
    Doc.Element{UIIdentity.encode(key),"span",[Doc.Property{"data-frame-key", UIIdentity.encode(key)}],Renderer.properties(styles,Renderer.properties(Renderer.primitive_styles_at(capacity,value),Nil{})),Nil{},[Doc.Text{text}]} : Doc.Node}

law unbroken_render:
  for +capacity: Nat
  for +key: UIIdentity.Key
  for +text: String
  for choice: Source.FontChoice
  for font: T.Presentation
  for bounds: Spatial.Box
  for canvas: Enclosure.Extent
  for rule: Model.Rule
  for interaction: Model.Interaction<Doc.DOMEvent>
  for styles: +List<Doc.Property>
  for owned: +List<Renderer.Owned>
  unbroken_render_claim(capacity,key,text,choice,font,bounds,canvas,rule,interaction,styles,owned)

def unbroken_metric_claim(metric: T.Metric) -> Type:
  T.Metric{key,minimum,+preferred,+height,advance} = metric
  {PhysicalSource.text_natural_dimensions(T.UnbrokenLine{},minimum,preferred,height,advance) ==
    Space.Demand{Enclosure.Extent{preferred,height},Enclosure.Extent{preferred,height}} : Space.Demand}

law unbroken_metric:
  for metric: T.Metric
  unbroken_metric_claim(metric)

# The marker connects authored control states to the browser's native selectors.
def first_attribute(values: +List<Doc.Property>) -> Maybe<&2, Doc.Property>:
  match values:
    case Nil{}: None{}
    case Con{value, rest}: Some{value}

def first_rendered_attribute(node: Doc.Node) -> Maybe<&2, Doc.Property>:
  match node:
    case Doc.Element{key, tag, attributes, styles, events, children}: first_attribute(attributes)
    case _: None{}

def control_attributes_claim(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String,
  interaction: Model.Interaction<Doc.DOMEvent>) -> Type:
  {first_attribute(Renderer.control_attributes(tag, attrs, name, interaction)) ==
    Some{Doc.Property{"class", "native-control"}} : Maybe<&2, Doc.Property>}

def control_render_claim(key: UIIdentity.Key, tag: Source.ControlTag, style: Source.Style,
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

type ControlRequirements is Type:
  ControlRequirements{
    background_uses_rest_channel: @chrome:Design.Chrome -> background_channel_claim(chrome),
    foreground_uses_rest_channel: @chrome:Design.Chrome -> foreground_channel_claim(chrome),
    attributes_consume_control_states: @tag:Source.ControlTag -> @attrs:+List<Source.Attribute> -> @name:String ->
      @interaction:Model.Interaction<Doc.DOMEvent> -> control_attributes_claim(tag, attrs, name, interaction),
    rendered_controls_consume_control_states: @key:UIIdentity.Key -> @tag:Source.ControlTag -> @style:Source.Style ->
      @attrs:+List<Source.Attribute> -> @name:String -> @enabled:Bool -> @first:Doc.DOMEvent ->
      @remaining:+List<Doc.DOMEvent> -> @original_children:+List<Source.Node> -> @font:T.Presentation ->
      @interaction:Model.Interaction<Doc.DOMEvent> -> @styles:+List<Doc.Property> -> @children:+List<Doc.Node> ->
      @native:Bool -> control_render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native)}

law control_evidence:
  ControlRequirements

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
  for meaning: SurfaceTypes.Meaning
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
  for meaning: SurfaceTypes.Meaning
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

def text_properties(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (PaintRule.property_value(values, "font-family"), (PaintRule.property_value(values, "font-size"),
    (PaintRule.property_value(values, "line-height"), PaintRule.property_value(values, "font-weight"))))

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def reading_box_claim(+capacity: Nat, +key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.DOMEvent>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool) -> Type:
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

def demand_claim_parameters(+wrapping: T.Wrapping, +observation: Content.Observation, +minimum: Nat, +preferred: Nat, +height: Nat) -> Type:
  match wrapping:
    case T.SingleLine{}:
      +visible: Nat = Nat.min(minimum, PhysicalSource.observation_advance(observation))
      {PhysicalSource.text_natural_demand(wrapping, observation) ==
        Space.Demand{Enclosure.Extent{visible, height}, Enclosure.Extent{Nat.max(visible, preferred), height}} : Space.Demand}
    case T.UnbrokenLine{}:
      {PhysicalSource.text_natural_demand(wrapping, observation) ==
        Space.Demand{Enclosure.Extent{preferred, height}, Enclosure.Extent{preferred, height}} : Space.Demand}
    case _:
      {PhysicalSource.text_natural_demand(wrapping, observation) ==
        Space.Demand{Enclosure.Extent{minimum, height}, Enclosure.Extent{preferred, height}} : Space.Demand}

def demand_claim(+wrapping: T.Wrapping, +observation: Content.Observation) -> Type:
  demand_claim_parameters(wrapping, observation, PhysicalSource.observation_minimum(observation), PhysicalSource.observation_preferred(observation), PhysicalSource.observation_height(observation))

def source_claim(label: UIIdentity.Key, text: String, choice: Source.FontChoice, +wrapping: T.Wrapping,
  key: String, font: T.Presentation, rule: Model.Rule, +observation: Content.Observation,
  roots: +List<Content.NativeRoot>, policies: +List<Content.NativePolicy>) -> Type:
  {PhysicalSource.observed_leaf(Source.Text{label, text, choice, wrapping}, key, font, rule, observation, roots, policies) ==
    PhysicalSource.ReadyForest{[Model.Leaf{key, Content.local_value(Source.Text{label, text, choice, wrapping}, font), Model.DisplayOnly{}, rule,
      PhysicalSource.text_natural_demand(wrapping, observation), PhysicalSource.text_height(wrapping, key, PhysicalSource.observation_height(observation))}], roots, policies} : PhysicalSource.Forest}

type TextSpaceRequirements is Type:
  TextSpaceRequirements{
    measured_minimum_bound: @+observation:Content.Observation ->
      {Nat.is_le(minimum_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation)), PhysicalSource.observation_advance(observation)) == True{} : Bool},
    natural_preferred_bound: @+observation:Content.Observation ->
      {Nat.is_le(PhysicalSource.observation_preferred(observation), preferred_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation))) == True{} : Bool},
    demand_policy: @+wrapping:T.Wrapping -> @+observation:Content.Observation -> demand_claim(wrapping, observation),
    production_source: @label:UIIdentity.Key -> @text:String -> @choice:Source.FontChoice -> @+wrapping:T.Wrapping ->
      @key:String -> @font:T.Presentation -> @rule:Model.Rule -> @+observation:Content.Observation ->
      @roots:+List<Content.NativeRoot> -> @policies:+List<Content.NativePolicy> -> source_claim(label, text, choice, wrapping, key, font, rule, observation, roots, policies),
    complete_render: @+capacity:Nat -> @+key:UIIdentity.Key -> @+text:String -> @choice:Source.FontChoice -> @font:T.Presentation ->
      @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @rule:Model.Rule -> @interaction:Model.Interaction<Doc.DOMEvent> ->
      @styles:+List<Doc.Property> -> @owned:+List<Renderer.Owned> -> text_space_render_claim(capacity, key, text, choice, font, bounds, canvas, rule, interaction, styles, owned),
    attributes_policy: @+wrapping:T.Wrapping -> @+text:String -> text_space_attributes_claim(wrapping, text)}

law text_space_evidence:
  TextSpaceRequirements

law unbroken_width:
  for +observation: Content.Observation
  {minimum_width(PhysicalSource.text_natural_demand(T.UnbrokenLine{}, observation)) ==
    preferred_width(PhysicalSource.text_natural_demand(T.UnbrokenLine{}, observation)) : Nat}

law unbroken_dimensions:
  for +observation: Content.Observation
  {PhysicalSource.text_natural_demand(T.UnbrokenLine{}, observation) ==
    Space.Demand{Enclosure.Extent{PhysicalSource.observation_preferred(observation),PhysicalSource.observation_height(observation)},
      Enclosure.Extent{PhysicalSource.observation_preferred(observation),PhysicalSource.observation_height(observation)}} : Space.Demand}

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
  canvas: Enclosure.Extent, rule: Model.Rule, interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, owned: +List<Renderer.Owned>) -> Type:
  match value:
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Glyph{key, picture, style}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: {field_observation(kind, Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.RichText{key, style, content, attachments, owner}, font}: {observation(Renderer.leaf_at(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case _: {True{} == True{} : Bool}

def container_observation_claim(+capacity: Nat, +value: Content.Value, interaction: Model.Interaction<Doc.DOMEvent>, styles: +List<Doc.Property>, children: +List<Doc.Node>, +native: Bool) -> Type:
  match value:
    case Content.Value{Source.Box{key, tag, style, attrs, original}, font}: {observation(Renderer.container_at(capacity, value, interaction, styles, children, native)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, original}, font}: {observation(Renderer.container_at(capacity, value, interaction, styles, children, native)) == Some{Doc.Property{"data-frame-key", Renderer.observation_key(value)}} : Maybe<&2, Doc.Property>}
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, original}, font}:
      match native:
        case True{}: {Renderer.container_at(capacity, value, interaction, styles, children, native) == Doc.Element{UIIdentity.encode(key), "div", Nil{}, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, value), Renderer.visual(style))), Nil{}, children} : Doc.Node}
        case False{}: {True{} == True{} : Bool}
    case _: {True{} == True{} : Bool}

type RendererRequirements is Type:
  RendererRequirements{
    observed_element: @key:String -> @dom_key:String -> @tag:String -> @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.DOMEvent> -> @children:+List<Doc.Node> ->
      {Renderer.observed(key, Doc.Element{dom_key, tag, attrs, styles, events, children}) == Doc.Element{dom_key, tag, Renderer.properties(attrs, [Doc.Property{"data-frame-key", key}]), styles, events, children} : Doc.Node},
    observed_toggle: @identity:String -> @dom_key:String -> @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.DOMEvent> -> @input_key:String -> @input_attrs:+List<Doc.Property> -> @input_styles:+List<Doc.Property> -> @input_events:+List<Doc.DOMEvent> -> @input_children:+List<Doc.Node> -> @rest:+List<Doc.Node> ->
      {Renderer.observed_field(Source.ToggleField{}, identity, Doc.Element{dom_key, "span", attrs, styles, events, Con{Doc.Element{input_key, "input", input_attrs, input_styles, input_events, input_children}, rest}}) ==
        Doc.Element{dom_key, "span", attrs, styles, events, Con{Doc.Element{input_key, "input", Renderer.properties(input_attrs, [Doc.Property{"data-frame-key", identity}]), input_styles, input_events, input_children}, rest}} : Doc.Node},
    native_attachment_carrier: @owner:String -> @target:Source.NativeTarget -> @key:String -> @+identity:UIIdentity.Key -> @+native_target:Source.NativeTarget -> @+attrs:+List<Source.Attribute> -> @+style:Source.Style -> @+original:+List<Source.Node> -> @+font:T.Presentation -> @interaction:Model.Interaction<Doc.DOMEvent> -> @rule:Model.Rule -> @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @direction:Allocation.ResolvedDirection -> @children:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> ->
      {native_carrier_attributes(Renderer.allocated_native_properties(owner, target, Allocation.AllocatedContainer{key, Content.Value{Source.NativeAttachment{identity, native_target, attrs, style, original}, font}, interaction, rule, bounds, canvas, direction, children})) == Renderer.attributes(attrs) : +List<Doc.Property>},
    leaf_observation: @+capacity:Nat -> @+value:Content.Value -> @physical_key:String -> @bounds:Spatial.Box -> @canvas:Enclosure.Extent -> @+rule:Model.Rule -> @+interaction:Model.Interaction<Doc.DOMEvent> -> @+styles:+List<Doc.Property> -> @owned:+List<Renderer.Owned> ->
      leaf_observation_claim(capacity, value, physical_key, bounds, canvas, rule, interaction, styles, owned),
    container_observation: @+capacity:Nat -> @+value:Content.Value -> @interaction:Model.Interaction<Doc.DOMEvent> -> @styles:+List<Doc.Property> -> @children:+List<Doc.Node> -> @+native:Bool ->
      container_observation_claim(capacity, value, interaction, styles, children, native),
    reading_box: @+capacity:Nat -> @+key:UIIdentity.Key -> @+tag:Source.BoxTag -> @+style:Source.Style ->
      @+attrs:+List<Source.Attribute> -> @+original:+List<Source.Node> -> @+font:T.Presentation ->
      @interaction:Model.Interaction<Doc.DOMEvent> -> @+styles:+List<Doc.Property> -> @children:+List<Doc.Node> -> @native:Bool ->
      @+content:Bool -> @recognized:{Renderer.reading_content(attrs) == content : Bool} ->
      reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content),
    reading_content: @styles:+List<Doc.Property> ->
      {Renderer.reading_styles(True{}, styles) == Renderer.properties(styles, [Paint.property("padding-bottom", "var(--reading-composer-reserve, 0px)")]) : +List<Doc.Property>},
    reading_noncontent: @styles:+List<Doc.Property> -> {Renderer.reading_styles(False{}, styles) == styles : +List<Doc.Property>},
    rich_parent: @+capacity:Nat -> @+font:T.Presentation -> @policy:Source.RichPolicy ->
      {text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))},
    root_theme: @generation:Nat -> @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @children:+List<Source.Node> -> @font:T.Presentation -> @theme:Design.Theme ->
      {Renderer.root_theme(Content.Snapshot{generation, Source.Box{key, tag, style, [Source.DataAttribute{"theme", Shell.theme_name(theme)}], children}, font}) ==
        Doc.TargetProperties{"@browser/root-theme", "@document/root", [Doc.Property{"data-theme", Shell.theme_name(theme)}], Paint.focus_indicator_style(Appearance.default_focus_indicator())} : Doc.Node},
    admitted_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.DOMEvent> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @valid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) ==
        (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>},
    rejected_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.DOMEvent> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @invalid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}}

law renderer_evidence:
  RendererRequirements
