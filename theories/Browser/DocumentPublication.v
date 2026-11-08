From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Interaction Require Import CodeSource Origin Codec.
From Selvedge.Interaction.Interactive Require Types.
Import ListNotations.
Open Scope string_scope.

(** Publication affects the original Markdown fence, not a second source node
    invented by the component renderer. The physical host only applies this plan. *)
Inductive target := Toolbar | Body | Source | Frame | Preview.
Definition target_name value := match value with Toolbar=>"toolbar"|Body=>"body"
 |Source=>"source"|Frame=>"frame"|Preview=>"preview" end.
Definition target_key identity value := CodeSource.key identity ++ "/" ++ target_name value.
Definition encode_targets identity := JObject (map (fun t=>
 (target_name t,JString (target_key identity t))) [Toolbar;Body;Source;Frame;Preview]).
Record fence_policy := FencePolicy {
 fence_identity : CodeSource.identity;
 source_visible : bool;
 preview_active : bool
}.
Definition interactive identity exposed := FencePolicy identity exposed true.
Definition source_display policy := if source_visible policy then "block" else "none".
Definition source_properties policy : list (string * string) :=
 if preview_active policy then [("display",source_display policy)] else [].
Definition frame_properties policy : list (string * string) :=
 if preview_active policy then [("border","0");("background","transparent");("padding","0")] else [].
Definition frame_attributes policy :=
 if preview_active policy then [("data-interactive-active","true")] else [].
Definition encode_policy policy := JObject [
 ("targets",encode_targets (fence_identity policy));
 ("source_visible",JBool (source_visible policy));
 ("preview_active",JBool (preview_active policy))].

Theorem undisclosed_preview_hides_original_source : forall identity,
 source_properties (interactive identity false) = [("display","none")].
Proof. reflexivity. Qed.
Theorem disclosed_preview_restores_original_source : forall identity,
 source_properties (interactive identity true) = [("display","block")].
Proof. reflexivity. Qed.

(** A parser observation is correlated with a registered logical document. The
    source revision is its UTF-8 prefix length, so appends have one ordering. *)
Record document := PublishedDocument {
 published_namespace:string;
 published_viewer:N;
 published_origin:Origin.output_origin;
 published_epoch:N;
 published_text:string;
 published_ending:Types.ending
}.
Definition published_complete value := match published_ending value with Types.Complete=>true|_=>false end.
Definition published_code_source value := CodeSource.Generated (published_namespace value) (published_viewer value)
 (published_origin value) (published_complete value).
Definition published_revision value := N.of_nat (Utf8.byte_length (published_text value)).
Definition encode_document value := JObject [
 ("source",CodeSource.encode_source (published_code_source value));
 ("document_key",JString (CodeSource.source_key (published_code_source value)));
 ("origin",Origin.observation_origin (published_namespace value) (published_viewer value) (published_origin value));
 ("epoch",number (published_epoch value));("revision",number (published_revision value));
 ("ending",JString (Types.ending_name (published_ending value)))].
