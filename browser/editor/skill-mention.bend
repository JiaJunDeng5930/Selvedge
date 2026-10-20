import Base
import ../../bendlib/json.bend as J
import ../controls/GEOMETRY.bend as Physical

type Skill is Data:
  Skill{name: String, description: String, path: String}

type Trigger is Data:
  Trigger{start: Nat, end: Nat, query: String}

type CatalogStatus is Data:
  Unrequested{}
  Loading{}
  Ready{}
  Failed{reason: String}

type State is Data:
  State{field: String, trigger: Maybe<&2, Trigger>, dismissed: Maybe<&2, Trigger>, selected: Nat,
    skills: +List<Skill>, workspace: String, generation: Nat, status: CatalogStatus}

type Insertion is Data:
  Insertion{text: String, caret: Nat}

def initial() -> State:
  State{"", None{}, None{}, 0n, Nil{}, "", 0n, Unrequested{}}

def whitespace(+char: Char) -> Bool:
  Char.is_eq(char, ' ') || Char.is_eq(char, '\t') || Char.is_eq(char, '\n') || Char.is_eq(char, '\r')

def boundary(+char: Char) -> Bool:
  whitespace(char) || Char.is_eq(char, '(') || Char.is_eq(char, '[') || Char.is_eq(char, '{')

def extend(trigger: Maybe<&2, Trigger>, +char: Char, end: Nat) -> Maybe<&2, Trigger>:
  match trigger:
    case None{}: None{}
    case Some{Trigger{start, old_end, +query}}:
      Bool.pick(Maybe<&2, Trigger>, String.eq(query, "") && whitespace(char), None{}, Some{Trigger{start, end, query ++ SCon{char, ""}}})

def scan(text: String, +offset: Nat, previous_boundary: Bool, +fenced: Bool, +inline_code: Bool, trigger: Maybe<&2, Trigger>) -> Maybe<&2, Trigger>:
  match text:
    case "": trigger
    case SCon{'`', SCon{'`', SCon{'`', rest}}}:
      scan(rest, (offset + 3n : Nat), False{}, Bool.not(fenced), False{}, None{})
    case SCon{'~', SCon{'~', SCon{'~', rest}}}:
      scan(rest, (offset + 3n : Nat), False{}, Bool.not(fenced), False{}, None{})
    case SCon{'`', rest}: scan(rest, (offset + 1n : Nat), False{}, fenced, Bool.not(inline_code), None{})
    case SCon{'\n', rest}: scan(rest, (offset + 1n : Nat), True{}, fenced, False{}, None{})
    case SCon{'\r', rest}: scan(rest, (offset + 1n : Nat), True{}, fenced, False{}, None{})
    case SCon{'@', rest}:
      scan(rest, (offset + 1n : Nat), False{}, fenced, inline_code,
        Bool.pick(Maybe<&2, Trigger>, previous_boundary && Bool.not(fenced || inline_code), Some{Trigger{offset, (offset + 1n : Nat), ""}}, None{}))
    case SCon{+char, rest}:
      scan(rest, (offset + 1n : Nat), boundary(char), fenced, inline_code,
        Bool.pick(Maybe<&2, Trigger>, fenced || inline_code, None{}, extend(trigger, char, (offset + 1n : Nat))))

def detect(+text: String, selection: Physical.Selection, composing: Bool) -> Maybe<&2, Trigger>:
  Physical.Selection{+start, end, direction} = selection
  Bool.pick(Maybe<&2, Trigger>, composing || Bool.not(Nat.is_eq(start, end)) || Nat.is_lt(String.length(text), start),
    None{}, scan(String.take(text, start), 0n, True{}, False{}, False{}, None{}))

def same_trigger(left: Maybe<&2, Trigger>, right: Maybe<&2, Trigger>) -> Bool:
  match left right:
    case Some{Trigger{a, b, query}} Some{Trigger{c, d, other}}:
      Nat.is_eq(a, c) && Nat.is_eq(b, d) && String.eq(query, other)
    case None{} None{}: True{}
    case _ _: False{}

def query(trigger: Maybe<&2, Trigger>) -> String:
  match trigger:
    case None{}: ""
    case Some{Trigger{start, end, value}}: value

def open(state: State) -> Bool:
  State{field, +trigger, dismissed, selected, skills, workspace, generation, status} = state
  match trigger:
    case None{}: False{}
    case Some{value}: Bool.not(same_trigger(Some{value}, dismissed))


def refresh_opening(refresh: Bool, state: State) -> State:
  match refresh:
    case False{}: state
    case True{}:
      State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
      State{field, trigger, dismissed, 0n, Nil{}, workspace, generation, Unrequested{}}

def refocus(+state: State) -> State:
  refresh_opening(open(state), state)

def observe_found(+found: Maybe<&2, Trigger>, +state: State) -> State:
  State{field, +previous, +dismissed, selected, skills, workspace, generation, status} = state
  +next : State = State{field, found,
    Bool.pick(Maybe<&2, Trigger>, same_trigger(found, dismissed), dismissed, None{}),
    Bool.pick(Nat, same_trigger(found, previous), selected, 0n), skills, workspace, generation, status}
  refresh_opening(Bool.not(open(state)) && open(next), next)

def observe(text: String, selection: Physical.Selection, composing: Bool, state: State) -> State:
  observe_found(detect(text, selection, composing), state)


def dismiss(state: State) -> State:
  State{field, +trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, trigger, trigger, selected, skills, workspace, generation, status}

def keep_skill(keep: Bool, skill: Skill, rest: +List<Skill>) -> +List<Skill>:
  match keep:
    case True{}: skill <> rest
    case False{}: rest

def filter(skills: +List<Skill>, +search: String) -> +List<Skill>:
  match skills:
    case Nil{}: Nil{}
    case Con{Skill{+name, +description, path}, rest}:
      keep_skill(String.contains(String.to_lower(name ++ " " ++ description), search), Skill{name, description, path}, filter(rest, search))

def candidates(state: State) -> +List<Skill>:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  filter(skills, String.to_lower(String.trim(query(trigger))))

def at(skills: +List<Skill>, index: Nat) -> Maybe<&2, Skill>:
  match skills index:
    case Nil{} _: None{}
    case Con{first, rest} 0n: Some{first}
    case Con{first, rest} 1n+n: at(rest, n)

def selected(state: State) -> Nat:
  State{field, trigger, dismissed, index, skills, workspace, generation, status} = state
  index

def active(+state: State) -> Maybe<&2, Skill>:
  Bool.pick(Maybe<&2, Skill>, open(state), at(candidates(state), selected(state)), None{})

def move_index(backward: Bool, +selected: Nat, +count: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(count, 0n), 0n,
    Bool.pick(Nat, backward,
      Bool.pick(Nat, Nat.is_eq(selected, 0n), Nat.sub(count, 1n), Nat.sub(selected, 1n)),
      Bool.pick(Nat, Nat.is_lt((selected + 1n : Nat), count), (selected + 1n : Nat), 0n)))

def move(backward: Bool, +state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, trigger, dismissed, move_index(backward, selected, List.length(&2, Skill, candidates(state))), skills, workspace, generation, status}

def choose(index: Nat, state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, trigger, dismissed, index, skills, workspace, generation, status}

def escaped_label(text: String) -> String:
  match text:
    case "": ""
    case SCon{+char, rest}:
      Bool.pick(String, Char.is_eq(char, '\\') || Char.is_eq(char, '[') || Char.is_eq(char, ']'), "\\", "") ++ SCon{char, escaped_label(rest)}

def escaped_path(text: String) -> String:
  match text:
    case "": ""
    case SCon{+char, rest}:
      Bool.pick(String, Char.is_eq(char, '\\') || Char.is_eq(char, '(') || Char.is_eq(char, ')') || Char.is_eq(char, '<') || Char.is_eq(char, '>'), "\\", "") ++ SCon{char, escaped_path(rest)}

def destination(+path: String) -> String:
  Bool.pick(String, String.contains(path, " ") || String.contains(path, "\t"), "<" ++ escaped_path(path) ++ ">", escaped_path(path))

def reference(skill: Skill) -> String:
  Skill{name, description, path} = skill
  "[$" ++ escaped_label(name) ++ "](" ++ destination(path) ++ ")"

def separator(suffix: String) -> String:
  match suffix:
    case SCon{char, rest}: Bool.pick(String, whitespace(char), "", " ")
    case "": " "

def insert(+text: String, trigger: Trigger, skill: Skill) -> Insertion:
  Trigger{+start, +end, query} = trigger
  +replacement = reference(skill) ++ separator(String.drop(text, end))
  Insertion{String.take(text, start) ++ replacement ++ String.drop(text, end), (start + String.length(replacement) : Nat)}

def decode_skills(values: +List<J.Json>) -> +List<Skill>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      Skill{J.text(J.get(value, "name")), J.text(J.get(value, "description")), J.text(J.get(value, "path"))} <> decode_skills(rest)

def receive(current: Bool, +body: J.Json, state: State) -> State:
  match current:
    case False{}: state
    case True{}:
      State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
      State{field, trigger, dismissed, 0n, decode_skills(J.items(J.get(body, "skills"))), workspace, generation,
        Bool.pick(CatalogStatus, J.boolean(J.get(body, "ok")), Ready{}, Failed{J.text(J.get(body, "error"))})}

def field(state: State) -> String:
  State{key, trigger, dismissed, selected, skills, workspace, generation, status} = state
  key

def with_field(key: String, state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{key, trigger, dismissed, selected, skills, workspace, generation, status}

def context(same: Bool, workspace: String, state: State) -> State:
  match same:
    case True{}: state
    case False{}:
      State{field, trigger, dismissed, selected, skills, old_workspace, generation, status} = state
      State{field, trigger, dismissed, 0n, Nil{}, workspace, generation, Unrequested{}}

def workspace(state: State) -> String:
  State{field, trigger, dismissed, selected, skills, value, generation, status} = state
  value

def generation(state: State) -> Nat:
  State{field, trigger, dismissed, selected, skills, workspace, value, status} = state
  value

def unrequested(state: State) -> Bool:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  match status:
    case Unrequested{}: True{}
    case _: False{}

def requested(state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, trigger, dismissed, selected, skills, workspace, (generation + 1n : Nat), Loading{}}

def trigger(state: State) -> Maybe<&2, Trigger>:
  State{field, value, dismissed, selected, skills, workspace, generation, status} = state
  value

def clear(state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, None{}, None{}, 0n, skills, workspace, generation, status}


def without_workspace(state: State) -> State:
  State{field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  State{field, None{}, None{}, 0n, Nil{}, "", generation, Unrequested{}}
