import Base
import ../context-control-laws.bend as Rule
import ../enclosure.bend as Enclosure
import ../space.bend as Space
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../core/user-context.bend as Context
import ../controls.bend as Controls
import ../renderer.bend as Render
import ../design.bend as Design
import ./control.bend as BindingProof

def initial_execution(+content: Core.Scene) ->
  {Rule.execution_observation(Controls.initial(content)) == Rule.page_observation(content) : Maybe<&2, Context.Observation>}:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, entered, appearance, open_action, close_action, connect} = settings
  {==}



















def choice_native_event(+key: String, label: String, selected: Bool, description: String, +visual: Design.Style,
  input: Core.Input, availability: View.Availability, name: String, face: Controls.Face,
  behavior: Controls.Behavior, geometry: Controls.Geometry, placement: Controls.Placement,
  help: Controls.Help, feedback: Controls.Feedback, visual_children: +List<Render.Child>) -> Rule.choice_native_event_law(key, label, selected, description, visual, input, availability, name, face, behavior, geometry, placement, help, feedback, visual_children):
  Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}















def Rule.evidence():
  Rule.Requirements{choice_native_event, +key => +selected => description => +input => +availability => +label => role => context => BindingProof.choice_retains_binding(key, selected, description, input, availability, label, role, context), +selected => {==}, +selected => description => +input => +availability => {==}, +selected => description => +input => +availability => {==}, +key => semantic => +label => role => +selected => description => +input => +availability => +elements => {==}, +label => expanded => {==}, +label => current => +execution => {==}, initial_execution, +origin => +project => +workspace => +sandbox => +approval => +guidance => {==}, +task => +workspace => +sandbox => +approval => +project => +guidance => +access => {==}, +reason => {==}, +label => {==}, +filesystem => +network => +approval => +name => {==}, +label => current => execution => {==}, +label => current => execution => {==}, {==}, {==}, {==}, {==}, {==}, {==}, +profile => {==}}
