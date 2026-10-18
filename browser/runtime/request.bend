import Base
import ../../bendlib/json.bend as J

def kept_field(owned: Bool, field: J.Field, rest: +List<J.Field>) -> +List<J.Field>:
  match owned:
    case True{}: rest
    case False{}: field <> rest

def without_guidance(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+name, value}, rest}:
      kept_field(String.eq(name, "guidance"), J.Field{name, value}, without_guidance(rest))

def settings_value(value: J.Json) -> J.Json:
  match value:
    case J.Object{fields}: J.Object{without_guidance(fields)}
    case other: other

def settings_field(selected: Bool, name: String, value: J.Json) -> J.Field:
  match selected:
    case True{}: J.Field{name, settings_value(value)}
    case False{}: J.Field{name, value}

def settings_fields(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+name, value}, rest}:
      settings_field(String.eq(name, "settings"), name, value) <> settings_fields(rest)

type ObjectRequestName is Data:
  ObjectRequestNameCreate{}
  ObjectRequestNameCreateProject{}
  ObjectRequestNameOther{}

def object_request_discriminant(+value: String) -> ObjectRequestName:
  Bool.pick(ObjectRequestName, String.eq(value, "create"), ObjectRequestNameCreate{},
    Bool.pick(ObjectRequestName, String.eq(value, "create_worktree_task"), ObjectRequestNameCreate{},
    Bool.pick(ObjectRequestName, String.eq(value, "fork"), ObjectRequestNameCreate{},
    Bool.pick(ObjectRequestName, String.eq(value, "save_board_agent"), ObjectRequestNameCreate{},
    Bool.pick(ObjectRequestName, String.eq(value, "create_project"), ObjectRequestNameCreateProject{},
    Bool.pick(ObjectRequestName, String.eq(value, "update_project"), ObjectRequestNameCreateProject{},
    ObjectRequestNameOther{}))))))

def object_request_classified(op: ObjectRequestName, fields: +List<J.Field>) -> J.Json:
  match op:
    case ObjectRequestNameCreate{}: J.Object{settings_fields(fields)}
    case ObjectRequestNameCreateProject{}: J.Object{without_guidance(fields)}
    case ObjectRequestNameOther{}: J.Object{fields}

def object_request(op: String, fields: +List<J.Field>) -> J.Json:
  object_request_classified(object_request_discriminant(op), fields)

def client(value: J.Json) -> J.Json:
  match value:
    case J.Object{+fields}: object_request(J.text(J.get(J.Object{fields}, "op")), fields)
    case other: other
