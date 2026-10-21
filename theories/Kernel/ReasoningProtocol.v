From Stdlib Require Import List Bool NArith.
Import ListNotations.
Definition lease_generations : list N := [1%N; 2%N; 5%N; 10%N].
Definition valid_generations (maximum generations : N) :=
  existsb (N.eqb generations) lease_generations && N.leb generations maximum.
