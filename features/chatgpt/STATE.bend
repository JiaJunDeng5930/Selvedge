import Base
import ./MODEL.bend as G
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/effects.bend as Effects
import ../../bendlib/association-map.bend as Finite

def registry(world: M.World()) -> G.State:
  F.chatgpt(C.rest(D.State, F.State(), world))

def store(state: G.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_chatgpt(state, features), world)

def effects(values: +List<G.Effect>) -> +List<M.Effect()>:
  match values:
    case Nil{}: Nil{}
    case Con{effect, rest}: Effects.FeatureEffect{F.ChatGPTEffect{effect}} <> effects(rest)

def embed(decision: C.Decision<G.State, G.Effect>, world: M.World()) -> M.Decision():
  C.Decision{state, reply, emitted} = decision
  C.Decision{store(state, world), reply, effects(emitted)}

def valid(+world: M.World()) -> Bool:
  G.valid(registry(world), Projects.registry(F.State(), world))
