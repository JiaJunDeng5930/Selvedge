From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec CodeSource.
From Selvedge.Interaction.Interactive Require Import Bounds Types State Registry Expand Render Runtime Codec.
Import ListNotations.
Open Scope string_scope.
Module IS := Selvedge.Interaction.Interactive.State.
Module IC := Selvedge.Interaction.Interactive.Codec.
Definition initial := IS.initial.
Definition storage_policy := JObject [("maximumDocuments",JNumber (Numbers.show_nat Bounds.stored_documents));
 ("maximumBytes",JNumber (Numbers.show_nat Bounds.stored_bytes));("prefix",JString "selvedge-interactive-v1/")].
Definition step_visible := Runtime.step_visible.
Definition step := Runtime.step.

(** Rendering requires the source established by document publication. An opaque
    interactive owner is not evidence of a message, viewer, or source identity. *)
Definition fence_for identity b environment :=
 let prepared:=Runtime.prepared b environment in
 let b:=IS.with_sources prepared.(Registry.sources) (IS.with_locals prepared.(prepared_locals) b) in
 let '(nodes,allocation):=Expand.expand b prepared environment in
 Render.fence identity b prepared nodes allocation.(Expand.remaining).
Definition shared_for identity b environment :=
 let prepared:=Runtime.prepared b environment in
 let b:=IS.with_sources prepared.(Registry.sources) (IS.with_locals prepared.(prepared_locals) b) in
 let '(nodes,allocation):=Expand.expand b prepared environment in
 Render.shared identity b prepared nodes allocation.(Expand.remaining).

(** The standalone language entry reduces admitted component state. The product
    UI is published through the application's actual document context above. *)
Definition decoded_step request :=
 encoded<-field "state" request;;state<-IC.decode_state encoded;;
 encoded<-field "input" request;;input<-Types.decode_input encoded;;environment<-field "environment" request;;
 let decision:=step input state environment in
 Some (JObject [("state",IC.encode_state decision.(next_state));
  ("effects",JArray (map Types.encode_effect decision.(effects))) ]).
Definition call operation request :=
 if String.eqb operation "initial" then Json.success (IC.encode_state initial) else
 if String.eqb operation "storage_policy" then Json.success storage_policy else
 if String.eqb operation "step" then match decoded_step request with
 |Some value=>Json.success value|None=>Json.failure "interactive_request" "Invalid interactive language request" end
 else Json.failure "interactive_operation" "Unknown interactive language operation".
