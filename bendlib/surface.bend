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

type Node is Data:
  Group{key: String, role: String, title: String, children: +List<Node>}
  Text{key: String, role: String, title: String, text: String}
  Value{key: String, title: String, value: J.Json}
  Action{key: String, label: String, event: M.ViewEvent, enabled: Bool, selected: Bool}
  Form{key: String, title: String, label: String, command: M.Command, fields: +List<Field>, enabled: Bool}
  Composition{key: String, role: String, properties: J.Json, children: +List<Node>}

type Presentation is Data:
  Presentation{state: M.ViewState, root: Node}
