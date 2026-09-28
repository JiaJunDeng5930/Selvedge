import Base
import ../MODEL.bend as M
import ./json.bend as J

# Shared presentation vocabulary. Components can construct surfaces without
# importing the application renderer or another component's view implementation.
type Choice is Data:
  Choice{value: String, label: String}

type Field is Data:
  Field{name: String, label: String, kind: String, value: J.Json,
    schema: J.Json, choices: +List<Choice>, required: Bool}

type ActivityState is Data:
  Running{}
  Waiting{}
  Complete{}
  Failed{}
  Informational{}

def activity_state(state: ActivityState) -> String:
  match state:
    case Running{}: "running"
    case Waiting{}: "waiting"
    case Complete{}: "complete"
    case Failed{}: "failed"
    case Informational{}: "information"

# A conversation has named regions, not a bag of widgets whose placement the
# adapter guesses. Draft ownership is independent of the chosen submission form.
type Node is Data:
  Thread{key: String, task_id: Maybe<&2, Nat>, title: String, subtitle: String,
    timeline: +List<Node>, composer: +List<Node>, details: +List<Node>, actions: +List<Node>}
  ThreadLink{key: String, title: String, subtitle: String, state: String,
    event: M.ViewEvent, selected: Bool}
  Composer{key: String, draft_key: String, title: String, hint: String,
    forms: +List<Node>, actions: +List<Node>}
  Activity{key: String, title: String, state: ActivityState, children: +List<Node>}
  Group{key: String, role: String, title: String, children: +List<Node>}
  Text{key: String, role: String, title: String, text: String}
  Value{key: String, title: String, value: J.Json}
  Action{key: String, label: String, event: M.ViewEvent, enabled: Bool, selected: Bool}
  Form{key: String, title: String, label: String, command: M.Command, fields: +List<Field>, enabled: Bool}
  Composition{key: String, role: String, properties: J.Json, children: +List<Node>}

type Presentation is Data:
  Presentation{state: M.ViewState, root: Node}
