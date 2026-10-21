From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Import Numbers Context Compaction ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Definition frame_bytes : N := 4194304.
Definition schedule_steps : nat := 256.
Definition operation_limit : N := 64.
Definition plugin_limit : N := 16.
Definition plugin_events := ["task_created";"task_changed";"model_started";"model_completed";"tool_requested";"tool_dispatched";"tool_completed";"hook_completed";"recovered";"configured"].
Definition boundary_limits := JObject [
 ("frame_bytes", number frame_bytes); ("header_bytes", number 16384);
 ("request_timeout_ms", number 5000); ("tool_output_bytes", number 65536);
 ("approval_reason_bytes", number ApprovalProtocol.reason_bytes); ("mcp_catalog_tools", number 1024);
 ("mcp_timeout_ms", number 30000); ("plugin_timeout_ms", number 10000);
 ("plugin_event_timeout_ms", number 5000); ("plugin_catalog_tools", number 1024);
 ("plugin_event_queue", number 128); ("bash_default_output_length", number 40000);
 ("bash_max_output_length", number 65536); ("operations_per_task", number operation_limit);
 ("artifact_bytes", number 8388608); ("summary_limit_bytes", number Compaction.summary_limit_bytes);
 ("project_context_bytes", number Context.project_limit);
 ("model_retry", JObject [("statuses", JArray (map number [408%N;429%N;500%N;502%N;503%N;504%N]));
   ("delays_ms", JArray (map number [250%N;1000%N;2500%N])); ("max_retry_after_ms", number 60000)])].
