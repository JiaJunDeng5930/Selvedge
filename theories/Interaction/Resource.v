From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

(** A completed observation retains its request, so its owner and trigger cannot drift. *)
Inductive resource (A B:Type) :=
| Dormant | Loading (ticket:N) (request:A) | Loaded (ticket:N) (request:A) (value:B)
| Failed (ticket:N) (request:A) (reason:string).
Arguments Dormant {A B}.
Arguments Loading {A B}.
Arguments Loaded {A B}.
Arguments Failed {A B}.
Definition resource_request {A B} (r:resource A B) : option A :=
 match r with Dormant=>None|Loading _ request|Loaded _ request _|Failed _ request _=>Some request end.
Definition resource_ticket {A B} (r:resource A B) : option N :=
  match r with Dormant => None | Loading t _ | Loaded t _ _ | Failed t _ _ => Some t end.
Definition settle {A B} (ticket:N) (result:sum string B) (r:resource A B) : resource A B :=
  match r with
  | Loading current request =>
      if N.eqb current ticket then
        match result with inl error => Failed current request error | inr value => Loaded current request value end
      else r
  | _ => r
  end.
Definition encode_resource {A B} (ea:A->json) (eb:B->json) (r:resource A B) : json :=
  match r with
  | Dormant => JObject [("status",JString "idle")]
  | Loading t a => JObject [("status",JString "loading");("ticket",number t);("request",ea a)]
  | Loaded t a b => JObject [("status",JString "ready");("ticket",number t);("request",ea a);("value",eb b)]
  | Failed t a e => JObject [("status",JString "failed");("ticket",number t);("request",ea a);("error",JString e)]
  end.
Definition decode_resource {A B} (da:json->option A) (db:json->option B) (j:json) : option(resource A B) :=
  match string_field "status" j with
  | Some "idle" => Some Dormant
  | Some "loading" => t <- natural_field "ticket" j ;; a <- bind (field "request" j) da ;; Some(Loading t a)
  | Some "ready" => t <- natural_field "ticket" j ;; a <- bind (field "request" j) da ;; b <- bind (field "value" j) db ;; Some(Loaded t a b)
  | Some "failed" => t <- natural_field "ticket" j ;; a <- bind (field "request" j) da ;; e <- string_field "error" j ;; Some(Failed t a e)
  | _ => None
  end.

Theorem stale_completion_preserves_resource : forall A B t u a result,
  t <> u -> @settle A B t result (Loading u a) = Loading u a.
Proof. intros. unfold settle. destruct (N.eqb u t) eqn:E; auto. apply N.eqb_eq in E; congruence. Qed.
Theorem completion_requires_pending : forall A B t result (r:resource A B),
  (forall u a, r <> Loading u a) -> settle t result r = r.
Proof. intros A B t result r H. destruct r as [|u a|u a b|u a e]; simpl; auto. exfalso. apply (H u a). reflexivity. Qed.
Theorem accepted_completion_retains_owner : forall A B t (a:A) (b:B),
  settle t (inr b) (Loading t a) = Loaded t a b.
Proof. intros. unfold settle. now rewrite N.eqb_refl. Qed.
