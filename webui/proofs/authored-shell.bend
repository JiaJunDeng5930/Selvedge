import Base
import ../authored-shell.bend as Shell
import ../authored-shell-rules.bend as Rule
import ../source.bend as Source
import ../typography.bend as Typography

def events(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_events(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def interaction(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_interaction(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def children(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_children(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def wrapper(key: String, style: Source.Style, +children: +List<Source.Node>) -> Rule.wrapper_children(key, style, children):
  {==}

def no_wrapper_events(key: String, style: Source.Style, children: +List<Source.Node>) -> Rule.wrapper_events(key, style, children):
  {==}

def footer(key: String, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Rule.footer_children(key, tag, style, attributes, children, settings, font):
  {==}

def Rule.evidence():
  Rule.Requirements{events, interaction, children, wrapper, no_wrapper_events, footer}
