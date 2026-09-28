import Base
import ../FEATURES.bend as Features
import ./component.bend as Component
import ../BOARD.bend as B
import ../MODEL.bend as M
import ./board.bend as Board
import ./board-scheduling-spec.bend as Spec
import ./association-map.bend as Finite
import ./json.bend as J

# Execute the bounded board pump with PROGRAM's public command implementation.
# Its required decisions live in the independent specification module.

def failure_text(+reply: J.Json) -> String:
  J.text(J.get(J.get(reply, "error"), "code")) ++ ": " ++ J.text(J.get(J.get(reply, "error"), "message"))

def settled(ok: Bool, id: Nat, card: B.Card, before: M.Decision(), result: M.Decision()) -> M.Decision():
  match ok before result:
    case True{} Component.Decision{old, reply, effects} Component.Decision{world, ignored, added}:
      Component.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}
    case False{} Component.Decision{world, reply, effects} Component.Decision{ignored, failure, discarded}:
      Component.Decision{Board.failed_start(id, card, failure_text(failure), world), reply, effects}

def attempt(~run: M.Command -> M.World() -> M.Decision(), +id: Nat, +card: B.Card, +before: M.Decision()) -> M.Decision():
  +result = run(M.FeatureCommand{Features.BoardCommand{B.Run{id, B.revision(card), B.updated(card)}}}, Spec.decision_world(before))
  settled(Spec.result_ok(result), id, card, before, result)

def pump(~run: M.Command -> M.World() -> M.Decision(), fuel: Nat, selected: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision()) -> M.Decision():
  match fuel selected:
    case 0n _: decision
    case 1n+rest None{}: decision
    case 1n+rest Some{(id, card)}:
      +advanced = attempt(~run, id, card, decision)
      pump(~run, rest, Spec.next(Spec.decision_world(advanced)), advanced)

def prepared(~run: M.Command -> M.World() -> M.Decision(), +decision: M.Decision()) -> M.Decision():
  pump(~run, 8n, Spec.next(Spec.decision_world(decision)), decision)

def prepare(~run: M.Command -> M.World() -> M.Decision(), decision: M.Decision()) -> M.Decision():
  prepared(~run, Spec.synchronize(decision))
