import Base
import ./MODEL.bend as R
import ../../bendlib/json.bend as J

def granted(+controller: String, rights: R.Rights, state: R.State) -> R.Change:
  R.State{enabled, +grants, +next, +receipts} = state
  +grant = {R.Grant{controller, next, rights}: R.Grant}
  R.Change{R.State{enabled, grant <> R.remove_grant(grants, controller), 1n+next, R.remove_receipts(receipts, controller)},
    R.success(R.grant_json(grant))}

def grant_capacity_checked(available: Bool, controller: String, rights: R.Rights, state: R.State) -> R.Change:
  match available:
    case True{}: granted(controller, rights, state)
    case False{}: R.Change{state, R.failure("remote_grants_full", "At most 64 controllers can be granted; revoke an existing controller first")}

def grant_checked(valid: Bool, +controller: String, rights: R.Rights, +state: R.State) -> R.Change:
  match valid:
    case True{}: grant_capacity_checked(R.grant_capacity(controller, state), controller, rights, state)
    case False{}: R.Change{state, R.failure("remote_invalid_controller", "Controller identity must contain 1 to 128 UTF-8 bytes")}

def revoked(+controller: String, state: R.State) -> R.Change:
  R.State{enabled, grants, next, receipts} = state
  R.Change{R.State{enabled, R.remove_grant(grants, controller), next, R.remove_receipts(receipts, controller)},
    R.success(J.Object{[J.Field{"controller_id", J.Text{controller}}, J.Field{"revoked", J.Boolean{True{}}}]})}

def admin(command: R.Admin, +state: R.State) -> R.Change:
  match command:
    case R.Enable{}: R.Change{R.with_enabled(True{}, state), R.success(R.status(R.with_enabled(True{}, state)))}
    case R.Disable{}: R.Change{R.with_enabled(False{}, state), R.success(R.status(R.with_enabled(False{}, state)))}
    case R.GrantDevice{+controller, rights}: grant_checked(R.identifier_valid(controller), controller, rights, state)
    case R.RevokeDevice{controller}: revoked(controller, state)
    case R.Status{}: R.Change{state, R.success(R.status(state))}

def fresh(available: Bool) -> R.Authorization:
  match available:
    case True{}: R.Admitted{}
    case False{}: R.Denied{"remote_receipts_full", "Retained command receipts are full; revoke or replace this device grant before issuing a new request"}

def replay(same: Bool, reply: J.Json) -> R.Authorization:
  match same:
    case True{}: R.Replay{reply}
    case False{}: R.Denied{"remote_request_conflict", "This request ID was already committed with different intent"}

def deduplicate(found: Maybe<&2, R.Receipt>, intent: J.Json, available: Bool) -> R.Authorization:
  match found:
    case None{}: fresh(available)
    case Some{R.Receipt{controller, epoch, key, stored, reply}}: replay(J.same_unordered(intent, stored), reply)

def permission_checked(allowed: Bool, +request: R.Request, +state: R.State) -> R.Authorization:
  match allowed:
    case False{}: R.Denied{"remote_permission_denied", "This device grant does not permit this operation"}
    case True{}: deduplicate(R.find_receipt(R.receipts(state), request), R.request_intent(request), R.receipt_capacity(state))

def epoch_checked(current: Bool, required: R.Rights, rights: R.Rights, request: R.Request, state: R.State) -> R.Authorization:
  match current:
    case False{}: R.Denied{"remote_grant_expired", "This device grant generation is no longer current"}
    case True{}: permission_checked(R.rights_allow(required, rights), request, state)

def grant_checked_access(found: Maybe<&2, R.Grant>, required: R.Rights, +request: R.Request, state: R.State) -> R.Authorization:
  match found:
    case None{}: R.Denied{"remote_controller_revoked", "This controller has no active local grant"}
    case Some{R.Grant{controller, epoch, rights}}: epoch_checked(Nat.is_eq(epoch, R.request_epoch(request)), required, rights, request, state)

def request_checked(valid: Bool, required: R.Rights, +request: R.Request, +state: R.State) -> R.Authorization:
  match valid:
    case False{}: R.Denied{"remote_invalid_request", "Remote request identity or intent exceeds the current protocol bounds"}
    case True{}: grant_checked_access(R.find_grant(R.grants(state), R.request_controller(request)), required, request, state)

def enabled_checked(enabled: Bool, required: R.Rights, +request: R.Request, state: R.State) -> R.Authorization:
  match enabled:
    case False{}: R.Denied{"remote_disabled", "Remote control is disabled on this host"}
    case True{}: request_checked(R.request_valid(request), required, request, state)

def authorize(required: R.Rights, request: R.Request, +state: R.State) -> R.Authorization:
  enabled_checked(R.enabled(state), required, request, state)

def check_permission(allowed: Bool) -> R.Authorization:
  match allowed:
    case False{}: R.Denied{"remote_permission_denied", "This device grant does not permit this operation"}
    case True{}: R.Admitted{}

def check_epoch(current: Bool, required: R.Rights, rights: R.Rights) -> R.Authorization:
  match current:
    case False{}: R.Denied{"remote_grant_expired", "This device grant generation is no longer current"}
    case True{}: check_permission(R.rights_allow(required, rights))

def check_grant(found: Maybe<&2, R.Grant>, required: R.Rights, epoch: Nat) -> R.Authorization:
  match found:
    case None{}: R.Denied{"remote_controller_revoked", "This controller has no active local grant"}
    case Some{R.Grant{controller, current, rights}}: check_epoch(Nat.is_eq(current, epoch), required, rights)

def check_identity(valid: Bool, required: R.Rights, controller: String, epoch: Nat, state: R.State) -> R.Authorization:
  match valid:
    case False{}: R.Denied{"remote_invalid_request", "Remote request identity or intent exceeds the current protocol bounds"}
    case True{}: check_grant(R.find_grant(R.grants(state), controller), required, epoch)

def check_enabled(enabled: Bool, required: R.Rights, +controller: String, +epoch: Nat, state: R.State) -> R.Authorization:
  match enabled:
    case False{}: R.Denied{"remote_disabled", "Remote control is disabled on this host"}
    case True{}: check_identity(R.identifier_valid(controller) && Nat.is_gt(epoch, 0n), required, controller, epoch, state)

def check(required: R.Rights, controller: String, epoch: Nat, +state: R.State) -> R.Authorization:
  check_enabled(R.enabled(state), required, controller, epoch, state)

def retain(authorization: R.Authorization, request: R.Request, reply: J.Json, +state: R.State) -> R.State:
  match authorization request:
    case R.Admitted{} R.Request{controller, epoch, key, intent}:
      R.with_receipts(R.Receipt{controller, epoch, key, intent, reply} <> R.receipts(state), state)
    case _ _: state

def remember_checked(valid: Bool, +request: R.Request, reply: J.Json, +state: R.State) -> R.State:
  match valid:
    case False{}: state
    case True{}: retain(authorize(R.Rights{False{}, False{}, False{}, False{}}, request, state), request, reply, state)

def remember(request: R.Request, +reply: J.Json, state: R.State) -> R.State:
  remember_checked(R.payload_valid(reply), request, reply, state)
