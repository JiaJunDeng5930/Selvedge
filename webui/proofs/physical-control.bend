import Base
import ../../core/ui-identity.bend as UIIdentity
import ../document.bend as Doc
import ../source.bend as Source
import ../physical-space.bend as Model
import ../typography.bend as T
import ../design.bend as Design
import ../controls.bend as Controls
import ../physical-control-rules.bend as Rule

def attributes_consume_control_states(tag: Source.ControlTag, attrs: +List<Source.Attribute>, name: String,
  interaction: Model.Interaction<Doc.Event>) -> Rule.attributes_claim(tag, attrs, name, interaction):
  {==}

def rendered_controls_consume_control_states(key: UIIdentity.Key, tag: Source.ControlTag, style: Source.Style,
  attrs: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.Event,
  remaining: +List<Doc.Event>, original_children: +List<Source.Node>, font: T.Presentation,
  interaction: Model.Interaction<Doc.Event>, styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool) ->
  Rule.render_claim(key, tag, style, attrs, name, enabled, first, remaining, original_children, font, interaction, styles, children, native):
  {==}

def background_uses_rest_channel(chrome: Design.Chrome) -> Rule.background_channel_claim(chrome):
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def foreground_uses_rest_channel(chrome: Design.Chrome) -> Rule.foreground_channel_claim(chrome):
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  match shadow:
    case False{}: {==}
    case True{}: {==}

def Rule.evidence():
  Rule.Requirements{background_uses_rest_channel, foreground_uses_rest_channel, attributes_consume_control_states, rendered_controls_consume_control_states}

def Rule.keyboard_activation_total(event):
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

def Rule.keyboard_activation_empty(): {==}
def Rule.keyboard_activation_cons(first,remaining): {==}
def Rule.keyboard_control_display_only(): {==}
def Rule.keyboard_control_operable(first,remaining,enabled): {==}

def Rule.keyboard_attribute_projection(active,interaction,name):
  match active:
    case True{}: {==}
    case False{}: {==}

def Rule.nonnative_attribute_projection(attrs,name,interaction): {==}

def Rule.control_attribute_projection(tag,attrs,name,interaction):
  match tag:
    case Source.Button{}: {==}
    case Source.Summary{}: {==}
    case Source.ArticleControl{}: {==}
    case Source.DivControl{}: {==}
    case Source.SectionControl{}: {==}
    case Source.SpanControl{}: {==}

def Rule.source_control_interaction(key,tag,style,attrs,name,enabled,first,remaining,children): {==}
def Rule.rendered_control_projection(capacity,key,tag,style,attrs,name,enabled,first,remaining,original_children,font,interaction,styles,children,native): {==}

def Rule.native_field_probe_appearance(kind): {==}

def Rule.native_field_rendered_appearance(kind, rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def Rule.toggle_field_probe_appearance(): {==}

def Rule.toggle_field_rendered_appearance(rule):
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  {==}

def Rule.other_native_field_appearance(minimum, multiple): {==}

def Rule.toggle_geometry_bounded(): {==}
def Rule.toggle_geometry_centered(): {==}
def Rule.toggle_probe_rectangle(): {==}
def Rule.toggle_target_rectangle(): {==}
def Rule.toggle_visual_rectangle(style):
  Source.Style{layout, font, Design.Chrome{foreground, background, border, width, radius, shadow}, states} = style
  {==}
def Rule.production_toggle_face(key, meaning, name, placement, availability, typography, parameters):
  match placement:
    case Controls.AccessibleOnly{}: {==}
    case Controls.AboveInput{}: {==}
    case Controls.BesideInput{}: {==}
def Rule.unchecked_toggle_glyph(key): {==}
def Rule.toggle_authoring_allocation(key, meaning, name, placement, availability, visual, parameters):
  match placement visual:
    case Controls.AccessibleOnly{} Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case Controls.AboveInput{} Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
    case Controls.BesideInput{} Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states}: {==}
def Rule.beside_label_activation(key, name, visual, field):
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def Rule.toggle_rendered_composition(key, style, attrs, attributes, styles, events, children): {==}


def Rule.measurement_probe_targets(request, roots): {==}

def Rule.native_target_probe_targets(request, roots): {==}
