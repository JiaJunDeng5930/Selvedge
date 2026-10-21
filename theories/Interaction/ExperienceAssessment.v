From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema Utf8.
From Selvedge.Kernel Require Import Commands Workspace TaskConstraints.
From Selvedge.Kernel Require Codec.
From Selvedge.Features Require Board Work Titles TaskGraph.
From Selvedge.Interaction Require Import Codec Identity Forms Experience ExperienceObservation Resource Services ModelSelection.
From Selvedge.Interaction Require CommandAssessment.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition field_obstruction_with_attention e name code message actionable : obstruction e :=
  Obstruction (match admit_subject e name with Some subject => RepairField subject
    | None => RepairEditor end) code message actionable.
Definition field_obstruction e name code message := field_obstruction_with_attention e name code message true.
Definition editor_obstruction e code message actionable : obstruction e :=
  Obstruction RepairEditor code message actionable.
Definition require_field e (valid : bool) name code message :=
  if valid then [] else [field_obstruction e name code message].
Definition require_passive_field e (valid:bool)name code message :=
  if valid then []else[field_obstruction_with_attention e name code message false].
Definition require_editor e (valid : bool) code message actionable :=
  if valid then [] else [editor_obstruction e code message actionable].
Definition raw_requirements d := map (fun entry => field_obstruction (owner d) (fst entry)
  "invalid_field" ("Correct the value of " ++ fst entry)%string) (raw_fields d).
Definition selected_model_requirements e profile effort world :=
  match ModelSelection.observed_profile world profile with
  | None => [field_obstruction e "profile" "model_not_found" "Choose a configured model"]
  | Some _ => require_field e
      (ModelSelection.valid_preference world (profile,effort))
      "reasoning" "invalid_reasoning" "Choose an allowed reasoning effort"
  end.
Definition model_requirements d world :=
  match owner d with
  |Execution task=>match bind(committed_value task "profile" world)as_string,
      bind(committed_value task "reasoning" world)as_string with
    |Some profile,Some effort=>selected_model_requirements(owner d)profile effort world
    |_,_=>[editor_obstruction(owner d)"task_not_found" "The target task does not exist" true]end
  |_=>selected_model_requirements(owner d)(read_text "profile" d)(read_text "reasoning" d)world end.
Definition project_original d world := match owner d with
| Project (Some id) => project_resource id world | _ => None end.
Definition project_changed d world :=
  match project_original d world with
  | None => true
  | Some original => negb (Json.equal (get "name" d) (value_or JNull (field "name" original)) &&
      Json.equal (workspace d) (value_or JNull (field "workspace" original)) &&
      Json.equal (get "create_worktree" d) (value_or JNull (field "create_worktree" original)))
  end || negb (String.eqb (read_text "directory_entry" d) "").
Definition project_requirements d world :=
  require_field (owner d) (Workspace.valid_project_name (read_text "name" d))
    "name" "invalid_project_name" "Enter a project name of at most 256 UTF-8 bytes" ++
  require_editor (owner d) (project_changed d world) "unchanged_project"
    "No project changes to save" false ++
  match owner d with
  | Project (Some id) => require_editor (owner d)
      (match project_resource id world with Some _ => true | None => false end)
      "project_not_found" "The project does not exist" true
  | _ => [] end.
Definition agent_requirements d world :=
  require_field (owner d) (Board.agent_name_valid (read_text "name" d))
    "name" "invalid_agent_name" "Enter an agent name of at most 160 UTF-8 bytes" ++
  require_field (owner d) (Board.agent_profile_valid (read_text "profile" d))
    "profile" "invalid_agent_profile" "Enter a valid model profile" ++
  require_field (owner d) (Board.agent_reasoning_valid (read_text "reasoning" d))
    "reasoning" "invalid_agent_reasoning" "Enter a valid reasoning effort" ++
  require_field (owner d) (Board.agent_instructions_valid (read_text "instructions" d))
    "instructions" "invalid_agent_instructions" "Shorten the agent instructions" ++
  require_field (owner d) (match natural (get "concurrency" d) with
    | Some count => Board.agent_concurrency_valid count | None => false end)
    "concurrency" "invalid_agent_concurrency" "Choose concurrency from 1 to 64" ++
  model_requirements d world ++
  match owner d with
  | Agent (Some id) => require_editor (owner d)
      (match field "board" world with Some board => match world_resource "agents" "agent_id" id board with
        Some _ => true | None => false end | None => false end)
      "agent_not_found" "The agent does not exist" true
  | _ => [] end.
Definition valid_graph_declaration source :=
  match string_field "name" source, array_field "nodes" source, array_field "rules" source with
  | Some name, Some nodes, Some rules =>
      match traverse TaskGraph.parse_node nodes, traverse TaskGraph.parse_rule rules with
      | Some nodes, Some rules => TaskGraph.valid_declaration name nodes rules
      | _, _ => false end
  | _, _, _ => false end.
Definition fork_requirements d world task :=
  match task_resource task world with
  | None => [editor_obstruction (owner d) "task_not_found" "The target task does not exist" true]
  | Some parent =>
      require_editor (owner d) (negb (flag "working" parent) &&
        negb (String.eqb (text "status" parent) "archived"))
        "task_busy" "A manual fork requires an idle task" false ++
      require_field (owner d) (match natural (get "child_count" d), natural_field "max_fork" parent with
        | Some count, Some maximum => TaskConstraints.fork_count_valid count maximum
        | _, _ => false end) "child_count" "invalid_fork_count" "Choose a fork count within the task limit" ++
      require_field (owner d) (match natural (get "child_count" d) with
        | Some count => TaskConstraints.fork_messages_valid count (List.length (read_list "messages" d))
        | None => false end) "messages" "invalid_fork_messages" "Provide one message per fork, or no messages"
  end.
Definition body_requirements d world := match owner d with
| NewTask _ => require_passive_field (owner d) (has_message d) "message" "empty_message" "Write a task to start" ++
    model_requirements d world
| Message _ => require_passive_field (owner d) (has_message d) "message" "empty_message" "Write a message to send"
| Execution _ => model_requirements d world
| Project _ => project_requirements d world
| Agent _ => agent_requirements d world
| Fork task => fork_requirements d world task
| TaskGraph _ _ => require_field (owner d) (valid_graph_declaration (get "declaration" d))
    "declaration" "invalid_task_graph_declaration" "Enter a valid task graph declaration"
| WorkName _ => require_field (owner d) (Work.valid_name (read_text "name" d))
    "name" "invalid_work_name" "Enter a Work name of at most 4096 UTF-8 bytes"
| TitlePrompts =>
    require_field (owner d) (Titles.valid_instructions (read_text "task_prompt" d))
      "task_prompt" "invalid_task_title_prompt" "Enter a nonempty title prompt of at most 4096 UTF-8 bytes" ++
    require_field (owner d) (Titles.valid_instructions (read_text "agent_prompt" d))
      "agent_prompt" "invalid_agent_title_prompt" "Enter a nonempty title prompt of at most 4096 UTF-8 bytes"
| _ => [] end.
Definition preparation_workspace d := match owner d with
| Project _ => Some (workspace d)
| NewTask _ | Agent _ | Fork _ => workspace_override d
| _ => None end.
Definition context_requirements d world :=
  match owner d with
  | NewTask _ | Agent _ | Fork _ =>
      require_field (owner d) (match workspace_context d world with Some _ => true | None => false end)
        "project_id" "context_unavailable" "Choose an available task context" ++
      (match preparation_workspace d with
      | None => []
      | Some source => require_field (owner d) (match Selvedge.Kernel.Codec.parse_workspace source with
        | Some _ => true | None => false end) "roots" "invalid_workspace"
        "Use distinct absolute workspace paths and a primary directory in the collection" end) ++
      (match current_approval d world false with
      | Some (JString "approval-for-me") =>
          require_field (owner d) (match permission_context d world "reviewer_profile" with
          | Some (JString key, _) => match ModelSelection.observed_profile world key with
            Some profile => Selvedge.Kernel.ModelCapabilities.valid_reviewer_profile profile | None => false end
          | _ => false end) "reviewer_profile" "reviewer_not_found" "Choose an available automatic review model"
      | _ => [] end)
  | Project _ => require_field (owner d) (match Selvedge.Kernel.Codec.parse_workspace (workspace d) with
      | Some _ => true | None => false end) "roots" "invalid_workspace"
      "Use distinct absolute workspace paths and a primary directory in the collection"
  | _ => [] end.
Definition workspace_git_available d world services :=
  match resolved_workspace d world, workspace_git services with
  | Some workspace, Loaded _ (e, primary) available => same_editor (owner d) e &&
      String.eqb primary (value_or "" (string_field "primary_root" workspace)) && available
  | _, _ => false end.
Definition workspace_requirements d world services :=
  (if workspace_editor(owner d)then
    require_field(owner d)(String.eqb(read_text "directory_entry" d)"")
      "directory_entry" "unadded_directory" "Add or clear the directory before continuing"else[])++
  (match status d with
  | WorkspaceRejected reason => [field_obstruction (owner d) "roots" "workspace_observation_failed" reason]
  | _ => [] end) ++
  match owner d with
  | NewTask _ => require_field (owner d)
      (negb (local_worktree d) || workspace_git_available d world services)
      "task_environment" "git_observation_required"
      "Wait for Git verification of the primary workspace before creating a worktree."
  | _ => [] end.
Definition service_requirements d services pending :=
  require_editor (owner d) (connected services) "disconnected" "Connect to continue" false ++
  require_editor (owner d) (negb pending) "pending" "Wait for the current submission" false ++
  require_editor (owner d) (negb (preparing (owner d) services))
    "preparing_workspace" "Wait for directory observation" false ++
  require_editor (owner d) (negb (blocks (owner d) services))
    "pending_upload" "Finish or cancel this editor's uploads" false.
Definition draft_requirements d world services pending :=
  service_requirements d services pending ++ raw_requirements d ++
  workspace_requirements d world services ++ context_requirements d world ++ body_requirements d world.
Definition request_matches d sequence source request :=
  match decode_command command_specs source with None=>false|Some command=>
    CommandAssessment.matches(CommandAssessment.DraftOwner(owner d))(revision d)sequence command request end.
Definition canonical_requirements d world services source :=
  let waiting := [editor_obstruction (owner d) "availability_pending" "Checking action availability" false] in
  match decode_command command_specs source with
  |None=>[editor_obstruction (owner d) "invalid_command" "The complete declaration does not match the public command protocol" true]
  |Some _=>
  match natural_field "sequence" world with
  | None => [editor_obstruction (owner d) "snapshot_unavailable" "Wait for the current workspace observation" false]
  | Some sequence => match find (assessment_owned (owner d)) (command_assessments services) with
    | Some (Loaded _ request observation) =>
        if request_matches d sequence source request &&
          CommandAssessment.current (owner d) (revision d) sequence observation then
          match CommandAssessment.observed_admission observation with
          | CommandAssessment.Admitted => []
          | CommandAssessment.Refused code message => [editor_obstruction (owner d) code message true] end
        else waiting
    | Some (Failed _ request reason) => if request_matches d sequence source request then
        [editor_obstruction (owner d) "assessment_failed" reason true] else waiting
    | _ => waiting end
  end end.
Definition action_requirements d world services pending :=
  let requirements := draft_requirements d world services pending in
  match requirements, preparation_workspace d with
  | [],None => canonical_requirements d world services (command d)
  | _,_ => requirements end.
Definition assess_draft d world services pending :=
  assess_requirements (revision d) (preparation_workspace d) (action_requirements d world services pending).
Theorem all_preparation_obstructions_remain_visible d world services pending :
  assessment_obstructions (assess_draft d world services pending) =
    action_requirements d world services pending.
Proof. apply every_requirement_is_retained. Qed.
Theorem preparation_uses_the_complete_assessment d world services pending :
  can_prepare (assess_draft d world services pending) = true <->
    action_requirements d world services pending = [].
Proof. apply preparation_admission_iff_no_requirement. Qed.
