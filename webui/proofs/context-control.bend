import Base
import ../context-control-laws.bend as Rule
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../core/user-context.bend as Context
import ../controls.bend as Controls
import ./control.bend as BindingProof

def initial_execution(+content: Core.Scene) ->
  {Rule.execution_observation(Controls.initial(content)) == Rule.page_observation(content) : Maybe<&2, Context.Observation>}:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, entered, appearance, open_action, close_action, connect} = settings
  {==}

def Rule.evidence():
  Rule.Requirements{
    +key => +selected => description => +input => +availability => +label => role => context => BindingProof.choice_retains_binding(key, selected, description, input, availability, label, role, context),
    +selected => description => +input => +availability => {==},
    +selected => description => +input => +availability => {==},
    +key => semantic => +label => role => +selected => description => +input => +availability => +elements => {==},
    +label => expanded => {==},
    +label => current => +execution => {==},
    initial_execution,
    +origin => +project => +workspace => +sandbox => +approval => +guidance => {==},
    +task => +workspace => +sandbox => +approval => +project => +guidance => +access => {==},
    +reason => {==},
    +label => {==},
    +filesystem => +network => +approval => +name => {==},
    +label => current => execution => {==},
    +label => current => execution => {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    +profile => {==}}
