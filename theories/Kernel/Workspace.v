From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Schema Utf8 Numbers.
From Selvedge.Kernel Require Import Domain Numbers.
Import ListNotations.
Open Scope string_scope.
Definition valid_project_name (name : string) :=
 Utf8.nonblank name && Nat.leb (String.length name) 256.
Fixpoint contains (needle text : string) :=
 if String.prefix needle text then true else match text with EmptyString => false | String _ rest => contains needle rest end.
Definition valid_path (path : string) :=
 String.prefix "/" path && Nat.leb (String.length path) 4096 && Utf8.no_nul path &&
 negb (contains "/../" (String.append path "/")) && negb (contains "/./" (String.append path "/")) &&
 (String.eqb path "/" || negb (contains "//" (String.append path "/"))).
Definition workspace_schema := [Field "roots" (KArray KText); Field "primary_root" (KOptional KText)].
Definition valid_workspace (value : workspace) :=
 Nat.leb (List.length (workspace_roots value)) 32 &&
 Schema.unique_names (workspace_roots value) && forallb valid_path (workspace_roots value) &&
 match workspace_primary value, workspace_roots value with
 | None, [] => true
 | Some primary, roots => existsb (String.eqb primary) roots
 | _,_ => false end.
Definition root_within (root bound : string) :=
 String.eqb bound "/" || String.eqb root bound || String.prefix (String.append bound "/") root.
Definition workspace_bound (child parent : workspace) :=
 forallb (fun root => existsb (root_within root) (workspace_roots parent)) (workspace_roots child).
Definition approval_bound (child parent : approval_policy) :=
 match parent, child with
 | FullAccess,_ => true
 | AskForApproval, AskForApproval => true
 | ReviewWith _, AskForApproval => true
 | ReviewWith parent, ReviewWith child => Domain.same_profile child parent
 | _,_ => false end.
Definition same_resource (first second : option N) :=
 match first,second with None,None=>true | Some owner,Some other=>N.eqb owner other | _,_=>false end.
Definition writes_no_broader (child parent : sandbox) (child_space parent_space : workspace) :=
 match sandbox_access child, sandbox_access parent with
 | ReadOnly, _ => true
 | WorkspaceWrite, WorkspaceWrite => workspace_bound child_space parent_space
 | _, _ => false
 end.
(* FullAccess authorizes unrestricted delegation. Otherwise only write roots
   are bounded: selecting another read-only root does not confer write access. *)
Definition may_delegate (child parent : task_settings) :=
 match settings_approval parent with
 | FullAccess => true
 | approval =>
   (negb (sandbox_network (settings_sandbox child)) || sandbox_network (settings_sandbox parent)) &&
   writes_no_broader (settings_sandbox child) (settings_sandbox parent)
     (settings_workspace child) (settings_workspace parent) &&
   approval_bound (settings_approval child) approval
 end.

(* Stable registry positions are identities; the last registry edit controls
   presentation order independently of that identity. *)
Definition next_project_order (projects : list project) :=
 N.succ (fold_right (fun value order => N.max (project_order value) order) 0%N projects).
Fixpoint insert_project (entry : N * project) (entries : list (N * project)) :=
 match entries with
 | [] => [entry]
 | first :: rest => if N.leb (project_order (snd first)) (project_order (snd entry))
   then entry :: entries else first :: insert_project entry rest
 end.
Definition ordered_projects (projects : list project) :=
 fold_right insert_project []
  (filter (fun entry => negb (project_deleted (snd entry))) (Numbers.indexed pair 0 projects)).
