import Base
import ../../bendlib/json.bend as J
import ../../bendlib/string-equality.bend as Text

type Rights is Data:
  Rights{read: Bool, control: Bool, configure: Bool, approve: Bool}

type Grant is Data:
  Grant{controller_id: String, epoch: Nat, rights: Rights}

type Receipt is Data:
  Receipt{controller_id: String, epoch: Nat, request_id: String, intent: J.Json, reply: J.Json}

type State is Data:
  State{enabled: Bool, grants: +List<Grant>, next_epoch: Nat, receipts: +List<Receipt>}

type Request is Data:
  Request{controller_id: String, grant_epoch: Nat, request_id: String, intent: J.Json}

type Admin is Data:
  Enable{}
  Disable{}
  GrantDevice{controller_id: String, rights: Rights}
  RevokeDevice{controller_id: String}
  Status{}

type Change is Data:
  Change{state: State, reply: J.Json}

type Authorization is Data:
  Denied{code: String, reason: String}
  Admitted{}
  Replay{reply: J.Json}

def initial() -> State:
  State{False{}, Nil{}, 1n, Nil{}}

def enabled(state: State) -> Bool:
  State{enabled, grants, next_epoch, receipts} = state
  enabled

def grants(state: State) -> +List<Grant>:
  State{enabled, grants, next_epoch, receipts} = state
  grants

def next_epoch(state: State) -> Nat:
  State{enabled, grants, next_epoch, receipts} = state
  next_epoch

def receipts(state: State) -> +List<Receipt>:
  State{enabled, grants, next_epoch, receipts} = state
  receipts

def result_state(change: Change) -> State:
  Change{state, reply} = change
  state

def result_reply(change: Change) -> J.Json:
  Change{state, reply} = change
  reply

def with_enabled(value: Bool, state: State) -> State:
  State{enabled, grants, next_epoch, receipts} = state
  State{value, grants, next_epoch, receipts}

def with_receipts(value: +List<Receipt>, state: State) -> State:
  State{enabled, grants, next_epoch, receipts} = state
  State{enabled, grants, next_epoch, value}

def select_grant(same: Bool, grant: Grant, fallback: Maybe<&2, Grant>) -> Maybe<&2, Grant>:
  match same:
    case True{}: Some{grant}
    case False{}: fallback

def find_grant(entries: +List<Grant>, +controller: String) -> Maybe<&2, Grant>:
  match entries:
    case Nil{}: None{}
    case Con{Grant{+id, epoch, rights}, rest}:
      select_grant(Text.string_equal(id, controller), Grant{id, epoch, rights}, find_grant(rest, controller))

def retained_grant(same: Bool, grant: Grant, rest: +List<Grant>) -> +List<Grant>:
  match same:
    case True{}: rest
    case False{}: grant <> rest

def remove_grant(entries: +List<Grant>, +controller: String) -> +List<Grant>:
  match entries:
    case Nil{}: Nil{}
    case Con{Grant{+id, epoch, rights}, rest}:
      retained_grant(Text.string_equal(id, controller), Grant{id, epoch, rights}, remove_grant(rest, controller))

def retained_receipt(same: Bool, receipt: Receipt, rest: +List<Receipt>) -> +List<Receipt>:
  match same:
    case True{}: rest
    case False{}: receipt <> rest

def remove_receipts(entries: +List<Receipt>, +controller: String) -> +List<Receipt>:
  match entries:
    case Nil{}: Nil{}
    case Con{Receipt{+id, epoch, request, intent, reply}, rest}:
      retained_receipt(Text.string_equal(id, controller), Receipt{id, epoch, request, intent, reply}, remove_receipts(rest, controller))

def request_controller(request: Request) -> String:
  Request{controller, epoch, key, intent} = request
  controller

def request_epoch(request: Request) -> Nat:
  Request{controller, epoch, key, intent} = request
  epoch

def request_key(request: Request) -> String:
  Request{controller, epoch, key, intent} = request
  key

def request_intent(request: Request) -> J.Json:
  Request{controller, epoch, key, intent} = request
  intent

def same_key(+request: Request, receipt: Receipt) -> Bool:
  Receipt{id, epoch, key, intent, reply} = receipt
  Text.string_equal(request_controller(request), id) &&
    Nat.is_eq(request_epoch(request), epoch) && Text.string_equal(request_key(request), key)

def select_receipt(same: Bool, receipt: Receipt, fallback: Maybe<&2, Receipt>) -> Maybe<&2, Receipt>:
  match same:
    case True{}: Some{receipt}
    case False{}: fallback

def find_receipt(entries: +List<Receipt>, +request: Request) -> Maybe<&2, Receipt>:
  match entries:
    case Nil{}: None{}
    case Con{+receipt, rest}:
      select_receipt(same_key(request, receipt), receipt, find_receipt(rest, request))

def receipt_count(entries: +List<Receipt>) -> Nat:
  match entries:
    case Nil{}: 0n
    case Con{receipt, rest}: 1n+receipt_count(rest)

def grant_count(entries: +List<Grant>) -> Nat:
  match entries:
    case Nil{}: 0n
    case Con{grant, rest}: 1n+grant_count(rest)

def grant_present(found: Maybe<&2, Grant>) -> Bool:
  match found:
    case None{}: False{}
    case Some{grant}: True{}

def grant_capacity(controller: String, +state: State) -> Bool:
  grant_present(find_grant(grants(state), controller)) || Nat.is_lt(grant_count(grants(state)), 64n)

def identifier_valid(+text: String) -> Bool:
  Bool.not(Text.string_equal(text, "")) && Nat.is_le(J.utf8_length(text), 128n)

def rendered_valid(value: Result<&2, &2, String, String>) -> Bool:
  match value:
    case Fail{reason}: False{}
    case Done{text}: Nat.is_le(J.utf8_length(text), 65536n)

def intent_valid(value: J.Json) -> Bool:
  rendered_valid(J.show(value))

def payload_valid(value: J.Json) -> Bool:
  intent_valid(value)

def request_valid(request: Request) -> Bool:
  Request{controller, epoch, key, intent} = request
  identifier_valid(controller) && Nat.is_gt(epoch, 0n) && identifier_valid(key) && intent_valid(intent)

def allows(required: Bool, granted: Bool) -> Bool:
  Bool.not(required) || granted

def rights_allow(required: Rights, granted: Rights) -> Bool:
  Rights{read, control, configure, approve} = required
  Rights{can_read, can_control, can_configure, can_approve} = granted
  allows(read, can_read) && allows(control, can_control) &&
    allows(configure, can_configure) && allows(approve, can_approve)

def receipt_capacity(state: State) -> Bool:
  Nat.is_lt(receipt_count(receipts(state)), 1024n)

def success(value: J.Json) -> J.Json:
  J.Object{[J.Field{"ok", J.Boolean{True{}}}, J.Field{"result", value}]}

def failure(code: String, reason: String) -> J.Json:
  J.Object{[J.Field{"ok", J.Boolean{False{}}}, J.Field{"error", J.Object{[
    J.Field{"code", J.Text{code}}, J.Field{"message", J.Text{reason}}]}}]}

def rights_json(value: Rights) -> J.Json:
  Rights{read, control, configure, approve} = value
  J.Object{[J.Field{"read", J.Boolean{read}}, J.Field{"control", J.Boolean{control}},
    J.Field{"configure", J.Boolean{configure}}, J.Field{"approve", J.Boolean{approve}}]}

def grant_json(value: Grant) -> J.Json:
  Grant{controller, epoch, rights} = value
  J.Object{[J.Field{"controller_id", J.Text{controller}}, J.Field{"grant_epoch", J.nat(epoch)},
    J.Field{"permissions", rights_json(rights)}]}

def grants_json(values: +List<Grant>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: grant_json(value) <> grants_json(rest)

def status(+state: State) -> J.Json:
  J.Object{[J.Field{"enabled", J.Boolean{enabled(state)}}, J.Field{"grants", J.Array{grants_json(grants(state))}},
    J.Field{"receipt_count", J.nat(receipt_count(receipts(state)))}, J.Field{"receipt_limit", J.nat(1024n)}]}

def grant_valid(grant: Grant, +next: Nat) -> Bool:
  Grant{id, +epoch, rights} = grant
  identifier_valid(id) && Nat.is_gt(epoch, 0n) && Nat.is_lt(epoch, next)

def grant_absent(found: Maybe<&2, Grant>) -> Bool:
  match found:
    case None{}: True{}
    case Some{grant}: False{}

def grants_valid(entries: +List<Grant>, +next: Nat) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{+grant, +rest}:
      Grant{+id, epoch, rights} = grant
      grant_absent(find_grant(rest, id)) && grant_valid(grant, next) && grants_valid(rest, next)

def receipt_granted(found: Maybe<&2, Grant>, epoch: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{Grant{id, current, rights}}: Nat.is_eq(epoch, current)

def receipt_absent(found: Maybe<&2, Receipt>) -> Bool:
  match found:
    case None{}: True{}
    case Some{receipt}: False{}

def receipts_valid(entries: +List<Receipt>, +granted: +List<Grant>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{Receipt{+controller, +epoch, +key, +intent, reply}, +rest}:
      +request = {Request{controller, epoch, key, intent}: Request}
      receipt_absent(find_receipt(rest, request)) && request_valid(request) && payload_valid(reply) &&
        receipt_granted(find_grant(granted, controller), epoch) && receipts_valid(rest, granted)

def valid(+state: State) -> Bool:
  Nat.is_gt(next_epoch(state), 0n) && Nat.is_le(grant_count(grants(state)), 64n) && grants_valid(grants(state), next_epoch(state)) &&
    Nat.is_le(receipt_count(receipts(state)), 1024n) && receipts_valid(receipts(state), grants(state))

def evolution(before: State, after: State) -> Bool:
  Nat.is_le(next_epoch(before), next_epoch(after))
