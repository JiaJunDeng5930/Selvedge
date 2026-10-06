import Base
import ./authored.bend as Authored
import ./source.bend as Source
import ../core/interface.bend as UI
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
  for kind: UI.ChoiceKind
  for classification: Maybe<&2, Filter.Classification>
  for selected: Bool
  for description: String
  for input: Core.Input
  for availability: View.Availability
  {Authored.dialog_operation(UI.Choice{kind, classification, selected, description, input, availability}) == False{} : Bool}

law choice_group_content:
  {Authored.dialog_operation(UI.ChoiceGroup{}) == False{} : Bool}

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
    Authored.Child{key, UI.Section{}, UI.ChoiceGroup{}, control, choices},
    Authored.Child{action_key, UI.Button{}, UI.Activate{input, availability}, action_control, actions}]) ==
      Authored.BodyAndActions{Authored.ordinary(choices), Authored.ordinary(actions)} : Authored.DialogParts}
