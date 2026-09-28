import Base
import ../MODEL.bend as M
import ../INVARIANTS.bend as I
import ./commit.bend as Commit
import ./execution.bend as Execution
import ./stdlib.bend as Std

# Independent finite-trace meaning. Complete receipts are newest first.
# No implementation module is in this specification's dependency closure.
type Tape is Data:
  Tape{world: M.World(), pending: +List<M.Input>, receipts: +List<M.Decision()>}

def state(tape: Tape) -> M.World():
  Tape{world, pending, receipts} = tape
  world

def valid(tape: Tape) -> Bool:
  I.world(state(tape))

def record(+decision: M.Decision(), pending: +List<M.Input>, receipts: +List<M.Decision()>) -> Tape:
  Tape{Execution.world(decision), pending, decision <> receipts}

def step(tape: Tape) -> Tape:
  match tape:
    case Tape{world, Nil{}, receipts}: Tape{world, Nil{}, receipts}
    case Tape{world, Con{input, pending}, receipts}:
      record(Commit.input(~Execution.scheduled, input, world), pending, receipts)

def run(count: Nat, tape: Tape) -> Tape:
  Std.iter(~Tape, ~step, count, tape)

def identity(tape: Tape) -> Tape:
  tape
