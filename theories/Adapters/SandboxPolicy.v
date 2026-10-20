From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Utf8 TextJson.
From Selvedge.Adapters Require Import Common Observation Workspaces.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive filesystem_mode := ReadOnly | WorkspaceWrite.
(** A project-scoped unrestricted execution has no constructor. *)
Inductive execution_plan :=
| TaskSandbox (mode : filesystem_mode) (network : bool)
| TaskUnrestricted (mode : filesystem_mode) (network : bool)
| ProjectSandbox (mode : filesystem_mode) (network : bool).
Definition decode_plan (source : json) : option execution_plan :=
  let sandbox := get source "sandbox" in
  let mode := if String.eqb (str sandbox "mode") "read-only" then Some ReadOnly
    else if String.eqb (str sandbox "mode") "workspace-write" then Some WorkspaceWrite else None in
  match mode,as_bool (get sandbox "network_access") with
  | Some mode,Some network =>
    if is_object source then
      if has source "scope" then
        if String.eqb (str source "scope") "project" && String.eqb (str source "access") "sandboxed"
        then Some (ProjectSandbox mode network) else None
      else if String.eqb (str source "access") "sandboxed" then Some (TaskSandbox mode network)
      else if String.eqb (str source "access") "unrestricted" then Some (TaskUnrestricted mode network) else None
    else None
  | _,_ => None
  end.
Definition within (root : string) (parents : list json) (separator : string) :=
  existsb (fun parent => String.eqb root (text parent) || starts root (text parent ++ separator)) parents.
Definition strictly_within (root : string) (parents : list json) (separator : string) :=
  existsb (fun parent => starts root (text parent ++ separator)) parents.
Definition any_within (roots parents : list json) (separator : string) :=
  existsb (fun root => within (text root) parents separator) roots.
Definition paths_valid (paths : list json) := forallb Workspaces.path_valid paths.
Definition managed_writable_roots (source : json) :=
  let root := get source "managedWorktreeRoot" in
  filter (fun value => negb (is_null root) && within (text value) [root] (str source "separator"))
    (items (get source "writableRoots")).
Definition protected_workspace (source : json) :=
  if boolean_field source "projectOnly" && any_within (items (get (get source "workspace") "roots"))
    (items (get source "protectedRoots")) (str source "separator")
  then err "A ChatGPT Workspace cannot be inside the private service home" else success JNull.
Definition managed_worktree_admission (source : json) :=
  let root := get source "managedWorktreeRoot" in
  if equal root (get (get source "options") "managedWorktreeRoot") &&
    (is_null root || (paths_valid [root] && negb (boolean_field source "projectOnly") &&
      strictly_within (text root) (items (get source "protectedRoots")) (str source "separator") &&
      negb (any_within (items (get source "protectedRoots")) [root] (str source "separator")) &&
      within (str (get source "workspace") "primary_root") [root] (str source "separator")))
  then success JNull else err "Managed Worktree does not match its committed Workspace and private service home".
Definition removed_environment_name (name : string) :=
  existsb (String.eqb name) ["BASH_ENV";"ENV";"TMPDIR";"TMP";"TEMP";"HISTFILE"] || starts name "LD_" || starts name "DYLD_".
Definition environment (source : json) :=
  let scratch := get source "scratch" in let project := boolean_field source "projectOnly" in
  JObject [("names",JArray (if project then [] else filter (fun name => negb (removed_environment_name (text name))) (items (get source "names"))));
    ("overrides",JObject ((if project then [("PATH",JString (if String.eqb (str source "platform") "darwin"
      then "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" else "/usr/bin:/bin:/usr/sbin:/sbin"));("HOME",scratch)] else []) ++
      [("TMPDIR",scratch);("TMP",scratch);("TEMP",scratch);("HISTFILE",JString "/dev/null")] ++
      if project then [("LANG",JString "C");("TERM",JString "dumb");("GIT_CONFIG_NOSYSTEM",JString "1")] else []))].

Inductive architecture := X64 | Arm64.
Inductive filter_result := Allow | Kill | Deny | Unavailable.
Inductive comparison := Equal | GreaterOrEqual | HasBits.
Inductive instruction :=
| Load (offset : N)
| Return (result : filter_result)
| Jump (comparison : comparison) (operand yes no : N).
Record architecture_spec := ArchitectureSpec { audit_arch : N; socket_call : N; clone_call : N; denied_calls : list N }.
Definition architecture_policy (architecture : architecture) :=
  match architecture with
  | X64 => ArchitectureSpec 3221225534 41 56 [101;133;155;161;165;166;167;168;169;172;173;175;176;246;248;249;250;259;272;298;303;304;308;310;311;313;320;321;323]
  | Arm64 => ArchitectureSpec 3221225655 198 220 [33;39;40;41;51;97;104;105;106;117;142;217;218;219;224;225;241;264;265;268;270;271;273;280;282;294]
  end.
Definition return_code (result : filter_result) :=
  match result with Allow => 2147418112 | Kill => 2147483648 | Deny => 327681 | Unavailable => 327718 end.
Definition instruction_json (instruction : instruction) :=
  let '(code,yes,no,operand) := match instruction with
    | Load offset => (32,0,0,offset)
    | Return result => (6,0,0,return_code result)
    | Jump comparison operand yes no =>
      ((match comparison with Equal => 21 | GreaterOrEqual => 53 | HasBits => 69 end),yes,no,operand)
    end in
  JObject [("code",number code);("jt",number yes);("jf",number no);("k",number operand)].
Definition denied_program (syscall : N) := [Jump Equal syscall 0 1;Return Deny].
Definition socket_program (network : bool) (syscall : N) :=
  if network then [Jump Equal syscall 0 5;Load 16;Jump Equal 2 2 0;Jump Equal 10 1 0;Return Deny;Return Allow]
  else denied_program syscall.
Definition seccomp_program (architecture : architecture) (network : bool) : list instruction :=
  let policy := architecture_policy architecture in
  [Load 4;Jump Equal policy.(audit_arch) 1 0;Return Kill;Load 0] ++
  (match architecture with X64 => [Jump GreaterOrEqual 1073741824 0 1;Return Deny] | Arm64 => [] end) ++
  flat_map denied_program policy.(denied_calls) ++
  [Jump Equal 435 0 1;Return Unavailable;Jump Equal policy.(clone_call) 0 3;
    Load 16;Jump HasBits 2114060288 0 1;Return Deny;Load 0] ++
  socket_program network policy.(socket_call) ++ [Return Allow].
Definition seccomp (source : json) :=
  let name := str source "architecture" in
  let architecture := if String.eqb name "x64" then Some X64
    else if String.eqb name "arm64" then Some Arm64 else None in
  match architecture with
  | Some architecture => success (JArray (map instruction_json (seccomp_program architecture (boolean_field source "networkAccess"))))
  | None => err ("Linux sandbox does not support architecture " ++ name)
  end.

Definition binding (readonly : bool) (root : json) := JObject [("root",root);("readonly",JBool readonly)].
Definition bindings (source : json) := JArray
  (if boolean_field source "projectOnly" then
    map (binding (String.eqb (str (get (get source "plan") "sandbox") "mode") "read-only")) (items (get (get source "workspace") "roots")) ++
      [binding false (get source "scratch")]
  else map (binding false) (items (get source "writableRoots") ++ [get source "scratch"]) ++
    map (binding true) (items (get source "protectedRoots")) ++ map (binding false) (managed_writable_roots source)).
Definition runtime_candidates (platform : string) := JArray (map JString
  (if String.eqb platform "darwin" then
    ["/System/Library";"/System/Volumes/Preboot/Cryptexes/OS";"/usr/bin";"/usr/lib";"/usr/libexec";"/usr/share";
     "/bin";"/sbin";"/usr/sbin";"/opt/homebrew/bin";"/opt/homebrew/sbin";"/opt/homebrew/lib";"/opt/homebrew/opt";
     "/opt/homebrew/Cellar";"/opt/homebrew/share";"/Library/Developer/CommandLineTools";"/Library/Apple";
     "/private/etc/passwd";"/private/etc/group";"/private/etc/localtime";"/private/etc/hosts";"/private/etc/resolv.conf";
     "/private/etc/ssl/cert.pem";"/private/etc/ssl/certs";"/dev/null";"/dev/zero";"/dev/random";"/dev/urandom";"/dev/fd"]
  else ["/usr/bin";"/usr/sbin";"/usr/lib";"/usr/lib64";"/usr/libexec";"/usr/share";"/bin";"/sbin";"/lib";"/lib64";
     "/etc/ld.so.cache";"/etc/nsswitch.conf";"/etc/passwd";"/etc/group";"/etc/localtime";"/etc/hosts";"/etc/resolv.conf";"/etc/ssl/certs";"/etc/os-release"])).
Definition executable_candidates (platform : string) := JArray (map JString
  (if String.eqb platform "darwin" then ["/usr/bin/sandbox-exec"] else ["/usr/bin/bwrap";"/bin/bwrap"])).
Definition bind_arguments (entries : list json) := flat_map (fun entry =>
  [JString (if boolean_field entry "readonly" then "--ro-bind" else "--bind");
    JString ("/proc/self/fd/" ++ diagnostic (get entry "descriptor"));get entry "root"]) entries.
Definition linux_prefix (source : json) :=
  let project := boolean_field source "projectOnly" in
  JArray (map JString ["--die-with-parent";"--new-session";"--unshare-user";"--unshare-pid";"--unshare-ipc";"--unshare-uts";"--cap-drop";"ALL"] ++
    (if project then map JString ["--tmpfs";"/"] else map JString ["--ro-bind";"/";"/"]) ++
    (if boolean_field (get (get source "plan") "sandbox") "network_access" then [] else [JString "--unshare-net"]) ++
    (if project then flat_map (fun entry => [JString "--ro-bind";get entry "canonical";get entry "root"]) (items (get source "runtimeReads")) else []) ++
    bind_arguments (items (get source "bindings")) ++
    (if project then flat_map (fun root => [JString "--tmpfs";root;JString "--remount-ro";root]) (items (get source "protectedRoots")) else []) ++
    (map JString ["--proc";"/proc";"--dev";"/dev";"--seccomp";"3";"--chdir"] ++ [get source "cwd"] ++
      map JString ["--";"/bin/bash";"--noprofile";"--norc"])).
Definition darwin_prefix (source : json) := JArray [JString "-p";get source "profile";
  JString "/bin/bash";JString "--noprofile";JString "--norc"].
