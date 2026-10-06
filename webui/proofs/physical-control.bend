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
