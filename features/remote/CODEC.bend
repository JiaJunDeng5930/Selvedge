import Base
import ./MODEL.bend as R
import ../../bendlib/json.bend as J

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

def rights(+value: J.Json) -> R.Rights:
  R.Rights{J.boolean(J.get(value, "read")), J.boolean(J.get(value, "control")),
    J.boolean(J.get(value, "configure")), J.boolean(J.get(value, "approve"))}

# Structural fields and permission Booleans are admitted by the shared wire schema.
# Controller identifiers additionally obey the domain's UTF-8 byte limit.
def additional_constraints(kind: AdminKind, body: J.Json) -> Bool:
  match kind:
    case GrantKind{}: R.identifier_valid(J.text(J.get(body, "controller_id")))
    case RevokeKind{}: R.identifier_valid(J.text(J.get(body, "controller_id")))
    case _: True{}

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
