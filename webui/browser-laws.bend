import Base
import ./browser.bend as Browser
import ./MODEL.bend as Web
import ./focus.bend as Focus
import ./rendered.bend as Rendered
import ./platform.bend as Platform
import ./design.bend as Design
import ../core/SYSTEM.bend as Core
import ../MODEL.bend as M
import ../UI.bend as Product
import ../core/user-experience.bend as E
import ../bendlib/json.bend as J

# Settlement removes every matching ticket, even from malformed duplicate input.
def removed_choice_absent(+same: Bool, +entry: Browser.Pending,
  +rest: +List<Browser.Pending>, +ticket: Nat,
  matching: {Nat.is_eq(Browser.ticket_of(entry), ticket) == same : Bool},
  absent: {Browser.owns_ticket(rest, ticket) == False{} : Bool}) ->
  {Browser.owns_ticket(Browser.choose_removed(same, entry, rest), ticket) == False{} : Bool}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(Bool,
        Browser.owns_ticket(entry <> rest, ticket),
        Browser.owned_choice(False{}, Browser.owns_ticket(rest, ticket)),
        False{},
        Equal.cong(Bool, Bool,
          (selected => Browser.owned_choice(selected, Browser.owns_ticket(rest, ticket))),
          Nat.is_eq(Browser.ticket_of(entry), ticket), False{}, matching), absent)

def consumed_ticket(+pending: +List<Browser.Pending>, +ticket: Nat) ->
  {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool}:
  match pending:
    case Nil{}: {==}
    case Con{+entry, rest}:
      Browser.Pending{current, completion, command, origin, status} = entry
      removed_choice_absent(Nat.is_eq(current, ticket), entry, Browser.remove(rest, ticket), ticket,
        {==}, consumed_ticket(rest, ticket))

# A stale snapshot never touches the program or any local interaction state.
def sequence(state: Browser.State) -> Nat:
  Browser.State{web, sequence, next, pending} = state
  sequence

# Admission reserves its ticket and carries the original completion exactly once.
def stale_snapshot(+received: Nat, +world: M.World(), +state: Browser.State,
  stale: {Nat.is_lt(sequence(state), received) == False{} : Bool}) ->
  {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Browser.State{web, current, next, pending} = state
  Equal.cong(Bool, Browser.Decision,
    (newer => Browser.snapshot_new(newer, received, world, Browser.State{web, current, next, pending})),
    Nat.is_lt(current, received), False{}, stale)
def admitted_request(command: J.Json, completion: E.Completion, origin: String,
  web: Web.State, sequence: Nat, next: Nat, pending: +List<Browser.Pending>) ->
  {Browser.request_ready(False{}, command, completion, origin, Browser.State{web, sequence, next, pending}) ==
    Browser.Decision{Browser.State{web, sequence, (next + 1n : Nat),
      List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin, Browser.AwaitingReceipt{}}])},
      [Browser.Command{next, command}]} : Browser.Decision}:
  {==}
def duplicate_retains_state(command: J.Json, completion: E.Completion, origin: String,
  state: Browser.State) ->
  {Browser.request_ready(True{}, command, completion, origin, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  {==}
def unmatched_completion(received: Nat, world: M.World(), reply: J.Json, state: Browser.State) ->
  {Browser.completed(None{}, received, world, reply, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  {==}

def stale_completion_uses_current(ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json,
  completion: E.Completion, web: Web.State, current: Nat, next: Nat,
  pending: +List<Browser.Pending>) ->
  {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
    Browser.State{web, current, next, pending}) ==
    Browser.product_input(Product.CommandCompleted{
      Browser.program(Browser.State{web, current, next, pending}), reply, completion},
      Browser.State{web, current, next, Browser.remove(pending, ticket)}) : Browser.Decision}:
  {==}

def failed_transition(ticket: Nat, error: String, web: Web.State, sequence: Nat, next: Nat, requests: +List<Browser.Pending>) ->
  {Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests}) ==
    Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(requests, ticket, error)}, Nil{}} : Browser.Decision}:
  {==}

def document_key(tab: Bool, escape: Bool, shift: Bool, realization: Rendered.State, state: Browser.State) ->
  {Browser.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  {==}

def pending(decision: Browser.Decision) -> +List<Browser.Pending>:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  requests

def web_state(decision: Browser.Decision) -> Web.State:
  Browser.Decision{Browser.State{web, sequence, next, requests}, effects} = decision
  web

def failed_preserves_web(ticket: Nat, error: String, web: Web.State, sequence: Nat, next: Nat, requests: +List<Browser.Pending>) ->
  {web_state(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})) == web : Web.State}:
  {==}

def uncertain_entry_ticket(hit: Bool, entry: Browser.Pending, reason: String) ->
  {Browser.ticket_of(Browser.mark_uncertain(hit, entry, reason)) == Browser.ticket_of(entry) : Nat}:
  match hit:
    case False{}: {==}
    case True{}:
      Browser.Pending{ticket, completion, command, origin, status} = entry
      {==}

def uncertain_retains_tickets(+requests: +List<Browser.Pending>, +ticket: Nat, +reason: String, +observed: Nat) ->
  {Browser.owns_ticket(Browser.uncertain_pending(requests, ticket, reason), observed) ==
    Browser.owns_ticket(requests, observed) : Bool}:
  match requests:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.trans(Bool,
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed)),
        Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), Browser.owns_ticket(rest, observed)),
        Equal.cong(Nat, Bool,
          (key => Browser.owned_choice(Nat.is_eq(key, observed), Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed))),
          Browser.ticket_of(Browser.mark_uncertain(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)), Browser.ticket_of(entry),
          uncertain_entry_ticket(Nat.is_eq(Browser.ticket_of(entry), ticket), entry, reason)),
        Equal.cong(Bool, Bool,
          (tail => Browser.owned_choice(Nat.is_eq(Browser.ticket_of(entry), observed), tail)),
          Browser.owns_ticket(Browser.uncertain_pending(rest, ticket, reason), observed), Browser.owns_ticket(rest, observed),
          uncertain_retains_tickets(rest, ticket, reason, observed)))

def failed_retains_ticket(ticket: Nat, error: String, web: Web.State, sequence: Nat, next: Nat, requests: +List<Browser.Pending>, observed: Nat) ->
  {Browser.owns_ticket(pending(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})), observed) ==
    Browser.owns_ticket(requests, observed) : Bool}:
  uncertain_retains_tickets(requests, ticket, error, observed)

def document_state(core: Core.State, platform: Platform.Platform, generation: Nat, realization: Rendered.State, environment: Design.Environment,
  sequence: Nat, next: Nat, requests: +List<Browser.Pending>) -> Browser.State:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, Focus.Document{}}},
    generation, realization, environment}, sequence, next, requests}

def document_key_event(+key: String, +shift: Bool, +core: Core.State, platform: Platform.Platform, +generation: Nat,
  +realization: Rendered.State, +environment: Design.Environment, +sequence: Nat, +next: Nat, +requests: +List<Browser.Pending>) ->
  {Browser.key_event(key, shift, document_state(core, platform, generation, realization, environment, sequence, next, requests)) ==
    Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, sequence, next, requests), Nil{}}} : Browser.KeyResult}:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  {==}

type Requirements is Type:
  Requirements{
    document_key_event: @+key:String -> @+shift:Bool -> @+core:Core.State -> @platform:Platform.Platform -> @+generation:Nat ->
      @+realization:Rendered.State -> @+environment:Design.Environment -> @+sequence:Nat -> @+next:Nat -> @+requests:+List<Browser.Pending> ->
      {Browser.key_event(key, shift, document_state(core, platform, generation, realization, environment, sequence, next, requests)) ==
        Browser.KeyResult{False{}, Browser.Decision{document_state(core, platform, generation, realization, environment, sequence, next, requests), Nil{}}} : Browser.KeyResult},
    failed_transition: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests}) ==
        Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(requests, ticket, error)}, Nil{}} : Browser.Decision},
    document_key: @tab:Bool -> @escape:Bool -> @shift:Bool -> @realization:Rendered.State -> @state:Browser.State ->
      {Browser.key_scoped(Focus.Document{}, tab, escape, shift, realization, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    failed_preserves_web: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> ->
      {web_state(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})) == web : Web.State},
    failed_retains_ticket: @ticket:Nat -> @error:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @requests:+List<Browser.Pending> -> @observed:Nat ->
      {Browser.owns_ticket(pending(Browser.step(Browser.Failed{ticket, error}, Browser.State{web, sequence, next, requests})), observed) ==
        Browser.owns_ticket(requests, observed) : Bool},
    consumed_ticket: @+pending:+List<Browser.Pending> -> @+ticket:Nat ->
      {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Browser.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    admitted_request: @command:J.Json -> @completion:E.Completion -> @origin:String ->
      @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.request_ready(False{}, command, completion, origin, Browser.State{web, sequence, next, pending}) ==
        Browser.Decision{Browser.State{web, sequence, (next + 1n : Nat),
          List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin, Browser.AwaitingReceipt{}}])},
          [Browser.Command{next, command}]} : Browser.Decision},
    stale_completion: @ticket:Nat -> @received:Nat -> @supplied:M.World() -> @reply:J.Json ->
      @completion:E.Completion -> @web:Web.State -> @current:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
        Browser.State{web, current, next, pending}) ==
        Browser.product_input(Product.CommandCompleted{
          Browser.program(Browser.State{web, current, next, pending}), reply, completion},
          Browser.State{web, current, next, Browser.remove(pending, ticket)}) : Browser.Decision}
  }
def evidence() -> Requirements:
  Requirements{document_key_event, failed_transition, document_key, failed_preserves_web, failed_retains_ticket, consumed_ticket, stale_snapshot, admitted_request, stale_completion_uses_current}
