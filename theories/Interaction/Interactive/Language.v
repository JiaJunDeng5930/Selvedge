From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Scene.
From Selvedge.Interaction.Interactive Require Import Bounds Types State Registry Expand Render Runtime Codec.
Import ListNotations.
Open Scope string_scope.
Definition initial := State.initial.
Definition storage_policy := JObject[("maximumDocuments",JNumber(Numbers.show_nat Bounds.stored_documents));
 ("maximumBytes",JNumber(Numbers.show_nat Bounds.stored_bytes));("prefix",JString "selvedge-interactive-v1/")].
Definition step_visible := Runtime.step_visible.
Definition step := Runtime.step.
Definition scene_for b environment :=
 let prepared:=Runtime.prepared b environment in
 let b:=State.with_sources prepared.(Registry.sources)(State.with_locals prepared.(prepared_locals)b)in
 let '(nodes,allocation):=Expand.expand b prepared environment in
 Render.block_scene b prepared nodes allocation.(Expand.remaining).
Definition observe_owner who state environment :=
 match State.find_block who state.(blocks)with
 |Some b=>Some(scene_for b environment)|None=>None end.
Definition observe_visible (visible:owner->bool) state environment : Scene.scene Types.input :=
 Scene.Container Scene.CGroup "interactive-documents" [] None
 (map(fun b=>scene_for b environment)(filter(fun b=>visible b.(block_owner))state.(blocks))).
Definition observe:=observe_visible(fun _=>true).
Definition decoded_step request :=
 encoded <- field "state"request;;state <- Codec.decode_state encoded;;
 encoded <- field "input"request;;input <- Types.decode_input encoded;;environment <- field "environment"request;;
 let decision:=step input state environment in
 Some(JObject[("state",Codec.encode_state decision.(next_state));
 ("effects",JArray(map Types.encode_effect decision.(effects)));
 ("scene",Scene.encode Types.encode_input(observe decision.(next_state)environment))]).
Definition decoded_observe request :=
 encoded <- field "state"request;;state <- Codec.decode_state encoded;;environment <- field "environment"request;;
 Some(Scene.encode Types.encode_input(observe state environment)).
Definition call operation request :=
 if String.eqb operation "initial"then Json.success(Codec.encode_state initial)else
 if String.eqb operation "storage_policy"then Json.success storage_policy else
 let result:=if String.eqb operation "step"then decoded_step request else
   if String.eqb operation "observe"then decoded_observe request else None in
 match result with Some value=>Json.success value|None=>Json.failure "interactive_request" "Invalid interactive language request"end.
