import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../../bendlib/stdlib.bend as Std
import ../conversation/MODEL.bend as Spec

# A finite input trace is an ordinary discrete state machine. Receipts retain
# complete decisions, newest first; simulation therefore preserves replies and
# effect order as well as the last world. Exhausted input is a stationary state.
def implementation(tape: Spec.Tape) -> Spec.Tape:
  match tape:
    case Spec.Tape{world, Nil{}, receipts}: Spec.Tape{world, Nil{}, receipts}
    case Spec.Tape{world, Con{input, pending}, receipts}:
      Spec.record(P.transition(input, world), pending, receipts)

def actual(count: Nat, tape: Spec.Tape) -> Spec.Tape:
  Std.iter(~Spec.Tape, ~implementation, count, tape)

def replay(+inputs: +List<M.Input>, world: M.World()) -> M.World():
  Spec.state(actual(List.length(&2, M.Input, inputs), Spec.Tape{world, inputs, Nil{}}))
