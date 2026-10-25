From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Codec ContextTypes Context ContextProtocol.
From Selvedge.Host Require Import ContextDiscovery.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition nullable_string value : option (option string) := match value with
 | JNull => Some None | JString value => Some (Some value) | _ => None end.
Definition optional_json value := match value with Some value => JString value | None => JNull end.
Definition mode_text value := match value with
 | ContextDiscovery.HomeGuidance => "home_guidance" | ContextDiscovery.PrimaryGuidance => "primary_guidance"
 | ContextDiscovery.WorkspaceGuidance => "workspace_guidance" | ContextDiscovery.HomeSkills => "home_skills"
 | ContextDiscovery.WorkspaceSkills => "workspace_skills" end.
Definition mode_policy observer := match observer with
 | ContextTypes.HomeGuidance policy => Some (ContextDiscovery.HomeGuidance,policy)
 | ContextTypes.PrimaryGuidance policy => Some (ContextDiscovery.PrimaryGuidance,policy)
 | ContextTypes.WorkspaceGuidance policy => Some (ContextDiscovery.WorkspaceGuidance,policy)
 | ContextTypes.HomeSkills policy => Some (ContextDiscovery.HomeSkills,policy)
 | ContextTypes.WorkspaceSkills policy => Some (ContextDiscovery.WorkspaceSkills,policy) | _ => None end.
Definition mode_read name := match name with
 | "home_guidance" => Some ContextDiscovery.HomeGuidance | "primary_guidance" => Some ContextDiscovery.PrimaryGuidance
 | "workspace_guidance" => Some ContextDiscovery.WorkspaceGuidance | "home_skills" => Some ContextDiscovery.HomeSkills
 | "workspace_skills" => Some ContextDiscovery.WorkspaceSkills | _ => None end.
Definition job_json value :=
 let '(kind,owner,folder,origin,global,skills,chain) := match value with
 | Ancestors owner folder chain => ("ancestors",Some owner,folder,folder,false,false,chain)
 | Guidance owner folder global => ("guidance",owner,folder,folder,global,false,[])
 | Containers owner folder global => ("containers",owner,folder,folder,global,false,[])
 | Skill owner folder origin global => ("skill",owner,folder,origin,global,true,[])
 | Children owner folder origin global skills => ("children",owner,folder,origin,global,skills,[]) end in
 JObject [("type",JString kind);("owner",optional_json owner);("folder",JString folder);("origin",JString origin);
 ("global",JBool global);("skills",JBool skills);("chain",JArray (map JString chain))].
Definition parse_job value :=
 match string_field "type" value, nullable_string (get value "owner"),string_field "folder" value,
 string_field "origin" value,bool_field "global" value,bool_field "skills" value,array_field "chain" value with
 | Some kind,Some owner,Some folder,Some origin,Some global,Some skills,Some chain =>
   match Codec.traverse as_string chain with None => None | Some chain =>
   match kind with
   | "ancestors" => match owner with Some owner => Some (Ancestors owner folder chain) | None => None end
   | "guidance" => Some (Guidance owner folder global) | "containers" => Some (Containers owner folder global)
   | "skill" => Some (Skill owner folder origin global) | "children" => Some (Children owner folder origin global skills)
   | _ => None end end | _,_,_,_,_,_,_ => None end.
Definition source_json value := JObject [("filename",JString (source_path value));("workspace",optional_json (source_owner value));
 ("observations",JObject [("path",JString (source_path value));
 ("applies_to",JString (if source_global value then "*" else source_scope value));("precedence",JString (source_scope value))])].
Definition parse_source value := match string_field "filename" value,nullable_string (get value "workspace"),
 string_field "precedence" (get value "observations"),string_field "applies_to" (get value "observations") with
 | Some filename,Some owner,Some folder,Some applies => Some (Source filename owner folder (String.eqb applies "*"))
 | _,_,_,_ => None end.
Definition state_json s := JObject [("mode",JString (mode_text (scan_mode s)));("policy",Context.policy_json (scan_policy s));
 ("primary",optional_json (scan_primary s));("jobs",JArray (map job_json (scan_jobs s)));
 ("directories",JArray (map JString (scan_directories s)));("entries",number (scan_entries s));
 ("sources",JArray (map source_json (scan_sources s)));("error",optional_json (scan_error s))].
Definition parse_state value := match mode_read (str value "mode"),ContextProtocol.parse_policy (get value "policy"),
 nullable_string (get value "primary"),array_field "jobs" value,array_field "directories" value,
 natural (get value "entries"),array_field "sources" value,nullable_string (get value "error") with
 | Some mode,Some policy,Some primary,Some jobs,Some dirs,Some entries,Some sources,Some error =>
   match Codec.traverse parse_job jobs,Codec.traverse as_string dirs,Codec.traverse parse_source sources with
   | Some jobs,Some dirs,Some sources => Some (State mode policy primary jobs dirs entries sources error)
   | _,_,_ => None end | _,_,_,_,_,_,_,_ => None end.
Definition parse_entry value := match string_field "name" value,string_field "path" value,string_field "kind" value with
 | Some name,Some path,Some kind => Some (DirectoryEntry name path kind) | _,_,_ => None end.
Definition parse_probe value := match string_field "name" value,string_field "kind" value with
 | Some name,Some kind => Some (name,kind) | _,_ => None end.
Definition parse_observation value := match string_field "error" value with
 | Some message => Some (FailedObservation message)
 | None => match bool_field "canonical" value,string_field "parent" value,array_field "probes" value,array_field "entries" value with
   | Some canonical,Some parent,Some probes,Some entries =>
     match Codec.traverse parse_probe probes,Codec.traverse parse_entry entries with
     | Some probes,Some entries => Some (ObservedDirectory canonical parent probes entries) | _,_ => None end
   | _,_,_,_ => None end end.
Definition primitive_json value := JObject [("folder",JString (inspect_folder value));
 ("probes",JArray (map JString (inspect_probes value)));("entries",JBool (inspect_entries value));
 ("maximum",number (inspect_maximum value))].
Definition reply s effects := success (JObject [("state",state_json s);("effects",JArray (map primitive_json effects));
 ("done",JBool (match effects with [] => true | _ => false end));("entries",JArray (map source_json (scan_sources s)));
 ("error",optional_json (scan_error s))]).
Definition initialize value := match ContextProtocol.parse_observer (get value "observer"),string_field "home" value,
 nullable_string (get (get value "workspace") "primary_root"),array_field "roots" (get value "workspace") with
 | Some observer,Some home,Some primary,Some roots => match mode_policy observer,Codec.traverse as_string roots with
   | Some (mode,policy),Some roots => let s := start mode policy home primary roots in reply s (next s)
   | _,_ => type_error "Invalid context discovery initialization" end
 | _,_,_,_ => type_error "Invalid context discovery initialization" end.
Definition advance value := match parse_state (get value "state"),parse_observation (get value "observation") with
 | Some state,Some observation => let '(state,effects) := step state observation in reply state effects
 | _,_ => type_error "Invalid context discovery observation" end.

Definition workspace_observer value := match value with
 | WorkspaceFile _ | ContextTypes.PrimaryGuidance _ | ContextTypes.WorkspaceGuidance _ | ContextTypes.WorkspaceSkills _ => true
 | _ => false end.
Definition classify observer := JObject [("discovery",JBool (match mode_policy observer with Some _ => true | None => false end));
 ("workspace",JBool (workspace_observer observer));
 ("skills",JBool (match observer with ContextTypes.HomeSkills _ | ContextTypes.WorkspaceSkills _ => true | _ => false end));
 ("catalog",JBool (match observer with ContextTypes.HomeSkills _ | ContextTypes.WorkspaceSkills _ | ConfigFiles "skills" => true | _ => false end));
 ("configuration",JBool (match observer with ConfigText _ | ConfigFiles _ | ContextTypes.HomeSkills _ | ContextTypes.WorkspaceSkills _ => true | _ => false end))].
Definition descriptor value := match ContextProtocol.parse_observer (get value "observer") with
 | Some observer => success (classify observer) | None => type_error "Invalid context observer" end.
Definition fallback_filename observer home workspace :=
 let folder := match observer with ContextTypes.HomeGuidance _ => home
 | _ => match workspace with JString folder => folder | _ => home end end in
 match observer with
 | ContextTypes.HomeSkills _ | ContextTypes.WorkspaceSkills _ => home
 | ContextTypes.HomeGuidance policy | ContextTypes.PrimaryGuidance policy | ContextTypes.WorkspaceGuidance policy =>
   match discovery_files policy with name :: _ => ContextDiscovery.join folder name | [] => folder end
 | _ => folder end.
Definition source_plan value := match ContextProtocol.parse_definition (get value "definition") with
 | None => type_error "Invalid context definition" | Some definition =>
 let observer := definition_observer definition in
 let active := match definition_scope definition with Global => true | _ => negb (is_null (get value "workspace")) end in
 let '(base,filenames) := match observer with
 | NativeText _ _ | ConfigText _ => ("home",[JNull])
 | HomeFile relative => ("home",[JString relative])
 | WorkspaceFile relative => ("workspace",if active then [JString relative] else [])
 | ConfigFiles setting => ("home",match array_field setting (get value "config") with Some values => values | None => [] end)
 | _ => ("home",[]) end in
 success (JObject [("active",JBool active);("base",JString base);("filenames",JArray filenames);
 ("descriptor",classify observer);
 ("fallback",JString (fallback_filename observer (str value "home") (get value "workspace")))]) end.
Definition collection_json value := JObject [("observations",JArray (collection_observations value));
 ("bytes",number (collection_bytes value));("maximum",number (collection_maximum value));
 ("error",optional_json (collection_error value))].
Definition parse_collection value := match array_field "observations" value,natural (get value "bytes"),
 natural (get value "maximum"),nullable_string (get value "error") with
 | Some observations,Some bytes,Some maximum,Some error => Some (CollectionState observations bytes maximum error)
 | _,_,_,_ => None end.
Definition collect_source value := match parse_collection (get value "state"),natural (get value "bytes") with
 | Some state,Some bytes => success (collection_json (collect state (get value "observation") bytes))
 | _,_ => type_error "Invalid context snapshot observation" end.
Definition collection_result value := match array_field "previous" value,parse_collection (get value "state"),
 nullable_string (get value "failure") with
 | Some previous,Some state,Some failure =>
 let result := match failure,collection_error state with
 | Some message,_ | _,Some message => IncompleteCollection message
 | None,None => CompleteCollection (collection_observations state) end in
 success (JArray (complete_collection previous (get value "fallback") result))
 | _,_,_ => type_error "Invalid context collection observation" end.
Definition filter_sources value := match array_field "entries" value,array_field "explicit" value with
 | Some entries,Some explicit => success (JArray (filter (fun entry => negb (existsb (fun name =>
   Json.equal (get entry "filename") name) explicit)) entries))
 | _,_ => type_error "Invalid explicit context sources" end.
Definition call operation value :=
 if String.eqb operation "control.context.start" then initialize value
 else if String.eqb operation "control.context.step" then advance value
 else if String.eqb operation "control.context.descriptor" then descriptor value
 else if String.eqb operation "control.context.plan" then source_plan value
 else if String.eqb operation "control.context.collect" then collect_source value
 else if String.eqb operation "control.context.collection" then collection_result value
 else if String.eqb operation "control.context.filter" then filter_sources value
 else type_error ("Unknown context control operation: " ++ operation).
