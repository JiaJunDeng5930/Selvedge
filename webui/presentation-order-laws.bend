import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./controls.bend as Controls
import ./design.bend as Design
import ./layout.bend as Layout
import ./visibility.bend as Visibility
import ./presentation-order.bend as Order
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./presentation-laws.bend as PresentationLaws
import ./font-observation.bend as F
import ../bendlib/stdlib.bend as Std

type NodePayload is Data:
  NodePayload{key: String, semantic: String, label: String, role: UI.Role, meaning: UI.Meaning}

type SurfacePayload is Data:
  SurfacePayload{content: Core.Scene, scope: Maybe<&2, String>}

def node_payload(value: UI.Node) -> NodePayload:
  UI.Node{key, semantic, label, role, meaning, children} = value
  NodePayload{key, semantic, label, role, meaning}

def surface_payload(surface: UI.Surface) -> SurfacePayload:
  UI.Surface{content, base, overlays, active_scope} = surface
  SurfacePayload{content, active_scope}

def specified_header_representation(representation: Controls.Representation) -> Bool:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: True{}
    case _: False{}

def specified_header_child(+value: UI.Node, +context: Controls.Context) -> Bool:
  UI.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  specified_header_representation(Controls.represent(key, meaning, label, role, local))

def header_step(value: UI.Node, include: Bool, +tail: +List<UI.Node>) -> +List<UI.Node>:
  match include:
    case True{}: value <> tail
    case False{}: tail

def body_step(value: UI.Node, include: Bool, +tail: +List<UI.Node>) -> +List<UI.Node>:
  match include:
    case True{}: tail
    case False{}: value <> tail

def specified_header(values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      header_step(value, specified_header_child(value, context), specified_header(rest, context))

def specified_body(values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      body_step(value, specified_header_child(value, context), specified_body(rest, context))

def reference_header(parts: Order.DialogParts) -> +List<UI.Node>:
  Order.DialogParts{+header, +body} = parts
  header

def reference_body(parts: Order.DialogParts) -> +List<UI.Node>:
  Order.DialogParts{+header, +body} = parts
  body

def specified_parts(+values: +List<UI.Node>, +context: Controls.Context) -> Order.DialogParts:
  Order.DialogParts{specified_header(values, context), specified_body(values, context)}

def reference_ordered_children(parts: Order.DialogParts) -> +List<UI.Node>:
  Order.DialogParts{+header, +body} = parts
  List.append(&2, UI.Node, header, body)

def specified_order(+values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  List.append(&2, UI.Node, specified_header(values, context), specified_body(values, context))

def specified_children(role: UI.Role, values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match role:
    case UI.Dialog{}:
      specified_order(values, context)
    case _: values

def panel_header_matches_specification(representation: Controls.Representation) ->
  {Controls.panel_header(representation) == specified_header_representation(representation) : Bool}:
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

def header_classifier_matches_specification(value: UI.Node, +context: Controls.Context) ->
  {Order.header_child(value, context) == specified_header_child(value, context) : Bool}:
  match value:
    case UI.Node{+key, semantic, +label, +role, +meaning, children}:
      panel_header_matches_specification(Controls.represent(key, meaning, label, role,
        Controls.enter(value, context)))

def partition_header_step_matches(value: UI.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_header(Order.partition_child(value, include, parts)) ==
    header_step(value, include, Order.partition_header(parts)) : +List<UI.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_body_step_matches(value: UI.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_body(Order.partition_child(value, include, parts)) ==
    body_step(value, include, Order.partition_body(parts)) : +List<UI.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_header_matches_specification(+values: +List<UI.Node>, +context: Controls.Context) ->
  {Order.partition_header(Order.partition_dialog_children(values, context)) == specified_header(values, context) : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_header_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = specified_header_child(value, context)
      Equal.trans(+List<UI.Node>,
        Order.partition_header(Order.partition_child(value, actual_include, tail_parts)),
        header_step(value, actual_include, Order.partition_header(tail_parts)),
        header_step(value, specified_include, specified_header(rest, context)),
        partition_header_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<UI.Node>,
          header_step(value, actual_include, Order.partition_header(tail_parts)),
          header_step(value, specified_include, Order.partition_header(tail_parts)),
          header_step(value, specified_include, specified_header(rest, context)),
          Equal.cong(Bool, +List<UI.Node>, (include => header_step(value, include, Order.partition_header(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => header_step(value, specified_include, tail)),
            Order.partition_header(tail_parts), specified_header(rest, context), tail_evidence)))

def partition_body_matches_specification(+values: +List<UI.Node>, +context: Controls.Context) ->
  {Order.partition_body(Order.partition_dialog_children(values, context)) == specified_body(values, context) : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_body_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = specified_header_child(value, context)
      Equal.trans(+List<UI.Node>,
        Order.partition_body(Order.partition_child(value, actual_include, tail_parts)),
        body_step(value, actual_include, Order.partition_body(tail_parts)),
        body_step(value, specified_include, specified_body(rest, context)),
        partition_body_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<UI.Node>,
          body_step(value, actual_include, Order.partition_body(tail_parts)),
          body_step(value, specified_include, Order.partition_body(tail_parts)),
          body_step(value, specified_include, specified_body(rest, context)),
          Equal.cong(Bool, +List<UI.Node>, (include => body_step(value, include, Order.partition_body(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => body_step(value, specified_include, tail)),
            Order.partition_body(tail_parts), specified_body(rest, context), tail_evidence)))

def parts_match_filters(parts: Order.DialogParts, expected_header: +List<UI.Node>,
  expected_body: +List<UI.Node>,
  header_evidence: {Order.partition_header(parts) == expected_header : +List<UI.Node>},
  body_evidence: {Order.partition_body(parts) == expected_body : +List<UI.Node>}) ->
  {parts == Order.DialogParts{expected_header, expected_body} : Order.DialogParts}:
  match parts:
    case Order.DialogParts{+header, +body}:
      Equal.trans(Order.DialogParts, Order.DialogParts{header, body},
        Order.DialogParts{expected_header, body}, Order.DialogParts{expected_header, expected_body},
        Equal.cong(+List<UI.Node>, Order.DialogParts,
          (value => Order.DialogParts{value, body}), header, expected_header, header_evidence),
        Equal.cong(+List<UI.Node>, Order.DialogParts,
          (value => Order.DialogParts{expected_header, value}), body, expected_body, body_evidence))

def partition_matches_specification(+values: +List<UI.Node>, +context: Controls.Context) ->
  {Order.partition_dialog_children(values, context) == specified_parts(values, context) : Order.DialogParts}:
  parts_match_filters(Order.partition_dialog_children(values, context),
    specified_header(values, context), specified_body(values, context),
    partition_header_matches_specification(values, context),
    partition_body_matches_specification(values, context))

def ordered_children_matches_specification(+values: +List<UI.Node>, role: UI.Role, +context: Controls.Context) ->
  {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<UI.Node>}:
  match role:
    case UI.Dialog{}:
      +parts_evidence = partition_matches_specification(values, context)
      Equal.cong(Order.DialogParts, +List<UI.Node>, (parts => Order.ordered_dialog_children(parts)),
        Order.partition_dialog_children(values, context), specified_parts(values, context), parts_evidence)
    case UI.Navigation{}: {==}
    case UI.NavigationHeader{}: {==}
    case UI.Main{}: {==}
    case UI.Heading{}: {==}
    case UI.PrimaryButton{}: {==}
    case UI.DestructiveButton{}: {==}
    case UI.SelectedButton{}: {==}
    case UI.ComposerActions{}: {==}
    case UI.Timeline{}: {==}
    case UI.Activity{}: {==}
    case UI.UserMessage{}: {==}
    case UI.AssistantMessage{}: {==}
    case UI.Composer{}: {==}
    case UI.Approval{}: {==}
    case UI.Toolbar{}: {==}
    case UI.CodeBlock{}: {==}
    case UI.ApprovalQueue{}: {==}
    case UI.Section{}: {==}
    case UI.Menu{}: {==}
    case UI.Details{}: {==}
    case UI.Card{}: {==}
    case UI.Button{}: {==}
    case UI.Field{}: {==}
    case UI.Content{}: {==}
    case UI.Alert{}: {==}



def non_dialog_order_observation(role: UI.Role, +values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match role:
    case UI.Dialog{}: values
    case _: Order.ordered_children(role, values, context)

def non_dialog_order(role: UI.Role, +values: +List<UI.Node>, +context: Controls.Context) ->
  {non_dialog_order_observation(role, values, context) == values : +List<UI.Node>}:
  match role:
    case UI.Dialog{}: {==}
    case UI.Navigation{}: {==}
    case UI.NavigationHeader{}: {==}
    case UI.Main{}: {==}
    case UI.Heading{}: {==}
    case UI.PrimaryButton{}: {==}
    case UI.DestructiveButton{}: {==}
    case UI.SelectedButton{}: {==}
    case UI.ComposerActions{}: {==}
    case UI.Timeline{}: {==}
    case UI.Activity{}: {==}
    case UI.UserMessage{}: {==}
    case UI.AssistantMessage{}: {==}
    case UI.Composer{}: {==}
    case UI.Approval{}: {==}
    case UI.Toolbar{}: {==}
    case UI.CodeBlock{}: {==}
    case UI.ApprovalQueue{}: {==}
    case UI.Section{}: {==}
    case UI.Menu{}: {==}
    case UI.Details{}: {==}
    case UI.Card{}: {==}
    case UI.Button{}: {==}
    case UI.Field{}: {==}
    case UI.Content{}: {==}
    case UI.Alert{}: {==}

def specified_header_append_step(value: UI.Node, rest: +List<UI.Node>, right: +List<UI.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {specified_header(List.append(&2, UI.Node, rest, right), context) ==
    List.append(&2, UI.Node, specified_header(rest, context), specified_header(right, context)) : +List<UI.Node>}) ->
  {header_step(value, include, specified_header(List.append(&2, UI.Node, rest, right), context)) ==
    List.append(&2, UI.Node, header_step(value, include, specified_header(rest, context)), specified_header(right, context)) : +List<UI.Node>}:
  match include:
    case True{}:
      Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => value <> tail),
        specified_header(List.append(&2, UI.Node, rest, right), context),
        List.append(&2, UI.Node, specified_header(rest, context), specified_header(right, context)),
        tail_evidence)
    case False{}: tail_evidence

def specified_body_append_step(value: UI.Node, rest: +List<UI.Node>, right: +List<UI.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {specified_body(List.append(&2, UI.Node, rest, right), context) ==
    List.append(&2, UI.Node, specified_body(rest, context), specified_body(right, context)) : +List<UI.Node>}) ->
  {body_step(value, include, specified_body(List.append(&2, UI.Node, rest, right), context)) ==
    List.append(&2, UI.Node, body_step(value, include, specified_body(rest, context)), specified_body(right, context)) : +List<UI.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => value <> tail),
        specified_body(List.append(&2, UI.Node, rest, right), context),
        List.append(&2, UI.Node, specified_body(rest, context), specified_body(right, context)),
        tail_evidence)

def specified_header_append(+left: +List<UI.Node>, +right: +List<UI.Node>, +context: Controls.Context) ->
  {specified_header(List.append(&2, UI.Node, left, right), context) ==
    List.append(&2, UI.Node, specified_header(left, context), specified_header(right, context)) : +List<UI.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_append(rest, right, context)
      specified_header_append_step(value, rest, right, specified_header_child(value, context), context,
        tail_evidence)

def specified_body_append(+left: +List<UI.Node>, +right: +List<UI.Node>, +context: Controls.Context) ->
  {specified_body(List.append(&2, UI.Node, left, right), context) ==
    List.append(&2, UI.Node, specified_body(left, context), specified_body(right, context)) : +List<UI.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_append(rest, right, context)
      specified_body_append_step(value, rest, right, specified_header_child(value, context), context,
        tail_evidence)

def specified_header_idempotent_step(+value: UI.Node, +rest: +List<UI.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == specified_header_child(value, context) : Bool},
  tail_evidence: {specified_header(specified_header(rest, context), context) == specified_header(rest, context) : +List<UI.Node>}) ->
  {specified_header(header_step(value, include, specified_header(rest, context)), context) ==
    header_step(value, include, specified_header(rest, context)) : +List<UI.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<UI.Node>,
        (flag => header_step(value, flag, specified_header(specified_header(rest, context), context))),
        specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<UI.Node>, +List<UI.Node>,
        (tail => header_step(value, include, tail)),
        specified_header(specified_header(rest, context), context), specified_header(rest, context), tail_evidence)
      Equal.trans(+List<UI.Node>,
        specified_header(header_step(value, include, specified_header(rest, context)), context),
        header_step(value, include, specified_header(specified_header(rest, context), context)),
        header_step(value, include, specified_header(rest, context)),
        Equal.trans(+List<UI.Node>,
          specified_header(header_step(value, include, specified_header(rest, context)), context),
          header_step(value, specified_header_child(value, context), specified_header(specified_header(rest, context), context)),
          header_step(value, include, specified_header(specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_step)
    case False{}: tail_evidence

def specified_body_idempotent_step(+value: UI.Node, +rest: +List<UI.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == specified_header_child(value, context) : Bool},
  tail_evidence: {specified_body(specified_body(rest, context), context) == specified_body(rest, context) : +List<UI.Node>}) ->
  {specified_body(body_step(value, include, specified_body(rest, context)), context) ==
    body_step(value, include, specified_body(rest, context)) : +List<UI.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<UI.Node>,
        (flag => body_step(value, flag, specified_body(specified_body(rest, context), context))),
        specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<UI.Node>, +List<UI.Node>,
        (tail => body_step(value, include, tail)),
        specified_body(specified_body(rest, context), context), specified_body(rest, context), tail_evidence)
      Equal.trans(+List<UI.Node>,
        specified_body(body_step(value, include, specified_body(rest, context)), context),
        body_step(value, include, specified_body(specified_body(rest, context), context)),
        body_step(value, include, specified_body(rest, context)),
        Equal.trans(+List<UI.Node>,
          specified_body(body_step(value, include, specified_body(rest, context)), context),
          body_step(value, specified_header_child(value, context), specified_body(specified_body(rest, context), context)),
          body_step(value, include, specified_body(specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_step)

def specified_header_after_body_step(+value: UI.Node, +rest: +List<UI.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == specified_header_child(value, context) : Bool},
  tail_evidence: {specified_header(specified_body(rest, context), context) == Nil{} : +List<UI.Node>}) ->
  {specified_header(body_step(value, include, specified_body(rest, context)), context) == Nil{} : +List<UI.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<UI.Node>,
        (flag => header_step(value, flag, specified_header(specified_body(rest, context), context))),
        specified_header_child(value, context), include, same_include)
      Equal.trans(+List<UI.Node>,
        specified_header(body_step(value, include, specified_body(rest, context)), context),
        header_step(value, include, specified_header(specified_body(rest, context), context)),
        Nil{},
        Equal.trans(+List<UI.Node>,
          specified_header(body_step(value, include, specified_body(rest, context)), context),
          header_step(value, specified_header_child(value, context), specified_header(specified_body(rest, context), context)),
          header_step(value, include, specified_header(specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)

def specified_body_after_header_step(+value: UI.Node, +rest: +List<UI.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == specified_header_child(value, context) : Bool},
  tail_evidence: {specified_body(specified_header(rest, context), context) == Nil{} : +List<UI.Node>}) ->
  {specified_body(header_step(value, include, specified_header(rest, context)), context) == Nil{} : +List<UI.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<UI.Node>,
        (flag => body_step(value, flag, specified_body(specified_header(rest, context), context))),
        specified_header_child(value, context), include, same_include)
      Equal.trans(+List<UI.Node>,
        specified_body(header_step(value, include, specified_header(rest, context)), context),
        body_step(value, include, specified_body(specified_header(rest, context), context)),
        Nil{},
        Equal.trans(+List<UI.Node>,
          specified_body(header_step(value, include, specified_header(rest, context)), context),
          body_step(value, specified_header_child(value, context), specified_body(specified_header(rest, context), context)),
          body_step(value, include, specified_body(specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)
    case False{}: tail_evidence

def specified_header_idempotent(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_header(specified_header(values, context), context) == specified_header(values, context) : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_idempotent(rest, context)
      specified_header_idempotent_step(value, rest, specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_idempotent(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_body(specified_body(values, context), context) == specified_body(values, context) : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_idempotent(rest, context)
      specified_body_idempotent_step(value, rest, specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_after_body(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_header(specified_body(values, context), context) == Nil{} : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_after_body(rest, context)
      specified_header_after_body_step(value, rest, specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_after_header(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_body(specified_header(values, context), context) == Nil{} : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_after_header(rest, context)
      specified_body_after_header_step(value, rest, specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_of_order(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_header(specified_order(values, context), context) == specified_header(values, context) : +List<UI.Node>}:
  +headers = specified_header(values, context)
  +bodies = specified_body(values, context)
  +split = specified_header_append(headers, bodies, context)
  +headers_repeat = specified_header_idempotent(values, context)
  +body_empty = specified_header_after_body(values, context)
  +filtered_headers = specified_header(headers, context)
  +filtered_bodies = specified_header(bodies, context)
  Equal.trans(+List<UI.Node>,
    specified_header(specified_order(values, context), context),
    List.append(&2, UI.Node, filtered_headers, filtered_bodies),
    headers, split,
    Equal.trans(+List<UI.Node>,
      List.append(&2, UI.Node, filtered_headers, filtered_bodies),
      List.append(&2, UI.Node, headers, Nil{}),
      headers,
      Equal.trans(+List<UI.Node>,
        List.append(&2, UI.Node, filtered_headers, filtered_bodies),
        List.append(&2, UI.Node, headers, filtered_bodies),
        List.append(&2, UI.Node, headers, Nil{}),
        Equal.cong(+List<UI.Node>, +List<UI.Node>, (head => List.append(&2, UI.Node, head, filtered_bodies)),
          filtered_headers, headers, headers_repeat),
        Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => List.append(&2, UI.Node, headers, tail)),
          filtered_bodies, Nil{}, body_empty)),
      Std.app_nil_r(UI.Node, headers)))

def specified_body_of_order(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_body(specified_order(values, context), context) == specified_body(values, context) : +List<UI.Node>}:
  +headers = specified_header(values, context)
  +bodies = specified_body(values, context)
  +split = specified_body_append(headers, bodies, context)
  +header_empty = specified_body_after_header(values, context)
  +bodies_repeat = specified_body_idempotent(values, context)
  Equal.trans(+List<UI.Node>,
    specified_body(specified_order(values, context), context),
    List.append(&2, UI.Node, specified_body(headers, context), specified_body(bodies, context)),
    bodies, split,
    Equal.trans(+List<UI.Node>,
      List.append(&2, UI.Node, specified_body(headers, context), specified_body(bodies, context)),
      List.append(&2, UI.Node, Nil{}, bodies),
      bodies,
      Equal.trans(+List<UI.Node>,
        List.append(&2, UI.Node, specified_body(headers, context), specified_body(bodies, context)),
        List.append(&2, UI.Node, Nil{}, specified_body(bodies, context)),
        List.append(&2, UI.Node, Nil{}, bodies),
        Equal.cong(+List<UI.Node>, +List<UI.Node>, (head => List.append(&2, UI.Node, head, specified_body(bodies, context))),
          specified_body(headers, context), Nil{}, header_empty),
        Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => List.append(&2, UI.Node, Nil{}, tail)),
          specified_body(bodies, context), bodies, bodies_repeat)),
      {==}))

def specified_order_idempotent(+values: +List<UI.Node>, +context: Controls.Context) ->
  {specified_order(specified_order(values, context), context) == specified_order(values, context) : +List<UI.Node>}:
  +headers = specified_header(values, context)
  +bodies = specified_body(values, context)
  Equal.trans(+List<UI.Node>,
    specified_order(specified_order(values, context), context),
    List.append(&2, UI.Node, specified_header(specified_order(values, context), context),
      specified_body(specified_order(values, context), context)),
    List.append(&2, UI.Node, headers, bodies),
    {==},
    Equal.trans(+List<UI.Node>,
      List.append(&2, UI.Node, specified_header(specified_order(values, context), context),
        specified_body(specified_order(values, context), context)),
      List.append(&2, UI.Node, headers, specified_body(specified_order(values, context), context)),
      List.append(&2, UI.Node, headers, bodies),
      Equal.cong(+List<UI.Node>, +List<UI.Node>, (head => List.append(&2, UI.Node, head,
        specified_body(specified_order(values, context), context))),
        specified_header(specified_order(values, context), context), headers,
        specified_header_of_order(values, context)),
    Equal.cong(+List<UI.Node>, +List<UI.Node>, (tail => List.append(&2, UI.Node, headers, tail)),
        specified_body(specified_order(values, context), context), bodies,
        specified_body_of_order(values, context))))

def dialog_order_idempotent(+values: +List<UI.Node>, +context: Controls.Context) ->
  {Order.ordered_children(UI.Dialog{}, Order.ordered_children(UI.Dialog{}, values, context), context) ==
    Order.ordered_children(UI.Dialog{}, values, context) : +List<UI.Node>}:
  +first_order = Order.ordered_children(UI.Dialog{}, values, context)
  +first_evidence = ordered_children_matches_specification(values, UI.Dialog{}, context)
  +second_evidence = ordered_children_matches_specification(first_order, UI.Dialog{}, context)
  +lifted_first = Equal.cong(+List<UI.Node>, +List<UI.Node>,
    (children => specified_order(children, context)), first_order, specified_order(values, context), first_evidence)
  Equal.trans(+List<UI.Node>,
    Order.ordered_children(UI.Dialog{}, first_order, context),
    specified_order(first_order, context),
    Order.ordered_children(UI.Dialog{}, values, context),
    second_evidence,
    Equal.trans(+List<UI.Node>,
      specified_order(first_order, context), specified_order(specified_order(values, context), context),
      Order.ordered_children(UI.Dialog{}, values, context),
      lifted_first,
      Equal.trans(+List<UI.Node>,
        specified_order(specified_order(values, context), context), specified_order(values, context),
        Order.ordered_children(UI.Dialog{}, values, context),
        specified_order_idempotent(values, context),
        Equal.sym(+List<UI.Node>, Order.ordered_children(UI.Dialog{}, values, context),
          specified_order(values, context), first_evidence))))

def node_with_children_preserves_payload(+value: UI.Node, +children: +List<UI.Node>) ->
  {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload}:
  match value:
    case UI.Node{key, semantic, label, role, meaning, original_children}: {==}

def ordered_surface_preserves_content_scope(surface: UI.Surface) ->
  {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload}:
  match surface:
    case UI.Surface{content, base, overlays, active_scope}: {==}


def FrameProjectionClaim(outcome: Model.SceneOutcome, projected: Maybe<&2, UI.Surface>) -> Type:
  match outcome:
    case Model.ReadyScene{scene}:
      {projected == Some{Visibility.project(PresentationLaws.scene_surface(scene), PresentationLaws.scene_layout(scene))} : Maybe<&2, UI.Surface>}
    case _: {projected == None{} : Maybe<&2, UI.Surface>}

def projected_frame_claim(+outcome: Model.SceneOutcome) -> FrameProjectionClaim(outcome, Model.projected_frame(outcome)):
  match outcome:
    case Model.ReadyScene{Model.Scene{presentation, platform, generation, realization, layout}}: {==}
    case Model.AwaitingTypography{}: {==}
    case Model.FailedTypography{}: {==}
    case Model.UnsupportedSpace{required, available}: {==}

def frame_surface_uses_ordered_projection(+state: Model.State, +surface: UI.Surface) ->
  FrameProjectionClaim(Model.scene_for_surface(state, Order.ordered_surface(surface)), Model.frame_surface(state, surface)):
  projected_frame_claim(Model.scene_for_surface(state, Order.ordered_surface(surface)))

def occurrence_step(included: Bool, rest: Nat) -> Nat:
  match included:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

type CountPredicate is Data:
  CountAll{}
  CountKey{key: String}

def count_matches(predicate: CountPredicate, value: UI.Node) -> Bool:
  match predicate:
    case CountAll{}: True{}
    case CountKey{key}: String.eq(UI.node_key(value), key)

def count_by(+predicate: CountPredicate, values: +List<UI.Node>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{+value, rest}: occurrence_step(count_matches(predicate, value), count_by(predicate, rest))

def count_append_step(+predicate: CountPredicate, +value: UI.Node, +rest: +List<UI.Node>,
  +right: +List<UI.Node>, included: Bool,
  tail_evidence: {count_by(predicate, List.append(&2, UI.Node, rest, right)) ==
    Nat.add(count_by(predicate, rest), count_by(predicate, right)) : Nat}) ->
  {occurrence_step(included, count_by(predicate, List.append(&2, UI.Node, rest, right))) ==
    Nat.add(occurrence_step(included, count_by(predicate, rest)), count_by(predicate, right)) : Nat}:
  match included:
    case True{}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        count_by(predicate, List.append(&2, UI.Node, rest, right)),
        Nat.add(count_by(predicate, rest), count_by(predicate, right)), tail_evidence)
    case False{}: tail_evidence

def count_append(+predicate: CountPredicate, +left: +List<UI.Node>, +right: +List<UI.Node>) ->
  {count_by(predicate, List.append(&2, UI.Node, left, right)) ==
    Nat.add(count_by(predicate, left), count_by(predicate, right)) : Nat}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = count_append(predicate, rest, right)
      count_append_step(predicate, value, rest, right, count_matches(predicate, value), tail_evidence)

def add_succ_right(left: Nat, right: Nat) ->
  {Nat.add(left, Nat.add(1n, right)) == Nat.add(1n, Nat.add(left, right)) : Nat}:
  match left:
    case 0n: {==}
    case 1n+rest:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        Nat.add(rest, Nat.add(1n, right)), Nat.add(1n, Nat.add(rest, right)),
        add_succ_right(rest, right))

def body_count_step(included: Bool, prefix: Nat, suffix: Nat) ->
  {Nat.add(prefix, occurrence_step(included, suffix)) ==
    occurrence_step(included, Nat.add(prefix, suffix)) : Nat}:
  match included:
    case True{}: add_succ_right(prefix, suffix)
    case False{}: {==}

def partition_count_step(+predicate: CountPredicate, +value: UI.Node, +rest: +List<UI.Node>,
  include: Bool, tail_parts: Order.DialogParts, +context: Controls.Context,
  tail_evidence: {count_by(predicate, Order.ordered_dialog_children(tail_parts)) ==
    count_by(predicate, rest) : Nat}) ->
  {count_by(predicate,
      Order.ordered_dialog_children(Order.partition_child(value, include, tail_parts))) ==
    count_by(predicate, value <> rest) : Nat}:
  match include:
    case True{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          Equal.cong(Nat, Nat, (count => occurrence_step(count_matches(predicate, value), count)),
            count_by(predicate, Order.ordered_dialog_children(tail_parts)),
            count_by(predicate, rest), tail_evidence)
    case False{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          +join_evidence = count_append(predicate, headers, bodies)
          +tail_relation = Equal.trans(Nat,
            Nat.add(count_by(predicate, headers), count_by(predicate, bodies)),
            count_by(predicate, List.append(&2, UI.Node, headers, bodies)),
            count_by(predicate, rest),
            Equal.sym(Nat, count_by(predicate, List.append(&2, UI.Node, headers, bodies)),
              Nat.add(count_by(predicate, headers), count_by(predicate, bodies)), join_evidence),
            tail_evidence)
          Equal.trans(Nat,
            count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
            Nat.add(count_by(predicate, headers), occurrence_step(count_matches(predicate, value), count_by(predicate, bodies))),
            occurrence_step(count_matches(predicate, value), count_by(predicate, rest)),
            Equal.trans(Nat,
              count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
              Nat.add(count_by(predicate, headers), count_by(predicate, value <> bodies)),
              Nat.add(count_by(predicate, headers), occurrence_step(count_matches(predicate, value), count_by(predicate, bodies))),
              count_append(predicate, headers, value <> bodies),
              Equal.cong(Nat, Nat, (count => Nat.add(count_by(predicate, headers), count)),
                count_by(predicate, value <> bodies), occurrence_step(count_matches(predicate, value), count_by(predicate, bodies)), {==})),
            Equal.trans(Nat,
              Nat.add(count_by(predicate, headers), occurrence_step(count_matches(predicate, value), count_by(predicate, bodies))),
              occurrence_step(count_matches(predicate, value), Nat.add(count_by(predicate, headers), count_by(predicate, bodies))),
              occurrence_step(count_matches(predicate, value), count_by(predicate, rest)),
              body_count_step(count_matches(predicate, value), count_by(predicate, headers), count_by(predicate, bodies)),
              Equal.cong(Nat, Nat, (count => occurrence_step(count_matches(predicate, value), count)),
                Nat.add(count_by(predicate, headers), count_by(predicate, bodies)), count_by(predicate, rest), tail_relation)))

def partition_count_preserved(+predicate: CountPredicate, +values: +List<UI.Node>,
  +context: Controls.Context) ->
  {count_by(predicate, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
    count_by(predicate, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_count_preserved(predicate, rest, context)
      partition_count_step(predicate, value, rest, Order.header_child(value, context), tail_parts,
        context, tail_evidence)

def count_all_is_length(values: +List<UI.Node>) ->
  {count_by(CountAll{}, values) == List.length(&2, UI.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        count_by(CountAll{}, rest), List.length(&2, UI.Node, rest), count_all_is_length(rest))





type Requirements is Type:
  Requirements{
    non_dialog_order: @role:UI.Role -> @values:+List<UI.Node> -> @context:Controls.Context ->
      {non_dialog_order_observation(role, values, context) == values : +List<UI.Node>},
    dialog_partition_specification: @values:+List<UI.Node> -> @context:Controls.Context ->
      {Order.partition_dialog_children(values, context) == specified_parts(values, context) : Order.DialogParts},
    dialog_partition_length: @values:+List<UI.Node> -> @context:Controls.Context ->
      {List.length(&2, UI.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        List.length(&2, UI.Node, values) : Nat},
    dialog_partition_occurrences: @target:UI.Node -> @values:+List<UI.Node> -> @context:Controls.Context ->
      {count_by(CountKey{UI.node_key(target)},
          Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        count_by(CountKey{UI.node_key(target)}, values) : Nat},
    ordered_children_reference: @values:+List<UI.Node> -> @role:UI.Role -> @context:Controls.Context ->
      {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<UI.Node>},
    dialog_order_idempotent: @values:+List<UI.Node> -> @context:Controls.Context ->
      {Order.ordered_children(UI.Dialog{}, Order.ordered_children(UI.Dialog{}, values, context), context) ==
        Order.ordered_children(UI.Dialog{}, values, context) : +List<UI.Node>},
    node_payload_preserved: @value:UI.Node -> @children:+List<UI.Node> ->
      {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload},
    surface_content_scope_preserved: @surface:UI.Surface ->
      {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload},
    scene_uses_ordered_surface: @environment:Design.Environment -> @+application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      PresentationLaws.SemanticClaim(Model.observe(Model.State{application, generation, realization, environment, font}),
        Order.ordered_surface(Model.surface(application))),
    frame_uses_ordered_projection: @+state:Model.State -> @+surface:UI.Surface ->
      FrameProjectionClaim(Model.scene_for_surface(state, Order.ordered_surface(surface)), Model.frame_surface(state, surface))
  }

def evidence() -> Requirements:
  Requirements{
    role => values => context => non_dialog_order(role, values, context),
    values => context => partition_matches_specification(values, context),
    +values => +context =>
      Equal.trans(Nat,
        List.length(&2, UI.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        count_by(CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        List.length(&2, UI.Node, values),
        Equal.sym(Nat,
          count_by(CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          List.length(&2, UI.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          count_all_is_length(Order.ordered_dialog_children(Order.partition_dialog_children(values, context)))),
        Equal.trans(Nat,
          count_by(CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          count_by(CountAll{}, values), List.length(&2, UI.Node, values),
          partition_count_preserved(CountAll{}, values, context), count_all_is_length(values)))
    ,
    +target => +values => +context => partition_count_preserved(CountKey{UI.node_key(target)}, values, context),
    values => role => context => ordered_children_matches_specification(values, role, context),
    values => context => dialog_order_idempotent(values, context),
    value => children => node_with_children_preserves_payload(value, children),
    surface => ordered_surface_preserves_content_scope(surface),
    environment => +application => generation => realization => font =>
      PresentationLaws.observes_semantic_surface(Model.State{application, generation, realization, environment, font})
    ,
    +state => +surface => frame_surface_uses_ordered_projection(state, surface)}
