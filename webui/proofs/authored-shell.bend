import Base
import ../../core/ui-identity.bend as UIIdentity
import ../authored-shell.bend as Shell
import ../authored-shell-rules.bend as Rule
import ../source.bend as Source
import ../typography.bend as Typography
import ../physical-space.bend as Model
import ../space.bend as Space
import ../space-laws.bend as SpaceRules
import ./space.bend as Order
import ../../bendlib/proofs/logic.bend as Logic
import ./physical-space.bend as ModelProof
import ../../bendlib/proofs/algebra.bend as Alg
import ../../bendlib/stdlib.bend as Std

def events(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_events(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def interaction(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_interaction(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def children(+node: Source.Node, +layout: Source.Layout) -> Rule.reframing_children(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def wrapper(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Rule.wrapper_children(key, style, children):
  {==}

def no_wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Rule.wrapper_events(key, style, children):
  {==}

def footer(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Rule.footer_children(key, tag, style, attributes, children, settings, font):
  {==}


def reading_axis_budget(+layout: Source.Layout, +maximum: Nat) -> Rule.reading_budget(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  Alg.nat_add_zero(maximum)

# This is the lower-capacity premise of the production reading materialization.
def reading_capacity_lower(+minimum: Nat, +maximum: Nat, +preferred: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Nat.is_le(minimum, Nat.min(maximum, Nat.max(minimum, preferred))) == True{} : Bool}:
  match minimum maximum preferred:
    case 0n _ _: Order.zero_le(Nat.min(maximum, Nat.max(0n, preferred)))
    case 1n+lower 0n _: Logic.impossible({Nat.is_le(1n+lower, Nat.min(0n, Nat.max(1n+lower, preferred))) == True{} : Bool}, fits)
    case 1n+lower 1n+cap 0n:
      Equal.trans(Bool, Nat.is_le(lower, Nat.min(cap, lower)), Nat.is_le(lower, Nat.min(cap, Nat.max(lower, 0n))), True{},
        Equal.sym(Bool, Nat.is_le(lower, Nat.min(cap, Nat.max(lower, 0n))), Nat.is_le(lower, Nat.min(cap, lower)),
          Equal.cong(Nat, Bool, (n => Nat.is_le(lower, Nat.min(cap, n))), Nat.max(lower, 0n), lower, ModelProof.max_zero(lower))),
        reading_capacity_lower(lower, cap, 0n, fits))
    case 1n+lower 1n+cap 1n+target: reading_capacity_lower(lower, cap, target, fits)

def reading_materialized(+layout: Source.Layout, +maximum: Nat, +minimum: Nat, +preferred: Nat, offered: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Rule.reading_dimension(layout, maximum, minimum, preferred, offered) ==
    Some{Space.Fit{minimum, Nat.sub(Nat.min(maximum, Nat.max(minimum, preferred)), minimum), Nat.sub(maximum, Nat.min(maximum, Nat.max(minimum, preferred)))}} : Maybe<&2, Space.Dimension>}:
  Source.Layout{direction, main, cross, frame, width, height, floor, scroll, position} = layout
  +chosen = Nat.min(maximum, Nat.max(minimum, preferred))
  normalized = Equal.cong(Nat, Maybe<&2, Space.Dimension>,
    (cap => Model.accept_dimension(Nat.is_le(Nat.max(minimum, 0n), cap), Space.Fit{Nat.max(minimum, 0n), Nat.sub(Nat.min(cap, Nat.max(Nat.max(minimum, 0n), preferred)), Nat.max(minimum, 0n)), Nat.sub(cap, Nat.min(cap, Nat.max(Nat.max(minimum, 0n), preferred)))})),
    Nat.add(maximum, 0n), maximum, Alg.nat_add_zero(maximum))
  lower = Equal.cong(Nat, Maybe<&2, Space.Dimension>,
    (base => Model.accept_dimension(Nat.is_le(base, maximum), Space.Fit{base, Nat.sub(Nat.min(maximum, Nat.max(base, preferred)), base), Nat.sub(maximum, Nat.min(maximum, Nat.max(base, preferred)))})),
    Nat.max(minimum, 0n), minimum, ModelProof.max_zero(minimum))
  accepted = Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    (valid => Model.accept_dimension(valid, Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)})), Nat.is_le(minimum, maximum), True{}, fits)
  Equal.trans(Maybe<&2, Space.Dimension>, Rule.reading_dimension(Source.Layout{direction, main, cross, frame, width, height, floor, scroll, position}, maximum, minimum, preferred, offered),
    Model.accept_dimension(Nat.is_le(Nat.max(minimum, 0n), maximum), Space.Fit{Nat.max(minimum, 0n), Nat.sub(Nat.min(maximum, Nat.max(Nat.max(minimum, 0n), preferred)), Nat.max(minimum, 0n)), Nat.sub(maximum, Nat.min(maximum, Nat.max(Nat.max(minimum, 0n), preferred)))}),
    Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}}, normalized,
    Equal.trans(Maybe<&2, Space.Dimension>, Model.accept_dimension(Nat.is_le(Nat.max(minimum, 0n), maximum), Space.Fit{Nat.max(minimum, 0n), Nat.sub(Nat.min(maximum, Nat.max(Nat.max(minimum, 0n), preferred)), Nat.max(minimum, 0n)), Nat.sub(maximum, Nat.min(maximum, Nat.max(Nat.max(minimum, 0n), preferred)))}),
      Model.accept_dimension(Nat.is_le(minimum, maximum), Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}), Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}}, lower, accepted))

def reading_fit_balance(+maximum: Nat, +minimum: Nat, +preferred: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Nat.add(Nat.add(minimum, Nat.sub(Nat.min(maximum, Nat.max(minimum, preferred)), minimum)), Nat.sub(maximum, Nat.min(maximum, Nat.max(minimum, preferred)))) == maximum : Nat}:
  +chosen = Nat.min(maximum, Nat.max(minimum, preferred))
  lower_fits = Equal.trans(Bool, Nat.is_le(Nat.add(minimum, 0n), chosen), Nat.is_le(minimum, chosen), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, chosen)), Nat.add(minimum, 0n), minimum, Alg.nat_add_zero(minimum)), reading_capacity_lower(minimum, maximum, preferred, fits))
  cap_fits = Equal.trans(Bool, Nat.is_le(Nat.add(chosen, 0n), maximum), Nat.is_le(chosen, maximum), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, maximum)), Nat.add(chosen, 0n), chosen, Alg.nat_add_zero(chosen)), Order.min_le_first(maximum, Nat.max(minimum, preferred)))
  lower_balance = Order.second({Nat.is_le(0n, Nat.sub(chosen, minimum)) == True{} : Bool},
    {Nat.add(minimum, Nat.sub(chosen, minimum)) == chosen : Nat}, Order.residual(minimum, 0n, chosen, lower_fits))
  cap_balance = Order.second({Nat.is_le(0n, Nat.sub(maximum, chosen)) == True{} : Bool},
    {Nat.add(chosen, Nat.sub(maximum, chosen)) == maximum : Nat}, Order.residual(chosen, 0n, maximum, cap_fits))
  Equal.trans(Nat, Nat.add(Nat.add(minimum, Nat.sub(chosen, minimum)), Nat.sub(maximum, chosen)), Nat.add(chosen, Nat.sub(maximum, chosen)), maximum,
    Equal.cong(Nat, Nat, (n => Nat.add(n, Nat.sub(maximum, chosen))), Nat.add(minimum, Nat.sub(chosen, minimum)), chosen, lower_balance), cap_balance)

def reading_materialized_budget(+layout: Source.Layout, +maximum: Nat, +minimum: Nat, +preferred: Nat, offered: Nat,
  natural: {Nat.is_le(minimum, preferred) == True{} : Bool}, +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) -> Rule.reading_fit_budget(layout, maximum, minimum, preferred, offered):
  +chosen = Nat.min(maximum, Nat.max(minimum, preferred))
  Std.transport(Maybe<&2, Space.Dimension>, Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}},
    (result => Rule.fit_budget(result, maximum)), reading_fit_balance(maximum, minimum, preferred, fits),
    Rule.reading_dimension(layout, maximum, minimum, preferred, offered), reading_materialized(layout, maximum, minimum, preferred, offered, fits))

def reading_allocated_width(+layout: Source.Layout, +maximum: Nat, +minimum: Nat, +preferred: Nat, offered: Nat, +room: Nat,
  natural: {Nat.is_le(minimum, preferred) == True{} : Bool}, +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) -> Rule.reading_fit_width(layout, maximum, minimum, preferred, offered, room):
  +chosen = Nat.min(maximum, Nat.max(minimum, preferred))
  +dimension: Space.Dimension = Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}
  balance = reading_fit_balance(maximum, minimum, preferred, fits)
  upper = Equal.trans(Bool, Nat.is_le(Space.choose(dimension, room), maximum), SpaceRules.maximum_ok(dimension, Space.choose(dimension, room)), True{},
    Equal.sym(Bool, SpaceRules.maximum_ok(dimension, Space.choose(dimension, room)), Nat.is_le(Space.choose(dimension, room), maximum),
      Equal.cong(Nat, Bool, (n => Nat.is_le(Space.choose(dimension, room), n)), Nat.add(Nat.add(minimum, Nat.sub(chosen, minimum)), Nat.sub(maximum, chosen)), maximum, balance)), Order.chosen_upper(dimension, room))
  Std.transport(Maybe<&2, Space.Dimension>, Some{dimension}, (result => Rule.fit_width(result, maximum, room)), upper,
    Rule.reading_dimension(layout, maximum, minimum, preferred, offered), reading_materialized(layout, maximum, minimum, preferred, offered, fits))

def reverse_layer_accumulator(+remaining: +List<Source.Node>, +acc: +List<Source.Node>, +behind: +List<Source.Node>) ->
  {List.reverse.go(&2, Source.Node, remaining, List.append(&2, Source.Node, acc, behind)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, remaining, acc), behind) : +List<Source.Node>}:
  Std.list_ind(~Source.Node,
    ~(layers => @+accumulator:+List<Source.Node> -> @+background:+List<Source.Node> ->
      {List.reverse.go(&2, Source.Node, layers, List.append(&2, Source.Node, accumulator, background)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, layers, accumulator), background) : +List<Source.Node>}),
    ~(+accumulator => +background => {==}),
    ~(+front => +rest => hypothesis => +accumulator => +background => hypothesis(front <> accumulator, background)), remaining)(acc, behind)

def front_layer_last(+first: Source.Node, +rest: +List<Source.Node>) -> Rule.front_layer_last(first, rest):
  reverse_layer_accumulator(rest, Nil{}, first <> Nil{})

def Rule.evidence():
  Rule.Requirements{front_layer_last, events, interaction, children, wrapper, no_wrapper_events, reading_axis_budget, reading_materialized_budget, reading_allocated_width, footer}
