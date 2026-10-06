import Base

type Context is Data:
  Context{task: Nat, generation: Nat}

type Part is Data:
  Scroll{}
  Content{}
  Dock{}

type Binding is Data:
  Binding{context: Context, part: Part}

def part_name(part: Part) -> String:
  match part:
    case Scroll{}: "scroll"
    case Content{}: "content"
    case Dock{}: "dock"
