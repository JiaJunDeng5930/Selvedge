From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import SchemaJson Utf8.
From Selvedge.Programming Require Import Arguments.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Programming Require CommandDeclarations.
From Selvedge.Kernel Require CommandDeclarations.
From Selvedge.Kernel Require Import ChatgptArguments.
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
Definition native_arguments route := match Selvedge.Kernel.CommandDeclarations.declaration_for (native_name route) with
 | Some declaration => Selvedge.Programming.CommandDeclarations.command_arguments false declaration | None => [] end.
Definition client_arguments route := filter (fun argument => negb
 (existsb (String.eqb (argument_name argument)) ["op";"connection_id";"arguments"])) (native_arguments route).
Definition client_argument (property : string * bool * ArgumentDeclaration.t) :=
 let '(name,_,description) := property in
 let schema := ArgumentDeclaration.schema description in
 let annotation := if String.eqb name "timeout_ms" then Some ChatgptArguments.default_timeout_ms
   else if String.eqb name "max_output_length" then Some ChatgptArguments.default_max_output_length else None in
 (name,match annotation with
 | None => schema
 | Some value => JObject [("allOf",JArray [schema]);("default",JNumber (show_natural value))] end).
Definition client_schema route :=
  let base := map (fun argument => (argument_name argument,argument_json argument)) (client_arguments route) in
  let required := map argument_name (filter argument_required (client_arguments route)) in
  match route with Execute => object_schema (base ++ map client_argument ChatgptArguments.properties)
      (required ++ ["command"])
  | _ => object_schema base required end.
Definition client_keys route := map argument_name (client_arguments route) ++
  match route with Execute => map (fun property => fst (fst property)) ChatgptArguments.properties | _ => [] end.
