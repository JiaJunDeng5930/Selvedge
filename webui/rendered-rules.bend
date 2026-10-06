import Base
import ../core/interface.bend as UI
import ./rendered.bend as Model

law stale_frame_retains_state:
  for +current: Nat
  for +received: Nat
  for +surface: UI.Surface
  for +frame: Model.Frame
  for +previous: Model.State
  for different: {Nat.is_eq(current, received) == False{} : Bool}
  {Model.observe(current, received, surface, frame, previous) == previous : Model.State}


law native_ownership_is_complete:
  for +identity: String
  for owner: String
  for +rest: +List<Model.NativeFocus>
  for +active: +List<UI.Node>
  for +elements: +List<Model.Element>
  {Model.native_valid(Model.NativeFocus{identity, owner} <> rest, active, elements) ==
    (Model.read_only(UI.find_node(active, owner)) && Bool.not(Model.exists(UI.find_node(active, identity))) &&
     Model.native_element(Model.find_element(elements, identity)) && Bool.not(Model.native_member(rest, identity)) && Model.native_valid(rest, active, elements)) : Bool}

law native_order_is_owned:
  for +owner: String
  for +identity: String
  for +parent: String
  for rest: +List<Model.NativeFocus>
  {Model.owner_tabs(Model.NativeFocus{identity, parent} <> rest, owner) ==
    Model.tab_entry(String.eq(parent, owner), identity, Model.owner_tabs(rest, owner)) : +List<String>}

law native_tab_contract:
  for +active: +List<UI.Node>
  for +elements: +List<Model.Element>
  for +native_focus: +List<Model.NativeFocus>
  for order: +List<String>
  {Model.tabs_valid(active, elements, native_focus, order) ==
    (Model.native_valid(native_focus, active, elements) && Model.same_order(Model.expected_tabs(active, elements, native_focus), order)) : Bool}
