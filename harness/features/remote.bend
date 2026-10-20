import Base
import ../../features/remote/MODEL.bend as R
import ../../features/remote/PROGRAM.bend as Remote
import ./MODEL.bend as F
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J

# Remote authority belongs to the environment's native state. The connector
# supplies an authenticated controller identity; bearer secrets never enter here.
def registry(world: M.World()) -> R.State:
  F.remote(C.rest(D.State, F.State(), world))

def store(state: R.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_remote(state, features), world)

def embed(change: R.Change, world: M.World()) -> M.Decision():
  R.Change{state, reply} = change
  C.Decision{store(state, world), reply, Nil{}}

def selected_settings(value: J.Json) -> Bool:
  match value:
    case J.Null{}: False{}
    case J.Object{Nil{}}: False{}
    case _: True{}

# Every remotely reachable public operation has an explicit permission. Local
# pairing, grants and tunnel administration have no remote permission mapping.
type NamedPermissionName is Data:
  NamedPermissionNameRead{}
  NamedPermissionNameCreate{}
  NamedPermissionNameCreateIdle{}
  NamedPermissionNameCreateWorktreeTask{}
  NamedPermissionNameRetryWorktreeArchive{}
  NamedPermissionNameReviewApproval{}
  NamedPermissionNameConfigureTaskExecution{}
  NamedPermissionNameOther{}

def named_permission_discriminant(+value: String) -> NamedPermissionName:
  Bool.pick(NamedPermissionName, String.eq(value, "read"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "describe"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list_projects"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list_worktrees"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "read_worktree"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "read_project"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list_cards"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "read_card"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list_board_agents"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "list_task_graphs"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "read_task_graph"), NamedPermissionNameRead{},
    Bool.pick(NamedPermissionName, String.eq(value, "create_idle"), NamedPermissionNameCreateIdle{},
    Bool.pick(NamedPermissionName, String.eq(value, "create"), NamedPermissionNameCreate{},
    Bool.pick(NamedPermissionName, (String.eq(value, "create_worktree_task") || String.eq(value, "create_workspace_task")), NamedPermissionNameCreateWorktreeTask{},
    Bool.pick(NamedPermissionName, String.eq(value, "retry_worktree_archive"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "fork"), NamedPermissionNameCreate{},
    Bool.pick(NamedPermissionName, String.eq(value, "send"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "steer"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "cancel_operation"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "freeze"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "unfreeze"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "stop"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "interrupt"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "archive"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "compact"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "review_approval"), NamedPermissionNameReviewApproval{},
    Bool.pick(NamedPermissionName, String.eq(value, "configure_task_execution"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "create_project"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "update_project"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "delete_project"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "create_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "update_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "move_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "archive_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "restore_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "delete_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "run_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "link_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "regenerate_card_title"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "pin_card"), NamedPermissionNameRetryWorktreeArchive{},
    Bool.pick(NamedPermissionName, String.eq(value, "board_settings"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "save_board_agent"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "delete_board_agent"), NamedPermissionNameConfigureTaskExecution{},
    Bool.pick(NamedPermissionName, String.eq(value, "create_task_graph"), NamedPermissionNameCreateWorktreeTask{},
    Bool.pick(NamedPermissionName, String.eq(value, "update_task_graph"), NamedPermissionNameCreateWorktreeTask{},
    Bool.pick(NamedPermissionName, String.eq(value, "delete_task_graph"), NamedPermissionNameCreateWorktreeTask{},
    NamedPermissionNameOther{})))))))))))))))))))))))))))))))))))))))))))))))

def named_permission_classified(name: NamedPermissionName, +body: J.Json) -> Maybe<&2, R.Rights>:
  match name:
    case NamedPermissionNameRead{}: Some{R.Rights{True{}, False{}, False{}, False{}}}
    case NamedPermissionNameCreateIdle{}: Some{R.Rights{False{}, True{}, selected_settings(J.get(body, "settings")) || J.boolean(J.get(body, "create_worktree")), False{}}}
    case NamedPermissionNameCreate{}: Some{R.Rights{False{}, True{}, selected_settings(J.get(body, "settings")), False{}}}
    case NamedPermissionNameCreateWorktreeTask{}: Some{R.Rights{False{}, True{}, True{}, False{}}}
    case NamedPermissionNameRetryWorktreeArchive{}: Some{R.Rights{False{}, True{}, False{}, False{}}}
    case NamedPermissionNameReviewApproval{}: Some{R.Rights{False{}, False{}, False{}, True{}}}
    case NamedPermissionNameConfigureTaskExecution{}: Some{R.Rights{False{}, False{}, True{}, False{}}}
    case NamedPermissionNameOther{}: None{}

def named_permission(name: String, +body: J.Json) -> Maybe<&2, R.Rights>:
  named_permission_classified(named_permission_discriminant(name), body)

def permission(+body: J.Json) -> Maybe<&2, R.Rights>:
  named_permission(J.text(J.get(body, "op")), body)

def authorize_mapped(required: Maybe<&2, R.Rights>, request: R.Request, state: R.State) -> R.Authorization:
  match required:
    case None{}: R.Denied{"remote_command_forbidden", "Remote access cannot invoke this local management command"}
    case Some{rights}: Remote.authorize(rights, request, state)

def authorization(+request: R.Request, state: R.State) -> R.Authorization:
  R.Request{controller, epoch, id, +intent} = request
  authorize_mapped(permission(intent), request, state)

def query_mapped(required: Maybe<&2, R.Rights>, +request: R.Request, state: R.State) -> R.Authorization:
  match required:
    case None{}: R.Denied{"remote_command_forbidden", "Remote access cannot invoke this local management command"}
    case Some{rights}: Remote.check(rights, R.request_controller(request), R.request_epoch(request), state)

def query_authorization(+request: R.Request, state: R.State) -> R.Authorization:
  query_mapped(permission(R.request_intent(request)), request, state)

def probe_reply(authorization: R.Authorization, world: M.World()) -> M.Decision():
  match authorization:
    case R.Denied{code, reason}: C.Decision{world, D.failure(code, reason), Nil{}}
    case R.Admitted{}: C.Decision{world, D.success(J.Object{[J.Field{"admitted", J.Boolean{True{}}}]}), Nil{}}
    case R.Replay{reply}: C.Decision{world, D.success(J.Object{[J.Field{"replayed", J.Boolean{True{}}}, J.Field{"reply", reply}]}), Nil{}}

def probe_authorization(command: M.Command, +request: R.Request, state: R.State) -> R.Authorization:
  match command:
    case M.Observe{query}: query_authorization(request, state)
    case _: authorization(request, state)

def probe(command: M.Command, +request: R.Request, +world: M.World()) -> M.Decision():
  probe_reply(probe_authorization(command, request, registry(world)), world)

def check(controller: String, epoch: Nat, +world: M.World()) -> M.Decision():
  probe_reply(Remote.check(R.Rights{True{}, False{}, False{}, False{}}, controller, epoch, registry(world)), world)
