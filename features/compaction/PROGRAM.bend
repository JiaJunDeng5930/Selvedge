import Base
import ./MODEL.bend as A
import ./STATE.bend as State
import ./SPEC.bend as Spec
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/features/MODEL.bend as F
import ../../harness/tasks/PROGRAM.bend as T
import ../../bendlib/component.bend as C
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J

# The implementation consumes the resolved writes; it does not reinterpret the
# observations or decide whether a partial model reply completed an operation.
type EventRequest is Data:
  EventRequest{completion: A.Completion, world: M.World()}

def allocate(+reserve: Bool, +world: M.World()) -> M.World():
  match reserve:
    case False{}: world
    case True{}: State.reserve_ticket(world)

def update_task(+task: Maybe<&2, D.Task>, +world: M.World()) -> M.World():
  match task:
    case None{}: world
    case Some{+task}: T.update_world(F.State(), task, world)

def realize_calculation(+change: Spec.Change, +world: M.World()) -> M.Decision():
  match change:
    case Spec.Unchanged{}: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case Spec.Change{+state, +task, +reserve, +effects}:
      C.Decision{update_task(task, allocate(reserve, State.store(state, world))),
        D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), State.effects(effects)}

def resolve(request: EventRequest) -> Spec.Change:
  EventRequest{+completion, +world} = request
  Spec.resolve(completion, world)

def ConstructedEvent() -> Type:
  Categories.Membership<Categories.Construction<EventRequest, Spec.Change>, Categories.constructed_by(EventRequest, Spec.Change, resolve)>

def construct_event(+completion: A.Completion, +world: M.World()) -> ConstructedEvent():
  Categories.construct(EventRequest, Spec.Change, resolve, EventRequest{completion, world})

def event(member: ConstructedEvent()) -> M.Decision():
  Categories.Membership{Categories.Construction{EventRequest{+completion, +world}, +change}, evidence} = member
  realize_calculation(change, world)

def complete(+completion: A.Completion, +world: M.World()) -> M.Decision():
  event(construct_event(completion, world))

def synchronize(+tasks: +List<D.Task>, +decision: M.Decision()) -> M.Decision():
  match tasks:
    case Nil{}: decision
    case Con{+task, +rest}:
      +decision = Spec.combine(decision, realize_calculation(Spec.synchronize(task, Spec.decision_world(decision)), Spec.decision_world(decision)))
      synchronize(rest, decision)

def prepare(+decision: M.Decision()) -> M.Decision():
  +decision = synchronize(State.tasks(Spec.decision_world(decision)), decision)
  Spec.combine(decision, realize_calculation(Spec.arm(State.registry(Spec.decision_world(decision))), Spec.decision_world(decision)))

def manual(+task: D.Task, +world: M.World()) -> M.Decision():
  realize_calculation(Spec.manual(task, world), world)

def supplied(+summary: String, +task: D.Task, +world: M.World()) -> M.Decision():
  realize_calculation(Spec.supplied(summary, task, world), world)

def cancel(+task: D.Task, +world: M.World()) -> M.Decision():
  realize_calculation(Spec.cancel(task, world), world)
