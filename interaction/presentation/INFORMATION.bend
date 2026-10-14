# Semantic text roles are independent of application and browser representations.
type TextRole is Data:
  IntroductionTitle{}
  SurfaceTitle{}
  GroupTitle{}
  NavigationCaption{}
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
    case NavigationCaption{}: "navigation-caption"
    case FieldLabel{}: "field-label"
    case FieldValue{}: "field-value"
    case OptionLabel{}: "option-label"
    case Description{}: "description"
    case Status{}: "status"
