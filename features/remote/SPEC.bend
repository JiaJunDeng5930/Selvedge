import Base
import ./MODEL.bend as R
import ../../bendlib/json.bend as J

# Complete meanings are independent of the production interpreter. Credentials,
# sockets and task execution are deliberately outside this state component.
def replacement(controller: String, rights: R.Rights, state: R.State) -> R.Change:
  R.State{enabled, grants, +epoch, receipts} = state
  +id = controller
  +grant = {R.Grant{id, epoch, rights}: R.Grant}
  R.Change{R.State{enabled, grant <> R.remove_grant(grants, id), 1n+epoch, R.remove_receipts(receipts, id)},
    R.success(R.grant_json(grant))}

def grant_space(available: Bool, controller: String, rights: R.Rights, state: R.State) -> R.Change:
  match available:
    case False{}: R.Change{state, R.failure("remote_grants_full", "At most 64 controllers can be granted; revoke an existing controller first")}
    case True{}: replacement(controller, rights, state)

def grant_identity(valid: Bool, +controller: String, rights: R.Rights, +state: R.State) -> R.Change:
  match valid:
    case False{}: R.Change{state, R.failure("remote_invalid_controller", "Controller identity must contain 1 to 128 UTF-8 bytes")}
    case True{}: grant_space(R.grant_capacity(controller, state), controller, rights, state)

def power(value: Bool, state: R.State) -> R.Change:
  R.State{previous, grants, next, receipts} = state
  +result = {R.State{value, grants, next, receipts}: R.State}
  R.Change{result, R.success(R.status(result))}

def revoke(+controller: String, state: R.State) -> R.Change:
  R.State{enabled, grants, next, receipts} = state
  R.Change{R.State{enabled, R.remove_grant(grants, controller), next, R.remove_receipts(receipts, controller)},
    R.success(J.Object{[J.Field{"controller_id", J.Text{controller}}, J.Field{"revoked", J.Boolean{True{}}}]})}

def admin(command: R.Admin, +state: R.State) -> R.Change:
  match command:
    case R.Enable{}: power(True{}, state)
    case R.Disable{}: power(False{}, state)
    case R.GrantDevice{+controller, rights}: grant_identity(R.identifier_valid(controller), controller, rights, state)
    case R.RevokeDevice{controller}: revoke(controller, state)
    case R.Status{}: R.Change{state, R.success(R.status(state))}

def permitted(allowed: Bool) -> R.Authorization:
  match allowed:
    case True{}: R.Admitted{}
    case False{}: R.Denied{"remote_permission_denied", "This device grant does not permit this operation"}

def generation(current: Bool, required: R.Rights, rights: R.Rights) -> R.Authorization:
  match current:
    case True{}: permitted(R.rights_allow(required, rights))
    case False{}: R.Denied{"remote_grant_expired", "This device grant generation is no longer current"}

def ownership(found: Maybe<&2, R.Grant>, required: R.Rights, epoch: Nat) -> R.Authorization:
  match found:
    case None{}: R.Denied{"remote_controller_revoked", "This controller has no active local grant"}
    case Some{R.Grant{id, current, rights}}: generation(Nat.is_eq(current, epoch), required, rights)

def identified(valid: Bool, required: R.Rights, controller: String, epoch: Nat, state: R.State) -> R.Authorization:
  match valid:
    case False{}: R.Denied{"remote_invalid_request", "Remote request identity or intent exceeds the current protocol bounds"}
    case True{}: ownership(R.find_grant(R.grants(state), controller), required, epoch)

def access_power(enabled: Bool, required: R.Rights, +controller: String, +epoch: Nat, state: R.State) -> R.Authorization:
  match enabled:
    case False{}: R.Denied{"remote_disabled", "Remote control is disabled on this host"}
    case True{}: identified(R.identifier_valid(controller) && Nat.is_gt(epoch, 0n), required, controller, epoch, state)

def check(required: R.Rights, controller: String, epoch: Nat, +state: R.State) -> R.Authorization:
  access_power(R.enabled(state), required, controller, epoch, state)

def new_request(available: Bool) -> R.Authorization:
  match available:
    case False{}: R.Denied{"remote_receipts_full", "Retained command receipts are full; revoke or replace this device grant before issuing a new request"}
    case True{}: R.Admitted{}

def prior_intent(same: Bool, reply: J.Json) -> R.Authorization:
  match same:
    case False{}: R.Denied{"remote_request_conflict", "This request ID was already committed with different intent"}
    case True{}: R.Replay{reply}

def prior_request(found: Maybe<&2, R.Receipt>, intent: J.Json, available: Bool) -> R.Authorization:
  match found:
    case None{}: new_request(available)
    case Some{R.Receipt{controller, epoch, key, stored, reply}}: prior_intent(J.same_unordered(intent, stored), reply)

def request_permissions(allowed: Bool, +request: R.Request, +state: R.State) -> R.Authorization:
  match allowed:
    case False{}: R.Denied{"remote_permission_denied", "This device grant does not permit this operation"}
    case True{}: prior_request(R.find_receipt(R.receipts(state), request), R.request_intent(request), R.receipt_capacity(state))

def request_generation(current: Bool, required: R.Rights, rights: R.Rights, request: R.Request, state: R.State) -> R.Authorization:
  match current:
    case False{}: R.Denied{"remote_grant_expired", "This device grant generation is no longer current"}
    case True{}: request_permissions(R.rights_allow(required, rights), request, state)

def request_ownership(found: Maybe<&2, R.Grant>, required: R.Rights, +request: R.Request, state: R.State) -> R.Authorization:
  match found:
    case None{}: R.Denied{"remote_controller_revoked", "This controller has no active local grant"}
    case Some{R.Grant{controller, epoch, rights}}:
      request_generation(Nat.is_eq(epoch, R.request_epoch(request)), required, rights, request, state)

def request_identity(valid: Bool, required: R.Rights, +request: R.Request, +state: R.State) -> R.Authorization:
  match valid:
    case False{}: R.Denied{"remote_invalid_request", "Remote request identity or intent exceeds the current protocol bounds"}
    case True{}: request_ownership(R.find_grant(R.grants(state), R.request_controller(request)), required, request, state)

def request_power(enabled: Bool, required: R.Rights, +request: R.Request, state: R.State) -> R.Authorization:
  match enabled:
    case False{}: R.Denied{"remote_disabled", "Remote control is disabled on this host"}
    case True{}: request_identity(R.request_valid(request), required, request, state)

def authorize(required: R.Rights, request: R.Request, +state: R.State) -> R.Authorization:
  request_power(R.enabled(state), required, request, state)

def receipt(authorization: R.Authorization, request: R.Request, reply: J.Json, state: R.State) -> R.State:
  match authorization request state:
    case R.Admitted{} R.Request{controller, epoch, key, intent} R.State{enabled, grants, next, receipts}:
      R.State{enabled, grants, next, R.Receipt{controller, epoch, key, intent, reply} <> receipts}
    case _ _ state: state

def bounded_receipt(valid: Bool, +request: R.Request, reply: J.Json, +state: R.State) -> R.State:
  match valid:
    case False{}: state
    case True{}: receipt(authorize(R.Rights{False{}, False{}, False{}, False{}}, request, state), request, reply, state)

def remember(request: R.Request, +reply: J.Json, state: R.State) -> R.State:
  bounded_receipt(R.payload_valid(reply), request, reply, state)
