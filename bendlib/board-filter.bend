import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../PROJECTS.bend as Projects
import ./board-state.bend as S
import ./board-codec.bend as C
import ./board-navigation.bend as N
import ./association-map.bend as Finite
import ./schema.bend as Schema
import ./json.bend as J

# The reference board combines categories by intersection and choices within a
# category by union. These predicates project the one native registry; the
# browser does not keep a second filtered collection or execution-state table.
def selected(+values: +List<String>, +value: String) -> Bool:
  match values:
    case Nil{}: True{}
    case entries: Schema.contains(entries, value)

def intersection(+left: +List<String>, +right: +List<String>) -> Bool:
  match left:
    case Nil{}: False{}
    case Con{value, rest}: Schema.contains(right, value) || intersection(rest, right)

def labels(+values: +List<String>, +labels: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case entries: intersection(entries, labels)

def age(+ordered: Bool, +now: U32, +then: U32) -> U32:
  match ordered:
    case True{}: U32.sub(now, then)
    case False{}: 0

def elapsed(+now: U32, +then: U32) -> U32:
  age(U32.is_le(then, now), now, then)

def day_limit(+days: String) -> U32:
  match days:
    case "1": 86400
    case "7": 604800
    case "30": 2592000
    case _: 0

def any_date(+values: +List<String>, +elapsed: U32) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{days, rest}: U32.is_le(elapsed, day_limit(days)) || any_date(rest, elapsed)

def date(+values: +List<String>, +elapsed: U32) -> Bool:
  match values:
    case Nil{}: True{}
    case entries: any_date(entries, elapsed)

def tab(+view: String, +assigned: Bool, +working: Bool) -> Bool:
  match view:
    case "assigned": assigned
    case "unassigned": Bool.not(assigned)
    case "working": working
    case _: True{}

def text(+query: String, +id: Nat, +card: B.Card) -> Bool:
  String.contains(String.to_lower(B.identifier(id) ++ " " ++ B.title(B.draft(card)) ++ " " ++ B.description(B.draft(card))),
    String.to_lower(String.trim(query)))

def matches(+filter: B.Filter, +now: U32, +id: Nat, +card: B.Card, +world: M.World) -> Bool:
  B.Filter{view, search, status, priority, dates, assignee, creator, project, label} = filter
  Bool.not(B.archived(card)) && tab(view, B.assigned(B.card_owner(B.draft(card))), S.busy(S.task(card, world))) &&
    selected(status, B.stage_name(B.card_stage(B.draft(card)))) &&
    selected(priority, B.priority_name(B.card_priority(B.draft(card)))) &&
    selected(assignee, B.owner_name(B.card_owner(B.draft(card)))) && selected(creator, "self") &&
    selected(project, C.id_text(B.project(B.draft(card)))) && labels(label, B.labels(B.draft(card))) &&
    date(dates, elapsed(now, B.updated(card))) && text(search, id, card)

def retain(+yes: Bool, +entry: Finite.Entry(B.Card), +rest: +List<Finite.Entry(B.Card)>) -> +List<Finite.Entry(B.Card)>:
  match yes:
    case True{}: entry <> rest
    case False{}: rest

def filtered(+entries: +List<Finite.Entry(B.Card)>, +filter: B.Filter, +now: U32, +world: M.World) -> +List<Finite.Entry(B.Card)>:
  match entries:
    case Nil{}: Nil{}
    case Con{(+id, +card), rest}:
      retain(matches(filter, now, id, card, world), (id, card), filtered(rest, filter, now, world))

def column(+entries: +List<Finite.Entry(B.Card)>, +stage: String) -> +List<Finite.Entry(B.Card)>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, +card), rest}: retain(String.eq(B.stage_name(B.card_stage(B.draft(card))), stage), (id, card), column(rest, stage))

def archived(+entries: +List<Finite.Entry(B.Card)>) -> +List<Finite.Entry(B.Card)>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, +card), rest}: retain(B.archived(card), (id, card), archived(rest))

def working(+entries: +List<Finite.Entry(B.Card)>, +world: M.World) -> Nat:
  match entries:
    case Nil{}: 0n
    case Con{(id, card), rest}: S.count(S.busy(S.task(card, world)), working(rest, world))

def choice(+value: String, +label: String, +icon: String) -> J.Json:
  J.Object{[J.Field{"value", J.Text{value}}, J.Field{"label", J.Text{label}}, J.Field{"icon", J.Text{icon}}]}

def stages(+entries: +List<B.Stage>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{+stage, rest}: choice(B.stage_name(stage), B.stage_label(stage), "status/" ++ B.stage_name(stage)) <> stages(rest)

def priority_choices() -> +List<J.Json>:
  [choice("none", "无优先级", "priority/none"), choice("low", "低优先级", "priority/low"),
   choice("medium", "中优先级", "priority/medium"), choice("high", "高优先级", "priority/high"), choice("urgent", "紧急优先级", "priority/urgent")]

def profile_choices(+profiles: +List<M.Profile>) -> +List<J.Json>:
  match profiles:
    case Nil{}: Nil{}
    case Con{M.Profile{+key, provider, model, policy}, rest}: choice(key, key, "bot") <> profile_choices(rest)

def profile_owners(+profiles: +List<M.Profile>) -> +List<J.Json>:
  match profiles:
    case Nil{}: Nil{}
    case Con{M.Profile{+key, provider, model, policy}, rest}: choice("profile/" ++ key, key, "bot") <> profile_owners(rest)

def agent_owners(+agents: +List<Finite.Entry(B.AgentProfile)>) -> +List<J.Json>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}), rest}:
      choice("agent/" ++ Nat.show(id), name, "bot") <> agent_owners(rest)

def owners(+world: M.World) -> +List<J.Json>:
  choice("none", "未分配", "user") <> choice("self", "我", "user") <>
    List.append(&2, J.Json, agent_owners(B.agents(S.registry(world))), profile_owners(S.profiles(world)))

def project_choices(+entries: +List<Finite.Entry(M.Project)>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, M.Project{name, workspace, guidance}), rest}: choice(Nat.show(id), name, "folder") <> project_choices(rest)

def projects(+world: M.World) -> +List<J.Json>:
  choice("", "未分配项目", "folder") <> project_choices(Projects.entries(Projects.registry(world)))

def add_label(+present: Bool, +name: String, +rest: +List<String>) -> +List<String>:
  match present:
    case True{}: rest
    case False{}: name <> rest

def unique_labels(+labels: +List<String>, +collected: +List<String>) -> +List<String>:
  match labels:
    case Nil{}: collected
    case Con{+name, rest}: unique_labels(rest, add_label(Schema.contains(collected, name), name, collected))

def collect_labels(+entries: +List<Finite.Entry(B.Card)>, +collected: +List<String>) -> +List<String>:
  match entries:
    case Nil{}: collected
    case Con{(id, card), rest}: collect_labels(rest, unique_labels(B.labels(B.draft(card)), collected))

def label_choices(+labels: +List<String>) -> +List<J.Json>:
  match labels:
    case Nil{}: Nil{}
    case Con{+name, rest}: choice(name, name, "tag") <> label_choices(rest)

def values(+category: String, +filter: B.Filter) -> +List<String>:
  match category filter:
    case "status" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: status
    case "priority" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: priority
    case "date" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: date
    case "assignee" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: assignee
    case "creator" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: creator
    case "project" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: project
    case "label" B.Filter{view, search, status, priority, date, assignee, creator, project, label}: label
    case _ _: Nil{}

def count(+filter: B.Filter) -> Nat:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  (List.length(&2, String, status) + List.length(&2, String, priority) + List.length(&2, String, date) +
    List.length(&2, String, assignee) + List.length(&2, String, creator) + List.length(&2, String, project) + List.length(&2, String, label) : Nat)

def project_name(+found: Maybe<&2, M.Project>) -> String:
  match found:
    case None{}: "未分配项目"
    case Some{M.Project{name, workspace, guidance}}: name

def project_label(+id: Maybe<&2, Nat>, +world: M.World) -> String:
  match id:
    case None{}: "未分配项目"
    case Some{id}: project_name(Projects.find(Projects.registry(world), id))

def agent_name(+found: Maybe<&2, B.AgentProfile>) -> String:
  match found:
    case None{}: "已移除的智能体"
    case Some{B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}}: name

def owner_label(+owner: B.Owner, +world: M.World) -> String:
  match owner:
    case B.Unassigned{}: "未分配"
    case B.Self{}: "我"
    case B.Profile{key}: key
    case B.Agent{id}: agent_name(B.find_agent(S.registry(world), id))

def time_unit(+minutes: Bool, +hours: Bool, +seconds: U32) -> String:
  match minutes hours:
    case True{} _: U32.show(U32.div(seconds, 60)) ++ " 分钟前"
    case _ True{}: U32.show(U32.div(seconds, 3600)) ++ " 小时前"
    case _ _: U32.show(U32.div(seconds, 86400)) ++ " 天前"

def recent(+just_now: Bool, +seconds: U32) -> String:
  match just_now:
    case True{}: "刚刚"
    case False{}: time_unit(U32.is_lt(seconds, 3600), U32.is_lt(seconds, 86400), seconds)

def time_ago(+now: U32, +then: U32) -> String:
  recent(U32.is_lt(elapsed(now, then), 60), elapsed(now, then))
