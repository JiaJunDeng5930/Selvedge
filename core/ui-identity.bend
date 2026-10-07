import Base
import ../bendlib/json.bend as J

type Key is Data:
  Place{path: String}
  Entity{owner: Key, kind: String, identity: String}
  Part{owner: Key, name: String}

def place(path: String) -> Key:
  Place{path}

def entity(owner: Key, kind: String, identity: String) -> Key:
  Entity{owner, kind, identity}

def part(owner: Key, name: String) -> Key:
  Part{owner, name}

def same(left: Key, right: Key) -> Bool:
  match left right:
    case Place{path} Place{other_path}: String.eq(path, other_path)
    case Entity{owner, kind, identity} Entity{other_owner, other_kind, other_identity}:
      same(owner, other_owner) && (String.eq(kind, other_kind) && String.eq(identity, other_identity))
    case Part{owner, name} Part{other_owner, other_name}:
      same(owner, other_owner) && String.eq(name, other_name)
    case _ _: False{}

# Tags and quoted fields preserve the boundary between an identity and its parts.
def encode(key: Key) -> String:
  match key:
    case Place{path}: "[\"place\",\"" ++ J.escape(path) ++ "\"]"
    case Entity{owner, kind, identity}:
      "[\"entity\"," ++ encode(owner) ++ ",\"" ++ J.escape(kind) ++ "\",\"" ++ J.escape(identity) ++ "\"]"
    case Part{owner, name}:
      "[\"part\"," ++ encode(owner) ++ ",\"" ++ J.escape(name) ++ "\"]"
