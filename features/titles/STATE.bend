import Base
import ./MODEL.bend as A
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as Conversation
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/json.bend as J

def registry(+world: M.World()) -> A.State:
  F.titles(C.rest(D.State, F.State(), world))

def store(+state: A.State, +world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_titles(state, features), world)

def tasks(+world: M.World()) -> +List<D.Task>:
  D.state_tasks(C.local(D.State, F.State(), world))

def ticket(+world: M.World()) -> Nat:
  D.state_next_ticket(C.local(D.State, F.State(), world))

def reserve(+world: M.World()) -> M.World():
  C.map_local(D.State, F.State(), +core => D.with_state_next_ticket(1n+D.state_next_ticket(core), core), world)

def environment_profiles(+environment: D.Environment) -> +List<D.Profile>:
  D.Environment{tools, profiles, forks, descendants, project, plugins, instructions} = environment
  profiles

def profiles(+world: M.World()) -> +List<D.Profile>:
  environment_profiles(D.state_environment(C.local(D.State, F.State(), world)))

def stored_title(entry: Maybe<&2, A.Entry>) -> Maybe<&2, String>:
  match entry:
    case Some{A.Named{title}}: Some{title}
    case _: None{}

def selected_title(found: Maybe<&2, String>, fallback: Unit -> String) -> String:
  match found:
    case Some{title}: title
    case None{}: fallback(Unit{})

def resolved_title(+id: Nat, +world: M.World()) -> Maybe<&2, String>:
  stored_title(A.find(registry(world), id))

def name(+id: Nat, fallback: String, +world: M.World()) -> String:
  selected_title(resolved_title(id, world), unused => fallback)

def title(+task: D.Task, +world: M.World()) -> String:
  selected_title(resolved_title(D.task_id(task), world), unused => Conversation.title(task))

def with_title(+value: J.Json, +title: String) -> J.Json:
  match value:
    case J.Object{fields}: J.Object{J.Field{"title", J.Text{title}} <> fields}
    case other: other

def summary(+task: D.Task, +world: M.World()) -> J.Json:
  with_title(Tasks.summary(task), title(task, world))

def titled_task_fields(+fields: +List<J.Field>, +title: String) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"task", value}, rest}: J.Field{"task", with_title(value, title)} <> rest
    case Con{field, rest}: field <> titled_task_fields(rest, title)

def page_fields(+page: J.Json, +title: String) -> J.Json:
  match page:
    case J.Object{fields}: J.Object{titled_task_fields(fields, title)}
    case other: other

def page(+task: D.Task, +after: Nat, +limit: Nat, +world: M.World()) -> J.Json:
  page_fields(Tasks.page(task, after, limit), title(task, world))

def summaries(+tasks: +List<D.Task>, +world: M.World()) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: summary(task, world) <> summaries(rest, world)

def request(+task: D.Task) -> String:
  Conversation.first_request(D.history_messages(D.task_history(task), Nil{}), "")

def absent(+entry: Maybe<&2, A.Entry>) -> Bool:
  match entry:
    case None{}: True{}
    case _: False{}

def candidate_model(+model: D.Model, +profiles: +List<D.Profile>) -> Maybe<&2, D.Profile>:
  D.Model{profile, effort} = model
  A.profile(profiles, profile)

def requested_candidate(found: Maybe<&2, D.Profile>, task: D.Task) -> Maybe<&2, D.Profile>:
  match found:
    case None{}: None{}
    case Some{profile}: A.selected(D.nonempty(request(task)), profile)

def candidate_when(+eligible: Bool, +task: D.Task, +world: M.World()) -> Maybe<&2, D.Profile>:
  match eligible:
    case False{}: None{}
    case True{}: requested_candidate(candidate_model(D.task_model(task), profiles(world)), task)

def candidate(+task: D.Task, +world: M.World()) -> Maybe<&2, D.Profile>:
  candidate_when(D.accepts_input(D.task_status(task)) && absent(A.find(registry(world), D.task_id(task))), task, world)

def correlated(+entry: Maybe<&2, A.Entry>, +ticket: Nat) -> Bool:
  match entry:
    case Some{A.Pending{expected, profile, prompt}}: Nat.is_eq(expected, ticket)
    case _: False{}

def valid_entry(+entry: A.Entry, +next_ticket: Nat) -> Bool:
  match entry:
    case A.Pending{ticket, profile, prompt}: Nat.is_lt(ticket, next_ticket) && A.title_capable(profile) && Nat.is_le(J.utf8_length(prompt), Title.maximum_prompt_bytes())
    case A.Named{+title}: D.nonempty(title) && Nat.is_le(String.length(title), Title.maximum_characters())
    case A.Failed{}: True{}

def missing_task(+found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: True{}
    case _: False{}

def valid_entries(+values: +List<Finite.Entry(A.Entry)>, +world: M.World()) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{(+id, entry), +rest}: absent(Finite.find(~A.Entry, rest, id)) &&
      Bool.not(missing_task(Tasks.find(tasks(world), id))) && valid_entry(entry, ticket(world)) && valid_entries(rest, world)

def valid(+world: M.World()) -> Bool:
  Title.valid_prompts(A.prompts(registry(world))) && valid_entries(A.entries(registry(world)), world)

def profile_key(+profile: D.Profile) -> String:
  D.Profile{key, provider, name, policy, options} = profile
  key

def configured(+found: Maybe<&2, D.Profile>, +profile: D.Profile) -> Bool:
  match found:
    case None{}: False{}
    case Some{current}: Workspace.profile_same(current, profile) && A.title_capable(profile)

def request_valid(+found: Maybe<&2, A.Entry>, +ticket: Nat, +profile: D.Profile, +prompt: String) -> Bool:
  match found:
    case Some{A.Pending{expected, selected, source}}:
      Nat.is_eq(expected, ticket) && Workspace.profile_same(selected, profile) && String.eq(source, prompt)
    case _: False{}
def effect_valid(+effect: A.Effect, +state: A.State, +profiles: +List<D.Profile>) -> Bool:
  A.Request{+id, +ticket, +profile, +prompt} = effect
  request_valid(A.find(state, id), ticket, profile, prompt) && configured(D.find_profile(profiles, profile_key(profile)), profile)
