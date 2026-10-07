import Base
import ./SEMANTICS.bend as Browser
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../interaction/submission/MODEL.bend as Receipt

def direct_claim(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, state: Browser.State) -> Type:
  {Browser.decision_receipt(Browser.completed(Some{Browser.Pending{ticket, E.DirectCompletion{}, command, origin, status}},
    received, world, D.failure(code, message), state)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>}
def confirmation_claim(+ticket: Nat, received: Nat, world: M.World(), +code: String, +message: String,
  command: J.Json, +origin: String, status: Browser.RequestStatus, selected: M.Command,
  trigger: String, destination: U.Route, occurrence: Nat, state: Browser.State) -> Type:
  {Browser.decision_receipt(Browser.completed(Some{Browser.Pending{ticket, E.ConfirmationCompletion{selected, trigger, destination, occurrence}, command, origin, status}},
    received, world, D.failure(code, message), state)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>}

type Requirements is Type:
  Requirements{
    direct: @+ticket:Nat -> @received:Nat -> @world:M.World() -> @+code:String -> @+message:String ->
      @command:J.Json -> @+origin:String -> @status:Browser.RequestStatus -> @state:Browser.State ->
      direct_claim(ticket, received, world, code, message, command, origin, status, state),
    confirmation: @+ticket:Nat -> @received:Nat -> @world:M.World() -> @+code:String -> @+message:String ->
      @command:J.Json -> @+origin:String -> @status:Browser.RequestStatus -> @selected:M.Command -> @trigger:String -> @destination:U.Route -> @occurrence:Nat -> @state:Browser.State ->
      confirmation_claim(ticket, received, world, code, message, command, origin, status, selected, trigger, destination, occurrence, state),
    stale: @received:Nat -> @world:M.World() -> @reply:J.Json -> @+state:Browser.State ->
      {Browser.completed(None{}, received, world, reply, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    draft: @draft:U.Draft -> @receipt:Maybe<&2, Receipt.Receipt> -> @+decision:Browser.Decision ->
      {Browser.completion_receipt(E.DraftCompletion{draft}, receipt, decision) == decision : Browser.Decision},
    unknown: @ticket:Nat -> @reason:String -> @+state:Browser.State ->
      {Browser.decision_receipt(Browser.failed_completion(ticket, reason, state)) == Browser.operation_receipt(state) : Maybe<&2, Receipt.Receipt>},
    duplicate: @command:J.Json -> @completion:E.Completion -> @origin:String -> @+state:Browser.State ->
      {Browser.request_ready(True{}, command, completion, origin, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    accepted: @command:J.Json -> @completion:E.Completion -> @origin:String -> @state:Browser.State ->
      {Browser.decision_receipt(Browser.request_ready(False{}, command, completion, origin, state)) == None{} : Maybe<&2, Receipt.Receipt>}}

law evidence:
  Requirements
