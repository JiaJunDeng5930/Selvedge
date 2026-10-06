import Base
import ../../core/ui-identity.bend as UIIdentity
import ../document.bend as Doc
import ../source.bend as Source
import ../physical-space.bend as Model
import ../typography.bend as T
import ../design.bend as Design
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
