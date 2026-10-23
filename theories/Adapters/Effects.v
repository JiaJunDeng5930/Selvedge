From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common EffectCallbacks Processes TextEndpoints Workspaces CloudWorkspaces SandboxPolicy Seatbelt Sandbox Attachments.
Import ListNotations.
Open Scope string_scope.

Definition handlers : list (string * (json -> json)) := [
  ("effect.cloud_backend",CloudConfiguration.require_cloud);
  ("effect.cloud_repository",CloudWorkspaces.repository);
  ("effect.cloud_remote_names",CloudWorkspaces.remote_names);
  ("effect.cloud_receipt",CloudWorkspaces.receipt);
  ("effect.cloud_workspace",CloudWorkspaces.workspace);
  ("effect.artifact_limit",Attachments.artifact_limit);
  ("effect.attachment",Attachments.attachment);
  ("effect.attachment_media_type",Attachments.attachment_media_type);
  ("effect.attachment_budget",Attachments.attachment_budget);
  ("effect.attachment_id",fun source => Attachments.identifier (get source "id"));
  ("effect.board_clock",Attachments.board_clock);
  ("effect.board_command",Attachments.board_command);
  ("effect.board_references",Attachments.board_references);
  ("effect.filename",fun source => Attachments.filename (get source "value"));
  ("effect.message_image_match",Attachments.message_image_match);
  ("effect.message_images",Attachments.message_images);
  ("effect.reference_match",fun source => Attachments.reference_match ["name";"mime";"path";"bytes"] (get source "value") (get source "attachment"));
  ("effect.sandbox_admit",Sandbox.plan_admission);
  ("effect.sandbox_prepare",Sandbox.sandbox_prepare);
  ("effect.sandbox_launch",Sandbox.sandbox_launch);
  ("effect.unrestricted_launch",Sandbox.unrestricted_launch);
  ("effect.sandbox_bindings",fun source => success (SandboxPolicy.bindings source));
  ("effect.environment",fun source => success (SandboxPolicy.environment source));
  ("effect.protected_workspace",SandboxPolicy.protected_workspace);
  ("effect.seccomp",SandboxPolicy.seccomp);
  ("effect.seatbelt",Seatbelt.seatbelt);
  ("effect.seatbelt_input",fun source => success (Seatbelt.seatbelt_input source));
  ("effect.runtime_candidates",fun source => success (SandboxPolicy.runtime_candidates (str source "platform")));
  ("effect.executable_candidates",fun source => success (SandboxPolicy.executable_candidates (str source "platform")));
  ("effect.workspace_command",fun source => success (Workspaces.plan_json (Workspaces.plan (get source "command"))));
  ("effect.workspace_settings",Workspaces.workspace_settings);
  ("effect.workspace_command_observed",Workspaces.workspace_command_observed);
  ("effect.workspace_admit",fun source => Workspaces.workspace_admit (get source "value"));
  ("effect.root_admit",Workspaces.root_admit);
  ("effect.workspace_distinct",Workspaces.workspace_distinct);
  ("effect.workspace_selected",Workspaces.workspace_selected);
  ("effect.workspace_selection",Workspaces.workspace_selection);
  ("effect.workspace_bound",Workspaces.workspace_bound);
  ("effect.workspace_environment_bound",Workspaces.workspace_environment_bound);
  ("effect.worktree_locations",Workspaces.worktree_locations);
  ("effect.worktree_path",Workspaces.worktree_path);
  ("effect.worktree_receipt",Workspaces.worktree_receipt);
  ("effect.worktree_workspace",Workspaces.worktree_workspace);
  ("effect.worktree_recovery_effect",Workspaces.worktree_recovery_effect);
  ("effect.completion",EffectCallbacks.completion);
  ("effect.failure",EffectCallbacks.failure);
  ("effect.bash_arguments",Processes.bash_arguments);
  ("effect.process_read_arguments",Processes.read_arguments);
  ("effect.process_write_arguments",Processes.write_arguments);
  ("effect.image_arguments",Processes.image_arguments);
  ("effect.process_result",fun source => success (Processes.process_result source));
  ("effect.approval_text",TextEndpoints.response_text true);
  ("effect.task_text_text",TextEndpoints.response_text false);
  ("effect.approval_outcome",TextEndpoints.approval_outcome);
  ("effect.task_text_outcome",TextEndpoints.task_text_outcome);
  ("effect.request_task_text",TextEndpoints.request_task_text);
  ("effect.request_approval",fun source =>
    if String.eqb (str (get source "effect") "kind") "approval" then success JNull
    else type_error "Expected a committed approval effect")].
Definition call (operation : string) (source : json) :=
  match find (fun handler => String.eqb operation (fst handler)) handlers with
  | Some (_,handler) => handler source
  | None => err ("Unknown host model operation: " ++ operation)
  end.
