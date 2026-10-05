import Base
import ../choice-rules.bend as Rule
import ../interface.bend as UI
import ../SYSTEM.bend as Core
import ../ui-world.bend as View
import ../../BOARD.bend as Board
import ../../bendlib/json.bend as J
import ../../bendlib/schema.bend as Schema
import ../../bendlib/board-filter.bend as Filter

# Selection changes the node's role, never its bound choice payload.
def finite_choice_payload(+kind: UI.ChoiceKind, +icon: Maybe<&2,String>, +selected: Bool, +description: String, +control: Core.Control, parent: String) ->
  {Rule.meaning(UI.finite_choice_control(kind, icon, selected, description, control, parent)) ==
    UI.Choice{kind, icon, selected, description, Rule.control_input(control), Rule.control_availability(control)} : UI.Meaning}:
  match selected:
    case True{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}
    case False{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}

def filter_payload(+choice: J.Json, +category: String, +filter: Board.Filter, parent: String, +state: Core.State) ->
  {Rule.meaning(UI.filter_option_node(choice, category, filter, parent, state)) ==
    UI.Choice{UI.MultipleChoice{}, Some{J.text(J.get(choice, "icon"))},
      Schema.contains(Filter.values(category, filter), J.text(J.get(choice, "value"))), "",
      Rule.control_input(Core.control(state, UI.filter_option_declaration(choice, category, filter))),
      Rule.control_availability(Core.control(state, UI.filter_option_declaration(choice, category, filter)))} : UI.Meaning}:
  finite_choice_payload(UI.MultipleChoice{}, Some{J.text(J.get(choice, "icon"))},
    Schema.contains(Filter.values(category, filter), J.text(J.get(choice, "value"))), "",
    Core.control(state, UI.filter_option_declaration(choice, category, filter)), parent)

def Rule.evidence():
  Rule.Requirements{
    kind => icon => selected => description => +input => +availability => {==},
    kind => icon => selected => description => input => +availability => {==},
    choice => category => filter => parent => state => filter_payload(choice, category, filter, parent, state),
    +owner => world => {==},
    +owner => +world => {==},
    value => projects => stages => priorities => +owners => {==}}
