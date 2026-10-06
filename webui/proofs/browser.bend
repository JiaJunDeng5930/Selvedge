import Base
import ../browser.bend as Browser
import ../MODEL.bend as Web
import ../laws.bend as Interaction
import ../rendered.bend as Rendered
import ../platform.bend as Platform
import ../design.bend as Design
import ../font-observation.bend as F
import ../../core/SYSTEM.bend as Core
import ../../MODEL.bend as M
import ../browser-laws.bend as Rule
import ./laws.bend as Proof_laws
import ../../core/interface-program-rules.bend as Rules_interface_program_rules

import ../../core/interface.bend as UI
import ../presentation-order.bend as Order

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

def document_key_event(+key: String, +shift: Bool, +core: Core.State, +platform: Platform.Platform, +generation: Nat,
  +realization: Rendered.State, +environment: Design.Environment, +font: F.State, +sequence: Nat, +next: Nat, +requests: +List<Browser.Pending>) -> Rule.document_key_event_law(key, shift, core, platform, generation, realization, environment, font, sequence, next, requests):
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
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
  {Browser.nodes(Browser.State{web, sequence, next, pending, None{}}) == UI.active_nodes(Order.ordered_surface(Browser.mask_surface(Web.surface(Interaction.model_application(web)), pending))) : +List<UI.Node>}:
  match web:
    case Web.State{Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}, generation, realization, environment, font}: {==}

def Rule.evidence():
  Rule.Requirements{
    +observation => +web => sequence => next => pending =>
      finished_receipt_transport(Web.step(Web.TypographyObserved{observation}, web),
        Interaction.model_core(Interaction.model_application(web)), Proof_laws.typography_product(web, observation), sequence, next, pending, ""),
    finish_unchanged_transport,
    receipt_input,
    +web => sequence => next => +pending => nodes_current_surface(web, sequence, next, pending),
    Rules_interface_program_rules.interface_evidence(),
    +input => +state => {==},
    input => +state => {==},
    document_key_event,
    ticket => error => web => sequence => next => requests => {==},
    tab => escape => shift => realization => state => {==},
    ticket => error => web => sequence => next => requests => {==},
    ticket => error => web => sequence => next => requests => observed => uncertain_retains_tickets(requests, ticket, error, observed),
    consumed_ticket,
    stale_snapshot,
    command => completion => origin => web => sequence => next => pending => {==},
    ticket => received => supplied => reply => completion => web => current => next => pending => {==}}
