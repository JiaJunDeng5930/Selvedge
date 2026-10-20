From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
From Selvedge.Kernel Require Import Commands ChatgptArguments.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Inductive route := Projects | Project | Execute | Operation | Operations | Cancel | Forget.
Definition routes := [Projects;Project;Execute;Operation;Operations;Cancel;Forget].
Definition public_name route := match route with
  | Projects => "list_projects" | Project => "get_project" | Execute => "exec"
  | Operation => "get_operation" | Operations => "list_operations"
  | Cancel => "cancel_operation" | Forget => "forget_operation" end.
Definition native_name route := match route with
  | Projects => "chatgpt_projects" | Project => "chatgpt_project" | Execute => "chatgpt_exec"
  | Operation => "chatgpt_operation" | Operations => "chatgpt_operations"
  | Cancel => "chatgpt_cancel" | Forget => "chatgpt_forget" end.
Definition find_route name := find (fun r => String.eqb name (public_name r)) routes.
Definition readonly route := match route with Projects | Project | Operation | Operations => true | _ => false end.
Definition destructive route := negb (readonly route).
Definition idempotent route := match route with Cancel => true | _ => readonly route end.
Definition open_world route := match route with Execute => true | _ => false end.
Definition identity_maximum := ChatgptArguments.identity_maximum.
Definition argument_declaration := ChatgptArguments.argument_declaration.
Definition bounds := ChatgptArguments.bounds.
Definition bounded_property := ChatgptArguments.bounded_property.
Definition args_schema := ChatgptArguments.args_schema.
Definition bounded_number := ChatgptArguments.bounded_number.
Definition admit_args := ChatgptArguments.admit_args.
Definition valid_args := ChatgptArguments.valid_args.
Definition native_fields route := match find (fun spec => String.eqb spec.(command_name) (native_name route)) command_specs with
  | Some declaration => declaration.(command_fields) | None => [] end.
Definition client_fields route := filter (fun f => negb (String.eqb f.(field_name) "connection_id" ||
  String.eqb f.(field_name) "arguments")) (native_fields route).
Definition id_property field :=
  let properties := kind_schema field.(field_kind) in
  JObject (if String.eqb field.(field_name) "request_id" then properties else
    set_field "maximum" (JNumber (show_natural identity_maximum)) properties).
Definition client_schema route :=
  let base := map (fun f => (f.(field_name),id_property f)) (client_fields route) in
  let required := map field_name (client_fields route) in
  match route with Execute => object_schema (base ++ map (fun f => (f.(field_name),JObject (
      match bounded_property f with JObject fs => fs | _ => [] end ++
      if String.eqb f.(field_name) "timeout_ms" then [("default",JNumber (show_natural ChatgptArguments.default_timeout_ms))]
      else if String.eqb f.(field_name) "max_output_length" then [("default",JNumber (show_natural ChatgptArguments.default_max_output_length))] else []))) argument_declaration)
      (required ++ ["command"])
  | _ => object_schema base required end.
Definition client_keys route := map field_name (client_fields route) ++
  match route with Execute => map field_name argument_declaration | _ => [] end.
