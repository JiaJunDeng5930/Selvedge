From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Adapters Require Import Common Observation Workspaces SandboxPolicy.
Import ListNotations.
Open Scope string_scope.

Definition path_rule (kind : string) (path : json) := "(" ++ kind ++ " " ++ TextJson.quote (text path) ++ ")".
Definition path_rules (kind : string) (paths : list json) := map (path_rule kind) paths.
Definition protected_write_path (root : json) (exceptions : list json) :=
  match exceptions with
  | [] => path_rule "subpath" root
  | _ => "(require-all " ++ path_rule "subpath" root ++ " " ++
      String.concat " " (map (fun exception => "(require-not " ++ path_rule "subpath" exception ++ ")") exceptions) ++ ")"
  end.
Fixpoint protected_rules (roots ancestors : list json) (restricted : bool) (exceptions : list json) : list string :=
  match roots,ancestors with
  | root::rest,parents::tail =>
    ["(deny file-write* " ++ protected_write_path root exceptions ++ ")"] ++
    (if restricted then ["(deny file-read* " ++ path_rule "subpath" root ++ ")"] else []) ++
    map (fun parent => "(deny file-write-unlink " ++ path_rule "literal" parent ++ ")") (items parents) ++
    protected_rules rest tail restricted exceptions
  | _,_ => []
  end.
Definition unique_paths (values : list json) :=
  fold_left (fun seen value => if existsb (String.eqb (text value)) seen then seen else List.app seen [text value]) values [].
Definition read_rules (restricted : bool) (reads : list json) (ancestors : list string) : list string :=
  if restricted then ["(allow file-read-data (literal ""/""))";
    "(allow file-read* " ++ String.concat " " (path_rules "subpath" reads) ++ ")";
    "(allow file-read-metadata " ++ String.concat " " (map (fun parent => "(literal " ++ TextJson.quote parent ++ ")") ancestors) ++ ")"]
  else ["(allow file-read*)"].
Definition network_rules (network : bool) :=
  if network then ["(allow network-outbound (remote ip ""*:*""))";
    "(allow network-inbound (local ip ""*:*""))";
    "(allow mach-lookup (global-name ""com.apple.system.config.network_change"") (global-name ""com.apple.mDNSResponder"") (global-name ""com.apple.trustd.agent""))"] else [].
Definition rules (source : json) (writes reads : list json) : list string :=
  let restricted := has source "readableRoots" && negb (is_null (get source "readableRoots")) in
  ["(version 1)";"(deny default)";"(allow process-exec process-fork)";
    "(allow signal (target same-sandbox))";"(allow process-info* (target same-sandbox))"] ++
  read_rules restricted reads (unique_paths (flat_map items (items (get source "readAncestors")))) ++
  ["(allow sysctl-read)";"(allow mach-lookup (global-name ""com.apple.system.opendirectoryd.libinfo""))";
    "(allow ipc-posix-sem)";"(allow file-write-data (require-all (literal ""/dev/null"") (vnode-type CHARACTER-DEVICE)))";
    "(allow file-write*" ++ String (Ascii.ascii_of_nat 10) "  " ++
      String.concat (String (Ascii.ascii_of_nat 10) "  ") (path_rules "subpath" writes) ++ ")"] ++
  protected_rules (items (get source "readOnlyPaths")) (items (get source "protectedAncestors")) restricted (items (get source "readOnlyExceptions")) ++
  map (fun root => "(deny file-write-unlink " ++ path_rule "literal" root ++ ")") (items (get source "readOnlyExceptions")) ++
  network_rules (boolean_field source "networkAccess").
Definition seatbelt (source : json) :=
  let writes := List.app (items (get source "writableRoots")) [get source "scratch"] in
  let reads := List.app (items (get source "readableRoots")) [get source "scratch"] in
  if paths_valid writes && paths_valid (items (get source "readOnlyPaths")) &&
     paths_valid (items (get source "readOnlyExceptions")) && paths_valid reads
  then success (JString (String.concat (String (Ascii.ascii_of_nat 10) "") (rules source writes reads)))
  else type_error "Invalid sandbox path".
Definition seatbelt_input (source : json) := JObject
  ([("writableRoots",get source "writableRoots");("scratch",get source "scratch");
    ("readOnlyPaths",get source "protectedRoots");("readOnlyExceptions",JArray (managed_writable_roots source));
    ("networkAccess",get (get (get source "plan") "sandbox") "network_access")] ++
    if boolean_field source "projectOnly" then [("readableRoots",JArray
      (items (get (get source "workspace") "roots") ++ map (fun entry => get entry "canonical") (items (get source "runtimeReads"))))] else []).
