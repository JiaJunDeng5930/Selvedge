# AGENTS.md

This file is for coding agents working in this repository.

## Start Here

- Read [README.md](./README.md) first for the repository-level workflow.
- Before you call or modify a module, read that module's `README.md` first.
- If the relevant `README.md` already answers your question, do not open the module internals first.

## Git Hooks

- `pre-commit` checks `cargo fmt --all -- --check`
- `pre-commit` checks `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- `pre-commit` checks that the project index in this file is up to date
- `pre-commit` checks requirement comments with `cargo xtask req check --staged`
- `pre-commit` checks package README Mermaid diagrams with `cargo xtask readme check-mermaid`
- `pre-push` checks `cargo test --workspace --all-targets --all-features`
- `pre-push` checks package README freshness metadata with `cargo xtask readme check-freshness`

## Package README State Machines

- Each workspace package README contains a Mermaid package-level state machine.
- Read the package state machine before changing package behavior or boundary errors.
- Package README metadata includes `freshness_commit`, the commit whose package implementation the README state machine has been checked against.
- `cargo xtask readme check-freshness` compares `freshness_commit..HEAD` for each package directory, excludes that package README, and reports packages with implementation changes that may require README review.
- When reported package changes leave the README state machine accurate, update only `freshness_commit` to a commit after those package changes.

## Branch Protection

- `main` is a protected branch.
- Do not commit work directly on `main`.
- Do not use `main` as the active branch for task work unless the user explicitly asks for a change on `main`.

## Branch And Worktree Workflow

- Default workflow: if the user does not explicitly ask for multi-branch parallel development, create or switch branches in the repository root and work there.
- Only use `just worktree <branch-name>` when the user explicitly asks for multi-branch parallel development.
- When the user explicitly asks for multi-branch parallel development, keep the repository root on `main`; do not turn the root checkout into a feature branch.
- A branch created from the repository root should place its worktree under the repository root `.worktrees/`.
- A branch created from an existing worktree should place its child worktree under that worktree's own `.worktrees` namespace, not under the repository root `.worktrees/`.
- Child worktrees must not live inside their parent worktree checkout; keep them in that parent worktree's adjacent `.worktrees` storage so removing the parent does not delete the child.
- Do not use this helper from a worktree that lives outside the repository root `.worktrees/` hierarchy; fail fast instead of creating worktrees in ad-hoc locations.
- Do not flatten every parallel branch worktree into the repository root `.worktrees/` when the new branch belongs under an existing branch worktree.
- Each `.worktrees/` directory must stay Git-ignored. Fail fast if the ignore rule is missing.
- When working inside a worktree, only edit files inside that worktree and that worktree's own `.workpad/`.
- Do not edit parent directories, sibling worktrees, or any ancestor `.workpad/` while working inside a worktree.
- Each worktree should stay focused on one task so review and cleanup remain straightforward.

## Working Notes

- Unless the user explicitly asks otherwise, place temporary task documents (such as specs, plans, and research notes) under `.workpad/`.
- `.workpad/` is git-ignored on purpose and should be used for task artifacts that should not be committed.

## Code Marker Comments

- Allowed tags: `TODO`, `FIXME`, `HACK`, `NOTE`, `XXX`.
- Format: `<comment marker> <TAG>(<optional issue>): <specific action or reason>`.
- Marker comments must explain the intent, decision, risk, or follow-up behind the code. Do not use marker comments to restate facts already visible from the code.
- `TODO` means known follow-up work while current code is acceptable.
- `FIXME` means a known defect that needs repair.
- `HACK` means a temporary workaround that should be replaced by normal design.
- `NOTE` means important context that affects code understanding.
- `XXX` means high-risk code that needs reviewer attention.

## Requirement Comments

- Requirement truth lives only in source comments next to Rust code.
- Requirement comments use `@behavior`, `@constraint`, `@intent`, and `@verifies`.
- `@behavior`, `@constraint`, and `@intent` comment bodies are one sentence.
- `@behavior` states externally observable system behavior: user-visible tasks, messages, commands, process output, persisted files, database data, network/API requests, network/API responses, or caller-visible results.
- Write `@behavior` sentences in terms of the external task, command, stored data, or network interaction affected by the code.
- Internal mechanisms such as helper functions, adapters, envelopes, queues, and in-memory plumbing are placement context for nearby comments.
- `@constraint` states an externally meaningful invariant, boundary, or limit that visible behavior must preserve.
- `@intent` states the externally relevant purpose of an abstraction, adapter, interface, registry, extension point, migration bridge, or compatibility layer.
- `@verifies` IDs are direct references to existing IDs declared by `@behavior` or `@constraint`.
- `@verifies` contains only the tag and referenced ID.
- One `@verifies` reference verifies the referenced requirement and every descendant requirement under that ID.
- Declare each requirement body with `@behavior` or `@constraint` near production code before tests reference that ID with `@verifies`.
- When a test needs a narrower ID, add the narrower requirement declaration near the production code before referencing it from `@verifies`.
- Dotted IDs form an arbitrary-depth requirement tree.
- Each requirement node states one externally meaningful commitment at its tree depth.
- Each child node states the next direct externally meaningful commitment, branch, boundary, invariant, side effect, or failure path needed to make the parent true.
- Sibling nodes should read like the immediate observable answers that appear when the parent requirement is examined one layer deeper.
- Package names, directories, and architecture layers are retrieval context for locating the source comment.
- Details belong in narrower descendant IDs near the code units that implement them.
- The generated requirement index helps agents find IDs; the full sentence lives in the source comment.
- Search source comments for an ID before changing Rust behavior, constraints, structural abstractions, or tests.
- After changing requirement tags, run `cargo xtask req fmt-agents` and stage `AGENTS.md`.
- Before committing, run `cargo xtask req check --staged` to validate staged Rust hunks against nearby requirement anchors.
- CI runs `cargo xtask req check --all` to validate every tracked Rust source line in the checkout against nearby requirement anchors.
- CI runs `cargo xtask req check --base <git-ref>` to validate changed Rust hunks against the merge-base snapshot.
- Generated requirement index rows are updated only through `cargo xtask req fmt-agents`.

## Requirement Index

<!-- BEGIN AGENTS_MD_REQUIREMENT_INDEX -->
[Requirement Index]|root:.
|IMPORTANT: Requirement truth lives in source comments; search source comments for an ID before changing code.
|source:source_comments_only
|comment_body:single_sentence
|tags:{@behavior,@constraint,@intent,@verifies}
|selvedge|selvedge.{auth,cli,client,config,core,login,model,operations,session,startup,state,task,testsupport}
|selvedge.auth|selvedge.auth.{config,errors,file,jwt,lock,refresh,resolve,resolved}
|selvedge.auth.config|selvedge.auth.config.{client_id,error,expected_workspace,home,issuer,read,valid}
|selvedge.auth.config.valid|selvedge.auth.config.valid.{base,client_id,http,issuer,read,settings_type,userinfo,workspace}
|selvedge.auth.config.valid.settings_type|selvedge.auth.config.valid.settings_type.{read}
|selvedge.auth.file|selvedge.auth.file.{credential_kind_field,load,parse,parse_errors,path,persist,provider_field,refresh_hint,required_string,schema_field,schema_version,tokens,tokens_field}
|selvedge.auth.file.load|selvedge.auth.file.load.{malformed}
|selvedge.auth.file.parse|selvedge.auth.file.parse.{credential_kind,provider,schema,unsupported_schema}
|selvedge.auth.file.persist|selvedge.auth.file.persist.{directory,encode,parent,replace,temp,write}
|selvedge.auth.file.required_string|selvedge.auth.file.required_string.{empty}
|selvedge.auth.file.schema_version|selvedge.auth.file.schema_version.{range}
|selvedge.auth.file.tokens|selvedge.auth.file.tokens.{access_field,id_field,refresh_field,required}
|selvedge.auth.jwt|selvedge.auth.jwt.{claims,errors,expiration,header,json,optional_object_string,optional_string,parse,segments}
|selvedge.auth.jwt.claims|selvedge.auth.jwt.claims.{account_field,email_field,expiration_field,plan_field,subject_field,user_field}
|selvedge.auth.jwt.parse|selvedge.auth.jwt.parse.{claims}
|selvedge.auth.lock|selvedge.auth.lock.{directory,exclusive,file,guard,join,open,parent,path,path_error,release,table}
|selvedge.auth.refresh|selvedge.auth.refresh.{access_token,access_usable,diagnostics,diagnostics_fields,diagnostics_struct,diagnostics_value,error_status,id_token,invalid_success,merge,merge_optional,reauthentication_codes,request,response,success_json,success_shape,transport}
|selvedge.auth.refresh.access_token|selvedge.auth.refresh.access_token.{changed,empty,required,usable}
|selvedge.auth.refresh.id_token|selvedge.auth.refresh.id_token.{empty,required}
|selvedge.auth.refresh.merge_optional|selvedge.auth.refresh.merge_optional.{empty}
|selvedge.auth.resolve|selvedge.auth.resolve.{access_expiration,access_expires_at,concurrent_reuse,existing,flow,id_token_account,refresh_decision,refreshed,request,unauthorized,workspace,workspace_mismatch}
|selvedge.auth.resolve.request|selvedge.auth.resolve.request.{entry}
|selvedge.auth.resolve.unauthorized|selvedge.auth.resolve.unauthorized.{entry}
|selvedge.auth.resolved|selvedge.auth.resolved.{access_field,account_field,email_field,expiration_field,plan_field,user_field}
|selvedge.cli|selvedge.cli.{args,command,command_id,config,config_error,default_server_args_builder,deps,error,invalid_args,list_models,local_client,local_connector,logging_error,name,parse,parse_client_id_duplicate,parse_client_id_empty,parse_client_id_missing,process,provider_login_chatgpt,ready_probe,run,server,server_args,server_args_builder,server_runner,server_starter,startup_message,status,submit}
|selvedge.cli.args|selvedge.cli.args.{argv}
|selvedge.cli.command_id|selvedge.cli.command_id.{counter}
|selvedge.cli.config|selvedge.cli.config.{default,defaults,failed,local_client,loopback,read,ready_poll_interval,ready_timeout,systemd,uninitialized}
|selvedge.cli.default_server_args_builder|selvedge.cli.default_server_args_builder.{abstraction,contract,new}
|selvedge.cli.deps|selvedge.cli.deps.{argument_parse,invalid_args}
|selvedge.cli.list_models|selvedge.cli.list_models.{executor,parse}
|selvedge.cli.list_models.executor|selvedge.cli.list_models.executor.{config_error,home_error,list_error,output}
|selvedge.cli.local_client|selvedge.cli.local_client.{abstraction,attach,close,contract,default,default_attach,default_close,default_ready,default_submit,error,ready,submit}
|selvedge.cli.local_connector|selvedge.cli.local_connector.{abstraction,client,connect,contract,default_client,default_connect,default_struct}
|selvedge.cli.parse|selvedge.cli.parse.{command_name,extra_positional,flag,payload}
|selvedge.cli.process|selvedge.cli.process.{exit_code,main,stderr}
|selvedge.cli.provider_login_chatgpt|selvedge.cli.provider_login_chatgpt.{executor,progress}
|selvedge.cli.provider_login_chatgpt.executor|selvedge.cli.provider_login_chatgpt.executor.{failure}
|selvedge.cli.provider_login_chatgpt.progress|selvedge.cli.provider_login_chatgpt.progress.{closed,diagnostic_closed}
|selvedge.cli.ready_probe|selvedge.cli.ready_probe.{connect,ready}
|selvedge.cli.server_args|selvedge.cli.server_args.{empty_snapshot,tool_unavailable,unsupported_command}
|selvedge.cli.server_args_builder|selvedge.cli.server_args_builder.{abstraction,build,contract}
|selvedge.cli.server_runner|selvedge.cli.server_runner.{abstraction,contract,run}
|selvedge.cli.server_starter|selvedge.cli.server_starter.{abstraction,contract,default,start}
|selvedge.cli.server_starter.default|selvedge.cli.server_starter.default.{error,path_error}
|selvedge.cli.submit|selvedge.cli.submit.{attach_cleanup,attach_error,attach_gate,command_id_error,deadline,deadline_overflow,empty_snapshot,outcome,ready_existing,ready_timeout,retry_sleep,service_unready,service_wait_error,submit_error,terminal_frame}
|selvedge.cli.submit.empty_snapshot|selvedge.cli.submit.empty_snapshot.{closed,first_frame,non_empty,stream_error}
|selvedge.cli.submit.terminal_frame|selvedge.cli.submit.terminal_frame.{closed,stream_error}
|selvedge.client|selvedge.client.{blocking,body,command_id,compression,config,delivery_seq,detach_reason,error,event,events,execute,frame,history_projection,id,local,log,method,notice,protocol,redaction,redirect,request,response,snapshot,status,stream,subscription,sync,task_projection,timeout,tls,transport,tui,web}
|selvedge.client.command_id|selvedge.client.command_id.{validation}
|selvedge.client.config|selvedge.client.config.{ca_bundle_path,connect_timeout,log,override,read,request_timeout,resolve,stream_idle_timeout,timeout,user_agent}
|selvedge.client.config.ca_bundle_path|selvedge.client.config.ca_bundle_path.{home_error,relative}
|selvedge.client.error|selvedge.client.error.{build,display,source}
|selvedge.client.event|selvedge.client.event.{debug_notice,history_appended,model_call_status,task_changed,tool_status}
|selvedge.client.event.debug_notice|selvedge.client.event.debug_notice.{message,task_id}
|selvedge.client.event.history_appended|selvedge.client.event.history_appended.{nodes,task_id,version}
|selvedge.client.event.model_call_status|selvedge.client.event.model_call_status.{model_call_id,phase,task_id}
|selvedge.client.event.task_changed|selvedge.client.event.task_changed.{task}
|selvedge.client.event.tool_status|selvedge.client.event.tool_status.{node_id,phase,run_id,task_id,tool_name}
|selvedge.client.events|selvedge.client.events.{control,detach,hydration,ingress,notice_delivery,raw,reserve,sender,snapshot_delivery,subscription_update}
|selvedge.client.events.detach|selvedge.client.events.detach.{client_id,command_id,reason}
|selvedge.client.events.hydration|selvedge.client.events.hydration.{client_id,command_id,outbound,subscription}
|selvedge.client.events.notice_delivery|selvedge.client.events.notice_delivery.{client_id,command_id,notice}
|selvedge.client.events.raw|selvedge.client.events.raw.{debug,history_appended,model_call_status,task_changed,tool_status}
|selvedge.client.events.raw.debug|selvedge.client.events.raw.debug.{message,task_id}
|selvedge.client.events.raw.history_appended|selvedge.client.events.raw.history_appended.{nodes,task_id,version}
|selvedge.client.events.raw.model_call_status|selvedge.client.events.raw.model_call_status.{model_call_id,phase,task_id}
|selvedge.client.events.raw.task_changed|selvedge.client.events.raw.task_changed.{task}
|selvedge.client.events.raw.tool_status|selvedge.client.events.raw.tool_status.{node_id,phase,run_id,task_id,tool_name}
|selvedge.client.events.reserve|selvedge.client.events.reserve.{client_id,command_id,responder,result,result_sender}
|selvedge.client.events.snapshot_delivery|selvedge.client.events.snapshot_delivery.{client_id,command_id,snapshot}
|selvedge.client.events.subscription_update|selvedge.client.events.subscription_update.{client_id,command_id,subscription}
|selvedge.client.execute|selvedge.client.execute.{inner,log,status}
|selvedge.client.frame|selvedge.client.frame.{event,notice,sender,snapshot}
|selvedge.client.frame.event|selvedge.client.frame.event.{delivery_seq,payload}
|selvedge.client.frame.notice|selvedge.client.frame.notice.{command_id,delivery_seq,payload}
|selvedge.client.frame.snapshot|selvedge.client.frame.snapshot.{command_id,delivery_seq,payload}
|selvedge.client.history_projection|selvedge.client.history_projection.{body,body_field,created_at,node_id,parent_node_id}
|selvedge.client.id|selvedge.client.id.{validation}
|selvedge.client.local|selvedge.client.local.{attach,attach_result,client,close,command,config,connect,connect_http,endpoint,error,failure,frame_stream,http,http_transport,ready,request,state,state_machine,stream,transport}
|selvedge.client.local.attach|selvedge.client.local.attach.{client_error,generation,rejected,state,success,timeout,validate}
|selvedge.client.local.attach.state|selvedge.client.local.attach.state.{already_attached,busy,closed,closing,disconnected,failed}
|selvedge.client.local.client|selvedge.client.local.client.{abstraction}
|selvedge.client.local.close|selvedge.client.local.close.{call,cancel,complete,state}
|selvedge.client.local.close.state|selvedge.client.local.close.state.{busy,closed,closing}
|selvedge.client.local.command|selvedge.client.local.command.{validate}
|selvedge.client.local.config|selvedge.client.local.config.{endpoint,timeout}
|selvedge.client.local.connect|selvedge.client.local.connect.{call,transport}
|selvedge.client.local.connect_http|selvedge.client.local.connect_http.{call}
|selvedge.client.local.endpoint|selvedge.client.local.endpoint.{host_header,socket,valid}
|selvedge.client.local.failure|selvedge.client.local.failure.{pending}
|selvedge.client.local.frame_stream|selvedge.client.local.frame_stream.{abstraction}
|selvedge.client.local.http|selvedge.client.local.http.{attach,attach_accept,attach_reject,close,command,connect,content_type,frame_line,header_line,headers,json_body,post,problem,ready,status,stream,stream_item}
|selvedge.client.local.http.attach|selvedge.client.local.http.attach.{call,reject_status,status}
|selvedge.client.local.http.attach_accept|selvedge.client.local.http.attach_accept.{call,empty,first_item,identity,sequence_errors}
|selvedge.client.local.http.attach_reject|selvedge.client.local.http.attach_reject.{body,call,identity,identity_error,invalid,rejected}
|selvedge.client.local.http.command|selvedge.client.local.http.command.{call,identity}
|selvedge.client.local.http.content_type|selvedge.client.local.http.content_type.{unexpected}
|selvedge.client.local.http.frame_line|selvedge.client.local.http.frame_line.{accepted_late,call,frame,stream_error}
|selvedge.client.local.http.header_line|selvedge.client.local.http.header_line.{call,closed}
|selvedge.client.local.http.json_body|selvedge.client.local.http.json_body.{call,parse,status}
|selvedge.client.local.http.post|selvedge.client.local.http.post.{body,call,connect,flush,headers}
|selvedge.client.local.http.stream|selvedge.client.local.http.stream.{ended,eof,io_error,poll}
|selvedge.client.local.ready|selvedge.client.local.ready.{validate}
|selvedge.client.local.request|selvedge.client.local.request.{cancel,finish,state,success}
|selvedge.client.local.request.finish|selvedge.client.local.request.finish.{call,error,success,timeout}
|selvedge.client.local.request.state|selvedge.client.local.request.state.{busy,closed,closing,disconnected,failed}
|selvedge.client.local.state|selvedge.client.local.state.{read,resolve}
|selvedge.client.local.stream|selvedge.client.local.stream.{clear,closed_by_client,drop,poll,wake}
|selvedge.client.local.stream.clear|selvedge.client.local.stream.clear.{drop,stale}
|selvedge.client.local.stream.poll|selvedge.client.local.stream.poll.{after_closed,client_closed,error,frame}
|selvedge.client.local.stream.wake|selvedge.client.local.stream.wake.{reader}
|selvedge.client.local.transport|selvedge.client.local.transport.{abstraction,attach,close,command,connect,content_type,ready,response}
|selvedge.client.local.transport.attach|selvedge.client.local.transport.attach.{call}
|selvedge.client.local.transport.close|selvedge.client.local.transport.close.{call}
|selvedge.client.local.transport.command|selvedge.client.local.transport.command.{call}
|selvedge.client.local.transport.connect|selvedge.client.local.transport.connect.{call}
|selvedge.client.local.transport.ready|selvedge.client.local.transport.ready.{call}
|selvedge.client.log|selvedge.client.log.{failure,finish,macro,status,stream,stream_failure,stream_status,timeout_absent,transport}
|selvedge.client.method|selvedge.client.method.{reqwest,string}
|selvedge.client.notice|selvedge.client.notice.{kind,kind_field,level,level_field,message}
|selvedge.client.protocol|selvedge.client.protocol.{attach,attach_stream,client_id,command,command_id,delivery_seq,event,frame,history_projection,http_problem,message_role,model_status_phase,notice,ready,reasoning_effort,snapshot,subscription,task_id,task_projection,tool_argument,tool_name,tool_status_phase,validation_error}
|selvedge.client.protocol.attach|selvedge.client.protocol.attach.{accepted,reject_reason,rejected,request,validation}
|selvedge.client.protocol.attach.accepted|selvedge.client.protocol.attach.accepted.{client_id,command_id}
|selvedge.client.protocol.attach.rejected|selvedge.client.protocol.attach.rejected.{command_id,reason}
|selvedge.client.protocol.attach.request|selvedge.client.protocol.attach.request.{client_id,command_id,subscription}
|selvedge.client.protocol.attach_stream|selvedge.client.protocol.attach_stream.{error,error_reason,item,item_validation,order_error,state,validator}
|selvedge.client.protocol.attach_stream.error|selvedge.client.protocol.attach_stream.error.{command_id,message,reason}
|selvedge.client.protocol.attach_stream.item_validation|selvedge.client.protocol.attach_stream.item_validation.{error_text}
|selvedge.client.protocol.attach_stream.validator|selvedge.client.protocol.attach_stream.validator.{default,new,next,state,state_storage}
|selvedge.client.protocol.attach_stream.validator.next|selvedge.client.protocol.attach_stream.validator.next.{duplicate_accepted,ended,error_first,frame_first,item_after_end,transition_table}
|selvedge.client.protocol.client_id|selvedge.client.protocol.client_id.{payload_validation,validation}
|selvedge.client.protocol.client_id.payload_validation|selvedge.client.protocol.client_id.payload_validation.{empty}
|selvedge.client.protocol.command|selvedge.client.protocol.command.{outcome,reject_reason,request,response,validation}
|selvedge.client.protocol.command.request|selvedge.client.protocol.command.request.{client_id,command_id,name,payload}
|selvedge.client.protocol.command.response|selvedge.client.protocol.command.response.{command_id,outcome}
|selvedge.client.protocol.command.validation|selvedge.client.protocol.command.validation.{name}
|selvedge.client.protocol.command_id|selvedge.client.protocol.command_id.{payload_validation,validation}
|selvedge.client.protocol.command_id.payload_validation|selvedge.client.protocol.command_id.payload_validation.{empty}
|selvedge.client.protocol.delivery_seq|selvedge.client.protocol.delivery_seq.{validation}
|selvedge.client.protocol.delivery_seq.validation|selvedge.client.protocol.delivery_seq.validation.{zero}
|selvedge.client.protocol.event|selvedge.client.protocol.event.{debug_notice,history_appended,model_call_status,task_changed,tool_status,validation}
|selvedge.client.protocol.event.debug_notice|selvedge.client.protocol.event.debug_notice.{message,task_id}
|selvedge.client.protocol.event.history_appended|selvedge.client.protocol.event.history_appended.{nodes,task_id,version}
|selvedge.client.protocol.event.model_call_status|selvedge.client.protocol.event.model_call_status.{model_call_id,phase,task_id}
|selvedge.client.protocol.event.task_changed|selvedge.client.protocol.event.task_changed.{task}
|selvedge.client.protocol.event.tool_status|selvedge.client.protocol.event.tool_status.{node_id,phase,run_id,task_id,tool_name}
|selvedge.client.protocol.event.validation|selvedge.client.protocol.event.validation.{debug_text,tool_status_node}
|selvedge.client.protocol.frame|selvedge.client.protocol.frame.{event,notice,snapshot,validation}
|selvedge.client.protocol.frame.event|selvedge.client.protocol.frame.event.{delivery_seq,payload}
|selvedge.client.protocol.frame.notice|selvedge.client.protocol.frame.notice.{command_id,delivery_seq,payload}
|selvedge.client.protocol.frame.snapshot|selvedge.client.protocol.frame.snapshot.{command_id,delivery_seq,payload}
|selvedge.client.protocol.history_projection|selvedge.client.protocol.history_projection.{body,body_field,body_validation,created_at,node_id,parent_node_id,validation}
|selvedge.client.protocol.history_projection.body_validation|selvedge.client.protocol.history_projection.body_validation.{argument,function_output}
|selvedge.client.protocol.history_projection.validation|selvedge.client.protocol.history_projection.validation.{node,parent}
|selvedge.client.protocol.http_problem|selvedge.client.protocol.http_problem.{build,code,code_field,message}
|selvedge.client.protocol.notice|selvedge.client.protocol.notice.{kind,kind_field,level,level_field,message,validation}
|selvedge.client.protocol.notice.validation|selvedge.client.protocol.notice.validation.{command_name,empty,url,user_code}
|selvedge.client.protocol.ready|selvedge.client.protocol.ready.{request,response,state,validation}
|selvedge.client.protocol.ready.response|selvedge.client.protocol.ready.response.{state}
|selvedge.client.protocol.snapshot|selvedge.client.protocol.snapshot.{generated_at,history_nodes,parent_edges,task_versions,tasks,validation,version}
|selvedge.client.protocol.snapshot.validation|selvedge.client.protocol.snapshot.validation.{duplicate_version}
|selvedge.client.protocol.snapshot.version|selvedge.client.protocol.snapshot.version.{state_version,task_id}
|selvedge.client.protocol.subscription|selvedge.client.protocol.subscription.{detail,detail_field,include_debug_notices,include_model_call_status,include_tool_execution_status,snapshot_mode,snapshot_mode_field,task_scope,task_scope_field,validation}
|selvedge.client.protocol.subscription.validation|selvedge.client.protocol.subscription.validation.{duplicate_task,empty_task}
|selvedge.client.protocol.task_id|selvedge.client.protocol.task_id.{validation}
|selvedge.client.protocol.task_id.validation|selvedge.client.protocol.task_id.validation.{empty}
|selvedge.client.protocol.task_projection|selvedge.client.protocol.task_projection.{created_at,cursor,model_profile,parent,reasoning_effort,state_version,status,status_field,task_id,updated_at,validation}
|selvedge.client.protocol.task_projection.parent|selvedge.client.protocol.task_projection.parent.{child_task_id,parent_task_id}
|selvedge.client.protocol.task_projection.validation|selvedge.client.protocol.task_projection.validation.{cursor,model_profile}
|selvedge.client.protocol.tool_argument|selvedge.client.protocol.tool_argument.{name,value,value_field}
|selvedge.client.protocol.tool_name|selvedge.client.protocol.tool_name.{validation}
|selvedge.client.protocol.tool_name.validation|selvedge.client.protocol.tool_name.validation.{empty}
|selvedge.client.redaction|selvedge.client.redaction.{as_str,display,embedded,error_text,into_string,invalid,parts,sanitize_url}
|selvedge.client.redaction.embedded|selvedge.client.redaction.embedded.{delimiter}
|selvedge.client.redirect|selvedge.client.redirect.{cross_origin,headers,hop,limit,location,log,method,origin,preserve_request,statuses,target}
|selvedge.client.request|selvedge.client.request.{body,body_public,compression,compression_public,content_length,content_type,headers,method,prepare,prepared,prepared_body_len,prepared_method,prepared_url,public,timeout_public,url,url_public,user_agent}
|selvedge.client.request.body|selvedge.client.request.body.{encode,form,into_bytes,json,len}
|selvedge.client.request.compression|selvedge.client.request.compression.{apply,empty,encode,finish_error,header,integrity,output,start_error,zstd,zstd_conflicts}
|selvedge.client.request.compression.integrity|selvedge.client.request.compression.integrity.{names}
|selvedge.client.request.content_length|selvedge.client.request.content_length.{final}
|selvedge.client.request.headers|selvedge.client.request.headers.{defaults}
|selvedge.client.request.url|selvedge.client.request.url.{absolute,parse,scheme}
|selvedge.client.response|selvedge.client.response.{body,body_public,headers,public,status,status_body,timeout,transport_error,wait_budget}
|selvedge.client.snapshot|selvedge.client.snapshot.{generated_at,history_nodes,parent_edges,task_versions,tasks,version}
|selvedge.client.snapshot.version|selvedge.client.snapshot.version.{state_version,task_id}
|selvedge.client.status|selvedge.client.status.{body,code,display,headers,public,timeout,truncated,url,wait_budget}
|selvedge.client.status.timeout|selvedge.client.status.timeout.{log}
|selvedge.client.status.truncated|selvedge.client.status.truncated.{log}
|selvedge.client.stream|selvedge.client.stream.{body,body_public,bytes,debug,finish_log,headers,idle,inner,inter_poll,log,public,status,status_error,transport_error,wait_budget,wait_timeout,wait_timeout_item}
|selvedge.client.stream.idle|selvedge.client.stream.idle.{charge,new,remaining,reset}
|selvedge.client.subscription|selvedge.client.subscription.{detail,detail_field,include_debug_notices,include_model_call_status,include_tool_execution_status,snapshot_mode,snapshot_mode_field,task_scope,task_scope_field}
|selvedge.client.sync|selvedge.client.sync.{begin_failure,build_future,build_request,builder,builder_result,builder_task,cancel,capacity,current_result,delivery,delivery_failure,duplicate,error,event_send,exit,handle,ingress,ingress_closed,replace,result,sender,shutdown,snapshot,snapshot_error,spawn,spawn_error,start,start_args}
|selvedge.client.sync.build_future|selvedge.client.sync.build_future.{result}
|selvedge.client.sync.build_request|selvedge.client.sync.build_request.{client_id,command_id,subscription}
|selvedge.client.sync.builder|selvedge.client.sync.builder.{build,contract}
|selvedge.client.sync.builder_task|selvedge.client.sync.builder_task.{spawn,start}
|selvedge.client.sync.cancel|selvedge.client.sync.cancel.{client_id,command_id,match}
|selvedge.client.sync.delivery|selvedge.client.sync.delivery.{result}
|selvedge.client.sync.event_send|selvedge.client.sync.event_send.{call,failure}
|selvedge.client.sync.handle|selvedge.client.sync.handle.{ingress,join}
|selvedge.client.sync.result|selvedge.client.sync.result.{delivery,identity}
|selvedge.client.sync.sender|selvedge.client.sync.sender.{control}
|selvedge.client.sync.snapshot|selvedge.client.sync.snapshot.{failure}
|selvedge.client.sync.snapshot_error|selvedge.client.sync.snapshot_error.{detach_failure,notice_failure}
|selvedge.client.sync.spawn|selvedge.client.sync.spawn.{runtime,task}
|selvedge.client.sync.start_args|selvedge.client.sync.start_args.{builder,capacity,config,events}
|selvedge.client.task_projection|selvedge.client.task_projection.{created_at,cursor,model_profile,parent,reasoning_effort,state_version,status,status_field,task_id,updated_at}
|selvedge.client.task_projection.parent|selvedge.client.task_projection.parent.{child_task_id,parent_task_id}
|selvedge.client.timeout|selvedge.client.timeout.{charge,new,ready,remaining,wait,wait_budget,wait_new}
|selvedge.client.timeout.wait|selvedge.client.timeout.wait.{tie}
|selvedge.client.tls|selvedge.client.tls.{ca_bundle}
|selvedge.client.tls.ca_bundle|selvedge.client.tls.ca_bundle.{der_error,http_skip,nonempty,parse_error,pem_error,read,read_error}
|selvedge.client.transport|selvedge.client.transport.{build_error,config,error,error_chain,failure,send,single_hop,timeout}
|selvedge.client.tui|selvedge.client.tui.{r2,run}
|selvedge.client.tui.r2|selvedge.client.tui.r2.{attach_client_failure,attach_rejected,command_mapper,connect_failure,connect_unavailable,exit_status,initial_command_failure,input_action,invalid_attach_command_id,invalid_client_id,map_input,ready_failure,run_entry,runtime_state,snapshot_stream,snapshot_stream_failure,snapshot_timeout,snapshot_wait,start_args}
|selvedge.client.tui.r2.command_mapper|selvedge.client.tui.r2.command_mapper.{intent}
|selvedge.client.tui.r2.exit_status|selvedge.client.tui.r2.exit_status.{attach_rejected,command_rejected,invalid_args,local_client_failed,terminal_failed}
|selvedge.client.tui.r2.input_action|selvedge.client.tui.r2.input_action.{submit_command}
|selvedge.client.tui.r2.snapshot_stream|selvedge.client.tui.r2.snapshot_stream.{disconnected}
|selvedge.client.tui.r2.start_args|selvedge.client.tui.r2.start_args.{attach_command_id,client_config,client_id,initial_command,subscription}
|selvedge.client.web|selvedge.client.web.{r2,spawn}
|selvedge.client.web.r2|selvedge.client.web.r2.{accept_failure,attach_future,attach_result,bind_localhost,bind_reservation,bridge,bridge_attach,bridge_error,bridge_future,bridge_ready,bridge_submit_command,control,control_inner,exit_status,fail_surface,frame_stream,frame_stream_type,handle,http,localhost_bind,localhost_host,next_frame,parse_json,read_request,read_request_inner,read_request_inner_result,read_request_timeout,rejected_command_response,request_timeout,reserve_bind,reserved_start_args,runtime_state,spawn_entry,spawn_reserved,start_args,start_error,stop_status,write_attach_stream_item,write_json_parse_error,write_json_response,write_problem_response,write_raw_response,write_stream_headers}
|selvedge.client.web.r2.attach_future|selvedge.client.web.r2.attach_future.{intent}
|selvedge.client.web.r2.attach_result|selvedge.client.web.r2.attach_result.{bridge_error,rejected}
|selvedge.client.web.r2.bind_localhost|selvedge.client.web.r2.bind_localhost.{bind_failed,nonblocking_failed}
|selvedge.client.web.r2.bridge|selvedge.client.web.r2.bridge.{intent}
|selvedge.client.web.r2.bridge_error|selvedge.client.web.r2.bridge_error.{attach_rejected,command_rejected,internal_failure}
|selvedge.client.web.r2.control|selvedge.client.web.r2.control.{attach,closed_operation,ready,state,stop,submit_command}
|selvedge.client.web.r2.control.attach|selvedge.client.web.r2.control.attach.{bridge_error,closing,invalid_request,request,server_not_ready,server_not_ready_response,validation_failed,validation_failed_response}
|selvedge.client.web.r2.control.ready|selvedge.client.web.r2.control.ready.{bridge_error,not_ready}
|selvedge.client.web.r2.control.stop|selvedge.client.web.r2.control.stop.{signal}
|selvedge.client.web.r2.control.submit_command|selvedge.client.web.r2.control.submit_command.{bridge_error,server_not_ready,validation_failed}
|selvedge.client.web.r2.exit_status|selvedge.client.web.r2.exit_status.{fatal}
|selvedge.client.web.r2.frame_stream|selvedge.client.web.r2.frame_stream.{close_after_error,error}
|selvedge.client.web.r2.handle|selvedge.client.web.r2.handle.{control,join}
|selvedge.client.web.r2.http|selvedge.client.web.r2.http.{attach_route,body_too_large,command_route,ready_route}
|selvedge.client.web.r2.http.attach_route|selvedge.client.web.r2.http.attach_route.{bridge_error,parse_error,rejected}
|selvedge.client.web.r2.http.command_route|selvedge.client.web.r2.http.command_route.{bridge_error,parse_error}
|selvedge.client.web.r2.http.ready_route|selvedge.client.web.r2.http.ready_route.{bridge_error,parse_error}
|selvedge.client.web.r2.localhost_bind|selvedge.client.web.r2.localhost_bind.{host,port}
|selvedge.client.web.r2.next_frame|selvedge.client.web.r2.next_frame.{stream_error}
|selvedge.client.web.r2.parse_json|selvedge.client.web.r2.parse_json.{malformed,unsupported_content_type}
|selvedge.client.web.r2.read_request_inner|selvedge.client.web.r2.read_request_inner.{body_limit,eof,header_limit,header_utf8}
|selvedge.client.web.r2.read_request_timeout|selvedge.client.web.r2.read_request_timeout.{elapsed}
|selvedge.client.web.r2.reserve_bind|selvedge.client.web.r2.reserve_bind.{zero_port}
|selvedge.client.web.r2.reserved_start_args|selvedge.client.web.r2.reserved_start_args.{bind,bridge}
|selvedge.client.web.r2.spawn_reserved|selvedge.client.web.r2.spawn_reserved.{listener,runtime,zero_port}
|selvedge.client.web.r2.start_args|selvedge.client.web.r2.start_args.{bind,bridge}
|selvedge.client.web.r2.start_error|selvedge.client.web.r2.start_error.{bind_failed}
|selvedge.client.web.r2.write_attach_stream_item|selvedge.client.web.r2.write_attach_stream_item.{serialize,write}
|selvedge.client.web.r2.write_json_response|selvedge.client.web.r2.write_json_response.{serialize}
|selvedge.client.web.r2.write_raw_response|selvedge.client.web.r2.write_raw_response.{body,headers}
|selvedge.config|selvedge.config.{cli,current,env,error,file,home,init,merge,model,model_error,override,read,serialize,service,test_reset,update,update_persist,update_runtime,value}
|selvedge.config.cli|selvedge.config.cli.{entries}
|selvedge.config.env|selvedge.config.env.{entries}
|selvedge.config.env.entries|selvedge.config.env.entries.{nonempty_suffix,parse_error,prefix,utf8}
|selvedge.config.file|selvedge.config.file.{load,optional,parent,path,write}
|selvedge.config.file.write|selvedge.config.file.write.{bytes,parent,persist,sync}
|selvedge.config.home|selvedge.config.home.{call,candidates,create,default_candidates,default_create,default_select,env,error,explicit,search,valid}
|selvedge.config.home.create|selvedge.config.home.create.{canonicalize,file}
|selvedge.config.home.default_create|selvedge.config.home.default_create.{exhausted,failure}
|selvedge.config.home.search|selvedge.config.home.search.{skip_absent}
|selvedge.config.init|selvedge.config.init.{call,cli,home,once}
|selvedge.config.init.cli|selvedge.config.init.cli.{call,default_home,home_source,lock,validation}
|selvedge.config.init.home|selvedge.config.init.home.{call}
|selvedge.config.model|selvedge.config.model.{app,error,feature,input,llm,logging,materialize,network,server,url,validate,validation_error}
|selvedge.config.model.app|selvedge.config.model.app.{feature,llm,logging,network,server}
|selvedge.config.model.feature|selvedge.config.model.feature.{defaults,enabled,input,rollout,valid}
|selvedge.config.model.feature.valid|selvedge.config.model.feature.valid.{enabled_rollout,range}
|selvedge.config.model.input|selvedge.config.model.input.{materialize}
|selvedge.config.model.llm|selvedge.config.model.llm.{defaults,input,provider,provider_id,providers_field,valid}
|selvedge.config.model.llm.provider|selvedge.config.model.llm.provider.{base_url,defaults,input,models,settings,timeout,valid,valid_for_provider}
|selvedge.config.model.llm.provider.base_url|selvedge.config.model.llm.provider.base_url.{base_shape,valid}
|selvedge.config.model.llm.provider.models|selvedge.config.model.llm.provider.models.{nonblank,unique}
|selvedge.config.model.llm.provider.settings|selvedge.config.model.llm.provider.settings.{key,valid,value}
|selvedge.config.model.llm.provider.timeout|selvedge.config.model.llm.provider.timeout.{nonzero}
|selvedge.config.model.llm.provider_id|selvedge.config.model.llm.provider_id.{nonblank,path_safe}
|selvedge.config.model.logging|selvedge.config.model.logging.{defaults,filter,input,level,module_levels,valid}
|selvedge.config.model.logging.filter|selvedge.config.model.logging.filter.{display}
|selvedge.config.model.logging.filter.display|selvedge.config.model.logging.filter.display.{write}
|selvedge.config.model.network|selvedge.config.model.network.{ca_bundle,connect_timeout,defaults,input,request_timeout,stream_idle_timeout,user_agent,valid}
|selvedge.config.model.network.valid|selvedge.config.model.network.valid.{connect_timeout,request_timeout,stream_idle_timeout,user_agent}
|selvedge.config.model.server|selvedge.config.model.server.{defaults,host,input,port,timeout,valid}
|selvedge.config.model.server.valid|selvedge.config.model.server.valid.{port,timeout}
|selvedge.config.model.url|selvedge.config.model.url.{authority,loopback,scheme}
|selvedge.config.model.url.authority|selvedge.config.model.url.authority.{host,scheme,separator}
|selvedge.config.model.url.loopback|selvedge.config.model.url.loopback.{host,result}
|selvedge.config.model.url.scheme|selvedge.config.model.url.scheme.{allowed,https,userinfo}
|selvedge.config.override|selvedge.config.override.{path,replace_table}
|selvedge.config.read|selvedge.config.read.{call}
|selvedge.config.serialize|selvedge.config.serialize.{table}
|selvedge.config.service|selvedge.config.service.{candidate,global,materialize,new,persist,read_base,read_home,state,update}
|selvedge.config.service.new|selvedge.config.service.new.{base,home}
|selvedge.config.service.update|selvedge.config.service.update.{lock_error,persist_flag}
|selvedge.config.update|selvedge.config.update.{atomic,lock_error,persisted,value_error}
|selvedge.config.update_runtime|selvedge.config.update_runtime.{call}
|selvedge.config.value|selvedge.config.value.{parse}
|selvedge.core|selvedge.core.{archive,command,config,conversation,cursor_tail,db_error,exit,freeze,mailbox_capacity,model_failure,model_profile,model_reply,model_request,open_tool_order,queue,ready,resume_open_tools,router_closed,router_output,spawn,spawn_args,spawn_deps,spawn_error,spawned,spawner,start,stop,tool_args,tool_calls,tool_dispatch,tool_result,user_input,wait_state}
|selvedge.core.config|selvedge.core.config.{mailbox_capacity,model_profiles}
|selvedge.core.conversation|selvedge.core.conversation.{duplicate_call,mismatched_tool,missing_call,open_call,path,tool_pair_validation,tool_pairs}
|selvedge.core.model_failure|selvedge.core.model_failure.{db_error}
|selvedge.core.model_reply|selvedge.core.model_reply.{db_error,expected,failure_stale,idle,persist,queued,stale,terminal,tool_calls,tool_validation}
|selvedge.core.open_tool_order|selvedge.core.open_tool_order.{queue}
|selvedge.core.queue|selvedge.core.queue.{promote}
|selvedge.core.spawn_args|selvedge.core.spawn_args.{config,db,router,task}
|selvedge.core.spawn_deps|selvedge.core.spawn_deps.{config,default_spawner,injected_spawner,overview,spawner}
|selvedge.core.spawned|selvedge.core.spawned.{control,sender,task}
|selvedge.core.spawner|selvedge.core.spawner.{contract,default,default_struct,spawn}
|selvedge.core.start|selvedge.core.start.{once}
|selvedge.core.tool_args|selvedge.core.tool_args.{declared,enabled,object,required,type,value}
|selvedge.core.tool_calls|selvedge.core.tool_calls.{persist,persist_batch,unique,validate}
|selvedge.core.tool_dispatch|selvedge.core.tool_dispatch.{request}
|selvedge.core.tool_result|selvedge.core.tool_result.{db_error,expected,next,next_choice,persist,stale,success}
|selvedge.core.user_input|selvedge.core.user_input.{busy,db_error,nonempty,persisted,ready}
|selvedge.login|selvedge.login.{auth_file,authorization,challenge,complete,config,errors,id_token,poll,poll_outcome,progress,provider_body,result,run,start,tests,token_exchange}
|selvedge.login.auth_file|selvedge.login.auth_file.{atomic,directory,encode,lock,lock_directory,lock_exclusive,lock_open,lock_parent,lock_path,parent,path,persist,persist_join,replace,result,temp,write}
|selvedge.login.authorization|selvedge.login.authorization.{code,verifier}
|selvedge.login.challenge|selvedge.login.challenge.{device_auth_id,expires_at,issued_at,poll_interval,user_code,verification_url}
|selvedge.login.complete|selvedge.login.complete.{expired,workspace_mismatch}
|selvedge.login.config|selvedge.login.config.{client_id,error,expected_workspace,home,issuer,read,valid}
|selvedge.login.config.valid|selvedge.login.config.valid.{base,client_id,http,issuer,read,settings_type,userinfo,workspace}
|selvedge.login.config.valid.settings_type|selvedge.login.config.valid.settings_type.{read}
|selvedge.login.id_token|selvedge.login.id_token.{account_id,claim_adapter,claims,email,extra_segments,json,object,parse,plan_type,segments,user_id}
|selvedge.login.poll|selvedge.login.poll.{authorized,pending,rejected,request,required_fields,response,transport}
|selvedge.login.progress|selvedge.login.progress.{error,future,sink}
|selvedge.login.progress.future|selvedge.login.progress.future.{abstraction}
|selvedge.login.progress.sink|selvedge.login.progress.sink.{abstraction,emit,noop}
|selvedge.login.result|selvedge.login.result.{account_id,auth_file_path,email,plan_type,user_id}
|selvedge.login.run|selvedge.login.run.{authorized,cancelled,expired,initial_interval,provider_expired}
|selvedge.login.start|selvedge.login.start.{error_status,interval,interval_positive,interval_string,interval_value,request,required_fields,response,transport,user_code}
|selvedge.login.tests|selvedge.login.tests.{jwt,jwt_header}
|selvedge.login.token_exchange|selvedge.login.token_exchange.{access_token,error_status,id_token,refresh_token,request,required_tokens,response,tokens,transport}
|selvedge.model|selvedge.model.{chatgpt,config,credentials,dispatch,domain,failure,limit,providers,router,terminal}
|selvedge.model.chatgpt|selvedge.model.chatgpt.{aggregate,api,argument_json,build,content,content_item,content_text,error,event,fallback,fallback_text,finish,history,item,json_convert,json_value,message,number,payload_field,payload_json,preference,reply,request,request_build,stream,stream_bytes,stream_count,tool_args,tool_call,tool_call_map,tool_history,tool_history_item,tool_schema,tools,tools_map}
|selvedge.model.chatgpt.api|selvedge.model.chatgpt.api.{capabilities,config,content,context,decode,drive,error,event,http_request,item,json_object,open,raw_event,reasoning,request,response_stream,retry,send_item,service_tier,snapshot,sse,stream,text,tool_descriptor,tool_output,turn_state,usage}
|selvedge.model.chatgpt.api.capabilities|selvedge.model.chatgpt.api.capabilities.{default_reasoning_effort,reasoning_summaries,text_verbosity}
|selvedge.model.chatgpt.api.config|selvedge.model.chatgpt.api.config.{base_url,resolve,stream_timeout}
|selvedge.model.chatgpt.api.config.base_url|selvedge.model.chatgpt.api.config.base_url.{responses_suffix}
|selvedge.model.chatgpt.api.content|selvedge.model.chatgpt.api.content.{object}
|selvedge.model.chatgpt.api.context|selvedge.model.chatgpt.api.context.{beta_features,conversation_id,installation_id,parent_thread_id,subagent,turn_metadata,turn_state,window_generation}
|selvedge.model.chatgpt.api.decode|selvedge.model.chatgpt.api.decode.{nested_u64_parent,optional_string,optional_u64_numeric,optional_u64_type,required_array,required_array_type,required_string,required_u64}
|selvedge.model.chatgpt.api.drive|selvedge.model.chatgpt.api.drive.{body_error,chunk_timeout,completion_timeout,empty_close,endpoint_event,final_endpoint_error,final_error,final_map_error,final_noncompletion,frame_error,map_error,next_chunk,trailing_frame,utf8}
|selvedge.model.chatgpt.api.error|selvedge.model.chatgpt.api.error.{endpoint,failed,failed_kind,incomplete,lower,other}
|selvedge.model.chatgpt.api.error.failed|selvedge.model.chatgpt.api.error.failed.{code,kind,message,raw,response_id}
|selvedge.model.chatgpt.api.error.incomplete|selvedge.model.chatgpt.api.error.incomplete.{raw,reason,response_id}
|selvedge.model.chatgpt.api.error.other|selvedge.model.chatgpt.api.error.other.{code,event_type,message,raw,retry_after}
|selvedge.model.chatgpt.api.event|selvedge.model.chatgpt.api.event.{map,object,type}
|selvedge.model.chatgpt.api.http_request|selvedge.model.chatgpt.api.http_request.{header,header_error}
|selvedge.model.chatgpt.api.item|selvedge.model.chatgpt.api.item.{custom_tool_call_output,decode_field,field_object,function_call,function_call_output,message,opaque,reasoning}
|selvedge.model.chatgpt.api.item.custom_tool_call_output|selvedge.model.chatgpt.api.item.custom_tool_call_output.{call_id,id,output,required,status}
|selvedge.model.chatgpt.api.item.function_call|selvedge.model.chatgpt.api.item.function_call.{arguments,call_id,id,name,namespace,status}
|selvedge.model.chatgpt.api.item.function_call_output|selvedge.model.chatgpt.api.item.function_call_output.{call_id,id,output,required,status}
|selvedge.model.chatgpt.api.item.message|selvedge.model.chatgpt.api.item.message.{content,id,role,status}
|selvedge.model.chatgpt.api.item.opaque|selvedge.model.chatgpt.api.item.opaque.{raw}
|selvedge.model.chatgpt.api.item.reasoning|selvedge.model.chatgpt.api.item.reasoning.{content,content_array,encrypted_content,id,status,summary,summary_required}
|selvedge.model.chatgpt.api.open|selvedge.model.chatgpt.api.open.{auth,client_error,content_type,reauth_error,request_error,retry,unauthorized}
|selvedge.model.chatgpt.api.raw_event|selvedge.model.chatgpt.api.raw_event.{event_type,payload}
|selvedge.model.chatgpt.api.reasoning|selvedge.model.chatgpt.api.reasoning.{effort,summary}
|selvedge.model.chatgpt.api.request|selvedge.model.chatgpt.api.request.{beta_features,capabilities,context,conversation_id,header_value,input,instructions,model,nonblank,parallel_tool_calls,reasoning,reasoning_support,service_tier,text,tool_json,tool_json_error,tools,validation,validation_error,verbosity_support}
|selvedge.model.chatgpt.api.request.validation_error|selvedge.model.chatgpt.api.request.validation_error.{field,reason}
|selvedge.model.chatgpt.api.response_stream|selvedge.model.chatgpt.api.response_stream.{construct,drop,poll,turn_state}
|selvedge.model.chatgpt.api.retry|selvedge.model.chatgpt.api.retry.{classification,delay}
|selvedge.model.chatgpt.api.send_item|selvedge.model.chatgpt.api.send_item.{backpressure_timeout,receiver_closed,timeout}
|selvedge.model.chatgpt.api.snapshot|selvedge.model.chatgpt.api.snapshot.{decode,id,model,raw,response_object,service_tier,usage}
|selvedge.model.chatgpt.api.sse|selvedge.model.chatgpt.api.sse.{final_frame}
|selvedge.model.chatgpt.api.stream|selvedge.model.chatgpt.api.stream.{config,invalid_request}
|selvedge.model.chatgpt.api.text|selvedge.model.chatgpt.api.text.{json_schema,verbosity,verbosity_values}
|selvedge.model.chatgpt.api.tool_output|selvedge.model.chatgpt.api.tool_output.{shape}
|selvedge.model.chatgpt.api.usage|selvedge.model.chatgpt.api.usage.{cached_input,input,nested_fallback,object,output,reasoning_output,total}
|selvedge.model.chatgpt.event|selvedge.model.chatgpt.event.{verify_surface}
|selvedge.model.chatgpt.tool_args|selvedge.model.chatgpt.tool_args.{encode,item,name}
|selvedge.model.config|selvedge.model.config.{bytes,timeout}
|selvedge.model.credentials|selvedge.model.credentials.{decode,directory,error,exists,kind,list,lock,path,persist,provider_id,read,record,write}
|selvedge.model.credentials.list|selvedge.model.credentials.list.{from_home}
|selvedge.model.credentials.list.from_home|selvedge.model.credentials.list.from_home.{absent,entry_error,read_dir_error,skip_extension,skip_stem}
|selvedge.model.credentials.lock|selvedge.model.credentials.lock.{file,guard,path,release,table}
|selvedge.model.credentials.lock.file|selvedge.model.credentials.lock.file.{directory,exclusive,open,parent_error}
|selvedge.model.credentials.lock.guard|selvedge.model.credentials.lock.guard.{file,process}
|selvedge.model.credentials.persist|selvedge.model.credentials.persist.{directory,parent_error,replace,temp,write}
|selvedge.model.credentials.provider_id|selvedge.model.credentials.provider_id.{nonblank,path_safe}
|selvedge.model.credentials.read|selvedge.model.credentials.read.{from_home}
|selvedge.model.credentials.read.from_home|selvedge.model.credentials.read.from_home.{absent,provider_match,read_error}
|selvedge.model.credentials.record|selvedge.model.credentials.record.{kind,payload,provider,schema_version,valid}
|selvedge.model.credentials.record.valid|selvedge.model.credentials.record.valid.{api_key,login,payload_object,schema}
|selvedge.model.credentials.write|selvedge.model.credentials.write.{from_home}
|selvedge.model.dispatch|selvedge.model.dispatch.{bytes,input,outcome,provider,provider_config,reply,run,spawn,success,timeout,unknown_provider}
|selvedge.model.dispatch.provider_config|selvedge.model.dispatch.provider_config.{config_error,home_error}
|selvedge.model.domain|selvedge.model.domain.{conversation,conversation_item,conversation_items,conversation_message,conversation_message_content,conversation_message_role,conversation_message_source,conversation_path,conversation_path_messages,finish_reason,function_call_id_type,history_node_id_type,ids,message_content,message_role,model_profile_key_type,model_reply,model_reply_content,model_reply_finish_reason,model_reply_tool_calls,model_reply_usage,provider_profile,provider_profile_max_output_tokens,provider_profile_model_name,provider_profile_provider_name,provider_profile_temperature,reasoning_effort,response_preference,structured_payload,task_id_type,token_usage,token_usage_input,token_usage_output,tool_argument_value,tool_call_argument,tool_call_argument_name,tool_call_argument_value,tool_call_proposal,tool_call_proposal_arguments,tool_call_proposal_call_id,tool_call_proposal_tool_name,tool_manifest,tool_manifest_tools,tool_name_type,tool_parameter,tool_parameter_description,tool_parameter_name_field,tool_parameter_name_type,tool_parameter_required,tool_parameter_type,tool_parameter_type_field,tool_spec,tool_spec_description,tool_spec_name,tool_spec_parameters,unix_ts_type,validation,validation_error}
|selvedge.model.domain.validation|selvedge.model.domain.validation.{conversation,provider,reply,tools}
|selvedge.model.domain.validation.reply|selvedge.model.domain.validation.reply.{empty,empty_tool_call_id,empty_tool_call_name}
|selvedge.model.domain.validation.tools|selvedge.model.domain.validation.tools.{duplicate_parameter_name,duplicate_tool_name,empty_parameter_name,empty_tool_name}
|selvedge.model.limit|selvedge.model.limit.{counter,encode,encoded,reply,write}
|selvedge.model.providers|selvedge.model.providers.{credential_error,default_registry,descriptor,dispatch_model,error,list,listing,model_source,provider_config,provider_id,registry}
|selvedge.model.providers.descriptor|selvedge.model.providers.descriptor.{credential_kind,model_source,provider_id}
|selvedge.model.providers.dispatch_model|selvedge.model.providers.dispatch_model.{built_in,configured,credential_error,discoverable,kind_mismatch,missing_credential,nonblank,unknown}
|selvedge.model.providers.dispatch_model.built_in|selvedge.model.providers.dispatch_model.built_in.{invalid_model}
|selvedge.model.providers.dispatch_model.configured|selvedge.model.providers.dispatch_model.configured.{invalid_model,missing_config}
|selvedge.model.providers.dispatch_model.discoverable|selvedge.model.providers.dispatch_model.discoverable.{accept}
|selvedge.model.providers.list|selvedge.model.providers.list.{built_in,configured,credential_error,discoverable,kind_mismatch,missing_credential}
|selvedge.model.providers.list.built_in|selvedge.model.providers.list.built_in.{models}
|selvedge.model.providers.list.configured|selvedge.model.providers.list.configured.{empty_models,missing_config,models}
|selvedge.model.providers.list.discoverable|selvedge.model.providers.list.discoverable.{diagnostic}
|selvedge.model.providers.listing|selvedge.model.providers.listing.{diagnostics,models,provider_id}
|selvedge.model.providers.model_source|selvedge.model.providers.model_source.{valid}
|selvedge.model.providers.model_source.valid|selvedge.model.providers.model_source.valid.{built_in}
|selvedge.model.providers.provider_id|selvedge.model.providers.provider_id.{nonblank,path_safe}
|selvedge.model.providers.registry|selvedge.model.providers.registry.{default,descriptor,descriptors,new}
|selvedge.model.providers.registry.new|selvedge.model.providers.registry.new.{provider_id,unique}
|selvedge.model.router|selvedge.model.router.{output,r2,send,spawn}
|selvedge.model.router.r2|selvedge.model.router.r2.{actor_effects,api_output,attach,command,events,exit_status,factory,handle,run,runtime,runtime_exit,spawn_error,spawn_router,spawn_tool_execution,start_args,task_command,tool_execution,tool_execution_spawner,tool_output,tool_spawn_error}
|selvedge.model.router.r2.attach|selvedge.model.router.r2.attach.{abandoned_reserved_client,admission,events_closed_exit,events_closed_response,reserve_event,result_channel_closed}
|selvedge.model.router.r2.command|selvedge.model.router.r2.command.{validation}
|selvedge.model.router.r2.events|selvedge.model.router.r2.events.{debug,domain,send,send_closed}
|selvedge.model.router.r2.exit_status|selvedge.model.router.r2.exit_status.{fatal_error}
|selvedge.model.router.r2.factory|selvedge.model.router.r2.factory.{create_child,ensure_task,output,run,task_failure}
|selvedge.model.router.r2.handle|selvedge.model.router.r2.handle.{ingress_tx,join_handle}
|selvedge.model.router.r2.run|selvedge.model.router.r2.run.{error_exit}
|selvedge.model.router.r2.runtime|selvedge.model.router.r2.runtime.{register}
|selvedge.model.router.r2.runtime.register|selvedge.model.router.r2.runtime.register.{archive,deferred,start}
|selvedge.model.router.r2.start_args|selvedge.model.router.r2.start_args.{api_config,core_spawn_deps,db,events_tx,tool_executor}
|selvedge.model.router.r2.task_command|selvedge.model.router.r2.task_command.{delivery,send}
|selvedge.model.router.r2.tool_execution|selvedge.model.router.r2.tool_execution.{spawn_failure}
|selvedge.model.router.r2.tool_execution_spawner|selvedge.model.router.r2.tool_execution_spawner.{extension}
|selvedge.operations|selvedge.operations.{logging,systemd}
|selvedge.operations.logging|selvedge.operations.logging.{emit,runtime,tests}
|selvedge.operations.logging.emit|selvedge.operations.logging.emit.{fields_factory,lazy,message_factory,reserved_field_error,result,sink_write}
|selvedge.operations.logging.runtime|selvedge.operations.logging.runtime.{config_ready,current_sink,emit_error,filter,init,init_error,installed_sink,level,sink_trait,stderr_write}
|selvedge.operations.logging.runtime.config_ready|selvedge.operations.logging.runtime.config_ready.{error}
|selvedge.operations.logging.runtime.current_sink|selvedge.operations.logging.runtime.current_sink.{lock_error,missing}
|selvedge.operations.logging.runtime.emit_error|selvedge.operations.logging.runtime.emit_error.{not_initialized_message,output_lock_message,read_config,reserved_field,runtime_lock_message,write}
|selvedge.operations.logging.runtime.filter|selvedge.operations.logging.runtime.filter.{config_error}
|selvedge.operations.logging.runtime.init|selvedge.operations.logging.runtime.init.{already_initialized,lock,lock_poisoned}
|selvedge.operations.logging.runtime.init_error|selvedge.operations.logging.runtime.init_error.{already_initialized_message,read_config,runtime_lock_message}
|selvedge.operations.logging.runtime.stderr_write|selvedge.operations.logging.runtime.stderr_write.{output_lock,write_error}
|selvedge.operations.logging.tests|selvedge.operations.logging.tests.{install_runtime_error,install_runtime_lock,recorder_clear,recorder_take,recorder_write}
|selvedge.operations.systemd|selvedge.operations.systemd.{backend,backend_query,backend_start,client,config,error,parse_show,process_run,process_runner,query_status,run_boxed,runner,scope,start_outcome,start_unit,status,std_run,systemctl,systemctl_backend,systemctl_runner_field,validate}
|selvedge.operations.systemd.backend|selvedge.operations.systemd.backend.{abstraction}
|selvedge.operations.systemd.backend_start|selvedge.operations.systemd.backend_start.{rejected}
|selvedge.operations.systemd.client|selvedge.operations.systemd.client.{backend,config,new,query,start,wait}
|selvedge.operations.systemd.client.start|selvedge.operations.systemd.client.start.{not_installed}
|selvedge.operations.systemd.client.wait|selvedge.operations.systemd.client.wait.{after_query_timeout,deadline,not_installed,query,query_timeout,zero_sleep}
|selvedge.operations.systemd.config|selvedge.operations.systemd.config.{operation_timeout,poll_interval,unit_name}
|selvedge.operations.systemd.error|selvedge.operations.systemd.error.{backend_failure,start_rejected,unavailable}
|selvedge.operations.systemd.parse_show|selvedge.operations.systemd.parse_show.{exit_status,utf8}
|selvedge.operations.systemd.process_runner|selvedge.operations.systemd.process_runner.{abstraction}
|selvedge.operations.systemd.runner|selvedge.operations.systemd.runner.{erased}
|selvedge.operations.systemd.std_run|selvedge.operations.systemd.std_run.{pipe_read,spawn_error,stderr_join,stdout_join,timeout,timeout_kill,wait,wait_error}
|selvedge.operations.systemd.systemctl|selvedge.operations.systemd.systemctl.{backend,config,new,new_with_runner,output}
|selvedge.operations.systemd.systemctl.config|selvedge.operations.systemd.systemctl.config.{path,path_empty,scope}
|selvedge.operations.systemd.systemctl.output|selvedge.operations.systemd.systemctl.output.{exit_code,stderr,stdout}
|selvedge.operations.systemd.validate|selvedge.operations.systemd.validate.{operation_timeout,poll_interval,unit_blank,unit_whitespace}
|selvedge.session|selvedge.session.{events_r2}
|selvedge.session.events_r2|selvedge.session.events_r2.{client_event_for_subscription,delivery_failure,handle,remove_hidden_reservation,reserve,spawn,spawn_error,start_args}
|selvedge.session.events_r2.handle|selvedge.session.events_r2.handle.{ingress_sender,join}
|selvedge.session.events_r2.reserve|selvedge.session.events_r2.reserve.{responder_closed,restore}
|selvedge.session.events_r2.spawn|selvedge.session.events_r2.spawn.{invalid_hydration_buffer,invalid_ingress,invalid_registry}
|selvedge.session.events_r2.start_args|selvedge.session.events_r2.start_args.{client_registry_capacity,hydration_buffer_capacity,ingress_capacity}
|selvedge.startup|selvedge.startup.{server}
|selvedge.startup.server|selvedge.startup.server.{client_sync,event_delivery,lifecycle,local_operation,local_protocol,lock,ready,shutdown,start_after_lock,startup,web}
|selvedge.startup.server.client_sync|selvedge.startup.server.client_sync.{cancel_hydration,start_hydration}
|selvedge.startup.server.client_sync.cancel_hydration|selvedge.startup.server.client_sync.cancel_hydration.{closed,full,retry}
|selvedge.startup.server.client_sync.start_hydration|selvedge.startup.server.client_sync.start_hydration.{closed,full}
|selvedge.startup.server.event_delivery|selvedge.startup.server.event_delivery.{detach,detach_await,detach_clear,detach_restore}
|selvedge.startup.server.event_delivery.detach|selvedge.startup.server.event_delivery.detach.{closed,full,retry}
|selvedge.startup.server.event_delivery.detach_await|selvedge.startup.server.event_delivery.detach_await.{send}
|selvedge.startup.server.event_delivery.detach_clear|selvedge.startup.server.event_delivery.detach_clear.{full,immediate,retry}
|selvedge.startup.server.event_delivery.detach_restore|selvedge.startup.server.event_delivery.detach_restore.{full,immediate,retry}
|selvedge.startup.server.lifecycle|selvedge.startup.server.lifecycle.{coordinator,inner_effects,state}
|selvedge.startup.server.lifecycle.state|selvedge.startup.server.lifecycle.state.{query}
|selvedge.startup.server.local_operation|selvedge.startup.server.local_operation.{cancellation_registry,command,dispatch,executor,executor_ref,executor_trait,failure,future,list,login,notice,progress,progress_sender,success,task}
|selvedge.startup.server.local_operation.executor|selvedge.startup.server.local_operation.executor.{execute}
|selvedge.startup.server.local_operation.failure|selvedge.startup.server.local_operation.failure.{message}
|selvedge.startup.server.local_operation.future|selvedge.startup.server.local_operation.future.{abstraction}
|selvedge.startup.server.local_operation.list|selvedge.startup.server.local_operation.list.{concurrent_login}
|selvedge.startup.server.local_operation.login|selvedge.startup.server.local_operation.login.{attach_lookup,attach_required,events_required,single_flight}
|selvedge.startup.server.local_operation.notice|selvedge.startup.server.local_operation.notice.{delivery,delivery_closed}
|selvedge.startup.server.local_operation.progress|selvedge.startup.server.local_operation.progress.{notice}
|selvedge.startup.server.local_operation.progress_sender|selvedge.startup.server.local_operation.progress_sender.{abstraction}
|selvedge.startup.server.local_operation.success|selvedge.startup.server.local_operation.success.{message}
|selvedge.startup.server.local_operation.task|selvedge.startup.server.local_operation.task.{abort,attach_closed,cancel_attach,cancel_clear,cancel_clear_lock,cancel_lock,cancel_track,delivery_closed,failure,run,terminal,track}
|selvedge.startup.server.local_operation.task.cancel_track|selvedge.startup.server.local_operation.task.cancel_track.{lock,replace}
|selvedge.startup.server.local_protocol|selvedge.startup.server.local_protocol.{attach,command,control,error,event}
|selvedge.startup.server.local_protocol.attach|selvedge.startup.server.local_protocol.attach.{active_reject,active_reservation,admission_closed,channel_factory,channel_failed,clear_active,duplicate,frame_stream,frame_stream_type,registry_full,registry_lock,reject,request,reservation_rollback,response,restore_active,router_command,stream_closed,subscription_mapping}
|selvedge.startup.server.local_protocol.attach.channel_factory|selvedge.startup.server.local_protocol.attach.channel_factory.{create}
|selvedge.startup.server.local_protocol.attach.clear_active|selvedge.startup.server.local_protocol.attach.clear_active.{lock}
|selvedge.startup.server.local_protocol.attach.restore_active|selvedge.startup.server.local_protocol.attach.restore_active.{lock}
|selvedge.startup.server.local_protocol.command|selvedge.startup.server.local_protocol.command.{internal,malformed,map,mapper,mapper_ref,mapper_trait,not_ready,pipeline,response,router_closed,router_send,unsupported,validation}
|selvedge.startup.server.local_protocol.control|selvedge.startup.server.local_protocol.control.{debug}
|selvedge.startup.server.local_protocol.error|selvedge.startup.server.local_protocol.error.{internal}
|selvedge.startup.server.local_protocol.event|selvedge.startup.server.local_protocol.event.{tool_phase_mapping}
|selvedge.startup.server.lock|selvedge.startup.server.lock.{cleanup,contention,error,file_open,home_directory,open_error,shutdown_cleanup}
|selvedge.startup.server.lock.contention|selvedge.startup.server.lock.contention.{error}
|selvedge.startup.server.ready|selvedge.startup.server.ready.{response}
|selvedge.startup.server.shutdown|selvedge.startup.server.shutdown.{client_sync_status,client_sync_stop,collect_exit,events_status,exit_status,final_state,join_task,router_status,router_stop,state_closing,stop,supervised,web_status,web_stop}
|selvedge.startup.server.shutdown.client_sync_status|selvedge.startup.server.shutdown.client_sync_status.{join_error}
|selvedge.startup.server.shutdown.events_status|selvedge.startup.server.shutdown.events_status.{join_error}
|selvedge.startup.server.shutdown.exit_status|selvedge.startup.server.shutdown.exit_status.{fatal,startup_failed}
|selvedge.startup.server.shutdown.router_status|selvedge.startup.server.shutdown.router_status.{join_error}
|selvedge.startup.server.shutdown.supervised|selvedge.startup.server.shutdown.supervised.{client_sync,router,state}
|selvedge.startup.server.shutdown.web_status|selvedge.startup.server.shutdown.web_status.{join_error}
|selvedge.startup.server.startup|selvedge.startup.server.startup.{args,bind_target,client_sync,config,db_open,error,events,failure_cleanup,handle,local_binding,logging,router,run,spawn}
|selvedge.startup.server.startup.args|selvedge.startup.server.startup.args.{api_config,command_mapper,core_spawn_deps,home,local_binding,local_operation_executor,snapshot_builder,tool_executor,web_binding}
|selvedge.startup.server.startup.client_sync|selvedge.startup.server.startup.client_sync.{failure}
|selvedge.startup.server.startup.config|selvedge.startup.server.startup.config.{already_initialized,home_mismatch,init_error,requested_home,requested_home_error,resolve_home,selected_home}
|selvedge.startup.server.startup.db_open|selvedge.startup.server.startup.db_open.{failure}
|selvedge.startup.server.startup.error|selvedge.startup.server.startup.error.{client_sync,config,db,events,localhost_bind,logging,router}
|selvedge.startup.server.startup.events|selvedge.startup.server.startup.events.{failure}
|selvedge.startup.server.startup.failure_cleanup|selvedge.startup.server.startup.failure_cleanup.{error}
|selvedge.startup.server.startup.handle|selvedge.startup.server.startup.handle.{control,join}
|selvedge.startup.server.startup.local_binding|selvedge.startup.server.startup.local_binding.{target}
|selvedge.startup.server.startup.logging|selvedge.startup.server.startup.logging.{already_initialized,failure,init_error}
|selvedge.startup.server.startup.router|selvedge.startup.server.startup.router.{failure}
|selvedge.startup.server.startup.run|selvedge.startup.server.startup.run.{spawn_error}
|selvedge.startup.server.web|selvedge.startup.server.web.{attach_forward,bind_target,binding,command_forward,control_store,frame_stream,reserve,start,start_result}
|selvedge.startup.server.web.attach_forward|selvedge.startup.server.web.attach_forward.{reject}
|selvedge.startup.server.web.bind_target|selvedge.startup.server.web.bind_target.{zero_port}
|selvedge.startup.server.web.binding|selvedge.startup.server.web.binding.{target}
|selvedge.startup.server.web.frame_stream|selvedge.startup.server.web.frame_stream.{error_mapping}
|selvedge.startup.server.web.reserve|selvedge.startup.server.web.reserve.{error,error_mapping,failure}
|selvedge.startup.server.web.start|selvedge.startup.server.web.start.{error,error_mapping,failure}
|selvedge.state|selvedge.state.{connection,conversation,domain_types,error,history,open,schema,task,tool,transaction}
|selvedge.state.connection|selvedge.state.connection.{handle}
|selvedge.state.conversation|selvedge.state.conversation.{read}
|selvedge.state.error|selvedge.state.error.{active_tx,append_all_queued_user_inputs_in_tx_delete_queued_user_inputs,append_all_queued_user_inputs_in_tx_read_queued_user_inputs,append_all_queued_user_inputs_in_tx_read_queued_user_inputs_step2,append_all_queued_user_inputs_in_tx_read_queued_user_inputs_step3,append_assistant_message_and_drain_queue_commit,append_cursor,append_function_output_and_drain_queue_commit,append_history,append_history_node_and_move_cursor_commit,append_history_node_and_move_cursor_transaction,append_history_node_and_move_cursor_update_tasks,append_history_node_and_move_cursor_update_tasks_step2,append_model_reply_with_tool_calls_and_move_cursor_commit,append_model_reply_with_tool_calls_and_move_cursor_transaction,append_next_queued_user_input_and_move_cursor_commit,append_next_queued_user_input_and_move_cursor_commit_step2,append_next_queued_user_input_and_move_cursor_read_queued_user_inputs,append_next_queued_user_input_and_move_cursor_read_tasks,append_next_queued_user_input_and_move_cursor_update_tasks,append_next_queued_user_input_and_move_cursor_update_tasks_step2,append_next_queued_user_input_and_move_cursor_update_tasks_step3,archive_task_commit,archive_task_update_tasks,archive_task_update_tasks_step2,argument_value_decode,call_argument_read,call_insert,call_read,connection_database_error,consume_next_queued_user_input_commit,consume_next_queued_user_input_delete_queued_user_inputs,consume_next_queued_user_input_read_queued_user_inputs,content_kind_from_db_invalid_value,create_child_task_commit,create_child_task_insert_task_tools,create_child_task_insert_task_tools_step2,create_child_task_insert_tasks,create_root_task_commit,create_root_task_insert_task_tools,create_root_task_insert_tasks,current_cursor,current_cursor_node_id_in_tx_read_tasks,database_is_empty_read_sqlite_master,drain_queued_user_inputs_and_move_cursor_commit,ensure_active_task_in_tx_read_tasks,ensure_active_task_in_tx_read_tasks_step2,ensure_active_task_in_tx_read_tasks_step3,ensure_active_task_read_tasks,ensure_active_task_read_tasks_step2,ensure_active_task_read_tasks_step3,ensure_current_path_contains_open_function_call_database_error,ensure_current_path_contains_open_function_call_database_error_step2,ensure_current_path_contains_open_function_call_database_error_step3,ensure_current_path_contains_open_function_call_invalid_value,ensure_current_path_contains_open_function_call_invalid_value_step2,history_base,history_concrete,history_insert,i64_to_u64_read_db,insert_function_call_node_database_error,insert_function_call_node_insert_history_function_call_nodes,insert_function_call_node_read_rows,insert_function_call_node_read_tool_parameters,insert_function_call_node_read_tool_parameters_step2,insert_function_call_node_read_tool_parameters_step3,insert_function_output_node_insert_history_function_output_nodes,insert_history_node_insert_history_nodes,insert_message_node_insert_history_message_nodes,insert_message_node_invalid_value,insert_reasoning_node_insert_history_reasoning_nodes,list_active_tasks_read_tasks,list_active_tasks_read_tasks_step2,list_active_tasks_read_tasks_step3,list_queued_inputs_read_queued_user_inputs,list_queued_inputs_read_queued_user_inputs_step2,list_queued_inputs_read_queued_user_inputs_step3,map_history_node_row_database_error,map_queued_user_input_row_database_error,map_task_row_database_error,map_task_row_database_error_step2,map_task_row_database_error_step3,message_insert,message_read,message_role_from_db_invalid_value,output_insert,output_read,queue_drain,queue_user_input_commit,queue_user_input_insert_queued_user_inputs,queue_user_input_read_queued_user_inputs,read_function_call_arguments_database_error,read_function_call_arguments_database_error_step2,read_function_call_arguments_read_history_function_call_arguments,read_function_call_arguments_read_rows,read_function_call_node_read_history_function_call_nodes,read_function_output_node_database_error,read_history_node_in_connection_read_history_nodes,read_message_node_read_history_message_nodes,read_message_node_read_history_message_nodes_step2,read_open_function_calls_for_task_invalid_value,read_reasoning_node_read_history_reasoning_nodes,read_task_in_tx_read_tasks,read_task_parent_edges_read_rows,read_task_parent_edges_read_task_parent_edges,read_task_read_tasks,read_tool_manifest_for_task_database_error,read_tool_manifest_for_task_read_rows,read_tool_manifest_for_task_read_rows_step2,read_tool_manifest_for_task_read_tool_parameters,read_tool_manifest_for_task_read_tool_parameters_step2,read_tool_manifest_for_task_read_tools,read_tool_manifest_for_task_read_tools_step2,reasoning_effort_from_db_invalid_value,reasoning_insert,reasoning_read,register_tool_commit,register_tool_insert_tool_parameters,task_status_from_db_read_db,tool_argument_value_from_db_invalid_value,tool_parameter_type_from_db_invalid_value,u64_to_i64_database_error,u64_to_i64_integer_conversion,update_task_cursor_in_tx_database_error,update_task_cursor_in_tx_update_task,update_task_cursor_in_tx_update_task_step2}
|selvedge.state.history|selvedge.state.history.{append_assistant,append_function_output,append_model_tool_calls,append_user,create,function_argument,function_call,function_output,kind,message,new_content,new_function_call,new_function_output,new_message,new_node,new_reasoning,node,open_call,reasoning,row}
|selvedge.state.history.function_argument|selvedge.state.history.function_argument.{fields}
|selvedge.state.history.function_argument.fields|selvedge.state.history.function_argument.fields.{name,node,tool,value}
|selvedge.state.history.function_call|selvedge.state.history.function_call.{fields}
|selvedge.state.history.function_call.fields|selvedge.state.history.function_call.fields.{call,node,tool}
|selvedge.state.history.function_output|selvedge.state.history.function_output.{fields}
|selvedge.state.history.function_output.fields|selvedge.state.history.function_output.fields.{call,call_node,error,node,text,tool}
|selvedge.state.history.message|selvedge.state.history.message.{fields}
|selvedge.state.history.message.fields|selvedge.state.history.message.fields.{node,role,text}
|selvedge.state.history.new_function_call|selvedge.state.history.new_function_call.{fields}
|selvedge.state.history.new_function_call.fields|selvedge.state.history.new_function_call.fields.{arguments,call,tool}
|selvedge.state.history.new_function_output|selvedge.state.history.new_function_output.{fields}
|selvedge.state.history.new_function_output.fields|selvedge.state.history.new_function_output.fields.{call,call_node,error,text,tool}
|selvedge.state.history.new_message|selvedge.state.history.new_message.{fields}
|selvedge.state.history.new_message.fields|selvedge.state.history.new_message.fields.{role,text}
|selvedge.state.history.new_node|selvedge.state.history.new_node.{fields}
|selvedge.state.history.new_node.fields|selvedge.state.history.new_node.fields.{content,created,parent}
|selvedge.state.history.new_reasoning|selvedge.state.history.new_reasoning.{fields}
|selvedge.state.history.new_reasoning.fields|selvedge.state.history.new_reasoning.fields.{text}
|selvedge.state.history.node|selvedge.state.history.node.{id}
|selvedge.state.history.open_call|selvedge.state.history.open_call.{fields,read}
|selvedge.state.history.open_call.fields|selvedge.state.history.open_call.fields.{arguments,call,node,tool}
|selvedge.state.history.reasoning|selvedge.state.history.reasoning.{fields}
|selvedge.state.history.reasoning.fields|selvedge.state.history.reasoning.fields.{node,text}
|selvedge.state.history.row|selvedge.state.history.row.{fields}
|selvedge.state.history.row.fields|selvedge.state.history.row.fields.{created,kind,node,parent}
|selvedge.state.open|selvedge.state.open.{call,path}
|selvedge.state.open.call|selvedge.state.open.call.{schema_error}
|selvedge.state.schema|selvedge.state.schema.{mismatch,read_error}
|selvedge.state.task|selvedge.state.task.{archive,create_child,create_root,list_active,load_active,loaded,parent,queue,row,status,tool}
|selvedge.state.task.create_child|selvedge.state.task.create_child.{call,fields}
|selvedge.state.task.create_child.fields|selvedge.state.task.create_child.fields.{child,created,cursor,parent}
|selvedge.state.task.create_root|selvedge.state.task.create_root.{call,fields}
|selvedge.state.task.create_root.fields|selvedge.state.task.create_root.fields.{created,cursor,id,profile,reasoning,tools}
|selvedge.state.task.loaded|selvedge.state.task.loaded.{fields}
|selvedge.state.task.loaded.fields|selvedge.state.task.loaded.fields.{cursor,queue,task,tools}
|selvedge.state.task.parent|selvedge.state.task.parent.{fields,read}
|selvedge.state.task.parent.fields|selvedge.state.task.parent.fields.{child,created,parent}
|selvedge.state.task.queue|selvedge.state.task.queue.{add,append_next,consume,drain,fields}
|selvedge.state.task.queue.fields|selvedge.state.task.queue.fields.{message,queued,sequence,task}
|selvedge.state.task.row|selvedge.state.task.row.{fields}
|selvedge.state.task.row.fields|selvedge.state.task.row.fields.{created,cursor,id,profile,reasoning,status,updated,version}
|selvedge.state.task.tool|selvedge.state.task.tool.{fields}
|selvedge.state.task.tool.fields|selvedge.state.task.tool.fields.{task,tool}
|selvedge.state.tool|selvedge.state.tool.{fields,manifest,parameter,register}
|selvedge.state.tool.fields|selvedge.state.tool.fields.{description,name}
|selvedge.state.tool.parameter|selvedge.state.tool.parameter.{fields}
|selvedge.state.tool.parameter.fields|selvedge.state.tool.parameter.fields.{description,name,required,tool,type}
|selvedge.state.transaction|selvedge.state.transaction.{handle}
|selvedge.task|selvedge.task.{api_effect,api_output,core_output,correlation,dispatch,domain_event,domain_event_publish,factory,id,model_run,model_status_phase,router_command,router_ingress,runtime,runtime_command,runtime_control,runtime_exit,tool_request,tool_result,tool_run,tool_status_phase,validation_error,validation_message}
|selvedge.task.api_output|selvedge.task.api_output.{failure,validation}
|selvedge.task.api_output.failure|selvedge.task.api_output.failure.{kind,kind_field,message}
|selvedge.task.core_output|selvedge.task.core_output.{message,payload,task_id}
|selvedge.task.correlation|selvedge.task.correlation.{api_effect_id,model_run_id,task_id,validation}
|selvedge.task.correlation.validation|selvedge.task.correlation.validation.{api_effect,model_run,task}
|selvedge.task.dispatch|selvedge.task.dispatch.{conversation,correlation,provider,request_alias,response_preference,tool_manifest,validation}
|selvedge.task.dispatch.validation|selvedge.task.dispatch.validation.{tool_manifest}
|selvedge.task.domain_event_publish|selvedge.task.domain_event_publish.{event,task_id}
|selvedge.task.factory|selvedge.task.factory.{effect,failure,output,runtime_created,scan}
|selvedge.task.factory.failure|selvedge.task.factory.failure.{kind,kind_field,message,task_id}
|selvedge.task.factory.output|selvedge.task.factory.output.{effect_id,payload,result}
|selvedge.task.factory.runtime_created|selvedge.task.factory.runtime_created.{control,kind,kind_field,sender,task_id}
|selvedge.task.factory.scan|selvedge.task.factory.scan.{created,failed_list,failure,skip_reason,skipped,skipped_list}
|selvedge.task.factory.scan.failure|selvedge.task.factory.scan.failure.{kind,message,task_id}
|selvedge.task.factory.scan.skipped|selvedge.task.factory.scan.skipped.{reason,task_id}
|selvedge.task.id|selvedge.task.id.{export,validation}
|selvedge.task.model_run|selvedge.task.model_run.{event_id}
|selvedge.task.router_command|selvedge.task.router_command.{attach_result,client_command_id,client_id,command,payload,validation,validation_result}
|selvedge.task.router_command.attach_result|selvedge.task.router_command.attach_result.{sender}
|selvedge.task.router_command.validation_result|selvedge.task.router_command.validation_result.{child_task,client_correlation,task_scoped,user_input}
|selvedge.task.router_ingress|selvedge.task.router_ingress.{api_alias,sender,weak_sender}
|selvedge.task.runtime|selvedge.task.runtime.{factory}
|selvedge.task.runtime.factory|selvedge.task.runtime.factory.{command,create_child,dispatch,effect_args,ensure_one,inventory,one_output,run,scan,spawn_created,spawn_runtime}
|selvedge.task.runtime.factory.command|selvedge.task.runtime.factory.command.{create_child,ensure_missing,ensure_task}
|selvedge.task.runtime.factory.command.create_child|selvedge.task.runtime.factory.command.create_child.{args,cursor,effect_id,parent_task}
|selvedge.task.runtime.factory.command.ensure_missing|selvedge.task.runtime.factory.command.ensure_missing.{args,effect_id}
|selvedge.task.runtime.factory.command.ensure_task|selvedge.task.runtime.factory.command.ensure_task.{args,effect_id,task_id}
|selvedge.task.runtime.factory.create_child|selvedge.task.runtime.factory.create_child.{persist,persist_failure}
|selvedge.task.runtime.factory.effect_args|selvedge.task.runtime.factory.effect_args.{command,db,inventory,router,spawn_deps}
|selvedge.task.runtime.factory.ensure_one|selvedge.task.runtime.factory.ensure_one.{live,load_failure,pending}
|selvedge.task.runtime.factory.inventory|selvedge.task.runtime.factory.inventory.{live,pending}
|selvedge.task.runtime.factory.scan|selvedge.task.runtime.factory.scan.{list_failure,skip_live,skip_pending,spawn_failure,spawn_result}
|selvedge.task.runtime.factory.spawn_created|selvedge.task.runtime.factory.spawn_created.{spawn_failure}
|selvedge.task.runtime.factory.spawn_runtime|selvedge.task.runtime.factory.spawn_runtime.{failure,result}
|selvedge.task.runtime_command|selvedge.task.runtime_command.{sender}
|selvedge.task.runtime_control|selvedge.task.runtime_control.{debug,default,eq,finish_stop,freeze,is_frozen,is_stopping,new,same_control,state,stop,stop_result,unfreeze,wait}
|selvedge.task.runtime_exit|selvedge.task.runtime_exit.{control,reason,reason_field,task_id}
|selvedge.task.tool_request|selvedge.task.tool_request.{arguments,call_id,node_id,run_id,task_id,tool_name}
|selvedge.task.tool_result|selvedge.task.tool_result.{call_id,is_error,node_id,output_text,run_id,task_id,tool_name}
|selvedge.testsupport|selvedge.testsupport.{chatgpt_auth,chatgpt_auth_module,config,config_module,db,db_module,http,http_module,local_transport,local_transport_module,process,process_module}
|selvedge.testsupport.chatgpt_auth|selvedge.testsupport.chatgpt_auth.{file_json,jwt,write_file}
|selvedge.testsupport.chatgpt_auth.write_file|selvedge.testsupport.chatgpt_auth.write_file.{directory,persist}
|selvedge.testsupport.config|selvedge.testsupport.config.{logging}
|selvedge.testsupport.db|selvedge.testsupport.db.{empty_snapshot,memory,message_node,model_profiles,root_task,root_user_task,summary_subscription}
|selvedge.testsupport.db.message_node|selvedge.testsupport.db.message_node.{fail}
|selvedge.testsupport.db.root_task|selvedge.testsupport.db.root_task.{fail}
|selvedge.testsupport.http|selvedge.testsupport.http.{addr,base_url,held_addr,held_port,held_port_value,hold_port,port,released_port,spawn_axum,spawn_http,url}
|selvedge.testsupport.local_transport|selvedge.testsupport.local_transport.{attach,attach_action,attach_calls,attach_script,close,close_action,close_calls,close_script,command,command_action,command_calls,command_script,connect,connect_plan_state,connected_client,connected_client_fail,connected_client_timeout,connected_configs,drop_counter,drop_stream,empty_snapshot,fake,install_connect,new_state,next_seq,noop_command,notice_frame,poll_sender,poll_stream,ready,ready_action,ready_calls,ready_script,ready_state,state,state_handle,valid_attach,valid_attach_for,valid_command,valid_config,valid_local_config}
|selvedge.testsupport.local_transport.attach|selvedge.testsupport.local_transport.attach.{rejected}
|selvedge.testsupport.local_transport.connect|selvedge.testsupport.local_transport.connect.{state_lock}
|selvedge.testsupport.local_transport.drop_stream|selvedge.testsupport.local_transport.drop_stream.{drop,poll}
|selvedge.testsupport.local_transport.poll_stream|selvedge.testsupport.local_transport.poll_stream.{poll,signal}
|selvedge.testsupport.process|selvedge.testsupport.process.{assert_child_success,run_child,spawn_child}
|selvedge.testsupport.process.spawn_child|selvedge.testsupport.process.spawn_child.{fail}
|tool|tool.{api,check,cli,detector,format,project_index,readme,scan,worktree}
|tool.api|tool.api.{diagnostic,mode,module,parse,record,report,status,tag}
|tool.api.diagnostic|tool.api.diagnostic.{line,macro,message,path,rule}
|tool.api.parse|tool.api.parse.{id_grammar,id_presence,sentence_count,sentence_presence,tag,verifies_body}
|tool.api.record|tool.api.record.{binding,id,line,path,sentence,tag,test_context}
|tool.api.record.binding|tool.api.record.binding.{file_header,inner_doc,target}
|tool.api.report|tool.api.report.{declarations,diagnostics,verifications}
|tool.api.tag|tool.api.tag.{string}
|tool.check|tool.check.{all_anchors,base_head_snapshot,diagnostics,git_path_list,git_path_list_status,git_ref_list,git_ref_read,git_ref_status,head_snapshot,merge_base,registry,snapshot}
|tool.check.git_path_list|tool.check.git_path_list.{cached,worktree}
|tool.check.merge_base|tool.check.merge_base.{status}
|tool.check.registry|tool.check.registry.{ancestor,ancestor_declaration,duplicate,inline_test_context,target_declaration,target_kind,target_presence,test_path,verification_context}
|tool.check.snapshot|tool.check.snapshot.{git_ref,git_ref_invalid,git_ref_missing,index,staged_invalid,staged_missing,staged_read,worktree_invalid,worktree_read}
|tool.cli|tool.cli.{all_error,all_stale,base_error,base_ref,base_stale,format_error,project_index,readme_freshness_error,readme_freshness_stale,readme_mermaid_error,scan_error,scan_output,scan_status,staged_error,staged_stale,usage_error,workspace_root}
|tool.cli.project_index|tool.cli.project_index.{check_error,check_fresh,check_stale,update_error,update_success,warning_output}
|tool.detector|tool.detector.{anchor,assertion,contract,diagnostic,diff,diff_command,failure,field,full,hunk_parse,line,side_effect,signature,structure,test_context}
|tool.detector.assertion|tool.detector.assertion.{unwrap}
|tool.detector.contract|tool.detector.contract.{container}
|tool.detector.contract.container|tool.detector.contract.container.{header}
|tool.detector.failure|tool.detector.failure.{assertion}
|tool.detector.field|tool.detector.field.{tuple}
|tool.detector.structure|tool.detector.structure.{trait_object}
|tool.format|tool.format.{index_block,read,render,write}
|tool.format.index_block|tool.format.index_block.{insert,marker_balance,marker_count,marker_lookup_begin,marker_lookup_end,replace}
|tool.project_index|tool.project_index.{check,directory_map,git_env,git_files,render,status,update,upsert,warning}
|tool.project_index.check|tool.project_index.check.{missing_agents,read_error}
|tool.project_index.directory_map|tool.project_index.directory_map.{nonempty_path}
|tool.project_index.git_files|tool.project_index.git_files.{failure}
|tool.project_index.update|tool.project_index.update.{read_error,write}
|tool.project_index.upsert|tool.project_index.upsert.{marker_balance,marker_count,marker_lookup_begin,marker_lookup_end}
|tool.project_index.warning|tool.project_index.warning.{collect,entry_count,missing_dir,path,read_error}
|tool.readme|tool.readme.{changed_files,commit,freshness,mermaid,metadata,module,packages,read_file,stale_package,status}
|tool.readme.changed_files|tool.readme.changed_files.{git_failure,readme_exclusion,root_scope,spawn_failure}
|tool.readme.commit|tool.readme.commit.{ancestor,ancestor_git_failure,ancestor_spawn_failure,spawn_failure,unknown}
|tool.readme.mermaid|tool.readme.mermaid.{diagnostics,invalid}
|tool.readme.metadata|tool.readme.metadata.{invalid_commit,missing,package_mismatch}
|tool.readme.packages|tool.readme.packages.{excludes,git_failure,git_spawn_failure,metadata,metadata_failure,metadata_json,metadata_packages,metadata_path,metadata_spawn_failure,workspace_members}
|tool.readme.stale_package|tool.readme.stale_package.{changed_files,freshness_commit,package,package_path,readme_path}
|tool.scan|tool.scan.{binding,comment_parse_error,extract,parse_error,parse_failed,parser_unavailable,string_literals}
<!-- END AGENTS_MD_REQUIREMENT_INDEX -->

## Project Index Workflow

- Update the index with `just agents-index`
- Check whether the index is current with `just agents-index-check`
- The underlying repository commands are `cargo xtask agents-index update` and `cargo xtask agents-index check`
- Run all configured hooks with `just hooks`
- The index only includes Git-tracked files. Git-ignored and untracked files are excluded on purpose.
- Index commands warn when an indexed directory has an unusually large number of direct filesystem entries.

## Project Index

<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->
```text
[Project Index]|root:.
|source:git-tracked-files-only
|excluded:{git-ignored,git-untracked}
|.:{.cargo/,.github/,crates/,scripts/,src/,tests/,xtask/,.editorconfig,.gitignore,.pre-commit-config.yaml,AGENTS.md,CONTRIBUTING.md,Cargo.lock,Cargo.toml,Justfile,README.md,rust-toolchain.toml}
|.cargo:{config.toml}
|.github:{workflows/}
|.github/workflows:{ci.yml}
|crates:{api/,chatgpt-api/,chatgpt-auth/,chatgpt-login/,client-sync/,client/,command-model/,config-model/,config/,core/,db/,domain-model/,events/,local-client/,local-protocol/,logging/,model-credentials/,model-providers/,router/,server/,systemd/,task-runtime-factory/,test-support/,tui/,web/}
|crates/api:{src/,tests/,Cargo.toml,README.md}
|crates/api/src:{lib.rs}
|crates/api/tests:{api_contract.rs}
|crates/chatgpt-api:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-api/src:{lib.rs}
|crates/chatgpt-api/tests:{support/,public_api.rs,request_contract.rs,stream_integration.rs}
|crates/chatgpt-api/tests/support:{mod.rs}
|crates/chatgpt-auth:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-auth/src:{auth_file.rs,config.rs,jwt.rs,lib.rs,lock.rs,refresh.rs,resolve.rs}
|crates/chatgpt-auth/tests:{support/,parse_contract.rs,public_api.rs,resolve_integration.rs}
|crates/chatgpt-auth/tests/support:{mod.rs}
|crates/chatgpt-login:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-login/src:{auth_file.rs,config.rs,device_code.rs,id_token.rs,lib.rs,token_exchange.rs}
|crates/chatgpt-login/tests:{support/,complete_login_integration.rs,device_code_start_integration.rs,public_api.rs}
|crates/chatgpt-login/tests/support:{mod.rs}
|crates/client:{src/,tests/,Cargo.toml,README.md}
|crates/client-sync:{src/,tests/,Cargo.toml,README.md}
|crates/client-sync/src:{lib.rs}
|crates/client-sync/tests:{client_sync_contract.rs}
|crates/client/src:{config_resolution.rs,lib.rs,redaction.rs,redirect_runtime.rs,request_prep.rs,runtime.rs,single_hop.rs}
|crates/client/tests:{support/,http_integration.rs}
|crates/client/tests/support:{mod.rs}
|crates/command-model:{src/,tests/,Cargo.toml,README.md}
|crates/command-model/src:{lib.rs}
|crates/command-model/tests:{command_contract.rs}
|crates/config:{examples/,src/,tests/,Cargo.toml,README.md}
|crates/config-model:{src/,tests/,Cargo.toml,README.md}
|crates/config-model/src:{lib.rs}
|crates/config-model/tests:{model_contract.rs}
|crates/config/examples:{README.md,layered_sources.rs,load_defaults.rs,runtime_updates.rs}
|crates/config/src:{lib.rs}
|crates/config/tests:{public_api.rs}
|crates/core:{src/,tests/,Cargo.toml,README.md}
|crates/core/src:{lib.rs}
|crates/core/tests:{runtime_contract.rs}
|crates/db:{src/,tests/,Cargo.toml,README.md}
|crates/db/src:{lib.rs,schema.sql}
|crates/db/tests:{db_contract.rs}
|crates/domain-model:{src/,tests/,Cargo.toml,README.md}
|crates/domain-model/src:{lib.rs}
|crates/domain-model/tests:{domain_contract.rs}
|crates/events:{src/,tests/,Cargo.toml,README.md}
|crates/events/src:{lib.rs}
|crates/events/tests:{events_contract.rs}
|crates/local-client:{src/,tests/,Cargo.toml,README.md}
|crates/local-client/src:{lib.rs}
|crates/local-client/tests:{local_client_contract.rs}
|crates/local-protocol:{src/,tests/,Cargo.toml,README.md}
|crates/local-protocol/src:{lib.rs}
|crates/local-protocol/tests:{local_protocol_contract.rs}
|crates/logging:{src/,Cargo.toml,README.md}
|crates/logging/src:{lib.rs}
|crates/model-credentials:{src/,tests/,Cargo.toml,README.md}
|crates/model-credentials/src:{lib.rs}
|crates/model-credentials/tests:{credential_contract.rs}
|crates/model-providers:{src/,tests/,Cargo.toml,README.md}
|crates/model-providers/src:{lib.rs}
|crates/model-providers/tests:{provider_contract.rs}
|crates/router:{src/,tests/,Cargo.toml,README.md}
|crates/router/src:{lib.rs}
|crates/router/tests:{router_contract.rs}
|crates/server:{src/,tests/,Cargo.toml,README.md}
|crates/server/src:{lib.rs}
|crates/server/tests:{server_contract.rs}
|crates/systemd:{src/,tests/,Cargo.toml,README.md}
|crates/systemd/src:{lib.rs}
|crates/systemd/tests:{systemd_contract.rs}
|crates/task-runtime-factory:{src/,tests/,Cargo.toml,README.md}
|crates/task-runtime-factory/src:{lib.rs}
|crates/task-runtime-factory/tests:{factory_contract.rs}
|crates/test-support:{src/,Cargo.toml,README.md}
|crates/test-support/src:{chatgpt_auth.rs,config.rs,db.rs,http.rs,lib.rs,local_transport.rs,process.rs}
|crates/tui:{src/,tests/,Cargo.toml,README.md}
|crates/tui/src:{lib.rs}
|crates/tui/tests:{tui_contract.rs}
|crates/web:{src/,tests/,Cargo.toml,README.md}
|crates/web/src:{lib.rs}
|crates/web/tests:{web_contract.rs}
|scripts:{bootstrap.sh,create-worktree.sh}
|src:{lib.rs,main.rs}
|tests:{config_integration.rs,stdout_stderr_integration.rs,worktree_tool_integration.rs}
|xtask:{src/,Cargo.toml,README.md}
|xtask/src:{agents_index.rs,lib.rs,main.rs,readme_gate.rs,requirements.rs}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->
