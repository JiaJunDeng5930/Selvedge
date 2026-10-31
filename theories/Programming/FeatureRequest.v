From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require RequestTypes CommandResult.
From Selvedge.Programming Require Import Receiver.
From Selvedge.Kernel Require Import State.
Import ListNotations.
Open Scope string_scope.
Module F := Selvedge.Features.Domain.

Definition install_feature {input} (receiver : Receiver.t F.state input) request value :=
 with_features (Receiver.install receiver request (world_features value)) value.

(** A channel consumes a domain selection. Its payload and located protocol
    are projections of that one selection; only domain-specific eligibility is
    part of the source. Allocation and receiver installation belong here. *)
Record feature_channel (source : world -> Type) (payload : Type) := FeatureChannel {
 channel_space : identity_space;
 channel_input : forall before, source before -> payload;
 channel_protocol : forall before, source before ->
   RequestTypes.located payload (world_features (snd (allocate_identity channel_space before)))
}.
Arguments FeatureChannel {source payload}.
Arguments channel_space {source payload}.
Arguments channel_input {source payload} _ {before}.
Arguments channel_protocol {source payload} _ {before}.
Record feature_plan (before : world) := FeaturePlan {
 feature_source : world -> Type;
 feature_payload : Type;
 feature_protocol : feature_channel feature_source feature_payload;
 feature_selected : feature_source before
}.
Arguments FeaturePlan {before feature_source feature_payload}.
Arguments feature_source {before}.
Arguments feature_payload {before}.
Arguments feature_protocol {before}.
Arguments feature_selected {before}.
Definition feature_input {before} (request : feature_plan before) :=
 channel_input (feature_protocol request) (feature_selected request).
Definition feature_envelope {before} (request : feature_plan before) :=
 RequestEnvelope.Envelope (next_identity (channel_space (feature_protocol request)) before) (feature_input request).
Definition feature_request {before} (request : feature_plan before) :=
 RequestTypes.Packet
   (RequestTypes.release (channel_protocol (feature_protocol request) (feature_selected request)))
   (feature_envelope request).
Definition feature_issue_change {before} (request : feature_plan before) : CommandResult.change :=
 let '(_,allocated) := allocate_identity (channel_space (feature_protocol request)) before in
 let sent := feature_request request in
 CommandResult.Change (JObject [("accepted",JBool true)])
   (with_features (RequestTypes.install sent (world_features allocated)) allocated)
   [RequestFeature sent].
Definition feature_issue {before} (request : feature_plan before) : decision :=
 CommandResult.accept (feature_issue_change request).
