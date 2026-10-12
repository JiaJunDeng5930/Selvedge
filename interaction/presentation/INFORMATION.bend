# Semantic text roles are independent of application and browser representations.
type TextRole is Data:
  IntroductionTitle{}
  SurfaceTitle{}
  GroupTitle{}
  FieldLabel{}
  FieldValue{}
  OptionLabel{}
  Description{}
  Status{}

def name(role: TextRole) -> String:
  match role:
    case IntroductionTitle{}: "introduction-title"
    case SurfaceTitle{}: "surface-title"
    case GroupTitle{}: "group-title"
    case FieldLabel{}: "field-label"
    case FieldValue{}: "field-value"
    case OptionLabel{}: "option-label"
    case Description{}: "description"
    case Status{}: "status"
