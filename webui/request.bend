import Base
import ../bendlib/json.bend as J

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

def object_request(op: String, fields: +List<J.Field>) -> J.Json:
  match op:
    case "create": J.Object{settings_fields(fields)}
    case "fork": J.Object{settings_fields(fields)}
    case "save_board_agent": J.Object{settings_fields(fields)}
    case "create_project": J.Object{without_guidance(fields)}
    case "update_project": J.Object{without_guidance(fields)}
    case _: J.Object{fields}

def client(value: J.Json) -> J.Json:
  match value:
    case J.Object{+fields}: object_request(J.text(J.get(J.Object{fields}, "op")), fields)
    case other: other
