import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/stdlib.bend as Std
import ./BUTTONS.bend as Buttons
import ./PROGRAM.bend as Controls
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/MODEL.bend as View
import ../appearance/DESIGN.bend as Design
import ../layout/SPACE.bend as Space
import ../layout/enclosure.bend as Enclosure

def construction_evidence(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +button: Controls.Button) -> Buttons.authored(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}):
  Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback} = button
  Buttons.Authored{{==}, {==}, {==}, {==}, {==}, Buttons.Content{{==}, {==}}}

def Buttons.construction_evidence(): construction_evidence

def Buttons.construct():
  +key => +visual => +parameters => +button => Categories.Membership{Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}, Buttons.construction_evidence(key, visual, parameters, button)}

def Buttons.constructor_correspondence():
  +key => +visual => +parameters => +button => {==}

def icon_production(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +input: InteractionTypes.Input, +availability: View.Availability, +name: String, +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement, +feedback: Controls.Feedback, +glyph: Controls.Icon) -> Buttons.icon(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, Controls.IconFace{glyph}, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, Controls.IconFace{glyph}, behavior, geometry, placement, feedback})}):
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Controls.Geometry{demand, size, geometry_radius, leading} = geometry
  Space.Demand{minimum, preferred} = demand
  Enclosure.Extent{width, height} = minimum
  Buttons.Icon{glyph, {==}, construction_evidence(key, visual, parameters, Controls.Button{input, availability, name, Controls.IconFace{glyph}, behavior, geometry, placement, feedback}), Buttons.Centered{{==}, {==}}, {==}, {==}}

def icon_evidence(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +button: Controls.Button, +glyph: Controls.Icon, premise: Buttons.requested_face(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}, Controls.IconFace{glyph})) -> Buttons.icon(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}):
  Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback} = button
  Std.transport(Controls.Face, Controls.IconFace{glyph}, (replacement => Buttons.icon(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback})})), icon_production(key, visual, parameters, input, availability, name, behavior, geometry, placement, feedback, glyph), face, premise)

def Buttons.icon_evidence(): icon_evidence

def choice_production(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +input: InteractionTypes.Input, +availability: View.Availability, +name: String, +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement, +feedback: Controls.Feedback, +text: String, +description: Maybe<&2, String>, +glyph: Maybe<&2, Controls.Icon>, +selected: Bool) -> Buttons.choice(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, Controls.ChoiceFace{text, description, glyph, selected}, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, Controls.ChoiceFace{text, description, glyph, selected}, behavior, geometry, placement, feedback})}):
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  Buttons.Choice{text, description, glyph, selected, {==}, construction_evidence(key, visual, parameters, Controls.Button{input, availability, name, Controls.ChoiceFace{text, description, glyph, selected}, behavior, geometry, placement, feedback}), {==}}

def choice_evidence(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +button: Controls.Button, +text: String, +description: Maybe<&2, String>, +glyph: Maybe<&2, Controls.Icon>, +selected: Bool, premise: Buttons.requested_face(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}, Controls.ChoiceFace{text, description, glyph, selected})) -> Buttons.choice(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}):
  Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback} = button
  Std.transport(Controls.Face, Controls.ChoiceFace{text, description, glyph, selected}, (replacement => Buttons.choice(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback})})), choice_production(key, visual, parameters, input, availability, name, behavior, geometry, placement, feedback, text, description, glyph, selected), face, premise)

def Buttons.choice_evidence(): choice_evidence

def picker_production(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +input: InteractionTypes.Input, +availability: View.Availability, +name: String, +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement, +feedback: Controls.Feedback, +glyph: Maybe<&2, Controls.Icon>, +text: String) -> Buttons.picker(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, Controls.PickerFace{glyph, text}, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, Controls.PickerFace{glyph, text}, behavior, geometry, placement, feedback})}):
  Design.Style{font, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  Buttons.Picker{glyph, text, {==}, construction_evidence(key, visual, parameters, Controls.Button{input, availability, name, Controls.PickerFace{glyph, text}, behavior, geometry, placement, feedback}), {==}}

def picker_evidence(+key: UIIdentity.Key, +visual: Design.Style, +parameters: Design.LayoutParameters, +button: Controls.Button, +glyph: Maybe<&2, Controls.Icon>, +text: String, premise: Buttons.requested_face(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}, Controls.PickerFace{glyph, text})) -> Buttons.picker(Buttons.Observation{key, visual, parameters, button, Buttons.source(key, visual, parameters, button)}):
  Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback} = button
  Std.transport(Controls.Face, Controls.PickerFace{glyph, text}, (replacement => Buttons.picker(Buttons.Observation{key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback}, Buttons.source(key, visual, parameters, Controls.Button{input, availability, name, replacement, behavior, geometry, placement, feedback})})), picker_production(key, visual, parameters, input, availability, name, behavior, geometry, placement, feedback, glyph, text), face, premise)

def Buttons.picker_evidence(): picker_evidence
