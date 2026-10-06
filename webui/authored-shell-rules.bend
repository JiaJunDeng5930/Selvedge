import Base
import ../core/ui-identity.bend as UIIdentity
import ./authored-shell.bend as Shell
import ./source.bend as Source
import ./document.bend as Doc
import ./physical-space.bend as Model
import ./typography.bend as Typography
import ./space.bend as Space

def reframing_events(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.events_of(Shell.reframe(node, layout)) == Source.events_of(node) : +List<Doc.Event>}

def reframing_interaction(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.interaction_of(Shell.reframe(node, layout)) == Source.interaction_of(node) : Model.Interaction<Doc.Event>}

def reframing_children(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.children_of(Shell.reframe(node, layout)) == Source.children_of(node) : +List<Source.Node>}

def wrapper_children(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Type:
  {Source.children_of(Shell.wrap(key, style, children)) == children : +List<Source.Node>}

def wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Type:
  {Source.events_of(Shell.wrap(key, style, children)) == Nil{} : +List<Doc.Event>}

def footer_children(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Type:
  {Source.children_of(Shell.with_footer(key, tag, style, attributes, children, settings, font)) == List.append(&2, Source.Node, children, Shell.spacer(UIIdentity.part(UIIdentity.place("/application"), "navigation-spacer"), font) <> settings) : +List<Source.Node>}


def reading_layout_axis(layout: Source.Layout) -> Model.AxisSize:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  width
def reading_axis(layout: Source.Layout, maximum: Nat) -> Model.AxisSize:
  reading_layout_axis(Shell.reading_layout(layout, maximum))

def axis_budget(size: Model.AxisSize) -> Nat:
  match size:
    case Model.LimitedSize{minimum, preferred_extra, maximum_extra}: Nat.add(Nat.add(minimum, preferred_extra), maximum_extra)
    case _: 0n

def reading_budget(+layout: Source.Layout, +maximum: Nat) -> Type:
  {axis_budget(reading_axis(layout, maximum)) == maximum : Nat}

def reading_dimension(layout: Source.Layout, maximum: Nat, minimum: Nat, preferred: Nat, offered: Nat) -> Maybe<&2, Space.Dimension>:
  Model.materialize(reading_axis(layout, maximum), minimum, preferred, offered)

# Neither a rejected materialization nor another dimension witnesses a reading fit.
def fit_budget(result: Maybe<&2, Space.Dimension>, maximum: Nat) -> Type:
  match result:
    case Some{Space.Fit{minimum, preferred_extra, maximum_extra}}:
      {Nat.add(Nat.add(minimum, preferred_extra), maximum_extra) == maximum : Nat}
    case _: {False{} == True{} : Bool}

def fit_width(result: Maybe<&2, Space.Dimension>, maximum: Nat, room: Nat) -> Type:
  match result:
    case Some{Space.Fit{minimum, preferred_extra, maximum_extra}}:
      {Nat.is_le(Space.choose(Space.Fit{minimum, preferred_extra, maximum_extra}, room), maximum) == True{} : Bool}
    case _: {False{} == True{} : Bool}

def reading_fit_budget(layout: Source.Layout, +maximum: Nat, minimum: Nat, preferred: Nat, offered: Nat) -> Type:
  fit_budget(reading_dimension(layout, maximum, minimum, preferred, offered), maximum)

def reading_fit_width(layout: Source.Layout, +maximum: Nat, minimum: Nat, preferred: Nat, offered: Nat, room: Nat) -> Type:
  fit_width(reading_dimension(layout, maximum, minimum, preferred, offered), maximum, room)

def front_layer_last(+first: Source.Node, +rest: +List<Source.Node>) -> Type:
  {Shell.back_to_front(first <> rest) == List.append(&2, Source.Node, Shell.back_to_front(rest), first <> Nil{}) : +List<Source.Node>}

type Requirements is Type:
  Requirements{
    front_layer_last: @+first:Source.Node -> @+rest:+List<Source.Node> -> front_layer_last(first, rest),
    events: @+node:Source.Node -> @+layout:Source.Layout -> reframing_events(node, layout),
    interaction: @+node:Source.Node -> @+layout:Source.Layout -> reframing_interaction(node, layout),
    children: @+node:Source.Node -> @+layout:Source.Layout -> reframing_children(node, layout),
    wrapper: @key:UIIdentity.Key -> @style:Source.Style -> @+children:+List<Source.Node> -> wrapper_children(key, style, children),
    no_wrapper_events: @key:UIIdentity.Key -> @style:Source.Style -> @children:+List<Source.Node> -> wrapper_events(key, style, children),
    reading_axis_budget: @+layout:Source.Layout -> @+maximum:Nat -> reading_budget(layout, maximum),
    reading_materialized_budget: @+layout:Source.Layout -> @+maximum:Nat -> @+minimum:Nat -> @+preferred:Nat -> @offered:Nat ->
      @natural:{Nat.is_le(minimum, preferred) == True{} : Bool} -> @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> reading_fit_budget(layout, maximum, minimum, preferred, offered),
    reading_allocated_width: @+layout:Source.Layout -> @+maximum:Nat -> @+minimum:Nat -> @+preferred:Nat -> @offered:Nat -> @+room:Nat ->
      @natural:{Nat.is_le(minimum, preferred) == True{} : Bool} -> @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> reading_fit_width(layout, maximum, minimum, preferred, offered, room),
    footer: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @+children:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+font:Typography.Presentation -> footer_children(key, tag, style, attributes, children, settings, font)
  }

law evidence:
  Requirements
