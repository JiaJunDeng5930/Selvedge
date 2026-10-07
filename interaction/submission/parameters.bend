import Base

def label(name: String) -> String:
  match name:
    case "command": "Command"
    case "justification": "Reason"
    case other: other
