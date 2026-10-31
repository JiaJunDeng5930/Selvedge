From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Programming Require RequestTypes.
From Selvedge.Programming Require CommandResult.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Programming Require Import OptionObservationProofs ReceiverProofs.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TicketedRequest TaskScopeProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.

(** The common contract follows the receiver constructor, independently of
    which protocol declares it. A new protocol adds no preservation case. *)
Theorem every_feature_request_has_its_installed_receiver : forall before (request : S.feature_plan before),
 match decision_effects (S.feature_issue request) with
 | [RequestFeature sent] =>
   Receiver.lookup (RequestTypes.receiver (RequestTypes.definition sent)) (RequestTypes.request sent)
     (world_features (decision_world (S.feature_issue request))) = Some (RequestTypes.request sent)
 | _ => False end.
Proof.
 intros before request.
 unfold S.feature_issue,S.feature_issue_change,CommandResult.accept,allocate_identity,
   S.feature_request,RequestTypes.install; cbn -[Receiver.lookup Receiver.install S.feature_envelope].
 apply ReceiverProofs.installed; exact (Receiver.position
   (RequestTypes.receiver (S.channel_protocol (S.feature_protocol request) (S.feature_selected request)))).
Qed.

Theorem feature_requests_preserve_execution_frame : forall before (request : S.feature_plan before),
 let after:=decision_world (S.feature_issue request) in
 world_tasks after=world_tasks before /\ world_projects after=world_projects before /\
 world_environment after=world_environment before /\ world_sequence after=world_sequence before.
Proof.
 intros before request; cbn zeta.
 unfold S.feature_issue,S.feature_issue_change,CommandResult.accept,S.install_feature,allocate_identity.
 destruct (S.channel_space (S.feature_protocol request)); repeat split; reflexivity.
Qed.
