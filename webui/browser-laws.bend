import Base
import ./presentation-order.bend as Order
import ./laws.bend as Interaction
import ./browser.bend as Browser
import ./MODEL.bend as Web
import ./focus.bend as Focus
import ./rendered.bend as Rendered
import ./platform.bend as Platform
import ./design.bend as Design
import ./font-observation.bend as F
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../MODEL.bend as M
import ../UI.bend as Product
import ../core/user-experience.bend as E
import ../bendlib/json.bend as J
import ../core/interface-program-rules.bend as Rules_interface_program_rules

def sequence(state: Browser.State) -> Nat:
  Browser.State{web, sequence, next, pending, receipt} = state
  sequence

# Admission reserves its ticket and carries the original completion exactly once.

def pending(decision: Browser.Decision) -> +List<Browser.Pending>:
  Browser.Decision{Browser.State{web, sequence, next, requests, receipt}, effects} = decision
  requests

def web_state(decision: Browser.Decision) -> Web.State:
  Browser.Decision{Browser.State{web, sequence, next, requests, receipt}, effects} = decision
  web

def document_state(core: Core.State, platform: Platform.Platform, generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State,
  sequence: Nat, next: Nat, requests: +List<Browser.Pending>) -> Browser.State:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, Focus.Document{}}},
    generation, realization, environment, font}, sequence, next, requests, None{}}

def document_key_event_law(-key: String, -shift: Bool, -core: Core.State, -platform: Platform.Platform, -generation: Nat, -realization: Rendered.State, -environment: Design.Environment, -font: F.State, -sequence: Nat, -next: Nat, -requests: +List<Browser.Pending>) -> Type:
  {Browser.key_event(key, shift, document_state(core, platform, generation, realization, environment, font, sequence, next, requests)) ==
      Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, font, sequence, next, requests), Nil{}}} : Browser.KeyResult}

def transport(decision: Browser.Decision) -> (Nat & (Nat & +List<Browser.Pending>)):
  Browser.Decision{Browser.State{web, sequence, next, pending, receipt}, effects} = decision
  (sequence, (next, pending))

type Requirements is Type:
  Requirements{
    measurements_transport: @+observation: F.Observation -> @+web: Web.State -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> {transport(Browser.measurements(observation, Browser.State{web, sequence, next, pending, None{}})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    finish_unchanged_transport: @web: Web.State -> @core: Core.State -> @effects: +List<Web.Effect> -> @sequence: Nat -> @next: Nat -> @pending: +List<Browser.Pending> -> @origin: String -> {transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))},
    receipt_input: @observation: F.Observation -> @state: Browser.State -> {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision},
    nodes_current_surface: @+web:Web.State -> @sequence:Nat -> @next:Nat -> @+pending:+List<Browser.Pending> ->
      {Browser.nodes(Browser.State{web, sequence, next, pending, None{}}) == UI.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(web)), pending))) : +List<UI.Node>},
    interface_bridge: Rules_interface_program_rules.InterfaceRequirements,
    dismissal_allowed: @+input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(True{}, input, state) ==
        Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    dismissal_refused: @input:Core.Input -> @+state:Browser.State ->
      {Browser.dismiss_permitted(False{}, input, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    document_key_event: @+key:String -> @+shift:Bool -> @+core:Core.State -> @+platform:Platform.Platform -> @+generation:Nat ->
      @+realization:Rendered.State -> @+environment:Design.Environment -> @+font:F.State -> @+sequence:Nat -> @+next:Nat -> @+requests:+List<Browser.Pending> ->
      document_key_event_law(key, shift, core, platform, generation, realization, environment, font, sequence, next, requests),
    failed_transition: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests, None{}}) ==
        Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(requests, ticket, error), None{}}, Nil{}} : Browser.Decision},
    document_key: @tab:Bool -> @escape:Bool -> @shift:Bool -> @realization:Rendered.State -> @state:Browser.State ->
      {Browser.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    failed_preserves_web: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {web_state(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests, None{}})) == web : Web.State},
    failed_retains_ticket: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> -> @observed:Nat ->
      {Browser.owns_ticket(pending(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests, None{}})), observed) ==
        Browser.owns_ticket(requests, observed) : Bool},
    consumed_ticket: @+pending:+List<Browser.Pending> -> @+ticket:Nat ->
      {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Browser.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    admitted_request: @command:J.Json -> @completion:E.Completion -> @origin:String ->
      @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.request_ready(False{}, command, completion, origin, Browser.State{web, sequence, next, pending, None{}}) ==
          Browser.Decision{Browser.State{web, sequence, (next + 1n : Nat),
            List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin, Browser.AwaitingReceipt{}}]), None{}},
            [Browser.Command{next, command}]} : Browser.Decision},
    stale_completion: @ticket:Nat -> @received:Nat -> @supplied:M.World() -> @reply:J.Json ->
      @completion:E.Completion -> @web:Web.State -> @current:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.State{web, current, next, pending, None{}}) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.State{web, current, next, pending, None{}}), reply, completion},
            Browser.State{web, current, next, Browser.remove(pending, ticket), None{}}) : Browser.Decision}}

law evidence:
  Requirements
