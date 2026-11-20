From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Utf8.
From Selvedge.Programming Require ArgumentDeclaration Schema.
From Selvedge.Kernel Require Codec Workspace.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Module D := ArgumentDeclaration.
Definition identifier := Workspace.environment_declaration.
Definition peer := D.Object [
 ("id",true,identifier); ("url",true,D.text);
 ("token_file",true,D.text); ("ca_file",false,D.text)].
Definition peers := D.BoundedArray 0 32 peer.
Definition endpoint_path := "/execution".
Definition admitted_endpoint (value : json) :=
 String.eqb (str value "protocol") "wss:" &&
 negb (String.eqb (str value "hostname") "") &&
 String.eqb (str value "pathname") endpoint_path &&
 String.eqb (str value "username") "" && String.eqb (str value "password") "" &&
 String.eqb (str value "search") "" && String.eqb (str value "hash") "".

Definition configuration source :=
 let value := get source "connections" in
 let connections := items value in
 let endpoints := items (get source "endpoints") in
 if negb (D.check peers value) then
   type_error "远程执行连接需要机器名称、连接地址和令牌文件路径。"
 else if negb (Schema.unique_names (map (fun connection => str connection "id") connections)) then
   type_error "远程执行连接的机器名称需要唯一。"
 else if negb (forallb (fun connection => Utf8.nonblank (str connection "token_file")) connections) then
   type_error "请填写令牌文件路径。"
 else if Nat.eqb (List.length connections) (List.length endpoints) && forallb admitted_endpoint endpoints then
   success value
 else type_error "连接地址应为 wss://主机:端口/execution。".

Definition execution := D.Object [
 ("workspace",true,Codec.workspace_declaration); ("resource",true,D.Const JNull);
 ("sandbox",true,Codec.sandbox_declaration);
 ("scope",false,D.Const (JString "project"));
 ("access",true,D.Value (Selvedge.Programming.Schema.KEnum "sandboxed" ["unrestricted"]))].
Definition operation := [("operation_id",true,identifier)].
Definition start := D.Object (operation ++ [
 ("tool",true,D.Value (Selvedge.Programming.Schema.KEnum "bash" ["read_image"]));
 ("arguments",true,D.RawObject); ("execution",true,execution)]).
Definition handle := D.Object operation.
Definition read_output := D.Object (operation ++ [("cursor",true,D.text)]).
Definition write_input := D.Object (operation ++ [("input",true,D.RawObject)]).
Definition file_path := D.Object [("path",true,Workspace.path_declaration)].
Definition file_read := D.Object [("path",true,Workspace.path_declaration);
 ("maximum",true,D.Natural 0 16777216)].
Definition directory_list := D.Object [("path",true,Workspace.path_declaration);
 ("maximum",true,D.Natural 1 32768)].
Definition methods : list (string * D.t) := [
 ("execution.start",start); ("execution.read",read_output); ("execution.write",write_input);
 ("execution.wait",handle); ("execution.cancel",handle);
 ("execution.realpath",file_path); ("execution.stat",file_path); ("execution.lstat",file_path);
 ("execution.readdir",directory_list); ("execution.read_file",file_read)].
Definition request_branch (entry : string * D.t) :=
 D.Object [("id",true,identifier);("method",true,D.Const (JString (fst entry)));
           ("params",true,snd entry)].
Definition request := D.Union (map request_branch methods).
Definition response := D.Union [
 D.Object [("id",true,identifier);("result",true,D.Any)];
 D.Object [("id",true,identifier);("error",true,D.Object
  [("code",true,identifier);("message",true,D.text)])];
 D.Object [("method",true,D.Const (JString "execution.output"));("params",true,
   D.Object (operation ++ [("output",true,D.text)]))]].
Definition admit (declaration : D.t) source :=
 if D.check declaration source then success source else type_error "Invalid shared execution message".

(** A committed reservation is durable before launch. An equal replay gets the
    existing result; a conflicting replay cannot dispatch anything. *)
Definition start_action (recorded : bool) (previous incoming : json) :=
 if negb recorded then "reserve" else match previous with
 | JNull => "cancelled"
 | _ => if Json.equal previous incoming then "observe" else "conflict"
 end.
