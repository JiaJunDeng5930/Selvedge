import Base
import ../ui-identity.bend as Identity
import ../choice-rules.bend as Rule
import ../interface.bend as UI
import ../SYSTEM.bend as Core
import ../ui-world.bend as View
import ../../BOARD.bend as Board
import ../../bendlib/schema.bend as Schema
import ../../bendlib/board-filter.bend as Filter

# Selection changes the node's role, never its bound choice payload.
def finite_choice_payload(+kind: UI.ChoiceKind, +classification: Maybe<&2,Filter.Classification>, +selected: Bool, +description: String, +control: Core.Control, parent: Identity.Key) ->
  {Rule.meaning(UI.finite_choice_control(kind, classification, selected, description, control, parent)) ==
    UI.Choice{kind, classification, selected, description, Rule.control_input(control), Rule.control_availability(control)} : UI.Meaning}:
  match selected:
    case True{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}
    case False{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}

def filter_payload(+choice: Filter.Choice, +category: String, +filter: Board.Filter, parent: Identity.Key, +state: Core.State) ->
  {Rule.meaning(UI.filter_option_node(choice, category, filter, parent, state)) ==
    UI.Choice{UI.MultipleChoice{}, Some{Rule.filter_classification(choice)},
      Schema.contains(Filter.values(category, filter), Rule.filter_value(choice)), "",
      Rule.control_input(Core.control(state, UI.filter_option_declaration(choice, category, filter))),
      Rule.control_availability(Core.control(state, UI.filter_option_declaration(choice, category, filter)))} : UI.Meaning}:
  Filter.Choice{+value, label, classification} = choice
  finite_choice_payload(UI.MultipleChoice{}, Some{classification},
    Schema.contains(Filter.values(category, filter), value), "",
    Core.control(state, UI.filter_option_declaration(choice, category, filter)), Identity.Entity{parent, "filter-option", value})

def Rule.evidence():
  Rule.Requirements{
    kind => classification => selected => description => +input => +availability => {==},
    kind => classification => selected => description => input => +availability => {==},
    choice => category => filter => parent => state => filter_payload(choice, category, filter, parent, state),
    +owner => world => {==},
    +owner => +world => {==},
    value => projects => stages => priorities => +owners => {==},
    value => projects => stages => +priorities => owners => {==}}
