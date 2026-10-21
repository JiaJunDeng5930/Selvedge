From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec.
Import ListNotations.
Open Scope string_scope.

Theorem an_empty_sandbox_override_inherits_the_committed_sandbox : forall fallback,
 Codec.parse_sandbox_patch fallback (JObject []) = Some fallback.
Proof. intros [access network]; destruct access, network; reflexivity. Qed.

Theorem a_network_override_retains_the_committed_access_mode : forall fallback network,
 Codec.parse_sandbox_patch fallback (JObject [("network_access",JBool network)]) =
 Some (Sandbox (sandbox_access fallback) network).
Proof. intros [access previous] network; destruct access, previous, network; reflexivity. Qed.

Theorem null_is_not_a_sandbox_field_override : forall fallback,
 Codec.parse_sandbox_patch fallback (JObject [("network_access",JNull)]) = None /\
 Codec.parse_sandbox_patch fallback (JObject [("mode",JNull)]) = None.
Proof. intros [access network]; destruct access, network; split; reflexivity. Qed.
