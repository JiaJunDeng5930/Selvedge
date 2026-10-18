import Base
import ../../bendlib/association-map.bend as Finite
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/workspace/WORKSPACE.bend as Workspace

type Entry is Data:
  Pending{ticket: Nat, profile: D.Profile, prompt: String}
  Named{title: String}
  Failed{}

type State is Data:
  State{entries: +List<Finite.Entry(Entry)>, revision: Nat, prompts: Title.Prompts}

type Command is Data:
  Configure{revision: Nat, prompts: Title.Prompts}

type Query is Data:
  Settings{}

type Outcome is Data:
  Suggested{title: String}
  Unavailable{}

type Effect is Data:
  Request{task_id: Nat, ticket: Nat, profile: D.Profile, prompt: String}

type Completion is Data:
  Completed{task_id: Nat, ticket: Nat, outcome: Outcome}

def initial() -> State:
  State{Nil{}, 0n, Title.default_prompts()}

def entries(+state: State) -> +List<Finite.Entry(Entry)>:
  State{entries, revision, prompts} = state
  entries

def revision(state: State) -> Nat:
  State{entries, revision, prompts} = state
  revision

def prompts(state: State) -> Title.Prompts:
  State{entries, revision, prompts} = state
  prompts

def with_prompts(value: Title.Prompts, state: State) -> State:
  State{entries, revision, previous} = state
  State{entries, 1n+revision, value}

def find(+state: State, +id: Nat) -> Maybe<&2, Entry>:
  Finite.find(~Entry, entries(state), id)

def put(+id: Nat, +entry: Entry, +state: State) -> State:
  State{(id, entry) <> Finite.remove(~Entry, entries(state), id), revision(state), prompts(state)}

def ordinary(+profile: D.Profile) -> Bool:
  D.Profile{key, +provider, name, policy, options} = profile
  Bool.not(String.eq(provider, "echo")) && Bool.not(Reasoning.automatic(policy))

def title_capable(profile: D.Profile) -> Bool:
  D.Profile{key, provider, name, policy, options} = profile
  Bool.not(String.eq(provider, "echo"))

def selected(+eligible: Bool, +profile: D.Profile) -> Maybe<&2, D.Profile>:
  match eligible:
    case True{}: Some{profile}
    case False{}: None{}

def prefer_selected(+use: Bool, +profile: D.Profile, +fallback: Maybe<&2, D.Profile>) -> Maybe<&2, D.Profile>:
  match use:
    case True{}: Some{profile}
    case False{}: fallback

def account_parts(parts: +List<String>) -> String:
  match parts:
    case Con{"chatgpt", Con{account, Con{model, rest}}}: "chatgpt/" ++ account ++ "/"
    case _: ""

def account_prefix(key: String) -> String:
  account_parts(String.split(key, Chr{47}))

def preferred(+profiles: +List<D.Profile>, +provider: String, +prefix: String, +fallback: Maybe<&2, D.Profile>) -> Maybe<&2, D.Profile>:
  match profiles:
    case Nil{}: fallback
    case Con{D.Profile{+key, +source, +name, +policy, +options}, rest}:
      prefer_selected(String.eq(provider, "chatgpt") && Bool.not(String.is_empty(prefix)) && String.starts_with(key, prefix) && String.eq(source, provider) && String.eq(name, "gpt-5.6-luna") && ordinary(D.Profile{key, source, name, policy, options}),
        D.Profile{key, source, name, policy, options}, preferred(rest, provider, prefix, fallback))

def available(+found: Maybe<&2, D.Profile>) -> Maybe<&2, D.Profile>:
  match found:
    case None{}: None{}
    case Some{+profile}: selected(title_capable(profile), profile)

def profile(+profiles: +List<D.Profile>, +current: D.Profile) -> Maybe<&2, D.Profile>:
  D.Profile{+key, +provider, +name, +policy, +options} = current
  preferred(profiles, provider, account_prefix(key), available(D.find_profile(profiles, key)))

def completed_title(+title: String) -> Entry:
  match title:
    case "": Failed{}
    case title: Named{title}

def completed(+outcome: Outcome) -> Entry:
  match outcome:
    case Unavailable{}: Failed{}
    case Suggested{title}: completed_title(Title.normalize(title))

def recover_entry(+entry: Entry) -> Entry:
  match entry:
    case Pending{ticket, profile, prompt}: Failed{}
    case other: other

def recovered(+values: +List<Finite.Entry(Entry)>) -> +List<Finite.Entry(Entry)>:
  match values:
    case Nil{}: Nil{}
    case Con{(id, entry), rest}: (id, recover_entry(entry)) <> recovered(rest)

def recover(+state: State) -> State:
  State{recovered(entries(state)), revision(state), prompts(state)}

def pending(+values: +List<Finite.Entry(Entry)>) -> +List<Nat>:
  match values:
    case Nil{}: Nil{}
    case Con{(id, Pending{ticket, profile, prompt}), rest}: ticket <> pending(rest)
    case Con{other, rest}: pending(rest)

def entry_retained(previous: Entry, current: Maybe<&2, Entry>) -> Bool:
  match previous current:
    case Pending{ticket, profile, prompt} Some{Pending{next_ticket, next_profile, next_prompt}}:
      Nat.is_eq(ticket, next_ticket) && Workspace.profile_same(profile, next_profile) && String.eq(prompt, next_prompt)
    case Pending{ticket, profile, prompt} Some{Named{title}}: True{}
    case Pending{ticket, profile, prompt} Some{Failed{}}: True{}
    case Named{title} Some{Named{next}}: String.eq(title, next)
    case Failed{} Some{Failed{}}: True{}
    case _ _: False{}

def retained(previous: +List<Finite.Entry(Entry)>, +current: State) -> Bool:
  match previous:
    case Nil{}: True{}
    case Con{(+id, entry), rest}: entry_retained(entry, find(current, id)) && retained(rest, current)

def evolution(+previous: State, +current: State) -> Bool:
  retained(entries(previous), current) && Nat.is_le(revision(previous), revision(current)) &&
    (Bool.not(Nat.is_eq(revision(previous), revision(current))) || Title.same_prompts(prompts(previous), prompts(current)))
