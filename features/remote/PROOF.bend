import Base
import ./MODEL.bend as R
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./CONTRACT.bend as Contract
import ../../bendlib/json.bend as J

def grant_space(+available: Bool, +controller: String, +rights: R.Rights, +state: R.State) ->
  {Actual.grant_capacity_checked(available, controller, rights, state) == Spec.grant_space(available, controller, rights, state) : R.Change}:
  match available state:
    case False{} _: {==}
    case True{} R.State{enabled, grants, next, receipts}: {==}

def grant_identity(+valid: Bool, +controller: String, +rights: R.Rights, +state: R.State) ->
  {Actual.grant_checked(valid, controller, rights, state) == Spec.grant_identity(valid, controller, rights, state) : R.Change}:
  match valid:
    case False{}: {==}
    case True{}: grant_space(R.grant_capacity(controller, state), controller, rights, state)

def administration(+command: R.Admin, +state: R.State) ->
  {Actual.admin(command, state) == Spec.admin(command, state) : R.Change}:
  match command state:
    case R.Enable{} R.State{enabled, grants, next, receipts}: {==}
    case R.Disable{} R.State{enabled, grants, next, receipts}: {==}
    case R.GrantDevice{controller, rights} _: grant_identity(R.identifier_valid(controller), controller, rights, state)
    case R.RevokeDevice{controller} R.State{enabled, grants, next, receipts}: {==}
    case R.Status{} _: {==}

def permission(+allowed: Bool) -> {Actual.check_permission(allowed) == Spec.permitted(allowed) : R.Authorization}:
  match allowed:
    case True{}: {==}
    case False{}: {==}

def generation(+current: Bool, +required: R.Rights, +rights: R.Rights) ->
  {Actual.check_epoch(current, required, rights) == Spec.generation(current, required, rights) : R.Authorization}:
  match current:
    case False{}: {==}
    case True{}: permission(R.rights_allow(required, rights))

def ownership(+found: Maybe<&2, R.Grant>, +required: R.Rights, +epoch: Nat) ->
  {Actual.check_grant(found, required, epoch) == Spec.ownership(found, required, epoch) : R.Authorization}:
  match found:
    case None{}: {==}
    case Some{R.Grant{id, current, rights}}: generation(Nat.is_eq(current, epoch), required, rights)

def identified(+valid: Bool, +required: R.Rights, +controller: String, +epoch: Nat, +state: R.State) ->
  {Actual.check_identity(valid, required, controller, epoch, state) == Spec.identified(valid, required, controller, epoch, state) : R.Authorization}:
  match valid:
    case False{}: {==}
    case True{}: ownership(R.find_grant(R.grants(state), controller), required, epoch)

def access_power(+enabled: Bool, +required: R.Rights, +controller: String, +epoch: Nat, +state: R.State) ->
  {Actual.check_enabled(enabled, required, controller, epoch, state) == Spec.access_power(enabled, required, controller, epoch, state) : R.Authorization}:
  match enabled:
    case False{}: {==}
    case True{}: identified(R.identifier_valid(controller) && Nat.is_gt(epoch, 0n), required, controller, epoch, state)

def access(+required: R.Rights, +controller: String, +epoch: Nat, +state: R.State) ->
  {Actual.check(required, controller, epoch, state) == Spec.check(required, controller, epoch, state) : R.Authorization}:
  access_power(R.enabled(state), required, controller, epoch, state)

def new_request(+available: Bool) -> {Actual.fresh(available) == Spec.new_request(available) : R.Authorization}:
  match available:
    case False{}: {==}
    case True{}: {==}

def prior_intent(+same: Bool, +reply: J.Json) -> {Actual.replay(same, reply) == Spec.prior_intent(same, reply) : R.Authorization}:
  match same:
    case False{}: {==}
    case True{}: {==}

def prior_request(+found: Maybe<&2, R.Receipt>, +intent: J.Json, +available: Bool) ->
  {Actual.deduplicate(found, intent, available) == Spec.prior_request(found, intent, available) : R.Authorization}:
  match found:
    case None{}: new_request(available)
    case Some{R.Receipt{controller, epoch, key, stored, reply}}: prior_intent(J.same(intent, stored), reply)

def request_permissions(+allowed: Bool, +request: R.Request, +state: R.State) ->
  {Actual.permission_checked(allowed, request, state) == Spec.request_permissions(allowed, request, state) : R.Authorization}:
  match allowed:
    case False{}: {==}
    case True{}: prior_request(R.find_receipt(R.receipts(state), request), R.request_intent(request), R.receipt_capacity(state))

def request_generation(+current: Bool, +required: R.Rights, +rights: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.epoch_checked(current, required, rights, request, state) == Spec.request_generation(current, required, rights, request, state) : R.Authorization}:
  match current:
    case False{}: {==}
    case True{}: request_permissions(R.rights_allow(required, rights), request, state)

def request_ownership(+found: Maybe<&2, R.Grant>, +required: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.grant_checked_access(found, required, request, state) == Spec.request_ownership(found, required, request, state) : R.Authorization}:
  match found:
    case None{}: {==}
    case Some{R.Grant{controller, epoch, rights}}: request_generation(Nat.is_eq(epoch, R.request_epoch(request)), required, rights, request, state)

def request_identity(+valid: Bool, +required: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.request_checked(valid, required, request, state) == Spec.request_identity(valid, required, request, state) : R.Authorization}:
  match valid:
    case False{}: {==}
    case True{}: request_ownership(R.find_grant(R.grants(state), R.request_controller(request)), required, request, state)

def request_power(+enabled: Bool, +required: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.enabled_checked(enabled, required, request, state) == Spec.request_power(enabled, required, request, state) : R.Authorization}:
  match enabled:
    case False{}: {==}
    case True{}: request_identity(R.request_valid(request), required, request, state)

def authorization(+required: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.authorize(required, request, state) == Spec.authorize(required, request, state) : R.Authorization}:
  request_power(R.enabled(state), required, request, state)

def retained(+admitted: R.Authorization, +request: R.Request, +reply: J.Json, +state: R.State) ->
  {Actual.retain(admitted, request, reply, state) == Spec.receipt(admitted, request, reply, state) : R.State}:
  match admitted request state:
    case R.Admitted{} R.Request{controller, epoch, key, intent} R.State{enabled, grants, next, receipts}: {==}
    case R.Denied{code, reason} _ _: {==}
    case R.Replay{previous} _ _: {==}

def bounded_receipt(+valid: Bool, +request: R.Request, +reply: J.Json, +state: R.State) ->
  {Actual.remember_checked(valid, request, reply, state) == Spec.bounded_receipt(valid, request, reply, state) : R.State}:
  match valid:
    case False{}: {==}
    case True{}:
      +actual = Actual.authorize(R.Rights{False{}, False{}, False{}, False{}}, request, state)
      +specified = Spec.authorize(R.Rights{False{}, False{}, False{}, False{}}, request, state)
      Equal.trans(R.State, Actual.retain(actual, request, reply, state), Spec.receipt(actual, request, reply, state),
        Spec.receipt(specified, request, reply, state), retained(actual, request, reply, state),
        Equal.cong(R.Authorization, R.State, value => Spec.receipt(value, request, reply, state), actual, specified,
          authorization(R.Rights{False{}, False{}, False{}, False{}}, request, state)))

def receipt(+request: R.Request, +reply: J.Json, +state: R.State) ->
  {Actual.remember(request, reply, state) == Spec.remember(request, reply, state) : R.State}:
  bounded_receipt(R.payload_valid(reply), request, reply, state)

def retained_authority(+admitted: R.Authorization, +request: R.Request, reply: J.Json, +state: R.State) ->
  {Contract.authority(Actual.retain(admitted, request, reply, state)) == Contract.authority(state) : Bool & (+List<R.Grant> & Nat)}:
  match admitted request state:
    case R.Admitted{} R.Request{controller, epoch, key, intent} R.State{enabled, grants, next, receipts}: {==}
    case R.Denied{code, reason} _ _: {==}
    case R.Replay{previous} _ _: {==}

def bounded_authority(+valid: Bool, +request: R.Request, reply: J.Json, +state: R.State) ->
  {Contract.authority(Actual.remember_checked(valid, request, reply, state)) == Contract.authority(state) : Bool & (+List<R.Grant> & Nat)}:
  match valid:
    case False{}: {==}
    case True{}: retained_authority(Actual.authorize(R.Rights{False{}, False{}, False{}, False{}}, request, state), request, reply, state)

def receipt_authority(+request: R.Request, +reply: J.Json, +state: R.State) ->
  {Contract.authority(Actual.remember(request, reply, state)) == Contract.authority(state) : Bool & (+List<R.Grant> & Nat)}:
  bounded_authority(R.payload_valid(reply), request, reply, state)

def disabled(+required: R.Rights, +request: R.Request, +state: R.State) ->
  {Actual.authorize(required, request, R.with_enabled(False{}, state)) ==
    R.Denied{"remote_disabled", "Remote control is disabled on this host"} : R.Authorization}:
  R.State{enabled, grants, next, receipts} = state
  {==}

def status_read(+state: R.State) -> {R.result_state(Actual.admin(R.Status{}, state)) == state : R.State}:
  {==}

def issued_generation(+controller: String, +rights: R.Rights, +state: R.State) ->
  {R.next_epoch(R.result_state(Actual.granted(controller, rights, state))) == 1n+R.next_epoch(state) : Nat}:
  R.State{enabled, grants, next, receipts} = state
  {==}

def revoked_generation(+controller: String, +state: R.State) ->
  {R.next_epoch(R.result_state(Actual.revoked(controller, state))) == R.next_epoch(state) : Nat}:
  R.State{enabled, grants, next, receipts} = state
  {==}

def Contract.boundary():
  Contract.Boundary{administration, access, authorization, receipt, receipt_authority, disabled, status_read,
    issued_generation, revoked_generation}
