import Base
import ../../bendlib/logic-proof.bend as Logic
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../bendlib/stdlib.bend as Std
import ./MODEL.bend as Authored
import ../document/SOURCE.bend as Source
import ./dialog-content-rules.bend as Rule

def dialog_prepend_trailing_reading(+operation: Bool, +nodes: +List<Source.Node>, +actions: +List<Source.Node>) ->
  {Authored.append(Authored.dialog_part_body(Authored.dialog_prepend_trailing(operation, nodes, actions)),
    Authored.dialog_part_actions(Authored.dialog_prepend_trailing(operation, nodes, actions))) ==
    Authored.append(Authored.ordinary(nodes), actions) : +List<Source.Node>}:
  match operation:
    case True{}: {==}
    case False{}: {==}

# Match the original tail partition rather than a computed classification, so
# the proof retains the exact boundary chosen by the production recursion.
def dialog_prepend_reading(+operation: Bool, +nodes: +List<Source.Node>, +parts: Authored.DialogParts) ->
  {Authored.append(Authored.dialog_part_body(Authored.dialog_prepend(operation, nodes, parts)),
    Authored.dialog_part_actions(Authored.dialog_prepend(operation, nodes, parts))) ==
    Authored.append(Authored.ordinary(nodes), Authored.append(Authored.dialog_part_body(parts),
      Authored.dialog_part_actions(parts))) : +List<Source.Node>}:
  match parts:
    case Authored.TrailingActions{actions}:
      dialog_prepend_trailing_reading(operation, nodes, actions)
    case Authored.BodyAndActions{body, actions}:
      Equal.sym(+List<Source.Node>,
        Authored.append(Authored.ordinary(nodes), Authored.append(body, actions)),
        Authored.append(Authored.append(Authored.ordinary(nodes), body), actions),
        Std.app_assoc(Source.Node, Authored.ordinary(nodes), body, actions))

def dialog_reading_order(+children: +List<Authored.Child>) -> Rule.dialog_reading_order(children):
  match children:
    case Nil{}: {==}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      +parts = Authored.dialog_parts(rest)
      tail_evidence = dialog_reading_order(rest)
      Equal.trans(+List<Source.Node>,
        Authored.append(Authored.dialog_body(Authored.Child{key, role, meaning, control, nodes} <> rest),
          Authored.dialog_actions(Authored.Child{key, role, meaning, control, nodes} <> rest)),
        Authored.append(Authored.ordinary(nodes), Authored.append(Authored.dialog_part_body(parts),
          Authored.dialog_part_actions(parts))),
        Authored.append(Authored.ordinary(nodes), Rule.dialog_reading_content(rest)),
        dialog_prepend_reading(Authored.dialog_operation(role), nodes, parts),
        Equal.cong(+List<Source.Node>, +List<Source.Node>,
          (tail => Authored.append(Authored.ordinary(nodes), tail)),
          Authored.append(Authored.dialog_body(rest), Authored.dialog_actions(rest)),
          Rule.dialog_reading_content(rest), tail_evidence))

def Rule.choice_content(kind, classification, selected, description, input, availability):
  {==}

def Rule.choice_group_content():
  {==}

def Rule.choice_group_partition(key, control, choices, action_key, action_control, actions, input, availability):
  Equal.cong(+List<Source.Node>, Authored.DialogParts,
    (tail => Authored.BodyAndActions{Authored.ordinary(choices), tail}),
    List.append(&2, Source.Node, Authored.ordinary(actions), Nil{}), Authored.ordinary(actions), Std.app_nil_r(Source.Node, Authored.ordinary(actions)))

def action_suffix_head(first: Bool, following: Bool, evidence: {first && following == True{} : Bool}) ->
  {first == True{} : Bool} & {following == True{} : Bool}:
  match first following:
    case True{} True{}: ({==}, {==})
    case False{} True{}: Logic.impossible({False{} == True{} : Bool} & {True{} == True{} : Bool}, evidence)
    case True{} False{}: Logic.impossible({True{} == True{} : Bool} & {False{} == True{} : Bool}, evidence)
    case False{} False{}: Logic.impossible({False{} == True{} : Bool} & {False{} == True{} : Bool}, evidence)

def action_suffix_first(first: Bool, following: Bool, evidence: {first == True{} : Bool} & {following == True{} : Bool}) ->
  {first == True{} : Bool}:
  (head, tail) = evidence
  head

def action_suffix_following(first: Bool, following: Bool, evidence: {first == True{} : Bool} & {following == True{} : Bool}) ->
  {following == True{} : Bool}:
  (head, tail) = evidence
  tail

# The suffix premise constrains the same role classifier used by production.
def action_suffix_parts(+children: +List<Authored.Child>, +evidence: {Authored.dialog_only_actions(children) == True{} : Bool}) ->
  {Authored.dialog_parts(children) == Authored.TrailingActions{Rule.dialog_reading_content(children)} : Authored.DialogParts}:
  match children:
    case Nil{}: {==}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      head = action_suffix_first(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), action_suffix_head(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), evidence))
      tail = action_suffix_following(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), action_suffix_head(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), evidence))
      Equal.trans(Authored.DialogParts,
        Authored.dialog_prepend(Authored.dialog_operation(role), nodes, Authored.dialog_parts(rest)),
        Authored.dialog_prepend(True{}, nodes, Authored.dialog_parts(rest)),
        Authored.TrailingActions{Authored.append(Authored.ordinary(nodes), Rule.dialog_reading_content(rest))},
        Equal.cong(Bool, Authored.DialogParts, operation => Authored.dialog_prepend(operation, nodes, Authored.dialog_parts(rest)),
          Authored.dialog_operation(role), True{}, head),
        Equal.cong(Authored.DialogParts, Authored.DialogParts, parts => Authored.dialog_prepend(True{}, nodes, parts),
          Authored.dialog_parts(rest), Authored.TrailingActions{Rule.dialog_reading_content(rest)}, action_suffix_parts(rest, tail)))

def Rule.dialog_action_region():
  {==}

def Rule.dialog_action_footer(key, meaning, control, nodes, rest, ordered):
  Equal.cong(Authored.DialogParts, Authored.DialogParts, parts => Authored.dialog_prepend(True{}, nodes, parts),
    Authored.dialog_parts(rest), Authored.TrailingActions{Rule.dialog_reading_content(rest)}, action_suffix_parts(rest, ordered))

def ordinary_prepend(+nodes: +List<Source.Node>, +parts: Authored.DialogParts) ->
  {Authored.dialog_prepend(False{}, nodes, parts) == Authored.BodyAndActions{Authored.append(Authored.ordinary(nodes), Authored.dialog_part_body(parts)), Authored.dialog_part_actions(parts)} : Authored.DialogParts}:
  match parts:
    case Authored.TrailingActions{actions}:
      Equal.cong(+List<Source.Node>, Authored.DialogParts, body => Authored.BodyAndActions{body, actions},
        Authored.ordinary(nodes), Authored.append(Authored.ordinary(nodes), Nil{}),
        Equal.sym(+List<Source.Node>, Authored.append(Authored.ordinary(nodes), Nil{}), Authored.ordinary(nodes), Std.app_nil_r(Source.Node, Authored.ordinary(nodes))))
    case Authored.BodyAndActions{body, actions}: {==}

def Rule.dialog_ordinary_activation(key, role, input, availability, control, nodes, rest, ordinary):
  Equal.trans(Authored.DialogParts,
    Authored.dialog_prepend(Authored.dialog_operation(role), nodes, Authored.dialog_parts(rest)),
    Authored.dialog_prepend(False{}, nodes, Authored.dialog_parts(rest)),
    Authored.BodyAndActions{Authored.append(Authored.ordinary(nodes), Authored.dialog_body(rest)), Authored.dialog_actions(rest)},
    Equal.cong(Bool, Authored.DialogParts, operation => Authored.dialog_prepend(operation, nodes, Authored.dialog_parts(rest)),
      Authored.dialog_operation(role), False{}, ordinary), ordinary_prepend(nodes, Authored.dialog_parts(rest)))

def Rule.dialog_rejects_invalid_order(key, label, meaning, visual, control, children, parameters, invalid):
  Equal.cong(Bool, Authored.Authorship,
    ordered => Authored.authored_node_ordered(ordered, key, label, InterfaceView.Dialog{}, meaning, visual, control, children, parameters),
    Authored.dialog_ordered(children), False{}, invalid)
