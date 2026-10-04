import Base
import ../core/SYSTEM.bend as Core
import ../UI.bend as Product
import ../core/interface.bend as UI
import ../core/user-input.bend as U
import ../core/user-experience.bend as E
import ../core/ui-world.bend as View
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./browser.bend as Browser
import ./focus.bend as Focus
import ./controls.bend as Controls

def application_layers(application: E.Application) -> +List<E.Layer>:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  layers

# The complete result fixes all unaffected state and the ordered attention effect.

def closed_application(+application: E.Application, panel: U.Panel, +trigger: String) -> E.Decision:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  E.Decision{E.Application{program, E.Session{route, drafts, readers, E.without_panel(layers, E.panel_target(panel)), trigger,
    navigation, filter, now, next, pending, previews, code_blocks}}, D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}

type Requirements is Type:
  Requirements{
    toggle_absent: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @absent:{E.panel_present(application_layers(application), E.panel_target(panel)) == False{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision},
    toggle_present: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @present:{E.panel_present(application_layers(application), E.panel_target(panel)) == True{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == closed_application(application, panel, trigger) : E.Decision},
    details_policy: @task:Nat -> @trigger:String -> {View.layer_dismissal(U.TaskDetails{task}, trigger) == View.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}} : View.Dismissal},
    persistent_policy: @action:U.Action -> {UI.dismissal_meaning(View.ByTrigger{action}) == UI.LayerRegion{Core.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}} : UI.Meaning},
    transient_policy: @action:U.Action -> {UI.dismissal_meaning(View.OutsideOrEscape{action}) == UI.LayerRegion{Core.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}} : UI.Meaning},
    layer_children: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+initial:String -> @restore:String -> @dismissal:View.Dismissal -> @+state:Core.State ->
      {UI.layers([View.Layer{kind, content, initial, restore, dismissal}], state) ==
          [UI.Node{UI.layer_key(initial), initial, View.layer_title(content), UI.layer_role(kind), UI.dismissal_meaning(dismissal),
            UI.layer_content(content, UI.layer_key(initial), state)}] : +List<UI.Node>},
    observed_policy: @+key:String -> @semantic:String -> @label:String -> @role:UI.Role -> @+input:Core.Input -> @+outside:Bool -> @+escape:Bool -> @children:+List<UI.Node> -> @rest:+List<UI.Node> ->
      {Browser.dismiss_target(UI.Node{key, semantic, label, role, UI.LayerRegion{input, outside, escape}, children} <> rest) == Some{Browser.DismissTarget{key, input, outside, escape}} : Maybe<&2, Browser.DismissTarget>},
    outside_absent: @+identity:String -> @+state:Browser.State -> {Browser.outside_target(identity, None{}, Browser.scene_layer_key(Browser.scene(state)), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_persistent: @+identity:String -> @+key:String -> @input:Core.Input -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, False{}, escape}}, Browser.scene_layer_key(Browser.scene(state)), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_stale: @+identity:String -> @+key:String -> @+input:Core.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> @stale:{String.eq(identity, key) == False{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.scene_layer_key(Browser.scene(state)), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    escape_persistent: @key:String -> @input:Core.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, False{}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    escape_dispatch: @key:String -> @+input:Core.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, True{}}}, state) == Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    outside_dispatch: @+identity:String -> @+key:String -> @+input:Core.Input -> @escape:Bool -> @+state:Browser.State -> @owned:{String.eq(identity, key) == True{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, True{}, escape}}, Browser.scene_layer_key(Browser.scene(state)), state) == Browser.outside_permitted(Browser.outside_layer_owned(identity, Browser.scene_layer_key(Browser.scene(state))), input, state) : Browser.OutsideDecision},
    outside_production: @+identity:String -> @+state:Browser.State -> {Browser.outside_event(identity, state) == Browser.outside_target(identity, Browser.dismiss_target(Browser.nodes(state)), Browser.scene_layer_key(Browser.scene(state)), state) : Browser.OutsideDecision},
    outside_policy: @+identity:String -> @+key:String -> @+input:Core.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.scene_layer_key(Browser.scene(state)), state) == Browser.outside_permitted((String.eq(identity, key) && outside) && Browser.outside_layer_owned(identity, Browser.scene_layer_key(Browser.scene(state))), input, state) : Browser.OutsideDecision},
    outside_document: @input:Core.Input -> @+state:Browser.State -> {Browser.outside_scoped(Focus.Document{}, input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_temporary: @+identity:String -> @initial:String -> @restore:String -> @+input:Core.Input -> @+state:Browser.State -> {Browser.outside_scoped(Focus.Temporary{identity, initial, restore}, input, state) == Browser.outside_transition(identity, Browser.product_input(Product.InterfaceInput{input}, state), state) : Browser.OutsideDecision},
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
