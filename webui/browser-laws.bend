import Base
import ./browser.bend as Browser
import ./MODEL.bend as Web
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
      Browser.Pending{current, completion, command, origin} = entry
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
      List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin}])},
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

type Requirements is Type:
  Requirements{
    consumed_ticket: @+pending:+List<Browser.Pending> -> @+ticket:Nat ->
      {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    stale_snapshot: @+received:Nat -> @+world:M.World() -> @+state:Browser.State ->
      @stale:{Nat.is_lt(sequence(state), received) == False{} : Bool} ->
      {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    admitted_request: @command:J.Json -> @completion:E.Completion -> @origin:String ->
      @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.request_ready(False{}, command, completion, origin, Browser.State{web, sequence, next, pending}) ==
        Browser.Decision{Browser.State{web, sequence, (next + 1n : Nat),
          List.append(&2, Browser.Pending, pending, [Browser.Pending{next, completion, command, origin}])},
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
  Requirements{consumed_ticket, stale_snapshot, admitted_request, stale_completion_uses_current}
