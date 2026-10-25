From Stdlib Require Import String List Bool NArith Sorting.Mergesort Structures.Orders.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Import ContextTypes.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive mode := HomeGuidance | PrimaryGuidance | WorkspaceGuidance | HomeSkills | WorkspaceSkills.
Inductive job :=
 | Ancestors (owner folder : string) (chain : list string)
 | Guidance (owner : option string) (folder : string) (global : bool)
 | Containers (owner : option string) (folder : string) (global : bool)
 | Skill (owner : option string) (folder origin : string) (global : bool)
 | Children (owner : option string) (folder origin : string) (global skills : bool).
Record source := Source { source_path : string; source_owner : option string;
 source_scope : string; source_global : bool }.
Record state := State { scan_mode : mode; scan_policy : discovery_policy;
 scan_primary : option string; scan_jobs : list job; scan_directories : list string;
 scan_entries : N; scan_sources : list source; scan_error : option string }.
Record directory_entry := DirectoryEntry { entry_name : string; entry_path : string; entry_kind : string }.
Inductive observation := ObservedDirectory (canonical : bool) (parent : string)
 (probes : list (string * string)) (entries : list directory_entry) | FailedObservation (message : string).
Record primitive := Inspect { inspect_folder : string; inspect_probes : list string;
 inspect_entries : bool; inspect_maximum : N }.

Definition rebuild (s : state) jobs directories entries sources error :=
 State (scan_mode s) (scan_policy s) (scan_primary s) jobs directories entries sources error.
Definition enqueue (s : state) jobs := rebuild s (jobs ++ scan_jobs s)%list
 (scan_directories s) (scan_entries s) (scan_sources s) (scan_error s).
Definition fail (s : state) message := rebuild s [] (scan_directories s)
 (scan_entries s) (scan_sources s) (Some message).
Definition directory (s : state) folder :=
 let dirs := if existsb (String.eqb folder) (scan_directories s)
             then scan_directories s else folder :: scan_directories s in
 let s := rebuild s (scan_jobs s) dirs (scan_entries s) (scan_sources s) (scan_error s) in
 (* DEFENSE: A reachable workspace may exceed the admitted distinct-directory budget. *)
 if N.of_nat (List.length dirs) <=? discovery_max_directories (scan_policy s)
 then s else fail s "Context discovery directory budget exceeded".
Definition add_entries (s : state) (entries : list directory_entry) :=
 let count := scan_entries s + N.of_nat (List.length entries) in
 let s := rebuild s (scan_jobs s) (scan_directories s) count (scan_sources s) (scan_error s) in
 (* DEFENSE: Directory streams can exceed the remaining admitted entry budget. *)
 if count <=? discovery_max_entries (scan_policy s)
 then s else fail s "Context discovery entry budget exceeded".
Definition optional_string_equal (x y : option string) :=
 match x,y with Some x,Some y => String.eqb x y | None,None => true | _,_ => false end.
Definition add_source (s : state) owner folder global filename :=
 if existsb (fun value => String.eqb filename (source_path value) &&
                          optional_string_equal owner (source_owner value)) (scan_sources s)
 then s else
 let sources := (scan_sources s ++ [Source filename owner folder global])%list in
 let s := rebuild s (scan_jobs s) (scan_directories s) (scan_entries s) sources (scan_error s) in
 (* DEFENSE: A discovered collection can exceed its admitted source count. *)
 if N.of_nat (List.length sources) <=? discovery_max_sources (scan_policy s)
 then s else fail s "Context discovery source budget exceeded".
Definition join (folder name : string) := if String.eqb folder "/" then "/" ++ name else folder ++ "/" ++ name.
Definition probe_kind name probes := match find (fun value => String.eqb name (fst value)) probes with
 | Some (_,kind) => kind | None => "missing" end.
Fixpoint selected files probes : option (string * bool) := match files with
 | [] => None
 | name :: rest => let kind := probe_kind name probes in
   if String.eqb kind "missing" then selected rest probes else Some (name,String.eqb kind "file") end.
Definition select_source s owner folder global probes :=
 match selected (discovery_files (scan_policy s)) probes with
 | None => s | Some (name,true) => add_source s owner folder global (join folder name)
 (* DEFENSE: A selected workspace source may be a symbolic link or special file. *)
 | Some (name,false) => fail s ("Context discovery source must be a regular file without symbolic links: " ++ join folder name)
 end.
Definition workspace_folder s owner folder :=
 match scan_mode s with
 | WorkspaceSkills => [Containers (Some owner) folder false]
 | _ => if optional_string_equal (Some owner) (scan_primary s) && String.eqb owner folder
        then [] else [Guidance (Some owner) folder false] end.
Definition workspace_tree s owner folder :=
 (workspace_folder s owner folder ++ [Children (Some owner) folder folder false false])%list.
Module DirectoryOrder <: Orders.TotalLeBool.
 Definition t := directory_entry.
 Definition leb (x y : t) := String.leb (entry_path x) (entry_path y).
 Lemma leb_total x y : leb x y = true \/ leb y x = true.
 Proof. apply String.leb_total. Qed.
End DirectoryOrder.
Module DirectorySort := Mergesort.Sort DirectoryOrder.
Definition sorted_paths := DirectorySort.sort.
Definition children s entries := sorted_paths (filter (fun entry =>
 String.eqb (entry_kind entry) "directory" && negb (existsb (String.eqb (entry_name entry))
 (discovery_excluded (scan_policy s)))) entries).

Definition transition (s : state) (task : job) (seen : observation) :=
 match seen with
 | FailedObservation message => fail s message
 | ObservedDirectory canonical parent probes entries =>
   (* DEFENSE: Workspace directory replacement or links must not escape canonical roots. *)
   let folder := match task with
     | Ancestors _ folder _ | Guidance _ folder _ | Containers _ folder _
     | Skill _ folder _ _ | Children _ folder _ _ _ => folder end in
   if negb canonical then fail s ("Context discovery requires a canonical directory without symbolic links: " ++ folder)
   else let s := directory s folder in
   match scan_error s with Some _ => s | None =>
   match task with
   | Ancestors owner folder chain =>
     if existsb (fun marker => negb (String.eqb (probe_kind marker probes) "missing"))
        (discovery_markers (scan_policy s)) then
       enqueue s (flat_map (workspace_folder s owner) (removelast (folder :: chain)) ++ workspace_tree s owner owner)%list
     else if String.eqb parent folder then enqueue s (workspace_tree s owner owner)
     else enqueue s [Ancestors owner parent (folder :: chain)]
   | Guidance owner folder global => select_source s owner folder global probes
   | Containers owner folder global => enqueue s (map (fun relative => Skill owner (join folder relative) folder global)
       (filter (fun relative => negb (String.eqb (probe_kind relative probes) "missing"))
         (discovery_directories (scan_policy s))))
   | Skill owner folder origin global =>
       match selected (discovery_files (scan_policy s)) probes with
       | None => enqueue s [Children owner folder origin global true]
       | Some (name,true) => add_source s owner origin global (join folder name)
       (* DEFENSE: A selected skill file may be a symbolic link or special file. *)
       | Some (name,false) => fail s ("Context discovery source must be a regular file without symbolic links: " ++ join folder name)
       end
   | Children owner folder origin global skills =>
       let s := add_entries s entries in
       match scan_error s with Some _ => s | None =>
       enqueue s (flat_map (fun entry => if skills then [Skill owner (entry_path entry) origin global]
         else match owner with Some root => workspace_tree s root (entry_path entry) | None => [] end)
         (children s entries)) end
   end end
 end.
Definition next (s : state) : list primitive :=
 match scan_error s,scan_jobs s with
 | None,task :: _ =>
   let '(folder,probes,listing) := match task with
   | Ancestors _ folder _ => (folder,discovery_markers (scan_policy s),false)
   | Guidance _ folder _ | Skill _ folder _ _ => (folder,discovery_files (scan_policy s),false)
   | Containers _ folder _ => (folder,discovery_directories (scan_policy s),false)
   | Children _ folder _ _ _ => (folder,[],true) end in
   [Inspect folder probes listing (discovery_max_entries (scan_policy s) - scan_entries s)]
 | _,_ => [] end.
Definition step (s : state) seen : state * list primitive :=
 let updated := match scan_error s,scan_jobs s with
 | None,task :: rest => transition (rebuild s rest (scan_directories s) (scan_entries s)
     (scan_sources s) None) task seen
 | _,_ => s end in (updated,next updated).
Definition start mode policy home primary roots :=
 let jobs := match mode with
 | HomeGuidance => [Guidance primary home true]
 | PrimaryGuidance => match primary with Some root => [Guidance primary root false] | None => [] end
 | WorkspaceGuidance | WorkspaceSkills => map (fun root => Ancestors root root []) roots
 | HomeSkills => [Containers primary home true] end in
 State mode policy primary jobs [] 0 [] None.

Record collection_state := CollectionState { collection_observations : list json;
 collection_bytes : N; collection_maximum : N; collection_error : option string }.
Definition collect (s : collection_state) observation bytes :=
 match collection_error s with Some _ => s | None =>
 let total := collection_bytes s + bytes in
 (* DEFENSE: Valid individual files can together exceed the collection content budget. *)
 if total <=? collection_maximum s
 then CollectionState (collection_observations s ++ [observation]) total (collection_maximum s) None
 else CollectionState [] total (collection_maximum s) (Some "Context discovery content budget exceeded") end.

Inductive collection := CompleteCollection (observations : list json) | IncompleteCollection (message : string).
Definition field_value name value := match Json.field name value with Some field => field | None => JNull end.
Definition failed_member message key := JObject [("type",JString "failure");("key",key);("message",JString message)].
Definition observation_key item := field_value "key" (field_value "snapshot" item).
Definition complete_collection previous fallback result :=
 match result with
 | IncompleteCollection message => map (failed_member message)
     (match previous with [] => [fallback] | _ => map (field_value "key") previous end)
 | CompleteCollection observations => (observations ++ map (fun binding =>
     JObject [("type",JString "absent");("key",field_value "key" binding)])
     (filter (fun binding => negb (existsb (fun observed =>
       Json.equal (field_value "key" binding) (observation_key observed)) observations)) previous))%list
 end.

Theorem failed_collection_preserves_members previous fallback message :
 complete_collection previous fallback (IncompleteCollection message) =
 map (failed_member message) (match previous with [] => [fallback] | _ => map (field_value "key") previous end).
Proof. reflexivity. Qed.
Theorem failed_step_emits_no_io s message : snd (step s (FailedObservation message)) = [].
Proof. destruct s as [mode policy primary jobs dirs entries sources error].
 destruct error as [error|]; [reflexivity|]. destruct jobs; reflexivity. Qed.

Theorem incomplete_collection_never_withdraws previous fallback message :
 Forall (fun item => field_value "type" item = JString "failure")
  (complete_collection previous fallback (IncompleteCollection message)).
Proof.
 unfold complete_collection. apply Forall_map.
 apply Forall_forall. intros value Hin. reflexivity.
Qed.
