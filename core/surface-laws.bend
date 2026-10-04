import Base
import ../MODEL.bend as M
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ../UI.bend as UI
import ./SYSTEM.bend as Core
import ./laws.bend as Laws
import ./interface.bend as Interface
import ./ui-world.bend as View
import ./user-input.bend as U
import ./user-experience.bend as E
import ./client-services.bend as Services

type Receipt is Data:
  Receipt{runtime: M.Decision(), services: Services.State,
    interaction: +List<E.Effect>, service_effects: +List<Services.Effect>, durable: Bool}

def receipt(+decision: Core.Decision) -> Receipt:
  Core.Decision{Core.State{application, services}, reply, runtime, interaction, service_effects, durable} = decision
  Receipt{Laws.runtime(decision), services, interaction, service_effects, durable}

def quiet_decision(+state: Core.State) -> Core.Decision:
  Core.State{application, services} = state
  Core.Decision{Core.State{application, services}, D.success(J.Null{}), Nil{}, Nil{}, Nil{}, False{}}

type Requirements is Type:
  Requirements{
    absent_element: @capacity:View.Capacity -> @+state:Core.State -> @key:String -> @gesture:Interface.Gesture ->
      @absent:{Interface.find_node(Interface.active_nodes(UI.observe(capacity, state)), key) == None{} : Maybe<&2, Interface.Node>} ->
      {UI.step(UI.Element{capacity, key, gesture}, state) == quiet_decision(state) : Core.Decision},
    disabled_element: @capacity:View.Capacity -> @+state:Core.State -> @key:String -> @+input:Core.Input ->
      @reason:String -> @node_key:String -> @semantic:String -> @label:String -> @role:Interface.Role -> @+children:+List<Interface.Node> ->
      @found:{Interface.find_node(Interface.active_nodes(UI.observe(capacity, state)), key) ==
        Some{Interface.Node{node_key, semantic, label, role, Interface.Activate{input, View.Unavailable{reason}}, children}} : Maybe<&2, Interface.Node>} ->
      {UI.step(UI.Element{capacity, key, Interface.Press{}}, state) == quiet_decision(state) : Core.Decision},
    absent_composer: @capacity:View.Capacity -> @+state:Core.State -> @editor:U.Editor ->
      @absent:{Interface.submission(Interface.active_nodes(UI.observe(capacity, state)), editor) == None{} : Maybe<&2, Interface.Node>} ->
      {UI.step(UI.SubmitComposer{capacity, editor}, state) == quiet_decision(state) : Core.Decision},
    element_receipt: @capacity:View.Capacity -> @+state:Core.State -> @key:String -> @gesture:Interface.Gesture ->
      {receipt(UI.step(UI.Element{capacity, key, gesture}, state)) ==
        receipt(Interface.apply_input(Interface.resolve(UI.observe(capacity, state), key, gesture), state)) : Receipt},
    available_element: @capacity:View.Capacity -> @+state:Core.State -> @key:String -> @+input:Core.Input ->
      @node_key:String -> @semantic:String -> @label:String -> @role:Interface.Role -> @+children:+List<Interface.Node> ->
      @found:{Interface.find_node(Interface.active_nodes(UI.observe(capacity, state)), key) ==
        Some{Interface.Node{node_key, semantic, label, role, Interface.Activate{input, View.Available{}}, children}} : Maybe<&2, Interface.Node>} ->
      {receipt(UI.step(UI.Element{capacity, key, Interface.Press{}}, state)) == receipt(Core.step(input, state)) : Receipt},
    existing_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+rest:+List<E.Layer> ->
      @present:{Interface.layer_present(previous, E.panel_target(panel)) == True{} : Bool} ->
      {Interface.record_layer(E.Layer{panel, trigger, initial_attention, query} <> rest, previous, origin) ==
        E.Layer{panel, trigger, initial_attention, query} <> rest : +List<E.Layer>},
    new_layer_trigger: @+previous:+List<E.Layer> -> @origin:String -> @+panel:U.Panel -> @trigger:String ->
      @initial_attention:String -> @query:String -> @+rest:+List<E.Layer> ->
      @absent:{Interface.layer_present(previous, E.panel_target(panel)) == False{} : Bool} ->
      {Interface.record_layer(E.Layer{panel, trigger, initial_attention, query} <> rest, previous, origin) ==
        E.Layer{panel, origin, initial_attention, query} <> rest : +List<E.Layer>}}

law evidence:
  Requirements
