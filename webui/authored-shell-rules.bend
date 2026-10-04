import Base
import ./authored-shell.bend as Shell
import ./source.bend as Source
import ./document.bend as Doc
import ./physical-space.bend as Model
import ./typography.bend as Typography

def reframing_events(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.events_of(Shell.reframe(node, layout)) == Source.events_of(node) : +List<Doc.Event>}

def reframing_interaction(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.interaction_of(Shell.reframe(node, layout)) == Source.interaction_of(node) : Model.Interaction<Doc.Event>}

def reframing_children(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.children_of(Shell.reframe(node, layout)) == Source.children_of(node) : +List<Source.Node>}

def wrapper_children(key: String, style: Source.Style, +children: +List<Source.Node>) -> Type:
  {Source.children_of(Shell.wrap(key, style, children)) == children : +List<Source.Node>}

def wrapper_events(key: String, style: Source.Style, children: +List<Source.Node>) -> Type:
  {Source.events_of(Shell.wrap(key, style, children)) == Nil{} : +List<Doc.Event>}

def footer_children(key: String, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Type:
  {Source.children_of(Shell.with_footer(key, tag, style, attributes, children, settings, font)) == List.append(&2, Source.Node, children, Shell.spacer("/application/navigation-spacer", font) <> settings) : +List<Source.Node>}

type Requirements is Type:
  Requirements{
    events: @+node:Source.Node -> @+layout:Source.Layout -> reframing_events(node, layout),
    interaction: @+node:Source.Node -> @+layout:Source.Layout -> reframing_interaction(node, layout),
    children: @+node:Source.Node -> @+layout:Source.Layout -> reframing_children(node, layout),
    wrapper: @key:String -> @style:Source.Style -> @+children:+List<Source.Node> -> wrapper_children(key, style, children),
    no_wrapper_events: @key:String -> @style:Source.Style -> @children:+List<Source.Node> -> wrapper_events(key, style, children),
    footer: @key:String -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @+children:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+font:Typography.Presentation -> footer_children(key, tag, style, attributes, children, settings, font)
  }

law evidence:
  Requirements
