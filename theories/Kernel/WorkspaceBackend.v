From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
Import ListNotations.
Open Scope string_scope.

Inductive backend := Local | TencentCvm.

Definition name (value : backend) :=
  match value with Local => "local" | TencentCvm => "tencent_cvm" end.

Definition declaration := KEnum (name Local) [name TencentCvm].

Definition to_value (value : backend) : denote declaration := match value with
 | Local => exist _ "local" (or_introl eq_refl)
 | TencentCvm => exist _ "tencent_cvm" (or_intror (or_introl eq_refl)) end.

Definition of_value (value : denote declaration) : backend :=
  if String.eqb (proj1_sig value) (name Local) then Local else TencentCvm.

Definition decode (value : string) : option backend :=
  match Schema.decode_value declaration (JString value) with
  | Some admitted => Some (of_value admitted)
  | None => None
  end.

Definition cloud (value : backend) :=
  match value with Local => false | TencentCvm => true end.

Lemma name_of_value : forall value, name (of_value value) = proj1_sig value.
Proof.
  intros [value member]. unfold of_value. simpl.
  unfold declaration in member. simpl in member.
  destruct member as [<- | [<- | []]]; reflexivity.
Qed.

Lemma decode_name : forall value, decode (name value) = Some value.
Proof. destruct value; reflexivity. Qed.
