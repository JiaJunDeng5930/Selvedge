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
Definition args_schema := ChatgptArguments.args_schema.
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
Definition client_argument (property : string * bool * ArgumentDeclaration.t) :=
 let '(name,_,description) := property in
 let schema := ArgumentDeclaration.schema description in
 let annotation := if String.eqb name "timeout_ms" then Some ChatgptArguments.default_timeout_ms
   else if String.eqb name "max_output_length" then Some ChatgptArguments.default_max_output_length else None in
 (name,match annotation with
 | None => schema
 | Some value => JObject [("allOf",JArray [schema]);("default",JNumber (show_natural value))] end).
Definition client_schema route :=
  let base := map (fun f => (f.(field_name),id_property f)) (client_fields route) in
  let required := map field_name (client_fields route) in
  match route with Execute => object_schema (base ++ map client_argument ChatgptArguments.properties)
      (required ++ ["command"])
  | _ => object_schema base required end.
Definition client_keys route := map field_name (client_fields route) ++
  match route with Execute => map (fun property => fst (fst property)) ChatgptArguments.properties | _ => [] end.
