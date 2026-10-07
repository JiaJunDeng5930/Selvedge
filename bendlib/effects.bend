import Base
import ../harness/DOMAIN.bend as D
import ./json.bend as J

# The task effect alphabet is independent of every feature's private payload.
# Its extension parameter is carried opaquely by task-local code.
type Effect<-X: Data> is Data:
  RequestModel{task_id: Nat, ticket: Nat, model: D.Model, history: D.History,
    tools: +List<D.Tool>, callable: +List<String>, context: D.TaskContext}
  RequestReasoning{task_id: Nat, ticket: Nat, model: D.Model, history: D.History}
  ExecuteTool{task_id: Nat, ticket: Nat, tool: D.Tool, call: D.Call, context: D.TaskContext, access: D.ExecutionAccess}
  RequestApproval{task_id: Nat, ticket: Nat, reviewer: D.Profile, call: D.Call, context: D.TaskContext, history: D.History}
  CheckTool{task_id: Nat, ticket: Nat, plugin: D.PluginRef, tool: D.Tool, call: D.Call}
  CheckResult{task_id: Nat, ticket: Nat, operation_id: Nat, plugin: D.PluginRef, call: D.Call, value: J.Json, error: Bool}
  NotifyPlugins{events: +List<D.Notice>}
  RequestSummary{task_id: Nat, ticket: Nat, model: D.Model, history: D.History, context: D.TaskContext}
  CancelTask{task_id: Nat}
  CancelTicket{task_id: Nat, ticket: Nat}
  ContinueScheduling{}
  FeatureEffect{effect: X}
