import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./LAWS.bend as Laws
import ../bendlib/json.bend as J
import ./transport/presentation.bend as View

# Local proof obligations for the observations boundary. No runtime policy lives here.

def output_admitted_world(fits: Bool, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.output_admitted(fits, decision, previous)) == previous : M.World()}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_world(rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.admission(rendered, decision, previous)) == previous : M.World()}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_world(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def deliver_world(+durable: Bool, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.deliver(durable, decision, previous)) == previous : M.World()}:
  admission_world(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, evidence)

def Laws.observation_preserves_world(query, world):
  deliver_world(False{}, P.observe(query, world), world, {==})

def output_admitted_no_effects(fits: Bool, +decision: M.Decision(), previous: M.World(),
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(P.output_admitted(fits, decision, previous)) == Nil{} : +List<M.Effect()>}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_no_effects(rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(P.admission(rendered, decision, previous)) == Nil{} : +List<M.Effect()>}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_no_effects(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def Laws.observation_has_no_effects(query, world):
  admission_no_effects(J.render(P.rendering_budget(world), J.One{View.envelope(False{}, P.observe(query, world))}),
    P.observe(query, world), world, {==})

def Laws.observation_not_durable(query):
  {==}

def Laws.delivery_observation_world(durable, decision, previous, unchanged):
  deliver_world(durable, decision, previous, unchanged)

def Laws.delivery_observation_effects(durable, decision, previous, silent):
  admission_no_effects(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, silent)
