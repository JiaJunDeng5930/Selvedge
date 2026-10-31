From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require ArgumentDeclaration Utf8.
From Selvedge.Kernel Require Import Context WorkspacePath.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.

(** A file observation belongs to one workspace even when no guidance file
    exists there. Its present/absent syntax survives admission and storage. *)
Definition case_declaration (path revision instructions : D.t) := D.Object
 [("workspace",true,WorkspacePath.declaration);("path",true,path);("revision",true,revision);
  ("instructions",true,instructions)].
Definition body_declaration := D.Union
 [case_declaration (D.Const (JString "")) (D.Const (JString "absent")) (D.Const (JString ""));
  case_declaration ContextTypes.required_text (D.exact_lower_hex 64)
    (D.Text (D.TextConstraints 0 D.maximum_natural 32768 true false false None))].
Definition declaration := D.nullable body_declaration.
Definition source_root (value : D.denote body_declaration) : string :=
 match value with inl fields | inr (inl fields) => proj1_sig (fst (proj1_sig fields))
 | inr (inr impossible) => match impossible with end end.
Definition admissible (value : D.denote body_declaration) :=
 WorkspacePath.canonical (source_root value) && match value with
 | inl _ => true
 | inr (inl fields) => existsb (String.eqb (proj1_sig (fst (snd (proj1_sig fields)))))
     (ContextTypes.policy_paths Context.guidance_policy (source_root value))
 | inr (inr impossible) => match impossible with end end.
Definition observation := D.checked admissible.
Definition t := option observation.
Definition root (value : observation) := source_root (proj1_sig value).
Definition of_values (values : D.denote declaration) : option t := match values with
 | inl value => option_map Some (D.admit admissible value)
 | inr (inl _) => Some None
 | inr (inr impossible) => match impossible with end end.
Definition parse source := match D.decode declaration source with Some values => of_values values | None => None end.
Definition json (value : t) := match value with
 | Some value => D.encode body_declaration (proj1_sig value) | None => JNull end.
Definition same (left right : t) := Json.equal (json left) (json right).

(** Dropping text restrictions is a type projection; it never runs a second
    parser. The source declaration's bounds discharge this once for every use. *)
Definition required_text (constraints : D.text_constraints)
 (Minimum : (1 <= D.minimum_characters constraints)%N)
 (Characters : (D.maximum_characters constraints <= D.maximum_natural)%N)
 (Bytes : (D.maximum_bytes constraints <= D.maximum_natural)%N)
 (value : D.denote (D.Text constraints)) : D.denote ContextTypes.required_text.
Proof.
 destruct value as [text Accepted]; exists text.
 unfold D.check_text in Accepted |- *.
 destruct (Utf8.scalar_count text) as [count|]; [|discriminate].
 repeat rewrite Bool.andb_true_iff in Accepted; destruct Accepted as [[[[[Range Size] _] _] _] _].
 unfold D.in_bounds in Range; apply Bool.andb_true_iff in Range; destruct Range as [Low High].
 apply N.leb_le in Low; apply N.leb_le in High; apply N.leb_le in Size.
 cbn; rewrite !Bool.andb_true_r; apply Bool.andb_true_iff; split.
 - apply Bool.andb_true_iff; split; apply N.leb_le; lia.
 - apply N.leb_le; lia.
Defined.
Definition workspace_text := required_text WorkspacePath.constraints ltac:(vm_compute; discriminate) ltac:(vm_compute; discriminate) ltac:(vm_compute; discriminate).
Definition revision_text := required_text (D.TextConstraints 64 64 64 false false true None)
 ltac:(vm_compute; discriminate) ltac:(vm_compute; discriminate) ltac:(vm_compute; discriminate).
Definition selected_path (paths : list string) (value : D.denote ContextTypes.required_text)
 (Selected : existsb (String.eqb (proj1_sig value)) paths = true)
 : D.denote (ContextTypes.path_declaration true paths).
Proof.
 destruct value as [text Accepted]; cbn in Selected; exists text.
 unfold D.check_text in Accepted |- *.
 destruct (Utf8.scalar_count text); [|discriminate].
 cbn; rewrite Selected; exact Accepted.
Defined.
Definition snapshot (value : observation) : option ContextTypes.snapshot.
Proof.
 destruct value as [source Accepted].
 destruct source as [absent|[present|impossible]]; [exact None| |destruct impossible].
 destruct present as [[workspace [path [revision [instructions done]]]] Unique].
 destruct workspace as [workspace Bounds].
 apply Bool.andb_true_iff in Accepted; destruct Accepted as [_ Selected].
 let key := constr:(ContextKey Context.project_guidance
   (exist _ (workspace_text (exist _ workspace Bounds),tt) eq_refl)) in
 refine (Some (Snapshot key (inl (revision_text revision)) _)).
 refine (exist _ (proj1_sig instructions,(selected_path _ path _,(tt,(tt,tt)))) eq_refl).
 exact Selected.
Defined.
Definition initial (value : t) := match value with Some observed => snapshot observed | None => None end.
