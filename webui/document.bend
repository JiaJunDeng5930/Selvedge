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
  SelectDestination{key: String}

type Node is Data:
  Element{key: String, tag: String, attributes: +List<Property>,
    styles: +List<Property>, events: +List<Event>, children: +List<Node>}
  Text{value: String}
  Markdown{key: String, source: Maybe<&2, Code.Source>, value: String, native_owner: Maybe<&2, String>}
  Portal{key: String, target: String, children: +List<Node>}
  TargetProperties{key: String, target: String,
    attributes: +List<Property>, styles: +List<Property>}

type Document is Data:
  Document{root: Node, title: String}
