import Base
import ../document/presentation-order.bend as Order
import ../CONTRACT.bend as Interaction
import ./SEMANTICS.bend as Browser
import ../MODEL.bend as Web
import ../focus/MODEL.bend as Focus
import ../document/RENDERED.bend as Rendered
import ./PLATFORM.bend as Platform
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../harness/MODEL.bend as M
import ../../interaction/MODEL.bend as Product
import ../../interaction/session/MODEL.bend as E
import ../../bendlib/json.bend as J
import ../../interaction/presentation/CONTRACT.bend as Rules_interface_program_rules

def sequence(+state: Browser.State) -> Nat:
  +sequence = Browser.sequence(state)
  sequence

# Admission reserves its ticket and carries the original completion exactly once.

def pending(decision: Browser.Decision) -> +List<Browser.Pending>:
  Browser.Decision{+observed_state_1, effects} = decision
  +requests = Browser.pending(observed_state_1)
  requests

def web_state(decision: Browser.Decision) -> Web.State:
  Browser.Decision{+observed_state_1, effects} = decision
  +web = Browser.web(observed_state_1)
  web

def document_state(+state: Browser.State) -> Browser.State:
  +web = Browser.web(state)
  +application = Web.application(web)
  +platform = Platform.platform(application)
  Browser.with_receipt(None{}, Browser.with_web(Web.with_application(
    Platform.with_platform(Platform.with_scope(Focus.Document{}, platform), application), web), state))

def document_key_event_law(-key: String, -shift: Bool, -state: Browser.State) -> Type:
  {Browser.key_event(key, shift, document_state(state)) ==
    Browser.KeyResult{False{}, Browser.Decision{document_state(state), Nil{}}} : Browser.KeyResult}

def transport(decision: Browser.Decision) -> (Nat & (Nat & +List<Browser.Pending>)):
  Browser.Decision{+observed_state_1, effects} = decision
  +sequence = Browser.sequence(observed_state_1)
  +next = Browser.next_ticket(observed_state_1)
  +pending = Browser.pending(observed_state_1)
  (sequence, (next, pending))

type Requirements is Type:
  Requirements{
    measurements_transport: @+model_state:Browser.State ->  @+observation: F.Observation -> {transport(Browser.measurements(observation, Browser.with_receipt(None{}, model_state))) ==
    (Browser.sequence(model_state), (Browser.next_ticket(model_state), Browser.pending(model_state))) : (Nat & (Nat & +List<Browser.Pending>))},
    finish_unchanged_transport: @web: Web.State -> @core: Core.State -> @effects: +List<Web.Effect> -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> @origin: String -> {transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    receipt_input: @observation: F.Observation -> @state: Browser.State -> {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision},
    nodes_current_surface: @+model_state:Browser.State ->  {Browser.nodes(Browser.with_receipt(None{}, model_state)) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(Browser.web(model_state))), Browser.pending(model_state)))) : +List<InterfaceView.Node>},
    interface_bridge: Rules_interface_program_rules.InterfaceRequirements,
    dismissal_allowed: @+input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(True{}, input, state) ==
        Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    dismissal_refused: @input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(False{}, input, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    document_key_event: @+key:String -> @+shift:Bool -> @+state:Browser.State ->
      document_key_event_law(key, shift, state),
    failed_transition: @+model_state:Browser.State ->  @ticket:Nat -> @error:String -> {Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, error), model_state)), Nil{}} : Browser.Decision},
    document_key: @tab:Bool -> @escape:Bool -> @shift:Bool -> @realization:Rendered.State -> @state:Browser.State ->
      {Browser.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    failed_preserves_web: @+model_state:Browser.State ->  @ticket:Nat -> @error:String -> {web_state(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))) == Browser.web(model_state) : Web.State},
    failed_retains_ticket: @+model_state:Browser.State ->  @ticket:Nat -> @error:String -> @observed:Nat ->
      {Browser.owns_ticket(pending(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))), observed) ==
        Browser.owns_ticket(Browser.pending(model_state), observed) : Bool},
    consumed_ticket: @+pending:+List<Browser.Pending> -> @+ticket:Nat ->
      {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Browser.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    admitted_request: @+model_state:Browser.State ->  @command:J.Json -> @completion:E.Completion -> @origin:String ->
      {Browser.request_ready(False{}, command, completion, origin, Browser.with_receipt(None{}, model_state)) ==
          Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(List.append(&2, Browser.Pending, Browser.pending(model_state), [Browser.Pending{Browser.next_ticket(model_state), completion, command, origin, Browser.AwaitingReceipt{}}]), Browser.with_next_ticket((Browser.next_ticket(model_state) + 1n : Nat), model_state))),
            [Browser.Command{Browser.next_ticket(model_state), command}]} : Browser.Decision},
    stale_completion: @+model_state:Browser.State ->  @ticket:Nat -> @received:Nat -> @supplied:M.World() -> @reply:J.Json ->
      @completion:E.Completion -> {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.with_receipt(None{}, model_state)), reply, completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state))) : Browser.Decision}}
law evidence:
  Requirements
