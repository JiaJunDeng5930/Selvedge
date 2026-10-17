import Base
import ./MODEL.bend as R
import ../../bendlib/json.bend as J
import ../../bendlib/string-equality.bend as Text

type AdminKind is Data:
  EnableKind{}
  DisableKind{}
  GrantKind{}
  RevokeKind{}
  StatusKind{}

type Spec is Data:
  Spec{name: String, description: String, kind: AdminKind, schema: J.Json}

def object_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{properties}},
    J.Field{"required", J.Array{required}}, J.Field{"additionalProperties", J.Boolean{False{}}}]}

def bool_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"boolean"}}]}

def id_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"minLength", J.nat(1n)}, J.Field{"maxLength", J.nat(128n)}]}

def rights_schema() -> J.Json:
  object_schema([J.Field{"read", bool_schema()}, J.Field{"control", bool_schema()},
    J.Field{"configure", bool_schema()}, J.Field{"approve", bool_schema()}],
    [J.Text{"read"}, J.Text{"control"}, J.Text{"configure"}, J.Text{"approve"}])

def schema(kind: AdminKind) -> J.Json:
  match kind:
    case GrantKind{}: object_schema([J.Field{"op", id_schema()}, J.Field{"controller_id", id_schema()},
      J.Field{"permissions", rights_schema()}], [J.Text{"op"}, J.Text{"controller_id"}, J.Text{"permissions"}])
    case RevokeKind{}: object_schema([J.Field{"op", id_schema()}, J.Field{"controller_id", id_schema()}], [J.Text{"op"}, J.Text{"controller_id"}])
    case _: object_schema([J.Field{"op", id_schema()}], [J.Text{"op"}])

def specs() -> +List<Spec>:
  [Spec{"remote_enable", "Enable locally granted remote controllers; administrative access only.", EnableKind{}, schema(EnableKind{})},
   Spec{"remote_disable", "Disable remote control immediately without cancelling local tasks; administrative access only.", DisableKind{}, schema(DisableKind{})},
   Spec{"remote_grant", "Grant or replace one remote controller's permissions and issue a fresh grant generation; administrative access only.", GrantKind{}, schema(GrantKind{})},
   Spec{"remote_revoke", "Revoke one remote controller and remove its retained command receipts; administrative access only.", RevokeKind{}, schema(RevokeKind{})},
   Spec{"remote_status", "Read local remote-control status and granted controllers; administrative access only.", StatusKind{}, schema(StatusKind{})}]

def field_count(fields: +List<J.Field>) -> Nat:
  match fields:
    case Nil{}: 0n
    case Con{field, rest}: 1n+field_count(rest)

def counted(same: Bool, rest: Nat) -> Nat:
  match same:
    case True{}: 1n+rest
    case False{}: rest

def name_count(fields: +List<J.Field>, +name: String) -> Nat:
  match fields:
    case Nil{}: 0n
    case Con{J.Field{key, value}, rest}: counted(Text.string_equal(key, name), name_count(rest, name))

def names_count(names: +List<String>) -> Nat:
  match names:
    case Nil{}: 0n
    case Con{name, rest}: 1n+names_count(rest)

def names_once(names: +List<String>, +fields: +List<J.Field>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{name, rest}: Nat.is_eq(name_count(fields, name), 1n) && names_once(rest, fields)

def exact_keys(value: J.Json, +names: +List<String>) -> Bool:
  match value:
    case J.Object{+fields}: Nat.is_eq(field_count(fields), names_count(names)) && names_once(names, fields)
    case _: False{}

def is_bool(value: J.Json) -> Bool:
  match value:
    case J.Boolean{boolean}: True{}
    case _: False{}

def is_natural(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{number}: True{}
    case None{}: False{}

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def rights_valid(+value: J.Json) -> Bool:
  exact_keys(value, ["read", "control", "configure", "approve"]) &&
    is_bool(J.get(value, "read")) && is_bool(J.get(value, "control")) &&
    is_bool(J.get(value, "configure")) && is_bool(J.get(value, "approve"))

def rights(+value: J.Json) -> R.Rights:
  R.Rights{J.boolean(J.get(value, "read")), J.boolean(J.get(value, "control")),
    J.boolean(J.get(value, "configure")), J.boolean(J.get(value, "approve"))}

def valid(kind: AdminKind, +body: J.Json) -> Bool:
  match kind:
    case GrantKind{}: exact_keys(body, ["op", "controller_id", "permissions"]) && J.is_text(J.get(body, "op")) &&
      J.is_text(J.get(body, "controller_id")) && R.identifier_valid(J.text(J.get(body, "controller_id"))) && rights_valid(J.get(body, "permissions"))
    case RevokeKind{}: exact_keys(body, ["op", "controller_id"]) && J.is_text(J.get(body, "op")) &&
      J.is_text(J.get(body, "controller_id")) && R.identifier_valid(J.text(J.get(body, "controller_id")))
    case _: exact_keys(body, ["op"]) && J.is_text(J.get(body, "op"))

def construct(kind: AdminKind, +body: J.Json) -> R.Admin:
  match kind:
    case EnableKind{}: R.Enable{}
    case DisableKind{}: R.Disable{}
    case GrantKind{}: R.GrantDevice{J.text(J.get(body, "controller_id")), rights(J.get(body, "permissions"))}
    case RevokeKind{}: R.RevokeDevice{J.text(J.get(body, "controller_id"))}
    case StatusKind{}: R.Status{}

def command_json(command: R.Admin) -> J.Json:
  match command:
    case R.Enable{}: J.Object{[J.Field{"op", J.Text{"remote_enable"}}]}
    case R.Disable{}: J.Object{[J.Field{"op", J.Text{"remote_disable"}}]}
    case R.GrantDevice{controller, permissions}: J.Object{[J.Field{"op", J.Text{"remote_grant"}},
      J.Field{"controller_id", J.Text{controller}}, J.Field{"permissions", R.rights_json(permissions)}]}
    case R.RevokeDevice{controller}: J.Object{[J.Field{"op", J.Text{"remote_revoke"}}, J.Field{"controller_id", J.Text{controller}}]}
    case R.Status{}: J.Object{[J.Field{"op", J.Text{"remote_status"}}]}

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def grant(+value: J.Json) -> R.Grant:
  R.Grant{J.text(J.get(value, "controller_id")), number(J.get(value, "grant_epoch")), rights(J.get(value, "permissions"))}

def grants(values: +List<J.Json>) -> +List<R.Grant>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: grant(value) <> grants(rest)

def grant_shape(+value: J.Json) -> Bool:
  exact_keys(value, ["controller_id", "grant_epoch", "permissions"]) && J.is_text(J.get(value, "controller_id")) &&
    is_natural(J.natural(J.get(value, "grant_epoch"))) && rights_valid(J.get(value, "permissions"))

def grants_shape(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{value, rest}: grant_shape(value) && grants_shape(rest)

def receipt(+value: J.Json) -> R.Receipt:
  R.Receipt{J.text(J.get(value, "controller_id")), number(J.get(value, "grant_epoch")),
    J.text(J.get(value, "request_id")), J.get(value, "intent"), J.get(value, "reply")}

def receipts(values: +List<J.Json>) -> +List<R.Receipt>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: receipt(value) <> receipts(rest)

def receipt_shape(+value: J.Json) -> Bool:
  exact_keys(value, ["controller_id", "grant_epoch", "request_id", "intent", "reply"]) &&
    J.is_text(J.get(value, "controller_id")) && is_natural(J.natural(J.get(value, "grant_epoch"))) && J.is_text(J.get(value, "request_id"))

def receipts_shape(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{value, rest}: receipt_shape(value) && receipts_shape(rest)

def receipt_json(value: R.Receipt) -> J.Json:
  R.Receipt{controller, epoch, key, intent, reply} = value
  J.Object{[J.Field{"controller_id", J.Text{controller}}, J.Field{"grant_epoch", J.nat(epoch)},
    J.Field{"request_id", J.Text{key}}, J.Field{"intent", intent}, J.Field{"reply", reply}]}

def receipts_json(values: +List<R.Receipt>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: receipt_json(value) <> receipts_json(rest)

def state_json(value: R.State) -> J.Json:
  R.State{enabled, grants, next, receipts} = value
  J.Object{[J.Field{"enabled", J.Boolean{enabled}}, J.Field{"grants", J.Array{R.grants_json(grants)}},
    J.Field{"next_epoch", J.nat(next)}, J.Field{"receipts", J.Array{receipts_json(receipts)}}]}

def state(+value: J.Json) -> R.State:
  R.State{J.boolean(J.get(value, "enabled")), grants(J.items(J.get(value, "grants"))),
    number(J.get(value, "next_epoch")), receipts(J.items(J.get(value, "receipts")))}

def state_valid(+value: J.Json) -> Bool:
  exact_keys(value, ["enabled", "grants", "next_epoch", "receipts"]) && is_bool(J.get(value, "enabled")) &&
    is_array(J.get(value, "grants")) && grants_shape(J.items(J.get(value, "grants"))) &&
    is_natural(J.natural(J.get(value, "next_epoch"))) && is_array(J.get(value, "receipts")) &&
    receipts_shape(J.items(J.get(value, "receipts"))) && R.valid(state(value))

def request(+value: J.Json) -> R.Request:
  R.Request{J.text(J.get(value, "controller_id")), number(J.get(value, "grant_epoch")),
    J.text(J.get(value, "request_id")), J.get(value, "intent")}

def request_valid(+value: J.Json) -> Bool:
  exact_keys(value, ["controller_id", "grant_epoch", "request_id", "intent"]) && J.is_text(J.get(value, "controller_id")) &&
    is_natural(J.natural(J.get(value, "grant_epoch"))) && J.is_text(J.get(value, "request_id")) && R.request_valid(request(value))
