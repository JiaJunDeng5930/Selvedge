import Base
import ../MODEL.bend as M
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ../UI.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/laws.bend as Laws
import ../core/interface.bend as Interface
import ../core/ui-world.bend as View
import ../core/user-input.bend as U
import ../core/user-experience.bend as E
import ../core/client-services.bend as Services

type Receipt is Data:
  Receipt{runtime: M.Decision(), services: Services.State,
    interaction: +List<E.Effect>, service_effects: +List<Services.Effect>, durable: Bool}

def receipt(+decision: Core.Decision) -> Receipt:
  Core.Decision{Core.State{application, services}, reply, runtime, interaction, service_effects, durable} = decision
  Receipt{Laws.runtime(decision), services, interaction, service_effects, durable}

def quiet_decision(+state: Core.State) -> Core.Decision:
  Core.State{application, services} = state
  Core.Decision{Core.State{application, services}, D.success(J.Null{}), Nil{}, Nil{}, Nil{}, False{}}

def absent_input_is_quiet(+state: Core.State) ->
  {Interface.apply_input(None{}, state) == quiet_decision(state) : Core.Decision}:
  Core.State{application, services} = state
  {==}

def resolve_absent(+surface: Interface.Surface, +key: String, +gesture: Interface.Gesture,
  absent: {Interface.find_node(Interface.active_nodes(surface), key) == None{} : Maybe<&2, Interface.Node>}) ->
  {Interface.resolve(surface, key, gesture) == None{} : Maybe<&2, Core.Input>}:
  Equal.cong(Maybe<&2, Interface.Node>, Maybe<&2, Core.Input>,
    source => Interface.resolve_source(source, gesture, surface),
    Interface.find_node(Interface.active_nodes(surface), key), None{}, absent)

def resolve_unavailable(+surface: Interface.Surface, +key: String, +input: Core.Input, +reason: String,
  +node_key: String, +semantic: String, +label: String, +role: Interface.Role,
  +children: +List<Interface.Node>,
  found: {Interface.find_node(Interface.active_nodes(surface), key) ==
    Some{Interface.Node{node_key, semantic, label, role, Interface.Activate{input, View.Unavailable{reason}}, children}} : Maybe<&2, Interface.Node>}) ->
  {Interface.resolve(surface, key, Interface.Press{}) == None{} : Maybe<&2, Core.Input>}:
  Equal.trans(Maybe<&2, Core.Input>,
    Interface.resolve(surface, key, Interface.Press{}),
    Interface.resolve_source(Some{Interface.Node{node_key, semantic, label, role,
      Interface.Activate{input, View.Unavailable{reason}}, children}}, Interface.Press{}, surface),
    None{},
    Equal.cong(Maybe<&2, Interface.Node>, Maybe<&2, Core.Input>,
      source => Interface.resolve_source(source, Interface.Press{}, surface),
      Interface.find_node(Interface.active_nodes(surface), key),
      Some{Interface.Node{node_key, semantic, label, role,
        Interface.Activate{input, View.Unavailable{reason}}, children}}, found),
    {==})

def resolve_available(+surface: Interface.Surface, +key: String, +input: Core.Input,
  +node_key: String, +semantic: String, +label: String, +role: Interface.Role,
  +children: +List<Interface.Node>,
  found: {Interface.find_node(Interface.active_nodes(surface), key) ==
    Some{Interface.Node{node_key, semantic, label, role, Interface.Activate{input, View.Available{}}, children}} : Maybe<&2, Interface.Node>}) ->
  {Interface.resolve(surface, key, Interface.Press{}) == Some{input} : Maybe<&2, Core.Input>}:
  Equal.trans(Maybe<&2, Core.Input>,
    Interface.resolve(surface, key, Interface.Press{}),
    Interface.resolve_source(Some{Interface.Node{node_key, semantic, label, role,
      Interface.Activate{input, View.Available{}}, children}}, Interface.Press{}, surface),
    Some{input},
    Equal.cong(Maybe<&2, Interface.Node>, Maybe<&2, Core.Input>,
      source => Interface.resolve_source(source, Interface.Press{}, surface),
      Interface.find_node(Interface.active_nodes(surface), key),
      Some{Interface.Node{node_key, semantic, label, role,
        Interface.Activate{input, View.Available{}}, children}}, found),
    {==})

def element_without_resolution(+capacity: View.Capacity, +state: Core.State, +key: String,
  +gesture: Interface.Gesture,
  unresolved: {Interface.resolve(UI.observe(capacity, state), key, gesture) == None{} : Maybe<&2, Core.Input>}) ->
  {UI.step(UI.Element{capacity, key, gesture}, state) == quiet_decision(state) : Core.Decision}:
  Equal.trans(Core.Decision,
    UI.step(UI.Element{capacity, key, gesture}, state),
    Interface.perform(capacity, state, key, None{}),
    quiet_decision(state),
    Equal.cong(Maybe<&2, Core.Input>, Core.Decision,
      input => Interface.perform(capacity, state, key, input),
      Interface.resolve(UI.observe(capacity, state), key, gesture), None{}, unresolved),
    Equal.trans(Core.Decision,
      Interface.perform(capacity, state, key, None{}),
      Interface.apply_input(None{}, state),
      quiet_decision(state),
      {==}, absent_input_is_quiet(state)))







def receipt_source(+decision: Core.Decision, previous: +List<E.Layer>, origin: String) ->
  {receipt(Interface.source_decision(decision, previous, origin)) == receipt(decision) : Receipt}:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_record_source(+before: Core.State, key: String, +decision: Core.Decision) ->
  {receipt(Interface.record_source(before, key, decision)) == receipt(decision) : Receipt}:
  Core.State{E.Application{program, E.Session{route, drafts, readers, +layers, attention,
    navigation, filter, now, next, pending, previews, code}}, services} = before
  receipt_source(decision, layers, Interface.origin(layers, key))

def receipt_navigation_closed(+decision: Core.Decision) ->
  {receipt(Interface.navigation_closed(decision)) == receipt(decision) : Receipt}:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_after_navigation(dismiss: Bool, +decision: Core.Decision) ->
  {receipt(Interface.after_navigation(dismiss, decision)) == receipt(decision) : Receipt}:
  match dismiss:
    case False{}: {==}
    case True{}: receipt_navigation_closed(decision)

def receipt_perform_present(+capacity: View.Capacity, +state: Core.State, +key: String,
  +input: Maybe<&2, Core.Input>) ->
  {receipt(Interface.perform_present(capacity, state, key, input)) == receipt(Interface.apply_input(input, state)) : Receipt}:
  View.Capacity{navigation_beside, details_beside} = capacity
  Equal.trans(Receipt,
    receipt(Interface.perform_present(capacity, state, key, input)),
    receipt(Interface.record_source(state, key, Interface.apply_input(input, state))),
    receipt(Interface.apply_input(input, state)),
    receipt_after_navigation(Bool.not(navigation_beside) && Interface.navigates(input),
      Interface.record_source(state, key, Interface.apply_input(input, state))),
    receipt_record_source(state, key, Interface.apply_input(input, state)))

def receipt_perform_input(+input: Maybe<&2, Core.Input>, +capacity: View.Capacity,
  +state: Core.State, +key: String) ->
  {receipt(Interface.perform_input(input, capacity, state, key)) == receipt(Interface.apply_input(input, state)) : Receipt}:
  match input:
    case None{}: {==}
    case Some{value}: receipt_perform_present(capacity, state, key, Some{value})

def receipt_perform(+capacity: View.Capacity, +state: Core.State, +key: String,
  +input: Maybe<&2, Core.Input>) ->
  {receipt(Interface.perform(capacity, state, key, input)) == receipt(Interface.apply_input(input, state)) : Receipt}:
  receipt_perform_input(input, capacity, state, key)

def element_receipt(+capacity: View.Capacity, +state: Core.State, +key: String,
  +gesture: Interface.Gesture) ->
  {receipt(UI.step(UI.Element{capacity, key, gesture}, state)) ==
    receipt(Interface.apply_input(Interface.resolve(UI.observe(capacity, state), key, gesture), state)) : Receipt}:
  receipt_perform(capacity, state, key, Interface.resolve(UI.observe(capacity, state), key, gesture))







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

def evidence() -> Requirements:
  Requirements{
    +capacity => +state => +key => +gesture => absent =>
      element_without_resolution(capacity, state, key, gesture,
        resolve_absent(UI.observe(capacity, state), key, gesture, absent))
    ,
    +capacity => +state => +key => +input => +reason => +node_key => +semantic => +label => +role => +children => found =>
      element_without_resolution(capacity, state, key, Interface.Press{},
        resolve_unavailable(UI.observe(capacity, state), key, input, reason, node_key, semantic, label, role, children, found))
    ,
    +capacity => +state => +editor => absent =>
      Equal.trans(Core.Decision,
        UI.step(UI.SubmitComposer{capacity, editor}, state),
        Interface.submit_found(None{}, capacity, state),
        quiet_decision(state),
        Equal.cong(Maybe<&2, Interface.Node>, Core.Decision,
          found => Interface.submit_found(found, capacity, state),
          Interface.submission(Interface.active_nodes(UI.observe(capacity, state)), editor), None{}, absent),
        absent_input_is_quiet(state))
    ,
    capacity => state => key => gesture => element_receipt(capacity, state, key, gesture),
    +capacity => +state => +key => +input => +node_key => +semantic => +label => +role => +children => found =>
      Equal.trans(Receipt,
        receipt(UI.step(UI.Element{capacity, key, Interface.Press{}}, state)),
        receipt(Interface.apply_input(Interface.resolve(UI.observe(capacity, state), key, Interface.Press{}), state)),
        receipt(Core.step(input, state)),
        element_receipt(capacity, state, key, Interface.Press{}),
        Equal.cong(Maybe<&2, Core.Input>, Receipt,
          resolved => receipt(Interface.apply_input(resolved, state)),
          Interface.resolve(UI.observe(capacity, state), key, Interface.Press{}), Some{input},
          resolve_available(UI.observe(capacity, state), key, input, node_key, semantic, label, role, children, found)))
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +rest => present =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Interface.layer_trigger(unchanged, trigger, origin), initial_attention, query} <> rest,
        Interface.layer_present(previous, E.panel_target(panel)), True{}, present)
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +rest => absent =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Interface.layer_trigger(unchanged, trigger, origin), initial_attention, query} <> rest,
        Interface.layer_present(previous, E.panel_target(panel)), False{}, absent)
    }
