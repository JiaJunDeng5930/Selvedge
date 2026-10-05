import Base
import ./interface.bend as UI
import ./SYSTEM.bend as Core
import ./ui-world.bend as View
import ./form-fields.bend as Forms
import ./field-options.bend as Options
import ../MODEL.bend as M
import ../BOARD.bend as Board
import ../bendlib/json.bend as J
import ../bendlib/schema.bend as Schema
import ../bendlib/board-filter.bend as Filter

# Observe the production payload without duplicating its node tree.
def meaning(node: UI.Node) -> UI.Meaning:
  UI.Node{key, semantic, label, role, value, children} = node
  value

def control_input(control: Core.Control) -> Core.Input:
  Core.Control{identity, label, prominence, input, availability} = control
  input

def control_availability(control: Core.Control) -> View.Availability:
  Core.Control{identity, label, prominence, input, availability} = control
  availability

def choice_identity(choice: Forms.ChoiceValue) -> String:
  Forms.ChoiceValue{value, label} = choice
  value

def choice_caption(choice: Forms.ChoiceValue) -> String:
  Forms.ChoiceValue{value, label} = choice
  label

type Requirements is Type:
  Requirements{
    press_binding: @kind:UI.ChoiceKind -> @icon:Maybe<&2,String> -> @selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability ->
      {UI.bind(UI.Choice{kind, icon, selected, description, input, availability}, UI.Press{}) == UI.when_available(UI.available(availability), input) : Maybe<&2,Core.Input>},
    availability: @kind:UI.ChoiceKind -> @icon:Maybe<&2,String> -> @selected:Bool -> @description:String -> @input:Core.Input -> @+availability:View.Availability ->
      {UI.focusable(UI.Choice{kind, icon, selected, description, input, availability}) == UI.available(availability) : Bool},
    filter_payload: @+choice:J.Json -> @+category:String -> @+filter:Board.Filter -> @parent:String -> @+state:Core.State ->
      {meaning(UI.filter_option_node(choice, category, filter, parent, state)) ==
        UI.Choice{UI.MultipleChoice{}, Some{J.text(J.get(choice, "icon"))},
          Schema.contains(Filter.values(category, filter), J.text(J.get(choice, "value"))), "",
          control_input(Core.control(state, UI.filter_option_declaration(choice, category, filter))),
          control_availability(Core.control(state, UI.filter_option_declaration(choice, category, filter)))} : UI.Meaning},
    owner_identity: @+owner:Board.Owner -> @world:M.World() ->
      {choice_identity(View.card_owner_choice(owner, world)) == Board.owner_name(owner) : String},
    owner_caption: @+owner:Board.Owner -> @+world:M.World() ->
      {choice_caption(View.card_owner_choice(owner, world)) == View.face_owner(owner, world) : String},
    card_owner_options: @value:Board.Draft -> @projects:+List<View.ProjectChoice> -> @stages:+List<Board.Stage> -> @priorities:+List<Board.Priority> -> @+owners:+List<Forms.ChoiceValue> ->
      {Options.group_options("card-owner", View.CardContentInput{value, projects, stages, priorities, owners}) == owners : +List<Forms.ChoiceValue>}
  }

law evidence:
  Requirements
