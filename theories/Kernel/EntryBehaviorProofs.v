From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Packet.
Import ListNotations.
Open Scope string_scope.

Definition first_task_configuration := JObject [
 ("kind",JString "configure");
 ("profiles",JArray [JObject [("key",JString "fixture");("provider",JString "responses");
   ("name",JString "fixture");("reasoning_options",JNull)]]);
 ("tools",JArray []);("max_fork",JNumber "4");("max_descendants",JNumber "8");
 ("instructions",JObject [("configured",JString "")])].
Definition first_task_command := JObject [("kind",JString "command");
 ("command",JObject [("op",JString "create");("profile",JString "fixture");
   ("message",JString "First user input")])].

(* A positive requirement at the exported entry also excludes an implementation
   that silently removes all scheduling while preserving its safety properties. *)
Theorem the_initial_public_create_commits_input_and_dispatches_context :
 let configured := fst (Packet.packet first_task_configuration State.initial) in
 let '(committed,envelope) := Packet.packet first_task_command configured in
 List.length (world_tasks committed) = 1%nat /\
 (match find_task 0 committed with
 | Some created => In (UserMessage [TextPart "First user input"]) (task_history created)
 | None => False end) /\
 existsb (fun request => String.eqb (text_default "kind" request "") "observe_context" &&
   match natural_field "task_id" request with Some id => N.eqb id 0 | None => false end)
   (array_default "effects" envelope) = true.
Proof. vm_compute; repeat split; auto. Qed.
