import Base
import ../browser.bend as Browser
import ../browser-receipt-laws.bend as Rule
import ../../core/operation-receipt.bend as Receipt
import ../../core/user-experience.bend as E
import ../../core/user-input.bend as U
import ../../MODEL.bend as M
import ../../bendlib/domain.bend as D
import ../../bendlib/json.bend as J

def receipt_recorded(+receipt: Maybe<&2, Receipt.Receipt>, decision: Browser.Decision) ->
  {Browser.decision_receipt(Browser.receipt_decision(receipt, decision)) == receipt : Maybe<&2, Receipt.Receipt>}:
  match decision:
    case Browser.Decision{Browser.State{web, sequence, next, pending, previous}, effects}: {==}
def direct(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, state: Browser.State) ->
  Rule.direct_claim(ticket, received, world, code, message, command, origin, status, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.DirectCompletion{}, state))
def confirmation(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, selected: M.Command,
  trigger: String, destination: U.Route, occurrence: Nat, state: Browser.State) ->
  Rule.confirmation_claim(ticket, received, world, code, message, command, origin, status, selected, trigger, destination, occurrence, state):
  receipt_recorded(Some{Receipt.Receipt{ticket, origin, code, message}},
    Browser.complete_ticket(ticket, received, world, D.failure(code, message), E.ConfirmationCompletion{selected, trigger, destination, occurrence}, state))
def unknown_receipt(ticket: Nat, reason: String, +state: Browser.State) ->
  {Browser.decision_receipt(Browser.failed_completion(ticket, reason, state)) == Browser.operation_receipt(state) : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def accepted_receipt(command: J.Json, completion: E.Completion, origin: String, state: Browser.State) ->
  {Browser.decision_receipt(Browser.request_ready(False{}, command, completion, origin, state)) == None{} : Maybe<&2, Receipt.Receipt>}:
  match state:
    case Browser.State{web, sequence, next, pending, receipt}: {==}

def Rule.evidence():
  Rule.Requirements{direct, confirmation,
    received => world => reply => +state => {==},
    draft => receipt => +decision => {==},
    ticket => reason => +state => unknown_receipt(ticket, reason, state),
    command => completion => origin => +state => {==},
    command => completion => origin => state => accepted_receipt(command, completion, origin, state)}
