#![doc = include_str!("../README.md")]
//! @behavior selvedge.model.router.spawn The router accepts process-local ingress and routes client commands, runtime output, API output, tool output, factory output, and event publication until stopped.
//! @behavior selvedge.model.router.r2 Router processing preserves command routing, event publication, runtime ownership, and typed termination behavior.
//! @behavior selvedge.model.router.r2.run Router execution stops runtimes before returning stopped, mailbox-closed, or fatal exit status.
//! @behavior selvedge.model.router.r2.command Router command handling validates incoming commands before routing them to task, event, factory, or runtime effects.
//! @behavior selvedge.model.router.r2.tool_execution Router tool execution delegates tool requests to the configured executor and routes results back through ingress.
//! @behavior selvedge.model.router.r2.attach Router attach handling reserves event client sessions and reports admission outcomes to callers.
//! @behavior selvedge.model.router.r2.factory Router factory handling starts runtime factory effects and applies their output to router-owned state.
//! @behavior selvedge.model.router.r2.runtime Router runtime handling registers, commands, stops, and removes task runtimes by task identity.
//! @behavior selvedge.model.router.r2.events Router event handling publishes domain and debug events through the event ingress boundary.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;

use selvedge_api::{ApiExecutorConfig, spawn_model_call_tokio_task};
use selvedge_command_model::{
    ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage, DebugRawEvent, DetachReason,
    DomainEvent, DomainEventPublishRequest, EventClientReservationResult, EventControlMessage,
    EventIngress, EventIngressSender, FactoryEffectId, FactoryOutput, FactoryOutputEnvelope,
    FactoryScanOutput, FactoryTaskFailure, RawEvent, ReserveClientSession,
    RouterAttachAdmissionResult, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
    RouterIngressSender, RouterIngressWeakSender, TaskRuntimeCommand, TaskRuntimeControl,
    TaskRuntimeExitNotice, TaskRuntimeSender, ToolExecutionRequest, ToolExecutionResult,
    validate_router_command,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::DbPool;
use selvedge_domain_model::TaskId;
use selvedge_task_runtime_factory::{
    CreateChildTaskAndRuntimeCommand, EnsureMissingTaskRuntimesCommand, EnsureTaskRuntimeCommand,
    FactoryCommand, FactoryEffectArgs, FactoryRuntimeInventory, run_factory_effect,
};
use tokio::task::JoinHandle;

// @behavior selvedge.model.router.r2.start_args Router start arguments provide database, event ingress, API, tool, and runtime dependencies for the spawned router.
pub struct RouterStartArgs {
    // @behavior selvedge.model.router.r2.start_args.db The spawned router uses the supplied database pool when factory effects create or discover task runtimes.
    pub db: DbPool,
    // @behavior selvedge.model.router.r2.start_args.events_tx The spawned router publishes client controls, debug events, and domain events through the supplied events ingress.
    pub events_tx: EventIngressSender,
    // @behavior selvedge.model.router.r2.start_args.api_config The spawned router delegates model calls with the supplied API execution config.
    pub api_config: ApiExecutorConfig,
    // @behavior selvedge.model.router.r2.start_args.tool_executor The spawned router delegates tool requests to the supplied tool executor.
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    // @behavior selvedge.model.router.r2.start_args.core_spawn_deps The spawned router passes the supplied core runtime dependencies into task runtime factory effects.
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
}

// @behavior selvedge.model.router.r2.tool_execution_spawner Tool execution spawners receive router tool requests and return a task handle or typed spawn error.
// @intent selvedge.model.router.r2.tool_execution_spawner.extension The tool execution spawner abstraction lets router callers provide the process-local executor that produces tool output.
pub trait ToolExecutionSpawner: Send + Sync {
    /// @behavior selvedge.model.router.r2.spawn_tool_execution Router tool requests are delegated to the configured executor with router ingress for the resulting tool output.
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.model.router.r2.tool_spawn_error Tool execution spawn failures are reported as typed errors for Tokio spawn failure or executor unavailability.
pub enum ToolExecutionSpawnError {
    TokioSpawnFailed,
    ToolExecutorUnavailable,
}

// @behavior selvedge.model.router.r2.handle Router spawn returns an ingress sender and a join handle for observing router termination.
pub struct RouterHandle {
    // @behavior selvedge.model.router.r2.handle.ingress_tx Router callers submit commands and producer output through the handle ingress sender.
    pub ingress_tx: RouterIngressSender,
    // @behavior selvedge.model.router.r2.handle.join_handle Router callers observe the final router exit status through the handle join task.
    pub join_handle: JoinHandle<RouterExitStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.model.router.r2.exit_status Router termination reports whether the router stopped by request, mailbox closure, or fatal error.
pub enum RouterExitStatus {
    Stopped,
    EventsMailboxClosed,
    RouterMailboxClosed,
    // @behavior selvedge.model.router.r2.exit_status.fatal_error Fatal router termination carries the diagnostic message visible to the join handle caller.
    FatalError(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.model.router.r2.spawn_error Router spawn reports Tokio task creation failure as a typed spawn error.
pub enum SpawnRouterError {
    TokioSpawnFailed,
}

// @behavior selvedge.model.router.r2.spawn_router Spawning a router starts the actor with unbounded process-local ingress and returns the ingress handle to callers.
pub fn spawn_router(args: RouterStartArgs) -> Result<RouterHandle, SpawnRouterError> {
    let (ingress_tx, ingress_rx) = tokio::sync::mpsc::unbounded_channel();
    let actor = RouterActor {
        db: args.db,
        events_tx: args.events_tx,
        api_config: args.api_config,
        tool_executor: args.tool_executor,
        core_spawn_deps: args.core_spawn_deps,
        router_tx: ingress_tx.downgrade(),
        ingress_rx,
        task_runtime_registry: HashMap::new(),
        pending_effects: HashMap::new(),
        pending_effects_by_task: HashMap::new(),
        deferred_commands: HashMap::new(),
        next_effect_seq: 1,
    };
    let join_handle = tokio::spawn(actor.run());

    Ok(RouterHandle {
        ingress_tx,
        join_handle,
    })
}

// @intent selvedge.model.router.r2.actor_effects RouterActor stores delegated effect boundaries for database, events, API, tools, core runtimes, and factory state.
struct RouterActor {
    db: DbPool,
    events_tx: EventIngressSender,
    api_config: ApiExecutorConfig,
    tool_executor: Arc<dyn ToolExecutionSpawner>,
    core_spawn_deps: TaskRuntimeSpawnDeps,
    router_tx: RouterIngressWeakSender,
    ingress_rx: tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
    task_runtime_registry: HashMap<TaskId, RuntimeRegistryEntry>,
    pending_effects: HashMap<FactoryEffectId, PendingRuntimeEffect>,
    pending_effects_by_task: HashMap<TaskId, FactoryEffectId>,
    deferred_commands: HashMap<TaskId, VecDeque<TaskRuntimeCommand>>,
    next_effect_seq: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PendingRuntimeEffect {
    task_id: Option<TaskId>,
}

#[derive(Clone, Debug)]
struct RuntimeRegistryEntry {
    sender: TaskRuntimeSender,
    control: TaskRuntimeControl,
}

impl RouterActor {
    async fn run(mut self) -> RouterExitStatus {
        while let Some(ingress) = self.ingress_rx.recv().await {
            let result = match ingress {
                RouterIngressMessage::Command(command) => self.handle_command(command).await,
                RouterIngressMessage::Core(envelope) => self.handle_core(envelope).await,
                RouterIngressMessage::ApiOutput(envelope) => self.handle_api_output(envelope).await,
                RouterIngressMessage::Tool(result) => self.handle_tool_output(result).await,
                RouterIngressMessage::RuntimeExit(notice) => self.handle_runtime_exit(notice).await,
                RouterIngressMessage::PublishToEvents(request) => {
                    self.publish_domain_event(request).await
                }
                RouterIngressMessage::StopRouter => {
                    self.stop_runtimes().await;
                    return RouterExitStatus::Stopped;
                }
            };

            // @behavior selvedge.model.router.r2.run.error_exit The router stops live task runtimes before returning a failing exit status from message handling.
            if let Err(status) = result {
                self.stop_runtimes().await;
                return status;
            }
        }

        self.stop_runtimes().await;
        RouterExitStatus::RouterMailboxClosed
    }

    async fn handle_command(
        &mut self,
        envelope: RouterCommandEnvelope,
        // @behavior selvedge.model.router.r2.command.validation Invalid router commands publish a debug event and complete command handling through the events path.
    ) -> Result<(), RouterExitStatus> {
        if validate_router_command(&envelope).is_err() {
            return self
                .publish_debug(None, "router command validation failed")
                .await;
        }

        match envelope.command {
            RouterCommand::AttachClient {
                client_id,
                client_command_id,
                admission_tx,
                ..
            } => {
                self.reserve_client_session(client_id, client_command_id, admission_tx)
                    .await
            }
            RouterCommand::DetachClient {
                client_id,
                client_command_id,
            } => {
                self.send_event(EventIngress::Control(EventControlMessage::DetachClient(
                    selvedge_command_model::DetachClient {
                        client_id,
                        client_command_id,
                        reason: DetachReason::ClientRequested,
                    },
                )))
                .await
            }
            RouterCommand::UpdateSubscription {
                client_id,
                client_command_id,
                subscription,
            } => {
                self.send_event(EventIngress::Control(
                    EventControlMessage::UpdateSubscription(
                        selvedge_command_model::UpdateSubscription {
                            client_id,
                            client_command_id,
                            subscription,
                        },
                    ),
                ))
                .await
            }
            RouterCommand::SendUserInput {
                task_id,
                message_text,
            } => {
                self.route_task_local_command(
                    task_id,
                    TaskRuntimeCommand::UserInput { message_text },
                    true,
                )
                .await
            }
            RouterCommand::ArchiveTask { task_id } => {
                self.route_task_local_command(task_id, TaskRuntimeCommand::Archive, true)
                    .await
            }
            RouterCommand::StopTaskRuntime { task_id } => self.stop_task_runtime(task_id).await,
            RouterCommand::EnsureTaskRuntime { task_id } => self.ensure_task_runtime(task_id).await,
            RouterCommand::EnsureMissingTaskRuntimes => self.ensure_missing_task_runtimes().await,
            RouterCommand::CreateChildTaskAndRuntime {
                parent_task_id,
                child_cursor_node_id,
            } => {
                self.create_child_task_and_runtime(parent_task_id, child_cursor_node_id)
                    .await
            }
        }
    }

    async fn handle_core(&mut self, envelope: CoreOutputEnvelope) -> Result<(), RouterExitStatus> {
        // Core output is task-routed. Runtime identity gates registry ownership and exit cleanup;
        // queued core outputs already in ingress continue through normal task routing.
        let task_id = envelope.task_id;
        match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => {
                if request.correlation.task_id != task_id {
                    return Ok(());
                }
                let _join_handle = spawn_model_call_tokio_task(
                    request,
                    self.router_tx.clone(),
                    self.api_config.clone(),
                );
                Ok(())
            }
            CoreOutputMessage::RequestToolExecution(request) => {
                if request.task_id != task_id {
                    return Ok(());
                }
                let fallback_request = request.clone();
                match self
                    .tool_executor
                    .spawn_tool_execution(request, self.router_tx.clone())
                {
                    Ok(_join_handle) => Ok(()),
                    // @behavior selvedge.model.router.r2.tool_execution.spawn_failure Tool executor spawn failure is converted into an error tool result routed back to the task runtime.
                    Err(_) => {
                        self.handle_tool_output(tool_spawn_failed_result(fallback_request))
                            .await
                    }
                }
            }
            CoreOutputMessage::PublishDomainEvent(request) => {
                if request.task_id != task_id {
                    return Ok(());
                }
                self.publish_domain_event(request).await
            }
            CoreOutputMessage::RuntimeReady => {
                self.publish_domain_event(DomainEventPublishRequest {
                    task_id,
                    event: DomainEvent::TaskRuntimeReady,
                })
                .await
            }
        }
    }

    async fn reserve_client_session(
        &mut self,
        client_id: selvedge_command_model::ClientId,
        client_command_id: selvedge_command_model::ClientCommandId,
        admission_tx: selvedge_command_model::RouterAttachAdmissionSender,
        // @behavior selvedge.model.router.r2.attach.admission Attach commands reserve the client session through events and answer the admission sender with the reservation result.
    ) -> Result<(), RouterExitStatus> {
        let (result_tx, result_rx) = tokio::sync::oneshot::channel();
        let cleanup_client_id = client_id.clone();
        let cleanup_client_command_id = client_command_id.clone();
        if self
            .events_tx
            // @behavior selvedge.model.router.r2.attach.reserve_event Attach admission sends a reserve-client control message to the events ingress.
            .send(EventIngress::Control(
                EventControlMessage::ReserveClientSession(ReserveClientSession {
                    client_id,
                    client_command_id,
                    result_tx,
                }),
            ))
            .await
            .is_err()
        {
            // @behavior selvedge.model.router.r2.attach.events_closed_response Attach admission reports EventsMailboxClosed to the caller when reservation cannot reach events.
            let _ = admission_tx.send(RouterAttachAdmissionResult::EventsMailboxClosed);
            // @behavior selvedge.model.router.r2.attach.events_closed_exit Attach admission terminates router processing with EventsMailboxClosed when reservation cannot reach events.
            return Err(RouterExitStatus::EventsMailboxClosed);
        }

        let (result, reserved) = match result_rx.await {
            Ok(EventClientReservationResult::Reserved) => {
                (RouterAttachAdmissionResult::Accepted, true)
            }
            Ok(EventClientReservationResult::DuplicateAttach) => {
                (RouterAttachAdmissionResult::DuplicateAttach, false)
            }
            Ok(EventClientReservationResult::ClientRegistryFull) => {
                (RouterAttachAdmissionResult::ClientRegistryFull, false)
            }
            // @behavior selvedge.model.router.r2.attach.result_channel_closed A closed reservation result channel reports EventsMailboxClosed to the attach caller.
            Err(_) => (RouterAttachAdmissionResult::EventsMailboxClosed, false),
        };

        // @behavior selvedge.model.router.r2.attach.abandoned_reserved_client A reserved client whose admission response receiver is gone is detached through events as ClientDisconnected.
        if admission_tx.send(result).is_err() && reserved {
            self.send_event(EventIngress::Control(EventControlMessage::DetachClient(
                selvedge_command_model::DetachClient {
                    client_id: cleanup_client_id,
                    client_command_id: cleanup_client_command_id,
                    reason: DetachReason::ClientDisconnected,
                },
            )))
            .await?;
        }
        Ok(())
    }

    async fn handle_api_output(
        &mut self,
        envelope: ApiOutputEnvelope,
        // @behavior selvedge.model.router.r2.api_output API output is routed to the live task runtime for its task or discarded with a debug event when stale.
    ) -> Result<(), RouterExitStatus> {
        let task_id = match &envelope {
            ApiOutputEnvelope::Success { correlation, .. }
            | ApiOutputEnvelope::Failure { correlation, .. } => correlation.task_id.clone(),
        };

        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            self.send_to_task_runtime(
                task_id,
                sender,
                TaskRuntimeCommand::ApiModelReply(envelope),
                false,
            )
            .await
        } else {
            self.publish_debug(Some(task_id), "stale api output discarded")
                .await
        }
    }

    async fn handle_tool_output(
        &mut self,
        result: ToolExecutionResult,
        // @behavior selvedge.model.router.r2.tool_output Tool output is routed to the live task runtime for its task or discarded with a debug event when stale.
    ) -> Result<(), RouterExitStatus> {
        let task_id = result.task_id.clone();
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            self.send_to_task_runtime(
                task_id,
                sender,
                TaskRuntimeCommand::ToolResult(result),
                false,
            )
            .await
        } else {
            self.publish_debug(Some(task_id), "stale tool output discarded")
                .await
        }
    }

    async fn handle_runtime_exit(
        &mut self,
        notice: TaskRuntimeExitNotice,
        // @behavior selvedge.model.router.r2.runtime_exit Runtime exit notices remove the matching live runtime entry and publish a debug event for current or stale exits.
    ) -> Result<(), RouterExitStatus> {
        let removed = self
            .task_runtime_registry
            .get(&notice.task_id)
            .is_some_and(|entry| entry.control.same_control(&notice.task_runtime_control));
        if removed {
            self.task_runtime_registry.remove(&notice.task_id);
        }
        let message = if removed {
            format!("task runtime exited: {:?}", notice.reason)
        } else {
            format!("stale task runtime exit discarded: {:?}", notice.reason)
        };
        self.publish_debug(Some(notice.task_id), message).await
    }

    async fn route_task_local_command(
        &mut self,
        task_id: TaskId,
        command: TaskRuntimeCommand,
        create_when_missing: bool,
        // @behavior selvedge.model.router.r2.task_command Routing a task-local command sends it to a live runtime, defers it behind pending creation, or emits a debug miss.
    ) -> Result<(), RouterExitStatus> {
        if let Some(sender) = self
            .task_runtime_registry
            .get(&task_id)
            .map(|entry| entry.sender.clone())
        {
            return self
                .send_to_task_runtime(task_id, sender, command, create_when_missing)
                .await;
        }

        if self.pending_effects_by_task.contains_key(&task_id) {
            self.deferred_commands
                .entry(task_id)
                .or_default()
                .push_back(command);
            return Ok(());
        }

        if create_when_missing {
            self.deferred_commands
                .entry(task_id.clone())
                .or_default()
                .push_back(command);
            return self.start_ensure_task_runtime_effect(task_id).await;
        }

        self.publish_debug(Some(task_id), "task runtime is not live")
            .await
    }

    async fn send_to_task_runtime(
        &mut self,
        task_id: TaskId,
        sender: TaskRuntimeSender,
        command: TaskRuntimeCommand,
        create_when_closed: bool,
        // @behavior selvedge.model.router.r2.task_command.delivery Task runtime command delivery removes a closed runtime and either recreates it with the command deferred or emits a debug failure.
    ) -> Result<(), RouterExitStatus> {
        // @behavior selvedge.model.router.r2.task_command.send Successful task runtime command sends leave registry ownership unchanged.
        let Err(error) = sender.send(command).await else {
            return Ok(());
        };

        self.task_runtime_registry.remove(&task_id);
        if create_when_closed {
            self.deferred_commands
                .entry(task_id.clone())
                .or_default()
                .push_back(error.0);
            return self.start_ensure_task_runtime_effect(task_id).await;
        }

        self.publish_debug(Some(task_id), "task runtime mailbox closed")
            .await
    }

    async fn ensure_task_runtime(&mut self, task_id: TaskId) -> Result<(), RouterExitStatus> {
        if self.task_runtime_registry.contains_key(&task_id) {
            return self
                .publish_debug(Some(task_id), "task runtime is already live")
                .await;
        }
        if self.pending_effects_by_task.contains_key(&task_id) {
            return self
                .publish_debug(Some(task_id), "task runtime creation is already pending")
                .await;
        }

        self.start_ensure_task_runtime_effect(task_id).await
    }

    async fn start_ensure_task_runtime_effect(
        &mut self,
        task_id: TaskId,
        // @behavior selvedge.model.router.r2.factory.ensure_task Starting an ensure-task-runtime effect records the pending task and invokes the runtime factory.
    ) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects.insert(
            effect_id.clone(),
            PendingRuntimeEffect {
                task_id: Some(task_id.clone()),
            },
        );
        self.pending_effects_by_task
            .insert(task_id.clone(), effect_id.clone());
        let command =
            FactoryCommand::EnsureTaskRuntime(EnsureTaskRuntimeCommand { effect_id, task_id });
        self.run_factory_effect(command).await
    }

    async fn ensure_missing_task_runtimes(&mut self) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects
            .insert(effect_id.clone(), PendingRuntimeEffect { task_id: None });
        let command = FactoryCommand::EnsureMissingTaskRuntimes(EnsureMissingTaskRuntimesCommand {
            effect_id,
        });
        self.run_factory_effect(command).await
    }

    async fn create_child_task_and_runtime(
        &mut self,
        parent_task_id: TaskId,
        child_cursor_node_id: selvedge_domain_model::HistoryNodeId,
        // @behavior selvedge.model.router.r2.factory.create_child Create-child commands invoke the runtime factory with the parent task and cursor node.
    ) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects
            .insert(effect_id.clone(), PendingRuntimeEffect { task_id: None });
        let command = FactoryCommand::CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand {
            effect_id,
            parent_task_id,
            child_cursor_node_id,
        });
        self.run_factory_effect(command).await
    }

    async fn run_factory_effect(
        &mut self,
        command: FactoryCommand,
        // @behavior selvedge.model.router.r2.factory.run Factory effects receive live and pending runtime inventory plus router ingress for created runtime output.
    ) -> Result<(), RouterExitStatus> {
        let current_task_effect = match &command {
            FactoryCommand::EnsureTaskRuntime(command) => Some(&command.task_id),
            FactoryCommand::EnsureMissingTaskRuntimes(_)
            | FactoryCommand::CreateChildTaskAndRuntime(_) => None,
        };
        let inventory = FactoryRuntimeInventory {
            live_task_runtimes: self.task_runtime_registry.keys().cloned().collect(),
            pending_task_runtime_effects: self
                .pending_effects_by_task
                .keys()
                .filter(|task_id| Some(*task_id) != current_task_effect)
                .cloned()
                .collect(),
        };
        let envelope = run_factory_effect(FactoryEffectArgs {
            command,
            db: self.db.clone(),
            router_tx: self.router_tx.clone(),
            core_spawn_deps: self.core_spawn_deps.clone(),
            runtime_inventory: inventory,
        });
        self.apply_factory_output(envelope).await
    }

    async fn apply_factory_output(
        &mut self,
        envelope: FactoryOutputEnvelope,
        // @behavior selvedge.model.router.r2.factory.output Factory output is accepted only for pending effects and otherwise publishes a stale-output debug event.
    ) -> Result<(), RouterExitStatus> {
        let Some(pending) = self.pending_effects.remove(&envelope.effect_id) else {
            return self
                .publish_debug(None, "stale factory output discarded")
                .await;
        };
        if let Some(task_id) = &pending.task_id {
            self.pending_effects_by_task.remove(task_id);
        }

        match envelope.output {
            FactoryOutput::RuntimeCreated(created) => {
                self.register_runtime(
                    created.task_id,
                    created.task_runtime_tx,
                    created.task_runtime_control,
                )
                .await
            }
            FactoryOutput::ScanFinished(scan) => self.apply_scan_output(scan).await,
            FactoryOutput::Failed(failure) => {
                if let Some(task_id) = failure.task_id.clone() {
                    self.deferred_commands.remove(&task_id);
                }
                self.publish_debug(failure.task_id, failure.message).await
            }
        }
    }

    async fn apply_scan_output(&mut self, scan: FactoryScanOutput) -> Result<(), RouterExitStatus> {
        for created in scan.created {
            self.register_runtime(
                created.task_id,
                created.task_runtime_tx,
                created.task_runtime_control,
            )
            .await?;
        }
        for failure in scan.failed {
            self.publish_factory_task_failure(failure).await?;
        }
        Ok(())
    }

    async fn register_runtime(
        &mut self,
        task_id: TaskId,
        sender: TaskRuntimeSender,
        control: TaskRuntimeControl,
        // @behavior selvedge.model.router.r2.runtime.register Registering a runtime makes it the live command target and drains deferred commands for that task.
    ) -> Result<(), RouterExitStatus> {
        self.task_runtime_registry.insert(
            task_id.clone(),
            RuntimeRegistryEntry {
                sender: sender.clone(),
                control,
            },
        );
        let mut deferred = self.deferred_commands.remove(&task_id).unwrap_or_default();
        if deferred
            .iter()
            .any(|command| matches!(command, TaskRuntimeCommand::Archive))
        {
            while let Some(command) = deferred.pop_front() {
                // @behavior selvedge.model.router.r2.runtime.register.archive Deferred archive commands are delivered without sending runtime start first.
                if sender.send(command).await.is_err() {
                    self.task_runtime_registry.remove(&task_id);
                    return self
                        .publish_debug(Some(task_id), "deferred task command delivery failed")
                        .await;
                }
            }
            return Ok(());
        }

        // @behavior selvedge.model.router.r2.runtime.register.start Newly registered runtimes receive Start before non-archive deferred commands.
        if sender.send(TaskRuntimeCommand::Start).await.is_err() {
            self.task_runtime_registry.remove(&task_id);
            return self
                .publish_debug(Some(task_id), "task runtime start failed")
                .await;
        }

        while let Some(command) = deferred.pop_front() {
            // @behavior selvedge.model.router.r2.runtime.register.deferred Deferred task commands are delivered after runtime start and failures remove the runtime with a debug event.
            if sender.send(command).await.is_err() {
                self.task_runtime_registry.remove(&task_id);
                return self
                    .publish_debug(Some(task_id), "deferred task command delivery failed")
                    .await;
            }
        }
        Ok(())
    }

    async fn stop_task_runtime(&mut self, task_id: TaskId) -> Result<(), RouterExitStatus> {
        if let Some(entry) = self.task_runtime_registry.get(&task_id).cloned() {
            if self.stop_runtime_entry(entry.clone()).await.is_err() {
                return self
                    .publish_debug(Some(task_id), "task runtime mailbox closed")
                    .await;
            }
            self.remove_runtime_if_current(&task_id, &entry);
            return Ok(());
        }
        if self.pending_effects_by_task.remove(&task_id).is_some() {
            self.deferred_commands.remove(&task_id);
            return self
                .publish_debug(Some(task_id), "pending task runtime creation cancelled")
                .await;
        }
        self.publish_debug(Some(task_id), "task runtime is not live")
            .await
    }

    async fn stop_runtimes(&mut self) {
        let entries = self
            .task_runtime_registry
            .iter()
            .map(|(task_id, entry)| (task_id.clone(), entry.clone()))
            .collect::<Vec<_>>();
        for (task_id, entry) in entries {
            let _ = self.stop_runtime_entry(entry.clone()).await;
            self.remove_runtime_if_current(&task_id, &entry);
        }
    }

    async fn stop_runtime_entry(&self, entry: RuntimeRegistryEntry) -> Result<(), ()> {
        let _ = entry.control.stop().await;
        Ok(())
    }

    fn remove_runtime_if_current(&mut self, task_id: &TaskId, entry: &RuntimeRegistryEntry) {
        let is_current = self
            .task_runtime_registry
            .get(task_id)
            .is_some_and(|current| current.control.same_control(&entry.control));
        if is_current {
            self.task_runtime_registry.remove(task_id);
        }
    }

    async fn publish_domain_event(
        &mut self,
        request: DomainEventPublishRequest,
        // @behavior selvedge.model.router.r2.events.domain Supported domain events are published to events as raw debug output and persisted-message events are ignored.
    ) -> Result<(), RouterExitStatus> {
        let raw = match request.event {
            DomainEvent::TaskRuntimeReady => RawEvent::Debug(DebugRawEvent {
                task_id: Some(request.task_id),
                message_text: "task runtime ready".to_owned(),
            }),
            DomainEvent::ErrorNotice { message } => RawEvent::Debug(DebugRawEvent {
                task_id: Some(request.task_id),
                message_text: message,
            }),
            DomainEvent::UserMessageCommitted { .. }
            | DomainEvent::AssistantMessageCommitted { .. }
            | DomainEvent::ReasoningCommitted { .. }
            | DomainEvent::FunctionCallCommitted { .. }
            | DomainEvent::FunctionOutputCommitted { .. }
            | DomainEvent::TaskArchived => return Ok(()),
        };
        self.send_event(EventIngress::Raw(raw)).await
    }

    async fn publish_debug(
        &mut self,
        task_id: Option<TaskId>,
        message: impl Into<String>,
        // @behavior selvedge.model.router.r2.events.debug Debug publication sends a raw debug event with the optional task id and message text.
    ) -> Result<(), RouterExitStatus> {
        self.send_event(EventIngress::Raw(RawEvent::Debug(DebugRawEvent {
            task_id,
            message_text: message.into(),
        })))
        .await
    }

    async fn publish_factory_task_failure(
        &mut self,
        failure: FactoryTaskFailure,
        // @behavior selvedge.model.router.r2.factory.task_failure Factory task failures are published as task-scoped debug events.
    ) -> Result<(), RouterExitStatus> {
        self.publish_debug(Some(failure.task_id), failure.message)
            .await
    }

    async fn send_event(&mut self, event: EventIngress) -> Result<(), RouterExitStatus> {
        self.events_tx
            // @behavior selvedge.model.router.r2.events.send Router event publication sends control or raw event ingress to the configured events mailbox.
            .send(event)
            .await
            // @behavior selvedge.model.router.r2.events.send_closed A closed events mailbox converts event publication into EventsMailboxClosed router status.
            .map_err(|_| RouterExitStatus::EventsMailboxClosed)
    }

    fn next_effect_id(&mut self) -> FactoryEffectId {
        let effect_id = FactoryEffectId(format!("router-effect-{}", self.next_effect_seq));
        self.next_effect_seq += 1;
        effect_id
    }
}

fn tool_spawn_failed_result(request: ToolExecutionRequest) -> ToolExecutionResult {
    ToolExecutionResult {
        task_id: request.task_id,
        tool_execution_run_id: request.tool_execution_run_id,
        function_call_node_id: request.function_call_node_id,
        function_call_id: request.function_call_id,
        tool_name: request.tool_name,
        output_text: "tool execution spawn failed".to_owned(),
        is_error: true,
    }
}
