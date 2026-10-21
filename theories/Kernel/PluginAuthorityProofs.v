From Stdlib Require Import String List NArith Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Codec Capabilities Configuration Scheduler JsonProofs.
Import ListNotations.
Open Scope string_scope.

Lemma same_reference_preserves_identity : forall left right,
 PluginProtocol.same_reference left right = true ->
 value_or_null "name" left = value_or_null "name" right /\
 value_or_null "revision" left = value_or_null "revision" right.
Proof.
 intros left right Same; unfold PluginProtocol.same_reference in Same.
 apply json_comparison_is_exact in Same.
 split; [apply (f_equal (value_or_null "name")) in Same | apply (f_equal (value_or_null "revision")) in Same];
 cbn [PluginProtocol.reference_json PluginProtocol.reference_schema Schema.declared_names Schema.field_name value_or_null field lookup] in Same;
 exact Same.
Qed.
Lemma current_hook_owner : forall phase reference catalog,
 Capabilities.hook_available phase reference catalog = true ->
 exists owner, In owner catalog /\
 bool_field (Capabilities.hook_field phase) owner = Some true /\
 value_or_null "name" (value_or_null "reference" owner) = value_or_null "name" reference /\
 value_or_null "revision" (value_or_null "reference" owner) = value_or_null "revision" reference.
Proof.
 intros phase reference catalog Available.
 apply existsb_exists in Available as [owner [Member Available]].
 apply andb_true_iff in Available as [Enabled Same].
 exists owner; split; [exact Member|].
 unfold bool_default in Enabled; destruct (bool_field (Capabilities.hook_field phase) owner) as [enabled|] eqn:Flag; [|discriminate].
 destruct enabled; [|discriminate]. split; [reflexivity|].
 apply same_reference_preserves_identity; exact Same.
Qed.

Theorem actual_start_call_requires_a_current_hook_owner : forall execute id invocation remaining task value plugin pending,
 Scheduler.before_plugins task = plugin :: pending ->
 decision_effects (Scheduler.start_call execute id invocation remaining task value) <> [] ->
 exists owner, In owner (environment_plugins (world_environment value)) /\
 bool_field "before_tool" owner = Some true /\
 value_or_null "name" (value_or_null "reference" owner) = value_or_null "name" plugin /\
 value_or_null "revision" (value_or_null "reference" owner) = value_or_null "revision" plugin.
Proof.
 intros execute id invocation remaining task value plugin pending Frozen Emitted.
 unfold Scheduler.start_call in Emitted.
 destruct (Tasks.find_tool (call_name invocation) (contract_tools (task_contract task))) as [tool|]; [|contradiction].
 rewrite Frozen in Emitted; unfold Scheduler.before_hook_step in Emitted.
 destruct (Capabilities.hook_available Capabilities.BeforeTool plugin (environment_plugins (world_environment value))) eqn:Available; [|contradiction].
 apply current_hook_owner in Available; exact Available.
Qed.

Theorem actual_after_hook_requires_a_current_hook_owner : forall id operation task value plugin pending result error,
 operation_stage operation = AfterHooksReady (plugin :: pending) result error ->
 decision_effects (Scheduler.after_hooks_step id operation task value) <> [] ->
 exists owner, In owner (environment_plugins (world_environment value)) /\
 bool_field "after_tool" owner = Some true /\
 value_or_null "name" (value_or_null "reference" owner) = value_or_null "name" plugin /\
 value_or_null "revision" (value_or_null "reference" owner) = value_or_null "revision" plugin.
Proof.
 intros id operation task value plugin pending result error Stage Emitted.
 unfold Scheduler.after_hooks_step in Emitted; rewrite Stage in Emitted.
 destruct (Capabilities.hook_available Capabilities.AfterTool plugin (environment_plugins (world_environment value))) eqn:Available; [|contradiction].
 apply current_hook_owner in Available; exact Available.
Qed.

Theorem accepted_plugin_route_has_a_current_owner : forall plugins source reference,
 field "plugin" source = Some reference -> reference <> JNull ->
 Configuration.valid_route plugins source = true ->
 exists owner, In owner plugins /\
 value_or_null "name" (value_or_null "reference" owner) = value_or_null "name" reference /\
 value_or_null "revision" (value_or_null "reference" owner) = value_or_null "revision" reference.
Proof.
 intros plugins source reference Present NonNull Admitted.
 assert (Capabilities.plugin_present reference plugins = true) as Current.
 { unfold Configuration.valid_route in Admitted; rewrite Present in Admitted.
   destruct reference; try contradiction; repeat rewrite andb_true_iff in Admitted; tauto. }
 apply existsb_exists in Current as [owner [Member Same]].
 exists owner; split; [exact Member|]. apply same_reference_preserves_identity; exact Same.
Qed.
