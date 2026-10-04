import Base

type TextTone is Data:
  PrimaryText{}
  SecondaryText{}

type Tone is Data:
  Neutral{}
  Warning{}
  Success{}
  Info{}
  Danger{}

type Role is Data:
  Canvas{}
  Navigation{}
  Content{}
  Floating{}
  Inset{}
  Field{}
  EmbeddedField{}
  EmbeddedAction{}
  QuietAction{}
  PrimaryAction{}
  DestructiveAction{}
  Choice{selected: Bool}
  Lane{tone: Tone}
  Chip{tone: Tone}

type Phase is Data:
  Rest{}
  Hovered{}
  Pressed{}

type Color is Data:
  Clear{}
  Token{name: String}
  Blend{foreground: String, percent: Nat, background: String}

def text_token(value: TextTone) -> String:
  match value:
    case PrimaryText{}: "--color-token-text-primary"
    case SecondaryText{}: "--color-token-text-secondary"

def text_foreground(value: TextTone) -> Color:
  Token{text_token(value)}

def tone_name(value: Tone) -> String:
  match value:
    case Neutral{}: text_token(SecondaryText{})
    case Warning{}: "--color-text-warning"
    case Success{}: "--color-text-success"
    case Info{}: "--color-text-info"
    case Danger{}: "--color-text-danger"

def tone(value: Tone) -> Color:
  Token{tone_name(value)}

def foreground(role: Role) -> Color:
  match role:
    case PrimaryAction{}: Token{"--color-text-primary-solid"}
    case DestructiveAction{}: Token{"--color-text-danger-ghost"}
    case Chip{value}: tone(value)
    case _: text_foreground(PrimaryText{})

def action_background(phase: Phase, rest: String, hover: String, pressed: String) -> Color:
  match phase:
    case Rest{}: Token{rest}
    case Hovered{}: Token{hover}
    case Pressed{}: Token{pressed}

def destructive_background(phase: Phase) -> Color:
  match phase:
    case Rest{}: Clear{}
    case Hovered{}: Token{"--color-background-danger-ghost-hover"}
    case Pressed{}: Token{"--color-background-danger-ghost-active"}

def choice_background(selected: Bool, phase: Phase) -> Color:
  match selected phase:
    case False{} Rest{}: Clear{}
    case False{} Hovered{}: Token{"--color-token-list-hover-background"}
    case True{} Rest{}: Token{"--color-background-segmented-selected"}
    case True{} Hovered{}: Token{"--color-background-segmented-selected-hover"}
    case _ Pressed{}: Token{"--app-color-background-button-tertiary-active"}

def lane_background(value: Tone) -> Color:
  match value:
    case Neutral{}: Token{"--color-surface-secondary"}
    case other: Blend{tone_name(other), 7n, "--color-surface-secondary"}

def background(+role: Role, phase: Phase) -> Color:
  match role:
    case Canvas{}: Token{"--app-color-background-surface"}
    case Navigation{}: Token{"--color-token-side-bar-background"}
    case Content{}: Token{"--color-token-main-surface-primary"}
    case Floating{}: Token{"--color-token-dropdown-background"}
    case Inset{}: Token{"--color-surface-secondary"}
    case Field{}: Token{"--color-token-main-surface-primary"}
    case EmbeddedField{}: Clear{}
    case EmbeddedAction{}: Clear{}
    case QuietAction{}: action_background(phase, "--app-color-background-button-tertiary",
      "--app-color-background-button-tertiary-hover", "--app-color-background-button-tertiary-active")
    case PrimaryAction{}: action_background(phase, "--color-background-primary-solid",
      "--color-background-primary-solid-hover", "--color-background-primary-solid-active")
    case DestructiveAction{}: destructive_background(phase)
    case Choice{selected}: choice_background(selected, phase)
    case Lane{value}: lane_background(value)
    case Chip{value}: Blend{tone_name(value), 9n, "--color-surface-secondary"}
