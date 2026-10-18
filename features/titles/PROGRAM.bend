import Base
import ./MODEL.bend as A
import ./STATE.bend as S
import ./SPEC.bend as Spec
import ./CODEC.bend as Codec
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/effects.bend as Effects
import ../../bendlib/json.bend as J

def configure(prompts: Title.Prompts, +world: M.World()) -> M.Decision():
  C.Frame{core, +features} = world
  +updated = A.with_prompts(prompts, F.titles(features))
  C.Decision{C.Frame{core, F.with_titles(updated, features)}, D.success(Codec.settings(updated)), Nil{}}

def start(+operation: Spec.Start, +decision: M.Decision()) -> M.Decision():
  match operation decision:
    case Spec.Skip{} decision: decision
    case Spec.Generate{+id, +ticket, +profile, +prompt} C.Decision{C.Frame{+core, +features}, reply, effects}:
      C.Decision{C.Frame{D.with_state_next_ticket(1n+D.state_next_ticket(core), core),
        F.with_titles(A.put(id, A.Pending{ticket, profile, prompt}, F.titles(features)), features)}, reply,
        List.append(&2, M.Effect(), effects, [Effects.FeatureEffect{F.TitleEffect{A.Request{id, ticket, profile, prompt}}}])}

def prepare(+decision: M.Decision()) -> M.Decision():
  Spec.prepare_tasks(~start, S.tasks(Spec.world(decision)), decision)

def complete_selected(+current: Bool, +id: Nat, +outcome: A.Outcome, +world: M.World()) -> M.Decision():
  match current world:
    case False{} world: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case True{} C.Frame{core, +features}:
      C.Decision{C.Frame{core, F.with_titles(A.put(id, A.completed(outcome), F.titles(features)), features)},
        D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}

def complete(+completion: A.Completion, +world: M.World()) -> M.Decision():
  A.Completed{+id, ticket, outcome} = completion
  complete_selected(S.correlated(A.find(S.registry(world), id), ticket), id, outcome, world)
