import Base
import ../../bendlib/json.bend as J
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../bendlib/association-map.bend as Finite

type Part is Data:
  Part{index: Nat, text: String}

type Output is Data:
  Output{task: Nat, operation: Nat, parts: +List<Part>}

type Observation is Data:
  PartialOutput{output: Output}
  DiscardOutput{task: Nat, operation: Nat}
  ConnectionEnded{}

def selected_origin(matches: Bool, origin: D.OutputOrigin) -> Maybe<&2, D.OutputOrigin>:
  match matches:
    case True{}: Some{origin}
    case False{}: None{}

def matching_origin(phase: D.Phase, +producer: Nat, +operation: Nat, +part: Nat) -> Maybe<&2, D.OutputOrigin>:
  match phase:
    case D.ModelPending{expected, callable, mode}:
      selected_origin(Nat.is_eq(expected, operation), D.OutputOrigin{producer, operation, part, mode})
    case _: None{}


def found_origin(found: Maybe<&2, D.Task>, operation: Nat, part: Nat) -> Maybe<&2, D.OutputOrigin>:
  match found:
    case None{}: None{}
    case Some{+task}: matching_origin(D.task_phase(task), D.task_id(task), operation, part)

def origin(output: Output, part: Nat, world: M.World()) -> Maybe<&2, D.OutputOrigin>:
  Output{task, operation, parts} = output
  found_origin(Tasks.find(Commands.entries(world), task), operation, part)

def has_origin(value: Maybe<&2, D.OutputOrigin>) -> Bool:
  match value:
    case None{}: False{}
    case Some{origin}: True{}

def active(+output: Output, world: M.World()) -> Bool:
  has_origin(origin(output, 0n, world))

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

def namespace_characters(value: String) -> Bool:
  match value:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}:
      ((Bool.not(U32.is_lt(code, 48)) && U32.is_lt(code, 58)) ||
       (Bool.not(U32.is_lt(code, 97)) && U32.is_lt(code, 103))) && namespace_characters(rest)

def valid_namespace(+value: String) -> Bool:
  Nat.is_eq(String.length(value), 32n) && namespace_characters(value)

def decoded_part(index: Maybe<&2, Nat>, text: J.Json) -> Maybe<&2, Part>:
  match index text:
    case Some{index} J.Text{text}: Some{Part{index, text}}
    case _ _: None{}

def contains_part(parts: +List<Part>, +index: Nat) -> Bool:
  match parts:
    case Nil{}: False{}
    case Con{Part{actual, text}, rest}: Nat.is_eq(actual, index) || contains_part(rest, index)

def prepend_part_unique(duplicate: Bool, part: Part, rest: +List<Part>) -> Maybe<&2, +List<Part>>:
  match duplicate:
    case True{}: None{}
    case False{}: Some{part <> rest}

def prepend_decoded_part(part: Maybe<&2, Part>, rest: Maybe<&2, +List<Part>>) -> Maybe<&2, +List<Part>>:
  match part rest:
    case Some{Part{+index, text}} Some{+rest}: prepend_part_unique(contains_part(rest, index), Part{index, text}, rest)
    case _ _: None{}

def decoded_parts(values: +List<J.Json>) -> Maybe<&2, +List<Part>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{+value, rest}:
      prepend_decoded_part(decoded_part(J.natural(J.get(value, "output_index")), J.get(value, "text")), decoded_parts(rest))

def bounded_decoded_parts(allowed: Bool, values: +List<J.Json>) -> Maybe<&2, +List<Part>>:
  match allowed:
    case True{}: decoded_parts(values)
    case False{}: None{}

def decoded_part_array(value: J.Json) -> Maybe<&2, +List<Part>>:
  match value:
    case J.Array{+values}: bounded_decoded_parts(Nat.is_le(List.length(&2, J.Json, values), 32n), values)
    case _: None{}

def decoded_output(task: Maybe<&2, Nat>, ticket: Maybe<&2, Nat>, parts: Maybe<&2, +List<Part>>) -> Maybe<&2, Output>:
  match task ticket parts:
    case Some{task} Some{ticket} Some{parts}: Some{Output{task, ticket, parts}}
    case _ _ _: None{}

def active_decoded_output(owned: Bool, output: Output) -> Maybe<&2, Output>:
  match owned:
    case True{}: Some{output}
    case False{}: None{}

def decoded_active(output: Maybe<&2, Output>, world: M.World()) -> Maybe<&2, Output>:
  match output:
    case None{}: None{}
    case Some{+output}: active_decoded_output(active(output, world), output)

def decode_namespace_checked(matches: Bool, +value: J.Json, world: M.World()) -> Maybe<&2, Output>:
  match matches:
    case False{}: None{}
    case True{}: decoded_active(decoded_output(J.natural(J.get(value, "task_id")), J.natural(J.get(value, "ticket")), decoded_part_array(J.get(value, "parts"))), world)

def decode_namespace(+value: J.Json, +namespace: String, world: M.World()) -> Maybe<&2, Output>:
  decode_namespace_checked(valid_namespace(namespace) && String.eq(J.text(J.get(value, "namespace")), namespace), value, world)
