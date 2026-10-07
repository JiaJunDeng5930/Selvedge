import Base
import ./design.bend as Design
import ./authored.bend as Authored
import ./source.bend as Source
import ../core/interface.bend as InterfaceView
import ../core/ui-identity.bend as Identity
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../bendlib/board-filter.bend as Filter
import ./controls.bend as Controls

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

# Selection alternatives remain content even though choosing one produces input.
law choice_content:
  for kind: InterfaceView.ChoiceKind
  for classification: Maybe<&2, Filter.Classification>
  for selected: Bool
  for description: String
  for input: Core.Input
  for availability: View.Availability
  {Authored.dialog_operation(InterfaceView.Button{}) == False{} : Bool}

law choice_group_content:
  {Authored.dialog_operation(InterfaceView.Section{}) == False{} : Bool}

law choice_group_partition:
  for key: Identity.Key
  for control: Controls.Representation
  for +choices: +List<Source.Node>
  for action_key: Identity.Key
  for action_control: Controls.Representation
  for +actions: +List<Source.Node>
  for input: Core.Input
  for availability: View.Availability
  {Authored.dialog_parts([
    Authored.Child{key, InterfaceView.Section{}, InterfaceView.ChoiceGroup{}, control, choices},
    Authored.Child{action_key, InterfaceView.DialogActions{}, InterfaceView.Activate{input, availability}, action_control, actions}]) ==
      Authored.BodyAndActions{Authored.ordinary(choices), Authored.ordinary(actions)} : Authored.DialogParts}

law dialog_action_region:
  {Authored.dialog_operation(InterfaceView.DialogActions{}) == True{} : Bool}

law dialog_action_footer:
  for key: Identity.Key
  for meaning: InterfaceView.Meaning
  for control: Controls.Representation
  for +nodes: +List<Source.Node>
  for +rest: +List<Authored.Child>
  for ordered: {Authored.dialog_ordered(Authored.Child{key, InterfaceView.DialogActions{}, meaning, control, nodes} <> rest) == True{} : Bool}
  {Authored.dialog_parts(Authored.Child{key, InterfaceView.DialogActions{}, meaning, control, nodes} <> rest) ==
    Authored.TrailingActions{List.append(&2, Source.Node, Authored.ordinary(nodes), dialog_reading_content(rest))} : Authored.DialogParts}

law dialog_ordinary_activation:
  for key: Identity.Key
  for role: InterfaceView.Role
  for input: Core.Input
  for availability: View.Availability
  for control: Controls.Representation
  for +nodes: +List<Source.Node>
  for +rest: +List<Authored.Child>
  for ordinary: {Authored.dialog_operation(role) == False{} : Bool}
  {Authored.dialog_parts(Authored.Child{key, role, InterfaceView.Activate{input, availability}, control, nodes} <> rest) ==
    Authored.BodyAndActions{List.append(&2, Source.Node, Authored.ordinary(nodes), Authored.dialog_body(rest)), Authored.dialog_actions(rest)} : Authored.DialogParts}

law dialog_rejects_invalid_order:
  for key: Identity.Key
  for label: String
  for meaning: InterfaceView.Meaning
  for visual: Design.Style
  for control: Controls.Representation
  for +children: +List<Authored.Child>
  for parameters: Design.LayoutParameters
  for invalid: {Authored.dialog_ordered(children) == False{} : Bool}
  {Authored.authored_node(key, label, InterfaceView.Dialog{}, meaning, visual, control, children, parameters) ==
    Authored.Rejected{key, Authored.InvalidDialogOrder{}} : Authored.Authorship}
