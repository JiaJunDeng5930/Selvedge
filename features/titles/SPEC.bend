import Base
import ./MODEL.bend as A
import ./STATE.bend as S
import ./CODEC.bend as Codec
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/conversation/TITLE.bend as Title
import ../../bendlib/component.bend as C
import ../../bendlib/effects.bend as Effects
import ../../bendlib/json.bend as J

def world(+decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

type SettingsResolution is Data:
  Configure{prompts: Title.Prompts}
  Refuse{code: String, reason: String}

def configure_revision(current: Bool, prompts: Title.Prompts) -> SettingsResolution:
  match current:
    case False{}: Refuse{"title_settings_conflict", "Title settings changed; reopen the settings before saving"}
    case True{}: Configure{prompts}

def configure_valid(valid: Bool, revision: Nat, +prompts: Title.Prompts, state: A.State) -> SettingsResolution:
  match valid:
    case False{}: Refuse{"invalid_title_settings", "Title prompts must be nonempty UTF-8 text of at most 4096 bytes"}
    case True{}: configure_revision(Nat.is_eq(revision, A.revision(state)), prompts)

def resolve_settings(command: A.Command, world: M.World()) -> SettingsResolution:
  A.Configure{revision, +prompts} = command
  configure_valid(Title.valid_prompts(prompts), revision, prompts, S.registry(world))

def configure(prompts: Title.Prompts, +world: M.World()) -> M.Decision():
  +updated = A.with_prompts(prompts, S.registry(world))
  C.Decision{S.store(updated, world), D.success(Codec.settings(updated)), Nil{}}

# Resolution captures the exact request and profile before interpretation.
type Start is Data:
  Skip{}
  Generate{task: Nat, ticket: Nat, profile: D.Profile, prompt: String}

def selected(+found: Maybe<&2, D.Profile>, +task: D.Task, +world: M.World()) -> Start:
  match found:
    case None{}: Skip{}
    case Some{profile}: Generate{D.task_id(task), S.ticket(world), profile, Title.prompt_with(Title.agent_instructions(A.prompts(S.registry(world))), S.request(task))}

def resolve(+task: D.Task, +world: M.World()) -> Start:
  selected(S.candidate(task, world), task, world)

def start(+operation: Start, +decision: M.Decision()) -> M.Decision():
  match operation decision:
    case Skip{} decision: decision
    case Generate{+id, +ticket, +profile, +prompt} C.Decision{+world, reply, effects}:
      C.Decision{S.store(A.put(id, A.Pending{ticket, profile, prompt}, S.registry(world)), S.reserve(world)), reply,
        List.append(&2, M.Effect(), effects, [Effects.FeatureEffect{F.TitleEffect{A.Request{id, ticket, profile, prompt}}}])}

def prepare_tasks(~begin: @+operation:Start -> @+decision:M.Decision() -> M.Decision(), tasks: +List<D.Task>, +decision: M.Decision()) -> M.Decision():
  match tasks:
    case Nil{}: decision
    case Con{+task, rest}: prepare_tasks(~begin, rest, begin(resolve(task, world(decision)), decision))

def prepare(+decision: M.Decision()) -> M.Decision():
  prepare_tasks(~start, S.tasks(world(decision)), decision)

def accepted(+current: Bool, +id: Nat, +outcome: A.Outcome, +world: M.World()) -> M.Decision():
  match current:
    case False{}: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case True{}: C.Decision{S.store(A.put(id, A.completed(outcome), S.registry(world)), world), D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}

def complete(+completion: A.Completion, +world: M.World()) -> M.Decision():
  A.Completed{+id, ticket, outcome} = completion
  accepted(S.correlated(A.find(S.registry(world), id), ticket), id, outcome, world)
