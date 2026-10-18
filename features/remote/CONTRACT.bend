import Base
import ./MODEL.bend as R
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ../../bendlib/json.bend as J

def authority(+state: R.State) -> Bool & (+List<R.Grant> & Nat):
  (R.enabled(state), (R.grants(state), R.next_epoch(state)))

type Boundary is Type:
  Boundary{
    administration: @+command:R.Admin -> @+state:R.State ->
      {Actual.admin(command, state) == Spec.admin(command, state) : R.Change},
    access: @+required:R.Rights -> @+controller:String -> @+epoch:Nat -> @+state:R.State ->
      {Actual.check(required, controller, epoch, state) == Spec.check(required, controller, epoch, state) : R.Authorization},
    authorization: @+required:R.Rights -> @+request:R.Request -> @+state:R.State ->
      {Actual.authorize(required, request, state) == Spec.authorize(required, request, state) : R.Authorization},
    receipt: @+request:R.Request -> @+reply:J.Json -> @+state:R.State ->
      {Actual.remember(request, reply, state) == Spec.remember(request, reply, state) : R.State},
    receipt_authority: @+request:R.Request -> @+reply:J.Json -> @+state:R.State ->
      {authority(Actual.remember(request, reply, state)) == authority(state) : Bool & (+List<R.Grant> & Nat)},
    disabled: @+required:R.Rights -> @+request:R.Request -> @+state:R.State ->
      {Actual.authorize(required, request, R.with_enabled(False{}, state)) ==
        R.Denied{"remote_disabled", "Remote control is disabled on this host"} : R.Authorization},
    status_read: @+state:R.State -> {R.result_state(Actual.admin(R.Status{}, state)) == state : R.State},
    issued_generation: @+controller:String -> @+rights:R.Rights -> @+state:R.State ->
      {R.next_epoch(R.result_state(Actual.granted(controller, rights, state))) == 1n+R.next_epoch(state) : Nat},
    revoked_generation: @+controller:String -> @+state:R.State ->
      {R.next_epoch(R.result_state(Actual.revoked(controller, state))) == R.next_epoch(state) : Nat}}

law boundary:
  Boundary
