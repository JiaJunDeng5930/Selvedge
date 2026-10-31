Definition observe {A B : Type} (source : option A)
 (present : forall value, source = Some value -> B) (absent : source = None -> B) : B :=
 match source as found return source = found -> B with
 | Some value => present value | None => absent end eq_refl.
