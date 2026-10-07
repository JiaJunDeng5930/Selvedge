import ../../bendlib/logic-proof.bend as Logic
import ../../interaction/IDENTITY.bend as UIIdentity
import Base
import ../../bendlib/algebra-proof.bend as Alg
import ./presentation-order-laws.bend as Rule
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../MODEL.bend as Model
import ../controls/PROGRAM.bend as Controls
import ./presentation-order.bend as Order
import ../../bendlib/stdlib.bend as Std

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

def header_classifier_matches_specification(value: InterfaceView.Node, +context: Controls.Context) ->
  {Order.header_child(value, context) == Rule.specified_header_child(value, context) : Bool}:
  match value:
    case InterfaceView.Node{+key, semantic, +label, +role, +meaning, children}:
      panel_header_matches_specification(Controls.represent(key, meaning, label, role,
        Controls.enter(value, context)))

def partition_header_step_matches(value: InterfaceView.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_header(Order.partition_child(value, include, parts)) ==
    Rule.header_step(value, include, Order.partition_header(parts)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_body_step_matches(value: InterfaceView.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_body(Order.partition_child(value, include, parts)) ==
    Rule.body_step(value, include, Order.partition_body(parts)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_header_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_header(Order.partition_dialog_children(values, context)) == Rule.specified_header(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_header_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = Rule.specified_header_child(value, context)
      Equal.trans(+List<InterfaceView.Node>,
        Order.partition_header(Order.partition_child(value, actual_include, tail_parts)),
        Rule.header_step(value, actual_include, Order.partition_header(tail_parts)),
        Rule.header_step(value, specified_include, Rule.specified_header(rest, context)),
        partition_header_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<InterfaceView.Node>,
          Rule.header_step(value, actual_include, Order.partition_header(tail_parts)),
          Rule.header_step(value, specified_include, Order.partition_header(tail_parts)),
          Rule.header_step(value, specified_include, Rule.specified_header(rest, context)),
          Equal.cong(Bool, +List<InterfaceView.Node>, (include => Rule.header_step(value, include, Order.partition_header(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => Rule.header_step(value, specified_include, tail)),
            Order.partition_header(tail_parts), Rule.specified_header(rest, context), tail_evidence)))

def partition_body_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_body(Order.partition_dialog_children(values, context)) == Rule.specified_body(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_body_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = Rule.specified_header_child(value, context)
      Equal.trans(+List<InterfaceView.Node>,
        Order.partition_body(Order.partition_child(value, actual_include, tail_parts)),
        Rule.body_step(value, actual_include, Order.partition_body(tail_parts)),
        Rule.body_step(value, specified_include, Rule.specified_body(rest, context)),
        partition_body_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<InterfaceView.Node>,
          Rule.body_step(value, actual_include, Order.partition_body(tail_parts)),
          Rule.body_step(value, specified_include, Order.partition_body(tail_parts)),
          Rule.body_step(value, specified_include, Rule.specified_body(rest, context)),
          Equal.cong(Bool, +List<InterfaceView.Node>, (include => Rule.body_step(value, include, Order.partition_body(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => Rule.body_step(value, specified_include, tail)),
            Order.partition_body(tail_parts), Rule.specified_body(rest, context), tail_evidence)))

def parts_match_filters(parts: Order.DialogParts, expected_header: +List<InterfaceView.Node>,
  expected_body: +List<InterfaceView.Node>,
  header_evidence: {Order.partition_header(parts) == expected_header : +List<InterfaceView.Node>},
  body_evidence: {Order.partition_body(parts) == expected_body : +List<InterfaceView.Node>}) ->
  {parts == Order.DialogParts{expected_header, expected_body} : Order.DialogParts}:
  match parts:
    case Order.DialogParts{+header, +body}:
      Equal.trans(Order.DialogParts, Order.DialogParts{header, body},
        Order.DialogParts{expected_header, body}, Order.DialogParts{expected_header, expected_body},
        Equal.cong(+List<InterfaceView.Node>, Order.DialogParts,
          (value => Order.DialogParts{value, body}), header, expected_header, header_evidence),
        Equal.cong(+List<InterfaceView.Node>, Order.DialogParts,
          (value => Order.DialogParts{expected_header, value}), body, expected_body, body_evidence))

def partition_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_dialog_children(values, context) == Rule.specified_parts(values, context) : Order.DialogParts}:
  parts_match_filters(Order.partition_dialog_children(values, context),
    Rule.specified_header(values, context), Rule.specified_body(values, context),
    partition_header_matches_specification(values, context),
    partition_body_matches_specification(values, context))

def ordered_children_matches_specification(+values: +List<InterfaceView.Node>, role: InterfaceView.Role, +context: Controls.Context) ->
  {Order.ordered_children(role, values, context) == Rule.specified_children(role, values, context) : +List<InterfaceView.Node>}:
  match role:
    case InterfaceView.Dialog{}:
      +parts_evidence = partition_matches_specification(values, context)
      Equal.cong(Order.DialogParts, +List<InterfaceView.Node>, (parts => Order.ordered_dialog_children(parts)),
        Order.partition_dialog_children(values, context), Rule.specified_parts(values, context), parts_evidence)
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: {==}
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}

def non_dialog_order(role: InterfaceView.Role, +values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.non_dialog_order_observation(role, values, context) == values : +List<InterfaceView.Node>}:
  match role:
    case InterfaceView.Dialog{}: {==}
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: {==}
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}

def specified_header_append_step(value: InterfaceView.Node, rest: +List<InterfaceView.Node>, right: +List<InterfaceView.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {Rule.specified_header(List.append(&2, InterfaceView.Node, rest, right), context) ==
    List.append(&2, InterfaceView.Node, Rule.specified_header(rest, context), Rule.specified_header(right, context)) : +List<InterfaceView.Node>}) ->
  {Rule.header_step(value, include, Rule.specified_header(List.append(&2, InterfaceView.Node, rest, right), context)) ==
    List.append(&2, InterfaceView.Node, Rule.header_step(value, include, Rule.specified_header(rest, context)), Rule.specified_header(right, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => value <> tail),
        Rule.specified_header(List.append(&2, InterfaceView.Node, rest, right), context),
        List.append(&2, InterfaceView.Node, Rule.specified_header(rest, context), Rule.specified_header(right, context)),
        tail_evidence)
    case False{}: tail_evidence

def specified_body_append_step(value: InterfaceView.Node, rest: +List<InterfaceView.Node>, right: +List<InterfaceView.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {Rule.specified_body(List.append(&2, InterfaceView.Node, rest, right), context) ==
    List.append(&2, InterfaceView.Node, Rule.specified_body(rest, context), Rule.specified_body(right, context)) : +List<InterfaceView.Node>}) ->
  {Rule.body_step(value, include, Rule.specified_body(List.append(&2, InterfaceView.Node, rest, right), context)) ==
    List.append(&2, InterfaceView.Node, Rule.body_step(value, include, Rule.specified_body(rest, context)), Rule.specified_body(right, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => value <> tail),
        Rule.specified_body(List.append(&2, InterfaceView.Node, rest, right), context),
        List.append(&2, InterfaceView.Node, Rule.specified_body(rest, context), Rule.specified_body(right, context)),
        tail_evidence)

def specified_header_append(+left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_header(List.append(&2, InterfaceView.Node, left, right), context) ==
    List.append(&2, InterfaceView.Node, Rule.specified_header(left, context), Rule.specified_header(right, context)) : +List<InterfaceView.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_append(rest, right, context)
      specified_header_append_step(value, rest, right, Rule.specified_header_child(value, context), context,
        tail_evidence)

def specified_body_append(+left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_body(List.append(&2, InterfaceView.Node, left, right), context) ==
    List.append(&2, InterfaceView.Node, Rule.specified_body(left, context), Rule.specified_body(right, context)) : +List<InterfaceView.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_append(rest, right, context)
      specified_body_append_step(value, rest, right, Rule.specified_header_child(value, context), context,
        tail_evidence)

def specified_header_idempotent_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_header(Rule.specified_header(rest, context), context) == Rule.specified_header(rest, context) : +List<InterfaceView.Node>}) ->
  {Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context) ==
    Rule.header_step(value, include, Rule.specified_header(rest, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => Rule.header_step(value, flag, Rule.specified_header(Rule.specified_header(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
        (tail => Rule.header_step(value, include, tail)),
        Rule.specified_header(Rule.specified_header(rest, context), context), Rule.specified_header(rest, context), tail_evidence)
      Equal.trans(+List<InterfaceView.Node>,
        Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
        Rule.header_step(value, include, Rule.specified_header(Rule.specified_header(rest, context), context)),
        Rule.header_step(value, include, Rule.specified_header(rest, context)),
        Equal.trans(+List<InterfaceView.Node>,
          Rule.specified_header(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
          Rule.header_step(value, Rule.specified_header_child(value, context), Rule.specified_header(Rule.specified_header(rest, context), context)),
          Rule.header_step(value, include, Rule.specified_header(Rule.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_step)
    case False{}: tail_evidence

def specified_body_idempotent_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_body(Rule.specified_body(rest, context), context) == Rule.specified_body(rest, context) : +List<InterfaceView.Node>}) ->
  {Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context) ==
    Rule.body_step(value, include, Rule.specified_body(rest, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => Rule.body_step(value, flag, Rule.specified_body(Rule.specified_body(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
        (tail => Rule.body_step(value, include, tail)),
        Rule.specified_body(Rule.specified_body(rest, context), context), Rule.specified_body(rest, context), tail_evidence)
      Equal.trans(+List<InterfaceView.Node>,
        Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
        Rule.body_step(value, include, Rule.specified_body(Rule.specified_body(rest, context), context)),
        Rule.body_step(value, include, Rule.specified_body(rest, context)),
        Equal.trans(+List<InterfaceView.Node>,
          Rule.specified_body(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
          Rule.body_step(value, Rule.specified_header_child(value, context), Rule.specified_body(Rule.specified_body(rest, context), context)),
          Rule.body_step(value, include, Rule.specified_body(Rule.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_step)

def specified_header_after_body_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_header(Rule.specified_body(rest, context), context) == Nil{} : +List<InterfaceView.Node>}) ->
  {Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context) == Nil{} : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => Rule.header_step(value, flag, Rule.specified_header(Rule.specified_body(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<InterfaceView.Node>,
        Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
        Rule.header_step(value, include, Rule.specified_header(Rule.specified_body(rest, context), context)),
        Nil{},
        Equal.trans(+List<InterfaceView.Node>,
          Rule.specified_header(Rule.body_step(value, include, Rule.specified_body(rest, context)), context),
          Rule.header_step(value, Rule.specified_header_child(value, context), Rule.specified_header(Rule.specified_body(rest, context), context)),
          Rule.header_step(value, include, Rule.specified_header(Rule.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)

def specified_body_after_header_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == Rule.specified_header_child(value, context) : Bool},
  tail_evidence: {Rule.specified_body(Rule.specified_header(rest, context), context) == Nil{} : +List<InterfaceView.Node>}) ->
  {Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context) == Nil{} : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, Rule.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => Rule.body_step(value, flag, Rule.specified_body(Rule.specified_header(rest, context), context))),
        Rule.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<InterfaceView.Node>,
        Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
        Rule.body_step(value, include, Rule.specified_body(Rule.specified_header(rest, context), context)),
        Nil{},
        Equal.trans(+List<InterfaceView.Node>,
          Rule.specified_body(Rule.header_step(value, include, Rule.specified_header(rest, context)), context),
          Rule.body_step(value, Rule.specified_header_child(value, context), Rule.specified_body(Rule.specified_header(rest, context), context)),
          Rule.body_step(value, include, Rule.specified_body(Rule.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)
    case False{}: tail_evidence

def specified_header_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_header(values, context), context) == Rule.specified_header(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_idempotent(rest, context)
      specified_header_idempotent_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_body(values, context), context) == Rule.specified_body(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_idempotent(rest, context)
      specified_body_idempotent_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_after_body(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_body(values, context), context) == Nil{} : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_after_body(rest, context)
      specified_header_after_body_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_after_header(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_header(values, context), context) == Nil{} : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_after_header(rest, context)
      specified_body_after_header_step(value, rest, Rule.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_of_order(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_header(Rule.specified_order(values, context), context) == Rule.specified_header(values, context) : +List<InterfaceView.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  +split = specified_header_append(headers, bodies, context)
  +headers_repeat = specified_header_idempotent(values, context)
  +body_empty = specified_header_after_body(values, context)
  +filtered_headers = Rule.specified_header(headers, context)
  +filtered_bodies = Rule.specified_header(bodies, context)
  Equal.trans(+List<InterfaceView.Node>,
    Rule.specified_header(Rule.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
    headers, split,
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
      List.append(&2, InterfaceView.Node, headers, Nil{}),
      headers,
      Equal.trans(+List<InterfaceView.Node>,
        List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
        List.append(&2, InterfaceView.Node, headers, filtered_bodies),
        List.append(&2, InterfaceView.Node, headers, Nil{}),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head, filtered_bodies)),
          filtered_headers, headers, headers_repeat),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, headers, tail)),
          filtered_bodies, Nil{}, body_empty)),
      Std.app_nil_r(InterfaceView.Node, headers)))

def specified_body_of_order(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_body(Rule.specified_order(values, context), context) == Rule.specified_body(values, context) : +List<InterfaceView.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  +split = specified_body_append(headers, bodies, context)
  +header_empty = specified_body_after_header(values, context)
  +bodies_repeat = specified_body_idempotent(values, context)
  Equal.trans(+List<InterfaceView.Node>,
    Rule.specified_body(Rule.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
    bodies, split,
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
      List.append(&2, InterfaceView.Node, Nil{}, bodies),
      bodies,
      Equal.trans(+List<InterfaceView.Node>,
        List.append(&2, InterfaceView.Node, Rule.specified_body(headers, context), Rule.specified_body(bodies, context)),
        List.append(&2, InterfaceView.Node, Nil{}, Rule.specified_body(bodies, context)),
        List.append(&2, InterfaceView.Node, Nil{}, bodies),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head, Rule.specified_body(bodies, context))),
          Rule.specified_body(headers, context), Nil{}, header_empty),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, Nil{}, tail)),
          Rule.specified_body(bodies, context), bodies, bodies_repeat)),
      {==}))

def specified_order_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Rule.specified_order(Rule.specified_order(values, context), context) == Rule.specified_order(values, context) : +List<InterfaceView.Node>}:
  +headers = Rule.specified_header(values, context)
  +bodies = Rule.specified_body(values, context)
  Equal.trans(+List<InterfaceView.Node>,
    Rule.specified_order(Rule.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, Rule.specified_header(Rule.specified_order(values, context), context),
      Rule.specified_body(Rule.specified_order(values, context), context)),
    List.append(&2, InterfaceView.Node, headers, bodies),
    {==},
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, Rule.specified_header(Rule.specified_order(values, context), context),
        Rule.specified_body(Rule.specified_order(values, context), context)),
      List.append(&2, InterfaceView.Node, headers, Rule.specified_body(Rule.specified_order(values, context), context)),
      List.append(&2, InterfaceView.Node, headers, bodies),
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head,
        Rule.specified_body(Rule.specified_order(values, context), context))),
        Rule.specified_header(Rule.specified_order(values, context), context), headers,
        specified_header_of_order(values, context)),
    Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, headers, tail)),
        Rule.specified_body(Rule.specified_order(values, context), context), bodies,
        specified_body_of_order(values, context))))

def dialog_order_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.ordered_children(InterfaceView.Dialog{}, Order.ordered_children(InterfaceView.Dialog{}, values, context), context) ==
    Order.ordered_children(InterfaceView.Dialog{}, values, context) : +List<InterfaceView.Node>}:
  +first_order = Order.ordered_children(InterfaceView.Dialog{}, values, context)
  +first_evidence = ordered_children_matches_specification(values, InterfaceView.Dialog{}, context)
  +second_evidence = ordered_children_matches_specification(first_order, InterfaceView.Dialog{}, context)
  +lifted_first = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
    (children => Rule.specified_order(children, context)), first_order, Rule.specified_order(values, context), first_evidence)
  Equal.trans(+List<InterfaceView.Node>,
    Order.ordered_children(InterfaceView.Dialog{}, first_order, context),
    Rule.specified_order(first_order, context),
    Order.ordered_children(InterfaceView.Dialog{}, values, context),
    second_evidence,
    Equal.trans(+List<InterfaceView.Node>,
      Rule.specified_order(first_order, context), Rule.specified_order(Rule.specified_order(values, context), context),
      Order.ordered_children(InterfaceView.Dialog{}, values, context),
      lifted_first,
      Equal.trans(+List<InterfaceView.Node>,
        Rule.specified_order(Rule.specified_order(values, context), context), Rule.specified_order(values, context),
        Order.ordered_children(InterfaceView.Dialog{}, values, context),
        specified_order_idempotent(values, context),
        Equal.sym(+List<InterfaceView.Node>, Order.ordered_children(InterfaceView.Dialog{}, values, context),
          Rule.specified_order(values, context), first_evidence))))

def node_with_children_preserves_payload(+value: InterfaceView.Node, +children: +List<InterfaceView.Node>) ->
  {Rule.node_payload(Order.node_with_children(value, children)) == Rule.node_payload(value) : Rule.NodePayload}:
  match value:
    case InterfaceView.Node{key, semantic, label, role, meaning, original_children}: {==}

def ordered_surface_preserves_content_scope(surface: InterfaceView.Surface) ->
  {Rule.surface_payload(Order.ordered_surface(surface)) == Rule.surface_payload(surface) : Rule.SurfacePayload}:
  match surface:
    case InterfaceView.Surface{content, base, overlays, active_scope}: {==}

def count_append_step(+predicate: Rule.CountPredicate, +value: InterfaceView.Node, +rest: +List<InterfaceView.Node>,
  +right: +List<InterfaceView.Node>, included: Bool,
  tail_evidence: {Rule.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right)) ==
    Nat.add(Rule.count_by(predicate, rest), Rule.count_by(predicate, right)) : Nat}) ->
  {Rule.occurrence_step(included, Rule.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right))) ==
    Nat.add(Rule.occurrence_step(included, Rule.count_by(predicate, rest)), Rule.count_by(predicate, right)) : Nat}:
  match included:
    case True{}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        Rule.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right)),
        Nat.add(Rule.count_by(predicate, rest), Rule.count_by(predicate, right)), tail_evidence)
    case False{}: tail_evidence

def count_append(+predicate: Rule.CountPredicate, +left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>) ->
  {Rule.count_by(predicate, List.append(&2, InterfaceView.Node, left, right)) ==
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

def partition_count_step(+predicate: Rule.CountPredicate, +value: InterfaceView.Node, +rest: +List<InterfaceView.Node>,
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
            Rule.count_by(predicate, List.append(&2, InterfaceView.Node, headers, bodies)),
            Rule.count_by(predicate, rest),
            Equal.sym(Nat, Rule.count_by(predicate, List.append(&2, InterfaceView.Node, headers, bodies)),
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

def partition_count_preserved(+predicate: Rule.CountPredicate, +values: +List<InterfaceView.Node>,
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

def count_all_is_length(values: +List<InterfaceView.Node>) ->
  {Rule.count_by(Rule.CountAll{}, values) == List.length(&2, InterfaceView.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        Rule.count_by(Rule.CountAll{}, rest), List.length(&2, InterfaceView.Node, rest), count_all_is_length(rest))

def state_model_observes_ordered_surface_evidence(+model_state: Model.State) ->
  {Model.observed_surface(model_state) ==
        Order.ordered_surface(Model.surface(Model.application(model_state))) : InterfaceView.Surface}:
  Model.State{+application, +generation, +realization, +environment, +font} = model_state
  {==}

def Rule.evidence():
  Rule.Requirements{
    role => values => context => non_dialog_order(role, values, context),
    values => context => partition_matches_specification(values, context),
    +values => +context =>
      Equal.trans(Nat,
        List.length(&2, InterfaceView.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        List.length(&2, InterfaceView.Node, values),
        Equal.sym(Nat,
          Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          List.length(&2, InterfaceView.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          count_all_is_length(Order.ordered_dialog_children(Order.partition_dialog_children(values, context)))),
        Equal.trans(Nat,
          Rule.count_by(Rule.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          Rule.count_by(Rule.CountAll{}, values), List.length(&2, InterfaceView.Node, values),
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
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: Logic.impossible({Order.base_region_role(key, InterfaceView.Main{}) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}, belongs)
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Dialog{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}
