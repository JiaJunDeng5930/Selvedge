From Stdlib Require Import String.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Context Domain Compaction Conversation ContextSelection.
From Selvedge.Adapters Require Import Common Rpc Configuration Http Effects Audio AccountTransport BrowserAdapters Plugins Evaluator Accounts Web Backends.
Open Scope string_scope.

Definition call (operation : string) (source : json) : json :=
  if starts operation "account." then Accounts.call operation source
  else if starts operation "web." then Web.call operation source
  else if starts operation "backend." then Backends.call ContextSelection.target_messages operation source
  else if starts operation "rpc." then Rpc.call operation source
  else if starts operation "config." then Configuration.call
    Context.definitions_json (Domain.environment_instructions Domain.empty_environment)
    Compaction.legal_budget operation source
  else if starts operation "http." then Http.call operation source
  else if starts operation "effect." then Effects.call operation source
  else if starts operation "browser." then BrowserAdapters.call operation source
  else if starts operation "audio." then Audio.call
    AccountTransport.catalog_transport
    Conversation.json_message_assistant Conversation.json_message_content operation source
  else if starts operation "plugin." then Plugins.call operation source
  else if starts operation "evaluator." then Evaluator.call operation source
  else failure "Error" ("Unknown host model operation: " ++ operation).
