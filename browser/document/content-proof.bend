import Base
import ../controls/PROGRAM.bend as Controls
import ./CONTRACT.bend as Rule
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ./presentation-order.bend as Order
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/algebra-proof.bend as Alg
import ../MODEL.bend as Web
import ../../bendlib/logic-proof.bend as Logic
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/MODEL.bend as View
import ../appearance/DESIGN.bend as Design
import ../controls/MODEL.bend as Authored
import ../layout/physical-space.bend as Model
import ../layout/enclosure.bend as Enclosure
import ./SOURCE.bend as Source
import ../appearance/TYPOGRAPHY.bend as T

def panel_header_matches_specification(representation: Controls.Representation) ->
  {Controls.panel_header(representation) == Rule.specified_header_representation(representation) : Bool}:
  match representation:
    case Controls.NoControl{}: {==}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      match placement:
        case Controls.InFlow{}: {==}
        case Controls.ComposerEnd{}: {==}
        case Controls.PanelHeaderEnd{}: {==}
        case Controls.CodeToolbar{}: {==}
        case Controls.BesideValue{}: {==}
        case Controls.GroupHeadingEnd{}: {==}
    case Controls.Input{binding, name, widget, label, availability}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}: {==}

def header_classifier_matches_specification(value: SurfaceTypes.Node, +context: Controls.Context) ->
  {Order.header_child(value, context) == Rule.specified_header_child(value, context) : Bool}:
  match value:
    case SurfaceTypes.Node{+key, semantic, +label, +role, +meaning, children}:
      panel_header_matches_specification(Controls.represent(key, meaning, label, role,
        Controls.enter(value, context)))

def partition_header_step_matches(value: SurfaceTypes.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_header(Order.partition_child(value, include, parts)) ==
    Rule.header_step(value, include, Order.partition_header(parts)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_body_step_matches(value: SurfaceTypes.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_body(Order.partition_child(value, include, parts)) ==
    Rule.body_step(value, include, Order.partition_body(parts)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_header_matches_specification(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Order.partition_header(Order.partition_dialog_children(values, context)) == Rule.specified_header(values, context) : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_header_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = Rule.specified_header_child(value, context)
      Equal.trans(+List<SurfaceTypes.Node>,
        Order.partition_header(Order.partition_child(value, actual_include, tail_parts)),
        Rule.header_step(value, actual_include, Order.partition_header(tail_parts)),
        Rule.header_step(value, specified_include, Rule.specified_header(rest, context)),
        partition_header_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.header_step(value, actual_include, Order.partition_header(tail_parts)),
          Rule.header_step(value, specified_include, Order.partition_header(tail_parts)),
          Rule.header_step(value, specified_include, Rule.specified_header(rest, context)),
          Equal.cong(Bool, +List<SurfaceTypes.Node>, (include => Rule.header_step(value, include, Order.partition_header(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => Rule.header_step(value, specified_include, tail)),
            Order.partition_header(tail_parts), Rule.specified_header(rest, context), tail_evidence)))

def partition_body_matches_specification(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Order.partition_body(Order.partition_dialog_children(values, context)) == Rule.specified_body(values, context) : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_body_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = Rule.specified_header_child(value, context)
      Equal.trans(+List<SurfaceTypes.Node>,
        Order.partition_body(Order.partition_child(value, actual_include, tail_parts)),
        Rule.body_step(value, actual_include, Order.partition_body(tail_parts)),
        Rule.body_step(value, specified_include, Rule.specified_body(rest, context)),
        partition_body_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.body_step(value, actual_include, Order.partition_body(tail_parts)),
          Rule.body_step(value, specified_include, Order.partition_body(tail_parts)),
          Rule.body_step(value, specified_include, Rule.specified_body(rest, context)),
          Equal.cong(Bool, +List<SurfaceTypes.Node>, (include => Rule.body_step(value, include, Order.partition_body(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => Rule.body_step(value, specified_include, tail)),
            Order.partition_body(tail_parts), Rule.specified_body(rest, context), tail_evidence)))

def parts_match_filters(parts: Order.DialogParts, expected_header: +List<SurfaceTypes.Node>,
  expected_body: +List<SurfaceTypes.Node>,
  header_evidence: {Order.partition_header(parts) == expected_header : +List<SurfaceTypes.Node>},
  body_evidence: {Order.partition_body(parts) == expected_body : +List<SurfaceTypes.Node>}) ->
  {parts == Order.DialogParts{expected_header, expected_body} : Order.DialogParts}:
  match parts:
    case Order.DialogParts{+header, +body}:
      Equal.trans(Order.DialogParts, Order.DialogParts{header, body},
        Order.DialogParts{expected_header, body}, Order.DialogParts{expected_header, expected_body},
        Equal.cong(+List<SurfaceTypes.Node>, Order.DialogParts,
          (value => Order.DialogParts{value, body}), header, expected_header, header_evidence),
        Equal.cong(+List<SurfaceTypes.Node>, Order.DialogParts,
          (value => Order.DialogParts{expected_header, value}), body, expected_body, body_evidence))

def partition_matches_specification(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Order.partition_dialog_children(values, context) == Rule.specified_parts(values, context) : Order.DialogParts}:
  parts_match_filters(Order.partition_dialog_children(values, context),
    Rule.specified_header(values, context), Rule.specified_body(values, context),
    partition_header_matches_specification(values, context),
    partition_body_matches_specification(values, context))

def ordered_children_matches_specification(+values: +List<SurfaceTypes.Node>, role: SurfaceTypes.Role, +context: Controls.Context) ->
  {Order.ordered_children(role, values, context) == Rule.specified_children(role, values, context) : +List<SurfaceTypes.Node>}:
  match role:
    case SurfaceTypes.Dialog{}:
      +parts_evidence = partition_matches_specification(values, context)
      Equal.cong(Order.DialogParts, +List<SurfaceTypes.Node>, (parts => Order.ordered_dialog_children(parts)),
        Order.partition_dialog_children(values, context), Rule.specified_parts(values, context), parts_evidence)
    case SurfaceTypes.Navigation{}: {==}
    case SurfaceTypes.NavigationHeader{}: {==}
    case SurfaceTypes.Main{}: {==}
    case SurfaceTypes.Heading{}: {==}
    case SurfaceTypes.PrimaryButton{}: {==}
    case SurfaceTypes.DestructiveButton{}: {==}
    case SurfaceTypes.SelectedButton{}: {==}
    case SurfaceTypes.ComposerActions{}: {==}
    case SurfaceTypes.DialogActions{}: {==}
    case SurfaceTypes.Timeline{}: {==}
    case SurfaceTypes.Activity{}: {==}
    case SurfaceTypes.UserMessage{}: {==}
    case SurfaceTypes.AssistantMessage{}: {==}
    case SurfaceTypes.Composer{}: {==}
    case SurfaceTypes.Approval{}: {==}
    case SurfaceTypes.Toolbar{}: {==}
    case SurfaceTypes.CodeBlock{}: {==}
    case SurfaceTypes.ApprovalQueue{}: {==}
    case SurfaceTypes.Section{}: {==}
    case SurfaceTypes.Menu{}: {==}
    case SurfaceTypes.Details{}: {==}
    case SurfaceTypes.Card{}: {==}
    case SurfaceTypes.Button{}: {==}
    case SurfaceTypes.Field{}: {==}
    case SurfaceTypes.Content{}: {==}
    case SurfaceTypes.Alert{}: {==}

def non_dialog_order(role: SurfaceTypes.Role, +values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.non_dialog_order_observation(role, values, context) == values : +List<SurfaceTypes.Node>}:
  match role:
    case SurfaceTypes.Dialog{}: {==}
    case SurfaceTypes.Navigation{}: {==}
    case SurfaceTypes.NavigationHeader{}: {==}
    case SurfaceTypes.Main{}: {==}
    case SurfaceTypes.Heading{}: {==}
    case SurfaceTypes.PrimaryButton{}: {==}
    case SurfaceTypes.DestructiveButton{}: {==}
    case SurfaceTypes.SelectedButton{}: {==}
    case SurfaceTypes.ComposerActions{}: {==}
    case SurfaceTypes.DialogActions{}: {==}
    case SurfaceTypes.Timeline{}: {==}
    case SurfaceTypes.Activity{}: {==}
    case SurfaceTypes.UserMessage{}: {==}
    case SurfaceTypes.AssistantMessage{}: {==}
    case SurfaceTypes.Composer{}: {==}
    case SurfaceTypes.Approval{}: {==}
    case SurfaceTypes.Toolbar{}: {==}
    case SurfaceTypes.CodeBlock{}: {==}
    case SurfaceTypes.ApprovalQueue{}: {==}
    case SurfaceTypes.Section{}: {==}
    case SurfaceTypes.Menu{}: {==}
    case SurfaceTypes.Details{}: {==}
    case SurfaceTypes.Card{}: {==}
    case SurfaceTypes.Button{}: {==}
    case SurfaceTypes.Field{}: {==}
    case SurfaceTypes.Content{}: {==}
    case SurfaceTypes.Alert{}: {==}

def specified_header_append_step(value: SurfaceTypes.Node, rest: +List<SurfaceTypes.Node>, right: +List<SurfaceTypes.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {Rule.specified_header(List.append(&2, SurfaceTypes.Node, rest, right), context) ==
    List.append(&2, SurfaceTypes.Node, Rule.specified_header(rest, context), Rule.specified_header(right, context)) : +List<SurfaceTypes.Node>}) ->
  {Rule.header_step(value, include, Rule.specified_header(List.append(&2, SurfaceTypes.Node, rest, right), context)) ==
    List.append(&2, SurfaceTypes.Node, Rule.header_step(value, include, Rule.specified_header(rest, context)), Rule.specified_header(right, context)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}:
      Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => value <> tail),
        Rule.specified_header(List.append(&2, SurfaceTypes.Node, rest, right), context),
        List.append(&2, SurfaceTypes.Node, Rule.specified_header(rest, context), Rule.specified_header(right, context)),
        tail_evidence)
    case False{}: tail_evidence

def specified_body_append_step(value: SurfaceTypes.Node, rest: +List<SurfaceTypes.Node>, right: +List<SurfaceTypes.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {Rule.specified_body(List.append(&2, SurfaceTypes.Node, rest, right), context) ==
    List.append(&2, SurfaceTypes.Node, Rule.specified_body(rest, context), Rule.specified_body(right, context)) : +List<SurfaceTypes.Node>}) ->
  {Rule.body_step(value, include, Rule.specified_body(List.append(&2, SurfaceTypes.Node, rest, right), context)) ==
    List.append(&2, SurfaceTypes.Node, Rule.body_step(value, include, Rule.specified_body(rest, context)), Rule.specified_body(right, context)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => value <> tail),
        Rule.specified_body(List.append(&2, SurfaceTypes.Node, rest, right), context),
        List.append(&2, SurfaceTypes.Node, Rule.specified_body(rest, context), Rule.specified_body(right, context)),
        tail_evidence)

def specified_header_append(+left: +List<SurfaceTypes.Node>, +right: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_header(List.append(&2, SurfaceTypes.Node, left, right), context) ==
    List.append(&2, SurfaceTypes.Node, Rule.specified_header(left, context), Rule.specified_header(right, context)) : +List<SurfaceTypes.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_append(rest, right, context)
      specified_header_append_step(value, rest, right, Rule.specified_header_child(value, context), context,
        tail_evidence)

def specified_body_append(+left: +List<SurfaceTypes.Node>, +right: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_body(List.append(&2, SurfaceTypes.Node, left, right), context) ==
    List.append(&2, SurfaceTypes.Node, Rule.specified_body(left, context), Rule.specified_body(right, context)) : +List<SurfaceTypes.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_append(rest, right, context)
      specified_body_append_step(value, rest, right, Rule.specified_header_child(value, context), context,
        tail_evidence)

def specified_header_idempotent_step(+value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_header(Rule.specified_header(rest, context), context) == Rule.specified_header(rest, context) : +List<SurfaceTypes.Node>}) ->
  {Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context) ==
    Rule.header_step(value, include, Rule.specified_header(rest, context)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<SurfaceTypes.Node>,
        (flag => Rule.header_step(value, flag, Rule.specified_header(Rule.specified_header(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>,
        (tail => Rule.header_step(value, include, tail)),
        Rule.specified_header(Rule.specified_header(rest, context), context), Rule.specified_header(rest, context), tail_evidence)
      Equal.trans(+List<SurfaceTypes.Node>,
        Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
        Rule.header_step(value, include, Rule.specified_header(Rule.specified_header(rest, context), context)),
        Rule.header_step(value, include, Rule.specified_header(rest, context)),
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
          Rule.header_step(value, Rule.specified_header_child(value, context), Rule.specified_header(Rule.specified_header(rest, context), context)),
          Rule.header_step(value, include, Rule.specified_header(Rule.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_step)
    case False{}: tail_evidence

def specified_body_idempotent_step(+value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_body(Rule.specified_body(rest, context), context) == Rule.specified_body(rest, context) : +List<SurfaceTypes.Node>}) ->
  {Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context) ==
    Rule.body_step(value, include, Rule.specified_body(rest, context)) : +List<SurfaceTypes.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<SurfaceTypes.Node>,
        (flag => Rule.body_step(value, flag, Rule.specified_body(Rule.specified_body(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>,
        (tail => Rule.body_step(value, include, tail)),
        Rule.specified_body(Rule.specified_body(rest, context), context), Rule.specified_body(rest, context), tail_evidence)
      Equal.trans(+List<SurfaceTypes.Node>,
        Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
        Rule.body_step(value, include, Rule.specified_body(Rule.specified_body(rest, context), context)),
        Rule.body_step(value, include, Rule.specified_body(rest, context)),
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
          Rule.body_step(value, Rule.specified_header_child(value, context), Rule.specified_body(Rule.specified_body(rest, context), context)),
          Rule.body_step(value, include, Rule.specified_body(Rule.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_step)

def specified_header_after_body_step(+value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_header(Rule.specified_body(rest, context), context) == Nil{} : +List<SurfaceTypes.Node>}) ->
  {Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context) == Nil{} : +List<SurfaceTypes.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<SurfaceTypes.Node>,
        (flag => Rule.header_step(value, flag, Rule.specified_header(Rule.specified_body(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<SurfaceTypes.Node>,
        Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
        Rule.header_step(value, include, Rule.specified_header(Rule.specified_body(rest, context), context)),
        Nil{},
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
          Rule.header_step(value, Rule.specified_header_child(value, context), Rule.specified_header(Rule.specified_body(rest, context), context)),
          Rule.header_step(value, include, Rule.specified_header(Rule.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)

def specified_body_after_header_step(+value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_body(Rule.specified_header(rest, context), context) == Nil{} : +List<SurfaceTypes.Node>}) ->
  {Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context) == Nil{} : +List<SurfaceTypes.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<SurfaceTypes.Node>,
        (flag => Rule.body_step(value, flag, Rule.specified_body(Rule.specified_header(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<SurfaceTypes.Node>,
        Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
        Rule.body_step(value, include, Rule.specified_body(Rule.specified_header(rest, context), context)),
        Nil{},
        Equal.trans(+List<SurfaceTypes.Node>,
          Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
          Rule.body_step(value, Rule.specified_header_child(value, context), Rule.specified_body(Rule.specified_header(rest, context), context)),
          Rule.body_step(value, include, Rule.specified_body(Rule.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)
    case False{}: tail_evidence

def specified_header_idempotent(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_header(values, context), context) == Rule.specified_header(values, context) : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_idempotent(rest, context)
      specified_header_idempotent_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_idempotent(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_body(values, context), context) == Rule.specified_body(values, context) : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_idempotent(rest, context)
      specified_body_idempotent_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_after_body(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_body(values, context), context) == Nil{} : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_after_body(rest, context)
      specified_header_after_body_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_after_header(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_header(values, context), context) == Nil{} : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_after_header(rest, context)
      specified_body_after_header_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_of_order(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_order(values, context), context) == Rule.specified_header(values, context) : +List<SurfaceTypes.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  +split = specified_header_append(headers, bodies, context)
  +headers_repeat = specified_header_idempotent(values, context)
  +body_empty = specified_header_after_body(values, context)
  +filtered_headers = Rule.specified_header(headers, context)
  +filtered_bodies = Rule.specified_header(bodies, context)
  Equal.trans(+List<SurfaceTypes.Node>,
    Rule.specified_header(Rule.specified_order(values, context), context),
    List.append(&2, SurfaceTypes.Node, filtered_headers, filtered_bodies),
    headers, split,
    Equal.trans(+List<SurfaceTypes.Node>,
      List.append(&2, SurfaceTypes.Node, filtered_headers, filtered_bodies),
      List.append(&2, SurfaceTypes.Node, headers, Nil{}),
      headers,
      Equal.trans(+List<SurfaceTypes.Node>,
        List.append(&2, SurfaceTypes.Node, filtered_headers, filtered_bodies),
        List.append(&2, SurfaceTypes.Node, headers, filtered_bodies),
        List.append(&2, SurfaceTypes.Node, headers, Nil{}),
        Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (head => List.append(&2, SurfaceTypes.Node, head, filtered_bodies)),
          filtered_headers, headers, headers_repeat),
        Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => List.append(&2, SurfaceTypes.Node, headers, tail)),
          filtered_bodies, Nil{}, body_empty)),
      Std.app_nil_r(SurfaceTypes.Node, headers)))

def specified_body_of_order(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_order(values, context), context) == Rule.specified_body(values, context) : +List<SurfaceTypes.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  +split = specified_body_append(headers, bodies, context)
  +header_empty = specified_body_after_header(values, context)
  +bodies_repeat = specified_body_idempotent(values, context)
  Equal.trans(+List<SurfaceTypes.Node>,
    Rule.specified_body(Rule.specified_order(values, context), context),
    List.append(&2, SurfaceTypes.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
    bodies, split,
    Equal.trans(+List<SurfaceTypes.Node>,
      List.append(&2, SurfaceTypes.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
      List.append(&2, SurfaceTypes.Node, Nil{}, bodies),
      bodies,
      Equal.trans(+List<SurfaceTypes.Node>,
        List.append(&2, SurfaceTypes.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
        List.append(&2, SurfaceTypes.Node, Nil{}, Rule.specified_body(bodies, context)),
        List.append(&2, SurfaceTypes.Node, Nil{}, bodies),
        Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (head => List.append(&2, SurfaceTypes.Node, head, Rule.specified_body(bodies, context))),
          Rule.specified_body(headers, context), Nil{}, header_empty),
        Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => List.append(&2, SurfaceTypes.Node, Nil{}, tail)),
          Rule.specified_body(bodies, context), bodies, bodies_repeat)),
      {==}))

def specified_order_idempotent(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Rule.specified_order(Rule.specified_order(values, context), context) == Rule.specified_order(values, context) : +List<SurfaceTypes.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  Equal.trans(+List<SurfaceTypes.Node>,
    Rule.specified_order(Rule.specified_order(values, context), context),
    List.append(&2, SurfaceTypes.Node, Rule.specified_header(Rule.specified_order(values, context), context),
      Rule.specified_body(Rule.specified_order(values, context), context)),
    List.append(&2, SurfaceTypes.Node, headers, bodies),
    {==},
    Equal.trans(+List<SurfaceTypes.Node>,
      List.append(&2, SurfaceTypes.Node, Rule.specified_header(Rule.specified_order(values, context), context),
        Rule.specified_body(Rule.specified_order(values, context), context)),
      List.append(&2, SurfaceTypes.Node, headers, Rule.specified_body(Rule.specified_order(values, context), context)),
      List.append(&2, SurfaceTypes.Node, headers, bodies),
      Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (head => List.append(&2, SurfaceTypes.Node, head,
        Rule.specified_body(Rule.specified_order(values, context), context))),
        Rule.specified_header(Rule.specified_order(values, context), context), headers,
        specified_header_of_order(values, context)),
    Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>, (tail => List.append(&2, SurfaceTypes.Node, headers, tail)),
        Rule.specified_body(Rule.specified_order(values, context), context), bodies,
        specified_body_of_order(values, context))))

def dialog_order_idempotent(+values: +List<SurfaceTypes.Node>, +context: Controls.Context) ->
  {Order.ordered_children(SurfaceTypes.Dialog{}, Order.ordered_children(SurfaceTypes.Dialog{}, values, context), context) ==
    Order.ordered_children(SurfaceTypes.Dialog{}, values, context) : +List<SurfaceTypes.Node>}:
  +first_order = Order.ordered_children(SurfaceTypes.Dialog{}, values, context)
  +first_evidence = ordered_children_matches_specification(values, SurfaceTypes.Dialog{}, context)
  +second_evidence = ordered_children_matches_specification(first_order, SurfaceTypes.Dialog{}, context)
  +lifted_first = Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>,
    (children => Rule.specified_order(children, context)), first_order, Rule.specified_order(values, context), first_evidence)
  Equal.trans(+List<SurfaceTypes.Node>,
    Order.ordered_children(SurfaceTypes.Dialog{}, first_order, context),
    Rule.specified_order(first_order, context),
    Order.ordered_children(SurfaceTypes.Dialog{}, values, context),
    second_evidence,
    Equal.trans(+List<SurfaceTypes.Node>,
      Rule.specified_order(first_order, context), Rule.specified_order(Rule.specified_order(values, context), context),
      Order.ordered_children(SurfaceTypes.Dialog{}, values, context),
      lifted_first,
      Equal.trans(+List<SurfaceTypes.Node>,
        Rule.specified_order(Rule.specified_order(values, context), context), Rule.specified_order(values, context),
        Order.ordered_children(SurfaceTypes.Dialog{}, values, context),
        specified_order_idempotent(values, context),
        Equal.sym(+List<SurfaceTypes.Node>, Order.ordered_children(SurfaceTypes.Dialog{}, values, context),
          Rule.specified_order(values, context), first_evidence))))

def node_with_children_preserves_payload(+value: SurfaceTypes.Node, +children: +List<SurfaceTypes.Node>) ->
  {Rule.node_payload(Order.node_with_children(value, children)) == Rule.node_payload(value) : Rule.NodePayload}:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, meaning, original_children}: {==}

def ordered_surface_preserves_content_scope(surface: SurfaceTypes.Surface) ->
  {Rule.surface_payload(Order.ordered_surface(surface)) == Rule.surface_payload(surface) : Rule.SurfacePayload}:
  match surface:
    case SurfaceTypes.Surface{content, base, overlays, active_scope}: {==}

def count_append_step(+predicate: Rule.CountPredicate, +value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>,
  +right: +List<SurfaceTypes.Node>, included: Bool,
  tail_evidence: {Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, rest, right)) ==
    Nat.add(Rule.count_by(predicate, rest), Rule.count_by(predicate, right)) : Nat}) ->
  {Rule.occurrence_step(included, Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, rest, right))) ==
    Nat.add(Rule.occurrence_step(included, Rule.count_by(predicate, rest)), Rule.count_by(predicate, right)) : Nat}:
  match included:
    case True{}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, rest, right)),
        Nat.add(Rule.count_by(predicate, rest), Rule.count_by(predicate, right)), tail_evidence)
    case False{}: tail_evidence

def count_append(+predicate: Rule.CountPredicate, +left: +List<SurfaceTypes.Node>, +right: +List<SurfaceTypes.Node>) ->
  {Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, left, right)) ==
    Nat.add(Rule.count_by(predicate, left), Rule.count_by(predicate, right)) : Nat}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = count_append(predicate, rest, right)
      count_append_step(predicate, value, rest, right, Rule.count_matches(predicate, value), tail_evidence)

def body_count_step(included: Bool, prefix: Nat, suffix: Nat) ->
  {Nat.add(prefix, Rule.occurrence_step(included, suffix)) ==
    Rule.occurrence_step(included, Nat.add(prefix, suffix)) : Nat}:
  match included:
    case True{}: Alg.nat_add_succ(prefix, suffix)
    case False{}: {==}

def partition_count_step(+predicate: Rule.CountPredicate, +value: SurfaceTypes.Node, +rest: +List<SurfaceTypes.Node>,
  include: Bool, tail_parts: Order.DialogParts, +context: Controls.Context,
  tail_evidence: {Rule.count_by(predicate, Order.ordered_dialog_children(tail_parts)) ==
    Rule.count_by(predicate, rest) : Nat}) ->
  {Rule.count_by(predicate,
      Order.ordered_dialog_children(Order.partition_child(value, include, tail_parts))) ==
    Rule.count_by(predicate, value <> rest) : Nat}:
  match include:
    case True{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          Equal.cong(Nat, Nat, (count => Rule.occurrence_step(Rule.count_matches(predicate, value), count)),
            Rule.count_by(predicate, Order.ordered_dialog_children(tail_parts)),
            Rule.count_by(predicate, rest), tail_evidence)
    case False{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          +join_evidence = count_append(predicate, headers, bodies)
          +tail_relation = Equal.trans(Nat,
            Nat.add(Rule.count_by(predicate, headers), Rule.count_by(predicate, bodies)),
            Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, headers, bodies)),
            Rule.count_by(predicate, rest),
            Equal.sym(Nat, Rule.count_by(predicate, List.append(&2, SurfaceTypes.Node, headers, bodies)),
              Nat.add(Rule.count_by(predicate, headers), Rule.count_by(predicate, bodies)), join_evidence),
            tail_evidence)
          Equal.trans(Nat,
            Rule.count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
            Nat.add(Rule.count_by(predicate, headers), Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, bodies))),
            Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, rest)),
            Equal.trans(Nat,
              Rule.count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
              Nat.add(Rule.count_by(predicate, headers), Rule.count_by(predicate, value <> bodies)),
              Nat.add(Rule.count_by(predicate, headers), Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, bodies))),
              count_append(predicate, headers, value <> bodies),
              Equal.cong(Nat, Nat, (count => Nat.add(Rule.count_by(predicate, headers), count)),
                Rule.count_by(predicate, value <> bodies), Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, bodies)), {==})),
            Equal.trans(Nat,
              Nat.add(Rule.count_by(predicate, headers), Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, bodies))),
              Rule.occurrence_step(Rule.count_matches(predicate, value), Nat.add(Rule.count_by(predicate, headers), Rule.count_by(predicate, bodies))),
              Rule.occurrence_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, rest)),
              body_count_step(Rule.count_matches(predicate, value), Rule.count_by(predicate, headers), Rule.count_by(predicate, bodies)),
              Equal.cong(Nat, Nat, (count => Rule.occurrence_step(Rule.count_matches(predicate, value), count)),
                Nat.add(Rule.count_by(predicate, headers), Rule.count_by(predicate, bodies)), Rule.count_by(predicate, rest), tail_relation)))

def partition_count_preserved(+predicate: Rule.CountPredicate, +values: +List<SurfaceTypes.Node>,
  +context: Controls.Context) ->
  {Rule.count_by(predicate, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
    Rule.count_by(predicate, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_count_preserved(predicate, rest, context)
      partition_count_step(predicate, value, rest, Order.header_child(value, context), tail_parts,
        context, tail_evidence)

def count_all_is_length(values: +List<SurfaceTypes.Node>) ->
  {Rule.count_by(Rule.CountAll{}, values) == List.length(&2, SurfaceTypes.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        Rule.count_by(Rule.CountAll{}, rest), List.length(&2, SurfaceTypes.Node, rest), count_all_is_length(rest))

def state_model_observes_ordered_surface_evidence(+model_state: Web.State) ->
  {Web.observed_surface(model_state) ==
        Order.ordered_surface(Web.surface(Web.application(model_state))) : SurfaceTypes.Surface}:
  Web.State{+application, +generation, +realization, +environment, +font} = model_state
  {==}

def Rule.presentation_order_evidence():
  Rule.PresentationOrderRequirements{
    role => values => context => non_dialog_order(role, values, context),
    values => context => partition_matches_specification(values, context),
    +values => +context =>
      Equal.trans(Nat,
        List.length(&2, SurfaceTypes.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        List.length(&2, SurfaceTypes.Node, values),
        Equal.sym(Nat,
          Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          List.length(&2, SurfaceTypes.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          count_all_is_length(Order.ordered_dialog_children(Order.partition_dialog_children(values, context)))),
        Equal.trans(Nat,
          Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          Rule.count_by(Rule.CountAll{}, values), List.length(&2, SurfaceTypes.Node, values),
          partition_count_preserved(Rule.CountAll{}, values, context), count_all_is_length(values))),
    +target => +values => +context => partition_count_preserved(Rule.CountKey{Rule.count_key(target)}, values, context),
    values => role => context => ordered_children_matches_specification(values, role, context),
    values => context => dialog_order_idempotent(values, context),
    value => children => node_with_children_preserves_payload(value, children),
    surface => ordered_surface_preserves_content_scope(surface),
    state_model_observes_ordered_surface_evidence}

def Rule.base_classifier(key, role): {==}

def Rule.navigation_role(key): {==}

def Rule.navigation_precedence(key, role): {==}

def Rule.remaining_region(key, role): {==}

def Rule.main_precedence(key): {==}

def Rule.footer_region(): {==}

def Rule.other_region(): {==}

def Rule.base_partition_navigation(node, navigation, footer, main, other): {==}

def Rule.base_partition_footer(node, navigation, footer, main, other): {==}

def Rule.base_partition_main(node, navigation, footer, main, other): {==}

def Rule.base_partition_other(node, navigation, footer, main, other): {==}

def Rule.base_partition_empty(): {==}

def Rule.base_partition_step(key, semantic, label, role, meaning, children, rest): {==}

def Rule.base_region_order(navigation, footer, main, other): {==}

def Rule.ordered_base_partition(values): {==}

def Rule.ordered_surface_base(content, base, overlays, scope): {==}

def Rule.remaining_role_classification(key, role, belongs):
  match role:
    case SurfaceTypes.Navigation{}: {==}
    case SurfaceTypes.NavigationHeader{}: {==}
    case SurfaceTypes.Main{}: Logic.impossible({Order.base_region_role(key, SurfaceTypes.Main{}) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}, belongs)
    case SurfaceTypes.Heading{}: {==}
    case SurfaceTypes.PrimaryButton{}: {==}
    case SurfaceTypes.DestructiveButton{}: {==}
    case SurfaceTypes.SelectedButton{}: {==}
    case SurfaceTypes.ComposerActions{}: {==}
    case SurfaceTypes.DialogActions{}: {==}
    case SurfaceTypes.Timeline{}: {==}
    case SurfaceTypes.Activity{}: {==}
    case SurfaceTypes.UserMessage{}: {==}
    case SurfaceTypes.AssistantMessage{}: {==}
    case SurfaceTypes.Composer{}: {==}
    case SurfaceTypes.Approval{}: {==}
    case SurfaceTypes.Toolbar{}: {==}
    case SurfaceTypes.CodeBlock{}: {==}
    case SurfaceTypes.ApprovalQueue{}: {==}
    case SurfaceTypes.Section{}: {==}
    case SurfaceTypes.Dialog{}: {==}
    case SurfaceTypes.Menu{}: {==}
    case SurfaceTypes.Details{}: {==}
    case SurfaceTypes.Card{}: {==}
    case SurfaceTypes.Button{}: {==}
    case SurfaceTypes.Field{}: {==}
    case SurfaceTypes.Content{}: {==}
    case SurfaceTypes.Alert{}: {==}

def projection_construction(input: InteractionTypes.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Controls.presented_action(input, availability, name, projection, placement, help, feedback) == Rule.projected_action(input, availability, name, projection, placement, help, feedback) : Controls.Representation}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def name_geometry(+visual: Design.Style) -> Rule.name_geometry_law(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  {==}

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) -> Rule.chooser_draft_observation_law(id, fallback):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = fallback
  {==}

def project_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +children: +List<SurfaceTypes.Node>, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> Rule.project_reference_law(key, semantic, label, role, children, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +children: +List<SurfaceTypes.Node>, +context: Controls.Context, +task: Nat, +status: View.TaskStatus, +selected: Bool) -> Rule.task_reference_law(key, semantic, label, role, children, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +children: +List<SurfaceTypes.Node>, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> Rule.chooser_reference_law(key, semantic, label, role, children, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def project_family_projection(+area: Controls.Area, +owner: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +project: Nat, +selected: Bool, +expanded: Bool, +children: +List<SurfaceTypes.Node>, +input: InteractionTypes.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.SourceFamily{SurfaceTypes.Node{owner, semantic, label, role, SurfaceTypes.ProjectGroup{project, selected, expanded}, children}}, input, name, face, behavior, geometry) ==
    Controls.project_presentation(Controls.project_control_matches(input, project), Controls.project_control_input(input), expanded, name, face, behavior, geometry) : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def unscoped_projection(+area: Controls.Area, +input: InteractionTypes.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.Unscoped{}, input, name, face, behavior, geometry) == Controls.ActionPresentation{face, behavior, geometry} : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def status_indicator_extent(+key: UIIdentity.Key, status: View.TaskStatus, visual: Design.Style) ->
  {Rule.status_extent(Authored.task_status_indicator(key, status, visual)) == (Model.ExactSize{16n}, (Model.ExactSize{16n}, Enclosure.Extent{16n, 16n})) : Model.AxisSize & (Model.AxisSize & Enclosure.Extent)}:
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def Rule.project_presentation_evidence():
  Rule.ProjectPresentationRequirements{
    +project => {==},
    +project => {==},
    +project => {==},
    +project => +trigger => {==},
    +name => +expanded => +fallback => {==},
    project_family_projection,
    unscoped_projection,
    +area => +family => +input => +availability => +name => +face => +behavior => +geometry => +placement => +help => +feedback => projection_construction(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback),
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    name_geometry,
    {==},
    +trigger => +name => +face => +behavior => +geometry => {==},
    +name => +expanded => +fallback => {==},
    +name => +expanded => +fallback => {==},
    chooser_draft_observation,
    +typography => +key => +context => +representation => +fallback => +project => +selected => +expanded => {==},
    +typography => +key => +context => +representation => +fallback => +task => +status => +selected => {==},
    project_reference,
    task_reference,
    chooser_reference,
    +typography => +in_main => +start => +key => +semantic => +label => +role => +meaning => +children => +context => {==},
    +typography => +key => +owner => +owner_semantic => +owner_label => +owner_role => +owner_children => +project => +selected => +expanded => +area => +selection => +code => +appearance => +access => +open => +layers => +execution => +representation => +fallback => {==},
    {==},
    {==},
    working => {==},
    working => {==},
    working => {==},
    +key => +status => +visual => {==},
    status_indicator_extent,
    +key => role => meaning => nodes => +rest => +status => +visual => {==}}

def instructions_same(empty: Bool, +value: String) -> {Authored.project_instructions(empty, value) == Rule.instructions_text_when(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def frozen_project(+owner: UIIdentity.Key, +label: String, +directory: String, +revision: String, +instructions: String, +visual: Design.Style) -> Rule.project_law(owner, label, directory, revision, instructions, visual):
  Equal.cong(String, +List<Source.Node>,
    supplied_text => [Authored.group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), Authored.fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), Authored.fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), Authored.fact(UIIdentity.part(owner, "instructions"), "Instructions", supplied_text, visual)])],
    Authored.project_instructions(String.eq(instructions, ""), instructions),
    Rule.instructions_text_when(String.eq(instructions, ""), instructions),
    instructions_same(String.eq(instructions, ""), instructions))

def Rule.task_details_evidence():
  Rule.TaskDetailsRequirements{
    +owner => +label => +visual => {==},
    frozen_project,
    +owner => +visual => {==},
    +owner => +name => +description => +schema => +source => +rest => +visual => {==},
    {==},
    +ancestor => +rest => {==},
    +owner => +task => +roots => +primary => +mode => +network => +approval => +project => +guidance => +access => +id => +provider => +name => +policy => +options => +reasoning => +model_guidance => +tools => +lineage => +queued => +status => +phase => +visual => {==}}
