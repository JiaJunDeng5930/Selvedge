import Base
import ./MODEL.bend as Editor
import ./skill-mention.bend as Mention
import ../document/MODEL.bend as Doc

type Choice is Data:
  Choice{field: String, index: Nat}

def path_identity(path: String) -> String:
  match path:
    case "": ""
    case SCon{char, rest}: U32.show(Char.to_u32(char)) ++ "-" ++ path_identity(rest)

def option_key(field: String, index: Nat, skill: Mention.Skill) -> String:
  Mention.Skill{name, description, path} = skill
  "@skill-option/" ++ field ++ "/" ++ path_identity(path) ++ "/" ++ Nat.show(index)

def list_key(field: String) -> String:
  "@skill-list/" ++ field

def property(name: String, value: String) -> Doc.Property:
  Doc.Property{name, value}

def option(+field: String, +index: Nat, +selected: Bool, +skill: Mention.Skill) -> Doc.Node:
  Mention.Skill{name, description, path} = skill
  +key = option_key(field, index, skill)
  Doc.Element{key, "button", [property("id", key), property("type", "button"), property("role", "option"), property("tabindex", "-1"),
    property("aria-selected", Bool.pick(String, selected, "true", "false")), property("data-retain-focus", "true"),
    property("data-reveal-on-layout", Bool.pick(String, selected, "true", "false"))],
    [property("display", "flex"), property("flex-direction", "column"), property("gap", "2px"), property("width", "100%"),
      property("padding", "8px 12px"), property("text-align", "left"), property("border", "0"), property("border-radius", "6px"),
      property("background", Bool.pick(String, selected, "var(--color-token-main-surface-tertiary)", "transparent")), property("cursor", "pointer")],
    [Doc.Activate{key}],
    [Doc.Element{key ++ "/name", "strong", Nil{}, [property("font-size", "14px")], Nil{}, [Doc.Text{name}]},
      Doc.Element{key ++ "/description", "span", Nil{}, [property("font-size", "12px"), property("overflow", "hidden"), property("text-overflow", "ellipsis"), property("white-space", "nowrap"), property("max-width", "100%")], Nil{}, [Doc.Text{description}]},
      Doc.Element{key ++ "/path", "span", Nil{}, [property("font-size", "11px"), property("color", "var(--color-token-text-secondary)"), property("overflow-wrap", "anywhere")], Nil{}, [Doc.Text{path}]}]}

def options(skills: +List<Mention.Skill>, +field: String, +selected: Nat, +index: Nat) -> +List<Doc.Node>:
  match skills:
    case Nil{}: Nil{}
    case Con{skill, rest}: option(field, index, Nat.is_eq(selected, index), skill) <> options(rest, field, selected, (index + 1n : Nat))

def empty_message(status: Mention.CatalogStatus) -> String:
  match status:
    case Mention.Unrequested{}: "Loading skills…"
    case Mention.Loading{}: "Loading skills…"
    case Mention.Failed{reason}: "Could not load skills: " ++ reason
    case Mention.Ready{}: "No matching skills"

def menu_content(skills: +List<Mention.Skill>, field: String, selected: Nat, status: Mention.CatalogStatus) -> +List<Doc.Node>:
  match skills:
    case Nil{}: [Doc.Element{list_key(field) ++ "/empty", "div", [property("role", "status")], [property("padding", "10px 12px"), property("font-size", "13px")], Nil{}, [Doc.Text{empty_message(status)}]}]
    case values: options(values, field, selected, 0n)

def active_id(active: Maybe<&2, Mention.Skill>, field: String, selected: Nat) -> String:
  match active:
    case None{}: ""
    case Some{skill}: option_key(field, selected, skill)

def binding(+state: Mention.State) -> Doc.Node:
  Mention.State{+field, trigger, dismissed, +selected, skills, workspace, generation, status} = state
  Doc.TargetProperties{"@skill-binding/" ++ field, field,
    [property("role", "combobox"), property("aria-autocomplete", "list"), property("aria-expanded", Bool.pick(String, Mention.open(state), "true", "false")),
      property("aria-controls", Bool.pick(String, Mention.open(state), list_key(field), "")), property("aria-activedescendant", active_id(Mention.active(state), field, selected))],
    [property("anchor-name", Bool.pick(String, Mention.open(state), "--selvedge-skill-composer", "none"))]}

def popup(+state: Mention.State) -> Doc.Node:
  Mention.State{+field, trigger, dismissed, selected, skills, workspace, generation, status} = state
  Doc.Element{list_key(field), "div", [property("id", list_key(field)), property("role", "listbox"), property("aria-label", "Skills")],
    [property("position", "fixed"), property("position-anchor", "--selvedge-skill-composer"), property("position-try-fallbacks", "flip-block"),
      property("left", "anchor(left, 16px)"), property("bottom", "anchor(top, 96px)"), property("margin-bottom", "6px"),
      property("width", "anchor-size(width, min(32rem, calc(100vw - 32px)))"), property("max-width", "calc(100vw - 24px)"),
      property("max-height", "min(18rem, 45vh)"), property("overflow-y", "auto"), property("padding", "4px"), property("z-index", "1000"),
      property("border", "1px solid var(--color-token-border-light)"), property("border-radius", "10px"),
      property("background", "var(--color-token-main-surface-primary)"), property("color", "var(--color-token-text-primary)"),
      property("box-shadow", "0 6px 24px #0002")], Nil{}, menu_content(Mention.candidates(state), field, selected, status)}

def menu(open: Bool, +state: Mention.State, binding: Doc.Node) -> +List<Doc.Node>:
  match open:
    case False{}: [binding]
    case True{}: [binding, popup(state)]

def has_editor_attribute(attributes: +List<Doc.Property>, +field: String) -> Bool:
  match attributes:
    case Nil{}: False{}
    case Con{Doc.Property{name, value}, rest}: (String.eq(name, "data-native-editor-key") && String.eq(value, field)) || has_editor_attribute(rest, field)

def has_editor_nodes(nodes: +List<Doc.Node>, +field: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{Doc.Element{key, tag, attributes, styles, events, children}, rest}:
      has_editor_attribute(attributes, field) || has_editor_nodes(children, field) || has_editor_nodes(rest, field)
    case Con{Doc.Portal{key, target, children}, rest}: has_editor_nodes(children, field) || has_editor_nodes(rest, field)
    case Con{other, rest}: has_editor_nodes(rest, field)

def has_editor(node: Doc.Node, field: String) -> Bool:
  has_editor_nodes([node], field)

def menu_if_present(present: Bool, +state: Mention.State) -> +List<Doc.Node>:
  match present:
    case False{}: Nil{}
    case True{}: menu(Mention.open(state), state, binding(state))

def overlays(editors: +List<Editor.Editor>, +root: Doc.Node) -> +List<Doc.Node>:
  match editors:
    case Nil{}: Nil{}
    case Con{Editor.Editor{owner, selection, composing, +mentions}, rest}:
      List.append(&2, Doc.Node, menu_if_present(has_editor(root, Mention.field(mentions)), mentions), overlays(rest, root))

def append(root: Doc.Node, nodes: +List<Doc.Node>) -> Doc.Node:
  match root:
    case Doc.Element{key, tag, attributes, styles, events, children}: Doc.Element{key, tag, attributes, styles, events, List.append(&2, Doc.Node, children, nodes)}
    case other: other

def document(editors: +List<Editor.Editor>, document: Doc.Document) -> Doc.Document:
  Doc.Document{+root, title} = document
  Doc.Document{append(root, overlays(editors, root)), title}

def choice_for(skills: +List<Mention.Skill>, +field: String, +key: String, +index: Nat) -> Maybe<&2, Choice>:
  match skills:
    case Nil{}: None{}
    case Con{skill, rest}:
      Bool.pick(Maybe<&2, Choice>, String.eq(key, option_key(field, index, skill)), Some{Choice{field, index}}, choice_for(rest, field, key, (index + 1n : Nat)))

def choice_in(open: Bool, +state: Mention.State, key: String) -> Maybe<&2, Choice>:
  match open:
    case False{}: None{}
    case True{}:
      +skills = Mention.candidates(state)
      choice_for(skills, Mention.field(state), key, 0n)

def first_choice(first: Maybe<&2, Choice>, rest: Maybe<&2, Choice>) -> Maybe<&2, Choice>:
  match first:
    case None{}: rest
    case Some{choice}: Some{choice}

def choice(editors: +List<Editor.Editor>, +key: String) -> Maybe<&2, Choice>:
  match editors:
    case Nil{}: None{}
    case Con{Editor.Editor{owner, selection, composing, +mentions}, rest}: first_choice(choice_in(Mention.open(mentions), mentions, key), choice(rest, key))
