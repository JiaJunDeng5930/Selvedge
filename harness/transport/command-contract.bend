import Base
import ./command-codec.bend as Codec
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../../bendlib/json.bend as J

law approval_input_closed_shape:
  for +policy: D.ApprovalPolicy
  {Codec.approval_input(policy) == J.Object{[J.Field{"mode", J.Text{D.approval_name(policy)}},
    J.Field{"reviewer_profile", J.Text{D.reviewer_key(policy)}}]} : J.Json}

law configure_approval_input:
  for id: Nat
  for profile: String
  for reasoning: String
  for sandbox: D.Sandbox
  for +policy: D.ApprovalPolicy
  {J.get(Codec.command_json(M.ConfigureTaskExecution{id, profile, reasoning, sandbox, policy}), "approval") ==
    Codec.approval_input(policy) : J.Json}
