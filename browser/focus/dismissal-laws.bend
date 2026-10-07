import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/STATE.bend as Core
import ../../interaction/MODEL.bend as Product
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/INPUT.bend as U
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../runtime/SEMANTICS.bend as Browser
import ./MODEL.bend as Focus
import ../controls/PROGRAM.bend as Controls
def application_layers(+application: E.Application) -> +List<E.Layer>:
  +observed_session_1 = E.session(application)
  +layers = E.layers(observed_session_1)
  +attention = E.attention(observed_session_1)
  layers

# The complete result fixes all unaffected state and the ordered attention effect.

def closed_application(+application: E.Application, panel: U.Panel, +trigger: String) -> E.Decision:
  +session = E.session(application)
  +layers = E.layers(session)
  E.Decision{E.with_session(E.with_attention(trigger,
    E.with_layers(E.without_panel(layers, E.panel_target(panel)), session)), application),
    D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}

type Requirements is Type:
  Requirements{
    toggle_absent: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @absent:{E.panel_present(application_layers(application), E.panel_target(panel)) == False{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision},
    toggle_present: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @present:{E.panel_present(application_layers(application), E.panel_target(panel)) == True{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == closed_application(application, panel, trigger) : E.Decision},
    details_policy: @task:Nat -> @trigger:String -> {View.layer_dismissal(U.TaskDetails{task}, trigger) == View.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}} : View.Dismissal},
    persistent_policy: @action:U.Action -> {InterfaceView.dismissal_meaning(View.ByTrigger{action}) == InterfaceView.LayerRegion{Core.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}} : InterfaceView.Meaning},
    transient_policy: @action:U.Action -> {InterfaceView.dismissal_meaning(View.OutsideOrEscape{action}) == InterfaceView.LayerRegion{Core.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}} : InterfaceView.Meaning},
    layer_children: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+initial:String -> @restore:String -> @dismissal:View.Dismissal -> @+state:Core.State ->
      {InterfaceView.layers([View.Layer{kind, content, initial, restore, dismissal}], state) ==
          [InterfaceView.Node{InterfaceView.layer_key(initial), initial, View.layer_title(content), InterfaceView.layer_role(kind), InterfaceView.dismissal_meaning(dismissal),
            InterfaceView.layer_content(content, InterfaceView.layer_key(initial), state)}] : +List<InterfaceView.Node>},
    observed_policy: @+key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:InterfaceView.Role -> @+input:Core.Input -> @+outside:Bool -> @+escape:Bool -> @children:+List<InterfaceView.Node> -> @rest:+List<InterfaceView.Node> ->
      {Browser.dismiss_target(InterfaceView.Node{key, semantic, label, role, InterfaceView.LayerRegion{input, outside, escape}, children} <> rest) == Some{Browser.DismissTarget{UIIdentity.encode(key), input, outside, escape}} : Maybe<&2, Browser.DismissTarget>},
    outside_absent: @+identity:String -> @+state:Browser.State -> {Browser.outside_target(identity, None{}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_persistent: @+identity:String -> @+key:String -> @input:Core.Input -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, False{}, escape}}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_stale: @+identity:String -> @+key:String -> @+input:Core.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> @stale:{String.eq(identity, key) == False{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    escape_persistent: @key:String -> @input:Core.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, False{}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    escape_dispatch: @key:String -> @+input:Core.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, True{}}}, state) == Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    outside_dispatch: @+identity:String -> @+key:String -> @+input:Core.Input -> @escape:Bool -> @+state:Browser.State -> @owned:{String.eq(identity, key) == True{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, True{}, escape}}, Browser.current_layer_key(state), state) == Browser.outside_permitted(Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) : Browser.OutsideDecision},
    outside_production: @+identity:String -> @+state:Browser.State -> {Browser.outside_event(identity, state) == Browser.outside_target(identity, Browser.dismiss_target(Browser.nodes(state)), Browser.current_layer_key(state), state) : Browser.OutsideDecision},
    outside_policy: @+identity:String -> @+key:String -> @+input:Core.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.current_layer_key(state), state) == Browser.outside_permitted((String.eq(identity, key) && outside) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) : Browser.OutsideDecision},
    outside_document: @input:Core.Input -> @+state:Browser.State -> {Browser.outside_scoped(Focus.Document{}, input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_temporary: @+identity:String -> @initial:String -> @restore:String -> @occurrence:Maybe<&2, Nat> -> @+input:Core.Input -> @+state:Browser.State -> {Browser.outside_scoped(Focus.Temporary{identity, initial, restore, occurrence}, input, state) == Browser.outside_transition(identity, Browser.product_input(Product.InterfaceInput{input}, state), state) : Browser.OutsideDecision},
    outside_transition_dispatch: @+identity:String -> @+candidate:Browser.Decision -> @+state:Browser.State -> @closed:{Browser.outside_closed(identity, candidate) == True{} : Bool} -> {Browser.outside_transition(identity, candidate, state) == Browser.OutsideDecision{True{}, candidate} : Browser.OutsideDecision},
    outside_transition_refusal: @+identity:String -> @+candidate:Browser.Decision -> @+state:Browser.State -> @retained:{Browser.outside_closed(identity, candidate) == False{} : Bool} -> {Browser.outside_transition(identity, candidate, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_completed_dispatch: @+candidate:Browser.Decision -> @state:Browser.State -> {Browser.outside_completed(True{}, candidate, state) == Browser.OutsideDecision{True{}, candidate} : Browser.OutsideDecision},
    outside_completed_refusal: @candidate:Browser.Decision -> @+state:Browser.State -> {Browser.outside_completed(False{}, candidate, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    collapsed_navigation: {Controls.navigation_icon(False{}) == Controls.Sidebar{} : Controls.Icon},
    expanded_navigation: {Controls.navigation_icon(True{}) == Controls.SidebarClose{} : Controls.Icon},
    collapsed_details: {Controls.inspector_icon(False{}) == Controls.Inspector{} : Controls.Icon},
    expanded_details: {Controls.inspector_icon(True{}) == Controls.InspectorClose{} : Controls.Icon}}
law evidence:
  Requirements
def panel_policy(panel: U.Panel, trigger: String, dismissal: View.Dismissal) -> Type:
  match panel:
    case U.TaskDetails{task}: {dismissal == View.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}} : View.Dismissal}
    case _: {dismissal == View.OutsideOrEscape{U.ClosePanel{}} : View.Dismissal}

law all_panel_policies:
  for +panel: U.Panel
  for +trigger: String
  panel_policy(panel, trigger, View.layer_dismissal(panel, trigger))
