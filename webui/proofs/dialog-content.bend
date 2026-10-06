import Base
import ../../bendlib/stdlib.bend as Std
import ../authored.bend as Authored
import ../source.bend as Source
import ../dialog-content-rules.bend as Rule

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
        dialog_prepend_reading(Authored.dialog_operation(meaning), nodes, parts),
        Equal.cong(+List<Source.Node>, +List<Source.Node>,
          (tail => Authored.append(Authored.ordinary(nodes), tail)),
          Authored.append(Authored.dialog_body(rest), Authored.dialog_actions(rest)),
          Rule.dialog_reading_content(rest), tail_evidence))
