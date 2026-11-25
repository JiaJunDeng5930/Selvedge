From Stdlib Require Import String List NArith.
From Selvedge.Kernel Require Import Codec Domain.

Inductive task_creation :=
| ExistingTask (task : N)
| CreateTask (profile : string) (settings : settings_request) (original_settings : option Selvedge.Foundation.Json.json) (each_delivery : bool).

Inductive node_kind := Entrance | Exit | TaskNode (creation : task_creation).
Record node := Node { node_key : string; node_behavior : node_kind }.

(* The connection's output expression uses the same language as a task graph. *)
Section Graph.
Context {Message : Type}.
Record connection := Connection {
 connection_key : string;
 connection_source : string;
 connection_target : string;
 connection_description : string;
 connection_message : Message
}.
Record definition := DefinitionOf {
 workflow_work : option N;
 workflow_name : string;
 workflow_nodes : list node;
 workflow_connections : list connection
}.
Record invocation := Invocation { invocation_graph : N; invocation_entrance : string }.
Record delivery := Delivery {
 delivery_node : string;
 delivery_content : content;
 delivery_source : option string
}.
Inductive path_state :=
| Pending (input : delivery)
| Executing (input : delivery) (task : N) (choice : option string)
| Forwarding (input : delivery) (task : N) (choice : option string) (answer : content)
| Arrived (exit : string) (source : option string) (result : content)
| Blocked (input : delivery) (reason : string).
Record path := Path { path_id : N; path_value : path_state }.
Record instance := Instance {
 instance_graph : N;
 instance_definition : definition;
 instance_card : option N;
 instance_project : option N;
 instance_entrance : string;
 instance_message_preview : string;
 instance_started_at : option N;
 instance_browser_launch : option string;
 instance_paths : list path;
 instance_tasks : list (string * N);
 instance_history : list (N * string * N);
 instance_next_path : N
}.
End Graph.

Definition path_in_progress (value : path) :=
 match path_value value with Pending _ | Executing _ _ _ | Forwarding _ _ _ _ => true | _ => false end.
Definition instance_in_progress {Message} (value : @instance Message) :=
 existsb path_in_progress (instance_paths value).
