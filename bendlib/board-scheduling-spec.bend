import Base
import ./effects.bend as Effects
import ./domain.bend as D
import ../FEATURES.bend as F
import ./component.bend as C
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./board-state.bend as S
import ./association-map.bend as Finite
import ./json.bend as J

# Queue selection and continuation are authoritative semantic primitives.
# These equations import neither the executor nor a scheduler callback.

def decision_world(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def pick(ready: Bool, entry: Finite.Entry(B.Card), remaining: Maybe<&2, Finite.Entry(B.Card)>) -> Maybe<&2, Finite.Entry(B.Card)>:
  match ready:
    case True{}: Some{entry}
    case False{}: remaining

def candidate(entries: +List<Finite.Entry(B.Card)>, +world: M.World()) -> Maybe<&2, Finite.Entry(B.Card)>:
  match entries:
    case Nil{}: None{}
    case Con{(+id, +card), rest}:
      pick(B.ready(card) && S.runnable(card, world), (id, card), candidate(rest, world))

def automatic_candidate(enabled: Bool, +world: M.World()) -> Maybe<&2, Finite.Entry(B.Card)>:
  match enabled:
    case False{}: None{}
    case True{}: candidate(S.queued_cards(S.registry(world)), world)

def next(+world: M.World()) -> Maybe<&2, Finite.Entry(B.Card)>:
  automatic_candidate(B.automatic(S.registry(world)), world)

def synchronize(decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  C.Decision{S.synchronize(world), reply, effects}

def result_ok(decision: M.Decision()) -> Bool:
  C.Decision{world, reply, effects} = decision
  J.boolean(J.get(reply, "ok"))

def continuing(effects: +List<M.Effect()>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{Effects.ContinueScheduling{}, rest}: True{}
    case Con{other, rest}: continuing(rest)

def ensure_continue(present: Bool, effects: +List<M.Effect()>) -> +List<M.Effect()>:
  match present:
    case True{}: effects
    case False{}: List.append(&2, M.Effect(), effects, [Effects.ContinueScheduling{}])

def final_candidate(selected: Maybe<&2, Finite.Entry(B.Card)>, decision: M.Decision()) -> M.Decision():
  match selected decision:
    case None{} decision: decision
    case Some{entry} C.Decision{world, reply, +effects}:
      C.Decision{world, reply, ensure_continue(continuing(effects), effects)}

def finalized(+decision: M.Decision()) -> M.Decision():
  final_candidate(next(decision_world(decision)), decision)

def finish(decision: M.Decision()) -> M.Decision():
  finalized(synchronize(decision))

# Independent equations use the command specification, not the executor passed
# to pump. Their correspondence is proved for every fuel and candidate, not
# inferred from sample schedules or from the production implementation itself.

def required_result(ok: Bool, +id: Nat, card: B.Card, previous: M.Decision(), result: M.Decision()) -> M.Decision():
  match ok previous result:
    case True{} C.Decision{old, reply, effects} C.Decision{world, ignored, added}:
      C.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}
    case False{} C.Decision{C.Frame{D.State{tasks, task_id, ticket, environment, limits, projects}, +board}, reply, effects} C.Decision{ignored, +failure, discarded}:
      C.Decision{C.Frame{D.State{tasks, task_id, ticket, environment, limits, projects}, F.with_board(B.put(id, B.start_failed(String.take(J.text(J.get(J.get(failure, "error"), "code")) ++ ": " ++
          J.text(J.get(J.get(failure, "error"), "message")), 1000n), card), F.board(board), B.next_card(F.board(board))), board)}, reply, effects}

def required_attempt(+id: Nat, +card: B.Card, +previous: M.Decision()) -> M.Decision():
  +result = Commands.command(M.FeatureCommand{F.BoardCommand{B.Run{id, B.revision(card), B.updated(card)}}}, decision_world(previous))
  required_result(result_ok(result), id, card, previous, result)

def required(fuel: Nat, selected: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision()) -> M.Decision():
  match fuel selected:
    case 0n _: decision
    case 1n+rest None{}: decision
    case 1n+rest Some{(id, card)}:
      +advanced = required_attempt(id, card, decision)
      required(rest, next(decision_world(advanced)), advanced)

def required_prepared(+decision: M.Decision()) -> M.Decision():
  required(8n, next(decision_world(decision)), decision)

def required_prepare(decision: M.Decision()) -> M.Decision():
  required_prepared(synchronize(decision))
