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
def named_permission(name: String, +body: J.Json) -> Maybe<&2, R.Rights>:
  match name:
    case "read": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "describe": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list_projects": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list_worktrees": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "read_worktree": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "read_project": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list_cards": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "read_card": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list_board_agents": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "list_task_graphs": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "read_task_graph": Some{R.Rights{True{}, False{}, False{}, False{}}}
    case "create": Some{R.Rights{False{}, True{}, selected_settings(J.get(body, "settings")), False{}}}
    case "create_worktree_task": Some{R.Rights{False{}, True{}, True{}, False{}}}
    case "retry_worktree_archive": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "fork": Some{R.Rights{False{}, True{}, selected_settings(J.get(body, "settings")), False{}}}
    case "send": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "steer": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "cancel_operation": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "freeze": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "unfreeze": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "stop": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "interrupt": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "archive": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "compact": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "review_approval": Some{R.Rights{False{}, False{}, False{}, True{}}}
    case "configure_task_execution": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "create_project": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "update_project": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "delete_project": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "create_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "update_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "move_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "archive_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "restore_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "delete_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "run_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "link_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "regenerate_card_title": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "pin_card": Some{R.Rights{False{}, True{}, False{}, False{}}}
    case "board_settings": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "save_board_agent": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "delete_board_agent": Some{R.Rights{False{}, False{}, True{}, False{}}}
    case "create_task_graph": Some{R.Rights{False{}, True{}, True{}, False{}}}
    case "update_task_graph": Some{R.Rights{False{}, True{}, True{}, False{}}}
    case "delete_task_graph": Some{R.Rights{False{}, True{}, True{}, False{}}}
    case _: None{}

def permission(+body: J.Json) -> Maybe<&2, R.Rights>:
  named_permission(J.text(J.get(body, "op")), body)

def combine(left: R.Rights, right: R.Rights) -> R.Rights:
  match left right:
    case R.Rights{read_a, control_a, configure_a, approve_a} R.Rights{read_b, control_b, configure_b, approve_b}:
      R.Rights{read_a || read_b, control_a || control_b, configure_a || configure_b, approve_a || approve_b}

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
