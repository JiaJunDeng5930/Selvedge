From Stdlib Require Import List NArith.
From Selvedge.Foundation Require IndexedRegistry KeyedScope.

Record subscriptions := Subscriptions {
 monitored_task : N;
 monitoring_tasks : list N
}.

Definition observer_key (observer : N) := IndexedRegistry.key observer.
Definition observers (value : subscriptions) := map observer_key (monitoring_tasks value).
Definition registry := KeyedScope.t observers.
