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
Definition mcp_servers := D.BoundedArray 0 128 D.text.
Definition receiver_fields := [
 ("host",true,D.text); ("port",true,D.Natural 0 65535);
 ("cert_file",true,D.text); ("key_file",true,D.text); ("token_file",true,D.text);
 ("receipt_home",false,D.text);
 ("mcp_servers",true,mcp_servers)].
Definition receiver := D.Union [D.Const (JBool false); D.Object receiver_fields].
Definition mcp_import := D.Object [
 ("name",true,D.text); ("environment",true,identifier); ("server",true,D.text)].
Definition mcp_imports := D.BoundedArray 0 128 mcp_import.

Definition has_name name values := existsb (String.eqb name) values.
Definition exported_mcp (exports : list json) name := has_name name (map text exports).

Definition mcp_configuration source :=
 let listener := get source "receiver" in
 let imports := get source "imports" in
 let local := map fst (object_fields (get source "mcp")) in
 let environments := map (fun peer => str peer "id") (items (get source "connections")) in
 let exports := items (get listener "mcp_servers") in
 let names := map (fun entry => str entry "name") (items imports) in
 if negb (D.check receiver listener) then type_error "Invalid execution_receiver configuration"
 else if is_object listener &&
   negb (forallb (fun field => Utf8.nonblank (str listener field)) ["host";"cert_file";"key_file";"token_file"] &&
     (negb (has listener "receipt_home") || Utf8.nonblank (str listener "receipt_home")))
 then type_error "Execution receiver needs a listen address and TLS and token file paths"
 else if negb (Schema.unique_names (map text exports) && forallb (fun server => has_name (text server) local) exports)
 then type_error "Execution receiver can export only distinct local MCP servers"
 else if negb (D.check mcp_imports imports) then type_error "Invalid shared_mcp configuration"
 else if negb (Schema.unique_names (local ++ names)%list)
 then type_error "Shared and local MCP server names must be unique"
 else if negb (forallb (fun entry => Utf8.nonblank (str entry "name") &&
      Utf8.nonblank (str entry "server") && has_name (str entry "environment") environments) (items imports))
 then type_error "Shared MCP needs a name, a configured execution environment and a server name"
 else success JNull.

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

Definition task_owner := ("task_id",true,D.Natural 0 9007199254740991).
Definition local_worktree := ("backend",true,D.Const (JString "local")).
Definition execution := D.Object [
 ("workspace",true,Codec.workspace_declaration);
 ("resource",true,D.Union [D.Const JNull; D.Object [task_owner;local_worktree]]);
 ("sandbox",true,Codec.sandbox_declaration);
 ("scope",false,D.Const (JString "project"));
 ("access",true,D.Value (Selvedge.Programming.Schema.KEnum "sandboxed" ["unrestricted"]))].
Definition operation := [("operation_id",true,identifier)].
Definition workspace_start := D.Object (operation ++ [
 ("tool",true,D.Value (Selvedge.Programming.Schema.KEnum "bash" ["read_image"]));
 ("arguments",true,D.RawObject); ("execution",true,execution)]).
Definition mcp_start := D.Object (operation ++ [
 ("tool",true,D.Const (JString "mcp")); ("server",true,D.text);
 ("name",true,D.text); ("arguments",true,D.RawObject)]).
Definition worktree_source := [task_owner; ("source_root",true,Workspace.path_declaration)].
Definition worktree_effect := D.Union [
 D.Object ([("kind",true,D.Const (JString "worktree_create"));local_worktree;
   ("workspace",true,Codec.workspace_declaration)]++worktree_source);
 D.Object ([("kind",true,D.Const (JString "worktree_archive"));local_worktree;
   ("root",true,Workspace.path_declaration)]++worktree_source);
 D.Object ([("kind",true,D.Const (JString "worktree_recover"));
   ("status",true,D.Value (Schema.KEnum "creating" ["creating_archived";"archiving"]));
   ("root",true,D.Union [D.Const JNull;Workspace.path_declaration])]++worktree_source)].
Definition worktree_start := D.Object (operation ++ [
 ("tool",true,D.Const (JString "managed_worktree")); ("worktree",true,worktree_effect)]).
Definition start := D.Union [workspace_start; mcp_start; worktree_start].
Definition mcp_page := D.Object [("server",true,D.text);("cursor",false,D.text)].
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
 ("execution.mcp_servers",D.Object []); ("execution.mcp_list",mcp_page);
 ("execution.realpath",file_path); ("execution.stat",file_path); ("execution.lstat",file_path);
 ("execution.workspace_git",file_path);
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
   D.Object (operation ++ [("output",true,D.text)]))];
 D.Object [("method",true,D.Const (JString "execution.mcp_changed"));("params",true,
   D.Object [("server",true,D.text)])]].
Definition admit (declaration : D.t) source :=
 if D.check declaration source then success source else type_error "Invalid shared execution message".

(** A committed reservation is durable before launch. An equal replay gets the
    existing result; a conflicting replay cannot dispatch anything. *)
Definition start_action (recorded : bool) (previous incoming : json) :=
 if negb recorded then "reserve" else match previous with
 | JNull => "cancelled"
 | _ => if Json.equal previous incoming then "observe" else "conflict"
 end.
