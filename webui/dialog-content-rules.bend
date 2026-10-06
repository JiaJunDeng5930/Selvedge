import Base
import ./authored.bend as Authored
import ./source.bend as Source

# This specification flattens each original child's ordinary source nodes;
# it does not classify children or move operations past following content.
def dialog_reading_content(+children: +List<Authored.Child>) -> +List<Source.Node>:
  match children:
    case Nil{}: Nil{}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      List.append(&2, Source.Node, Authored.ordinary(nodes), dialog_reading_content(rest))

def dialog_reading_order(+children: +List<Authored.Child>) -> Type:
  {List.append(&2, Source.Node, Authored.dialog_body(children), Authored.dialog_actions(children)) ==
    dialog_reading_content(children) : +List<Source.Node>}
