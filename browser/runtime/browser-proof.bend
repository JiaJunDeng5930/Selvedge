import ../../interaction/session/MODEL.bend as E
import ../../interaction/MODEL.bend as Product
import ../../bendlib/json.bend as J
import Base
import ./SEMANTICS.bend as Browser
import ../MODEL.bend as Web
import ../CONTRACT.bend as Interaction
import ../document/RENDERED.bend as Rendered
import ./PLATFORM.bend as Platform
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../../interaction/STATE.bend as Core
import ../../harness/MODEL.bend as M
import ./browser-laws.bend as Rule
import ../PROOF.bend as Proof_laws
import ../../interaction/presentation/program-rules.bend as Rules_interface_program_rules

import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../document/presentation-order.bend as Order

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

def stale_snapshot(+received: Nat, +world: M.World(), +state: Browser.State,
  stale: {Nat.is_lt(Rule.sequence(state), received) == False{} : Bool}) ->
  {Browser.snapshot(received, world, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Browser.State{web, current, next, pending, receipt} = state
  Equal.cong(Bool, Browser.Decision,
    (newer => Browser.snapshot_new(newer, received, world, Browser.State{web, current, next, pending, receipt})),
    Nat.is_lt(current, received), False{}, stale)

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

def document_key_event(+key: String, +shift: Bool, +state: Browser.State) -> Rule.document_key_event_law(key, shift, state):
  Browser.State{Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}, sequence, next, requests, receipt} = state
  {==}

def receipt_input(observation: F.Observation, state: Browser.State) ->
  {Browser.measurements(observation, state) == Browser.step(Browser.Native{Web.TypographyObserved{observation}}, state) : Browser.Decision}:
  {==}

def finish_unchanged_transport(web: Web.State, core: Core.State, effects: +List<Web.Effect>, sequence: Nat,
  next: Nat, pending: +List<Browser.Pending>, origin: String) ->
  {Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})) ==
    (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  match core:
    case Core.State{application, services}: {==}

def finished_receipt_transport(decision: Web.Decision, +core: Core.State,
  unchanged: {Web.product(decision) == Platform.unchanged(core) : Core.Decision},
  +sequence: Nat, +next: Nat, +pending: +List<Browser.Pending>, +origin: String) ->
  {Rule.transport(Browser.finish(decision, sequence, next, pending, origin, None{})) == (sequence, (next, pending)) : (Nat & (Nat & +List<Browser.Pending>))}:
  Web.Decision{+web, +product, +effects} = decision
  Equal.trans((Nat & (Nat & +List<Browser.Pending>)),
    Rule.transport(Browser.finish(Web.Decision{web, product, effects}, sequence, next, pending, origin, None{})),
    Rule.transport(Browser.finish(Web.Decision{web, Platform.unchanged(core), effects}, sequence, next, pending, origin, None{})),
    (sequence, (next, pending)),
    Equal.cong(Core.Decision, (Nat & (Nat & +List<Browser.Pending>)),
      (current => Rule.transport(Browser.finish(Web.Decision{web, current, effects}, sequence, next, pending, origin, None{}))),
      product, Platform.unchanged(core), unchanged),
    finish_unchanged_transport(web, core, effects, sequence, next, pending, origin))

def nodes_current_surface(+web: Web.State, sequence: Nat, next: Nat, +pending: +List<Browser.Pending>) ->
  {Browser.nodes(Browser.State{web, sequence, next, pending, None{}}) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(web)), pending))) : +List<InterfaceView.Node>}:
  match web:
    case Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}: {==}

def state_measurements_transport_evidence(+model_state: Browser.State, +observation: F.Observation) ->
  {Rule.transport(Browser.measurements(observation, Browser.with_receipt(None{}, model_state))) ==
    (Browser.sequence(model_state), (Browser.next_ticket(model_state), Browser.pending(model_state))) : (Nat & (Nat & +List<Browser.Pending>))}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  finished_receipt_transport(Web.step(Web.TypographyObserved{observation}, web),
    Interaction.model_core(Interaction.model_application(web)), Proof_laws.typography_product(web, observation), sequence, next, pending, "")

def state_nodes_current_surface_evidence(+model_state: Browser.State) ->
  {Browser.nodes(Browser.with_receipt(None{}, model_state)) == InterfaceView.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(Browser.web(model_state))), Browser.pending(model_state)))) : +List<InterfaceView.Node>}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  nodes_current_surface(web, sequence, next, pending)

def state_failed_transition_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, error), model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_preserves_web_evidence(+model_state: Browser.State, ticket: Nat, error: String) ->
  {Rule.web_state(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))) == Browser.web(model_state) : Web.State}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  {==}

def state_failed_retains_ticket_evidence(+model_state: Browser.State, ticket: Nat, error: String, observed: Nat) ->
  {Browser.owns_ticket(Rule.pending(Browser.step(Browser.Failed{ticket, error}, Browser.with_receipt(None{}, model_state))), observed) ==
        Browser.owns_ticket(Browser.pending(model_state), observed) : Bool}:
  Browser.State{+web, +sequence, +next, +requests, +original_1} = model_state
  uncertain_retains_tickets(requests, ticket, error, observed)

def state_admitted_request_evidence(+model_state: Browser.State, command: J.Json, completion: E.Completion, origin: String) ->
  {Browser.request_ready(False{}, command, completion, origin, Browser.with_receipt(None{}, model_state)) ==
          Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(List.append(&2, Browser.Pending, Browser.pending(model_state), [Browser.Pending{Browser.next_ticket(model_state), completion, command, origin, Browser.AwaitingReceipt{}}]), Browser.with_next_ticket((Browser.next_ticket(model_state) + 1n : Nat), model_state))),
            [Browser.Command{Browser.next_ticket(model_state), command}]} : Browser.Decision}:
  Browser.State{+web, +sequence, +next, +pending, +original_1} = model_state
  {==}

def state_stale_completion_evidence(+model_state: Browser.State, ticket: Nat, received: Nat, supplied: M.World(), reply: J.Json, completion: E.Completion) ->
  {Browser.complete_new(False{}, ticket, received, supplied, reply, completion,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.product_input(Product.CommandCompleted{
            Browser.program(Browser.with_receipt(None{}, model_state)), reply, completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state))) : Browser.Decision}:
  Browser.State{+web, +current, +next, +pending, +original_1} = model_state
  {==}

def Rule.evidence():
  Rule.Requirements{
    state_measurements_transport_evidence,
    finish_unchanged_transport,
    receipt_input,
    state_nodes_current_surface_evidence,
    Rules_interface_program_rules.interface_evidence(),
    +input => +state => {==},
    input => +state => {==},
    document_key_event,
    state_failed_transition_evidence,
    tab => escape => shift => realization => state => {==},
    state_failed_preserves_web_evidence,
    state_failed_retains_ticket_evidence,
    consumed_ticket,
    stale_snapshot,
    state_admitted_request_evidence,
    state_stale_completion_evidence}
