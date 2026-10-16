import Base
import ../../bendlib/categories.bend as Categories
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/MODEL.bend as View
import ../appearance/DESIGN.bend as Design
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ./PROGRAM.bend as Controls
import ./CONTROLS.bend as A
import ./authored-primitives.bend as Factory

# Category observations bind construction inputs to the actual emitted node.
type Observation is Data:
  Observation{key: UIIdentity.Key, visual: Design.Style, parameters: Design.LayoutParameters, button: Controls.Button, node: Source.Node}

def source(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +button: Controls.Button) -> Source.Node:
  Controls.Button{input, +availability, +name, +value, +state, +geometry, placement, +response} = button
  Source.Control{key, Source.Button{}, Factory.with_alignments(Factory.with_direction(Factory.with_minimum(Factory.style(visual, A.action_width(value, visual), Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{Controls.geometry_minimum_width(Controls.geometry_at(A.parent_font(visual), geometry)), Controls.geometry_minimum_height(Controls.geometry_at(A.parent_font(visual), geometry))}), Model.Horizontal{}), A.action_alignment(value), A.action_cross_alignment(value, visual)), List.append(&2, Source.Attribute, A.choice_association(value, key), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, A.availability_attributes(availability), List.append(&2, Source.Attribute, A.behavior(state), List.append(&2, Source.Attribute, A.help(Controls.button_help(Controls.Button{input, availability, name, value, state, geometry, placement, response})), A.feedback(response)))))), name, A.enabled(availability), Doc.Activate{UIIdentity.encode(key)}, Nil{}, A.face(key, value, visual, geometry, parameters)}

def native_tag(node: Source.Node) -> Maybe<&2, Source.ControlTag>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first_event, remaining_events, children}: Some{tag}
    case _: None{}

def declared_name(node: Source.Node) -> Maybe<&2, String>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first_event, remaining_events, children}: Some{name}
    case _: None{}

def enabled_value(node: Source.Node) -> Maybe<&2, Bool>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first_event, remaining_events, children}: Some{enabled}
    case _: None{}

def node_attributes(node: Source.Node) -> Maybe<&2, +List<Source.Attribute>>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first_event, remaining_events, children}: Some{attributes}
    case _: None{}

def node_style(node: Source.Node) -> Maybe<&2, Source.Style>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first_event, remaining_events, children}: Some{style}
    case _: None{}

def button_face(button: Controls.Button) -> Controls.Face:
  Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback} = button
  face

def expected_attributes(+key: UIIdentity.Key, +button: Controls.Button) -> +List<Source.Attribute>:
  Controls.Button{input, +availability, +name, +face, +behavior, geometry, placement, +feedback} = button
  List.append(&2, Source.Attribute, A.choice_association(face, key), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, A.availability_attributes(availability), List.append(&2, Source.Attribute, A.behavior(behavior), List.append(&2, Source.Attribute, A.help(Controls.button_help(Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback})), A.feedback(feedback))))))

def expected_style(+visual: Design.Style, button: Controls.Button) -> Source.Style:
  Controls.Button{input, availability, name, +face, behavior, +geometry, placement, feedback} = button
  Factory.with_alignments(Factory.with_direction(Factory.with_minimum(Factory.style(visual, A.action_width(face, visual), Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{Controls.geometry_minimum_width(Controls.geometry_at(A.parent_font(visual), geometry)), Controls.geometry_minimum_height(Controls.geometry_at(A.parent_font(visual), geometry))}), Model.Horizontal{}), A.action_alignment(face), A.action_cross_alignment(face, visual))

def native(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {native_tag(node) == Some{Source.Button{}} : Maybe<&2, Source.ControlTag>}

def activation(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {Source.events_of(node) == [Doc.Activate{UIIdentity.encode(key)}] : +List<Doc.DOMEvent>}

def named(observation: Observation) -> Type:
  Observation{key, visual, parameters, Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}, node} = observation
  {declared_name(node) == Some{name} : Maybe<&2, String>}

def available(observation: Observation) -> Type:
  Observation{key, visual, parameters, Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}, node} = observation
  {enabled_value(node) == Some{A.enabled(availability)} : Maybe<&2, Bool>}

def attributes(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {node_attributes(node) == Some{expected_attributes(key, button)} : Maybe<&2, +List<Source.Attribute>>}

type Content<-observation: Observation> is Type:
  Content{style: content_style(observation), children: content_children(observation)}

def content_style(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {node_style(node) == Some{expected_style(visual, button)} : Maybe<&2, Source.Style>}

def content_children(observation: Observation) -> Type:
  Observation{key, visual, parameters, Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}, node} = observation
  {Source.children_of(node) == A.face(key, face, visual, geometry, parameters) : +List<Source.Node>}

def content(observation: Observation) -> Type:
  Content<observation>

type Authored<-observation: Observation> is Type:
  Authored{native: native(observation), activation: activation(observation), named: named(observation), available: available(observation), attributes: attributes(observation), content: content(observation)}

def authored(observation: Observation) -> Type:
  Authored<observation>

def main_alignment(node: Source.Node) -> Maybe<&2, Spatial.Alignment>:
  match node:
    case Source.Control{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, name, enabled, first_event, remaining_events, children}: Some{main}
    case _: None{}

def cross_alignment(node: Source.Node) -> Maybe<&2, Spatial.Alignment>:
  match node:
    case Source.Control{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, name, enabled, first_event, remaining_events, children}: Some{cross}
    case _: None{}

type Centered<-observation: Observation> is Type:
  Centered{main: centered_main(observation), cross: centered_cross(observation)}

def centered_main(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {main_alignment(node) == Some{Spatial.Centered{}} : Maybe<&2, Spatial.Alignment>}

def centered_cross(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {cross_alignment(node) == Some{Spatial.Centered{}} : Maybe<&2, Spatial.Alignment>}

def centered(observation: Observation) -> Type:
  Centered<observation>

def centered_glyph_style(style: Source.Style) -> Bool:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match main cross:
    case Spatial.Centered{} Spatial.Centered{}: True{}
    case _ _: False{}

def centered_glyph_children(children: +List<Source.Node>) -> Bool:
  match children:
    case [Source.Glyph{key, drawing, style}]: centered_glyph_style(style)
    case _: False{}

def glyph_centered(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {centered_glyph_children(Source.children_of(node)) == True{} : Bool}

def leading(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {main_alignment(node) == Some{Spatial.Leading{}} : Maybe<&2, Spatial.Alignment>}

def help_policy(help: Controls.Help) -> Bool:
  match help:
    case Controls.Tooltip{text, delay, True{}, True{}, False{}}: True{}
    case _: False{}

def icon_help(observation: Observation) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {help_policy(Controls.button_help(button)) == True{} : Bool}

def requested_face(observation: Observation, face: Controls.Face) -> Type:
  Observation{key, visual, parameters, button, node} = observation
  {button_face(button) == face : Controls.Face}

type Icon<-observation: Observation> is Type:
  Icon{-glyph: Controls.Icon, face: requested_face(observation, Controls.IconFace{glyph}), authored: authored(observation), centered: centered(observation), help: icon_help(observation), content: glyph_centered(observation)}

def icon(observation: Observation) -> Type:
  Icon<observation>

type Choice<-observation: Observation> is Type:
  Choice{-text: String, -description: Maybe<&2, String>, -glyph: Maybe<&2, Controls.Icon>, -selected: Bool, face: requested_face(observation, Controls.ChoiceFace{text, description, glyph, selected}), authored: authored(observation), leading: leading(observation)}

def choice(observation: Observation) -> Type:
  Choice<observation>

type Picker<-observation: Observation> is Type:
  Picker{-glyph: Maybe<&2, Controls.Icon>, -text: String, face: requested_face(observation, Controls.PickerFace{glyph, text}), authored: authored(observation), leading: leading(observation)}

def picker(observation: Observation) -> Type:
  Picker<observation>

def project_authored_native(-observation: Observation, evidence: authored(observation)) -> native(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  native

def authored_native() -> Categories.Inclusion<Observation, authored, native>:
  Categories.Inclusion{observation => evidence => project_authored_native(observation, evidence)}

def project_authored_activation(-observation: Observation, evidence: authored(observation)) -> activation(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  activation

def authored_activation() -> Categories.Inclusion<Observation, authored, activation>:
  Categories.Inclusion{observation => evidence => project_authored_activation(observation, evidence)}

def project_authored_named(-observation: Observation, evidence: authored(observation)) -> named(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  named

def authored_named() -> Categories.Inclusion<Observation, authored, named>:
  Categories.Inclusion{observation => evidence => project_authored_named(observation, evidence)}

def project_authored_available(-observation: Observation, evidence: authored(observation)) -> available(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  available

def authored_available() -> Categories.Inclusion<Observation, authored, available>:
  Categories.Inclusion{observation => evidence => project_authored_available(observation, evidence)}

def project_authored_attributes(-observation: Observation, evidence: authored(observation)) -> attributes(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  attributes

def authored_attributes() -> Categories.Inclusion<Observation, authored, attributes>:
  Categories.Inclusion{observation => evidence => project_authored_attributes(observation, evidence)}

def project_authored_content(-observation: Observation, evidence: authored(observation)) -> content(observation):
  Authored{native, activation, named, available, attributes, content} = evidence
  content

def authored_content() -> Categories.Inclusion<Observation, authored, content>:
  Categories.Inclusion{observation => evidence => project_authored_content(observation, evidence)}

def project_icon_authored(-observation: Observation, evidence: icon(observation)) -> authored(observation):
  Icon{glyph, face, authored, centered, help, content} = evidence
  authored

def icon_authored() -> Categories.Inclusion<Observation, icon, authored>:
  Categories.Inclusion{observation => evidence => project_icon_authored(observation, evidence)}

def project_icon_centered(-observation: Observation, evidence: icon(observation)) -> centered(observation):
  Icon{glyph, face, authored, centered, help, content} = evidence
  centered

def icon_centered() -> Categories.Inclusion<Observation, icon, centered>:
  Categories.Inclusion{observation => evidence => project_icon_centered(observation, evidence)}

def project_icon_glyph_centered(-observation: Observation, evidence: icon(observation)) -> glyph_centered(observation):
  Icon{glyph, face, authored, centered, help, content} = evidence
  content

def icon_glyph_centered() -> Categories.Inclusion<Observation, icon, glyph_centered>:
  Categories.Inclusion{observation => evidence => project_icon_glyph_centered(observation, evidence)}

def project_icon_help_inclusion(-observation: Observation, evidence: icon(observation)) -> icon_help(observation):
  Icon{glyph, face, authored, centered, help, content} = evidence
  help

def icon_help_inclusion() -> Categories.Inclusion<Observation, icon, icon_help>:
  Categories.Inclusion{observation => evidence => project_icon_help_inclusion(observation, evidence)}

def project_choice_authored(-observation: Observation, evidence: choice(observation)) -> authored(observation):
  Choice{text, description, glyph, selected, face, authored, leading} = evidence
  authored

def choice_authored() -> Categories.Inclusion<Observation, choice, authored>:
  Categories.Inclusion{observation => evidence => project_choice_authored(observation, evidence)}

def project_choice_leading(-observation: Observation, evidence: choice(observation)) -> leading(observation):
  Choice{text, description, glyph, selected, face, authored, leading} = evidence
  leading

def choice_leading() -> Categories.Inclusion<Observation, choice, leading>:
  Categories.Inclusion{observation => evidence => project_choice_leading(observation, evidence)}

def project_picker_authored(-observation: Observation, evidence: picker(observation)) -> authored(observation):
  Picker{glyph, text, face, authored, leading} = evidence
  authored

def picker_authored() -> Categories.Inclusion<Observation, picker, authored>:
  Categories.Inclusion{observation => evidence => project_picker_authored(observation, evidence)}

def project_picker_leading(-observation: Observation, evidence: picker(observation)) -> leading(observation):
  Picker{glyph, text, face, authored, leading} = evidence
  leading

def picker_leading() -> Categories.Inclusion<Observation, picker, leading>:
  Categories.Inclusion{observation => evidence => project_picker_leading(observation, evidence)}

law construction_evidence:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> authored(Observation{key, visual, parameters, button, source(key, visual, parameters, button)})

law icon_evidence:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> @+glyph:Controls.Icon -> requested_face(Observation{key, visual, parameters, button, source(key, visual, parameters, button)}, Controls.IconFace{glyph}) -> icon(Observation{key, visual, parameters, button, source(key, visual, parameters, button)})

law choice_evidence:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> @+text:String -> @+description:Maybe<&2, String> -> @+glyph:Maybe<&2, Controls.Icon> -> @+selected:Bool -> requested_face(Observation{key, visual, parameters, button, source(key, visual, parameters, button)}, Controls.ChoiceFace{text, description, glyph, selected}) -> choice(Observation{key, visual, parameters, button, source(key, visual, parameters, button)})

law picker_evidence:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> @+glyph:Maybe<&2, Controls.Icon> -> @+text:String -> requested_face(Observation{key, visual, parameters, button, source(key, visual, parameters, button)}, Controls.PickerFace{glyph, text}) -> picker(Observation{key, visual, parameters, button, source(key, visual, parameters, button)})

law construct:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> Categories.Membership<Observation, authored>

def constructed_node(constructed: Categories.Membership<Observation, authored>) -> Source.Node:
  Categories.Membership{Observation{key, visual, parameters, button, node}, evidence} = constructed
  node

law constructor_correspondence:
  @+key:UIIdentity.Key -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+button:Controls.Button -> {constructed_node(construct(key, visual, parameters, button)) == source(key, visual, parameters, button) : Source.Node}
