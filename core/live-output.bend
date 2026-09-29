import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../bendlib/domain.bend as D
import ../bendlib/tasks.bend as Tasks
import ../bendlib/association-map.bend as Finite

type Part is Data:
  Part{index: Nat, text: String}

type Output is Data:
  Output{task: Nat, operation: Nat, parts: +List<Part>}

type Observation is Data:
  PartialOutput{output: Output}
  DiscardOutput{task: Nat, operation: Nat}
  ConnectionEnded{}

def operation_exists(found: Maybe<&2, D.OperationBody>) -> Bool:
  match found:
    case Some{body}: True{}
    case None{}: False{}

def task_owns(found: Maybe<&2, D.Task>, operation: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: operation_exists(Finite.find(~D.OperationBody, D.task_operations(task), operation))

def active(output: Output, world: M.World()) -> Bool:
  Output{task, operation, parts} = output
  task_owns(Tasks.find(Commands.entries(world), task), operation)

def keep(allowed: Bool, output: Output, rest: +List<Output>) -> +List<Output>:
  match allowed:
    case True{}: output <> rest
    case False{}: rest

def remove(outputs: +List<Output>, +task: Nat, +operation: Nat) -> +List<Output>:
  match outputs:
    case Nil{}: Nil{}
    case Con{Output{+current, +ticket, parts}, rest}:
      keep(Bool.not(Nat.is_eq(current, task) && Nat.is_eq(ticket, operation)), Output{current, ticket, parts}, remove(rest, task, operation))

def observe(observation: Observation, outputs: +List<Output>, world: M.World()) -> +List<Output>:
  match observation:
    case PartialOutput{Output{+task, +operation, +parts}}:
      keep(active(Output{task, operation, parts}, world), Output{task, operation, parts}, remove(outputs, task, operation))
    case DiscardOutput{+task, +operation}: remove(outputs, task, operation)
    case ConnectionEnded{}: Nil{}

def retained(outputs: +List<Output>, +world: M.World()) -> +List<Output>:
  match outputs:
    case Nil{}: Nil{}
    case Con{+output, rest}: keep(active(output, world), output, retained(rest, world))

def for_task(outputs: +List<Output>, +task: Nat) -> +List<Output>:
  match outputs:
    case Nil{}: Nil{}
    case Con{Output{+current, operation, parts}, rest}:
      keep(Nat.is_eq(current, task), Output{current, operation, parts}, for_task(rest, task))
