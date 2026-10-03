import Base
import ../core/code-block.bend as Code

# These are browser operations, not another product vocabulary. The executable
# Bend renderer chooses every element, style, label and event binding.
type Property is Data:
  Property{name: String, value: String}

type Event is Data:
  Activate{key: String}
  EditText{key: String}
  ConfirmText{key: String}
  EditToggle{key: String}
  SelectFiles{key: String}
  DragCard{key: String}
  DropCard{key: String}
  PlaceCard{key: String, target: String}

type Node is Data:
  Element{key: String, tag: String, attributes: +List<Property>,
    styles: +List<Property>, events: +List<Event>, children: +List<Node>}
  Text{value: String}
  Markdown{key: String, source: Maybe<&2, Code.Source>, value: String}
  Portal{key: String, target: String, children: +List<Node>}
  TargetProperties{key: String, target: String,
    attributes: +List<Property>, styles: +List<Property>}

type Document is Data:
  Document{root: Node, title: String}


def element_attributes(node: Node) -> +List<Property>:
  match node:
    case Element{key, tag, attributes, styles, events, children}: attributes
    case _: Nil{}

def element_styles(node: Node) -> +List<Property>:
  match node:
    case Element{key, tag, attributes, styles, events, children}: styles
    case _: Nil{}

def element_events(node: Node) -> +List<Event>:
  match node:
    case Element{key, tag, attributes, styles, events, children}: events
    case _: Nil{}

def element_children(node: Node) -> +List<Node>:
  match node:
    case Element{key, tag, attributes, styles, events, children}: children
    case _: Nil{}

def direct_text(node: Node) -> String:
  match node:
    case Text{value}: value
    case _: ""
