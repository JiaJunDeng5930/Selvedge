import ../../bendlib/equality-proof.bend as Equal
import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/association-map.bend as Finite
import ./MODEL.bend as Model
import ./connection-contract.bend as Rule

def retry_outcome(ready: Bool, request: Model.UploadRetry, state: Model.State) -> Model.Decision:
  match ready:
    case False{}: Model.Decision{state, Nil{}}
    case True{}:
      Model.UploadRetry{ticket, editor, file, original} = request
      Model.State{access, settings, appearance, next, transfers, preview, picker, +speech} = original
      Model.upload_calculation(editor, file, Model.State{access, settings, appearance, next,
        Finite.remove(~Model.Transfer, transfers, ticket), preview, picker, speech})

def retry_checked(ready: Bool, +request: Model.UploadRetry, +state: Model.State,
  observed: {Model.retry_connected(request) == ready : Bool}) ->
  {Model.retry_admitted(Categories.admit_checked(Model.UploadRetry, Model.retry_connected, request, ready, observed), state) ==
    retry_outcome(ready, request, state) : Model.Decision}:
  match ready:
    case False{}: {==}
    case True{}:
      Model.UploadRetry{ticket, editor, file, original} = request
      Model.State{access, settings, appearance, next, transfers, preview, picker, +speech} = original
      {==}

def rejected_retry(+request: Model.UploadRetry, +state: Model.State, rejected: {Model.retry_connected(request) == False{} : Bool}) ->
  {Model.retry_admitted(Categories.admit(Model.UploadRetry, Model.retry_connected, request), state) == Model.Decision{state, Nil{}} : Model.Decision}:
  Equal.trans(Model.Decision,
    Model.retry_admitted(Categories.admit(Model.UploadRetry, Model.retry_connected, request), state),
    retry_outcome(Model.retry_connected(request), request, state), Model.Decision{state, Nil{}},
    retry_checked(Model.retry_connected(request), request, state, {==}),
    Equal.cong(Bool, Model.Decision, ready => retry_outcome(ready, request, state),
      Model.retry_connected(request), False{}, rejected))

def Rule.offline_upload_retry_preserves_state(state, found, ticket, offline):
  match found:
    case None{}: {==}
    case Some{Model.Uploading{editor, file}}: {==}
    case Some{Model.UploadFailed{editor, file, reason}}:
      rejected_retry(Model.UploadRetry{ticket, editor, file, state}, state, offline)

def Rule.production_upload_retry_dispatch(state, ticket):
  Model.State{access, settings, appearance, next, transfers, preview, picker, +speech} = state
  {==}

def accepted_retry(+request: Model.UploadRetry, +state: Model.State, connected: {Model.retry_connected(request) == True{} : Bool}) ->
  {Model.retry_admitted(Categories.admit(Model.UploadRetry, Model.retry_connected, request), state) ==
    retry_outcome(True{}, request, state) : Model.Decision}:
  Equal.trans(Model.Decision,
    Model.retry_admitted(Categories.admit(Model.UploadRetry, Model.retry_connected, request), state),
    retry_outcome(Model.retry_connected(request), request, state), retry_outcome(True{}, request, state),
    retry_checked(Model.retry_connected(request), request, state, {==}),
    Equal.cong(Bool, Model.Decision, ready => retry_outcome(ready, request, state),
      Model.retry_connected(request), True{}, connected))

def Rule.connected_failed_upload_retries(ticket, editor, file, reason, access, settings, appearance, next, transfers, preview, picker, speech, connected, found):
  +state: Model.State = Model.State{access, settings, appearance, next, transfers, preview, picker, speech}
  Equal.trans(Model.Decision,
    Model.step(Model.RetryUpload{ticket}, state),
    Model.retry(Some{Model.UploadFailed{editor, file, reason}}, ticket, state),
    retry_outcome(True{}, Model.UploadRetry{ticket, editor, file, state}, state),
    Equal.cong(Maybe<&2, Model.Transfer>, Model.Decision,
      observed => Model.retry(observed, ticket, state), Finite.find(~Model.Transfer, transfers, ticket), Some{Model.UploadFailed{editor, file, reason}}, found),
    accepted_retry(Model.UploadRetry{ticket, editor, file, state}, state, connected))

def Rule.admitted_upload_retry_replaces_atomically(ticket, editor, file, access, settings, appearance, next, transfers, preview, picker, speech, evidence):
  {==}

def Rule.stale_disconnect_preserves_state(state, ticket, reason, stale):
  Model.State{+access, settings, appearance, next, transfers, preview, picker, +speech} = state
  Equal.cong(Bool, Model.Decision,
    owned => Model.connection_lost(owned, ticket, reason, Model.State{access, settings, appearance, next, transfers, preview, picker, speech}),
    Model.live_connection(access, ticket), False{}, stale)

def Rule.lost_connection_schedules_owned_recovery(access, ticket, reason, settings, appearance, next, transfers, preview, picker, speech, owned):
  Equal.cong(Bool, Model.Decision,
    current => Model.connection_lost(current, ticket, reason, Model.State{access, settings, appearance, next, transfers, preview, picker, speech}),
    Model.live_connection(access, ticket), True{}, owned)

def Rule.stale_reconnect_preserves_state(state, ticket, stale):
  Model.State{+access, settings, appearance, next, transfers, preview, picker, +speech} = state
  Equal.cong(Bool, Model.Decision,
    owned => Model.reconnect(owned, Model.State{access, settings, appearance, next, transfers, preview, picker, speech}),
    Model.waiting_reconnect(access, ticket), False{}, stale)

def Rule.recovery_starts_fresh_attempt(access, ticket, settings, appearance, next, transfers, preview, picker, speech, owned):
  Equal.cong(Bool, Model.Decision,
    current => Model.reconnect(current, Model.State{access, settings, appearance, next, transfers, preview, picker, speech}),
    Model.waiting_reconnect(access, ticket), True{}, owned)
def Rule.appearance_restore_is_observation(access, settings, old, next, transfers, preview, picker, speech, stored): {==}
def Rule.stored_dark_appearance(): {==}
def Rule.stored_light_appearance(): {==}
def Rule.absent_appearance_uses_system(): {==}
