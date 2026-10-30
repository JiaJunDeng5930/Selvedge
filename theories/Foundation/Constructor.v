From Stdlib Require Import List.

(** A constructor view is derived from the actual inductive constructor. Its
    projection retrieves the supplied value; it is not an arbitrary encoder. *)
Class View {input output} (inject : input -> output) := {
 project : output -> option input;
 project_inject : forall value, project (inject value) = Some value
}.
Arguments project {input output} inject {_} _.
Arguments project_inject {input output} inject {_} _.

Ltac constructor_head value :=
 lazymatch value with ?head ?argument => constructor_head head | _ => value end.
Ltac derive_constructor_view inject :=
 let input := lazymatch type of inject with ?input -> _ => input end in
 let expected := lazymatch input with
 | unit => let constructed := (eval hnf in (inject tt)) in constructor_head constructed
 | _ => constructor_head inject
 end in
 unshelve refine (@Build_View _ _ inject _ _);
 [ let value := fresh "constructed" in let Selected := fresh "Selected" in
   intro value; destruct value eqn:Selected;
   lazymatch type of Selected with
   | _ = ?actual =>
     first [ let head := constructor_head actual in constr_eq head expected;
       lazymatch input with
       | unit => exact (Some tt)
       | _ => lazymatch actual with ?head ?argument => exact (Some argument) end
       end
     | exact None ]
   end
 | let value := fresh "request" in intro value;
   lazymatch input with unit => destruct value | _ => idtac end; reflexivity ].

#[global] Hint Extern 2 (View ?inject) => derive_constructor_view inject : typeclass_instances.
